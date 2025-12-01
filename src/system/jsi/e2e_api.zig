/// E2E API - End-to-End Testing and Plugin Development Debugging API
///
/// This module provides the vim.e2e JavaScript API for:
/// 1. E2E tests - Full stack testing with real editor state
/// 2. Plugin development - Interactive debugging during development
///
/// Architecture:
/// - JavaScript calls vim.e2e.* methods
/// - Methods execute synchronously via JSI (same process)
/// - State queries return current editor state
/// - vim.e2e.keys() simulates actual keystrokes
///
/// This is NOT the debug protocol (stdin/stdout JSON-RPC).
/// This runs IN-PROCESS for fast, synchronous access.
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;
const helpers = @import("helpers.zig");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const ModeManager = @import("../../editor/mode/mode.zig").ModeManager;
const VisualState = @import("../../editor/visual/visual.zig").VisualState;
const RegisterManager = @import("../../editor/register/register.zig").RegisterManager;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const animation_api = @import("animation_api.zig");

/// E2E Context - holds references to editor state
pub const E2EContext = struct {
    allocator: std.mem.Allocator,
    /// Function pointer to get current buffer (dynamically, not stale pointer!)
    /// This is critical for multi-window support (splits)
    get_current_buffer_fn: *const fn (*anyopaque) ?*Buffer,
    mode_manager: *ModeManager,
    visual_state: *VisualState,
    register_mgr: *RegisterManager,
    /// Editor reference for executeKeys and getCurrentBuffer
    editor: *anyopaque,
    /// Function pointer to execute keys on editor
    execute_keys_fn: *const fn (*anyopaque, []const u8) anyerror!void,
    /// js_state_dirty flag for triggering re-renders
    js_state_dirty: ?*bool,
    /// Display reference for PTY capture (optional for backwards compatibility)
    display: ?*Display = null,

    /// Get the current buffer (dynamically fetched, not cached)
    /// Returns null if no buffer is active
    pub fn getCurrentBuffer(self: *E2EContext) ?*Buffer {
        return self.get_current_buffer_fn(self.editor);
    }
};

/// Global context (set during registration)
var global_e2e_ctx: ?*E2EContext = null;

// ============================================================================
// State Query Functions (synchronous)
// ============================================================================

/// vim.e2e.getCursor() -> { line: number, col: number }
fn getCursor(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const buffer = ctx.getCurrentBuffer() orelse return helpers.returnUndefined(runtime);

    // Create result object { line: n, col: n }
    const result = c.hermes_value_create_object(runtime) orelse return helpers.returnUndefined(runtime);
    const line_val = c.hermes_value_create_number(runtime, @floatFromInt(buffer.cursor.row));
    const col_val = c.hermes_value_create_number(runtime, @floatFromInt(buffer.cursor.col));

    if (line_val != null and col_val != null) {
        c.hermes_value_set_property(runtime, result, "line", line_val);
        c.hermes_value_set_property(runtime, result, "col", col_val);
        c.hermes_value_destroy(line_val);
        c.hermes_value_destroy(col_val);
    }

    return result;
}

/// vim.e2e.getMode() -> string ("NORMAL" | "INSERT" | "VISUAL" | "COMMAND")
fn getMode(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const mode_str = ctx.mode_manager.getModeString();
    return c.hermes_value_create_string(runtime, mode_str.ptr, mode_str.len);
}

/// vim.e2e.getState() -> { mode, cursor, visual, buffer, registers }
fn getState(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const buffer = ctx.getCurrentBuffer() orelse return helpers.returnUndefined(runtime);
    const allocator = ctx.allocator;

    // Create result object
    const result = c.hermes_value_create_object(runtime) orelse return helpers.returnUndefined(runtime);

    // mode
    const mode_str = ctx.mode_manager.getModeString();
    const mode_val = c.hermes_value_create_string(runtime, mode_str.ptr, mode_str.len);
    if (mode_val) |mv| {
        c.hermes_value_set_property(runtime, result, "mode", mv);
        c.hermes_value_destroy(mv);
    }

    // cursor
    const cursor_obj = c.hermes_value_create_object(runtime);
    if (cursor_obj) |co| {
        const line_val = c.hermes_value_create_number(runtime, @floatFromInt(buffer.cursor.row));
        const col_val = c.hermes_value_create_number(runtime, @floatFromInt(buffer.cursor.col));
        if (line_val) |lv| {
            c.hermes_value_set_property(runtime, co, "line", lv);
            c.hermes_value_destroy(lv);
        }
        if (col_val) |cv| {
            c.hermes_value_set_property(runtime, co, "col", cv);
            c.hermes_value_destroy(cv);
        }
        c.hermes_value_set_property(runtime, result, "cursor", co);
        c.hermes_value_destroy(co);
    }

    // visual
    const visual_obj = c.hermes_value_create_object(runtime);
    if (visual_obj) |vo| {
        const active_val = c.hermes_value_create_boolean(runtime, ctx.visual_state.active);
        if (active_val) |av| {
            c.hermes_value_set_property(runtime, vo, "active", av);
            c.hermes_value_destroy(av);
        }
        if (ctx.visual_state.active) {
            const visual_mode = switch (ctx.visual_state.mode) {
                .char => "char",
                .line => "line",
                .block => "block",
            };
            const mode_v = c.hermes_value_create_string(runtime, visual_mode.ptr, visual_mode.len);
            if (mode_v) |m| {
                c.hermes_value_set_property(runtime, vo, "mode", m);
                c.hermes_value_destroy(m);
            }

            const anchor_obj = c.hermes_value_create_object(runtime);
            if (anchor_obj) |ao| {
                const anchor_line = c.hermes_value_create_number(runtime, @floatFromInt(ctx.visual_state.anchor.line));
                const anchor_col = c.hermes_value_create_number(runtime, @floatFromInt(ctx.visual_state.anchor.col));
                if (anchor_line) |al| {
                    c.hermes_value_set_property(runtime, ao, "line", al);
                    c.hermes_value_destroy(al);
                }
                if (anchor_col) |ac| {
                    c.hermes_value_set_property(runtime, ao, "col", ac);
                    c.hermes_value_destroy(ac);
                }
                c.hermes_value_set_property(runtime, vo, "anchor", ao);
                c.hermes_value_destroy(ao);
            }
        }
        c.hermes_value_set_property(runtime, result, "visual", vo);
        c.hermes_value_destroy(vo);
    }

    // buffer
    const buffer_obj = c.hermes_value_create_object(runtime);
    if (buffer_obj) |bo| {
        const modified_val = c.hermes_value_create_boolean(runtime, buffer.modified);
        if (modified_val) |mv| {
            c.hermes_value_set_property(runtime, bo, "modified", mv);
            c.hermes_value_destroy(mv);
        }
        const line_count_val = c.hermes_value_create_number(runtime, @floatFromInt(buffer.lineCount()));
        if (line_count_val) |lcv| {
            c.hermes_value_set_property(runtime, bo, "lineCount", lcv);
            c.hermes_value_destroy(lcv);
        }

        // buffer.lines (array of strings)
        const line_count = buffer.lineCount();
        const lines_arr = c.hermes_array_create(runtime, line_count);
        if (lines_arr) |la| {
            for (0..line_count) |i| {
                if (buffer.getLine(i)) |line| {
                    defer allocator.free(line);
                    // Remove trailing newline for cleaner API
                    const trimmed = if (line.len > 0 and line[line.len - 1] == '\n')
                        line[0 .. line.len - 1]
                    else
                        line;
                    const line_val = c.hermes_value_create_string(runtime, trimmed.ptr, trimmed.len);
                    if (line_val) |lv| {
                        c.hermes_array_set(runtime, la, i, lv);
                        c.hermes_value_destroy(lv);
                    }
                }
            }
            c.hermes_value_set_property(runtime, bo, "lines", la);
            c.hermes_value_destroy(la);
        }
        c.hermes_value_set_property(runtime, result, "buffer", bo);
        c.hermes_value_destroy(bo);
    }

    return result;
}

/// vim.e2e.getBufferContent() -> string
fn getBufferContent(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const buffer = ctx.getCurrentBuffer() orelse return helpers.returnUndefined(runtime);

    // Get full buffer content
    const content = buffer.content.toString() catch return helpers.returnUndefined(runtime);
    defer buffer.content.allocator.free(content);

    return c.hermes_value_create_string(runtime, content.ptr, content.len);
}

