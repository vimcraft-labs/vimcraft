const std = @import("std");
const highlights = @import("../config/highlights.zig");

// Import Hermes C API
const c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

/// Zig host function: zigSetHighlight(name, bg, fg)
/// Called from JavaScript: zigSetHighlight('CursorLine', '#2b2b2b', null)
export fn zig_set_highlight(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    // Get config from context
    const config = @as(*highlights.HighlightConfig, @ptrCast(@alignCast(context.?)));

    if (arg_count < 2) {
        std.debug.print("[JSI] zigSetHighlight: Need at least 2 args\n", .{});
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: highlight name (string)
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    const name = name_ptr[0..name_len];

    var hl = highlights.Highlight{};

    // Arg 1: background color (string or null)
    if (arg_count > 1 and !c.hermes_value_is_null(args[1])) {
        var bg_len: usize = 0;
        const bg_ptr = c.hermes_value_get_string(runtime, args[1], &bg_len);
        const bg_hex = bg_ptr[0..bg_len];

        hl.bg = highlights.Color.fromHex(bg_hex) catch {
            std.debug.print("[JSI] Invalid bg color: {s}\n", .{bg_hex});
            return c.hermes_value_create_undefined(runtime);
        };
    }

    // Arg 2: foreground color (string or null)
    if (arg_count > 2 and !c.hermes_value_is_null(args[2])) {
        var fg_len: usize = 0;
        const fg_ptr = c.hermes_value_get_string(runtime, args[2], &fg_len);
        const fg_hex = fg_ptr[0..fg_len];

        hl.fg = highlights.Color.fromHex(fg_hex) catch {
            std.debug.print("[JSI] Invalid fg color: {s}\n", .{fg_hex});
            return c.hermes_value_create_undefined(runtime);
        };
    }

    // Apply highlight to config
    config.setHighlight(name, hl);

    std.debug.print("[JSI] Set highlight '{s}' ", .{name});
    if (hl.bg) |bg| {
        std.debug.print("bg=#{x:0>2}{x:0>2}{x:0>2} ", .{ bg.r, bg.g, bg.b });
    }
    if (hl.fg) |fg| {
        std.debug.print("fg=#{x:0>2}{x:0>2}{x:0>2}", .{ fg.r, fg.g, fg.b });
    }
    std.debug.print("\n", .{});

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: zigSetOption(name, value)
/// Called from JavaScript: zigSetOption('cursorline', true)
export fn zig_set_option(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    // Get config from context
    const config = @as(*highlights.HighlightConfig, @ptrCast(@alignCast(context.?)));

    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: option name (string)
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    const name = name_ptr[0..name_len];

    // Arg 1: value (boolean, number, string, etc.)
    if (std.mem.eql(u8, name, "cursorline")) {
        const value = c.hermes_value_get_boolean(args[1]);
        config.cursorline_enabled = value;
        std.debug.print("[JSI] Set option cursorline = {}\n", .{value});
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Initialize JSI runtime and register host functions
pub fn initJSI(runtime: *c.OVHermesRuntime, config: *highlights.HighlightConfig) void {
    global_highlight_config = config;

    // Register Zig functions that JavaScript can call
    c.hermes_register_host_function(
        runtime,
        "zigSetHighlight",
        zig_set_highlight,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "zigSetOption",
        zig_set_option,
        null,
    );

    std.debug.print("[JSI] Registered host functions: zigSetHighlight, zigSetOption\n", .{});
}

/// Load and execute JavaScript configuration file
pub fn loadConfig(runtime: *c.OVHermesRuntime, filepath: []const u8) !void {
    std.debug.print("[JSI] Loading config: {s}\n", .{filepath});

    const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
        std.debug.print("[JSI] Could not open config file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(std.heap.page_allocator, 1_000_000);
    defer std.heap.page_allocator.free(source);

    const result = c.hermes_evaluate_javascript(
        runtime,
        source.ptr,
        source.len,
        filepath.ptr,
    );

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[JSI] JavaScript error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
    std.debug.print("[JSI] Config loaded successfully\n", .{});
}
