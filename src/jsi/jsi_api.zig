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
/// Called from JavaScript: zigSetOption('cursorline', true)
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
    if (std.mem.eql(u8, name, "cursorline")) {
        const value = c.hermes_value_get_boolean(args[1]);
        config.cursorline_enabled = value;
    }

    return c.hermes_value_create_undefined(runtime);
}

// Import CDP debugger for console.log
const cdp_c = @cImport({
    @cInclude("debug/cdp_debugger.h");
});

/// Zig host function: zigConsoleLog(message)
/// Called from JavaScript: zigConsoleLog('Hello from JS')
/// Sends message to Chrome DevTools Console (or terminal if no debugger)
export fn zig_console_log(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    if (arg_count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Get message string from argument
    const msg_value = args[0] orelse return c.hermes_value_create_undefined(runtime);

    var msg_len: usize = 0;
    const msg_ptr = c.hermes_value_get_string(rt, msg_value, &msg_len);

    if (msg_ptr == null or msg_len == 0) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Send to Chrome debugger if available, otherwise do nothing (silent)
    if (context) |ctx| {
        // Context is CDPDebugger pointer - send to Chrome Console
        const debugger_ptr: *cdp_c.CDPDebugger = @ptrCast(@alignCast(ctx));
        cdp_c.cdp_debugger_log(debugger_ptr, msg_ptr, 0); // 0 = log level
    }
    // If no debugger, console.log does nothing (silent mode)

    return c.hermes_value_create_undefined(runtime);
}

/// Initialize JSI runtime and register host functions
pub fn initJSI(runtime: *c.OVHermesRuntime, config: *highlights.HighlightConfig) void {
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
        \\  log: function(msg) {{ zigConsoleLog(String(msg)); }}
        \\}};
        \\
        \\// vim API object
        \\const vim = {{
        \\  highlight: function(name, opts) {{
        \\    const bg = opts.bg || null;
        \\    const fg = opts.fg || null;
        \\    zigSetHighlight(name, bg, fg);
        \\  }},
        \\  opt: {{
        \\    set cursorline(value) {{ zigSetOption('cursorline', value); }},
        \\    get cursorline() {{ return true; }}
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