/// vim.e2e.getLine(line_num) -> string
fn getLine(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const buffer = ctx.getCurrentBuffer() orelse return helpers.returnUndefined(runtime);

    if (arg_count < 1) return helpers.returnUndefined(runtime);

    const arg = args[0] orelse return helpers.returnUndefined(runtime);
    const line_num = helpers.extractNumberArg(runtime.?, arg) catch return helpers.returnUndefined(runtime);
    const line_idx: usize = @intFromFloat(line_num);

    if (buffer.getLine(line_idx)) |line| {
        defer ctx.allocator.free(line);
        // Remove trailing newline
        const trimmed = if (line.len > 0 and line[line.len - 1] == '\n')
            line[0 .. line.len - 1]
        else
            line;
        return c.hermes_value_create_string(runtime, trimmed.ptr, trimmed.len);
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.getLayers() -> array of layer objects
/// Returns information about all display layers for debugging compositor state
fn getLayersCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        // No display available - return empty array
        return c.hermes_array_create(runtime, 0);
    };

    // Get layers from layer manager
    const layers = display.layer_manager.layers.items;

    // Create result array
    const result = c.hermes_array_create(runtime, layers.len) orelse return helpers.returnUndefined(runtime);

    for (layers, 0..) |layer, i| {
        // Create layer object
        const layer_obj = c.hermes_value_create_object(runtime) orelse continue;

        // id
        const id_val = c.hermes_value_create_number(runtime, @floatFromInt(layer.id));
        if (id_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "id", v);
            c.hermes_value_destroy(v);
        }

        // name
        const name_val = c.hermes_value_create_string(runtime, layer.name.ptr, layer.name.len);
        if (name_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "name", v);
            c.hermes_value_destroy(v);
        }

        // z_index
        const z_val = c.hermes_value_create_number(runtime, @floatFromInt(layer.z_index));
        if (z_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "zIndex", v);
            c.hermes_value_destroy(v);
        }

        // enabled
        const enabled_val = c.hermes_value_create_boolean(runtime, layer.enabled);
        if (enabled_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "enabled", v);
            c.hermes_value_destroy(v);
        }

        // opacity
        const opacity_val = c.hermes_value_create_number(runtime, layer.opacity);
        if (opacity_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "opacity", v);
            c.hermes_value_destroy(v);
        }

        // dirty
        const dirty_val = c.hermes_value_create_boolean(runtime, layer.dirty);
        if (dirty_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "dirty", v);
            c.hermes_value_destroy(v);
        }

        // width
        const width_val = c.hermes_value_create_number(runtime, @floatFromInt(layer.grid.width));
        if (width_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "width", v);
            c.hermes_value_destroy(v);
        }

        // height
        const height_val = c.hermes_value_create_number(runtime, @floatFromInt(layer.grid.height));
        if (height_val) |v| {
            c.hermes_value_set_property(runtime, layer_obj, "height", v);
            c.hermes_value_destroy(v);
        }

        c.hermes_array_set(runtime, result, i, layer_obj);
        c.hermes_value_destroy(layer_obj);
    }

    return result;
}

/// vim.e2e.getLogs(opts?) -> array of log strings
/// Returns captured console.log entries from current test
/// opts.level: optional filter by log level (not used for console.log captures)
/// opts.maxBytes: optional max response size (default unlimited)
fn getLogsCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    // Return the captured console.log entries from current test
    const logs = current_test_logs.items;

    // Create result array
    const result = c.hermes_array_create(runtime, logs.len) orelse return helpers.returnUndefined(runtime);

    for (logs, 0..) |log, i| {
        const log_val = c.hermes_value_create_string(runtime, log.ptr, log.len);
        if (log_val) |v| {
            c.hermes_array_set(runtime, result, i, v);
            c.hermes_value_destroy(v);
        }
    }

    _ = ctx;
    return result;
}

// ============================================================================
// Command Functions
// ============================================================================

/// vim.e2e.keys(keys_string) -> void
/// Simulates keystrokes in the editor (synchronous)
fn keysCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    if (arg_count < 1) return helpers.returnUndefined(runtime);

    // Get keys string
    var len: usize = 0;
    const keys_ptr = c.hermes_value_get_string(runtime, args[0], &len);
    if (keys_ptr == null or len == 0) return helpers.returnUndefined(runtime);

    const keys_str = keys_ptr[0..len];

    // Execute keys via editor
    ctx.execute_keys_fn(ctx.editor, keys_str) catch |err| {
        std.debug.print("[E2E] keys() error: {}\n", .{err});
        return helpers.returnUndefined(runtime);
    };

    // Mark state dirty for re-render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.tick(iterations?) -> number
/// Process event loop iterations (timers, animation frames)
/// This allows setTimeout/setInterval callbacks to fire during tests
/// Returns number of timer callbacks processed
fn tickCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    // Get optional iteration count (default 10)
    var iterations: usize = 10;
    if (arg_count >= 1) {
        if (args[0]) |arg| {
            if (c.hermes_value_is_number(arg)) {
                iterations = @intFromFloat(c.hermes_value_get_number(arg));
            }
        }
    }

    // Import timer, fetch, and event loop modules
    const event_loop = @import("../event_loop/libuv.zig");
    const timer_api = @import("timer_api.zig");
    const fetch_api = @import("fetch_api.zig");

    // Process event loop multiple times to give timers/fetch a chance to fire
    for (0..iterations) |_| {
        // Run libuv event loop (non-blocking)
        // This handles OS-level async operations (including fetch HTTP requests)
        _ = event_loop.runOnce();

        // Process timer callbacks
        timer_api.processQueue(ctx.allocator);

        // Process fetch callbacks (async HTTP responses)
        fetch_api.processQueue(ctx.allocator);

        // Small sleep to allow timers/network requests to mature
        std.Thread.sleep(1_000_000); // 1ms
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.wait(ms) -> void
/// Wait for specified milliseconds while processing event loop
/// More convenient than tick() for timing-based tests
fn waitCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    // Get wait time in ms (default 50ms)
    var wait_ms: u64 = 50;
    if (arg_count >= 1) {
        if (args[0]) |arg| {
            if (c.hermes_value_is_number(arg)) {
                wait_ms = @intFromFloat(c.hermes_value_get_number(arg));
            }
        }
    }

    // Import timer, fetch, and event loop modules
    const event_loop = @import("../event_loop/libuv.zig");
    const timer_api = @import("timer_api.zig");
    const fetch_api = @import("fetch_api.zig");

    const start = std.time.milliTimestamp();
    const end_time = start + @as(i64, @intCast(wait_ms));

    // Process event loop until time expires
    while (std.time.milliTimestamp() < end_time) {
        // Run libuv event loop (non-blocking)
        // This handles OS-level async operations (including fetch HTTP requests)
        _ = event_loop.runOnce();

        // Process timer callbacks
        timer_api.processQueue(ctx.allocator);

        // Process fetch callbacks (async HTTP responses)
        fetch_api.processQueue(ctx.allocator);

        // Process animation frames (requestAnimationFrame callbacks)
        // This is critical for testing animation plugins like smear cursor
        _ = animation_api.processFrames(ctx.allocator);

        // Small sleep to prevent CPU spin
        std.Thread.sleep(1_000_000); // 1ms
    }

    return helpers.returnUndefined(runtime);
}

// ============================================================================
// Test Structure Functions
// ============================================================================

/// Test suite storage
const TestCase = struct {
    name: []const u8,
    callback: *c.OVHermesValue,
};

const TestSuite = struct {
    name: []const u8,
    tests: std.ArrayListUnmanaged(TestCase),
};

var test_suites: std.ArrayListUnmanaged(TestSuite) = .empty;
var test_suites_initialized: bool = false;
var current_suite: ?*TestSuite = null;

