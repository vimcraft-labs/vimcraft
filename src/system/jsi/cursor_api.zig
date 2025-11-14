/// Cursor API Module
/// Handles cursor position and rendering JSI functions
/// Used for animated cursor plugins and cursor effects
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const helpers = @import("helpers.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Zig host function: getCursorPosition() -> {row, col}
/// Returns current buffer cursor position as JavaScript object
export fn getCursorPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    // Get cursor position from buffer
    const row = editor.buffer.cursor.row;
    const col = editor.buffer.cursor.col;

    // Create JavaScript object: {row, col}
    const obj = c.hermes_value_create_object(runtime) orelse return null;

    // Create number values for row and col
    const row_val = c.hermes_value_create_number(runtime, @floatFromInt(row));
    const col_val = c.hermes_value_create_number(runtime, @floatFromInt(col));

    if (row_val != null and col_val != null) {
        // Set properties on the object
        c.hermes_value_set_property(runtime, obj, "row", row_val);
        c.hermes_value_set_property(runtime, obj, "col", col_val);

        // Clean up temporary values
        c.hermes_value_destroy(row_val);
        c.hermes_value_destroy(col_val);
    }

    return obj;
}

/// Zig host function: setCursorRenderPosition(row, col)
/// Sets the cursor render position override (for animations)
export fn setCursorRenderPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;

    if (count < 2) return null;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    const row_val = args[0] orelse return null;
    const col_val = args[1] orelse return null;

    const row_f = c.hermes_value_get_number(row_val);
    const col_f = c.hermes_value_get_number(col_val);

    // Validate that values are finite and non-negative
    if (std.math.isNan(row_f) or std.math.isInf(row_f) or row_f < 0) {
        return null; // Invalid row value
    }
    if (std.math.isNan(col_f) or std.math.isInf(col_f) or col_f < 0) {
        return null; // Invalid col value
    }

    const row: usize = @intFromFloat(row_f);
    const col: usize = @intFromFloat(col_f);

    // Store override position in editor
    editor.cursor_render_override.set(row, col);

    // Mark editor state as dirty to trigger render
    editor.js_state_dirty = true;

    return null; // Return undefined
}

/// Zig host function: clearCursorRenderPosition()
/// Clears the cursor render position override
export fn clearCursorRenderPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    _ = args;
    _ = count;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    // Clear override
    editor.cursor_render_override.clear();

    // Mark editor state as dirty to trigger render
    editor.js_state_dirty = true;

    return null; // Return undefined
}

/// Register cursor API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, editor: *Editor) void {
    // Register cursor position hooks (for animated cursor plugins)
    c.hermes_register_host_function(
        runtime,
        "getCursorPosition",
        getCursorPosition,
        @ptrCast(editor),
    );

    c.hermes_register_host_function(
        runtime,
        "setCursorRenderPosition",
        setCursorRenderPosition,
        @ptrCast(editor),
    );

    c.hermes_register_host_function(
        runtime,
        "clearCursorRenderPosition",
        clearCursorRenderPosition,
        @ptrCast(editor),
    );
}
