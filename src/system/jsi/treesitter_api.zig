/// Tree-sitter API Module
/// Exposes vim.treesitter.* API to JavaScript plugins
/// Neovim-compatible API with camelCase naming (as per project convention)
///
/// JavaScript API:
///   vim.treesitter.getParser(bufnr?, lang?)  - Get or create parser for buffer
///   vim.treesitter.hasParser(lang)           - Check if language is supported
///   vim.treesitter.getLanguageTree(bufnr?)   - Get LanguageTree with injection support
///   vim.treesitter.languageForRange(range)   - Get language at a position
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;
const LanguageTree = @import("../../editor/treesitter/language_tree.zig").LanguageTree;
const languages = @import("../../editor/treesitter/languages.zig");
const helpers = @import("helpers.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context struct for treesitter API
/// Stores Editor pointer to access current buffer dynamically
pub const TreesitterContext = struct {
    editor: *Editor,
    allocator: std.mem.Allocator,

    /// Get current buffer (may change between calls)
    inline fn getCurrentBuffer(self: *const TreesitterContext) ?*Buffer {
        return self.editor.getCurrentBuffer();
    }

    /// Mark editor state as dirty (triggers re-render in main loop)
    inline fn markDirty(self: *const TreesitterContext) void {
        self.editor.js_state_dirty = true;
    }
};

/// Global context (allocated on heap, cleaned up in deinit())
var global_treesitter_ctx: ?*TreesitterContext = null;
var global_allocator: ?std.mem.Allocator = null;

// ============================================================================
// Language Name Normalization
// ============================================================================

/// Normalize language name from go-enry to tree-sitter
/// go-enry returns capitalized names ("JavaScript"), tree-sitter needs lowercase ("javascript")
fn normalizeLangName(lang: []const u8) []const u8 {
    const mappings = std.StaticStringMap([]const u8).initComptime(.{
        .{ "JavaScript", "javascript" },
        .{ "Python", "python" },
        .{ "Rust", "rust" },
        .{ "Zig", "zig" },
        .{ "Go", "go" },
        .{ "C", "c" },
        .{ "C++", "cpp" },
        .{ "TypeScript", "typescript" },
        .{ "Markdown", "markdown" },
        .{ "JSON", "json" },
        .{ "YAML", "yaml" },
        .{ "TOML", "toml" },
        .{ "HTML", "html" },
        .{ "CSS", "css" },
        .{ "Bash", "bash" },
        .{ "Shell", "bash" },
    });
    return mappings.get(lang) orelse lang;
}

// ============================================================================
// API Functions
// ============================================================================

/// vim.treesitter.hasParser(lang) -> boolean
/// Check if a tree-sitter parser is available for the given language
///
/// JavaScript usage:
///   vim.treesitter.hasParser("javascript")  // true
///   vim.treesitter.hasParser("unknown")     // false
pub export fn treesitter_hasParser(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (count < 1) {
        return c.hermes_value_create_boolean(rt, false);
    }

    const lang_val = args[0] orelse return c.hermes_value_create_boolean(rt, false);
    if (!c.hermes_value_is_string(lang_val)) {
        return c.hermes_value_create_boolean(rt, false);
    }

    var lang_buf: [256]u8 = undefined;
    const lang = helpers.extractStringArg(rt, lang_val, &lang_buf) catch {
        return c.hermes_value_create_boolean(rt, false);
    };

    // Check if language is supported
    const has_parser = languages.getLanguage(lang) != null;
    return c.hermes_value_create_boolean(rt, has_parser);
}

/// vim.treesitter.getLanguageTree(bufnr?, lang?) -> boolean
/// Initialize LanguageTree for the current buffer (supports injections)
/// Returns true on success, false on failure
///
/// JavaScript usage:
///   vim.treesitter.getLanguageTree(0, "markdown")  // Initialize markdown with injections
///   vim.treesitter.getLanguageTree()               // Use current buffer's filetype
pub export fn treesitter_getLanguageTree(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    // Get current buffer dynamically
    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_boolean(rt, false);
    };

    // Get language name from args or buffer filetype
    var lang_buf: [256]u8 = undefined;
    const raw_lang: []const u8 = blk: {
        if (count >= 2) {
            // Second argument is language name
            const lang_val = args[1] orelse break :blk buffer.filetype orelse "text";
            if (c.hermes_value_is_string(lang_val)) {
                break :blk helpers.extractStringArg(rt, lang_val, &lang_buf) catch
                    (buffer.filetype orelse "text");
            }
        }
        // Use buffer's filetype
        break :blk buffer.filetype orelse "text";
    };

    // Normalize language name (go-enry "Markdown" → tree-sitter "markdown")
    const lang_name = normalizeLangName(raw_lang);

    // Initialize LanguageTree for the buffer
    buffer.initLanguageTree(lang_name) catch {
        return c.hermes_value_create_boolean(rt, false);
    };

    ctx.markDirty();
    return c.hermes_value_create_boolean(rt, buffer.hasLanguageTree());
}