/// vim.e2e.describe(name, fn) - Create test suite
fn describeCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    test_suites_initialized = true;

    if (arg_count < 2) return helpers.returnUndefined(runtime);

    // Get suite name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) return helpers.returnUndefined(runtime);

    const suite_name = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return helpers.returnUndefined(runtime);

    // Create new suite
    test_suites.append(ctx.allocator, TestSuite{
        .name = suite_name,
        .tests = .empty,
    }) catch return helpers.returnUndefined(runtime);

    // Set current suite and call the setup function
    current_suite = &test_suites.items[test_suites.items.len - 1];
    _ = c.hermes_call_function(runtime, args[1], null, 0);
    current_suite = null;

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.test(name, fn) - Add test to current suite
fn testCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    const suite = current_suite orelse {
        std.debug.print("[E2E] test() called outside describe()\n", .{});
        return helpers.returnUndefined(runtime);
    };

    if (arg_count < 2) return helpers.returnUndefined(runtime);

    // Get test name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) return helpers.returnUndefined(runtime);

    const test_name = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return helpers.returnUndefined(runtime);

    // Clone callback to prevent GC (args[1] is temporary)
    const callback = args[1] orelse return helpers.returnUndefined(runtime);
    const callback_clone = c.hermes_value_clone(runtime, callback) orelse {
        ctx.allocator.free(test_name);
        return helpers.returnUndefined(runtime);
    };

    suite.tests.append(ctx.allocator, TestCase{
        .name = test_name,
        .callback = callback_clone,
    }) catch return helpers.returnUndefined(runtime);

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.runAll() - Run all registered tests
fn runAllCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse {
        tests_complete = true;
        return helpers.returnUndefined(runtime);
    };

    if (!test_suites_initialized) {
        std.debug.print("[E2E] No test suites registered\n", .{});
        tests_complete = true;
        return helpers.returnUndefined(runtime);
    }

    var passed: usize = 0;
    var failed: usize = 0;
    var result_entries: std.ArrayList(TestResultEntry) = .empty;

    if (g_verbose) {
        std.debug.print("\n=== E2E Test Results ===\n\n", .{});
    }

    for (test_suites.items) |suite| {
        if (g_verbose) {
            std.debug.print("Suite: {s}\n", .{suite.name});
        }

        for (suite.tests.items) |test_case| {
            // Clear and enable log capture for this test
            if (current_test_logs.items.len > 0) {
                // Clear previous logs (don't free, they're owned by results now)
                current_test_logs.items.len = 0;
            }
            log_capture_enabled = true;

            // Start PTY capture for this test (if display available)
            if (ctx.display) |display| {
                display.startCapture();
            }

            // Capture state BEFORE test execution (LLM debugging)
            const state_before = captureStateSnapshot(ctx.allocator, ctx);

            const test_start = std.time.milliTimestamp();

            // Call test callback
            const result = c.hermes_call_function(runtime, test_case.callback, null, 0);

            const test_duration = std.time.milliTimestamp() - test_start;

            // Capture state AFTER test execution (LLM debugging)
            const state_after = captureStateSnapshot(ctx.allocator, ctx);

            // Stop PTY capture and get output
            const pty_output: ?[]const u8 = if (ctx.display) |display| blk: {
                const output = display.stopCapture();
                // Duplicate the output since capture buffer may be reused
                if (output.len > 0) {
                    break :blk ctx.allocator.dupe(u8, output) catch null;
                }
                break :blk null;
            } else null;

            // Disable log capture and get logs
            log_capture_enabled = false;
            const test_logs = getAndClearTestLogs();
            const test_checkpoints = getAndClearTestCheckpoints();

            // Check for exception
            if (c.hermes_has_exception(runtime)) {
                const err_msg = c.hermes_get_exception_message(runtime);
                if (g_verbose) {
                    std.debug.print("  FAIL: {s}\n", .{test_case.name});
                    std.debug.print("        Error: {s}\n", .{err_msg});
                }
                failed += 1;

                // Clear exception for next test
                c.hermes_clear_exception(runtime);

                // Store result
                result_entries.append(ctx.allocator, .{
                    .name = test_case.name,
                    .suite = suite.name,
                    .passed = false,
                    .error_message = if (err_msg != null) std.mem.span(err_msg) else null,
                    .duration_ms = test_duration,
                    .logs = test_logs,
                    .state_before = state_before,
                    .state_after = state_after,
                    .checkpoints = test_checkpoints,
                    .pty_output = pty_output,
                }) catch {};
            } else {
                if (g_verbose) {
                    std.debug.print("  PASS: {s}\n", .{test_case.name});
                }
                passed += 1;

                // Store result
                result_entries.append(ctx.allocator, .{
                    .name = test_case.name,
                    .suite = suite.name,
                    .passed = true,
                    .error_message = null,
                    .duration_ms = test_duration,
                    .logs = test_logs,
                    .state_before = state_before,
                    .state_after = state_after,
                    .checkpoints = test_checkpoints,
                    .pty_output = pty_output,
                }) catch {};
            }

            if (result) |r| {
                c.hermes_value_destroy(r);
            }
        }
        if (g_verbose) {
            std.debug.print("\n", .{});
        }
    }

    if (g_verbose) {
        std.debug.print("Results: {d} passed, {d} failed\n\n", .{ passed, failed });
    }

    // Mark tests as complete and store results for Zig runner
    markComplete(passed, failed, result_entries);

    // Return results object to JavaScript
    const results = c.hermes_value_create_object(runtime) orelse return helpers.returnUndefined(runtime);
    const passed_val = c.hermes_value_create_number(runtime, @floatFromInt(passed));
    const failed_val = c.hermes_value_create_number(runtime, @floatFromInt(failed));
    const total_val = c.hermes_value_create_number(runtime, @floatFromInt(passed + failed));

    if (passed_val) |pv| {
        c.hermes_value_set_property(runtime, results, "passed", pv);
        c.hermes_value_destroy(pv);
    }
    if (failed_val) |fv| {
        c.hermes_value_set_property(runtime, results, "failed", fv);
        c.hermes_value_destroy(fv);
    }
    if (total_val) |tv| {
        c.hermes_value_set_property(runtime, results, "total", tv);
        c.hermes_value_destroy(tv);
    }

    return results;
}

// ============================================================================
// PTY Capture Functions (for terminal output validation)
// ============================================================================

/// vim.e2e.pty.startCapture() - Start capturing terminal ANSI output
fn ptyStartCapture(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    display.startCapture();
    return helpers.returnUndefined(runtime);
}

/// vim.e2e.pty.stopCapture() - Stop capturing and return captured output
fn ptyStopCapture(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const output = display.stopCapture();
    return c.hermes_value_create_string(runtime, output.ptr, output.len);
}

/// vim.e2e.pty.getOutput() - Get current captured output without stopping
fn ptyGetOutput(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const output = display.getCapturedOutput();
    return c.hermes_value_create_string(runtime, output.ptr, output.len);
}

/// vim.e2e.pty.clear() - Clear captured output buffer
fn ptyClear(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    display.clearCapturedOutput();
    return helpers.returnUndefined(runtime);
}

/// vim.e2e.pty.getLength() - Get length of captured output (useful for checking if empty)
fn ptyGetLength(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const len = display.getCapturedLength();
    return c.hermes_value_create_number(runtime, @floatFromInt(len));
}

/// vim.e2e.pty.countSequence(pattern) - Count occurrences of escape sequence
/// Example: countSequence("\x1b[?25l") to count cursor hide sequences
fn ptyCountSequence(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "countSequence requires 1 argument (pattern)");
        return null;
    }

    var pattern_len: usize = 0;
    const pattern_ptr = c.hermes_value_get_string(runtime, args[0], &pattern_len);
    if (pattern_ptr == null or pattern_len == 0) {
        c.hermes_throw_error(runtime, "countSequence requires string pattern argument");
        return null;
    }

    const pattern = pattern_ptr[0..pattern_len];
    const output = display.getCapturedOutput();

    // Count occurrences of pattern in output
    var count: usize = 0;
    var i: usize = 0;
    while (i + pattern.len <= output.len) {
        if (std.mem.eql(u8, output[i..][0..pattern.len], pattern)) {
            count += 1;
            i += pattern.len; // Non-overlapping matches
        } else {
            i += 1;
        }
    }

    return c.hermes_value_create_number(runtime, @floatFromInt(count));
}

/// vim.e2e.pty.isCapturing() - Check if capture mode is active
fn ptyIsCapturing(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };
    return c.hermes_value_create_boolean(runtime, display.capture_mode);
}

/// vim.e2e.pty.countHideCursor() - Count cursor hide escape codes (ESC[?25l)
/// Returns number of times cursor was hidden in captured output
fn ptyCountHideCursor(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const output = display.getCapturedOutput();

    // Count ESC[?25l (hide cursor)
    const pattern = "\x1b[?25l";
    var count: usize = 0;
    var i: usize = 0;
    while (i + pattern.len <= output.len) {
        if (std.mem.eql(u8, output[i..][0..pattern.len], pattern)) {
            count += 1;
            i += pattern.len;
        } else {
            i += 1;
        }
    }

    return c.hermes_value_create_number(runtime, @floatFromInt(count));
}

/// vim.e2e.pty.countShowCursor() - Count cursor show escape codes (ESC[?25h)
/// Returns number of times cursor was shown in captured output
fn ptyCountShowCursor(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const output = display.getCapturedOutput();

    // Count ESC[?25h (show cursor)
    const pattern = "\x1b[?25h";
    var count: usize = 0;
    var i: usize = 0;
    while (i + pattern.len <= output.len) {
        if (std.mem.eql(u8, output[i..][0..pattern.len], pattern)) {
            count += 1;
            i += pattern.len;
        } else {
            i += 1;
        }
    }

    return c.hermes_value_create_number(runtime, @floatFromInt(count));
}

/// vim.e2e.pty.countCursorPositionCodes() - Count cursor position codes (ESC[row;colH)
/// Returns number of cursor positioning commands in captured output
fn ptyCountCursorPositionCodes(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const output = display.getCapturedOutput();

    // Count ESC[...H or ESC[...f (cursor position codes)
    var count: usize = 0;
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        // Look for ESC[
        if (output[i] == 0x1b and i + 1 < output.len and output[i + 1] == '[') {
            var j = i + 2;
            // Scan for H or f (cursor position terminators)
            while (j < output.len and j < i + 20) : (j += 1) {
                if (output[j] == 'H' or output[j] == 'f') {
                    count += 1;
                    break;
                }
                // Stop if we hit another letter (different escape code)
                if ((output[j] >= 'A' and output[j] <= 'Z' and output[j] != 'H') or
                    (output[j] >= 'a' and output[j] <= 'z' and output[j] != 'f'))
                {
                    break;
                }
            }
        }
    }

    return c.hermes_value_create_number(runtime, @floatFromInt(count));
}

/// vim.e2e.pty.countSGRCodes() - Count SGR (color/attribute) escape codes (ESC[...m)
/// Returns number of color/attribute codes in captured output
fn ptyCountSGRCodes(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const output = display.getCapturedOutput();

    // Count ESC[...m (SGR codes)
    var count: usize = 0;
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        if (output[i] == 0x1b and i + 1 < output.len and output[i + 1] == '[') {
            var j = i + 2;
            while (j < output.len and j < i + 30) : (j += 1) {
                if (output[j] == 'm') {
                    count += 1;
                    break;
                }
                // Stop if we hit another letter (different escape code)
                if ((output[j] >= 'A' and output[j] <= 'Z') or
                    (output[j] >= 'a' and output[j] < 'm') or
                    (output[j] > 'm' and output[j] <= 'z'))
                {
                    break;
                }
            }
        }
    }

    return c.hermes_value_create_number(runtime, @floatFromInt(count));
}

