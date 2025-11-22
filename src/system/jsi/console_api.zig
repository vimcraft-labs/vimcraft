/// Console API Module
/// Handles console.log JSI function with Chrome DevTools Console integration
/// Forwards logs to BOTH CDP debugger AND editor.logger (Core→Backend architecture)
/// Also supports E2E mode log capture for LLM debugging
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;
const e2e_api = @import("e2e_api.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// Import CDP debugger for console.log
const cdp_c = @cImport({
    @cInclude("backends/headless/cdp_debugger.h");
});

/// Configuration for object serialization
const MAX_DEPTH: usize = 3; // Maximum nesting depth for objects
const MAX_PROPS_PER_LEVEL: usize = 20; // Max properties to show per object

/// Global editor pointer for console.log forwarding to logger
/// Can be either *Editor or *EditorContext - both have a logger field
/// Set during initialization - enables Core→Backend logging architecture
var global_editor_with_logger: ?*Editor = null;
var global_editor_context: ?*EditorContext = null;

/// Set the global editor for logging (either *Editor or *EditorContext)
pub fn setEditor(editor: anytype) void {
    const T = @TypeOf(editor);
    if (T == *Editor) {
        global_editor_with_logger = editor;
        global_editor_context = null;
    } else if (T == *EditorContext) {
        global_editor_context = editor;
        global_editor_with_logger = null;
    }
}

/// Format a JavaScript value recursively with depth limiting
/// Returns true if successful, false if should fallback to "[object]"
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
            writer.writeAll("\"") catch return false;
            writer.writeAll(str_ptr[0..str_len]) catch return false;
            writer.writeAll("\"") catch return false;
            return true;
        }
    } else if (c.hermes_value_is_number(value)) {
        const num = c.hermes_value_get_number(value);
        std.fmt.format(writer, "{d}", .{num}) catch return false;
        return true;
    } else if (c.hermes_value_is_boolean(value)) {
        const bool_val = c.hermes_value_get_boolean(value);
        writer.writeAll(if (bool_val) "true" else "false") catch return false;
        return true;
    } else if (c.hermes_value_is_null(value)) {
        writer.writeAll("null") catch return false;
        return true;
    } else if (c.hermes_value_is_undefined(value)) {
        writer.writeAll("undefined") catch return false;
        return true;
    } else if (c.hermes_value_is_object(value)) {
        // Check depth limit
        if (current_depth >= MAX_DEPTH) {
            writer.writeAll("[max depth]") catch return false;
            return true;
        }

        // Enumerate object properties
        return formatObject(writer, runtime, value, current_depth);
    }

    return false; // Unknown type
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

    // Check for exception after calling Object.keys()
    if (c.hermes_has_exception(runtime)) return false;
    if (keys_array == null or !c.hermes_value_is_object(keys_array)) return false;
    defer c.hermes_value_destroy(keys_array);

    const length_prop = c.hermes_value_get_property(runtime, keys_array, "length");
    if (length_prop == null or !c.hermes_value_is_number(length_prop)) return false;
    defer c.hermes_value_destroy(length_prop);

    const length = @as(usize, @intFromFloat(c.hermes_value_get_number(length_prop)));
    writer.writeAll("{") catch return false;

    const props_to_show = if (length > MAX_PROPS_PER_LEVEL) MAX_PROPS_PER_LEVEL else length;

    for (0..props_to_show) |idx| {
        if (idx > 0) writer.writeAll(", ") catch return false;

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
        writer.writeAll(key) catch return false;
        writer.writeAll(": ") catch return false;

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
            writer.writeAll("null") catch return false;
        }
    }

    if (length > MAX_PROPS_PER_LEVEL) {
        std.fmt.format(writer, ", ...+{d} more", .{length - MAX_PROPS_PER_LEVEL}) catch return false;
    }

    writer.writeAll("}") catch return false;
    return true;
}

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

        // When CDP debugger is active, DON'T also log to editor.logger
        // Otherwise the logger callback will send string logs back to debugger,
        // overriding the raw CDP values we just sent!
        return c.hermes_value_create_undefined(runtime_nullable);
    }

    // ONLY forward to editor.logger when NO CDP debugger (Backend 2: LLM Debug)
    // Convert JavaScript arguments to a single string
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    for (0..arg_count) |i| {
        if (i > 0) {
            writer.writeAll(" ") catch break;
        }

        const arg = args[i] orelse continue;

        // Convert JavaScript value to string (with recursive depth support)
        if (c.hermes_value_is_string(arg)) {
            // Strings are printed without quotes in console.log
            var str_len: usize = 0;
            const str_ptr = c.hermes_value_get_string(runtime, arg, &str_len);
            if (str_ptr != null) {
                writer.writeAll(str_ptr[0..str_len]) catch break;
            }
        } else {
            // All other types use the recursive formatter
            if (!formatJSValue(writer, runtime, arg, 0)) {
                writer.writeAll("[unknown]") catch break;
            }
        }
    }

    // Forward to logger (info level for console.log)
    // Only reaches here when NO CDP debugger (--headless-debug mode or no debugging)
    const log_message = fbs.getWritten();

    // Capture logs for E2E mode (LLM-friendly debugging)
    e2e_api.captureLog(log_message);

    if (global_editor_with_logger) |editor| {
        editor.logger.info("{s}", .{log_message}) catch {};
    } else if (global_editor_context) |ctx| {
        ctx.logger().info("{s}", .{log_message}) catch {};
    } else {
        // Fallback: write to stderr if no logger is set
        // This helps debug issues where setEditor wasn't called correctly
        std.debug.print("[console.log] {s}\n", .{log_message});
    }

    return c.hermes_value_create_undefined(runtime_nullable);
}

/// Register console API with runtime (no debugger)
pub fn register(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_function(
        runtime,
        "consoleLog",
        consoleLog,
        null, // No context (no debugger yet)
    );
}

/// Re-register console.log with debugger pointer
/// This should be called after debugger is created to enable Chrome Console output
pub fn registerWithDebugger(runtime: *c.OVHermesRuntime, debugger_ptr: *anyopaque) void {
    c.hermes_register_host_function(
        runtime,
        "consoleLog",
        consoleLog,
        debugger_ptr, // Pass debugger as context
    );
}
