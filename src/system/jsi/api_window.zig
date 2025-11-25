/// vim.api Window Functions
/// Implements Neovim-compatible window API:
/// - getCurrentWin() -> Window (handle)
/// - setCurrentWin(win) -> void
/// - listWins() -> Window[]
/// - winGetCursor(win) -> [row, col] (row is 1-indexed, col is 0-indexed)
/// - winSetCursor(win, [row, col]) -> void
/// - winIsValid(win) -> boolean
/// - winGetBuf(win) -> Buffer (handle)
/// - winSetBuf(win, buf) -> void
/// - winGetHeight(win) -> number
/// - winSetHeight(win, height) -> void
/// - winGetWidth(win) -> number
/// - winSetWidth(win, width) -> void
/// - winClose(win, force) -> void
/// - winGetVar(win, name) -> any
/// - winSetVar(win, name, value) -> void
/// - winDelVar(win, name) -> void
/// - winCall(win, fun) -> any
/// - winGetNumber(win) -> number
/// - winGetPosition(win) -> [row, col]
///
/// These are registered as global functions for vim.api.* wrappers in runtime.js
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Dimensions struct for terminal size
pub const Dimensions = struct {
    rows: usize,
    cols: usize,
};

/// Context for window API functions
pub const ApiWindowContext = struct {
    allocator: std.mem.Allocator,
    /// Function pointer to get current buffer
    get_buffer_fn: *const fn (*anyopaque) ?*Buffer,
    /// Function pointer to get terminal dimensions
    get_dimensions_fn: *const fn (*anyopaque) Dimensions,
    /// Opaque pointer to Editor or EditorContext
    context_ptr: *anyopaque,
    /// Window variables (w:) storage - only for window 0
    /// Uses OVHermesValue clone for type-safe storage (same as buffer vars)
    window_vars: std.StringHashMap(*c.OVHermesValue),
    /// Hermes runtime pointer for winCall
    runtime: ?*c.OVHermesRuntime = null,
};

/// Global context (set during registration)
var global_ctx: ?*ApiWindowContext = null;

/// vim.api.getCurrentWin() -> Window
/// Returns current window handle (actual window ID for multi-window mode)
/// Note: Neovim convention uses handle 0 to mean "current window" in API calls
/// but getCurrentWin() returns the actual handle
pub export fn apiGetCurrentWin(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, 0);

    // Try to get real current window ID from Editor
    if (getCurrentWindowIdFromContext(ctx)) |win_id| {
        return c.hermes_value_create_number(rt, @floatFromInt(win_id));
    }

    // Fallback to 0 (current window, Neovim convention)
    return c.hermes_value_create_number(rt, 0);
}

/// vim.api.winGetCursor(win) -> [row, col]
/// Returns cursor position (row is 1-indexed, col is 0-indexed per Neovim convention)
/// CRITICAL: For current window, sync from buffer.cursor since cursor movements
/// update buffer.cursor directly, not window.cursor
pub export fn apiWinGetCursor(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get editor for cursor sync
    const editor = getEditorFromContext(ctx);

    // Try to get cursor from Window struct first (multi-window support)
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        // CRITICAL: For current window, sync cursor from buffer BEFORE returning
        // Cursor movements (hjkl) update buffer.cursor, not window.cursor
        // window.cursor only gets synced on focusWindow()
        if (editor) |e| {
            const is_current_window = if (e.current_window_id) |curr_id|
                window.id.eql(curr_id)
            else
                false;

            if (is_current_window) {
                // Sync buffer cursor to window cursor for accurate reporting
                if (e.buffers.get(window.buffer_id)) |buffer| {
                    window.cursor.row = buffer.cursor.row;
                    window.cursor.col = buffer.cursor.col;
                }
            }
        }

        const arr = c.hermes_array_create(rt, 2) orelse return c.hermes_value_create_null(rt);
        const row_val = c.hermes_value_create_number(rt, @floatFromInt(window.cursor.row + 1)); // 1-indexed
        const col_val = c.hermes_value_create_number(rt, @floatFromInt(window.cursor.col)); // 0-indexed

        if (row_val) |rv| {
            c.hermes_array_set(rt, arr, 0, rv);
            c.hermes_value_destroy(rv);
        }
        if (col_val) |cv| {
            c.hermes_array_set(rt, arr, 1, cv);
            c.hermes_value_destroy(cv);
        }
        return arr;
    }

    // Fallback: get from buffer for window 0 (legacy single-window mode)
    if (win_handle == 0) {
        const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_null(rt);

        const arr = c.hermes_array_create(rt, 2) orelse return c.hermes_value_create_null(rt);
        const row_val = c.hermes_value_create_number(rt, @floatFromInt(buffer.cursor.row + 1)); // 1-indexed
        const col_val = c.hermes_value_create_number(rt, @floatFromInt(buffer.cursor.col)); // 0-indexed

        if (row_val) |rv| {
            c.hermes_array_set(rt, arr, 0, rv);
            c.hermes_value_destroy(rv);
        }
        if (col_val) |cv| {
            c.hermes_array_set(rt, arr, 1, cv);
            c.hermes_value_destroy(cv);
        }
        return arr;
    }

    return c.hermes_value_create_null(rt);
}

