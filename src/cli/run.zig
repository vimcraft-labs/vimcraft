/// vimc run - Execute TypeScript files with full vim.* API
///
/// Usage:
///   vimc run script.ts
///   vimc run script.ts --debug
///   vimc run script.ts --no-cache
///
/// Features:
///   - Full vim.* API (motion, cursor, buffer, layer, etc.)
///   - require() support for imports
///   - console.log output to stdout
///   - Headless execution (no editor UI)

const std = @import("std");
const jsi_api = @import("../system/jsi/jsi_api.zig");
const highlights = @import("../editor/config/highlights.zig");
const EditorContext = @import("../backends/debug/editor_context.zig").EditorContext;
const c_api = @import("../system/jsi/c_api.zig");
const c = c_api.c;

/// Execute TypeScript file with full vim.* API available
pub fn execute(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    debug_mode: bool,
    no_cache: bool,
) !void {
    _ = no_cache; // TODO: Implement cache control

    // Check if file exists
    std.fs.cwd().access(file_path, .{}) catch {
        std.debug.print("Error: File not found: {s}\n", .{file_path});
        return error.FileNotFound;
    };

    if (debug_mode) {
        std.debug.print("[vimc run] Executing: {s}\n", .{file_path});
    }

    // Create headless editor context (provides Display for vim.layer API)
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
    editor_ctx.options_manager = &options_mgr;

    // Create Hermes runtime
    const runtime = c.hermes_runtime_create() orelse {
        std.debug.print("Error: Failed to create Hermes runtime\n", .{});
        return error.RuntimeInitFailed;
    };
    defer c.hermes_runtime_destroy(runtime);

    // Initialize full JSI API (vim.motion, vim.cursor, vim.buffer, vim.layer, etc.)
    jsi_api.initJSI(allocator, @ptrCast(runtime), &highlight_config, &options_mgr, &editor_ctx, &editor_ctx.display);
    defer jsi_api.deinitJSI();

    // Register console.log to print to stdout (not logger)
    // This overrides the default console.log that goes to logger
    c.hermes_register_host_function(
        runtime,
        "consoleLog",
        stdoutConsoleLog,
        null,
    );

    // Load and execute the TypeScript file
    // REPL mode: No caching, always compile fresh for immediate feedback
    // This is intentional - vimc run is for quick experimentation, not production
    const esbuild = @import("../system/transpiler/esbuild.zig");
    const hermes = @import("../system/transpiler/hermes.zig");
    const runtime_wrapper = @embedFile("../system/jsi/runtime.js");

    if (debug_mode) {
        std.debug.print("[vimc run] Bundling with esbuild...\n", .{});
    }

    // Bundle the script (resolves imports, transpiles TypeScript)
    const bundled_js = esbuild.build(allocator, file_path) catch |err| {
        std.debug.print("Error: Failed to bundle script: {}\n", .{err});
        return err;
    };
    defer allocator.free(bundled_js);

    if (debug_mode) {
        std.debug.print("[vimc run] Wrapping with runtime...\n", .{});
    }

    // Wrap with runtime.js (provides require(), etc.)
    const wrapped_source = try std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\// User script (bundled)
        \\{s}
    , .{ runtime_wrapper, bundled_js });
    defer allocator.free(wrapped_source);

    if (debug_mode) {
        std.debug.print("[vimc run] Compiling to bytecode...\n", .{});
    }

    // Compile to bytecode (no caching)
    const bytecode = hermes.compile(allocator, wrapped_source) catch |err| {
        std.debug.print("Error: Failed to compile script: {}\n", .{err});
        return err;
    };
    defer allocator.free(bytecode);

    if (debug_mode) {
        std.debug.print("[vimc run] Executing bytecode...\n", .{});
    }

    // Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);
    if (result == null or c.hermes_value_is_undefined(result)) {
        const err_msg = c.hermes_get_exception_message(runtime);
        if (err_msg != null) {
            const err_str = std.mem.span(err_msg);
            std.debug.print("Error: Execution failed: {s}\n", .{err_str});
        }
        return error.ExecutionFailed;
    }

    if (debug_mode) {
        std.debug.print("[vimc run] Execution complete\n", .{});
    }
}

