const std = @import("std");
const highlights = @import("../config/highlights.zig");
const Display = @import("../display/display.zig").Display;
const Editor = @import("../core/editor.zig").Editor;

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

/// Zig host function: zigSetHighlight(name, bg, fg)
/// Called from JavaScript: zigSetHighlight('CursorLine', '#2b2b2b', null)
export fn zig_set_highlight(
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

/// Zig host function: zigSetOption(name, value)
/// Called from JavaScript: zigSetOption('cursorLine', true)
export fn zig_set_option(
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

/// Zig host function: zigConsoleLog(...args)
/// Called from JavaScript: zigConsoleLog('Hello', 42, {foo: 'bar'})
/// Sends JavaScript values directly to Chrome DevTools Console
/// This follows React Native's approach - pass raw values and let Chrome format them
export fn zig_console_log(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        return c.hermes_value_create_undefined(runtime_nullable);
    }

    // Send to Chrome debugger if available
    if (context) |ctx| {
        // Context is CDPDebugger pointer
        const debugger_ptr: *cdp_c.CDPDebugger = @ptrCast(@alignCast(ctx));

        // Pass JavaScript values directly to CDP - let Chrome DevTools format them
        // This properly displays objects, arrays, and all other types
        cdp_c.cdp_debugger_log_values(debugger_ptr, args, arg_count, 0); // 0 = log level
    }
    // If no debugger, console.log does nothing (silent mode)

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

/// Zig host function: zigSetTimeout(id, delay)
/// React Native pattern: JavaScript provides timer ID, not callback
/// JavaScript keeps the callback in its own registry
export fn zig_set_timeout(
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

/// Zig host function: zigSetInterval(id, delay)
/// React Native pattern: JavaScript provides timer ID, not callback
/// JavaScript keeps the callback in its own registry
export fn zig_set_interval(
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

/// Zig host function: zigClearTimer(id)
/// React Native pattern: Find timer by JavaScript-provided ID
export fn zig_clear_timer(
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
export fn zig_get_cursor_position(
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
export fn zig_set_cursor_render_position(
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
export fn zig_clear_cursor_render_position(
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
export fn zig_draw_virtual_text(
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
export fn zig_clear_virtual_text(
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
export fn zig_get_viewport_info(
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
export fn zig_get_gutter_width(
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

/// Initialize JSI runtime and register host functions
pub fn initJSI(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime, config: *highlights.HighlightConfig, editor: *Editor, display: ?*Display) void {
    // Initialize timer system with libuv
    initTimers(allocator, runtime);

    // Set global display pointer for trail rendering (may be null in headless mode)
    global_display = display;

    // Register Zig functions that JavaScript can call
    // Pass config pointer as context so host functions can access it
    c.hermes_register_host_function(
        runtime,
        "zigSetHighlight",
        zig_set_highlight,
        @ptrCast(config), // Pass config as context
    );

    c.hermes_register_host_function(
        runtime,
        "zigSetOption",
        zig_set_option,
        @ptrCast(config), // Pass config as context
    );

    c.hermes_register_host_function(
        runtime,
        "zigConsoleLog",
        zig_console_log,
        null, // No context needed
    );

    // Register timer functions
    c.hermes_register_host_function(
        runtime,
        "zigSetTimeout",
        zig_set_timeout,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "zigSetInterval",
        zig_set_interval,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "zigClearTimer",
        zig_clear_timer,
        null,
    );

    // Register cursor position hooks (for animated cursor plugins)
    c.hermes_register_host_function(
        runtime,
        "zigGetCursorPosition",
        zig_get_cursor_position,
        @ptrCast(editor),
    );

    c.hermes_register_host_function(
        runtime,
        "zigSetCursorRenderPosition",
        zig_set_cursor_render_position,
        @ptrCast(editor),
    );

    c.hermes_register_host_function(
        runtime,
        "zigClearCursorRenderPosition",
        zig_clear_cursor_render_position,
        @ptrCast(editor),
    );

    // Register virtual text renderer (Neovim-style extmarks)
    // General primitive - any plugin can use this
    c.hermes_register_host_function(
        runtime,
        "zigDrawVirtualText",
        zig_draw_virtual_text,
        @ptrCast(editor),
    );

    c.hermes_register_host_function(
        runtime,
        "zigClearVirtualText",
        zig_clear_virtual_text,
        @ptrCast(editor),
    );

    // Register viewport/gutter helpers (for coordinate conversion)
    c.hermes_register_host_function(
        runtime,
        "zigGetViewportInfo",
        zig_get_viewport_info,
        @ptrCast(editor),
    );

    c.hermes_register_host_function(
        runtime,
        "zigGetGutterWidth",
        zig_get_gutter_width,
        @ptrCast(editor),
    );

    // JSI functions registered (silent mode)
}

/// Re-register console.log with debugger pointer
/// This should be called after debugger is created to enable Chrome Console output
pub fn registerConsoleWithDebugger(runtime: *c.OVHermesRuntime, debugger_ptr: *anyopaque) void {
    c.hermes_register_host_function(
        runtime,
        "zigConsoleLog",
        zig_console_log,
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

    // Wrap in vim API setup (React Native style)
    const wrapped_source = try std.fmt.allocPrint(allocator,
        \\// console object (for debugging) - make it global for plugins!
        \\globalThis.console = {{
        \\  log: function(...args) {{ zigConsoleLog(...args); }}
        \\}};
        \\
        \\// Timer Registry (React Native pattern - keeps callbacks alive in JS!)
        \\// This prevents garbage collection of timer callbacks
        \\// Make these global so plugins can use setTimeout/setInterval!
        \\globalThis._timerCallbacks = {{}};
        \\globalThis._nextTimerId = 1;
        \\
        \\// Timer functions (setTimeout, setInterval, clearTimeout, clearInterval)
        \\// Make them global so plugins can use them!
        \\globalThis.setTimeout = function(callback, delay) {{
        \\  const id = globalThis._nextTimerId++;
        \\  globalThis._timerCallbacks[id] = callback;
        \\  zigSetTimeout(id, delay || 0);
        \\  return id;
        \\}};
        \\
        \\globalThis.setInterval = function(callback, delay) {{
        \\  const id = globalThis._nextTimerId++;
        \\  globalThis._timerCallbacks[id] = callback;
        \\  zigSetInterval(id, delay || 0);
        \\  return id;
        \\}};
        \\
        \\globalThis.clearTimeout = function(id) {{
        \\  delete globalThis._timerCallbacks[id];
        \\  zigClearTimer(id);
        \\}};
        \\
        \\globalThis.clearInterval = function(id) {{
        \\  delete globalThis._timerCallbacks[id];
        \\  zigClearTimer(id);
        \\}};
        \\
        \\// Called by native code when timer fires
        \\globalThis.__handleTimerCallback = function(id) {{
        \\  const callback = globalThis._timerCallbacks[id];
        \\  if (callback) {{
        \\    try {{
        \\      callback();
        \\    }} catch (e) {{
        \\      globalThis.console.log('Timer callback error:', e);
        \\    }}
        \\  }}
        \\}};
        \\
        \\// Performance API (React Native style)
        \\// This enables Chrome DevTools Performance timeline!
        \\globalThis.performance = {{
        \\  _marks: {{}},
        \\  _measures: [],
        \\  now: function() {{
        \\    return Date.now(); // Milliseconds since epoch
        \\  }},
        \\  mark: function(name) {{
        \\    this._marks[name] = this.now();
        \\  }},
        \\  measure: function(name, startMark, endMark) {{
        \\    const start = this._marks[startMark] || 0;
        \\    const end = endMark ? (this._marks[endMark] || this.now()) : this.now();
        \\    const duration = end - start;
        \\    this._measures.push({{ name, duration, startTime: start }});
        \\  }},
        \\  clearMarks: function(name) {{
        \\    if (name) delete this._marks[name];
        \\    else this._marks = {{}};
        \\  }},
        \\  getEntriesByType: function(type) {{
        \\    if (type === 'measure') return this._measures;
        \\    return [];
        \\  }}
        \\}};
        \\
        \\// vim API object - make it global for plugins!
        \\globalThis.vim = {{
        \\  highlight: function(name, opts) {{
        \\    const bg = opts.bg || null;
        \\    const fg = opts.fg || null;
        \\    zigSetHighlight(name, bg, fg);
        \\  }},
        \\  opt: {{
        \\    set cursorLine(value) {{ zigSetOption('cursorLine', value); }},
        \\    get cursorLine() {{ return true; }}
        \\  }}
        \\}};
        \\
        \\// User config
        \\{s}
    , .{source});
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
