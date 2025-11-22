/// Motion API Module
/// Exposes Vim motion commands to JavaScript plugins
/// Allows plugins to programmatically trigger cursor movement
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const movement = @import("../../editor/movement/movement.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context for motion API (passed to all motion functions)
pub const MotionContext = struct {
    buffer: *Buffer,
    viewport_top: *usize, // Pointer to display's viewport_top
    viewport_height: usize,
    js_state_dirty: ?*bool, // Pointer to editor's js_state_dirty flag (null for EditorContext)

    /// Mark editor state as dirty (triggers re-render in main loop)
    inline fn markDirty(self: *const MotionContext) void {
        if (self.js_state_dirty) |dirty_flag| {
            dirty_flag.* = true;
        }
    }
};

// ============================================================================
// Character Motion (h/j/k/l)
// ============================================================================

/// Move cursor left (h)
pub export fn moveLeft(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    _ = movement.moveLeft(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move cursor right (l)
pub export fn moveRight(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    _ = movement.moveRight(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move cursor up (k)
pub export fn moveUp(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    _ = movement.moveUp(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move cursor down (j)
pub export fn moveDown(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    _ = movement.moveDown(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// Line Motion (0/$^)
// ============================================================================

/// Move to start of line (0)
pub export fn moveToLineStart(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToLineStart(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to end of line ($)
pub export fn moveToLineEnd(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToLineEnd(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to first non-blank character (^)
pub export fn moveToFirstNonBlank(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToFirstNonBlank(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// Word Motion (w/b/e)
// ============================================================================

/// Move to next word start (w)
pub export fn moveWordForward(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveWordForward(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to previous word start (b)
pub export fn moveWordBackward(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveWordBackward(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to word end (e)
pub export fn moveWordEnd(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveWordEnd(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// File Motion (gg/G)
// ============================================================================

/// Move to start of file (gg)
pub export fn moveToFileStart(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToFileStart(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to end of file (G)
pub export fn moveToFileEnd(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToFileEnd(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// Viewport Motion (H/M/L)
// ============================================================================

/// Move to top of viewport (H)
/// Note: Uses start_of_line=false (preserve sticky column) - modern preferred behavior
/// TODO: Add options_manager to MotionContext for full 'startofline' option support
pub export fn moveToViewportTop(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToViewportTop(ctx.buffer, ctx.viewport_top.*, false);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to middle of viewport (M)
/// Note: Uses start_of_line=false (preserve sticky column) - modern preferred behavior
pub export fn moveToViewportMiddle(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToViewportMiddle(ctx.buffer, ctx.viewport_top.*, ctx.viewport_height, false);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to bottom of viewport (L)
/// Note: Uses start_of_line=false (preserve sticky column) - modern preferred behavior
pub export fn moveToViewportBottom(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToViewportBottom(ctx.buffer, ctx.viewport_top.*, ctx.viewport_height, false);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// Scrolling (Ctrl+D/U)
// ============================================================================

/// Scroll half page down (Ctrl+D)
pub export fn scrollHalfPageDown(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.scrollHalfPageDown(ctx.buffer, ctx.viewport_height);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Scroll half page up (Ctrl+U)
pub export fn scrollHalfPageUp(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.scrollHalfPageUp(ctx.buffer, ctx.viewport_height);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

const host_object_builder = @import("host_object_builder.zig");

/// HostObject getter - routes property access to methods
/// This is called when JavaScript accesses vim.motion.up, vim.motion.down, etc.
pub export fn motionHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Use StaticStringMap for O(1) property dispatch
    const PropertyMap = std.StaticStringMap(host_object_builder.HostFunction).initComptime(.{
        .{ "left", moveLeft },
        .{ "right", moveRight },
        .{ "up", moveUp },
        .{ "down", moveDown },
        .{ "lineStart", moveToLineStart },
        .{ "lineEnd", moveToLineEnd },
        .{ "firstNonBlank", moveToFirstNonBlank },
        .{ "wordForward", moveWordForward },
        .{ "wordBackward", moveWordBackward },
        .{ "wordEnd", moveWordEnd },
        .{ "fileStart", moveToFileStart },
        .{ "fileEnd", moveToFileEnd },
        .{ "viewportTop", moveToViewportTop },
        .{ "viewportMiddle", moveToViewportMiddle },
        .{ "viewportBottom", moveToViewportBottom },
        .{ "scrollHalfPageDown", scrollHalfPageDown },
        .{ "scrollHalfPageUp", scrollHalfPageUp },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// HostObject enumerator - returns array of all motion method names
/// This is called when JavaScript calls Object.keys(vim.motion)
pub export fn motionHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    // Create array of method names
    const method_names = [_][]const u8{
        "left",           "right",          "up",
        "down",           "lineStart",      "lineEnd",
        "firstNonBlank",  "wordForward",    "wordBackward",
        "wordEnd",        "fileStart",      "fileEnd",
        "viewportTop",    "viewportMiddle", "viewportBottom",
        "scrollHalfPageDown", "scrollHalfPageUp",
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

/// Register motion API as HostObject (zero-copy, 3-5x faster than host functions)
/// JavaScript usage: vim.motion.up(), vim.motion.down(), etc.
pub fn register(runtime: *c.OVHermesRuntime, ctx: *MotionContext) void {
    c.hermes_register_host_object(
        runtime,
        "vimMotion", // Registered as global.vimMotion (will be vim.motion in runtime.js)
        motionHostObjectGet,
        null, // No setter (read-only methods)
        motionHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

/// Legacy registration (backwards compatibility during transition)
/// TODO: Remove after all examples/tests updated to new API
pub fn registerLegacy(runtime: *c.OVHermesRuntime, ctx: *MotionContext) void {
    // Character motion
    c.hermes_register_host_function(runtime, "moveLeft", moveLeft, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveRight", moveRight, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveUp", moveUp, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveDown", moveDown, @ptrCast(ctx));

    // Line motion
    c.hermes_register_host_function(runtime, "moveToLineStart", moveToLineStart, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveToLineEnd", moveToLineEnd, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveToFirstNonBlank", moveToFirstNonBlank, @ptrCast(ctx));

    // Word motion
    c.hermes_register_host_function(runtime, "moveWordForward", moveWordForward, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveWordBackward", moveWordBackward, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveWordEnd", moveWordEnd, @ptrCast(ctx));

    // File motion
    c.hermes_register_host_function(runtime, "moveToFileStart", moveToFileStart, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveToFileEnd", moveToFileEnd, @ptrCast(ctx));

    // Viewport motion
    c.hermes_register_host_function(runtime, "moveToViewportTop", moveToViewportTop, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveToViewportMiddle", moveToViewportMiddle, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "moveToViewportBottom", moveToViewportBottom, @ptrCast(ctx));

    // Scrolling
    c.hermes_register_host_function(runtime, "scrollHalfPageDown", scrollHalfPageDown, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "scrollHalfPageUp", scrollHalfPageUp, @ptrCast(ctx));
}