/// Configuration for object serialization
const MAX_DEPTH: usize = 3;
const MAX_PROPS_PER_LEVEL: usize = 20;

/// ANSI color codes for syntax highlighting
const Color = struct {
    const RESET = "\x1b[0m";
    const KEY = "\x1b[36m"; // Cyan for keys
    const STRING = "\x1b[32m"; // Green for strings
    const NUMBER = "\x1b[33m"; // Yellow for numbers
    const BOOLEAN = "\x1b[35m"; // Magenta for booleans
    const NULL = "\x1b[90m"; // Gray for null/undefined
    const PUNCTUATION = "\x1b[37m"; // White for {}, [], :, ,
};

/// Format a JavaScript value recursively with colors and indentation
fn formatJSValue(
    writer: anytype,
    runtime: *c.OVHermesRuntime,
    value: *c.OVHermesValue,
    current_depth: usize,
) bool {
    if (c.hermes_value_is_string(value)) {
        var str_len: usize = 0;
        const str_ptr = c.hermes_value_get_string(runtime, value, &str_len);
        if (str_ptr != null) {
            writer.writeAll(Color.STRING) catch return false;
            writer.writeAll("\"") catch return false;
            writer.writeAll(str_ptr[0..str_len]) catch return false;
            writer.writeAll("\"") catch return false;
            writer.writeAll(Color.RESET) catch return false;
            return true;
        }
    } else if (c.hermes_value_is_number(value)) {
        const num = c.hermes_value_get_number(value);
        writer.writeAll(Color.NUMBER) catch return false;
        std.fmt.format(writer, "{d}", .{num}) catch return false;
        writer.writeAll(Color.RESET) catch return false;
        return true;
    } else if (c.hermes_value_is_boolean(value)) {
        const bool_val = c.hermes_value_get_boolean(value);
        writer.writeAll(Color.BOOLEAN) catch return false;
        writer.writeAll(if (bool_val) "true" else "false") catch return false;
        writer.writeAll(Color.RESET) catch return false;
        return true;
    } else if (c.hermes_value_is_null(value)) {
        writer.writeAll(Color.NULL) catch return false;
        writer.writeAll("null") catch return false;
        writer.writeAll(Color.RESET) catch return false;
        return true;
    } else if (c.hermes_value_is_undefined(value)) {
        writer.writeAll(Color.NULL) catch return false;
        writer.writeAll("undefined") catch return false;
        writer.writeAll(Color.RESET) catch return false;
        return true;
    } else if (c.hermes_value_is_object(value)) {
        // Check depth limit
        if (current_depth >= MAX_DEPTH) {
            writer.writeAll(Color.NULL) catch return false;
            writer.writeAll("[max depth]") catch return false;
            writer.writeAll(Color.RESET) catch return false;
            return true;
        }

        // Format object
        return formatObject(writer, runtime, value, current_depth);
    }

    return false; // Unknown type
}

/// Write indentation (2 spaces per level)
fn writeIndent(writer: anytype, depth: usize) void {
    for (0..depth * 2) |_| {
        writer.writeAll(" ") catch return;
    }
}

