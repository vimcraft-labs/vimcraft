/// Cursor API Module
/// Handles cursor position JSI functions
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const helpers = @import("helpers.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// Global display pointer for cursor visibility control
// This follows the same pattern as layer_api.zig
var global_display: ?*Display = null;

/// Set the global display for cursor operations
pub fn setDisplay(display: ?*Display) void {
    global_display = display;
}

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

    // Get cursor position from current buffer
    const buffer = editor.getCurrentBuffer() orelse return null;
    const row = buffer.cursor.row;
    const col = buffer.cursor.col;

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

/// Zig host function: hideCursor() -> void
/// Hides the terminal cursor using ANSI escape code
/// Used by plugins like smear-cursor to hide cursor during animation
pub export fn hideCursor(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    // Use global display (same pattern as layer_api.zig)
    if (global_display) |display| {
        display.hideCursor() catch {};
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: showCursor() -> void
/// Shows the terminal cursor using ANSI escape code
/// Used by plugins like smear-cursor to restore cursor after animation
pub export fn showCursor(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    // Use global display (same pattern as layer_api.zig)
    if (global_display) |display| {
        display.showCursor() catch {};
    }

    return c.hermes_value_create_undefined(runtime);
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
        .{ "hide", hideCursor },
        .{ "show", showCursor },
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
        "hide",
        "show",
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
/// JavaScript usage: vim.cursor.getPosition(), vim.cursor.hide(), vim.cursor.show()
pub fn register(runtime: *c.OVHermesRuntime, editor: *Editor, display: ?*Display) void {
    // Set global display for hide/show cursor operations
    global_display = display;

    c.hermes_register_host_object(
        runtime,
        "vimCursor",
        cursorHostObjectGet,
        null, // No setter (read-only methods)
        cursorHostObjectEnumerator,
        @ptrCast(editor),
    );
}

/// Register cursor API for EditorContext (E2E/headless mode)
/// EditorContext wraps an Editor, so we just pass the inner editor pointer
pub fn registerForEditorContext(runtime: *c.OVHermesRuntime, editor_ctx: *@import("../../backends/headless/editor_context.zig").EditorContext, display: ?*Display) void {
    // Set global display for hide/show cursor operations (may be null in headless)
    global_display = display;

    c.hermes_register_host_object(
        runtime,
        "vimCursor",
        cursorHostObjectGet,
        null, // No setter (read-only methods)
        cursorHostObjectEnumerator,
        @ptrCast(&editor_ctx.editor),
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
}
