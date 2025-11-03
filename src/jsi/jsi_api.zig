const std = @import("std");
const highlights = @import("../config/highlights.zig");

// Import Hermes C API
const c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

/// Zig host function: zigSetHighlight(name, bg, fg)
/// Called from JavaScript: zigSetHighlight('CursorLine', '#2b2b2b', null)
export fn zig_set_highlight(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
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
) callconv(.C) ?*c.OVHermesValue {
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
) callconv(.C) ?*c.OVHermesValue {
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
const TimerData = struct {
    timer: uv.uv_timer_t,
    callback: *c.OVHermesValue, // Cloned JavaScript function
    runtime: *c.OVHermesRuntime,
    is_repeat: bool,
    allocator: std.mem.Allocator,
};

var timer_allocator: std.mem.Allocator = undefined;
var timer_runtime: ?*c.OVHermesRuntime = null;
var timer_initialized = false;

/// Track active timers for cleanup
var active_timers: std.ArrayList(*TimerData) = undefined;
var timers_list_initialized = false;

/// Initialize timer system
pub fn initTimers(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) void {
    timer_allocator = allocator;
    timer_runtime = runtime;
    timer_initialized = true;

    if (!timers_list_initialized) {
        active_timers = std.ArrayList(*TimerData).init(allocator);
        timers_list_initialized = true;
    }
}

/// Clear all active timers (for hot reload)
/// Unlike deinitTimers(), this keeps the timer system initialized
pub fn clearAllTimers() void {
    if (!timer_initialized or !timers_list_initialized) return;

    // Stop and close all active timers
    // Make a copy of the list because onTimerClose will modify active_timers
    const timers_copy = active_timers.clone() catch return;
    defer timers_copy.deinit();

    for (timers_copy.items) |timer_data| {
        _ = uv.uv_timer_stop(&timer_data.timer);
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
    }

    // Run event loop to process close callbacks
    const loop = event_loop.getLoop();
    if (loop) |l| {
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            _ = uv.uv_run(l, uv.UV_RUN_NOWAIT);
        }
    }
}

/// Deinitialize timer system
pub fn deinitTimers() void {
    if (!timer_initialized) return;

    // Clear all active timers first
    clearAllTimers();

    // Now deinitialize the timer system
    active_timers.clearAndFree();
    timer_initialized = false;
    timer_runtime = null;
}

/// libuv timer callback - called when timer fires
fn onTimerFire(handle: [*c]uv.uv_timer_t) callconv(.C) void {
    // Get our timer data from the handle
    const timer_data = @as(*TimerData, @ptrCast(@alignCast(handle.*.data)));

    // Call JavaScript callback
    const result = c.hermes_call_function(timer_data.runtime, timer_data.callback, null, 0);
    if (result != null) {
        c.hermes_value_destroy(result);
    }

    // If this is a one-shot timeout (not interval), clean up
    if (!timer_data.is_repeat) {
        _ = uv.uv_timer_stop(handle);
        uv.uv_close(@ptrCast(handle), onTimerClose);
    }
}

/// libuv close callback - called when timer handle is closed
fn onTimerClose(handle: [*c]uv.uv_handle_t) callconv(.C) void {
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

    // Destroy cloned callback
    c.hermes_value_destroy(timer_data.callback);

    // Free timer data
    timer_data.allocator.destroy(timer_data);
}

