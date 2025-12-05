/// Configuration API Module
/// Handles setHighlight, setOption, and getOption JSI functions
/// Allows JavaScript to configure editor appearance and behavior
const std = @import("std");
const highlights = @import("../../editor/config/highlights.zig");
const options_mod = @import("../../editor/config/options.zig");
const option_defs = @import("../../editor/config/option_defs.zig");
const helpers = @import("helpers.zig");
const Display = @import("../../backends/terminal/display/display.zig").Display;

const OptionsManager = options_mod.OptionsManager;
const OptionValue = options_mod.OptionValue;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Module cache entry for require() system
pub const ModuleEntry = struct {
    exports: *c.OVHermesValue, // Cached module.exports
    loading: bool, // True if currently executing (circular dependency detection)
};

/// Context for configuration API (passed to all config functions)
pub const ConfigContext = struct {
    highlight_config: *highlights.HighlightConfig,
    options_manager: *OptionsManager,
    allocator: std.mem.Allocator,
    display: ?*Display, // Optional - may be null in headless mode
    js_state_dirty: ?*bool = null, // Pointer to editor's dirty flag (null for EditorContext)
    buffer: ?*@import("../../editor/buffer/buffer.zig").Buffer = null, // Buffer for vim.bo access
    editor: ?*@import("../../editor/editor.zig").Editor = null, // Editor for tree-sitter parsing

    // Module system (Phase 4 - CommonJS require())
    module_cache: std.StringHashMap(ModuleEntry), // Cached modules by absolute path
    current_file_path: ?[]const u8 = null, // Currently executing file (for relative requires)
    runtime: ?*c.OVHermesRuntime = null, // Runtime for module execution
};

