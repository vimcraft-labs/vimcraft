/// Search API - vim.fn.setReg('/', ...), vim.cmd.nohlsearch(), etc.
///
/// Provides Neovim-compatible search functionality:
/// - vim.fn.getReg('/') - Get current search pattern
/// - vim.fn.setReg('/', 'pattern') - Set search pattern
/// - vim.cmd.nohlsearch() - Clear search highlighting
///
const std = @import("std");
const c = @import("c_api.zig").c;
const Editor = @import("../../editor/editor.zig").Editor;

/// Global editor context (set by jsi_api.zig)
var global_editor: ?*Editor = null;

pub fn setEditorContext(editor: *Editor) void {
    global_editor = editor;
}

/// Get current search pattern
/// JavaScript: vimSearchGetPattern() -> string
pub export fn vimSearchGetPattern(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const editor = global_editor orelse {
        return c.hermes_value_create_string(runtime, "", 0);
    };

    const pattern = editor.getSearchPattern();
    return c.hermes_value_create_string(runtime, pattern.ptr, pattern.len);
}

/// Set search pattern and execute search
/// JavaScript: vimSearchSetPattern(pattern: string)
pub export fn vimSearchSetPattern(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "vimSearchSetPattern requires 1 argument");
        return null;
    }

    const editor = global_editor orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Get pattern string
    const pattern_arg = args[0] orelse {
        c.hermes_throw_error(runtime, "vimSearchSetPattern: pattern is null");
        return null;
    };

    var pattern_len: usize = 0;
    const pattern_ptr = c.hermes_value_get_string(runtime, pattern_arg, &pattern_len);
    if (pattern_ptr == null or pattern_len == 0) {
        c.hermes_throw_error(runtime, "vimSearchSetPattern: pattern must be a non-empty string");
        return null;
    }

    const pattern = pattern_ptr[0..pattern_len];

    // Set pattern and execute search
    editor.setSearchPattern(pattern) catch |err| {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "setSearchPattern failed: {}", .{err}) catch "setSearchPattern failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    };

    // Trigger re-render
    editor.js_state_dirty = true;

    return c.hermes_value_create_undefined(runtime);
}

/// Clear search highlighting (keeps pattern for n/N)
/// JavaScript: vimSearchClearHighlight()
pub export fn vimSearchClearHighlight(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const editor = global_editor orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    editor.clearSearchHighlight();

    // Trigger re-render
    editor.js_state_dirty = true;

    return c.hermes_value_create_undefined(runtime);
}

/// Get word under cursor
/// JavaScript: vimGetWordUnderCursor() -> string
pub export fn vimGetWordUnderCursor(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const editor = global_editor orelse {
        return c.hermes_value_create_string(runtime, "", 0);
    };

    const word = editor.getWordUnderCursor() orelse {
        return c.hermes_value_create_string(runtime, "", 0);
    };
    defer editor.allocator.free(word);

    return c.hermes_value_create_string(runtime, word.ptr, word.len);
}

/// Clear search pattern completely
/// JavaScript: vimSearchClearPattern()
pub export fn vimSearchClearPattern(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const editor = global_editor orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    editor.clearSearchPattern();

    // Trigger re-render
    editor.js_state_dirty = true;

    return c.hermes_value_create_undefined(runtime);
}

/// Register all search API functions
pub fn registerSearchApi(runtime: ?*c.OVHermesRuntime) void {
    // Get global object
    const global = c.hermes_get_global_object(runtime);
    if (global == null) return;
    defer c.hermes_object_destroy(global);

    // vimSearchGetPattern
    const get_pattern_fn = c.hermes_create_function(
        runtime,
        "vimSearchGetPattern",
        vimSearchGetPattern,
        null,
    );
    if (get_pattern_fn) |f| {
        c.hermes_object_set_property(runtime, global, "vimSearchGetPattern", f);
        c.hermes_value_destroy(f);
    }

    // vimSearchSetPattern
    const set_pattern_fn = c.hermes_create_function(
        runtime,
        "vimSearchSetPattern",
        vimSearchSetPattern,
        null,
    );
    if (set_pattern_fn) |f| {
        c.hermes_object_set_property(runtime, global, "vimSearchSetPattern", f);
        c.hermes_value_destroy(f);
    }

    // vimSearchClearHighlight
    const clear_hl_fn = c.hermes_create_function(
        runtime,
        "vimSearchClearHighlight",
        vimSearchClearHighlight,
        null,
    );
    if (clear_hl_fn) |f| {
        c.hermes_object_set_property(runtime, global, "vimSearchClearHighlight", f);
        c.hermes_value_destroy(f);
    }

    // vimSearchClearPattern
    const clear_pattern_fn = c.hermes_create_function(
        runtime,
        "vimSearchClearPattern",
        vimSearchClearPattern,
        null,
    );
    if (clear_pattern_fn) |f| {
        c.hermes_object_set_property(runtime, global, "vimSearchClearPattern", f);
        c.hermes_value_destroy(f);
    }

    // vimGetWordUnderCursor
    const get_word_fn = c.hermes_create_function(
        runtime,
        "vimGetWordUnderCursor",
        vimGetWordUnderCursor,
        null,
    );
    if (get_word_fn) |f| {
        c.hermes_object_set_property(runtime, global, "vimGetWordUnderCursor", f);
        c.hermes_value_destroy(f);
    }
}
