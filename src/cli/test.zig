/// vimc e2e - E2E Test Runner
///
/// Usage:
///   vimc e2e <sandbox_path>
///
/// Architecture:
///   - PTY (pseudo-terminal) for real terminal rendering
///   - Hermes runtime with vim.e2e API
///   - TypeScript → HBC pipeline (config.ts, e2e.ts)
///   - JSON report output
///   - Event loop for async test support
///
/// Sandbox structure:
///   tests/e2e/basic/
///   ├── config.ts    # Setup: buffer content, keymaps, options
///   └── e2e.ts       # Tests: vim.e2e.keys(), vim.e2e.assert.*

const std = @import("std");
const jsi_api = @import("../system/jsi/jsi_api.zig");
const highlights = @import("../editor/config/highlights.zig");
const EditorContext = @import("../backends/headless/editor_context.zig").EditorContext;
const c_api = @import("../system/jsi/c_api.zig");
const c = c_api.c;
const event_loop = @import("../system/event_loop/libuv.zig");
const timer_api = @import("../system/jsi/timer_api.zig");
const e2e_api = @import("../system/jsi/e2e_api.zig");

/// Test result structure for JSON output
pub const TestResult = struct {
    name: []const u8,
    suite: []const u8,
    passed: bool,
    error_message: ?[]const u8,
    duration_ms: i64,
    /// Console logs captured during test execution (LLM debugging)
    logs: []const []const u8,
    /// Editor state before test execution (LLM debugging)
    state_before: ?e2e_api.StateSnapshot,
    /// Editor state after test execution (LLM debugging)
    state_after: ?e2e_api.StateSnapshot,
    /// Checkpoints captured during test (LLM debugging)
    checkpoints: []const e2e_api.CheckpointEntry,
};