/// vim.treesitter.hasLanguageTree(bufnr?) -> boolean
/// Check if buffer has a LanguageTree (injection support enabled)
///
/// JavaScript usage:
///   vim.treesitter.hasLanguageTree()  // Check current buffer
pub export fn treesitter_hasLanguageTree(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_boolean(rt, false);
    };
    return c.hermes_value_create_boolean(rt, buffer.hasLanguageTree());
}

/// vim.treesitter.getLanguages() -> string[]
/// Returns list of supported tree-sitter languages
///
/// JavaScript usage:
///   const langs = vim.treesitter.getLanguages()
///   // ["c", "zig", "javascript", "typescript", "markdown", ...]
pub export fn treesitter_getLanguages(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;
    const rt = runtime orelse return null;

    const lang_list = languages.listLanguages();
    const arr = c.hermes_array_create(rt, lang_list.len) orelse return null;

    for (lang_list, 0..) |lang, i| {
        const str = c.hermes_value_create_string(rt, lang.ptr, lang.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

/// vim.treesitter.languageForRange(startByte, endByte) -> string | null
/// Get the language name for a byte range (useful for injected languages)
///
/// JavaScript usage:
///   vim.treesitter.languageForRange(100, 200)  // "javascript" if in a JS code block
pub export fn treesitter_languageForRange(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    if (count < 2) {
        return c.hermes_value_create_null(rt);
    }

    const start_val = args[0] orelse return c.hermes_value_create_null(rt);
    const end_val = args[1] orelse return c.hermes_value_create_null(rt);

    if (!c.hermes_value_is_number(start_val) or !c.hermes_value_is_number(end_val)) {
        return c.hermes_value_create_null(rt);
    }

    const start_f = c.hermes_value_get_number(start_val);
    const end_f = c.hermes_value_get_number(end_val);

    if (std.math.isNan(start_f) or std.math.isNan(end_f) or start_f < 0 or end_f < 0) {
        return c.hermes_value_create_null(rt);
    }

    const start_byte: u32 = @intFromFloat(start_f);
    const end_byte: u32 = @intFromFloat(end_f);

    // Get current buffer dynamically
    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_null(rt);
    };

    // Get LanguageTree for the buffer
    const lang_tree = buffer.getLanguageTree() orelse {
        // Fallback to buffer filetype
        const ft = buffer.filetype orelse return c.hermes_value_create_null(rt);
        return c.hermes_value_create_string(rt, ft.ptr, ft.len);
    };

    // Find the most specific language for this range
    const tree_for_range = lang_tree.languageForRange(start_byte, end_byte);
    const lang = tree_for_range.language();

    return c.hermes_value_create_string(rt, lang.ptr, lang.len);
}

/// vim.treesitter.updateTree() -> boolean
/// Update the LanguageTree after buffer modifications
/// Returns true on success
///
/// JavaScript usage:
///   vim.treesitter.updateTree()  // Re-parse after edits
pub export fn treesitter_updateTree(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_boolean(rt, false);
    };

    if (!buffer.hasLanguageTree()) {
        return c.hermes_value_create_boolean(rt, false);
    }

    buffer.updateLanguageTree();
    ctx.markDirty();
    return c.hermes_value_create_boolean(rt, true);
}

/// vim.treesitter.getInjectedLanguages() -> string[]
/// Returns list of injected languages in the current buffer's LanguageTree
///
/// JavaScript usage:
///   const injected = vim.treesitter.getInjectedLanguages()
///   // ["javascript", "css"] for a markdown file with code blocks
pub export fn treesitter_getInjectedLanguages(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        // No current buffer - return empty array
        return c.hermes_array_create(rt, 0);
    };

    const lang_tree = buffer.getLanguageTree() orelse {
        // No LanguageTree - return empty array
        return c.hermes_array_create(rt, 0);
    };

    // Count children
    var child_count: usize = 0;
    var count_iter = lang_tree.children.valueIterator();
    while (count_iter.next()) |_| {
        child_count += 1;
    }

    const arr = c.hermes_array_create(rt, child_count) orelse return null;

    var iter = lang_tree.children.keyIterator();
    var i: usize = 0;
    while (iter.next()) |key| {
        const str = c.hermes_value_create_string(rt, key.*.ptr, key.*.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
        i += 1;
    }

    return arr;
}

/// Get debug info about the LanguageTree
/// Returns: { lang: string, treeCount: number, hasHighlightQuery: boolean, hasInjectionQuery: boolean }
pub export fn treesitter_getTreeInfo(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_string(rt, "no buffer", 9);
    };

    const lang_tree = buffer.getLanguageTree() orelse {
        return c.hermes_value_create_string(rt, "no tree", 7);
    };

    // Count trees
    var tree_count: usize = 0;
    var tree_iter = lang_tree.trees.iterator();
    while (tree_iter.next()) |_| {
        tree_count += 1;
    }

    // Build debug string
    var buf: [512]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "lang={s}, trees={d}, hasHLQuery={}, hasInjQuery={}, source_len={d}", .{
        lang_tree.lang,
        tree_count,
        lang_tree.highlightQuery != null,
        lang_tree.injectionQuery != null,
        lang_tree.source.len,
    }) catch return null;

    return c.hermes_value_create_string(rt, buf[0..len.len].ptr, len.len);
}

