/// Filetype API Module
/// Handles filetype detection for JavaScript plugins
/// Exposes vim.filetype.match() API compatible with Neovim
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const helpers = @import("helpers.zig");
const Loader = @import("../../editor/treesitter/loader.zig").Loader;
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context struct that works with both Editor and EditorContext
/// Both types have ts_loader and buffer fields
const FiletypeContext = struct {
    ts_loader: *Loader,
    buffer: *Buffer,
};

/// Global context (allocated on heap, cleaned up in jsi_api.deinitJSI())
var global_filetype_ctx: ?*FiletypeContext = null;
var global_allocator: ?std.mem.Allocator = null;

/// Zig host function: vim_filetype_match(opts) -> string | null
/// Detects filetype from filename or buffer
///
/// JavaScript API:
///   vim.filetype.match({ filename: "foo.rs" })      // returns "rust"
///   vim.filetype.match({ filename: "Makefile" })    // returns "make"
///   vim.filetype.match({ buf: 0 })                  // returns filetype for current buffer
///
/// Uses Neovim's comprehensive filetype database (1,437+ compile-time mappings)
export fn vim_filetype_match(
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

        // Detect filetype from filename
        const filetype = ctx.ts_loader.detectFiletype(filename, null);
        c.hermes_value_destroy(filename_prop);

        if (filetype) |ft| {
            // Return filetype string
            return c.hermes_value_create_string(runtime, ft.ptr, ft.len);
        } else {
            // Unknown filetype
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

        // Get first line of buffer for shebang detection
        var first_line: ?[]const u8 = null;
        if (ctx.buffer.content.items.len > 0) {
            // Find end of first line
            const content = ctx.buffer.content.items;
            var end: usize = 0;
            while (end < content.len and content[end] != '\n') : (end += 1) {}
            first_line = content[0..end];
        }

        // Detect filetype
        const filetype = ctx.ts_loader.detectFiletype(path, first_line);

        if (filetype) |ft| {
            // Return filetype string
            return c.hermes_value_create_string(runtime, ft.ptr, ft.len);
        } else {
            // Unknown filetype
            return c.hermes_value_create_null(runtime);
        }
    }

    // No valid 'filename' or 'buf' property found
    return c.hermes_value_create_null(runtime);
}

/// Register filetype API functions with runtime
/// Works with both *Editor and *EditorContext (both have ts_loader and buffer fields)
/// Note: Allocator must be passed in from jsi_api.initJSI()
pub fn register(runtime: *c.OVHermesRuntime, editor_or_context: anytype, allocator: std.mem.Allocator) void {
    // Allocate FiletypeContext on heap (cleaned up in jsi_api.deinitJSI())
    const ctx = allocator.create(FiletypeContext) catch @panic("Failed to allocate FiletypeContext");
    ctx.* = FiletypeContext{
        .ts_loader = &editor_or_context.ts_loader,
        .buffer = &editor_or_context.buffer,
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
