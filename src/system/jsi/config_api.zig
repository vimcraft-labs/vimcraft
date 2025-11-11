/// Configuration API Module
/// Handles setHighlight, setOption, and getOption JSI functions
/// Allows JavaScript to configure editor appearance and behavior
const std = @import("std");
const highlights = @import("../../editor/config/highlights.zig");
const options_mod = @import("../../editor/config/options.zig");
const option_defs = @import("../../editor/config/option_defs.zig");
const helpers = @import("helpers.zig");

const OptionsManager = options_mod.OptionsManager;
const OptionValue = options_mod.OptionValue;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context for configuration API (passed to all config functions)
pub const ConfigContext = struct {
    highlight_config: *highlights.HighlightConfig,
    options_manager: *OptionsManager,
    allocator: std.mem.Allocator,
};

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

    // Get context
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const config = ctx.highlight_config;

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

/// Zig host function: getOption(name)
/// Called from JavaScript: getOption('number')
/// Returns the option value or undefined if not found/set
export fn getOption(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Unwrap nullable runtime
    const runtime = runtime_nullable orelse return null;

    // Get context
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));

    if (arg_count < 1) {
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

    // Get option value from OptionsManager
    const opt_value = ctx.options_manager.get(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Convert OptionValue to Hermes value
    return switch (opt_value) {
        .boolean => |v| c.hermes_value_create_boolean(runtime, v),
        .number => |v| c.hermes_value_create_number(runtime, @floatFromInt(v)),
        .string => |s| c.hermes_value_create_string(runtime, s.ptr, s.len),
    };
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

    // Get context
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));

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

    // Convert name to lowercase for lookup (support both camelCase and lowercase)
    var lower_name_buf: [256]u8 = undefined;
    if (name_len >= lower_name_buf.len) return c.hermes_value_create_undefined(runtime);
    for (name, 0..) |char, i| {
        lower_name_buf[i] = std.ascii.toLower(char);
    }
    const lower_name = lower_name_buf[0..name_len];

    // Look up option metadata (use lowercase for lookup)
    const meta = option_defs.getOptionMeta(lower_name) orelse {
        // Unknown option - ignore silently (Vim behavior)
        return c.hermes_value_create_undefined(runtime);
    };

    // Arg 1: value - convert based on expected type
    const opt_value: OptionValue = switch (meta.type) {
        .boolean => blk: {
            if (!c.hermes_value_is_boolean(args[1])) {
                return c.hermes_value_create_undefined(runtime);
            }
            const value = c.hermes_value_get_boolean(args[1]);
            break :blk .{ .boolean = value };
        },
        .number => blk: {
            if (!c.hermes_value_is_number(args[1])) {
                return c.hermes_value_create_undefined(runtime);
            }
            const value = c.hermes_value_get_number(args[1]);
            break :blk .{ .number = @intFromFloat(value) };
        },
        .string => blk: {
            if (!c.hermes_value_is_string(args[1])) {
                return c.hermes_value_create_undefined(runtime);
            }
            var value_len: usize = 0;
            const value_ptr = c.hermes_value_get_string(runtime, args[1], &value_len);
            if (value_ptr == null) {
                return c.hermes_value_create_undefined(runtime);
            }
            const value_str = value_ptr[0..value_len];
            break :blk .{ .string = value_str };
        },
    };

    // Validate the option value
    if (!option_defs.validateOption(meta, opt_value)) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Store in OptionsManager (using lowercase name for consistency)
    ctx.options_manager.set(lower_name, opt_value) catch {
        return c.hermes_value_create_undefined(runtime);
    };

    // Apply side effects for specific options
    applySideEffects(ctx, lower_name, opt_value);

    return c.hermes_value_create_undefined(runtime);
}

/// Apply side effects when certain options are set
/// For example, cursorline should update HighlightConfig
fn applySideEffects(ctx: *ConfigContext, name: []const u8, value: OptionValue) void {
    if (std.mem.eql(u8, name, "cursorline")) {
        if (value == .boolean) {
            ctx.highlight_config.cursorline_enabled = value.boolean;
        }
    } else if (std.mem.eql(u8, name, "signcolumn")) {
        if (value == .string) {
            ctx.highlight_config.signcolumn_mode = value.string;
        }
    }
}

/// Register configuration API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, ctx: *ConfigContext) void {
    c.hermes_register_host_function(
        runtime,
        "setHighlight",
        setHighlight,
        @ptrCast(ctx), // Pass full context
    );

    c.hermes_register_host_function(
        runtime,
        "getOption",
        getOption,
        @ptrCast(ctx), // Pass full context
    );

    c.hermes_register_host_function(
        runtime,
        "setOption",
        setOption,
        @ptrCast(ctx), // Pass full context
    );
}
