/// Filetype API Module
/// Handles filetype detection for JavaScript plugins
/// Exposes vim.filetype.match() API compatible with Neovim
/// Uses go-enry for GitHub Linguist-based language detection (697 languages)
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const helpers = @import("helpers.zig");
const enry = @import("../enry/enry.zig");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context struct for filetype detection
const FiletypeContext = struct {
    buffer: *Buffer,
    allocator: std.mem.Allocator,
};

/// Global context (allocated on heap, cleaned up in jsi_api.deinitJSI())
var global_filetype_ctx: ?*FiletypeContext = null;
var global_allocator: ?std.mem.Allocator = null;

/// Zig host function: vim_filetype_match(opts) -> string | null
/// Detects filetype from filename or buffer
///
/// JavaScript API:
///   vim.filetype.match({ filename: "foo.rs" })      // returns "Rust"
///   vim.filetype.match({ filename: "Makefile" })    // returns "Makefile"
///   vim.filetype.match({ buf: 0 })                  // returns filetype for current buffer
///
/// Uses go-enry for GitHub Linguist-based language detection (697 languages)
pub export fn vim_filetype_match(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Require at least one argument (the options object)
    if (count < 1) {
        return c.hermes_value_create_null(runtime);
    }

    const ctx: *FiletypeContext = @ptrCast(@alignCast(context.?));
    const opts = args[0] orelse return c.hermes_value_create_null(runtime);

    // Check if opts is an object
    if (!c.hermes_value_is_object(opts)) {
        return c.hermes_value_create_null(runtime);
    }

    // Try to get 'filename' property
    const filename_prop = c.hermes_value_get_property(runtime, opts, "filename");
    if (filename_prop != null and c.hermes_value_is_string(filename_prop)) {
        // Extract filename string
        var filename_buf: [1024]u8 = undefined;
        const filename = helpers.extractStringArg(runtime.?, filename_prop, &filename_buf) catch {
            c.hermes_value_destroy(filename_prop);
            return c.hermes_value_create_null(runtime);
        };

        // Smart content detection: if filename matches current buffer's filepath,
        // use buffer content for better accuracy (helps disambiguate .rs, .h, etc.)
        var content_owned: ?[]u8 = null;
        defer if (content_owned) |content| ctx.allocator.free(content);

        const content = blk: {
            if (ctx.buffer.filepath) |buf_path| {
                // Check if filename matches buffer path (basename or full path)
                const buf_basename = std.fs.path.basename(buf_path);
                const filename_basename = std.fs.path.basename(filename);

                if (std.mem.eql(u8, filename, buf_path) or
                    std.mem.eql(u8, filename_basename, buf_basename)) {
                    // Filename matches loaded buffer - use content for accuracy
                    if (ctx.buffer.content.len() > 0) {
                        content_owned = ctx.buffer.content.toString() catch break :blk null;
                        break :blk content_owned.?;
                    } else {
                        break :blk null;
                    }
                }
            }
            // No match - filename-only detection
            break :blk null;
        };

        // Detect language from filename using go-enry (with content if available)
        const language = enry.detectLanguage(ctx.allocator, filename, content) catch {
            c.hermes_value_destroy(filename_prop);
            return c.hermes_value_create_null(runtime);
        };
        c.hermes_value_destroy(filename_prop);

        if (language) |lang| {
            // Return language string (enry allocates, we need to copy for Hermes then free enry's)
            const result = c.hermes_value_create_string(runtime, lang.ptr, lang.len);
            ctx.allocator.free(lang); // Free enry's allocation
            return result;
        } else {
            // Unknown language
            return c.hermes_value_create_null(runtime);
        }
    }

    // Try to get 'buf' property (buffer number)
    const buf_prop = c.hermes_value_get_property(runtime, opts, "buf");
    if (buf_prop != null and c.hermes_value_is_number(buf_prop)) {
        // For now, only support buf=0 (current buffer)
        // In the future, this could support multiple buffers
        const buf_num = c.hermes_value_get_number(buf_prop);
        c.hermes_value_destroy(buf_prop);

        if (buf_num != 0) {
            // Only current buffer supported for now
            return c.hermes_value_create_null(runtime);
        }

        // Get buffer path
        const path = ctx.buffer.filepath orelse {
            // No file path set
            return c.hermes_value_create_null(runtime);
        };

        // Get buffer content for language detection (helps with ambiguous extensions)
        var content_owned: ?[]u8 = null;
        defer if (content_owned) |content| ctx.allocator.free(content);

        const content = if (ctx.buffer.content.len() > 0) blk: {
            content_owned = ctx.buffer.content.toString() catch break :blk null;
            break :blk content_owned.?;
        } else null;

        // Detect language using go-enry (filename + content for best accuracy)
        const language = enry.detectLanguage(ctx.allocator, path, content) catch {
            return c.hermes_value_create_null(runtime);
        };

        if (language) |lang| {
            // Return language string (enry allocates, we need to copy for Hermes then free enry's)
            const result = c.hermes_value_create_string(runtime, lang.ptr, lang.len);
            ctx.allocator.free(lang); // Free enry's allocation
            return result;
        } else {
            // Unknown language
            return c.hermes_value_create_null(runtime);
        }
    }

    // No valid 'filename' or 'buf' property found
    return c.hermes_value_create_null(runtime);
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.filetype HostObject getter - routes property access to methods
pub export fn filetypeHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Use StaticStringMap for O(1) property dispatch
    const PropertyMap = std.StaticStringMap(*const fn (
        ?*c.OVHermesRuntime,
        ?*anyopaque,
        [*c]?*c.OVHermesValue,
        usize,
    ) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "match", vim_filetype_match },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.filetype HostObject enumerator - returns array of method names
pub export fn filetypeHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "match",
    };

    const arr = c.hermes_array_create(rt, method_names.len) orelse return null;

    for (method_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register filetype API as HostObject (zero-copy, 3-5x faster)
/// JavaScript usage: vim.filetype.match({ filename: "foo.rs" })
/// Works with both *Editor and *EditorContext (both have buffer fields)
/// Note: Allocator must be passed in from jsi_api.initJSI()
pub fn register(runtime: *c.OVHermesRuntime, editor_or_context: anytype, allocator: std.mem.Allocator) void {
    // Allocate FiletypeContext on heap (cleaned up in jsi_api.deinitJSI())
    const ctx = allocator.create(FiletypeContext) catch @panic("Failed to allocate FiletypeContext");
    ctx.* = FiletypeContext{
        .buffer = &editor_or_context.buffer,
        .allocator = allocator,
    };

    // Store in globals for cleanup
    global_filetype_ctx = ctx;
    global_allocator = allocator;

    c.hermes_register_host_object(
        runtime,
        "vimFiletype",
        filetypeHostObjectGet,
        null, // No setter (read-only methods)
        filetypeHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

/// Legacy registration (backwards compatibility)
/// TODO: Remove after all examples/tests updated
pub fn registerLegacy(runtime: *c.OVHermesRuntime, editor_or_context: anytype, allocator: std.mem.Allocator) void {
    // Allocate FiletypeContext on heap (cleaned up in jsi_api.deinitJSI())
    const ctx = allocator.create(FiletypeContext) catch @panic("Failed to allocate FiletypeContext");
    ctx.* = FiletypeContext{
        .buffer = &editor_or_context.buffer,
        .allocator = allocator,
    };

    // Store in globals for cleanup
    global_filetype_ctx = ctx;
    global_allocator = allocator;

    c.hermes_register_host_function(
        runtime,
        "vim_filetype_match",
        vim_filetype_match,
        @ptrCast(ctx),
    );
}

/// Clean up filetype API resources
pub fn deinit() void {
    if (global_filetype_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_filetype_ctx = null;
    }
    global_allocator = null;
}
