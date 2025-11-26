/// Animation Frame API Module
/// Handles requestAnimationFrame JSI function
/// Integrates with editor's render loop for smooth animations
/// React Native pattern: JavaScript provides callback IDs
const std = @import("std");
const debug_log = @import("../../backends/headless/log.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Animation frame callback registry
/// Stores callbacks that run on next frame
var animation_callbacks: std.ArrayList(usize) = undefined; // JS callback IDs
var animation_callbacks_initialized = false;
var animation_frame_modified_layers = false; // Track if last frame modified layers

/// Timer system state (needed for runtime access)
var animation_allocator: std.mem.Allocator = undefined;
var animation_runtime: ?*c.OVHermesRuntime = null;
var animation_initialized = false;

/// Initialize animation frame system
pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) void {
    if (animation_initialized) return;

    animation_allocator = allocator;
    animation_runtime = runtime;
    animation_initialized = true;

    if (!animation_callbacks_initialized) {
        animation_callbacks = .empty;
        animation_callbacks_initialized = true;
    }
}

/// Process all pending animation frame callbacks
/// Called by editor before rendering
/// Returns true if layers were modified (by RAF callbacks OR by timer callbacks via layer API)
pub fn processFrames(allocator: std.mem.Allocator) bool {
    if (!animation_initialized or !animation_callbacks_initialized) return false;

    // IMPORTANT: Check flag even when no RAF callbacks are queued!
    // Timer callbacks (setTimeout) can also modify layers via vim.layer.renderVirtualText()
    if (animation_callbacks.items.len == 0) {
        // Return current flag value and reset it
        const modified = animation_frame_modified_layers;
        animation_frame_modified_layers = false;
        if (modified) {
            debug_log.log("[ANIM] processFrames() returning TRUE (no RAF, but flag was set)", .{});
        }
        return modified;
    }

    const rt = animation_runtime orelse return false;

    // Reset the flag before processing callbacks
    animation_frame_modified_layers = false;

    debug_log.log("[RAF] Processing {d} animation frame callbacks", .{animation_callbacks.items.len});

    // Make a copy of callbacks and clear the list
    // This allows callbacks to re-queue themselves
    var callbacks_copy: std.ArrayList(usize) = .empty;
    callbacks_copy.appendSlice(allocator, animation_callbacks.items) catch return false;
    defer callbacks_copy.deinit(allocator);
    animation_callbacks.clearRetainingCapacity();

    // Call each animation frame callback
    for (callbacks_copy.items) |callback_id| {
        // Get global object
        const global = c.hermes_get_global_object(rt);
        if (global == null) continue;

        // Get __handleAnimationFrame function
        const callback_fn = c.hermes_object_get_property(rt, global, "__handleAnimationFrame");
        if (callback_fn == null) {
            c.hermes_object_destroy(global);
            continue;
        }

        if (!c.hermes_value_is_function(rt, callback_fn)) {
            c.hermes_value_destroy(callback_fn);
            c.hermes_object_destroy(global);
            continue;
        }

        // Create callback ID argument
        const id_arg = c.hermes_value_create_number(rt, @floatFromInt(callback_id));
        if (id_arg == null) {
            c.hermes_value_destroy(callback_fn);
            c.hermes_object_destroy(global);
            continue;
        }

        // Call __handleAnimationFrame(id)
        debug_log.log("[RAF] Calling JS callback {d}", .{callback_id});
        var args = [_]?*c.OVHermesValue{id_arg};
        const result = c.hermes_call_function(rt, callback_fn, &args, 1);

        c.hermes_value_destroy(id_arg);

        if (result != null) {
            debug_log.log("[RAF] Callback {d} completed successfully", .{callback_id});
            c.hermes_value_destroy(result);
        } else {
            if (c.hermes_has_exception(rt)) {
                const err_msg = c.hermes_get_exception_message(rt);
                std.debug.print("[JSI] Animation frame callback exception: {s}\n", .{err_msg});
                debug_log.log("[RAF] Callback {d} threw exception: {s}", .{ callback_id, err_msg });
            }
        }

        c.hermes_value_destroy(callback_fn);
        c.hermes_object_destroy(global);
    }

    // Return true ONLY if layers were actually modified
    // This prevents unnecessary re-renders when idle
    return animation_frame_modified_layers;
}

/// Zig host function: requestAnimationFrame(id)
/// JavaScript provides callback ID, callback runs on next render frame
export fn requestAnimationFrameNative(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const runtime = runtime_nullable;

    if (arg_count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    if (!animation_initialized or !animation_callbacks_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: callback ID (JavaScript-provided)
    const id_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    const callback_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Queue callback for next frame
    animation_callbacks.append(animation_allocator, callback_id) catch {
        debug_log.log("[RAF] FAILED to queue callback {d}", .{callback_id});
        return c.hermes_value_create_undefined(runtime);
    };

    debug_log.log("[RAF] Queued callback {d} (total queued: {d})", .{ callback_id, animation_callbacks.items.len });

    return c.hermes_value_create_undefined(runtime);
}

/// Mark that layers were modified during this animation frame
/// Called by JavaScript when it modifies layers
export fn markAnimationFrameDirty(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    _ = context;
    _ = args;
    _ = count;

    animation_frame_modified_layers = true;
    return null;
}

/// Public function to mark layers as modified (called by layer_api)
pub fn markLayersModified() void {
    animation_frame_modified_layers = true;
    debug_log.log("[ANIM] markLayersModified() called, flag now TRUE", .{});
}

/// Register animation frame API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, allocator: std.mem.Allocator) void {
    // Initialize animation system
    init(allocator, runtime);

    // Register animation frame API (native render loop integration)
    c.hermes_register_host_function(
        runtime,
        "__nativeRequestAnimationFrame",
        requestAnimationFrameNative,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "__nativeMarkAnimationFrameDirty",
        markAnimationFrameDirty,
        null,
    );
}
