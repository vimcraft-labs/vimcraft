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
pub export fn getCursorPosition(
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
pub export fn setCursorRenderPosition(
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
pub export fn clearCursorRenderPosition(
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

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.cursor HostObject getter - routes property access to methods
pub export fn cursorHostObjectGet(
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
        .{ "getPosition", getCursorPosition },
        .{ "setRenderPosition", setCursorRenderPosition },
        .{ "clearRenderPosition", clearCursorRenderPosition },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.cursor HostObject enumerator - returns array of method names
pub export fn cursorHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "getPosition",
        "setRenderPosition",
        "clearRenderPosition",
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

/// Register cursor API as HostObject (zero-copy, 3-5x faster)
/// JavaScript usage: vim.cursor.getPosition(), vim.cursor.setRenderPosition(row, col)
pub fn register(runtime: *c.OVHermesRuntime, editor: *Editor) void {
    c.hermes_register_host_object(
        runtime,
        "vimCursor",
        cursorHostObjectGet,
        null, // No setter (read-only methods)
        cursorHostObjectEnumerator,
        @ptrCast(editor),
    );
}

/// Legacy registration (backwards compatibility)
/// TODO: Remove after all examples/tests updated
pub fn registerLegacy(runtime: *c.OVHermesRuntime, editor: *Editor) void {
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