/// vim.e2e.pty.resetCursorState() - Reset cursor visibility tracking
/// This resets the internal cursor state so that the next render will
/// re-send cursor hide/show codes. Useful for tests that need to verify
/// cursor visibility behavior.
fn ptyResetCursorState(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    // Reset cursor visibility state to force re-sending cursor codes
    // This is useful for E2E tests that need fresh cursor state
    display.last_cursor_visible = true; // Assume visible (terminal default)
    display.last_cursor_row = std.math.maxInt(usize); // Force cursor move on next render
    display.last_cursor_col = std.math.maxInt(usize);

    return helpers.returnUndefined(runtime);
}

// ============================================================================
// Animation Frame Capture Functions (for animation testing)
// ============================================================================

/// vim.e2e.pty.startFrameCapture() - Start capturing animation frames
/// Each render cycle will create a new timestamped frame
fn ptyStartFrameCapture(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    display.startFrameCapture();
    return helpers.returnUndefined(runtime);
}

/// vim.e2e.pty.stopFrameCapture() - Stop capturing animation frames
/// Returns the number of frames captured
fn ptyStopFrameCapture(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const frame_count = display.stopFrameCapture();
    return c.hermes_value_create_number(runtime, @floatFromInt(frame_count));
}

/// vim.e2e.pty.captureFrame() - Manually capture current output as a frame
/// This is called automatically during render when frame_capture_mode is true,
/// but can also be called manually for more control
fn ptyCaptureFrame(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    display.captureFrame() catch |err| {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "captureFrame failed: {}", .{err}) catch "captureFrame failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    };
    return helpers.returnUndefined(runtime);
}

/// vim.e2e.pty.getFrames() - Get all captured animation frames
/// Returns an array of { timestamp: number, output: string } objects
fn ptyGetFrames(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const frames = display.getCapturedFrames();

    // Create result array
    const result = c.hermes_array_create(runtime, frames.len) orelse return helpers.returnUndefined(runtime);

    for (frames, 0..) |frame, i| {
        // Create frame object { timestamp, output }
        const frame_obj = c.hermes_value_create_object(runtime) orelse continue;

        // timestamp (milliseconds since capture started)
        const timestamp_val = c.hermes_value_create_number(runtime, @floatFromInt(frame.timestamp_ms));
        if (timestamp_val) |tv| {
            c.hermes_value_set_property(runtime, frame_obj, "timestamp", tv);
            c.hermes_value_destroy(tv);
        }

        // output (ANSI escape codes as string)
        const output_val = c.hermes_value_create_string(runtime, frame.output.ptr, frame.output.len);
        if (output_val) |ov| {
            c.hermes_value_set_property(runtime, frame_obj, "output", ov);
            c.hermes_value_destroy(ov);
        }

        c.hermes_array_set(runtime, result, i, frame_obj);
        c.hermes_value_destroy(frame_obj);
    }

    return result;
}

/// vim.e2e.pty.getFrameCount() - Get the number of captured frames
fn ptyGetFrameCount(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };
    const count = display.getCapturedFrameCount();
    return c.hermes_value_create_number(runtime, @floatFromInt(count));
}

/// vim.e2e.pty.isCapturingFrames() - Check if frame capture mode is active
fn ptyIsCapturingFrames(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };
    return c.hermes_value_create_boolean(runtime, display.isCapturingFrames());
}

/// vim.e2e.pty.render() - Trigger a full render cycle with PTY capture
/// This generates actual ANSI escape codes that can be inspected
/// Returns the number of bytes written to the capture buffer
fn ptyRender(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    // Get the Editor pointer - ctx.editor is *Editor (not *EditorContext!)
    // In test.zig, jsi_api.initJSI is called with &editor_ctx.editor which is *Editor
    const Editor = @import("../../editor/editor.zig").Editor;
    const ListChars = @import("../../editor/config/listchars.zig").ListChars;

    // Cast editor back to *Editor (NOT *EditorContext!)
    const editor: *Editor = @ptrCast(@alignCast(ctx.editor));

    // Get default listchars
    var listchars = ListChars{};

    // Process libuv event loop first (timers, I/O, etc.)
    // This is critical for setTimeout/setInterval callbacks to fire
    const event_loop = @import("../event_loop/libuv.zig");
    _ = event_loop.runOnce();

    // Process timer queue (setTimeout/setInterval callbacks)
    const timer_api = @import("timer_api.zig");
    timer_api.processQueue(ctx.allocator);

    // Process pending requestAnimationFrame callbacks (for smear cursor animation, etc.)
    // This is critical for testing plugins that use animation - without this,
    // the animation callbacks never execute during E2E tests
    _ = animation_api.processFrames(ctx.allocator);

    // Trigger a render cycle
    // When capture mode is active (for PTY testing), always use full render
    // to generate ANSI escape codes. Otherwise, use headless for clean output.
    if (g_verbose or display.capture_mode) {
        // Check if there are multiple split/pane windows (not floating) OR any floating windows
        // If so, use renderAllWindows() to properly render all windows including floating
        // Otherwise, use single-window render() for backwards compatibility
        // Neovim convention: floating windows don't count as "multiple windows" for statusline
        const has_multiple_windows = editor.countNonFloatingWindows() > 1;
        const has_floating_windows = editor.hasFloatingWindows();

        if (has_multiple_windows or has_floating_windows) {
            // Multi-window path: Renders all windows including floating windows
            // Floating windows don't require window_layout (they store their own screen position)
            display.renderAllWindows(
                editor,
                "-- NORMAL --",
                ctx.visual_state,
                &editor.yank_highlight,
                false, // cursorline disabled
                false, // list mode disabled
                &listchars,
                2, // laststatus = always show
            ) catch |err| {
                var msg_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "renderAllWindows failed: {}", .{err}) catch "render failed";
                if (msg.len < msg_buf.len) {
                    msg_buf[msg.len] = 0;
                }
                c.hermes_throw_error(runtime, msg.ptr);
                return null;
            };
        } else {
            // Single-window path: Original render for backwards compatibility
            display.render(
                editor,
                "-- NORMAL --", // Default status line
                false, // cursorline disabled
                ctx.visual_state,
                &editor.yank_highlight,
                false, // list mode disabled
                &listchars,
                2, // laststatus = always show
            ) catch |err| {
                var msg_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "render failed: {}", .{err}) catch "render failed";
                if (msg.len < msg_buf.len) {
                    msg_buf[msg.len] = 0;
                }
                c.hermes_throw_error(runtime, msg.ptr);
                return null;
            };
        }

        // CRITICAL FIX: Match backend.render() behavior after display.render()
        // backend.render() calls showCursor() to re-show cursor after rendering cells.
        // Without this, cursor is hidden by display.render() but never shown again!
        // This was causing the E2E tests to see 0 showCursor codes.
        display.showCursor() catch {};
        display.endSynchronizedUpdate() catch {};
        // NOTE: Don't call flush() in E2E tests - stdout may not be a real terminal
        // and fsync() returns ENOTSUP (errno 45) on non-fsync-able file descriptors
    } else {
        // Headless render: Update compositor state WITHOUT writing to stdout
        // This keeps stdout clean for JSON test results
        display.renderHeadless(
            editor,
            "-- NORMAL --",
            false,
            ctx.visual_state,
            &editor.yank_highlight,
            false,
            &listchars,
        ) catch |err| {
            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "render failed: {}", .{err}) catch "render failed";
            if (msg.len < msg_buf.len) {
                msg_buf[msg.len] = 0;
            }
            c.hermes_throw_error(runtime, msg.ptr);
            return null;
        };
    }

    // Return the number of bytes captured
    const captured_len = display.getCapturedLength();
    return c.hermes_value_create_number(runtime, @floatFromInt(captured_len));
}

/// vim.e2e.pty.getRenderStats() - Get render statistics from last render
/// Returns { cursorHideCodes, cursorShowCodes, cursorPositionCodes, totalRenders }
fn ptyGetRenderStats(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const result = c.hermes_value_create_object(runtime) orelse return helpers.returnUndefined(runtime);

    // Add render stats from display
    const stats = display.render_stats;

    const hide_val = c.hermes_value_create_number(runtime, @floatFromInt(stats.cursor_hide_codes));
    if (hide_val) |hv| {
        c.hermes_value_set_property(runtime, result, "cursorHideCodes", hv);
        c.hermes_value_destroy(hv);
    }

    const show_val = c.hermes_value_create_number(runtime, @floatFromInt(stats.cursor_show_codes));
    if (show_val) |sv| {
        c.hermes_value_set_property(runtime, result, "cursorShowCodes", sv);
        c.hermes_value_destroy(sv);
    }

    const pos_val = c.hermes_value_create_number(runtime, @floatFromInt(stats.cursor_position_codes));
    if (pos_val) |pv| {
        c.hermes_value_set_property(runtime, result, "cursorPositionCodes", pv);
        c.hermes_value_destroy(pv);
    }

    const total_val = c.hermes_value_create_number(runtime, @floatFromInt(stats.total_renders));
    if (total_val) |tv| {
        c.hermes_value_set_property(runtime, result, "totalRenders", tv);
        c.hermes_value_destroy(tv);
    }

    const avg_ms = stats.getAverageRenderDurationMs();
    const avg_val = c.hermes_value_create_number(runtime, avg_ms);
    if (avg_val) |av| {
        c.hermes_value_set_property(runtime, result, "avgRenderMs", av);
        c.hermes_value_destroy(av);
    }

    return result;
}

