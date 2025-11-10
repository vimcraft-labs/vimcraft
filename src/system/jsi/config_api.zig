/// Configuration API Module
/// Handles setHighlight and setOption JSI functions
/// Allows JavaScript to configure editor appearance and behavior

const std = @import("std");
const highlights = @import("../../editor/config/highlights.zig");
const helpers = @import("helpers.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Zig host function: setHighlight(name, bg, fg)
/// Called from JavaScript: setHighlight('CursorLine', '#2b2b2b', null)
export fn setHighlight(
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

/// Zig host function: setOption(name, value)
/// Called from JavaScript: setOption('cursorLine', true)
export fn setOption(
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

/// Register configuration API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, config: *highlights.HighlightConfig) void {
    c.hermes_register_host_function(
        runtime,
        "setHighlight",
        setHighlight,
        @ptrCast(config), // Pass config as context
    );

    c.hermes_register_host_function(
        runtime,
        "setOption",
        setOption,
        @ptrCast(config), // Pass config as context
    );
}