/// Zig host function: setHighlight(name, bg, fg)
/// Called from JavaScript: setHighlight('CursorLine', '#2b2b2b', null)
pub export fn setHighlight(
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

    // Mark editor state as dirty to trigger render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    // Debug messages sent to Chrome console instead of terminal

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: getOption(name)
/// Called from JavaScript: getOption('number')
/// Returns the option value or undefined if not found/set
pub export fn getOption(
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

    // Look up option metadata (supports Vim name, short name, or JavaScript camelCase)
    const meta = option_defs.getOptionMeta(name) orelse {
        // Unknown option
        return c.hermes_value_create_undefined(runtime);
    };

    // Try to get set value, fall back to default from metadata
    // Use Vim name (meta.name) for storage key
    const opt_value = blk: {
        if (ctx.options_manager.get(meta.name)) |value| {
            break :blk value;
        }
        // Not set - return default
        break :blk meta.default;
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
pub export fn setOption(
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

    // Look up option metadata (supports Vim name, short name, or JavaScript camelCase)
    const meta = option_defs.getOptionMeta(name) orelse {
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

    // Store in OptionsManager (using Vim name for consistency)
    ctx.options_manager.set(meta.name, opt_value) catch {
        return c.hermes_value_create_undefined(runtime);
    };

    // Apply side effects for specific options
    applySideEffects(ctx, meta.name, opt_value);

    // Mark editor state as dirty to trigger render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: getOptionWithScope(name, scope)
/// Called from JavaScript: getOptionWithScope('number', 'local')
/// scope: 'global', 'local', or 'force_local'
/// Returns the option value or undefined if not found/set
pub export fn getOptionWithScope(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
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

    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Look up option metadata (supports Vim name, short name, or JavaScript camelCase)
    const meta = option_defs.getOptionMeta(name) orelse {
        // Unknown option
        return c.hermes_value_create_undefined(runtime);
    };

    // Arg 1: scope (string: 'global', 'local', 'force_local')
    if (args[1] == null or !c.hermes_value_is_string(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var scope_len: usize = 0;
    const scope_ptr = c.hermes_value_get_string(runtime, args[1], &scope_len);
    if (scope_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }

    const scope_str = scope_ptr[0..scope_len];
    const scope: options_mod.OptionScope = if (std.mem.eql(u8, scope_str, "global"))
        .global
    else if (std.mem.eql(u8, scope_str, "force_local"))
        .force_local
    else
        .local; // Default to local

    // Try to get set value with scope, fall back to default from metadata
    // Use Vim name (meta.name) for storage key
    const opt_value = blk: {
        if (ctx.options_manager.getWithScope(meta.name, scope)) |value| {
            break :blk value;
        }
        // Not set - return default
        break :blk meta.default;
    };

    // Convert OptionValue to Hermes value
    return switch (opt_value) {
        .boolean => |v| c.hermes_value_create_boolean(runtime, v),
        .number => |v| c.hermes_value_create_number(runtime, @floatFromInt(v)),
        .string => |s| c.hermes_value_create_string(runtime, s.ptr, s.len),
    };
}

/// Zig host function: setOptionWithScope(name, value, scope)
/// Called from JavaScript: setOptionWithScope('number', true, 'local')
/// scope: 'global', 'local', or 'force_local'
pub export fn setOptionWithScope(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));

    if (arg_count < 3) {
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

    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Look up option metadata (supports Vim name, short name, or JavaScript camelCase)
    const meta = option_defs.getOptionMeta(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Arg 1: value
    const opt_value: OptionValue = switch (meta.type) {
        .boolean => blk: {
            if (!c.hermes_value_is_boolean(args[1])) {
                return c.hermes_value_create_undefined(runtime);
            }
            break :blk .{ .boolean = c.hermes_value_get_boolean(args[1]) };
        },
        .number => blk: {
            if (!c.hermes_value_is_number(args[1])) {
                return c.hermes_value_create_undefined(runtime);
            }
            break :blk .{ .number = @intFromFloat(c.hermes_value_get_number(args[1])) };
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
            break :blk .{ .string = value_ptr[0..value_len] };
        },
    };

    // Validate
    if (!option_defs.validateOption(meta, opt_value)) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 2: scope (string: 'global', 'local', 'force_local')
    if (args[2] == null or !c.hermes_value_is_string(args[2])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var scope_len: usize = 0;
    const scope_ptr = c.hermes_value_get_string(runtime, args[2], &scope_len);
    if (scope_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }

    const scope_str = scope_ptr[0..scope_len];
    const scope: options_mod.OptionScope = if (std.mem.eql(u8, scope_str, "global"))
        .global
    else if (std.mem.eql(u8, scope_str, "force_local"))
        .force_local
    else
        .local;

    // Store with scope (using Vim name for consistency)
    ctx.options_manager.setWithScope(meta.name, opt_value, scope) catch {
        return c.hermes_value_create_undefined(runtime);
    };

    // Apply side effects (only for global scope changes for now)
    if (scope == .global) {
        applySideEffects(ctx, meta.name, opt_value);
    }

    // Mark editor state as dirty to trigger render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: getAllOptions()
/// Called from JavaScript: getAllOptions()
/// Returns a plain JavaScript object with ALL defined options (set values + defaults)
/// Single JSI call replaces multiple getOption() calls for Chrome DevTools inspection
pub export fn getAllOptions(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;

    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));

    // Create JavaScript object
    const obj = c.hermes_value_create_object(runtime);

    // Iterate through ALL defined options (from option_defs)
    for (option_defs.OPTIONS) |meta| {
        // Try to get the set value, fall back to default
        const value = ctx.options_manager.get(meta.name) orelse meta.default;

        // Convert OptionValue to Hermes value
        const js_value = switch (value) {
            .boolean => |v| c.hermes_value_create_boolean(runtime, v),
            .number => |v| c.hermes_value_create_number(runtime, @floatFromInt(v)),
            .string => |s| c.hermes_value_create_string(runtime, s.ptr, s.len),
        };

        // Create null-terminated property name
        var name_buf: [256]u8 = undefined;
        if (meta.name.len >= name_buf.len - 1) continue; // Skip if name too long
        @memcpy(name_buf[0..meta.name.len], meta.name);
        name_buf[meta.name.len] = 0; // Null terminator

        c.hermes_value_set_property(runtime, obj, &name_buf, js_value);
    }

    return obj;
}

/// Zig host function: getAllOptionsWithScope(scope)
/// Called from JavaScript: getAllOptionsWithScope('local')
/// Returns a plain JavaScript object with all options in the specified scope
/// scope: 'global', 'local', or 'force_local'
pub export fn getAllOptionsWithScope(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));

    if (arg_count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: scope (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var scope_len: usize = 0;
    const scope_ptr = c.hermes_value_get_string(runtime, args[0], &scope_len);
    if (scope_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }

    const scope_str = scope_ptr[0..scope_len];
    const scope: options_mod.OptionScope = if (std.mem.eql(u8, scope_str, "global"))
        .global
    else if (std.mem.eql(u8, scope_str, "force_local"))
        .force_local
    else
        .local;

    // Create JavaScript object
    const obj = c.hermes_value_create_object(runtime);

    // Iterate through ALL defined options (from option_defs)
    for (option_defs.OPTIONS) |meta| {
        // Get value with the requested scope (handles fallback automatically)
        const value = ctx.options_manager.getWithScope(meta.name, scope) orelse meta.default;

        // Convert OptionValue to Hermes value
        const js_value = switch (value) {
            .boolean => |v| c.hermes_value_create_boolean(runtime, v),
            .number => |v| c.hermes_value_create_number(runtime, @floatFromInt(v)),
            .string => |s| c.hermes_value_create_string(runtime, s.ptr, s.len),
        };

        // Create null-terminated property name
        var name_buf: [256]u8 = undefined;
        if (meta.name.len >= name_buf.len - 1) continue;
        @memcpy(name_buf[0..meta.name.len], meta.name);
        name_buf[meta.name.len] = 0;

        c.hermes_value_set_property(runtime, obj, &name_buf, js_value);
    }

    return obj;
}

/// Apply side effects when certain options are set
/// Updates window.options which is the single source of truth for rendering.
/// Display syncs from window.options during render (see display.zig sync code).
fn applySideEffects(ctx: *ConfigContext, name: []const u8, value: OptionValue) void {
    // Get current window - window.options is the source of truth for rendering
    const current_window = if (ctx.editor) |editor| editor.getCurrentWindow() else null;

    if (std.mem.eql(u8, name, "cursorline")) {
        if (value == .boolean) {
            ctx.highlight_config.cursorline_enabled = value.boolean;
            if (current_window) |win| {
                win.options.cursorline = value.boolean;
            }
        }
    } else if (std.mem.eql(u8, name, "signcolumn")) {
        if (value == .string) {
            // Use static strings to avoid lifetime issues with JSI temporaries
            const mode: []const u8 = if (std.mem.eql(u8, value.string, "yes"))
                "yes"
            else if (std.mem.eql(u8, value.string, "auto"))
                "auto"
            else
                "no";
            ctx.highlight_config.signcolumn_mode = mode;
            if (current_window) |win| {
                const WindowOptions = @import("../../editor/window.zig").WindowOptions;
                win.options.signcolumn = if (std.mem.eql(u8, value.string, "yes"))
                    WindowOptions.SignColumn.yes
                else if (std.mem.eql(u8, value.string, "auto"))
                    WindowOptions.SignColumn.auto
                else
                    WindowOptions.SignColumn.no;
            }
        }
    } else if (std.mem.eql(u8, name, "number")) {
        if (value == .boolean) {
            if (current_window) |win| {
                win.options.number = value.boolean;
            }
        }
    } else if (std.mem.eql(u8, name, "relativenumber")) {
        if (value == .boolean) {
            if (current_window) |win| {
                win.options.relativenumber = value.boolean;
            }
        }
    } else if (std.mem.eql(u8, name, "numberwidth")) {
        if (value == .number) {
            // Clamp to valid range: 1-20 (Neovim uses 1-20)
            const width: u8 = @intCast(@max(1, @min(20, value.number)));
            if (current_window) |win| {
                win.options.numberwidth = width;
            }
        }
    }
}

/// Zig host function: getBufferOption(name)
/// Called from JavaScript: vim.bo.filetype
/// Returns buffer-specific options like filetype
pub export fn getBufferOption(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
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

    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Handle buffer-specific options
    if (std.mem.eql(u8, name, "filetype")) {
        if (ctx.buffer) |buffer| {
            if (buffer.filetype) |ft| {
                return c.hermes_value_create_string(runtime, ft.ptr, ft.len);
            }
        }
        return c.hermes_value_create_undefined(runtime);
    }

    // Unknown buffer option
    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: setBufferOption(name, value)
/// Called from JavaScript: vim.bo.filetype = 'rust'
/// Sets buffer-specific options like filetype
pub export fn setBufferOption(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
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

    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Handle buffer-specific options
    if (std.mem.eql(u8, name, "filetype")) {
        if (ctx.buffer) |buffer| {
            // Arg 1: value (string or null)
            if (c.hermes_value_is_null(args[1]) or c.hermes_value_is_undefined(args[1])) {
                // Clear filetype
                buffer.setFiletype(null) catch {};
            } else if (c.hermes_value_is_string(args[1])) {
                var value_len: usize = 0;
                const value_ptr = c.hermes_value_get_string(runtime, args[1], &value_len);
                if (value_ptr != null) {
                    // Use setFiletype which properly allocates and copies the string
                    buffer.setFiletype(value_ptr[0..value_len]) catch {};
                }
            }

            // Mark editor state as dirty to trigger render
            if (ctx.js_state_dirty) |dirty| {
                dirty.* = true;
            }
        }
        return c.hermes_value_create_undefined(runtime);
    }

    // Unknown buffer option - ignore silently (Vim behavior)
    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.opt HostObject getter - returns option value by property name
/// JavaScript: vim.opt.number, vim.opt.cursorline
pub export fn vimOptHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);

    // Look up option metadata
    const meta = option_defs.getOptionMeta(name) orelse return c.hermes_value_create_undefined(rt);

    // Get value (set value or default)
    const opt_value = ctx.options_manager.get(meta.name) orelse meta.default;

    // Convert to Hermes value
    return switch (opt_value) {
        .boolean => |v| c.hermes_value_create_boolean(rt, v),
        .number => |v| c.hermes_value_create_number(rt, @floatFromInt(v)),
        .string => |s| c.hermes_value_create_string(rt, s.ptr, s.len),
    };
}

/// vim.opt HostObject setter - sets option value by property name
/// JavaScript: vim.opt.number = true
pub export fn vimOptHostObjectSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);
    const val = value orelse return c.hermes_value_create_undefined(rt);

    // Look up option metadata
    const meta = option_defs.getOptionMeta(name) orelse return c.hermes_value_create_undefined(rt);

    // Convert value based on expected type
    const opt_value: OptionValue = switch (meta.type) {
        .boolean => blk: {
            if (!c.hermes_value_is_boolean(val)) return c.hermes_value_create_undefined(rt);
            break :blk .{ .boolean = c.hermes_value_get_boolean(val) };
        },
        .number => blk: {
            if (!c.hermes_value_is_number(val)) return c.hermes_value_create_undefined(rt);
            break :blk .{ .number = @intFromFloat(c.hermes_value_get_number(val)) };
        },
        .string => blk: {
            if (!c.hermes_value_is_string(val)) return c.hermes_value_create_undefined(rt);
            var value_len: usize = 0;
            const value_ptr = c.hermes_value_get_string(rt, val, &value_len);
            if (value_ptr == null) return c.hermes_value_create_undefined(rt);
            break :blk .{ .string = value_ptr[0..value_len] };
        },
    };

    // Validate
    if (!option_defs.validateOption(meta, opt_value)) {
        return c.hermes_value_create_undefined(rt);
    }

    // Store
    ctx.options_manager.set(meta.name, opt_value) catch {
        return c.hermes_value_create_undefined(rt);
    };

    // Apply side effects
    applySideEffects(ctx, meta.name, opt_value);

    // Mark dirty
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.opt HostObject enumerator - returns array of all option names
pub export fn vimOptHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const arr = c.hermes_array_create(rt, option_defs.OPTIONS.len) orelse return null;

    for (option_defs.OPTIONS, 0..) |meta, i| {
        const str = c.hermes_value_create_string(rt, meta.name.ptr, meta.name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

/// vim.optLocal HostObject getter - returns local-scope option value
pub export fn vimOptLocalHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);

    const meta = option_defs.getOptionMeta(name) orelse return c.hermes_value_create_undefined(rt);
    const opt_value = ctx.options_manager.getWithScope(meta.name, .local) orelse meta.default;

    return switch (opt_value) {
        .boolean => |v| c.hermes_value_create_boolean(rt, v),
        .number => |v| c.hermes_value_create_number(rt, @floatFromInt(v)),
        .string => |s| c.hermes_value_create_string(rt, s.ptr, s.len),
    };
}

/// vim.optLocal HostObject setter - sets local-scope option value
pub export fn vimOptLocalHostObjectSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);
    const val = value orelse return c.hermes_value_create_undefined(rt);

    const meta = option_defs.getOptionMeta(name) orelse return c.hermes_value_create_undefined(rt);

    const opt_value: OptionValue = switch (meta.type) {
        .boolean => blk: {
            if (!c.hermes_value_is_boolean(val)) return c.hermes_value_create_undefined(rt);
            break :blk .{ .boolean = c.hermes_value_get_boolean(val) };
        },
        .number => blk: {
            if (!c.hermes_value_is_number(val)) return c.hermes_value_create_undefined(rt);
            break :blk .{ .number = @intFromFloat(c.hermes_value_get_number(val)) };
        },
        .string => blk: {
            if (!c.hermes_value_is_string(val)) return c.hermes_value_create_undefined(rt);
            var value_len: usize = 0;
            const value_ptr = c.hermes_value_get_string(rt, val, &value_len);
            if (value_ptr == null) return c.hermes_value_create_undefined(rt);
            break :blk .{ .string = value_ptr[0..value_len] };
        },
    };

    if (!option_defs.validateOption(meta, opt_value)) {
        return c.hermes_value_create_undefined(rt);
    }

    ctx.options_manager.setWithScope(meta.name, opt_value, .local) catch {
        return c.hermes_value_create_undefined(rt);
    };

    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.optGlobal HostObject getter - returns global-scope option value
pub export fn vimOptGlobalHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);

    const meta = option_defs.getOptionMeta(name) orelse return c.hermes_value_create_undefined(rt);
    const opt_value = ctx.options_manager.getWithScope(meta.name, .global) orelse meta.default;

    return switch (opt_value) {
        .boolean => |v| c.hermes_value_create_boolean(rt, v),
        .number => |v| c.hermes_value_create_number(rt, @floatFromInt(v)),
        .string => |s| c.hermes_value_create_string(rt, s.ptr, s.len),
    };
}

/// vim.optGlobal HostObject setter - sets global-scope option value
pub export fn vimOptGlobalHostObjectSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);
    const val = value orelse return c.hermes_value_create_undefined(rt);

    const meta = option_defs.getOptionMeta(name) orelse return c.hermes_value_create_undefined(rt);

    const opt_value: OptionValue = switch (meta.type) {
        .boolean => blk: {
            if (!c.hermes_value_is_boolean(val)) return c.hermes_value_create_undefined(rt);
            break :blk .{ .boolean = c.hermes_value_get_boolean(val) };
        },
        .number => blk: {
            if (!c.hermes_value_is_number(val)) return c.hermes_value_create_undefined(rt);
            break :blk .{ .number = @intFromFloat(c.hermes_value_get_number(val)) };
        },
        .string => blk: {
            if (!c.hermes_value_is_string(val)) return c.hermes_value_create_undefined(rt);
            var value_len: usize = 0;
            const value_ptr = c.hermes_value_get_string(rt, val, &value_len);
            if (value_ptr == null) return c.hermes_value_create_undefined(rt);
            break :blk .{ .string = value_ptr[0..value_len] };
        },
    };

    if (!option_defs.validateOption(meta, opt_value)) {
        return c.hermes_value_create_undefined(rt);
    }

    ctx.options_manager.setWithScope(meta.name, opt_value, .global) catch {
        return c.hermes_value_create_undefined(rt);
    };

    applySideEffects(ctx, meta.name, opt_value);

    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.bo HostObject getter - returns buffer-specific option value
pub export fn vimBoHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);

    // Handle buffer-specific options
    if (std.mem.eql(u8, name, "filetype")) {
        if (ctx.buffer) |buffer| {
            if (buffer.filetype) |ft| {
                return c.hermes_value_create_string(rt, ft.ptr, ft.len);
            }
        }
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.bo HostObject setter - sets buffer-specific option value
pub export fn vimBoHostObjectSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);
    const val = value orelse return c.hermes_value_create_undefined(rt);

    // Handle buffer-specific options
    if (std.mem.eql(u8, name, "filetype")) {
        if (ctx.buffer) |buffer| {
            if (c.hermes_value_is_null(val) or c.hermes_value_is_undefined(val)) {
                // Clear filetype
                buffer.setFiletype(null) catch {};
            } else if (c.hermes_value_is_string(val)) {
                var value_len: usize = 0;
                const value_ptr = c.hermes_value_get_string(rt, val, &value_len);
                if (value_ptr != null) {
                    const ft_str = value_ptr[0..value_len];
                    // Use setFiletype which properly allocates and copies the string
                    buffer.setFiletype(ft_str) catch {};

                    // Trigger tree-sitter parsing for the new filetype
                    if (ctx.editor) |editor| {
                        editor.parseBufferWithTreeSitter(ft_str) catch {};
                    }
                }
            }

            if (ctx.js_state_dirty) |dirty| {
                dirty.* = true;
            }
        }
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.bo HostObject enumerator - returns array of buffer option names
pub export fn vimBoHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const option_names = [_][]const u8{"filetype"};
    const arr = c.hermes_array_create(rt, option_names.len) orelse return null;

    for (option_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// vim.g HostObject (Global Variables)
// ============================================================================

/// vim.g HostObject getter - returns global variable value by name
/// JavaScript: vim.g.mapleader, vim.g.myPluginVar
pub export fn vimGHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);

    // Get editor from context
    const editor = ctx.editor orelse return c.hermes_value_create_undefined(rt);

    // Look up global variable
    if (editor.getGlobalVar(name)) |value| {
        return c.hermes_value_create_string(rt, value.ptr, value.len);
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.g HostObject setter - sets global variable value by name
/// JavaScript: vim.g.mapleader = ' '
pub export fn vimGHostObjectSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));
    const name = std.mem.span(prop_name);
    const val = value orelse return c.hermes_value_create_undefined(rt);

    // Get editor from context
    const editor = ctx.editor orelse return c.hermes_value_create_undefined(rt);

    // Handle null/undefined = delete variable
    if (c.hermes_value_is_null(val) or c.hermes_value_is_undefined(val)) {
        editor.delGlobalVar(name);
        return c.hermes_value_create_undefined(rt);
    }

    // For now, only support string values (Neovim's vim.g is more flexible)
    if (c.hermes_value_is_string(val)) {
        var value_len: usize = 0;
        const value_ptr = c.hermes_value_get_string(rt, val, &value_len);
        if (value_ptr != null) {
            editor.setGlobalVar(name, value_ptr[0..value_len]) catch {
                return c.hermes_value_create_undefined(rt);
            };
        }
    }

    return c.hermes_value_create_undefined(rt);
}