/// vim.e2e.pty.setSize(rows, cols) - Set terminal size for testing
/// This allows testing different terminal dimensions without a real PTY.
/// Useful for testing responsive layouts, text wrapping, viewport behavior, etc.
/// Returns boolean indicating success.
fn ptySetSize(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Require 2 arguments: rows and cols
    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "pty.setSize requires 2 arguments: rows, cols");
        return null;
    }

    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    // Get rows argument
    if (!c.hermes_value_is_number(args[0])) {
        c.hermes_throw_error(runtime, "pty.setSize: rows must be a number");
        return null;
    }
    const rows_f = c.hermes_value_get_number(args[0]);
    if (rows_f < 1 or rows_f > 1000) {
        c.hermes_throw_error(runtime, "pty.setSize: rows must be between 1 and 1000");
        return null;
    }
    const rows: usize = @intFromFloat(rows_f);

    // Get cols argument
    if (!c.hermes_value_is_number(args[1])) {
        c.hermes_throw_error(runtime, "pty.setSize: cols must be a number");
        return null;
    }
    const cols_f = c.hermes_value_get_number(args[1]);
    if (cols_f < 1 or cols_f > 1000) {
        c.hermes_throw_error(runtime, "pty.setSize: cols must be between 1 and 1000");
        return null;
    }
    const cols: usize = @intFromFloat(cols_f);

    // Apply the size change
    display.setSize(rows, cols) catch |err| {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "pty.setSize failed: {}", .{err}) catch "setSize failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    };

    return c.hermes_value_create_boolean(runtime, true);
}

/// vim.e2e.pty.getSize() - Get current terminal size
/// Returns { rows: number, cols: number }
fn ptyGetSize(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const size = display.getSize();

    const result = c.hermes_value_create_object(runtime) orelse return helpers.returnUndefined(runtime);

    const rows_val = c.hermes_value_create_number(runtime, @floatFromInt(size.rows));
    if (rows_val) |rv| {
        c.hermes_value_set_property(runtime, result, "rows", rv);
        c.hermes_value_destroy(rv);
    }

    const cols_val = c.hermes_value_create_number(runtime, @floatFromInt(size.cols));
    if (cols_val) |cv| {
        c.hermes_value_set_property(runtime, result, "cols", cv);
        c.hermes_value_destroy(cv);
    }

    return result;
}

// ============================================================================
// Assertion Functions
// ============================================================================

/// vim.e2e.assert.equal(actual, expected, message?)
fn assertEqual(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "assert.equal requires 2 arguments");
        return null;
    }

    const actual = args[0];
    const expected = args[1];

    // Check if both are numbers
    if (c.hermes_value_is_number(actual) and c.hermes_value_is_number(expected)) {
        const actual_num = c.hermes_value_get_number(actual);
        const expected_num = c.hermes_value_get_number(expected);

        if (actual_num != expected_num) {
            var msg_buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Expected {d}, got {d}", .{ expected_num, actual_num }) catch "Assertion failed";
            if (msg.len < msg_buf.len) {
                msg_buf[msg.len] = 0;
            }
            c.hermes_throw_error(runtime, msg.ptr);
            return null;
        }
        return helpers.returnUndefined(runtime);
    }

    // Check if both are booleans
    if (c.hermes_value_is_boolean(actual) and c.hermes_value_is_boolean(expected)) {
        const actual_bool = c.hermes_value_get_boolean(actual);
        const expected_bool = c.hermes_value_get_boolean(expected);

        if (actual_bool != expected_bool) {
            var msg_buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Expected {}, got {}", .{ expected_bool, actual_bool }) catch "Assertion failed";
            if (msg.len < msg_buf.len) {
                msg_buf[msg.len] = 0;
            }
            c.hermes_throw_error(runtime, msg.ptr);
            return null;
        }
        return helpers.returnUndefined(runtime);
    }

    // Check if both are strings
    if (c.hermes_value_is_string(actual) and c.hermes_value_is_string(expected)) {
        var actual_len: usize = 0;
        var expected_len: usize = 0;
        const actual_ptr = c.hermes_value_get_string(runtime, actual, &actual_len);
        const expected_ptr = c.hermes_value_get_string(runtime, expected, &expected_len);

        if (actual_ptr != null and expected_ptr != null) {
            const actual_str = actual_ptr[0..actual_len];
            const expected_str = expected_ptr[0..expected_len];

            if (!std.mem.eql(u8, actual_str, expected_str)) {
                var msg_buf: [512]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Expected '{s}', got '{s}'", .{ expected_str, actual_str }) catch "Assertion failed";
                if (msg.len < msg_buf.len) {
                    msg_buf[msg.len] = 0;
                }
                c.hermes_throw_error(runtime, msg.ptr);
                return null;
            }
        }
        return helpers.returnUndefined(runtime);
    }

    // Type mismatch - fail with descriptive error
    var msg_buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "assert.equal: type mismatch between actual and expected values", .{}) catch "Type mismatch";
    if (msg.len < msg_buf.len) {
        msg_buf[msg.len] = 0;
    }
    c.hermes_throw_error(runtime, msg.ptr);
    return null;
}

/// vim.e2e.assert.mode(expected_mode)
fn assertMode(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "assert.mode requires 1 argument");
        return null;
    }

    var expected_len: usize = 0;
    const expected_ptr = c.hermes_value_get_string(runtime, args[0], &expected_len);
    if (expected_ptr == null) {
        c.hermes_throw_error(runtime, "assert.mode requires string argument");
        return null;
    }

    const expected = expected_ptr[0..expected_len];
    const actual = ctx.mode_manager.getModeString();

    if (!std.mem.eql(u8, expected, actual)) {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Expected mode {s}, got {s}", .{ expected, actual }) catch "Mode assertion failed";
        // Null-terminate for C string compatibility
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.cursorAt(line, col)
fn assertCursorAt(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const buffer = ctx.getCurrentBuffer() orelse return helpers.returnUndefined(runtime);

    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "assert.cursorAt requires 2 arguments (line, col)");
        return null;
    }

    const expected_line = helpers.extractNumberArg(runtime.?, args[0].?) catch {
        c.hermes_throw_error(runtime, "assert.cursorAt: line must be a number");
        return null;
    };
    const expected_col = helpers.extractNumberArg(runtime.?, args[1].?) catch {
        c.hermes_throw_error(runtime, "assert.cursorAt: col must be a number");
        return null;
    };

    const actual_line = buffer.cursor.row;
    const actual_col = buffer.cursor.col;

    if (@as(usize, @intFromFloat(expected_line)) != actual_line or
        @as(usize, @intFromFloat(expected_col)) != actual_col)
    {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Expected cursor at ({d},{d}), got ({d},{d})", .{ @as(usize, @intFromFloat(expected_line)), @as(usize, @intFromFloat(expected_col)), actual_line, actual_col }) catch "Cursor assertion failed";
        // Null-terminate for C string compatibility
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.bufferContains(text)
fn assertBufferContains(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);
    const buffer = ctx.getCurrentBuffer() orelse return helpers.returnUndefined(runtime);

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "assert.bufferContains requires 1 argument");
        return null;
    }

    var expected_len: usize = 0;
    const expected_ptr = c.hermes_value_get_string(runtime, args[0], &expected_len);
    if (expected_ptr == null) {
        c.hermes_throw_error(runtime, "assert.bufferContains requires string argument");
        return null;
    }

    const expected = expected_ptr[0..expected_len];

    // Get buffer content
    const content = buffer.content.toString() catch {
        c.hermes_throw_error(runtime, "Failed to get buffer content");
        return null;
    };
    defer buffer.content.allocator.free(content);

    if (std.mem.indexOf(u8, content, expected) == null) {
        var msg_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Buffer does not contain: {s}", .{expected}) catch "Buffer assertion failed";
        // Null-terminate for C string compatibility
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.true(condition, message?)
/// Asserts that a condition is truthy
fn assertTrue(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "assert.true requires 1 argument");
        return null;
    }

    const condition = args[0];

    // Check if condition is truthy
    const is_truthy = blk: {
        if (c.hermes_value_is_boolean(condition)) {
            break :blk c.hermes_value_get_boolean(condition);
        }
        if (c.hermes_value_is_number(condition)) {
            const num = c.hermes_value_get_number(condition);
            break :blk num != 0;
        }
        if (c.hermes_value_is_null(condition) or c.hermes_value_is_undefined(condition)) {
            break :blk false;
        }
        // Non-null objects, strings, etc. are truthy
        break :blk true;
    };

    if (!is_truthy) {
        // Get optional message
        if (arg_count >= 2) {
            var msg_len: usize = 0;
            const msg_ptr = c.hermes_value_get_string(runtime, args[1], &msg_len);
            if (msg_ptr != null and msg_len > 0) {
                // Use user-provided message (it's already null-terminated from JS)
                var msg_buf: [512]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Assertion failed: {s}", .{msg_ptr[0..msg_len]}) catch "Assertion failed";
                if (msg.len < msg_buf.len) {
                    msg_buf[msg.len] = 0;
                }
                c.hermes_throw_error(runtime, msg.ptr);
                return null;
            }
        }
        c.hermes_throw_error(runtime, "assert.true failed");
        return null;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.false(condition, message?)
/// Asserts that a condition is falsy
fn assertFalse(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "assert.false requires 1 argument");
        return null;
    }

    const condition = args[0];

    // Check if condition is truthy
    const is_truthy = blk: {
        if (c.hermes_value_is_boolean(condition)) {
            break :blk c.hermes_value_get_boolean(condition);
        }
        if (c.hermes_value_is_number(condition)) {
            const num = c.hermes_value_get_number(condition);
            break :blk num != 0;
        }
        if (c.hermes_value_is_null(condition) or c.hermes_value_is_undefined(condition)) {
            break :blk false;
        }
        // Non-null objects, strings, etc. are truthy
        break :blk true;
    };

    // assert.false expects the condition to be falsy
    if (is_truthy) {
        // Get optional message
        if (arg_count >= 2) {
            var msg_len: usize = 0;
            const msg_ptr = c.hermes_value_get_string(runtime, args[1], &msg_len);
            if (msg_ptr != null and msg_len > 0) {
                // Use user-provided message
                var msg_buf: [512]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Assertion failed: {s}", .{msg_ptr[0..msg_len]}) catch "Assertion failed";
                if (msg.len < msg_buf.len) {
                    msg_buf[msg.len] = 0;
                }
                c.hermes_throw_error(runtime, msg.ptr);
                return null;
            }
        }
        c.hermes_throw_error(runtime, "assert.false failed (value was truthy)");
        return null;
    }

    return helpers.returnUndefined(runtime);
}

