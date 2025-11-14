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
export fn moveLeft(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveLeft(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move cursor right (l)
export fn moveRight(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveRight(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move cursor up (k)
export fn moveUp(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveUp(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move cursor down (j)
export fn moveDown(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveDown(ctx.buffer);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// Line Motion (0/$^)
// ============================================================================

/// Move to start of line (0)
export fn moveToLineStart(
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
export fn moveToLineEnd(
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
export fn moveToFirstNonBlank(
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
export fn moveWordForward(
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
export fn moveWordBackward(
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
export fn moveWordEnd(
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
export fn moveToFileStart(
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
export fn moveToFileEnd(
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
export fn moveToViewportTop(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToViewportTop(ctx.buffer, ctx.viewport_top.*);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to middle of viewport (M)
export fn moveToViewportMiddle(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToViewportMiddle(ctx.buffer, ctx.viewport_top.*, ctx.viewport_height);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

/// Move to bottom of viewport (L)
export fn moveToViewportBottom(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*MotionContext, @ptrCast(@alignCast(context.?)));

    movement.moveToViewportBottom(ctx.buffer, ctx.viewport_top.*, ctx.viewport_height);
    ctx.markDirty();
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// Scrolling (Ctrl+D/U)
// ============================================================================

/// Scroll half page down (Ctrl+D)
export fn scrollHalfPageDown(
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
export fn scrollHalfPageUp(
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
// Registration
// ============================================================================

/// Register all motion API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, ctx: *MotionContext) void {
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
