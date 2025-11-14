/// Console API Module
/// Handles console.log JSI function with Chrome DevTools Console integration
/// Forwards logs to BOTH CDP debugger AND editor.logger (Core→Backend architecture)
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/debug/editor_context.zig").EditorContext;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// Import CDP debugger for console.log
const cdp_c = @cImport({
    @cInclude("backends/debug/cdp_debugger.h");
});

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
        } else if (c.hermes_value_is_object(arg)) {
            // Object/Array - for text logs just show [object]
            writer.writeAll("[object]") catch break;
        } else {
            // Unknown type
            writer.writeAll("[unknown]") catch break;
        }
    }

    // Forward to logger (info level for console.log)
    // Only reaches here when NO CDP debugger (--debug-protocol mode or no debugging)
    const log_message = fbs.getWritten();
    if (global_editor_with_logger) |editor| {
        editor.logger.info("{s}", .{log_message}) catch {};
    } else if (global_editor_context) |ctx| {
        ctx.logger.info("{s}", .{log_message}) catch {};
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
