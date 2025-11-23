/// vim.api Window Functions
/// Implements Neovim-compatible window API:
/// - getCurrentWin() -> Window (handle)
/// - winGetCursor(win) -> [row, col] (row is 1-indexed, col is 0-indexed)
/// - winSetCursor(win, [row, col]) -> void
/// - winIsValid(win) -> boolean
/// - winGetBuf(win) -> Buffer (handle)
/// - winGetHeight(win) -> number
/// - winGetWidth(win) -> number
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
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

fn registerFunctions(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_function(runtime, "vimApiGetCurrentWin", apiGetCurrentWin, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetCursor", apiWinGetCursor, null);
    c.hermes_register_host_function(runtime, "vimApiWinSetCursor", apiWinSetCursor, null);
    c.hermes_register_host_function(runtime, "vimApiWinIsValid", apiWinIsValid, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetBuf", apiWinGetBuf, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetHeight", apiWinGetHeight, null);
    c.hermes_register_host_function(runtime, "vimApiWinGetWidth", apiWinGetWidth, null);
}

/// Cleanup
pub fn deinit() void {
    if (global_ctx) |ctx| {
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
