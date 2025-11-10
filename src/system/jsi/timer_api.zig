/// Timer API Module
/// Handles setTimeout, setInterval, clearTimer JSI functions
/// React Native pattern: JavaScript manages callbacks, Zig only triggers them
/// Uses libuv for async timer management with thread-safe queue
const std = @import("std");
const debug_log = @import("../../backends/debug/log.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// Import libuv
const uv = @cImport({
    @cInclude("uv.h");
});

// Import event loop module
const event_loop = @import("../event_loop/libuv.zig");

/// Timer handle data
/// React Native pattern: Store only timer ID, not callback
/// JavaScript keeps the callbacks alive in its own registry
const TimerData = struct {
    timer: uv.uv_timer_t,
    runtime: *c.OVHermesRuntime,
    is_repeat: bool,
    allocator: std.mem.Allocator,
    timer_id: usize, // JavaScript-provided ID
};

var timer_allocator: std.mem.Allocator = undefined;
var timer_runtime: ?*c.OVHermesRuntime = null;
var timer_initialized = false;

/// Track active timers for cleanup
var active_timers: std.ArrayList(*TimerData) = undefined;
var timers_list_initialized = false;

/// Thread-safe timer queue (React Native style)
/// libuv callbacks add timer IDs here, main thread processes them
const TimerQueue = struct {
    mutex: std.Thread.Mutex = .{},
    pending_timers: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) TimerQueue {
        return .{
            .pending_timers = .empty,
            .allocator = allocator,
        };
    }

    fn deinit(self: *TimerQueue) void {
        self.pending_timers.deinit(self.allocator);
    }

    /// Add timer ID to queue (called from libuv thread)
    fn enqueue(self: *TimerQueue, timer_id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.pending_timers.append(self.allocator, timer_id) catch return;
    }

    /// Get all pending timer IDs (called from main thread)
    fn dequeueAll(self: *TimerQueue, allocator: std.mem.Allocator) !std.ArrayList(usize) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result: std.ArrayList(usize) = .empty;
        try result.appendSlice(allocator, self.pending_timers.items);
        self.pending_timers.clearRetainingCapacity();
        return result;
    }
};

var timer_queue: TimerQueue = undefined;
var timer_queue_initialized = false;

/// Initialize timer system
pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) void {
    timer_allocator = allocator;
    timer_runtime = runtime;
    timer_initialized = true;

    if (!timers_list_initialized) {
        active_timers = .empty;
        timers_list_initialized = true;
    }

    if (!timer_queue_initialized) {
        timer_queue = TimerQueue.init(allocator);
        timer_queue_initialized = true;
    }
}

/// Clear all active timers (for hot reload)
/// Unlike deinit(), this keeps the timer system initialized
pub fn clearAll() void {
    if (!timer_initialized or !timers_list_initialized) return;

    // Stop and close all active timers
    // Make a copy of the list because onTimerClose will modify active_timers
    var timers_copy = active_timers.clone(timer_allocator) catch return;
    defer timers_copy.deinit(timer_allocator);

    for (timers_copy.items) |timer_data| {
        _ = uv.uv_timer_stop(&timer_data.timer);
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
    }

    // Run event loop to process close callbacks
    const loop = event_loop.getLoop();
    if (loop) |l| {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            _ = uv.uv_run(@ptrCast(l), uv.UV_RUN_NOWAIT);
        }
    }
}

/// Deinitialize timer system
pub fn deinit() void {
    if (!timer_initialized) return;

    // Clear all active timers first
    clearAll();

    // Deinitialize timer queue
    if (timer_queue_initialized) {
        timer_queue.deinit();
        timer_queue_initialized = false;
    }

    // Now deinitialize the timer system
    active_timers.clearAndFree(timer_allocator);
    timer_initialized = false;
    timer_runtime = null;
}