/// Force loading highlight query and return result
pub export fn treesitter_loadHighlightQuery(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_string(rt, "no buffer", 9);
    };

    const lang_tree = buffer.getLanguageTree() orelse {
        return c.hermes_value_create_string(rt, "no tree", 7);
    };

    // Try to load highlight query
    const Query = @import("../../editor/treesitter/query.zig").Query;

    if (lang_tree.highlightQuery == null) {
        lang_tree.highlightQuery = Query.loadForLanguage(
            lang_tree.allocator,
            lang_tree.lang,
            lang_tree.tsLanguage,
        ) catch |err| {
            var buf: [256]u8 = undefined;
            const len = std.fmt.bufPrint(&buf, "error: {}", .{err}) catch return null;
            return c.hermes_value_create_string(rt, buf[0..len.len].ptr, len.len);
        };
    }

    if (lang_tree.highlightQuery != null) {
        return c.hermes_value_create_string(rt, "success", 7);
    } else {
        return c.hermes_value_create_string(rt, "failed", 6);
    }
}

/// Debug: Get highlight captures and their resolved styles
pub export fn treesitter_getHighlightCaptures(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_undefined(rt);
    };

    const lang_tree = buffer.getLanguageTree() orelse {
        return c.hermes_value_create_undefined(rt);
    };

    // Get highlight query
    const query = lang_tree.highlightQuery orelse {
        return c.hermes_value_create_undefined(rt);
    };

    // Get capture count and create array
    const capture_count = query.getCaptureCount();
    const arr = c.hermes_array_create(rt, capture_count) orelse return null;

    // Get capture names and add to array
    for (0..capture_count) |i| {
        const cap_name = query.getCaptureName(@intCast(i));
        const str = c.hermes_value_create_string(rt, cap_name.ptr, cap_name.len);
        if (str) |s| {
            c.hermes_array_set(rt, arr, @intCast(i), s);
            c.hermes_value_destroy(s);
        }
    }

    return arr;
}