/// vim.g HostObject enumerator - returns array of global variable names
pub export fn vimGHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = @as(*ConfigContext, @ptrCast(@alignCast(context.?)));

    // Get editor from context
    const editor = ctx.editor orelse return c.hermes_array_create(rt, 0);

    // Count keys first
    var count: usize = 0;
    var iter = editor.global_vars.iterator();
    while (iter.next()) |_| {
        count += 1;
    }

    const arr = c.hermes_array_create(rt, count) orelse return null;

    // Add keys to array
    iter = editor.global_vars.iterator();
    var i: usize = 0;
    while (iter.next()) |entry| {
        const str = c.hermes_value_create_string(rt, entry.key_ptr.*.ptr, entry.key_ptr.*.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
        i += 1;
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register configuration API as HostObjects (zero-copy, 3-5x faster)
/// JavaScript usage: vim.opt.number, vim.optLocal.cursorline, vim.bo.filetype
pub fn register(runtime: *c.OVHermesRuntime, ctx: *ConfigContext) void {
    // vim.opt HostObject (global/local fallback)
    c.hermes_register_host_object(
        runtime,
        "vimOpt",
        vimOptHostObjectGet,
        vimOptHostObjectSet,
        vimOptHostObjectEnumerator,
        @ptrCast(ctx),
    );

    // vim.optLocal HostObject (local-scope only)
    c.hermes_register_host_object(
        runtime,
        "vimOptLocal",
        vimOptLocalHostObjectGet,
        vimOptLocalHostObjectSet,
        vimOptHostObjectEnumerator, // Same options list
        @ptrCast(ctx),
    );

    // vim.optGlobal HostObject (global-scope only)
    c.hermes_register_host_object(
        runtime,
        "vimOptGlobal",
        vimOptGlobalHostObjectGet,
        vimOptGlobalHostObjectSet,
        vimOptHostObjectEnumerator, // Same options list
        @ptrCast(ctx),
    );

    // vim.bo HostObject (buffer-local options)
    c.hermes_register_host_object(
        runtime,
        "vimBo",
        vimBoHostObjectGet,
        vimBoHostObjectSet,
        vimBoHostObjectEnumerator,
        @ptrCast(ctx),
    );

    // vim.g HostObject (global variables like mapleader)
    c.hermes_register_host_object(
        runtime,
        "vimG",
        vimGHostObjectGet,
        vimGHostObjectSet,
        vimGHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

/// Legacy registration (backwards compatibility)
/// TODO: Remove after runtime.js updated to use HostObject properties
pub fn registerLegacy(runtime: *c.OVHermesRuntime, ctx: *ConfigContext) void {
    c.hermes_register_host_function(
        runtime,
        "setHighlight",
        setHighlight,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "getOption",
        getOption,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "setOption",
        setOption,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "getOptionWithScope",
        getOptionWithScope,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "setOptionWithScope",
        setOptionWithScope,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "getAllOptions",
        getAllOptions,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "getAllOptionsWithScope",
        getAllOptionsWithScope,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "getBufferOption",
        getBufferOption,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "setBufferOption",
        setBufferOption,
        @ptrCast(ctx),
    );
}