/// E2E test run summary
pub const TestSummary = struct {
    total: usize,
    passed: usize,
    failed: usize,
    duration_ms: i64,
    results: std.ArrayList(TestResult),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestSummary {
        return .{
            .total = 0,
            .passed = 0,
            .failed = 0,
            .duration_ms = 0,
            .results = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestSummary) void {
        self.results.deinit(self.allocator);
    }

    /// Output JSON report to stdout
    pub fn printJson(self: *const TestSummary) void {
        var buf: [8192]u8 = undefined;
        const stdout_file = std.fs.File.stdout();
        var stdout_writer = stdout_file.writer(&buf);
        const stdout = &stdout_writer.interface;

        stdout.print("{{\n", .{}) catch return;
        stdout.print("  \"total\": {},\n", .{self.total}) catch return;
        stdout.print("  \"passed\": {},\n", .{self.passed}) catch return;
        stdout.print("  \"failed\": {},\n", .{self.failed}) catch return;
        stdout.print("  \"duration_ms\": {},\n", .{self.duration_ms}) catch return;
        stdout.print("  \"tests\": [\n", .{}) catch return;

        for (self.results.items, 0..) |result, i| {
            stdout.print("    {{\n", .{}) catch return;
            stdout.print("      \"suite\": \"{s}\",\n", .{result.suite}) catch return;
            stdout.print("      \"name\": \"{s}\",\n", .{result.name}) catch return;
            stdout.print("      \"passed\": {},\n", .{result.passed}) catch return;
            if (result.error_message) |msg| {
                stdout.print("      \"error\": \"{s}\",\n", .{msg}) catch return;
            }
            stdout.print("      \"duration_ms\": {},\n", .{result.duration_ms}) catch return;

            // Logs array (LLM debugging)
            stdout.print("      \"logs\": [", .{}) catch return;
            for (result.logs, 0..) |log, log_idx| {
                // Escape JSON special characters in log message
                stdout.print("\"", .{}) catch return;
                for (log) |ch| {
                    switch (ch) {
                        '"' => stdout.print("\\\"", .{}) catch return,
                        '\\' => stdout.print("\\\\", .{}) catch return,
                        '\n' => stdout.print("\\n", .{}) catch return,
                        '\r' => stdout.print("\\r", .{}) catch return,
                        '\t' => stdout.print("\\t", .{}) catch return,
                        else => stdout.print("{c}", .{ch}) catch return,
                    }
                }
                stdout.print("\"", .{}) catch return;
                if (log_idx < result.logs.len - 1) {
                    stdout.print(", ", .{}) catch return;
                }
            }
            stdout.print("],\n", .{}) catch return;

            // State before test (LLM debugging)
            stdout.print("      \"state_before\": ", .{}) catch return;
            printStateSnapshot(stdout, result.state_before);
            stdout.print(",\n", .{}) catch return;

            // State after test (LLM debugging)
            stdout.print("      \"state_after\": ", .{}) catch return;
            printStateSnapshot(stdout, result.state_after);
            stdout.print(",\n", .{}) catch return;

            // Checkpoints array (LLM debugging)
            stdout.print("      \"checkpoints\": [", .{}) catch return;
            for (result.checkpoints, 0..) |checkpoint, cp_idx| {
                stdout.print("{{\"label\": \"{s}\", \"state\": ", .{checkpoint.label}) catch return;
                // Wrap in optional for printStateSnapshot
                const optional_state: ?e2e_api.StateSnapshot = checkpoint.state;
                printStateSnapshot(stdout, optional_state);
                stdout.print("}}", .{}) catch return;
                if (cp_idx < result.checkpoints.len - 1) {
                    stdout.print(", ", .{}) catch return;
                }
            }
            stdout.print("]\n", .{}) catch return;

            if (i < self.results.items.len - 1) {
                stdout.print("    }},\n", .{}) catch return;
            } else {
                stdout.print("    }}\n", .{}) catch return;
            }
        }

        stdout.print("  ]\n", .{}) catch return;
        stdout.print("}}\n", .{}) catch return;
        stdout.flush() catch return;
    }
};

/// Print a state snapshot as JSON (helper for printJson)
fn printStateSnapshot(stdout: anytype, state: ?e2e_api.StateSnapshot) void {
    if (state == null) {
        stdout.print("null", .{}) catch return;
        return;
    }
    const s = state.?;

    stdout.print("{{", .{}) catch return;
    stdout.print("\"mode\": \"{s}\", ", .{s.mode}) catch return;
    stdout.print("\"cursor\": {{\"line\": {d}, \"col\": {d}}}, ", .{ s.cursor_line, s.cursor_col }) catch return;
    stdout.print("\"line_count\": {d}, ", .{s.line_count}) catch return;

    // Buffer preview (array of strings)
    stdout.print("\"buffer_preview\": [", .{}) catch return;
    for (s.buffer_preview, 0..) |line, line_idx| {
        // Escape JSON special characters
        stdout.print("\"", .{}) catch return;
        for (line) |ch| {
            switch (ch) {
                '"' => stdout.print("\\\"", .{}) catch return,
                '\\' => stdout.print("\\\\", .{}) catch return,
                '\n' => stdout.print("\\n", .{}) catch return,
                '\r' => stdout.print("\\r", .{}) catch return,
                '\t' => stdout.print("\\t", .{}) catch return,
                else => stdout.print("{c}", .{ch}) catch return,
            }
        }
        stdout.print("\"", .{}) catch return;
        if (line_idx < s.buffer_preview.len - 1) {
            stdout.print(", ", .{}) catch return;
        }
    }
    stdout.print("]", .{}) catch return;

    stdout.print("}}", .{}) catch return;
}

/// Execute E2E tests in sandbox directory
/// Returns exit code: 0 = all passed, 1 = some failed
pub fn execute(allocator: std.mem.Allocator, sandbox_path: []const u8) !u8 {
    const start_time = std.time.milliTimestamp();

    // Verify sandbox path exists
    std.fs.cwd().access(sandbox_path, .{}) catch {
        std.debug.print("Error: Sandbox path not found: {s}\n", .{sandbox_path});
        return error.SandboxNotFound;
    };

    // Check for config.ts and e2e.ts
    const config_path = try std.fmt.allocPrint(allocator, "{s}/config.ts", .{sandbox_path});
    defer allocator.free(config_path);

    const e2e_path = try std.fmt.allocPrint(allocator, "{s}/e2e.ts", .{sandbox_path});
    defer allocator.free(e2e_path);

    // config.ts is optional, e2e.ts is required
    const has_config = blk: {
        std.fs.cwd().access(config_path, .{}) catch break :blk false;
        break :blk true;
    };

    std.fs.cwd().access(e2e_path, .{}) catch {
        std.debug.print("Error: e2e.ts not found in sandbox: {s}\n", .{sandbox_path});
        return error.E2EFileNotFound;
    };

    // Initialize libuv event loop (for async tests)
    try event_loop.init();
    defer event_loop.deinit();

    // Create EditorContext with PTY (pseudo-terminal)
    // This enables real terminal rendering for visual bug detection
    var editor_ctx = try EditorContext.init(allocator);
    defer editor_ctx.deinit();

    // Initialize highlight configuration
    var highlight_config = highlights.HighlightConfig.init(allocator);
    defer highlight_config.deinit();

    // Initialize options manager
    const OptionsManager = @import("../editor/config/options.zig").OptionsManager;
    var options_mgr = OptionsManager.init(allocator);
    defer options_mgr.deinit();

    // Wire options manager to editor context
    editor_ctx.setOptionsManager(&options_mgr);

    // Create Hermes runtime
    const runtime = c.hermes_runtime_create() orelse {
        std.debug.print("Error: Failed to create Hermes runtime\n", .{});
        return error.RuntimeInitFailed;
    };
    defer c.hermes_runtime_destroy(runtime);

    // Initialize full JSI API (vim.motion, vim.cursor, vim.buffer, vim.e2e, etc.)
    jsi_api.initJSI(allocator, @ptrCast(runtime), &highlight_config, &options_mgr, &editor_ctx, &editor_ctx.display);
    defer jsi_api.deinitJSI();

    // Initialize timer system for async tests
    timer_api.init(allocator, @ptrCast(runtime));
    defer timer_api.deinit();

    // Register console.log to print to stderr (tests output to stdout as JSON)
    c.hermes_register_host_function(
        runtime,
        "consoleLog",
        stderrConsoleLog,
        null,
    );

    // Transpiler and bytecode compilation
    const esbuild = @import("../system/transpiler/esbuild.zig");
    const hermes = @import("../system/transpiler/hermes.zig");
    const runtime_wrapper = @embedFile("../system/jsi/runtime.js");

    // Step 1: Load config.ts (if exists) - sets up buffer, keymaps, options
    if (has_config) {
        const config_js = esbuild.build(allocator, config_path) catch |err| {
            std.debug.print("Error: Failed to bundle config.ts: {}\n", .{err});
            return error.ConfigBundleFailed;
        };
        defer allocator.free(config_js);

        const config_wrapped = try std.fmt.allocPrint(allocator,
            \\{s}
            \\
            \\// Config script (bundled)
            \\{s}
        , .{ runtime_wrapper, config_js });
        defer allocator.free(config_wrapped);

        const config_bytecode = hermes.compile(allocator, config_wrapped) catch |err| {
            std.debug.print("Error: Failed to compile config.ts: {}\n", .{err});
            return error.ConfigCompileFailed;
        };
        defer allocator.free(config_bytecode);

        const config_result = c.hermes_evaluate_bytecode(runtime, config_bytecode.ptr, config_bytecode.len);
        if (config_result == null and c.hermes_has_exception(runtime)) {
            const err_msg = c.hermes_get_exception_message(runtime);
            if (err_msg != null) {
                std.debug.print("Error in config.ts: {s}\n", .{std.mem.span(err_msg)});
            }
            return error.ConfigExecutionFailed;
        }
    }

    // Step 2: Load e2e.ts - runs tests using vim.e2e API
    const e2e_js = esbuild.build(allocator, e2e_path) catch |err| {
        std.debug.print("Error: Failed to bundle e2e.ts: {}\n", .{err});
        return error.E2EBundleFailed;
    };
    defer allocator.free(e2e_js);

    // Only include runtime wrapper once (config.ts already loaded it if present)
    const e2e_wrapped = if (has_config)
        try std.fmt.allocPrint(allocator,
            \\// E2E test script (bundled)
            \\{s}
        , .{e2e_js})
    else
        try std.fmt.allocPrint(allocator,
            \\{s}
            \\
            \\// E2E test script (bundled)
            \\{s}
        , .{ runtime_wrapper, e2e_js });
    defer allocator.free(e2e_wrapped);

    const e2e_bytecode = hermes.compile(allocator, e2e_wrapped) catch |err| {
        std.debug.print("Error: Failed to compile e2e.ts: {}\n", .{err});
        return error.E2ECompileFailed;
    };
    defer allocator.free(e2e_bytecode);

    const e2e_result = c.hermes_evaluate_bytecode(runtime, e2e_bytecode.ptr, e2e_bytecode.len);
    if (e2e_result == null and c.hermes_has_exception(runtime)) {
        const err_msg = c.hermes_get_exception_message(runtime);
        if (err_msg != null) {
            std.debug.print("Error in e2e.ts: {s}\n", .{std.mem.span(err_msg)});
        }
        return error.E2EExecutionFailed;
    }

    // Step 3: Run event loop until tests complete (async support)
    // This allows setTimeout/setInterval in tests
    const timeout_ns: i128 = 30 * std.time.ns_per_s; // 30 second timeout
    const loop_start = std.time.nanoTimestamp();

    while (!e2e_api.isComplete() or event_loop.isAlive()) {
        // Check timeout
        const elapsed = std.time.nanoTimestamp() - loop_start;
        if (elapsed > timeout_ns) {
            std.debug.print("Error: E2E tests timed out after 30 seconds\n", .{});
            return error.TestTimeout;
        }

        // Process libuv events (timers, etc.)
        _ = event_loop.runOnce();

        // Process timer callbacks (calls JavaScript)
        timer_api.processQueue(allocator);

        // Small sleep to prevent CPU spin
        std.Thread.sleep(1_000_000); // 1ms
    }

    // Step 4: Get test results from vim.e2e
    const results = e2e_api.getResults();
    const end_time = std.time.milliTimestamp();

    // Build summary
    var summary = TestSummary.init(allocator);
    defer summary.deinit();

    summary.total = results.total;
    summary.passed = results.passed;
    summary.failed = results.failed;
    summary.duration_ms = end_time - start_time;

    // Copy test results
    for (results.tests.items) |test_result| {
        try summary.results.append(allocator, .{
            .name = test_result.name,
            .suite = test_result.suite,
            .passed = test_result.passed,
            .error_message = test_result.error_message,
            .duration_ms = test_result.duration_ms,
            .logs = test_result.logs.items,
            .state_before = test_result.state_before,
            .state_after = test_result.state_after,
            .checkpoints = test_result.checkpoints.items,
        });
    }

    // Output JSON report to stdout
    summary.printJson();

    // Return exit code
    return if (summary.failed > 0) 1 else 0;
}

/// Console.log implementation for E2E (prints to stderr, JSON goes to stdout)
/// Also captures logs for LLM debugging via e2e_api.captureLog
export fn stderrConsoleLog(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    // Build log message into buffer for both stderr and capture
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    for (0..arg_count) |i| {
        if (i > 0) {
            writer.writeAll(" ") catch break;
        }

        const arg = args[i] orelse continue;

        if (c.hermes_value_is_string(arg)) {
            var str_len: usize = 0;
            const str_ptr = c.hermes_value_get_string(rt, arg, &str_len);
            if (str_ptr != null) {
                writer.writeAll(str_ptr[0..str_len]) catch break;
            }
        } else if (c.hermes_value_is_number(arg)) {
            const num = c.hermes_value_get_number(arg);
            std.fmt.format(writer, "{d}", .{num}) catch break;
        } else if (c.hermes_value_is_boolean(arg)) {
            writer.writeAll(if (c.hermes_value_get_boolean(arg)) "true" else "false") catch break;
        } else if (c.hermes_value_is_null(arg)) {
            writer.writeAll("null") catch break;
        } else if (c.hermes_value_is_undefined(arg)) {
            writer.writeAll("undefined") catch break;
        } else {
            writer.writeAll("[object]") catch break;
        }
    }

    const log_msg = fbs.getWritten();

    // Print to stderr
    std.debug.print("{s}\n", .{log_msg});

    // Capture for LLM debugging (per-test log buffer)
    e2e_api.captureLog(log_msg);

    return c.hermes_value_create_undefined(runtime);
}