/// Process timer queue and execute callbacks (React Native pattern)
/// MUST be called from main thread (where JSI runtime was created)
/// This is the SAFE place to call JavaScript - same thread as runtime!
pub fn processQueue(allocator: std.mem.Allocator) void {
    if (!timer_initialized or !timer_queue_initialized) return;
    if (!timers_list_initialized) return;

    const rt = timer_runtime orelse return;

    // Get all pending timer IDs from queue (thread-safe)
    var pending = timer_queue.dequeueAll(allocator) catch return;
    defer pending.deinit(allocator);

    // If no pending timers, nothing to do
    if (pending.items.len == 0) return;

    // Now we're on the main thread - SAFE to call JavaScript!
    // Process each timer individually
    for (pending.items) |timer_id| {
        // Get global object
        const global = c.hermes_get_global_object(rt);
        if (global == null) continue;
        // NOTE: We CANNOT use defer here! global must stay alive until AFTER function call
        // because callback_fn might hold a reference to it

        // Get __handleTimerCallback function
        const callback_fn = c.hermes_object_get_property(rt, global, "__handleTimerCallback");
        if (callback_fn == null) {
            c.hermes_object_destroy(global); // Clean up before continue
            continue;
        }

        // Verify it's a function
        if (!c.hermes_value_is_function(rt, callback_fn)) {
            c.hermes_value_destroy(callback_fn);
            c.hermes_object_destroy(global);
            continue;
        }
        // Find the timer data for this ID
        // IMPORTANT: Timer might have been cleared while in queue!
        var timer_exists = false;
        for (active_timers.items) |td| {
            if (td.timer_id == timer_id) {
                timer_exists = true;
                break;
            }
        }

        // Only call if timer still exists (not cleared)
        if (timer_exists) {
            // Create timer ID argument
            const id_arg = c.hermes_value_create_number(rt, @floatFromInt(timer_id));
            if (id_arg == null) {
                std.debug.print("[JSI] ERROR: Failed to create number for timer ID {}\n", .{timer_id});
                // Clean up before continue
                c.hermes_value_destroy(callback_fn);
                c.hermes_object_destroy(global);
                continue;
            }

            // Call __handleTimerCallback(id) in JavaScript
            // JavaScript manages the actual callback - we just pass the ID!
            var args = [_]?*c.OVHermesValue{id_arg};
            const result = c.hermes_call_function(rt, callback_fn, &args, 1);

            // Clean up argument
            c.hermes_value_destroy(id_arg);

            if (result != null) {
                c.hermes_value_destroy(result);
            } else {
                // Null result could mean exception - log it
                if (c.hermes_has_exception(rt)) {
                    const err_msg = c.hermes_get_exception_message(rt);
                    std.debug.print("[JSI] Timer callback exception: {s}\n", .{err_msg});
                }
            }
        }

        // Clean up at end of loop iteration (AFTER function call!)
        c.hermes_value_destroy(callback_fn);
        c.hermes_object_destroy(global);
    }
}

/// libuv timer callback - called when timer fires
/// React Native style: Queue timer ID instead of calling JS directly
/// This is THREAD-SAFE - no JSI calls from libuv thread!
fn onTimerFire(handle: [*c]uv.uv_timer_t) callconv(.c) void {
    // Get our timer data from the handle
    const timer_data = @as(*TimerData, @ptrCast(@alignCast(handle.*.data)));

    // ✅ SAFE: Add timer ID to queue (thread-safe operation)
    // Main event loop will process this and call JavaScript
    if (timer_queue_initialized) {
        timer_queue.enqueue(timer_data.timer_id);
    }

    // If this is a one-shot timeout (not interval), clean up
    if (!timer_data.is_repeat) {
        _ = uv.uv_timer_stop(handle);
        uv.uv_close(@ptrCast(handle), onTimerClose);
    }
}

/// libuv close callback - called when timer handle is closed
fn onTimerClose(handle: [*c]uv.uv_handle_t) callconv(.c) void {
    // Get our timer data
    const timer_data = @as(*TimerData, @ptrCast(@alignCast(handle.*.data)));

    // Remove from active timers list
    if (timers_list_initialized) {
        for (active_timers.items, 0..) |item, i| {
            if (item == timer_data) {
                _ = active_timers.swapRemove(i);
                break;
            }
        }
    }

    // No callback to destroy - JavaScript manages callbacks!

    // Free timer data
    timer_data.allocator.destroy(timer_data);
}

