/// vimc run - Execute TypeScript files with vim.* globals
///
/// Usage:
///   vimc run script.ts
///   vimc run script.ts --debug
///   vimc run script.ts --no-cache

const std = @import("std");
const transpiler = @import("../system/transpiler/esbuild.zig");
const jsi = @import("../system/jsi/jsi_api.zig");
const c_api = @import("../system/jsi/c_api.zig");
const c = c_api.c;

/// Execute TypeScript file with vim.* API available
pub fn execute(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    debug_mode: bool,
    no_cache: bool,
) !void {
    // Step 1: Check if file exists
    const file_exists = blk: {
        std.fs.cwd().access(file_path, .{}) catch {
            std.debug.print("Error: File not found: {s}\n", .{file_path});
            return error.FileNotFound;
        };
        break :blk true;
    };
    _ = file_exists;

    if (debug_mode) {
        std.debug.print("[vimc run] Executing: {s}\n", .{file_path});
        std.debug.print("[vimc run] Cache: {s}\n", .{if (no_cache) "disabled" else "enabled"});
    }

    // Step 2: Read file content
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
        std.debug.print("Error: Failed to read file: {}\n", .{err});
        return err;
    };
    defer allocator.free(source);

    // Step 3: Initialize Hermes runtime (full runtime for JavaScript evaluation)
    const runtime = c.hermes_runtime_create() orelse {
        std.debug.print("Error: Failed to create Hermes runtime\n", .{});
        return error.RuntimeInitFailed;
    };
    defer c.hermes_runtime_destroy(runtime);

    // Step 4: Register minimal console.log for debugging
    c.hermes_register_host_function(
        runtime,
        "console_log",
        vimcRunConsoleLog,
        null,
    );

    // Step 5: Inject console.log into global scope
    const inject_console =
        \\globalThis.console = {
        \\  log: (...args) => console_log(args.map(String).join(' ')),
        \\  error: (...args) => console_log('ERROR: ' + args.map(String).join(' ')),
        \\  warn: (...args) => console_log('WARN: ' + args.map(String).join(' ')),
        \\};
    ;
    const inject_result = c.hermes_evaluate_javascript(runtime, inject_console.ptr, inject_console.len, "<console>");
    if (inject_result == null) {
        std.debug.print("Error: Failed to inject console API\n", .{});
        return error.InjectFailed;
    }

    // Step 6: Determine file type and transpile if needed
    const is_typescript = std.mem.endsWith(u8, file_path, ".ts") or std.mem.endsWith(u8, file_path, ".tsx");

    const javascript = if (is_typescript) blk: {
        if (debug_mode) std.debug.print("[vimc run] Transpiling TypeScript...\n", .{});

        const loader = if (std.mem.endsWith(u8, file_path, ".tsx")) "tsx" else "ts";
        const transpiled = transpiler.transpile(allocator, source, loader) catch |err| {
            std.debug.print("Error: Transpilation failed: {}\n", .{err});
            return err;
        };

        if (debug_mode) std.debug.print("[vimc run] Transpiled successfully\n", .{});
        break :blk transpiled;
    } else blk: {
        // JavaScript file - use as-is
        break :blk try allocator.dupe(u8, source);
    };
    defer allocator.free(javascript);

    // Step 7: Execute JavaScript
    if (debug_mode) std.debug.print("[vimc run] Executing JavaScript...\n", .{});

    const source_url_z = try allocator.dupeZ(u8, file_path);
    defer allocator.free(source_url_z);

    const result = c.hermes_evaluate_javascript(runtime, javascript.ptr, javascript.len, source_url_z.ptr);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("\n[JavaScript Error]\n{s}\n", .{err_msg});
        return error.JSError;
    }

    // Step 8: Print result if not undefined
    var str_len: usize = 0;
    const result_str = c.hermes_value_get_string(runtime, result, &str_len);
    const result_zig = std.mem.span(result_str);

    if (!std.mem.eql(u8, result_zig, "undefined")) {
        std.debug.print("\n[Result] {s}\n", .{result_zig});
    }

    if (debug_mode) std.debug.print("[vimc run] Execution complete\n", .{});
}

/// Console.log implementation for vimc run
export fn vimcRunConsoleLog(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count > 0) {
        const message_val = args[0] orelse return c.hermes_value_create_undefined(runtime);
        var msg_len: usize = 0;
        const message_ptr = c.hermes_value_get_string(runtime, message_val, &msg_len);
        const message = std.mem.span(message_ptr);

        // Print to stdout (not debug output)
        std.debug.print("{s}\n", .{message});
    }

    return c.hermes_value_create_undefined(runtime);
}