/// Debug: Get highlights for current buffer with style info
pub export fn treesitter_debugHighlights(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;
    const rt = runtime orelse return null;
    const ctx: *TreesitterContext = @ptrCast(@alignCast(context orelse return null));

    const buffer = ctx.getCurrentBuffer() orelse {
        return c.hermes_value_create_undefined(rt);
    };

    const lang_tree = buffer.getLanguageTree() orelse {
        return c.hermes_value_create_undefined(rt);
    };

    const editor = ctx.editor;

    // Create LanguageTreeHighlighter
    const LanguageTreeHighlighter = @import("../../editor/treesitter/syntax_highlighter.zig").LanguageTreeHighlighter;
    const Range = @import("../../editor/treesitter/highlight.zig").Range;

    var highlighter = LanguageTreeHighlighter.init(
        ctx.allocator,
        lang_tree,
        &editor.highlight_registry,
    );

    // Get highlights for first 200 bytes
    var iter = highlighter.highlights(Range{ .start_byte = 0, .end_byte = 200 }) catch {
        return c.hermes_value_create_undefined(rt);
    };
    defer iter.deinit();

    // Collect results
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    var highlight_count: usize = 0;
    while (iter.next() catch null) |styled| {
        highlight_count += 1;

        // Format: "start-end: fg=color"
        if (styled.style.fg) |fg_color| {
            switch (fg_color) {
                .rgb => |rgb| {
                    const len = std.fmt.bufPrint(buf[pos..], "[{}-{}:#{x:0>2}{x:0>2}{x:0>2}]", .{
                        styled.range.start_byte,
                        styled.range.end_byte,
                        rgb.r,
                        rgb.g,
                        rgb.b,
                    }) catch break;
                    pos += len.len;
                },
                .indexed => |idx| {
                    const len = std.fmt.bufPrint(buf[pos..], "[{}-{}:idx{}]", .{
                        styled.range.start_byte,
                        styled.range.end_byte,
                        idx,
                    }) catch break;
                    pos += len.len;
                },
            }
        }
    }

    // Add summary
    const summary = std.fmt.bufPrint(buf[pos..], " total={}", .{highlight_count}) catch return null;
    pos += summary.len;

    return c.hermes_value_create_string(rt, buf[0..pos].ptr, pos);
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.treesitter HostObject getter - routes property access to methods
pub export fn treesitterHostObjectGet(
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
        .{ "hasParser", treesitter_hasParser },
        .{ "getLanguageTree", treesitter_getLanguageTree },
        .{ "hasLanguageTree", treesitter_hasLanguageTree },
        .{ "getLanguages", treesitter_getLanguages },
        .{ "languageForRange", treesitter_languageForRange },
        .{ "updateTree", treesitter_updateTree },
        .{ "getInjectedLanguages", treesitter_getInjectedLanguages },
        .{ "getTreeInfo", treesitter_getTreeInfo },
        .{ "loadHighlightQuery", treesitter_loadHighlightQuery },
        .{ "getHighlightCaptures", treesitter_getHighlightCaptures },
        .{ "debugHighlights", treesitter_debugHighlights },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.treesitter HostObject enumerator - returns array of method names
pub export fn treesitterHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "hasParser",
        "getLanguageTree",
        "hasLanguageTree",
        "getLanguages",
        "languageForRange",
        "updateTree",
        "getInjectedLanguages",
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

/// Register treesitter API as HostObject (zero-copy, 3-5x faster)
/// JavaScript usage: vim.treesitter.hasParser("javascript")
pub fn register(
    runtime: *c.OVHermesRuntime,
    editor: *Editor,
    allocator: std.mem.Allocator,
) void {
    // Allocate TreesitterContext on heap (cleaned up in deinit())
    const ctx = allocator.create(TreesitterContext) catch @panic("Failed to allocate TreesitterContext");
    ctx.* = TreesitterContext{
        .editor = editor,
        .allocator = allocator,
    };

    // Store in globals for cleanup
    global_treesitter_ctx = ctx;
    global_allocator = allocator;

    c.hermes_register_host_object(
        runtime,
        "vimTreesitter",
        treesitterHostObjectGet,
        null, // No setter (read-only methods)
        treesitterHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

/// Clean up treesitter API resources
pub fn deinit() void {
    if (global_treesitter_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_treesitter_ctx = null;
    }
    global_allocator = null;
}
