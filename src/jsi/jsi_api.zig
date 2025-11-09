const std = @import("std");
const highlights = @import("../config/highlights.zig");
const Display = @import("../display/display.zig").Display;
const Editor = @import("../core/editor.zig").Editor;
const debug_log = @import("../debug/log.zig");

// Import Hermes C API
const c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

/// Context struct for host functions
pub const JSIContext = struct {
    config: *highlights.HighlightConfig,
    display: *Display,
};

/// Global display pointer for virtual text rendering (Neovim-style extmarks)
/// Set during initJSI
var global_display: ?*Display = null;

/// Global editor pointer for console.log forwarding to logger
/// Can be either *Editor or *EditorContext - both have a logger field
/// Set during initJSI - enables Core→Backend logging architecture
var global_editor_with_logger: ?*Editor = null;

/// Global editor context pointer (for headless/debug protocol mode)
const EditorContext = @import("../debug/editor_context.zig").EditorContext;
var global_editor_context: ?*EditorContext = null;

/// Zig host function: setHighlight(name, bg, fg)
/// Called from JavaScript: setHighlight('CursorLine', '#2b2b2b', null)
export fn setHighlight(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Unwrap nullable runtime
    const runtime = runtime_nullable orelse return null;

    // Get config from context
    const config = @as(*highlights.HighlightConfig, @ptrCast(@alignCast(context.?)));

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: highlight name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    // IMPORTANT: Copy the name! hermes_value_get_string() uses a shared buffer
    // that gets overwritten on next call
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    var hl = highlights.Highlight{};

    // Arg 1: background color (string or null)
    if (arg_count > 1 and !c.hermes_value_is_null(args[1])) {
        var bg_len: usize = 0;
        const bg_ptr = c.hermes_value_get_string(runtime, args[1], &bg_len);
        if (bg_ptr != null) {
            const bg_hex = bg_ptr[0..bg_len];
            hl.bg = highlights.Color.fromHex(bg_hex) catch null;
        }
    }

    // Arg 2: foreground color (string or null)
    if (arg_count > 2 and !c.hermes_value_is_null(args[2])) {
        var fg_len: usize = 0;
        const fg_ptr = c.hermes_value_get_string(runtime, args[2], &fg_len);
        if (fg_ptr != null) {
            const fg_hex = fg_ptr[0..fg_len];
            hl.fg = highlights.Color.fromHex(fg_hex) catch null;
        }
    }

    // Apply highlight to config
    config.setHighlight(name, hl);

    // Debug messages sent to Chrome console instead of terminal

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: setOption(name, value)
/// Called from JavaScript: setOption('cursorLine', true)
export fn setOption(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Unwrap nullable runtime
    const runtime = runtime_nullable orelse return null;

    // Get config from context
    const config = @as(*highlights.HighlightConfig, @ptrCast(@alignCast(context.?)));

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: option name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    // Copy the name to avoid shared buffer corruption
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: value (boolean, number, string, etc.)
    // Support both camelCase (cursorLine) and lowercase (cursorline) for backwards compatibility
    if (std.mem.eql(u8, name, "cursorLine") or std.mem.eql(u8, name, "cursorline")) {
        const value = c.hermes_value_get_boolean(args[1]);
        config.cursorline_enabled = value;
    } else if (std.mem.eql(u8, name, "signColumn") or std.mem.eql(u8, name, "signcolumn")) {
        // Get string value for signColumn ("yes", "no", "auto")
        var value_len: usize = 0;
        const value_ptr = c.hermes_value_get_string(runtime, args[1], &value_len);
        if (value_ptr != null) {
            // Store the mode string (will be applied to Display later)
            // Valid values: "yes", "no", "auto"
            if (value_len <= 4) { // "auto" is longest
                if (value_len == 3 and std.mem.eql(u8, value_ptr[0..3], "yes")) {
                    config.signcolumn_mode = "yes";
                } else if (value_len == 4 and std.mem.eql(u8, value_ptr[0..4], "auto")) {
                    config.signcolumn_mode = "auto";
                } else {
                    config.signcolumn_mode = "no";
                }
            }
        }
    }

    return c.hermes_value_create_undefined(runtime);
}

// Import CDP debugger for console.log
const cdp_c = @cImport({
    @cInclude("debug/cdp_debugger.h");
});

/// Zig host function: consoleLog(...args)
/// Called from JavaScript: consoleLog('Hello', 42, {foo: 'bar'})
/// Sends JavaScript values to BOTH Chrome DevTools Console AND editor.logger
/// This follows the Core→Backend logging architecture
export fn consoleLog(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        return c.hermes_value_create_undefined(runtime_nullable);
    }

    const runtime = runtime_nullable orelse return c.hermes_value_create_undefined(runtime_nullable);

    // Send to Chrome debugger if available (Backend 1: Terminal with --debug)
    if (context) |ctx| {
        // Context is CDPDebugger pointer
        const debugger_ptr: *cdp_c.CDPDebugger = @ptrCast(@alignCast(ctx));

        // Pass JavaScript values directly to CDP - let Chrome DevTools format them
        // This properly displays objects, arrays, and all other types
        cdp_c.cdp_debugger_log_values(debugger_ptr, args, arg_count, 0); // 0 = log level
    }

    // ALSO forward to editor.logger for LLM analysis (Backend 2: LLM Debug)
    // Convert JavaScript arguments to a single string
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    for (0..arg_count) |i| {
        if (i > 0) {
            writer.writeAll(" ") catch break;
        }

        const arg = args[i] orelse continue;

        // Convert JavaScript value to string
        if (c.hermes_value_is_string(arg)) {
            var str_len: usize = 0;
            const str_ptr = c.hermes_value_get_string(runtime, arg, &str_len);
            if (str_ptr != null) {
                writer.writeAll(str_ptr[0..str_len]) catch break;
            }
        } else if (c.hermes_value_is_number(arg)) {
            const num = c.hermes_value_get_number(arg);
            std.fmt.format(writer, "{d}", .{num}) catch break;
        } else if (c.hermes_value_is_boolean(arg)) {
            const bool_val = c.hermes_value_get_boolean(arg);
            writer.writeAll(if (bool_val) "true" else "false") catch break;
        } else if (c.hermes_value_is_null(arg)) {
            writer.writeAll("null") catch break;
        } else if (c.hermes_value_is_undefined(arg)) {
            writer.writeAll("undefined") catch break;
        } else {
            // Object/Array - just write [object] for now
            writer.writeAll("[object]") catch break;
        }
    }

    // Forward to logger (info level for console.log)
    // Works with both *Editor and *EditorContext
    const log_message = fbs.getWritten();
    if (global_editor_with_logger) |editor| {
        editor.logger.info("{s}", .{log_message}) catch {};
    } else if (global_editor_context) |ctx| {
        ctx.logger.info("{s}", .{log_message}) catch {};
    }

    return c.hermes_value_create_undefined(runtime_nullable);
}