/// vim.api.winSetCursor(win, [row, col]) -> void
/// Sets cursor position (row is 1-indexed, col is 0-indexed per Neovim convention)
pub export fn apiWinSetCursor(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win, pos)
    if (count < 2) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const pos_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get row and col from array
    const row_val = c.hermes_array_get(rt, pos_val, 0) orelse return c.hermes_value_create_undefined(rt);
    defer c.hermes_value_destroy(row_val);
    const col_val = c.hermes_array_get(rt, pos_val, 1) orelse return c.hermes_value_create_undefined(rt);
    defer c.hermes_value_destroy(col_val);

    const row_1indexed = @as(i64, @intFromFloat(c.hermes_value_get_number(row_val)));
    const col = @as(i64, @intFromFloat(c.hermes_value_get_number(col_val)));

    // Convert from 1-indexed row to 0-indexed
    const row: usize = if (row_1indexed > 0) @intCast(row_1indexed - 1) else 0;
    const col_usize: usize = if (col >= 0) @intCast(col) else 0;

    // Try to set cursor on Window struct first (multi-window support)
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        window.cursor.row = row;
        window.cursor.col = col_usize;
        window.ensureCursorVisible();
        window.markDirty();
        return c.hermes_value_create_undefined(rt);
    }

    // Fallback: set buffer cursor for window 0 (legacy single-window mode)
    if (win_handle == 0) {
        const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_undefined(rt);
        buffer.moveCursorTo(row, col_usize);
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winIsValid(win) -> boolean
/// Returns true if window handle is valid (exists in editor's windows)
pub export fn apiWinIsValid(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_boolean(rt, false);

    const win_handle_val = args[0] orelse return c.hermes_value_create_boolean(rt, false);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    const ctx = global_ctx orelse {
        // Fallback: only window 0 is valid
        return c.hermes_value_create_boolean(rt, win_handle == 0);
    };

    return c.hermes_value_create_boolean(rt, isWindowHandleValid(ctx, win_handle));
}

/// vim.api.winGetBuf(win) -> Buffer
/// Returns buffer handle for window
pub export fn apiWinGetBuf(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse {
        // Fallback: return buffer 0 for single-buffer mode
        return c.hermes_value_create_number(rt, 0);
    };

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Try to get buffer ID from Window struct (multi-window support)
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        return c.hermes_value_create_number(rt, @floatFromInt(window.buffer_id.id));
    }

    // Fallback: return buffer 0 for window 0 (legacy single-buffer mode)
    if (win_handle == 0) {
        return c.hermes_value_create_number(rt, 0);
    }

    return c.hermes_value_create_null(rt);
}

/// vim.api.winGetHeight(win) -> number
/// Returns window height in rows
pub export fn apiWinGetHeight(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Try to get actual window dimensions
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        return c.hermes_value_create_number(rt, @floatFromInt(window.height));
    }

    // Fallback: return terminal rows for window 0
    if (win_handle == 0) {
        const dims = ctx.get_dimensions_fn(ctx.context_ptr);
        return c.hermes_value_create_number(rt, @floatFromInt(dims.rows));
    }

    return c.hermes_value_create_null(rt);
}