/// Format an object by enumerating its properties
fn formatObject(
    writer: anytype,
    runtime: *c.OVHermesRuntime,
    obj: *c.OVHermesValue,
    current_depth: usize,
) bool {
    const global_obj = c.hermes_get_global_object(runtime);
    defer c.hermes_object_destroy(global_obj);

    const obj_ctor = c.hermes_object_get_property(runtime, global_obj, "Object");
    if (obj_ctor == null) return false;
    defer c.hermes_value_destroy(obj_ctor);

    const keys_func = c.hermes_value_get_property(runtime, obj_ctor, "keys");
    if (keys_func == null or !c.hermes_value_is_function(runtime, keys_func)) return false;
    defer c.hermes_value_destroy(keys_func);

    var keys_args = [_]?*c.OVHermesValue{obj};
    const keys_array = c.hermes_call_function(runtime, keys_func, &keys_args, 1);

    if (c.hermes_has_exception(runtime)) return false;
    if (keys_array == null or !c.hermes_value_is_object(keys_array)) return false;
    defer c.hermes_value_destroy(keys_array);

    const length_prop = c.hermes_value_get_property(runtime, keys_array, "length");
    if (length_prop == null or !c.hermes_value_is_number(length_prop)) return false;
    defer c.hermes_value_destroy(length_prop);

    const length = @as(usize, @intFromFloat(c.hermes_value_get_number(length_prop)));

    // Opening brace with color
    writer.writeAll(Color.PUNCTUATION) catch return false;
    writer.writeAll("{") catch return false;
    writer.writeAll(Color.RESET) catch return false;

    const props_to_show = if (length > MAX_PROPS_PER_LEVEL) MAX_PROPS_PER_LEVEL else length;

    // Multi-line formatting
    if (props_to_show > 0) {
        writer.writeAll("\n") catch return false;
    }

    for (0..props_to_show) |idx| {
        writeIndent(writer, current_depth + 1);

        // Get key name
        var idx_buf: [32]u8 = undefined;
        const idx_str_null = std.fmt.bufPrintZ(&idx_buf, "{d}", .{idx}) catch return false;
        const key_val = c.hermes_value_get_property(runtime, keys_array, idx_str_null.ptr);
        if (key_val == null or !c.hermes_value_is_string(key_val)) continue;
        defer c.hermes_value_destroy(key_val);

        var key_len: usize = 0;
        const key_ptr = c.hermes_value_get_string(runtime, key_val, &key_len);
        if (key_ptr == null) continue;

        const key = key_ptr[0..key_len];

        // Key with color
        writer.writeAll(Color.KEY) catch return false;
        writer.writeAll(key) catch return false;
        writer.writeAll(Color.RESET) catch return false;

        // Colon with color
        writer.writeAll(Color.PUNCTUATION) catch return false;
        writer.writeAll(": ") catch return false;
        writer.writeAll(Color.RESET) catch return false;

        // Get property value
        var key_buf: [256]u8 = undefined;
        if (key_len >= key_buf.len) continue;
        @memcpy(key_buf[0..key_len], key);
        key_buf[key_len] = 0;

        const val = c.hermes_value_get_property(runtime, obj, &key_buf);
        if (val) |value| {
            defer c.hermes_value_destroy(value);
            // Recursively format the value (depth + 1)
            if (!formatJSValue(writer, runtime, value, current_depth + 1)) {
                writer.writeAll("[error]") catch return false;
            }
        } else {
            writer.writeAll(Color.NULL) catch return false;
            writer.writeAll("null") catch return false;
            writer.writeAll(Color.RESET) catch return false;
        }

        // Comma separator
        if (idx < props_to_show - 1 or length > MAX_PROPS_PER_LEVEL) {
            writer.writeAll(Color.PUNCTUATION) catch return false;
            writer.writeAll(",") catch return false;
            writer.writeAll(Color.RESET) catch return false;
        }
        writer.writeAll("\n") catch return false;
    }

    // Show "...+N more" message
    if (length > MAX_PROPS_PER_LEVEL) {
        writeIndent(writer, current_depth + 1);
        writer.writeAll(Color.NULL) catch return false;
        std.fmt.format(writer, "...+{d} more", .{length - MAX_PROPS_PER_LEVEL}) catch return false;
        writer.writeAll(Color.RESET) catch return false;
        writer.writeAll("\n") catch return false;
    }

    // Closing brace with proper indentation
    if (props_to_show > 0) {
        writeIndent(writer, current_depth);
    }
    writer.writeAll(Color.PUNCTUATION) catch return false;
    writer.writeAll("}") catch return false;
    writer.writeAll(Color.RESET) catch return false;

    return true;
}

/// Console.log implementation for vimc run (prints to stdout)
export fn stdoutConsoleLog(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    // Format all arguments
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
            // Strings are printed without quotes in console.log
            var str_len: usize = 0;
            const str_ptr = c.hermes_value_get_string(rt, arg, &str_len);
            if (str_ptr != null) {
                writer.writeAll(str_ptr[0..str_len]) catch break;
            }
        } else {
            // All other types use the recursive formatter
            if (!formatJSValue(writer, rt, arg, 0)) {
                writer.writeAll("[unknown]") catch break;
            }
        }
    }

    // Print to stdout
    const message = fbs.getWritten();
    std.debug.print("{s}\n", .{message});

    return c.hermes_value_create_undefined(runtime);
}