// ============================================================================
// Timer System (setTimeout, setInterval) - libuv based
// ============================================================================

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

// ============================================================================
// Animation Frame System (requestAnimationFrame)
// ============================================================================

/// Animation frame callback registry
/// Stores callbacks that run on next frame
var animation_callbacks: std.ArrayList(usize) = undefined;  // JS callback IDs
var animation_callbacks_initialized = false;
var animation_frame_modified_layers = false;  // Track if last frame modified layers

/// Initialize animation frame system
fn initAnimationFrames(allocator: std.mem.Allocator) void {
    if (animation_callbacks_initialized) return;
    animation_callbacks = .empty;
    _ = allocator; // Will use timer_allocator for append operations
    animation_callbacks_initialized = true;
}

/// Process all pending animation frame callbacks
/// Called by editor before rendering
/// Returns true if any callbacks were processed AND layers were modified
pub fn processAnimationFrames(allocator: std.mem.Allocator) bool {
    if (!timer_initialized or !animation_callbacks_initialized) return false;
    if (animation_callbacks.items.len == 0) return false;

    const rt = timer_runtime orelse return false;

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
export fn requestAnimationFrame(
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

    if (!timer_initialized or !animation_callbacks_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: callback ID (JavaScript-provided)
    const id_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    const callback_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Queue callback for next frame
    animation_callbacks.append(timer_allocator, callback_id) catch {
        debug_log.log("[RAF] FAILED to queue callback {d}", .{callback_id});
        return c.hermes_value_create_undefined(runtime);
    };

    debug_log.log("[RAF] Queued callback {d} (total queued: {d})", .{ callback_id, animation_callbacks.items.len });

    return c.hermes_value_create_undefined(runtime);
}

/// Initialize timer system
pub fn initTimers(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) void {
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

    // Initialize animation frame system
    initAnimationFrames(allocator);
}

/// Clear all active timers (for hot reload)
/// Unlike deinitTimers(), this keeps the timer system initialized
pub fn clearAllTimers() void {
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
pub fn deinitTimers() void {
    if (!timer_initialized) return;

    // Clear all active timers first
    clearAllTimers();

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
pub fn processTimerQueue(allocator: std.mem.Allocator) void {
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
            c.hermes_object_destroy(global);  // Clean up before continue
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
export fn setTimeout(
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
export fn setInterval(
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
export fn clearTimer(
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

/// Zig host function: zigGetCursorPosition() -> {row, col}
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

/// Zig host function: zigSetCursorRenderPosition(row, col)
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

    return null; // Return undefined
}

/// Zig host function: zigClearCursorRenderPosition()
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

    return null; // Return undefined
}

/// Zig host function: zigDrawVirtualText(row, col, char, fg, bg)
/// Renders a virtual text overlay at screen coordinates (Neovim-style extmark)
/// This is a general primitive - plugins handle coordinate conversion
export fn drawVirtualText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    _ = context;

    if (count < 5) return null;

    const display = global_display orelse return null;

    const row_val = args[0] orelse return null;
    const col_val = args[1] orelse return null;
    const char_val = args[2] orelse return null;
    const fg_val = args[3] orelse return null;
    const bg_val = args[4] orelse return null;

    const row_f = c.hermes_value_get_number(row_val);
    const col_f = c.hermes_value_get_number(col_val);
    const char_f = c.hermes_value_get_number(char_val);

    // NaN/Infinity protection
    if (std.math.isNan(row_f) or std.math.isInf(row_f) or row_f < 0) return null;
    if (std.math.isNan(col_f) or std.math.isInf(col_f) or col_f < 0) return null;
    if (std.math.isNan(char_f) or std.math.isInf(char_f) or char_f < 0) return null;

    const row: usize = @intFromFloat(row_f);
    const col: usize = @intFromFloat(col_f);
    const char: u21 = @intCast(@as(u32, @intFromFloat(char_f)));

    // Parse optional colors (null = use default)
    var fg: ?u24 = null;
    var bg: ?u24 = null;

    if (!c.hermes_value_is_null(fg_val)) {
        const fg_f = c.hermes_value_get_number(fg_val);
        if (!std.math.isNan(fg_f) and !std.math.isInf(fg_f) and fg_f >= 0) {
            fg = @intCast(@as(u32, @intFromFloat(fg_f)));
        }
    }

    if (!c.hermes_value_is_null(bg_val)) {
        const bg_f = c.hermes_value_get_number(bg_val);
        if (!std.math.isNan(bg_f) and !std.math.isInf(bg_f) and bg_f >= 0) {
            bg = @intCast(@as(u32, @intFromFloat(bg_f)));
        }
    }

    // Add virtual text cell to display (Neovim: nvim_buf_set_extmark with virt_text)
    display.virtual_text.addCell(.{
        .row = row,
        .col = col,
        .char = char,
        .fg = fg,
        .bg = bg,
    }) catch return null;

    return null; // Return undefined
}

/// Zig host function: zigClearVirtualText()
/// Clears all virtual text overlays (Neovim: nvim_buf_clear_namespace)
export fn clearVirtualText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    _ = context;
    _ = args;
    _ = count;

    const display = global_display orelse return null;

    // Clear all virtual text cells
    display.virtual_text.clear();

    return null; // Return undefined
}

/// Zig host function: zigGetViewportInfo() -> {top, left, height, width}
/// Returns viewport scroll position and dimensions for coordinate conversion
export fn getViewportInfo(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const display = global_display orelse return null;

    // Create JavaScript object: {top, left, height, width}
    const obj = c.hermes_value_create_object(runtime) orelse return null;

    // Create number values
    const top_val = c.hermes_value_create_number(runtime, @floatFromInt(display.viewport_top));
    const left_val = c.hermes_value_create_number(runtime, @floatFromInt(display.viewport_left));
    const height_val = c.hermes_value_create_number(runtime, @floatFromInt(display.terminal_rows));
    const width_val = c.hermes_value_create_number(runtime, @floatFromInt(display.terminal_cols));

    if (top_val != null and left_val != null and height_val != null and width_val != null) {
        // Set properties on the object
        c.hermes_value_set_property(runtime, obj, "top", top_val);
        c.hermes_value_set_property(runtime, obj, "left", left_val);
        c.hermes_value_set_property(runtime, obj, "height", height_val);
        c.hermes_value_set_property(runtime, obj, "width", width_val);

        // Clean up temporary values
        c.hermes_value_destroy(top_val);
        c.hermes_value_destroy(left_val);
        c.hermes_value_destroy(height_val);
        c.hermes_value_destroy(width_val);
    }

    return obj;
}

/// Zig host function: zigGetGutterWidth() -> number
/// Returns total gutter width (line numbers + signs) for horizontal offset calculation
export fn getGutterWidth(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const display = global_display orelse return null;

    // Get total gutter width
    const gutter_width = display.gutter_manager.getTotalWidth();

    // Return as JavaScript number
    return c.hermes_value_create_number(runtime, @floatFromInt(gutter_width));
}

// ============================================================================
// Generic Virtual Text Layer API (Phase 1)
// ============================================================================

/// Zig host function: createLayer(name, options)
/// JavaScript: createLayer('my_layer', {z_index: 50, opacity: 1.0, cacheable: false})
/// Creates a custom rendering layer for plugins
export fn createLayer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse {
        std.debug.print("[JSI] ERROR: global_display is null!\n", .{});
        return c.hermes_value_create_undefined(runtime);
    };

    if (count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    // Copy name to avoid shared buffer corruption
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: options object {z_index, opacity?, cacheable?}
    if (args[1] == null or !c.hermes_value_is_object(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opts_val = args[1].?;

    // Get z_index (required) - use hermes_value_get_property directly
    const z_index_val = c.hermes_value_get_property(runtime, opts_val, "z_index");
    if (z_index_val == null or !c.hermes_value_is_number(z_index_val)) {
        if (z_index_val != null) c.hermes_value_destroy(z_index_val);
        return c.hermes_value_create_undefined(runtime);
    }
    const z_index: i32 = @intFromFloat(c.hermes_value_get_number(z_index_val));
    c.hermes_value_destroy(z_index_val);

    // Get opacity (optional, default 1.0)
    var opacity: f32 = 1.0;
    const opacity_val = c.hermes_value_get_property(runtime, opts_val, "opacity");
    if (opacity_val != null and c.hermes_value_is_number(opacity_val)) {
        opacity = @floatCast(c.hermes_value_get_number(opacity_val));
        c.hermes_value_destroy(opacity_val);
    } else if (opacity_val != null) {
        c.hermes_value_destroy(opacity_val);
    }

    // Get cacheable (optional, default false)
    var cacheable: bool = false;
    const cacheable_val = c.hermes_value_get_property(runtime, opts_val, "cacheable");
    if (cacheable_val != null and c.hermes_value_is_boolean(cacheable_val)) {
        cacheable = c.hermes_value_get_boolean(cacheable_val);
        c.hermes_value_destroy(cacheable_val);
    } else if (cacheable_val != null) {
        c.hermes_value_destroy(cacheable_val);
    }

    // Create custom layer via LayerManager
    const height = display.terminal_rows;
    const width = display.terminal_cols;

    _ = display.layer_manager.createCustomLayer(
        z_index,
        height,
        width,
        name,
        .{ .opacity = opacity, .cacheable = cacheable },
    ) catch {
        // Layer creation failed (likely ReservedZIndex error)
        std.debug.print("[JSI] ERROR: Failed to create layer '{s}' with z_index={d}\n", .{ name, z_index });
        return c.hermes_value_create_undefined(runtime);
    };

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

/// Zig host function: renderVirtualText(name, cells)
/// JavaScript: renderVirtualText('my_layer', [{row, col, char, fg?, bg?}, ...])
/// Renders cells to a custom layer
export fn renderVirtualText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: cells array (check if it's an object with length property)
    if (args[1] == null or !c.hermes_value_is_object(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Get layer by name
    const layer = display.layer_manager.getLayerByName(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Clear layer before rendering new cells
    layer.clear();

    // Get array length using hermes_value_get_property
    const cells_val = args[1].?;
    const length_val = c.hermes_value_get_property(runtime, cells_val, "length");
    if (length_val == null) return c.hermes_value_create_undefined(runtime);
    const length = @as(usize, @intFromFloat(c.hermes_value_get_number(length_val)));
    c.hermes_value_destroy(length_val);

    // Import Cell type
    const Cell = @import("../display/screen_grid.zig").Cell;
    const Color = @import("../config/highlights.zig").Color;

    // Iterate over cells array
    var i: usize = 0;
    while (i < length) : (i += 1) {
        // Get cell object at index i (convert index to string for property access)
        var idx_buf: [32]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch continue;
        const idx_str_null = std.fmt.bufPrintZ(&idx_buf, "{d}", .{i}) catch continue;
        _ = idx_str;

        const cell_val = c.hermes_value_get_property(runtime, cells_val, idx_str_null.ptr);
        if (cell_val == null or !c.hermes_value_is_object(cell_val)) {
            if (cell_val != null) c.hermes_value_destroy(cell_val);
            continue;
        }

        // Extract cell properties using hermes_value_get_property
        const row_val = c.hermes_value_get_property(runtime, cell_val, "row");
        const col_val = c.hermes_value_get_property(runtime, cell_val, "col");
        const char_val = c.hermes_value_get_property(runtime, cell_val, "char");

        if (row_val == null or col_val == null or char_val == null) {
            if (row_val != null) c.hermes_value_destroy(row_val);
            if (col_val != null) c.hermes_value_destroy(col_val);
            if (char_val != null) c.hermes_value_destroy(char_val);
            c.hermes_value_destroy(cell_val);
            continue;
        }

        const row_f = c.hermes_value_get_number(row_val);
        const col_f = c.hermes_value_get_number(col_val);

        // Validate coordinates
        if (std.math.isNan(row_f) or std.math.isInf(row_f) or row_f < 0 or
            std.math.isNan(col_f) or std.math.isInf(col_f) or col_f < 0)
        {
            c.hermes_value_destroy(row_val);
            c.hermes_value_destroy(col_val);
            c.hermes_value_destroy(char_val);
            c.hermes_value_destroy(cell_val);
            continue;
        }

        const row = @as(usize, @intFromFloat(row_f));
        const col = @as(usize, @intFromFloat(col_f));

        // Get character (could be number codepoint or string)
        var char: u21 = ' ';
        if (c.hermes_value_is_number(char_val)) {
            const char_f = c.hermes_value_get_number(char_val);
            if (!std.math.isNan(char_f) and !std.math.isInf(char_f) and char_f >= 0) {
                char = @intCast(@as(u32, @intFromFloat(char_f)));
            }
        } else if (c.hermes_value_is_string(char_val)) {
            var char_len: usize = 0;
            const char_ptr = c.hermes_value_get_string(runtime, char_val, &char_len);
            if (char_ptr != null and char_len > 0) {
                char = @intCast(char_ptr[0]);
            }
        }

        // Get optional fg/bg colors (null or hex number)
        var fg: ?Color = null;
        var bg: ?Color = null;

        const fg_val = c.hermes_value_get_property(runtime, cell_val, "fg");
        if (fg_val != null and !c.hermes_value_is_null(fg_val)) {
            if (c.hermes_value_is_number(fg_val)) {
                const fg_num = c.hermes_value_get_number(fg_val);
                if (!std.math.isNan(fg_num) and !std.math.isInf(fg_num)) {
                    const rgb: u24 = @intCast(@as(u32, @intFromFloat(fg_num)));
                    fg = Color{
                        .r = @intCast((rgb >> 16) & 0xFF),
                        .g = @intCast((rgb >> 8) & 0xFF),
                        .b = @intCast(rgb & 0xFF),
                    };
                }
            }
            c.hermes_value_destroy(fg_val);
        } else if (fg_val != null) {
            c.hermes_value_destroy(fg_val);
        }

        const bg_val = c.hermes_value_get_property(runtime, cell_val, "bg");
        if (bg_val != null and !c.hermes_value_is_null(bg_val)) {
            if (c.hermes_value_is_number(bg_val)) {
                const bg_num = c.hermes_value_get_number(bg_val);
                if (!std.math.isNan(bg_num) and !std.math.isInf(bg_num)) {
                    const rgb: u24 = @intCast(@as(u32, @intFromFloat(bg_num)));
                    bg = Color{
                        .r = @intCast((rgb >> 16) & 0xFF),
                        .g = @intCast((rgb >> 8) & 0xFF),
                        .b = @intCast(rgb & 0xFF),
                    };
                }
            }
            c.hermes_value_destroy(bg_val);
        } else if (bg_val != null) {
            c.hermes_value_destroy(bg_val);
        }

        // Set cell in layer grid
        layer.grid.setCell(row, col, Cell{ .char = char, .fg = fg, .bg = bg });

        // Cleanup
        c.hermes_value_destroy(row_val);
        c.hermes_value_destroy(col_val);
        c.hermes_value_destroy(char_val);
        c.hermes_value_destroy(cell_val);
    }

    // Mark layer as dirty to trigger re-composition
    layer.markDirty();

    // Mark that this animation frame modified layers (triggers re-render)
    // This is safe because renderVirtualText ALWAYS renders content
    animation_frame_modified_layers = true;

    // Debug: Log rendering (to debug log, not terminal)
    debug_log.log("[JSI] renderVirtualText('{s}') - rendered {d} cells, marked dirty", .{ name, length });

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: setLayerOpacity(name, opacity)
/// JavaScript: setLayerOpacity('my_layer', 0.5)
/// Updates layer opacity for fade effects
export fn setLayerOpacity(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: opacity (number)
    if (args[1] == null or !c.hermes_value_is_number(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opacity_f = c.hermes_value_get_number(args[1]);
    if (std.math.isNan(opacity_f) or std.math.isInf(opacity_f)) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opacity: f32 = @floatCast(opacity_f);

    // Get layer by name
    const layer = display.layer_manager.getLayerByName(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Update opacity
    layer.setOpacity(opacity);

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: zigClearVirtualText(name)
/// JavaScript: zigClearVirtualText('my_layer')
/// Clears layer content (keeps layer alive)
export fn clearLayer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Get layer by name
    const layer = display.layer_manager.getLayerByName(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Check if layer has actual content before clearing
    // This is critical to prevent flickering - don't mark dirty if clearing empty layer
    const had_content = layer.grid.hasContent();

    // Clear layer content
    layer.clear();

    // Only mark animation frame dirty if layer actually had content to clear
    // This prevents idle flickering when clearing already-empty layers
    if (had_content) {
        animation_frame_modified_layers = true;
        debug_log.log("[JSI] clearLayer('{s}') - had content, marked dirty", .{name});
    } else {
        debug_log.log("[JSI] clearLayer('{s}') - was empty, NOT marking dirty", .{name});
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: destroyLayer(name)
/// JavaScript: destroyLayer('my_layer')
/// Destroys layer and frees resources
export fn destroyLayer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Destroy layer via LayerManager
    display.layer_manager.destroyCustomLayer(name) catch {
        // Layer not found or cannot destroy core layer
        return c.hermes_value_create_undefined(runtime);
    };

    return c.hermes_value_create_undefined(runtime);
}

/// Initialize JSI runtime and register host functions
/// editor_or_context can be either *Editor or *EditorContext - both have logger field
pub fn initJSI(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime, config: *highlights.HighlightConfig, editor_or_context: anytype, display: ?*Display) void {
    // Initialize timer system with libuv
    initTimers(allocator, runtime);

    // Set global display pointer for trail rendering (may be null in headless mode)
    global_display = display;

    // Set global editor pointer for console.log → logger forwarding
    // Supports both *Editor and *EditorContext
    const T = @TypeOf(editor_or_context);
    if (T == *Editor) {
        global_editor_with_logger = editor_or_context;
        global_editor_context = null;
    } else if (T == *EditorContext) {
        global_editor_context = editor_or_context;
        global_editor_with_logger = null;
    }

    // Register Zig functions that JavaScript can call
    // Pass config pointer as context so host functions can access it
    c.hermes_register_host_function(
        runtime,
        "setHighlight",
        setHighlight,
        @ptrCast(config), // Pass config as context
    );

    c.hermes_register_host_function(
        runtime,
        "setOption",
        setOption,
        @ptrCast(config), // Pass config as context
    );

    c.hermes_register_host_function(
        runtime,
        "consoleLog",
        consoleLog,
        null, // No context needed
    );

    // Register timer functions with internal names to avoid recursion
    // JavaScript wrapper will call these and provide the user-facing API
    c.hermes_register_host_function(
        runtime,
        "__nativeSetTimeout",
        setTimeout,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "__nativeSetInterval",
        setInterval,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "__nativeClearTimer",
        clearTimer,
        null,
    );

    // Register animation frame API (native render loop integration)
    c.hermes_register_host_function(
        runtime,
        "__nativeRequestAnimationFrame",
        requestAnimationFrame,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "__nativeMarkAnimationFrameDirty",
        markAnimationFrameDirty,
        null,
    );

    // Register cursor position hooks (for animated cursor plugins)
    c.hermes_register_host_function(
        runtime,
        "getCursorPosition",
        getCursorPosition,
        @ptrCast(editor_or_context),
    );

    c.hermes_register_host_function(
        runtime,
        "setCursorRenderPosition",
        setCursorRenderPosition,
        @ptrCast(editor_or_context),
    );

    c.hermes_register_host_function(
        runtime,
        "clearCursorRenderPosition",
        clearCursorRenderPosition,
        @ptrCast(editor_or_context),
    );

    // Register virtual text renderer (Neovim-style extmarks)
    // General primitive - any plugin can use this
    c.hermes_register_host_function(
        runtime,
        "drawVirtualText",
        drawVirtualText,
        @ptrCast(editor_or_context),
    );

    c.hermes_register_host_function(
        runtime,
        "clearVirtualText",
        clearVirtualText,
        @ptrCast(editor_or_context),
    );

    // Register viewport/gutter helpers (for coordinate conversion)
    c.hermes_register_host_function(
        runtime,
        "getViewportInfo",
        getViewportInfo,
        @ptrCast(editor_or_context),
    );

    c.hermes_register_host_function(
        runtime,
        "getGutterWidth",
        getGutterWidth,
        @ptrCast(editor_or_context),
    );

    // Register generic virtual text layer API (Phase 1)
    c.hermes_register_host_function(
        runtime,
        "createLayer",
        createLayer,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "renderVirtualText",
        renderVirtualText,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "setLayerOpacity",
        setLayerOpacity,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "clearVirtualText",
        clearLayer,
        null,
    );

    // Also register as clearLayer for backwards compatibility
    c.hermes_register_host_function(
        runtime,
        "clearLayer",
        clearLayer,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "destroyLayer",
        destroyLayer,
        null,
    );

    // JSI functions registered (silent mode)
}

/// Re-register console.log with debugger pointer
/// This should be called after debugger is created to enable Chrome Console output
pub fn registerConsoleWithDebugger(runtime: *c.OVHermesRuntime, debugger_ptr: *anyopaque) void {
    c.hermes_register_host_function(
        runtime,
        "consoleLog",
        consoleLog,
        debugger_ptr, // Pass debugger as context
    );
}

/// Compile JavaScript to Hermes bytecode using hermesc
fn compileJsToBytecode(js_path: []const u8, hbc_path: []const u8) !void {
    // Run hermesc to compile JS to bytecode
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{
            "vendor/hermes/build/bin/hermesc",
            "-emit-binary",
            "-out",
            hbc_path,
            js_path,
        },
    }) catch |err| {
        std.debug.print("[JSI] Failed to run hermesc: {}\n", .{err});
        return err;
    };
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        // Keep stderr errors for hermesc failures (critical)
        std.debug.print("[JSI] hermesc failed:\n{s}\n", .{result.stderr});
        return error.CompilationFailed;
    }

    // Compilation successful (silent mode)
}

/// Check if file needs recompilation (returns true if hbc is missing or older than js)
fn needsRecompilation(js_path: []const u8, hbc_path: []const u8) bool {
    const js_file = std.fs.openFileAbsolute(js_path, .{}) catch return true;
    defer js_file.close();

    const hbc_file = std.fs.openFileAbsolute(hbc_path, .{}) catch return true;
    defer hbc_file.close();

    const js_stat = js_file.stat() catch return true;
    const hbc_stat = hbc_file.stat() catch return true;

    // Compare modification times (need recompile if js is newer)
    return js_stat.mtime > hbc_stat.mtime;
}

/// Load and execute JavaScript plugin file (NO wrapper - uses existing globals)
pub fn loadPlugin(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Read plugin source
    const file = std.fs.openFileAbsolute(filepath, .{}) catch |err| {
        std.debug.print("[JSI] Could not open plugin file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1_000_000);
    defer allocator.free(source);

    // Bytecode path (no .wrapped.js for plugins!)
    const hbc_path = try std.fmt.allocPrint(allocator, "{s}.hbc", .{filepath});
    defer allocator.free(hbc_path);

    // Compile if needed
    if (needsRecompilation(filepath, hbc_path)) {
        try compileJsToBytecode(filepath, hbc_path);
    }

    // Load and execute bytecode
    const hbc_file = try std.fs.openFileAbsolute(hbc_path, .{});
    defer hbc_file.close();

    const bytecode = try hbc_file.readToEndAlloc(allocator, 10_000_000);
    defer allocator.free(bytecode);

    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[JSI] Plugin error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
}

/// Load and execute JavaScript configuration file (via bytecode)
pub fn loadConfig(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Loading config (silent mode)

    // Read source to wrap it with vim API
    const file = std.fs.openFileAbsolute(filepath, .{}) catch |err| {
        // Keep critical errors
        std.debug.print("[JSI] Could not open config file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1_000_000);
    defer allocator.free(source);

    // Load runtime wrapper at compile time
    const runtime_wrapper = @embedFile("runtime.js");

    // Wrap user config with runtime wrapper
    const wrapped_source = try std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\// User config
        \\{s}
    , .{ runtime_wrapper, source });
    defer allocator.free(wrapped_source);

    // Write wrapped source to temp file for compilation
    const temp_js_path = try std.fmt.allocPrint(allocator, "{s}.wrapped.js", .{filepath});
    defer allocator.free(temp_js_path);

    const temp_js_file = try std.fs.createFileAbsolute(temp_js_path, .{});
    defer temp_js_file.close();
    try temp_js_file.writeAll(wrapped_source);

    // Bytecode path
    const hbc_path = try std.fmt.allocPrint(allocator, "{s}.hbc", .{filepath});
    defer allocator.free(hbc_path);

    // Compile if needed (check if wrapped.js is newer than hbc)
    if (needsRecompilation(temp_js_path, hbc_path)) {
        // Compiling to bytecode (silent mode)
        try compileJsToBytecode(temp_js_path, hbc_path);
    }

    // Load bytecode
    const hbc_file = try std.fs.openFileAbsolute(hbc_path, .{});
    defer hbc_file.close();

    const bytecode = try hbc_file.readToEndAlloc(allocator, 10_000_000);
    defer allocator.free(bytecode);

    // Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        // Keep critical errors
        std.debug.print("[JSI] JavaScript error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
    // Config loaded successfully (silent mode)
}