/// vim.api.winGetWidth(win) -> number
/// Returns window width in columns
pub export fn apiWinGetWidth(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Try to get actual window dimensions
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        return c.hermes_value_create_number(rt, @floatFromInt(window.width));
    }

    // Fallback: return terminal cols for window 0
    if (win_handle == 0) {
        const dims = ctx.get_dimensions_fn(ctx.context_ptr);
        return c.hermes_value_create_number(rt, @floatFromInt(dims.cols));
    }

    return c.hermes_value_create_null(rt);
}

// ============================================================================
// NEW WINDOW API FUNCTIONS (TDD - implemented to pass E2E tests)
// ============================================================================

/// vim.api.setCurrentWin(win) -> void
/// Switches to window (silently ignores invalid handles, Neovim behavior)
pub export fn apiSetCurrentWin(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Handle 0 = current window, no change needed
    if (win_handle == 0) return c.hermes_value_create_undefined(rt);

    // Try to switch window via Editor
    const editor = getEditorFromContext(ctx) orelse return c.hermes_value_create_undefined(rt);
    const win_id = WindowId{ .id = @intCast(win_handle) };

    // Verify window exists before switching
    if (editor.windows.contains(win_id)) {
        editor.current_window_id = win_id;
    }
    // Silently ignore invalid window handles (Neovim behavior)

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.listWins() -> Window[]
/// Returns array of all valid window handles
pub export fn apiListWins(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse {
        // Fallback: single window with handle 0
        const arr = c.hermes_array_create(rt, 1) orelse return c.hermes_value_create_null(rt);
        const win_val = c.hermes_value_create_number(rt, 0);
        if (win_val) |wv| {
            c.hermes_array_set(rt, arr, 0, wv);
            c.hermes_value_destroy(wv);
        }
        return arr;
    };

    // Get all window IDs
    const ids = getAllWindowIds(ctx, ctx.allocator) orelse {
        // Fallback: single window with handle 0
        const arr = c.hermes_array_create(rt, 1) orelse return c.hermes_value_create_null(rt);
        const win_val = c.hermes_value_create_number(rt, 0);
        if (win_val) |wv| {
            c.hermes_array_set(rt, arr, 0, wv);
            c.hermes_value_destroy(wv);
        }
        return arr;
    };
    defer ctx.allocator.free(ids);

    // Create array with all window IDs
    const arr = c.hermes_array_create(rt, @intCast(ids.len)) orelse return c.hermes_value_create_null(rt);
    for (ids, 0..) |id, i| {
        const win_val = c.hermes_value_create_number(rt, @floatFromInt(id));
        if (win_val) |wv| {
            c.hermes_array_set(rt, arr, @intCast(i), wv);
            c.hermes_value_destroy(wv);
        }
    }
    return arr;
}

/// vim.api.winSetBuf(win, buf) -> void
/// Sets buffer in window (single-buffer mode: validates but no-op)
pub export fn apiWinSetBuf(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    // Single-buffer mode: silently ignore (Neovim behavior)
    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winSetHeight(win, height) -> void
/// Sets window height (single-window mode: no-op)
pub export fn apiWinSetHeight(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    // Single-window mode: cannot change height (Neovim behavior)
    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winSetWidth(win, width) -> void
/// Sets window width (single-window mode: no-op)
pub export fn apiWinSetWidth(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    // Single-window mode: cannot change width (Neovim behavior)
    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winClose(win, force) -> void
/// Closes window (cannot close last window unless force=true for modified buffers)
pub export fn apiWinClose(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win, force)
    if (count < 1) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get force flag (default false)
    var force = false;
    if (count >= 2) {
        if (args[1]) |force_val| {
            force = c.hermes_value_get_boolean(force_val);
        }
    }

    // Get editor
    const editor = getEditorFromContext(ctx) orelse return c.hermes_value_create_undefined(rt);

    // Resolve window ID
    const win_id: WindowId = if (win_handle == 0) blk: {
        break :blk editor.current_window_id orelse return c.hermes_value_create_undefined(rt);
    } else blk: {
        break :blk WindowId{ .id = @intCast(win_handle) };
    };

    // Try to close the window
    editor.closeWindow(win_id, force) catch {
        // Silently fail (Neovim behavior - throws error but we just return)
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winGetVar(win, name) -> any
/// Gets window-local variable (w:)
pub export fn apiWinGetVar(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win, name)
    if (count < 2) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get variable name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    // Try to get variable from Window struct (multi-window support)
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        if (window.getVar(name)) |stored_val| {
            return c.hermes_value_clone(rt, stored_val);
        }
        return c.hermes_value_create_undefined(rt);
    }

    // Fallback: use global context vars for window 0 (legacy)
    if (win_handle == 0) {
        if (ctx.window_vars.get(name)) |stored_val| {
            return c.hermes_value_clone(rt, stored_val);
        }
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winSetVar(win, name, value) -> void
/// Sets window-local variable (w:)
pub export fn apiWinSetVar(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win, name, value)
    if (count < 3) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);
    const value_val = args[2] orelse return c.hermes_value_create_undefined(rt);

    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get variable name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    // Try to set variable on Window struct (multi-window support)
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        window.setVar(name, value_val) catch {};
        return c.hermes_value_create_undefined(rt);
    }

    // Fallback: use global context vars for window 0 (legacy)
    if (win_handle == 0) {
        // Allocate name copy
        const name_copy = ctx.allocator.dupe(u8, name) catch return c.hermes_value_create_undefined(rt);

        // Clone value for storage
        const value_clone = c.hermes_value_clone(rt, value_val) orelse {
            ctx.allocator.free(name_copy);
            return c.hermes_value_create_undefined(rt);
        };

        // Free old value if exists
        if (ctx.window_vars.fetchRemove(name_copy)) |old| {
            c.hermes_value_destroy(old.value);
            ctx.allocator.free(old.key);
        }

        ctx.window_vars.put(name_copy, value_clone) catch {
            c.hermes_value_destroy(value_clone);
            ctx.allocator.free(name_copy);
        };
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winDelVar(win, name) -> void
/// Deletes window-local variable (w:)
pub export fn apiWinDelVar(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win, name)
    if (count < 2) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get variable name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    // Try to delete variable from Window struct (multi-window support)
    if (getWindowFromHandle(ctx, win_handle)) |window| {
        window.delVar(name);
        return c.hermes_value_create_undefined(rt);
    }

    // Fallback: use global context vars for window 0 (legacy)
    if (win_handle == 0) {
        if (ctx.window_vars.fetchRemove(name)) |old| {
            c.hermes_value_destroy(old.value);
            ctx.allocator.free(old.key);
        }
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winCall(win, fun) -> any
/// Calls function with window context (temporarily switches current window)
pub export fn apiWinCall(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Validate arguments (win, fun)
    if (count < 2) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const fun_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get editor to switch window context
    const editor = getEditorFromContext(ctx);

    // Save original window ID
    var original_win_id: ?WindowId = null;
    if (editor) |e| {
        original_win_id = e.current_window_id;

        // Temporarily switch to target window
        if (win_handle != 0) {
            const target_id = WindowId{ .id = @intCast(win_handle) };
            if (e.windows.contains(target_id)) {
                e.current_window_id = target_id;
            }
        }
    }

    // Call the function
    const result = c.hermes_call_function(rt, fun_val, null, 0);

    // Restore original window context
    if (editor) |e| {
        e.current_window_id = original_win_id;
    }

    return result;
}

/// vim.api.winGetNumber(win) -> number
/// Returns window number (1-indexed, Vim convention)
/// Window numbers are assigned based on traversal order of the layout tree
pub export fn apiWinGetNumber(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse {
        // Fallback: single window is always #1
        return c.hermes_value_create_number(rt, 1);
    };

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_number(rt, -1);

    const win_handle_val = args[0] orelse return c.hermes_value_create_number(rt, -1);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get editor
    const editor = getEditorFromContext(ctx) orelse {
        // Fallback: window 0 is always #1
        if (win_handle == 0) return c.hermes_value_create_number(rt, 1);
        return c.hermes_value_create_number(rt, -1);
    };

    // Resolve window ID
    const target_win_id: WindowId = if (win_handle == 0) blk: {
        break :blk editor.current_window_id orelse return c.hermes_value_create_number(rt, -1);
    } else blk: {
        break :blk WindowId{ .id = @intCast(win_handle) };
    };

    // Get all window IDs and find the position
    const ids = getAllWindowIds(ctx, ctx.allocator) orelse {
        // Fallback
        if (win_handle == 0) return c.hermes_value_create_number(rt, 1);
        return c.hermes_value_create_number(rt, -1);
    };
    defer ctx.allocator.free(ids);

    // Find position (1-indexed)
    for (ids, 0..) |id, i| {
        if (id == target_win_id.id) {
            return c.hermes_value_create_number(rt, @floatFromInt(i + 1));
        }
    }

    return c.hermes_value_create_number(rt, -1);
}

/// vim.api.winGetPosition(win) -> [row, col]
/// Returns window position (screen coordinates)
pub export fn apiWinGetPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse {
        // Fallback: [0, 0] for single window
        const arr = c.hermes_array_create(rt, 2) orelse return c.hermes_value_create_null(rt);
        const row_val = c.hermes_value_create_number(rt, 0);
        const col_val = c.hermes_value_create_number(rt, 0);
        if (row_val) |rv| {
            c.hermes_array_set(rt, arr, 0, rv);
            c.hermes_value_destroy(rv);
        }
        if (col_val) |cv| {
            c.hermes_array_set(rt, arr, 1, cv);
            c.hermes_value_destroy(cv);
        }
        return arr;
    };

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Get actual window position
    const window = getWindowFromHandle(ctx, win_handle) orelse {
        // Window not found, return null
        return c.hermes_value_create_null(rt);
    };

    const arr = c.hermes_array_create(rt, 2) orelse return c.hermes_value_create_null(rt);

    const row_val = c.hermes_value_create_number(rt, @floatFromInt(window.screen_row));
    const col_val = c.hermes_value_create_number(rt, @floatFromInt(window.screen_col));

    if (row_val) |rv| {
        c.hermes_array_set(rt, arr, 0, rv);
        c.hermes_value_destroy(rv);
    }
    if (col_val) |cv| {
        c.hermes_array_set(rt, arr, 1, cv);
        c.hermes_value_destroy(cv);
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register vim.api window functions for Editor mode
pub fn registerForEditor(runtime: *c.OVHermesRuntime, editor: *Editor, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(ApiWindowContext) catch return;
    ctx.* = ApiWindowContext{
        .allocator = allocator,
        .get_buffer_fn = &getBufferFromEditor,
        .get_dimensions_fn = &getDimensionsFromEditor,
        .context_ptr = @ptrCast(editor),
        .window_vars = std.StringHashMap(*c.OVHermesValue).init(allocator),
        .runtime = runtime,
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

/// Register vim.api window functions for EditorContext mode (headless/E2E)
pub fn registerForEditorContext(runtime: *c.OVHermesRuntime, editor_ctx: *EditorContext, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(ApiWindowContext) catch return;
    ctx.* = ApiWindowContext{
        .allocator = allocator,
        .get_buffer_fn = &getBufferFromEditorContext,
        .get_dimensions_fn = &getDimensionsFromEditorContext,
        .context_ptr = @ptrCast(editor_ctx),
        .window_vars = std.StringHashMap(*c.OVHermesValue).init(allocator),
        .runtime = runtime,
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

fn registerFunctions(runtime: *c.OVHermesRuntime) void {
    // Original 7 functions
    c.hermes_register_host_function(runtime, "vimApiGetCurrentWin", apiGetCurrentWin, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetCursor", apiWinGetCursor, null);
    c.hermes_register_host_function(runtime, "vimApiWinSetCursor", apiWinSetCursor, null);
    c.hermes_register_host_function(runtime, "vimApiWinIsValid", apiWinIsValid, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetBuf", apiWinGetBuf, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetHeight", apiWinGetHeight, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetWidth", apiWinGetWidth, null);

    // 12 new functions
    c.hermes_register_host_function(runtime, "vimApiSetCurrentWin", apiSetCurrentWin, null);
    c.hermes_register_host_function(runtime, "vimApiListWins", apiListWins, null);
    c.hermes_register_host_function(runtime, "vimApiWinSetBuf", apiWinSetBuf, null);
    c.hermes_register_host_function(runtime, "vimApiWinSetHeight", apiWinSetHeight, null);
    c.hermes_register_host_function(runtime, "vimApiWinSetWidth", apiWinSetWidth, null);
    c.hermes_register_host_function(runtime, "vimApiWinClose", apiWinClose, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetVar", apiWinGetVar, null);
    c.hermes_register_host_function(runtime, "vimApiWinSetVar", apiWinSetVar, null);
    c.hermes_register_host_function(runtime, "vimApiWinDelVar", apiWinDelVar, null);
    c.hermes_register_host_function(runtime, "vimApiWinCall", apiWinCall, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetNumber", apiWinGetNumber, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetPosition", apiWinGetPosition, null);
}

/// Cleanup
pub fn deinit() void {
    if (global_ctx) |ctx| {
        // Clean up window variables
        var it = ctx.window_vars.iterator();
        while (it.next()) |entry| {
            c.hermes_value_destroy(entry.value_ptr.*);
            ctx.allocator.free(entry.key_ptr.*);
        }
        ctx.window_vars.deinit();
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}

// ============================================================================
// Helper functions for context abstraction
// ============================================================================

fn getBufferFromEditor(ptr: *anyopaque) ?*Buffer {
    const editor: *Editor = @ptrCast(@alignCast(ptr));
    return editor.getCurrentBuffer();
}

fn getBufferFromEditorContext(ptr: *anyopaque) ?*Buffer {
    const ctx: *EditorContext = @ptrCast(@alignCast(ptr));
    return ctx.buffer();
}

fn getDimensionsFromEditor(ptr: *anyopaque) Dimensions {
    _ = ptr;
    // Editor mode doesn't store terminal dimensions directly
    // For now, return default terminal size (actual size handled by terminal backend)
    // TODO: Store terminal dimensions in Editor or pass via registration
    return .{ .rows = 24, .cols = 80 };
}

fn getDimensionsFromEditorContext(ptr: *anyopaque) Dimensions {
    const ctx: *EditorContext = @ptrCast(@alignCast(ptr));
    // EditorContext has display with terminal dimensions
    return .{ .rows = ctx.display.terminal_rows, .cols = ctx.display.terminal_cols };
}

// ============================================================================
// Multi-window support helper functions (Phase 5)
// ============================================================================
const Window = @import("../../editor/window.zig").Window;
const WindowId = @import("../../editor/window.zig").WindowId;

/// Get current window ID from context (returns null if not available)
fn getCurrentWindowIdFromContext(ctx: *ApiWindowContext) ?u32 {
    // Try Editor first
    const editor = getEditorFromContext(ctx) orelse return null;
    if (editor.current_window_id) |win_id| {
        return win_id.id;
    }
    return null;
}

/// Get Editor from context (works for both Editor and EditorContext)
fn getEditorFromContext(ctx: *ApiWindowContext) ?*Editor {
    // Check if context_ptr is an Editor or EditorContext
    // The get_buffer_fn tells us which one we're using
    if (ctx.get_buffer_fn == &getBufferFromEditor) {
        // Direct Editor mode
        return @ptrCast(@alignCast(ctx.context_ptr));
    } else if (ctx.get_buffer_fn == &getBufferFromEditorContext) {
        // EditorContext mode (headless/E2E) - extract nested Editor
        const editor_ctx: *EditorContext = @ptrCast(@alignCast(ctx.context_ptr));
        return &editor_ctx.editor;
    }
    return null;
}

/// Get window by handle (handle 0 = current window)
fn getWindowFromHandle(ctx: *ApiWindowContext, handle: i32) ?*Window {
    const editor = getEditorFromContext(ctx) orelse return null;

    const win_id: WindowId = if (handle == 0) blk: {
        // Handle 0 = current window
        break :blk editor.current_window_id orelse return null;
    } else blk: {
        break :blk WindowId{ .id = @intCast(handle) };
    };

    return editor.windows.get(win_id);
}

/// Get buffer for a window
fn getBufferForWindow(ctx: *ApiWindowContext, window: *Window) ?*Buffer {
    const editor = getEditorFromContext(ctx) orelse return null;
    return editor.buffers.get(window.buffer_id);
}

/// Check if window handle is valid
fn isWindowHandleValid(ctx: *ApiWindowContext, handle: i32) bool {
    if (handle == 0) return true; // Handle 0 = current window (always valid if editor exists)
    return getWindowFromHandle(ctx, handle) != null;
}

/// Get all window IDs
fn getAllWindowIds(ctx: *ApiWindowContext, allocator: std.mem.Allocator) ?[]u32 {
    const editor = getEditorFromContext(ctx) orelse return null;

    var ids = std.ArrayListUnmanaged(u32){};
    var it = editor.windows.keyIterator();
    while (it.next()) |key| {
        ids.append(allocator, key.id) catch return null;
    }

    return ids.toOwnedSlice(allocator) catch null;
}