// ============================================================================
// Frame Assertion Helpers
// ============================================================================

/// vim.e2e.assert.frameCount(expected, message?)
/// Asserts that the captured frame count matches expected
fn assertFrameCount(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "assert.frameCount requires 1 argument");
        return null;
    }

    const expected = @as(usize, @intFromFloat(c.hermes_value_get_number(args[0])));
    const ctx = global_e2e_ctx orelse {
        c.hermes_throw_error(runtime, "E2E context not initialized");
        return null;
    };

    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const actual = display.captured_frames.items.len;

    if (actual != expected) {
        var msg_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "assert.frameCount failed: expected {d} frames, got {d}", .{ expected, actual }) catch "assert.frameCount failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.framesIncreasing(message?)
/// Asserts that frame timestamps are strictly increasing
fn assertFramesIncreasing(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse {
        c.hermes_throw_error(runtime, "E2E context not initialized");
        return null;
    };

    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const frames = display.captured_frames.items;
    if (frames.len < 2) {
        // Trivially true with less than 2 frames
        return helpers.returnUndefined(runtime);
    }

    var prev_ts = frames[0].timestamp_ms;
    for (frames[1..], 1..) |frame, i| {
        if (frame.timestamp_ms <= prev_ts) {
            var msg_buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "assert.framesIncreasing failed: frame {d} timestamp ({d}ms) not > frame {d} timestamp ({d}ms)", .{ i, frame.timestamp_ms, i - 1, prev_ts }) catch "assert.framesIncreasing failed";
            if (msg.len < msg_buf.len) {
                msg_buf[msg.len] = 0;
            }
            c.hermes_throw_error(runtime, msg.ptr);
            return null;
        }
        prev_ts = frame.timestamp_ms;
    }

    // Include message in success (for logging/debugging)
    _ = args;
    _ = arg_count;

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.framesNotEmpty(message?)
/// Asserts that all captured frames have non-empty output
fn assertFramesNotEmpty(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse {
        c.hermes_throw_error(runtime, "E2E context not initialized");
        return null;
    };

    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const frames = display.captured_frames.items;
    for (frames, 0..) |frame, i| {
        if (frame.output.len == 0) {
            var msg_buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "assert.framesNotEmpty failed: frame {d} has empty output", .{i}) catch "assert.framesNotEmpty failed";
            if (msg.len < msg_buf.len) {
                msg_buf[msg.len] = 0;
            }
            c.hermes_throw_error(runtime, msg.ptr);
            return null;
        }
    }

    _ = args;
    _ = arg_count;

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.framesUnique(message?)
/// Asserts that all captured frames have unique output (detects animation progression)
fn assertFramesUnique(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse {
        c.hermes_throw_error(runtime, "E2E context not initialized");
        return null;
    };

    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const frames = display.captured_frames.items;
    if (frames.len < 2) {
        // Trivially true with less than 2 frames
        return helpers.returnUndefined(runtime);
    }

    // O(n^2) comparison - acceptable for test frame counts (<100)
    for (frames, 0..) |frame_a, i| {
        for (frames[i + 1 ..], i + 1..) |frame_b, j| {
            if (std.mem.eql(u8, frame_a.output, frame_b.output)) {
                var msg_buf: [512]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "assert.framesUnique failed: frame {d} and frame {d} have identical output", .{ i, j }) catch "assert.framesUnique failed";
                if (msg.len < msg_buf.len) {
                    msg_buf[msg.len] = 0;
                }
                c.hermes_throw_error(runtime, msg.ptr);
                return null;
            }
        }
    }

    _ = args;
    _ = arg_count;

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.frameDuration(minMs, maxMs, message?)
/// Asserts that total animation duration is within expected bounds
fn assertFrameDuration(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "assert.frameDuration requires minMs and maxMs arguments");
        return null;
    }

    const min_ms = @as(i64, @intFromFloat(c.hermes_value_get_number(args[0])));
    const max_ms = @as(i64, @intFromFloat(c.hermes_value_get_number(args[1])));

    const ctx = global_e2e_ctx orelse {
        c.hermes_throw_error(runtime, "E2E context not initialized");
        return null;
    };

    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const frames = display.captured_frames.items;
    if (frames.len < 2) {
        // Can't measure duration with less than 2 frames
        return helpers.returnUndefined(runtime);
    }

    const first_ts = frames[0].timestamp_ms;
    const last_ts = frames[frames.len - 1].timestamp_ms;
    const duration = last_ts - first_ts;

    if (duration < min_ms or duration > max_ms) {
        var msg_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "assert.frameDuration failed: duration {d}ms not in range [{d}ms, {d}ms]", .{ duration, min_ms, max_ms }) catch "assert.frameDuration failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    return helpers.returnUndefined(runtime);
}

/// vim.e2e.assert.frameContains(frameIndex, pattern, message?)
/// Asserts that a specific frame contains the given pattern
fn assertFrameContains(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "assert.frameContains requires frameIndex and pattern arguments");
        return null;
    }

    const frame_index = @as(usize, @intFromFloat(c.hermes_value_get_number(args[0])));

    var pattern_len: usize = 0;
    const pattern_ptr = c.hermes_value_get_string(runtime, args[1], &pattern_len);
    if (pattern_ptr == null or pattern_len == 0) {
        c.hermes_throw_error(runtime, "assert.frameContains requires non-empty pattern");
        return null;
    }
    const pattern = pattern_ptr[0..pattern_len];

    const ctx = global_e2e_ctx orelse {
        c.hermes_throw_error(runtime, "E2E context not initialized");
        return null;
    };

    const display = ctx.display orelse {
        c.hermes_throw_error(runtime, "PTY capture not available (no display)");
        return null;
    };

    const frames = display.captured_frames.items;
    if (frame_index >= frames.len) {
        var msg_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "assert.frameContains failed: frame index {d} out of bounds (have {d} frames)", .{ frame_index, frames.len }) catch "assert.frameContains failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    const frame_output = frames[frame_index].output;
    if (std.mem.indexOf(u8, frame_output, pattern) == null) {
        var msg_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "assert.frameContains failed: frame {d} does not contain '{s}'", .{ frame_index, pattern }) catch "assert.frameContains failed";
        if (msg.len < msg_buf.len) {
            msg_buf[msg.len] = 0;
        }
        c.hermes_throw_error(runtime, msg.ptr);
        return null;
    }

    return helpers.returnUndefined(runtime);
}

// ============================================================================
// HostObject Registration
// ============================================================================

/// HostObject getter for vim.e2e
pub export fn vimE2EHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const name = std.mem.span(prop_name);

    // Map property names to functions
    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        // State queries
        .{ "getCursor", getCursor },
        .{ "getMode", getMode },
        .{ "getState", getState },
        .{ "getBufferContent", getBufferContent },
        .{ "getLine", getLine },
        .{ "getLayers", getLayersCmd },
        .{ "getLogs", getLogsCmd },
        // Commands
        .{ "keys", keysCmd },
        .{ "tick", tickCmd },
        .{ "wait", waitCmd },
        .{ "sleep", waitCmd }, // Alias for wait
        // Test structure
        .{ "describe", describeCmd },
        .{ "test", testCmd },
        .{ "runAll", runAllCmd },
        // Debugging
        .{ "checkpoint", checkpointCmd },
    });

    // Handle assert sub-object
    if (std.mem.eql(u8, name, "assert")) {
        return createAssertObject(runtime);
    }

    // Handle pty sub-object (for terminal output capture)
    if (std.mem.eql(u8, name, "pty")) {
        return createPtyObject(runtime);
    }

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, null);
}

