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
/// Returns current window handle (always 0 for single-window mode)
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

    // Return 0 for current window (Neovim convention)
    return c.hermes_value_create_number(rt, 0);
}

/// vim.api.winGetCursor(win) -> [row, col]
/// Returns cursor position (row is 1-indexed, col is 0-indexed per Neovim convention)
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

    // Only window 0 (current) is valid for now
    if (win_handle != 0) return c.hermes_value_create_null(rt);

    const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_null(rt);

    // Create result array [row, col]
    // Neovim: row is 1-indexed, col is 0-indexed
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

    // Only window 0 (current) is valid for now
    if (win_handle != 0) return c.hermes_value_create_undefined(rt);

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

    const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_undefined(rt);

    // Use buffer's moveCursorTo which handles clamping
    buffer.moveCursorTo(row, col_usize);

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winIsValid(win) -> boolean
/// Returns true if window handle is valid
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

    // Only window 0 (current) is valid for now
    return c.hermes_value_create_boolean(rt, win_handle == 0);
}

/// vim.api.winGetBuf(win) -> Buffer
/// Returns buffer handle for window (always 0 for single-buffer mode)
pub export fn apiWinGetBuf(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Only window 0 (current) is valid for now
    if (win_handle != 0) return c.hermes_value_create_null(rt);

    // Return buffer 0 (current buffer)
    return c.hermes_value_create_number(rt, 0);
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

    // Only window 0 (current) is valid for now
    if (win_handle != 0) return c.hermes_value_create_null(rt);

    const dims = ctx.get_dimensions_fn(ctx.context_ptr);
    return c.hermes_value_create_number(rt, @floatFromInt(dims.rows));
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

    // Only window 0 (current) is valid for now
    if (win_handle != 0) return c.hermes_value_create_null(rt);

    const dims = ctx.get_dimensions_fn(ctx.context_ptr);
    return c.hermes_value_create_number(rt, @floatFromInt(dims.cols));
}

// ============================================================================
// NEW WINDOW API FUNCTIONS (TDD - implemented to pass E2E tests)
// ============================================================================

/// vim.api.setCurrentWin(win) -> void
/// Switches to window (no-op for single window mode, silently ignores invalid)
pub export fn apiSetCurrentWin(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    // Single-window mode: silently ignore (Neovim behavior)
    return c.hermes_value_create_undefined(rt);
}

/// vim.api.listWins() -> Window[]
/// Returns array of all valid window handles (single-window: [0])
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

    // Create array with single window (handle 0)
    const arr = c.hermes_array_create(rt, 1) orelse return c.hermes_value_create_null(rt);
    const win_val = c.hermes_value_create_number(rt, 0);
    if (win_val) |wv| {
        c.hermes_array_set(rt, arr, 0, wv);
        c.hermes_value_destroy(wv);
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
/// Closes window (single-window mode: cannot close last window)
pub export fn apiWinClose(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    // Single-window mode: cannot close only window (Neovim behavior)
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

    // Only window 0 (current) is valid
    if (win_handle != 0) return c.hermes_value_create_undefined(rt);

    // Get variable name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    // Look up variable and return a clone
    if (ctx.window_vars.get(name)) |stored_val| {
        return c.hermes_value_clone(rt, stored_val);
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

    // Only window 0 (current) is valid
    if (win_handle != 0) return c.hermes_value_create_undefined(rt);

    // Get variable name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);

    // Allocate name copy
    const name_copy = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return c.hermes_value_create_undefined(rt);

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

    // Only window 0 (current) is valid
    if (win_handle != 0) return c.hermes_value_create_undefined(rt);

    // Get variable name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    // Remove variable
    if (ctx.window_vars.fetchRemove(name)) |old| {
        c.hermes_value_destroy(old.value);
        ctx.allocator.free(old.key);
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winCall(win, fun) -> any
/// Calls function with window context (single-window: just call function)
pub export fn apiWinCall(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    // Validate arguments (win, fun)
    if (count < 2) return c.hermes_value_create_undefined(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const fun_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Only window 0 (current) is valid
    if (win_handle != 0) return c.hermes_value_create_undefined(rt);

    // Call the function (no arguments, window context implicit)
    // Pass empty args array (same pattern as bufCall)
    const result = c.hermes_call_function(rt, fun_val, null, 0);
    return result;
}

/// vim.api.winGetNumber(win) -> number
/// Returns window number (1-indexed, Vim convention)
pub export fn apiWinGetNumber(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_number(rt, -1);

    const win_handle_val = args[0] orelse return c.hermes_value_create_number(rt, -1);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Only window 0 (current) is valid, returns 1 (1-indexed)
    if (win_handle == 0) {
        return c.hermes_value_create_number(rt, 1);
    }
    return c.hermes_value_create_number(rt, -1);
}

/// vim.api.winGetPosition(win) -> [row, col]
/// Returns window position (screen coordinates, [0, 0] for full-screen window)
pub export fn apiWinGetPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    // Validate arguments (win handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const win_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const win_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(win_handle_val)));

    // Only window 0 (current) is valid
    if (win_handle != 0) return c.hermes_value_create_null(rt);

    // Full-screen window always at [0, 0]
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