/// Zig host function: setTimeout(callback, delay)
export fn zig_set_timeout(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: callback function
    const callback_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    if (!c.hermes_value_is_function(rt, callback_value)) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 1: delay in milliseconds
    const delay_value = args[1] orelse return c.hermes_value_create_undefined(runtime);
    const delay_ms = c.hermes_value_get_number(delay_value);

    if (!timer_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    const loop = event_loop.getLoop() orelse return c.hermes_value_create_undefined(runtime);

    // Clone the callback to create a persistent reference
    const cloned_callback = c.hermes_value_clone(rt, callback_value) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Allocate timer data
    const timer_data = timer_allocator.create(TimerData) catch {
        c.hermes_value_destroy(cloned_callback);
        return c.hermes_value_create_undefined(runtime);
    };

    timer_data.* = TimerData{
        .timer = undefined,
        .callback = cloned_callback,
        .runtime = rt,
        .is_repeat = false,
        .allocator = timer_allocator,
    };

    // Initialize libuv timer
    const init_result = uv.uv_timer_init(loop, &timer_data.timer);
    if (init_result != 0) {
        c.hermes_value_destroy(cloned_callback);
        timer_allocator.destroy(timer_data);
        return c.hermes_value_create_undefined(runtime);
    }

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
    active_timers.append(timer_data) catch {
        // If we can't track it, close it
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
        return c.hermes_value_create_undefined(runtime);
    };

    // Return timer handle as number (for clearTimeout)
    const handle_addr = @intFromPtr(&timer_data.timer);
    return c.hermes_value_create_number(rt, @floatFromInt(handle_addr));
}

/// Zig host function: setInterval(callback, delay)
export fn zig_set_interval(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: callback function
    const callback_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    if (!c.hermes_value_is_function(rt, callback_value)) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 1: delay in milliseconds
    const delay_value = args[1] orelse return c.hermes_value_create_undefined(runtime);
    const delay_ms = c.hermes_value_get_number(delay_value);

    if (!timer_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Get libuv event loop
    const loop = event_loop.getLoop() orelse return c.hermes_value_create_undefined(runtime);

    // Clone the callback to create a persistent reference
    const cloned_callback = c.hermes_value_clone(rt, callback_value) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Allocate timer data on heap
    const timer_data = timer_allocator.create(TimerData) catch {
        c.hermes_value_destroy(cloned_callback);
        return c.hermes_value_create_undefined(runtime);
    };

    timer_data.* = TimerData{
        .timer = undefined,
        .callback = cloned_callback,
        .runtime = rt,
        .is_repeat = true, // This is an interval timer
        .allocator = timer_allocator,
    };

    // Initialize libuv timer handle
    const init_result = uv.uv_timer_init(loop, &timer_data.timer);
    if (init_result != 0) {
        c.hermes_value_destroy(cloned_callback);
        timer_allocator.destroy(timer_data);
        return c.hermes_value_create_undefined(runtime);
    }

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
    active_timers.append(timer_data) catch {
        // If we can't track it, close it
        uv.uv_close(@ptrCast(&timer_data.timer), onTimerClose);
        return c.hermes_value_create_undefined(runtime);
    };

    // Return timer handle address as ID
    const handle_addr = @intFromPtr(&timer_data.timer);
    return c.hermes_value_create_number(rt, @floatFromInt(handle_addr));
}

/// Zig host function: clearTimeout(id) / clearInterval(id)
export fn zig_clear_timer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1 or !timer_initialized) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: timer ID (handle address)
    const id_value = args[0] orelse return c.hermes_value_create_undefined(runtime);
    const handle_addr = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Convert address back to timer handle pointer
    const timer_handle = @as(*uv.uv_timer_t, @ptrFromInt(handle_addr));

    // Stop the timer
    _ = uv.uv_timer_stop(timer_handle);

    // Close the handle (will trigger onTimerClose callback for cleanup)
    uv.uv_close(@ptrCast(timer_handle), onTimerClose);

    return c.hermes_value_create_undefined(runtime);
}

/// Initialize JSI runtime and register host functions
pub fn initJSI(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime, config: *highlights.HighlightConfig) void {
    // Initialize timer system with libuv
    initTimers(allocator, runtime);

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

    // Wrap in vim API setup
    const wrapped_source = try std.fmt.allocPrint(allocator,
        \\// console object (for debugging)
        \\const console = {{
        \\  log: function(...args) {{ zigConsoleLog(...args); }}
        \\}};
        \\
        \\// Timer functions (setTimeout, setInterval, clearTimeout, clearInterval)
        \\function setTimeout(callback, delay) {{
        \\  return zigSetTimeout(callback, delay || 0);
        \\}}
        \\
        \\function setInterval(callback, delay) {{
        \\  return zigSetInterval(callback, delay || 0);
        \\}}
        \\
        \\function clearTimeout(id) {{
        \\  zigClearTimer(id);
        \\}}
        \\
        \\function clearInterval(id) {{
        \\  zigClearTimer(id);
        \\}}
        \\
        \\// vim API object
        \\const vim = {{
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