/// Create the assert sub-object
fn createAssertObject(runtime: ?*c.OVHermesRuntime) ?*c.OVHermesValue {
    const assert_obj = c.hermes_value_create_object(runtime) orelse return null;

    // Add assertion methods
    const equal_fn = c.hermes_create_function(runtime, "equal", assertEqual, null);
    if (equal_fn) |ef| {
        c.hermes_value_set_property(runtime, assert_obj, "equal", ef);
        c.hermes_value_destroy(ef);
    }

    const mode_fn = c.hermes_create_function(runtime, "mode", assertMode, null);
    if (mode_fn) |mf| {
        c.hermes_value_set_property(runtime, assert_obj, "mode", mf);
        c.hermes_value_destroy(mf);
    }

    const cursor_fn = c.hermes_create_function(runtime, "cursorAt", assertCursorAt, null);
    if (cursor_fn) |cf| {
        c.hermes_value_set_property(runtime, assert_obj, "cursorAt", cf);
        c.hermes_value_destroy(cf);
    }

    const contains_fn = c.hermes_create_function(runtime, "bufferContains", assertBufferContains, null);
    if (contains_fn) |cf2| {
        c.hermes_value_set_property(runtime, assert_obj, "bufferContains", cf2);
        c.hermes_value_destroy(cf2);
    }

    const true_fn = c.hermes_create_function(runtime, "true", assertTrue, null);
    if (true_fn) |tf| {
        c.hermes_value_set_property(runtime, assert_obj, "true", tf);
        c.hermes_value_destroy(tf);
    }

    // Add assert.ok as alias for assert.true (common Jest/Mocha pattern)
    const ok_fn = c.hermes_create_function(runtime, "ok", assertTrue, null);
    if (ok_fn) |okf| {
        c.hermes_value_set_property(runtime, assert_obj, "ok", okf);
        c.hermes_value_destroy(okf);
    }

    const false_fn = c.hermes_create_function(runtime, "false", assertFalse, null);
    if (false_fn) |ff| {
        c.hermes_value_set_property(runtime, assert_obj, "false", ff);
        c.hermes_value_destroy(ff);
    }

    // Frame assertion helpers for animation testing
    const frame_count_fn = c.hermes_create_function(runtime, "frameCount", assertFrameCount, null);
    if (frame_count_fn) |fcf| {
        c.hermes_value_set_property(runtime, assert_obj, "frameCount", fcf);
        c.hermes_value_destroy(fcf);
    }

    const frames_inc_fn = c.hermes_create_function(runtime, "framesIncreasing", assertFramesIncreasing, null);
    if (frames_inc_fn) |fif| {
        c.hermes_value_set_property(runtime, assert_obj, "framesIncreasing", fif);
        c.hermes_value_destroy(fif);
    }

    const frames_ne_fn = c.hermes_create_function(runtime, "framesNotEmpty", assertFramesNotEmpty, null);
    if (frames_ne_fn) |fnef| {
        c.hermes_value_set_property(runtime, assert_obj, "framesNotEmpty", fnef);
        c.hermes_value_destroy(fnef);
    }

    const frames_unique_fn = c.hermes_create_function(runtime, "framesUnique", assertFramesUnique, null);
    if (frames_unique_fn) |fuf| {
        c.hermes_value_set_property(runtime, assert_obj, "framesUnique", fuf);
        c.hermes_value_destroy(fuf);
    }

    const frame_dur_fn = c.hermes_create_function(runtime, "frameDuration", assertFrameDuration, null);
    if (frame_dur_fn) |fdf| {
        c.hermes_value_set_property(runtime, assert_obj, "frameDuration", fdf);
        c.hermes_value_destroy(fdf);
    }

    const frame_contains_fn = c.hermes_create_function(runtime, "frameContains", assertFrameContains, null);
    if (frame_contains_fn) |fcf| {
        c.hermes_value_set_property(runtime, assert_obj, "frameContains", fcf);
        c.hermes_value_destroy(fcf);
    }

    return assert_obj;
}

/// Create the pty sub-object (for terminal output capture)
fn createPtyObject(runtime: ?*c.OVHermesRuntime) ?*c.OVHermesValue {
    const pty_obj = c.hermes_value_create_object(runtime) orelse return null;

    // Add PTY capture methods
    const start_fn = c.hermes_create_function(runtime, "startCapture", ptyStartCapture, null);
    if (start_fn) |sf| {
        c.hermes_value_set_property(runtime, pty_obj, "startCapture", sf);
        c.hermes_value_destroy(sf);
    }

    const stop_fn = c.hermes_create_function(runtime, "stopCapture", ptyStopCapture, null);
    if (stop_fn) |sf| {
        c.hermes_value_set_property(runtime, pty_obj, "stopCapture", sf);
        c.hermes_value_destroy(sf);
    }

    const get_fn = c.hermes_create_function(runtime, "getOutput", ptyGetOutput, null);
    if (get_fn) |gf| {
        c.hermes_value_set_property(runtime, pty_obj, "getOutput", gf);
        c.hermes_value_destroy(gf);
    }

    const clear_fn = c.hermes_create_function(runtime, "clear", ptyClear, null);
    if (clear_fn) |cf| {
        c.hermes_value_set_property(runtime, pty_obj, "clear", cf);
        c.hermes_value_destroy(cf);
    }

    const len_fn = c.hermes_create_function(runtime, "getLength", ptyGetLength, null);
    if (len_fn) |lf| {
        c.hermes_value_set_property(runtime, pty_obj, "getLength", lf);
        c.hermes_value_destroy(lf);
    }

    const count_fn = c.hermes_create_function(runtime, "countSequence", ptyCountSequence, null);
    if (count_fn) |cf| {
        c.hermes_value_set_property(runtime, pty_obj, "countSequence", cf);
        c.hermes_value_destroy(cf);
    }

    const is_capturing_fn = c.hermes_create_function(runtime, "isCapturing", ptyIsCapturing, null);
    if (is_capturing_fn) |icf| {
        c.hermes_value_set_property(runtime, pty_obj, "isCapturing", icf);
        c.hermes_value_destroy(icf);
    }

    // Convenience counting functions (pre-built escape code patterns)
    const count_hide_fn = c.hermes_create_function(runtime, "countHideCursor", ptyCountHideCursor, null);
    if (count_hide_fn) |chf| {
        c.hermes_value_set_property(runtime, pty_obj, "countHideCursor", chf);
        c.hermes_value_destroy(chf);
    }

    const count_show_fn = c.hermes_create_function(runtime, "countShowCursor", ptyCountShowCursor, null);
    if (count_show_fn) |csf| {
        c.hermes_value_set_property(runtime, pty_obj, "countShowCursor", csf);
        c.hermes_value_destroy(csf);
    }

    const count_pos_fn = c.hermes_create_function(runtime, "countCursorPositionCodes", ptyCountCursorPositionCodes, null);
    if (count_pos_fn) |cpf| {
        c.hermes_value_set_property(runtime, pty_obj, "countCursorPositionCodes", cpf);
        c.hermes_value_destroy(cpf);
    }

    const count_sgr_fn = c.hermes_create_function(runtime, "countSGRCodes", ptyCountSGRCodes, null);
    if (count_sgr_fn) |csgrf| {
        c.hermes_value_set_property(runtime, pty_obj, "countSGRCodes", csgrf);
        c.hermes_value_destroy(csgrf);
    }

    const render_stats_fn = c.hermes_create_function(runtime, "getRenderStats", ptyGetRenderStats, null);
    if (render_stats_fn) |rsf| {
        c.hermes_value_set_property(runtime, pty_obj, "getRenderStats", rsf);
        c.hermes_value_destroy(rsf);
    }

    const render_fn = c.hermes_create_function(runtime, "render", ptyRender, null);
    if (render_fn) |rf| {
        c.hermes_value_set_property(runtime, pty_obj, "render", rf);
        c.hermes_value_destroy(rf);
    }

    const reset_cursor_fn = c.hermes_create_function(runtime, "resetCursorState", ptyResetCursorState, null);
    if (reset_cursor_fn) |rcf| {
        c.hermes_value_set_property(runtime, pty_obj, "resetCursorState", rcf);
        c.hermes_value_destroy(rcf);
    }

    // Animation frame capture methods
    const start_frame_fn = c.hermes_create_function(runtime, "startFrameCapture", ptyStartFrameCapture, null);
    if (start_frame_fn) |sff| {
        c.hermes_value_set_property(runtime, pty_obj, "startFrameCapture", sff);
        c.hermes_value_destroy(sff);
    }

    const stop_frame_fn = c.hermes_create_function(runtime, "stopFrameCapture", ptyStopFrameCapture, null);
    if (stop_frame_fn) |sff| {
        c.hermes_value_set_property(runtime, pty_obj, "stopFrameCapture", sff);
        c.hermes_value_destroy(sff);
    }

    const capture_frame_fn = c.hermes_create_function(runtime, "captureFrame", ptyCaptureFrame, null);
    if (capture_frame_fn) |cff| {
        c.hermes_value_set_property(runtime, pty_obj, "captureFrame", cff);
        c.hermes_value_destroy(cff);
    }

    const get_frames_fn = c.hermes_create_function(runtime, "getFrames", ptyGetFrames, null);
    if (get_frames_fn) |gff| {
        c.hermes_value_set_property(runtime, pty_obj, "getFrames", gff);
        c.hermes_value_destroy(gff);
    }

    const get_frame_count_fn = c.hermes_create_function(runtime, "getFrameCount", ptyGetFrameCount, null);
    if (get_frame_count_fn) |gfcf| {
        c.hermes_value_set_property(runtime, pty_obj, "getFrameCount", gfcf);
        c.hermes_value_destroy(gfcf);
    }

    const is_capturing_frames_fn = c.hermes_create_function(runtime, "isCapturingFrames", ptyIsCapturingFrames, null);
    if (is_capturing_frames_fn) |icff| {
        c.hermes_value_set_property(runtime, pty_obj, "isCapturingFrames", icff);
        c.hermes_value_destroy(icff);
    }

    // Terminal size methods for E2E testing
    const set_size_fn = c.hermes_create_function(runtime, "setSize", ptySetSize, null);
    if (set_size_fn) |ssf| {
        c.hermes_value_set_property(runtime, pty_obj, "setSize", ssf);
        c.hermes_value_destroy(ssf);
    }

    const get_size_fn = c.hermes_create_function(runtime, "getSize", ptyGetSize, null);
    if (get_size_fn) |gsf| {
        c.hermes_value_set_property(runtime, pty_obj, "getSize", gsf);
        c.hermes_value_destroy(gsf);
    }

    return pty_obj;
}