/// Zig host function: setTimeout(id, delay)
/// React Native pattern: JavaScript provides timer ID, not callback
/// JavaScript keeps the callback in its own registry
export fn setTimeoutNative(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: timer ID (JavaScript-provided)
    const id_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    const timer_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Arg 1: delay in milliseconds
    const delay_value = args[1] orelse return c.hermes_value_create_undefined(runtime);
    const delay_ms = c.hermes_value_get_number(delay_value);

    if (!timer_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    const loop = event_loop.getLoop() orelse return c.hermes_value_create_undefined(runtime);

    // Allocate timer data
    const timer_data = timer_allocator.create(TimerData) catch {
        return c.hermes_value_create_undefined(runtime);
    };

    // Initialize libuv timer FIRST (before setting TimerData fields)
    const init_result = uv.uv_timer_init(@ptrCast(loop), &timer_data.timer);
    if (init_result != 0) {
        timer_allocator.destroy(timer_data);
        return c.hermes_value_create_undefined(runtime);
    }

    // Now set the other fields
    timer_data.runtime = rt;
    timer_data.is_repeat = false;
    timer_data.allocator = timer_allocator;
    timer_data.timer_id = timer_id; // Use JavaScript-provided ID

    // Set timer data as user data
    timer_data.timer.data = timer_data;

    // Start the timer (one-shot: repeat = 0)
    const delay = @as(u64, @intFromFloat(@max(0, delay_ms)));
    const start_result = uv.uv_timer_start(&timer_data.timer, onTimerFire, delay, 0);
    if (start_result != 0) {
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
        return c.hermes_value_create_undefined(runtime);
    }

    // Track timer for cleanup
    active_timers.append(timer_allocator, timer_data) catch {
        // If we can't track it, close it
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
        return c.hermes_value_create_undefined(runtime);
    };

    // Return undefined - JavaScript already has the ID
    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: setInterval(id, delay)
/// React Native pattern: JavaScript provides timer ID, not callback
/// JavaScript keeps the callback in its own registry
export fn setIntervalNative(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: timer ID (JavaScript-provided)
    const id_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    const timer_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Arg 1: delay in milliseconds
    const delay_value = args[1] orelse return c.hermes_value_create_undefined(runtime);
    const delay_ms = c.hermes_value_get_number(delay_value);

    if (!timer_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Get libuv event loop
    const loop = event_loop.getLoop() orelse return c.hermes_value_create_undefined(runtime);

    // Allocate timer data on heap
    const timer_data = timer_allocator.create(TimerData) catch {
        return c.hermes_value_create_undefined(runtime);
    };

    // Initialize libuv timer handle FIRST
    const init_result = uv.uv_timer_init(@ptrCast(loop), &timer_data.timer);
    if (init_result != 0) {
        timer_allocator.destroy(timer_data);
        return c.hermes_value_create_undefined(runtime);
    }

    // Now set the other fields
    timer_data.runtime = rt;
    timer_data.is_repeat = true; // This is an interval timer
    timer_data.allocator = timer_allocator;
    timer_data.timer_id = timer_id; // Use JavaScript-provided ID

    // Store timer_data pointer in handle's data field for callback access
    timer_data.timer.data = timer_data;

    // Start the timer with repeat (interval mode)
    // For setInterval: pass delay as both timeout AND repeat parameter
    const delay = @as(u64, @intFromFloat(@max(0, delay_ms)));
    const start_result = uv.uv_timer_start(&timer_data.timer, onTimerFire, delay, delay);
    if (start_result != 0) {
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
        return c.hermes_value_create_undefined(runtime);
    }

    // Track timer for cleanup
    active_timers.append(timer_allocator, timer_data) catch {
        // If we can't track it, close it
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
        return c.hermes_value_create_undefined(runtime);
    };

    // Return undefined - JavaScript already has the ID
    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: clearTimer(id)
/// React Native pattern: Find timer by JavaScript-provided ID
export fn clearTimerNative(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1 or !timer_initialized or !timers_list_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: timer ID (JavaScript-provided)
    const id_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    const timer_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Find timer by ID
    var timer_data: ?*TimerData = null;
    for (active_timers.items) |td| {
        if (td.timer_id == timer_id) {
            timer_data = td;
            break;
        }
    }

    // If found, stop and close it
    if (timer_data) |td| {
        _ = uv.uv_timer_stop(&td.timer);
        uv.uv_close(@ptrCast(&td.timer), onTimerClose);
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Register timer API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, allocator: std.mem.Allocator) void {
    // Initialize timer system
    init(allocator, runtime);

    // Register timer functions with internal names to avoid recursion
    // JavaScript wrapper will call these and provide the user-facing API
    c.hermes_register_host_function(
        runtime,
        "__nativeSetTimeout",
        setTimeoutNative,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "__nativeSetInterval",
        setIntervalNative,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "__nativeClearTimer",
        clearTimerNative,
        null,
    );
}