/// Register vim.e2e API
pub fn register(runtime: *c.OVHermesRuntime, ctx: *E2EContext) void {
    global_e2e_ctx = ctx;

    // Register vimE2E HostObject
    c.hermes_register_host_object(
        runtime,
        "vimE2E",
        vimE2EHostObjectGet,
        null, // No setter
        null, // No enumerator
        @ptrCast(ctx),
    );
}

/// Cleanup
pub fn deinit() void {
    if (test_suites_initialized) {
        // Free test suite names, test case names, and cloned callbacks
        if (global_e2e_ctx) |ctx| {
            for (test_suites.items) |*suite| {
                ctx.allocator.free(suite.name);
                for (suite.tests.items) |test_case| {
                    ctx.allocator.free(test_case.name);
                    // Destroy cloned callback to prevent memory leak
                    c.hermes_value_destroy(test_case.callback);
                }
                suite.tests.deinit(ctx.allocator);
            }
            test_suites.deinit(ctx.allocator);
        }
        test_suites_initialized = false;
    }
    global_e2e_ctx = null;
    tests_complete = false;
    last_results = null;
}

// ============================================================================
// E2E Runner API (called from Zig, not JavaScript)
// ============================================================================

/// Track test completion state (for async tests)
var tests_complete: bool = false;
var last_results: ?TestResults = null;

/// State snapshot for before/after comparison (LLM debugging)
pub const StateSnapshot = struct {
    mode: []const u8,
    cursor_line: usize,
    cursor_col: usize,
    line_count: usize,
    /// First few lines of buffer for context (avoids huge JSON)
    buffer_preview: []const []const u8,
};

/// Checkpoint entry (labeled state snapshot during test)
pub const CheckpointEntry = struct {
    label: []const u8,
    state: StateSnapshot,
};

/// Test results structure returned to Zig runner
pub const TestResultEntry = struct {
    name: []const u8,
    suite: []const u8,
    passed: bool,
    error_message: ?[]const u8,
    duration_ms: i64,
    /// Console logs captured during test execution
    logs: std.ArrayListUnmanaged([]const u8),
    /// Editor state before test execution
    state_before: ?StateSnapshot,
    /// Editor state after test execution
    state_after: ?StateSnapshot,
    /// Checkpoints captured during test (via vim.e2e.checkpoint())
    checkpoints: std.ArrayListUnmanaged(CheckpointEntry),
    /// PTY (terminal ANSI) output captured during test execution
    /// Use for validating terminal escape codes (cursor flickering, colors, etc.)
    pty_output: ?[]const u8,
};

// ============================================================================
// State Capture (for LLM-friendly debugging)
// ============================================================================

/// Maximum lines to include in buffer preview (avoids huge JSON)
const MAX_PREVIEW_LINES: usize = 10;

/// Capture current editor state as a snapshot
fn captureStateSnapshot(allocator: std.mem.Allocator, ctx: *E2EContext) ?StateSnapshot {
    // Get current buffer (dynamic lookup for multi-window support)
    const buffer = ctx.getCurrentBuffer() orelse return null;

    // Get mode string (static, no allocation needed)
    const mode = ctx.mode_manager.getModeString();

    // Get line count
    const line_count = buffer.lineCount();

    // Capture first N lines for preview
    const preview_count = @min(line_count, MAX_PREVIEW_LINES);
    var preview_lines = allocator.alloc([]const u8, preview_count) catch return null;

    for (0..preview_count) |i| {
        if (buffer.getLine(i)) |line| {
            // Remove trailing newline for cleaner output
            const trimmed = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;
            preview_lines[i] = allocator.dupe(u8, trimmed) catch {
                allocator.free(line);
                // Free already allocated lines on error
                for (0..i) |j| {
                    allocator.free(preview_lines[j]);
                }
                allocator.free(preview_lines);
                return null;
            };
            allocator.free(line);
        } else {
            preview_lines[i] = "";
        }
    }

    return StateSnapshot{
        .mode = mode,
        .cursor_line = buffer.cursor.row,
        .cursor_col = buffer.cursor.col,
        .line_count = line_count,
        .buffer_preview = preview_lines,
    };
}

// ============================================================================
// Checkpoint Capture (for LLM-friendly debugging)
// ============================================================================

/// Per-test checkpoint buffer - captures vim.e2e.checkpoint() calls
var current_test_checkpoints: std.ArrayListUnmanaged(CheckpointEntry) = .empty;

/// vim.e2e.checkpoint(label) - Capture labeled state snapshot
/// Called during test execution to record intermediate states
fn checkpointCmd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = global_e2e_ctx orelse return helpers.returnUndefined(runtime);

    // Get label (optional, defaults to "checkpoint")
    var label: []const u8 = "checkpoint";
    if (arg_count >= 1) {
        if (args[0]) |arg| {
            if (c.hermes_value_is_string(arg)) {
                var label_len: usize = 0;
                const label_ptr = c.hermes_value_get_string(runtime, arg, &label_len);
                if (label_ptr != null and label_len > 0) {
                    // Duplicate label string
                    label = ctx.allocator.dupe(u8, label_ptr[0..label_len]) catch "checkpoint";
                }
            }
        }
    }

    // Capture current state
    if (captureStateSnapshot(ctx.allocator, ctx)) |state| {
        current_test_checkpoints.append(ctx.allocator, .{
            .label = label,
            .state = state,
        }) catch {};
    }

    return helpers.returnUndefined(runtime);
}

/// Get and clear current test checkpoints (returns ownership to caller)
fn getAndClearTestCheckpoints() std.ArrayListUnmanaged(CheckpointEntry) {
    const checkpoints = current_test_checkpoints;
    current_test_checkpoints = .empty;
    return checkpoints;
}

// ============================================================================
// Log Capture (for LLM-friendly debugging)
// ============================================================================

/// Per-test log buffer - captures console.log during test execution
var current_test_logs: std.ArrayListUnmanaged([]const u8) = .empty;
var log_capture_enabled: bool = false;

/// Global verbose flag - controls debug output during test execution
var g_verbose: bool = false;

/// Set verbose mode (called by test runner before tests execute)
pub fn setVerbose(verbose: bool) void {
    g_verbose = verbose;
}

/// Enable log capture (called before each test)
pub fn enableLogCapture() void {
    log_capture_enabled = true;
    // Note: current_test_logs is cleared before each test in runAllCmd
}

/// Disable log capture
pub fn disableLogCapture() void {
    log_capture_enabled = false;
}

/// Add a log entry (called from console.log override)
pub fn captureLog(msg: []const u8) void {
    if (!log_capture_enabled) return;
    const ctx = global_e2e_ctx orelse return;

    // Duplicate the string so it persists after caller frees it
    const msg_copy = ctx.allocator.dupe(u8, msg) catch return;
    current_test_logs.append(ctx.allocator, msg_copy) catch |err| {
        std.debug.print("[E2E] Failed to capture log: {}\n", .{err});
        ctx.allocator.free(msg_copy);
    };
}

/// Get and clear current test logs (returns ownership to caller)
fn getAndClearTestLogs() std.ArrayListUnmanaged([]const u8) {
    // Return current logs and reset to empty
    const logs = current_test_logs;
    current_test_logs = .empty;
    return logs;
}

pub const TestResults = struct {
    total: usize,
    passed: usize,
    failed: usize,
    tests: std.ArrayList(TestResultEntry),
};

/// Check if all E2E tests have completed (for async test support)
/// Called by E2E runner event loop
pub fn isComplete() bool {
    // For now, tests are complete after runAll() is called
    // In the future, this will support async tests with done() callbacks
    return tests_complete;
}

/// Get test results after completion
/// Called by E2E runner to build JSON report
pub fn getResults() TestResults {
    if (last_results) |results| {
        return results;
    }

    // Return empty results if no tests ran
    return TestResults{
        .total = 0,
        .passed = 0,
        .failed = 0,
        .tests = .empty,
    };
}

/// Mark tests as complete (called after runAll finishes)
fn markComplete(passed: usize, failed: usize, results: std.ArrayList(TestResultEntry)) void {
    tests_complete = true;
    last_results = TestResults{
        .total = passed + failed,
        .passed = passed,
        .failed = failed,
        .tests = results,
    };
}
