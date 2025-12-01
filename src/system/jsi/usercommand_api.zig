/// User Command API Module
/// JSI bridge for vim.api.createUserCommand() and related functions
/// Allows JavaScript to register custom Ex commands (:Command)
/// Neovim-compatible with TypeScript-enhanced type safety
const std = @import("std");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;
const helpers = @import("helpers.zig");

/// Command option flags parsed from JavaScript options object
pub const CommandOpts = struct {
    /// Command description
    desc: ?[]const u8 = null,
    /// Allow bang modifier (:Cmd!)
    bang: bool = false,
    /// Allow bar separator (:Cmd | other)
    bar: bool = false,
    /// Force overwrite existing command
    force: bool = false,
    /// Range specification: 0=none, -1=whole file (%), >0=default count
    range: i32 = 0,
    /// Count specification: 0=none, >0=default count
    count: i32 = 0,
    /// Accept register argument
    register: bool = false,
    /// Number of arguments: '0', '1', '*', '?', '+'
    nargs: u8 = '0',
    /// Buffer ID (null = global, 0+ = buffer-local)
    buffer: ?usize = null,
};

/// Stored user command
pub const UserCommand = struct {
    name: []const u8,
    callback: *c.OVHermesValue, // Protected JS function reference
    opts: CommandOpts,
    /// Owning allocator for cleanup
    allocator: std.mem.Allocator,

    pub fn deinit(self: *UserCommand, runtime: *c.OVHermesRuntime) void {
        // Release protected JS function reference
        c.hermes_value_destroy(self.callback);
        _ = runtime;
        // Free allocated strings
        if (self.opts.desc) |desc| {
            self.allocator.free(desc);
        }
        self.allocator.free(self.name);
    }
};

/// Context for usercommand API
pub const UserCommandContext = struct {
    /// Global commands (buffer = null)
    global_commands: std.StringHashMap(UserCommand),
    /// Buffer-local commands (buffer ID -> name -> command)
    buffer_commands: std.AutoHashMap(usize, std.StringHashMap(UserCommand)),
    allocator: std.mem.Allocator,
    runtime: *c.OVHermesRuntime,

    pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) !*UserCommandContext {
        const ctx = try allocator.create(UserCommandContext);
        ctx.* = .{
            .global_commands = std.StringHashMap(UserCommand).init(allocator),
            .buffer_commands = std.AutoHashMap(usize, std.StringHashMap(UserCommand)).init(allocator),
            .allocator = allocator,
            .runtime = runtime,
        };
        return ctx;
    }

    pub fn deinit(self: *UserCommandContext) void {
        // Clean up global commands
        var global_iter = self.global_commands.valueIterator();
        while (global_iter.next()) |cmd| {
            var command = cmd.*;
            command.deinit(self.runtime);
        }
        self.global_commands.deinit();

        // Clean up buffer-local commands
        var buffer_iter = self.buffer_commands.valueIterator();
        while (buffer_iter.next()) |buffer_map| {
            var map_iter = buffer_map.valueIterator();
            while (map_iter.next()) |cmd| {
                var command = cmd.*;
                command.deinit(self.runtime);
            }
            var map = buffer_map.*;
            map.deinit();
        }
        self.buffer_commands.deinit();

        self.allocator.destroy(self);
    }

    /// Add a user command
    pub fn addCommand(self: *UserCommandContext, name: []const u8, callback: *c.OVHermesValue, opts: CommandOpts) !void {
        // Validate command name (must start with uppercase)
        if (name.len == 0 or !std.ascii.isUpper(name[0])) {
            return error.InvalidCommandName;
        }

        // Duplicate name for storage
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        // Duplicate desc if present
        var owned_opts = opts;
        if (opts.desc) |desc| {
            owned_opts.desc = try self.allocator.dupe(u8, desc);
        }
        errdefer if (owned_opts.desc) |d| self.allocator.free(d);

        // Note: callback is already protected via Hermes internal reference counting
        // when stored in the HashMap

        const cmd = UserCommand{
            .name = owned_name,
            .callback = callback,
            .opts = owned_opts,
            .allocator = self.allocator,
        };

        if (opts.buffer) |buffer_id| {
            // Buffer-local command
            const entry = try self.buffer_commands.getOrPut(buffer_id);
            if (!entry.found_existing) {
                entry.value_ptr.* = std.StringHashMap(UserCommand).init(self.allocator);
            }

            // Check for existing command
            if (entry.value_ptr.get(owned_name)) |existing| {
                if (!opts.force) {
                    return error.CommandExists;
                }
                // Remove existing
                var existing_cmd = existing;
                existing_cmd.deinit(self.runtime);
            }

            try entry.value_ptr.put(owned_name, cmd);
        } else {
            // Global command
            if (self.global_commands.get(owned_name)) |existing| {
                if (!opts.force) {
                    return error.CommandExists;
                }
                // Remove existing
                var existing_cmd = existing;
                existing_cmd.deinit(self.runtime);
            }

            try self.global_commands.put(owned_name, cmd);
        }
    }

    /// Delete a user command
    pub fn delCommand(self: *UserCommandContext, name: []const u8, buffer: ?usize) !void {
        if (buffer) |buffer_id| {
            // Buffer-local command
            if (self.buffer_commands.getPtr(buffer_id)) |buffer_map| {
                if (buffer_map.fetchRemove(name)) |kv| {
                    var cmd = kv.value;
                    cmd.deinit(self.runtime);
                    return;
                }
            }
            return error.CommandNotFound;
        } else {
            // Global command
            if (self.global_commands.fetchRemove(name)) |kv| {
                var cmd = kv.value;
                cmd.deinit(self.runtime);
                return;
            }
            return error.CommandNotFound;
        }
    }

    /// Get a command by name (checks buffer-local first, then global)
    pub fn getCommand(self: *UserCommandContext, name: []const u8, buffer: ?usize) ?*const UserCommand {
        // Check buffer-local first
        if (buffer) |buffer_id| {
            if (self.buffer_commands.getPtr(buffer_id)) |buffer_map| {
                if (buffer_map.getPtr(name)) |cmd| {
                    return cmd;
                }
            }
        }
        // Fall back to global
        return self.global_commands.getPtr(name);
    }
};

/// Convert string to null-terminated buffer
fn valueToString(runtime: *c.OVHermesRuntime, value: *c.OVHermesValue, allocator: std.mem.Allocator) ![]const u8 {
    var len: usize = 0;
    const ptr = c.hermes_value_get_string(runtime, value, &len) orelse return error.NullString;

    const result = try allocator.alloc(u8, len);
    @memcpy(result, ptr[0..len]);
    return result;
}

/// Get object property helper
fn getObjectProperty(runtime: *c.OVHermesRuntime, obj: *c.OVHermesValue, key: [*:0]const u8) ?*c.OVHermesValue {
    return c.hermes_value_get_property(runtime, obj, key);
}

/// Parse command options from JavaScript object
fn parseOpts(runtime: *c.OVHermesRuntime, opts_value: *c.OVHermesValue, allocator: std.mem.Allocator) !CommandOpts {
    var opts = CommandOpts{};

    if (!c.hermes_value_is_object(opts_value)) {
        return opts;
    }

    // desc: string
    if (getObjectProperty(runtime, opts_value, "desc")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_string(val)) {
            opts.desc = valueToString(runtime, val, allocator) catch null;
        }
    }

    // bang: boolean
    if (getObjectProperty(runtime, opts_value, "bang")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_boolean(val)) {
            opts.bang = c.hermes_value_get_boolean(val);
        }
    }

    // bar: boolean
    if (getObjectProperty(runtime, opts_value, "bar")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_boolean(val)) {
            opts.bar = c.hermes_value_get_boolean(val);
        }
    }

    // force: boolean
    if (getObjectProperty(runtime, opts_value, "force")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_boolean(val)) {
            opts.force = c.hermes_value_get_boolean(val);
        }
    }

    // register: boolean
    if (getObjectProperty(runtime, opts_value, "register")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_boolean(val)) {
            opts.register = c.hermes_value_get_boolean(val);
        }
    }

    // range: boolean | '%' | number
    if (getObjectProperty(runtime, opts_value, "range")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_boolean(val)) {
            if (c.hermes_value_get_boolean(val)) {
                opts.range = -1; // Whole file
            }
        } else if (c.hermes_value_is_number(val)) {
            opts.range = @intFromFloat(c.hermes_value_get_number(val));
        } else if (c.hermes_value_is_string(val)) {
            var len: usize = 0;
            if (c.hermes_value_get_string(runtime, val, &len)) |str| {
                if (len == 1 and str[0] == '%') {
                    opts.range = -1; // Whole file
                }
            }
        }
    }

    // count: number
    if (getObjectProperty(runtime, opts_value, "count")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_number(val)) {
            opts.count = @intFromFloat(c.hermes_value_get_number(val));
        }
    }

    // nargs: '0' | '1' | '*' | '?' | '+'
    if (getObjectProperty(runtime, opts_value, "nargs")) |val| {
        defer c.hermes_value_destroy(val);
        if (c.hermes_value_is_string(val)) {
            var len: usize = 0;
            if (c.hermes_value_get_string(runtime, val, &len)) |str| {
                if (len == 1) {
                    const ch = str[0];
                    if (ch == '0' or ch == '1' or ch == '*' or ch == '?' or ch == '+') {
                        opts.nargs = ch;
                    }
                }
            }
        }
    }

    return opts;
}

// ============================================================================
// JSI Host Functions
// ============================================================================

/// vim.api.createUserCommand(name, callback, opts?)
pub export fn createUserCommand(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*UserCommandContext, @ptrCast(@alignCast(context.?)));

    // Validate argument count
    if (arg_count < 2) {
        return helpers.returnError(runtime, "createUserCommand requires at least 2 arguments (name, callback)");
    }

    // Extract name (arg 0)
    const name = valueToString(runtime, args[0].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "createUserCommand: name must be a string");
    };
    defer ctx.allocator.free(name);

    // Extract callback (arg 1) - must clone to prevent GC
    const callback_raw = args[1].?;
    if (!c.hermes_value_is_function(runtime, callback_raw)) {
        return helpers.returnError(runtime, "createUserCommand: callback must be a function");
    }
    const callback = c.hermes_value_clone(runtime, callback_raw) orelse {
        return helpers.returnError(runtime, "createUserCommand: failed to clone callback");
    };

    // Extract options (arg 2, optional)
    var opts = CommandOpts{};
    if (arg_count >= 3) {
        if (args[2]) |opts_val| {
            opts = parseOpts(runtime, opts_val, ctx.allocator) catch {
                return helpers.returnError(runtime, "createUserCommand: failed to parse options");
            };
        }
    }

    // Free opts.desc after addCommand (it makes its own copy)
    defer if (opts.desc) |desc| {
        ctx.allocator.free(desc);
    };

    // Add the command
    ctx.addCommand(name, callback, opts) catch |err| {
        // Destroy cloned callback on failure
        c.hermes_value_destroy(callback);
        return switch (err) {
            error.InvalidCommandName => helpers.returnError(runtime, "createUserCommand: command name must start with uppercase letter (e.g., 'Hello' not 'hello')"),
            error.CommandExists => helpers.returnError(runtime, "createUserCommand: command already exists (use force: true to overwrite)"),
            else => helpers.returnError(runtime, "createUserCommand: failed to create command"),
        };
    };

    return c.hermes_value_create_undefined(runtime);
}

/// vim.api.deleteUserCommand(name)
pub export fn deleteUserCommand(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*UserCommandContext, @ptrCast(@alignCast(context.?)));

    if (arg_count < 1) {
        return helpers.returnError(runtime, "deleteUserCommand requires 1 argument (name)");
    }

    const name = valueToString(runtime, args[0].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "deleteUserCommand: name must be a string");
    };
    defer ctx.allocator.free(name);

    ctx.delCommand(name, null) catch {
        // Silently ignore if command doesn't exist (idempotent)
    };

    return c.hermes_value_create_undefined(runtime);
}

/// vim.api.bufCreateUserCommand(buffer, name, callback, opts?)
pub export fn bufCreateUserCommand(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*UserCommandContext, @ptrCast(@alignCast(context.?)));

    if (arg_count < 3) {
        return helpers.returnError(runtime, "bufCreateUserCommand requires at least 3 arguments (buffer, name, callback)");
    }

    // Extract buffer (arg 0)
    const buffer_val = args[0].?;
    if (!c.hermes_value_is_number(buffer_val)) {
        return helpers.returnError(runtime, "bufCreateUserCommand: buffer must be a number");
    }
    const buffer_id: usize = @intFromFloat(c.hermes_value_get_number(buffer_val));

    // Extract name (arg 1)
    const name = valueToString(runtime, args[1].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "bufCreateUserCommand: name must be a string");
    };
    defer ctx.allocator.free(name);

    // Extract callback (arg 2) - must clone to prevent GC
    const callback_raw = args[2].?;
    if (!c.hermes_value_is_function(runtime, callback_raw)) {
        return helpers.returnError(runtime, "bufCreateUserCommand: callback must be a function");
    }
    const callback = c.hermes_value_clone(runtime, callback_raw) orelse {
        return helpers.returnError(runtime, "bufCreateUserCommand: failed to clone callback");
    };

    // Extract options (arg 3, optional)
    var opts = CommandOpts{};
    if (arg_count >= 4) {
        if (args[3]) |opts_val| {
            opts = parseOpts(runtime, opts_val, ctx.allocator) catch {
                return helpers.returnError(runtime, "bufCreateUserCommand: failed to parse options");
            };
        }
    }
    opts.buffer = buffer_id;

    // Free opts.desc after addCommand (it makes its own copy)
    defer if (opts.desc) |desc| {
        ctx.allocator.free(desc);
    };

    // Add the command
    ctx.addCommand(name, callback, opts) catch |err| {
        // Destroy cloned callback on failure
        c.hermes_value_destroy(callback);
        return switch (err) {
            error.InvalidCommandName => helpers.returnError(runtime, "bufCreateUserCommand: command name must start with uppercase letter (e.g., 'Hello' not 'hello')"),
            error.CommandExists => helpers.returnError(runtime, "bufCreateUserCommand: command already exists (use force: true to overwrite)"),
            else => helpers.returnError(runtime, "bufCreateUserCommand: failed to create command"),
        };
    };

    return c.hermes_value_create_undefined(runtime);
}

/// vim.api.bufDeleteUserCommand(buffer, name)
pub export fn bufDeleteUserCommand(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*UserCommandContext, @ptrCast(@alignCast(context.?)));

    if (arg_count < 2) {
        return helpers.returnError(runtime, "bufDeleteUserCommand requires 2 arguments (buffer, name)");
    }

    // Extract buffer (arg 0)
    const buffer_val = args[0].?;
    if (!c.hermes_value_is_number(buffer_val)) {
        return helpers.returnError(runtime, "bufDeleteUserCommand: buffer must be a number");
    }
    const buffer_id: usize = @intFromFloat(c.hermes_value_get_number(buffer_val));

    // Extract name (arg 1)
    const name = valueToString(runtime, args[1].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "bufDeleteUserCommand: name must be a string");
    };
    defer ctx.allocator.free(name);

    ctx.delCommand(name, buffer_id) catch {
        // Silently ignore if command doesn't exist (idempotent)
    };

    return c.hermes_value_create_undefined(runtime);
}

/// vim.api.getUserCommands(opts?) - Get list of user commands
pub export fn getUserCommands(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*UserCommandContext, @ptrCast(@alignCast(context.?)));

    // Count total commands
    var total: usize = ctx.global_commands.count();
    var buffer_iter = ctx.buffer_commands.valueIterator();
    while (buffer_iter.next()) |buffer_map| {
        total += buffer_map.count();
    }

    // Create array
    const arr = c.hermes_array_create(runtime, total) orelse return null;
    var idx: usize = 0;

    // Add global commands
    var global_iter = ctx.global_commands.valueIterator();
    while (global_iter.next()) |cmd| {
        if (createCommandInfoObject(runtime, cmd)) |obj| {
            c.hermes_array_set(runtime, arr, idx, obj);
            c.hermes_value_destroy(obj);
            idx += 1;
        }
    }

    // Add buffer-local commands
    var buf_iter = ctx.buffer_commands.iterator();
    while (buf_iter.next()) |entry| {
        const buffer_id = entry.key_ptr.*;
        var cmd_iter = entry.value_ptr.valueIterator();
        while (cmd_iter.next()) |cmd| {
            if (createCommandInfoObjectWithBuffer(runtime, cmd, buffer_id)) |obj| {
                c.hermes_array_set(runtime, arr, idx, obj);
                c.hermes_value_destroy(obj);
                idx += 1;
            }
        }
    }

    return arr;
}

/// Create command info object for getUserCommands
fn createCommandInfoObject(runtime: *c.OVHermesRuntime, cmd: *const UserCommand) ?*c.OVHermesValue {
    return createCommandInfoObjectWithBuffer(runtime, cmd, null);
}

fn createCommandInfoObjectWithBuffer(runtime: *c.OVHermesRuntime, cmd: *const UserCommand, buffer: ?usize) ?*c.OVHermesValue {
    const obj = c.hermes_value_create_object(runtime) orelse return null;

    // name
    if (c.hermes_value_create_string(runtime, cmd.name.ptr, cmd.name.len)) |val| {
        c.hermes_value_set_property(runtime, obj, "name", val);
        c.hermes_value_destroy(val);
    }

    // definition (callback function)
    if (c.hermes_value_create_string(runtime, "[function]", 10)) |val| {
        c.hermes_value_set_property(runtime, obj, "definition", val);
        c.hermes_value_destroy(val);
    }

    // nargs
    const nargs_str: []const u8 = switch (cmd.opts.nargs) {
        '0' => "0",
        '1' => "1",
        '*' => "*",
        '?' => "?",
        '+' => "+",
        else => "0",
    };
    if (c.hermes_value_create_string(runtime, nargs_str.ptr, nargs_str.len)) |val| {
        c.hermes_value_set_property(runtime, obj, "nargs", val);
        c.hermes_value_destroy(val);
    }

    // range
    const range_str: []const u8 = if (cmd.opts.range < 0) "%" else if (cmd.opts.range > 0) "N" else "";
    if (c.hermes_value_create_string(runtime, range_str.ptr, range_str.len)) |val| {
        c.hermes_value_set_property(runtime, obj, "range", val);
        c.hermes_value_destroy(val);
    }

    // complete
    if (c.hermes_value_create_string(runtime, "", 0)) |val| {
        c.hermes_value_set_property(runtime, obj, "complete", val);
        c.hermes_value_destroy(val);
    }

    // bang
    if (c.hermes_value_create_boolean(runtime, cmd.opts.bang)) |val| {
        c.hermes_value_set_property(runtime, obj, "bang", val);
        c.hermes_value_destroy(val);
    }

    // bar
    if (c.hermes_value_create_boolean(runtime, cmd.opts.bar)) |val| {
        c.hermes_value_set_property(runtime, obj, "bar", val);
        c.hermes_value_destroy(val);
    }

    // register
    if (c.hermes_value_create_boolean(runtime, cmd.opts.register)) |val| {
        c.hermes_value_set_property(runtime, obj, "register", val);
        c.hermes_value_destroy(val);
    }

    // buffer (0 for global, buffer ID for buffer-local)
    const buffer_num: f64 = if (buffer) |b| @floatFromInt(b) else 0.0;
    if (c.hermes_value_create_number(runtime, buffer_num)) |val| {
        c.hermes_value_set_property(runtime, obj, "buffer", val);
        c.hermes_value_destroy(val);
    }

    return obj;
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.api HostObject getter - routes property access to methods
/// Note: This extends the existing vim.api with user command methods
pub export fn userCommandHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Use StaticStringMap for O(1) property dispatch
    const PropertyMap = std.StaticStringMap(*const fn (
        ?*c.OVHermesRuntime,
        ?*anyopaque,
        [*c]?*c.OVHermesValue,
        usize,
    ) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "createUserCommand", createUserCommand },
        .{ "deleteUserCommand", deleteUserCommand },
        .{ "bufCreateUserCommand", bufCreateUserCommand },
        .{ "bufDeleteUserCommand", bufDeleteUserCommand },
        .{ "getUserCommands", getUserCommands },
    });

    const func = PropertyMap.get(name) orelse return null;

    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.api HostObject enumerator - returns array of method names
pub export fn userCommandHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "createUserCommand",
        "deleteUserCommand",
        "bufCreateUserCommand",
        "bufDeleteUserCommand",
        "getUserCommands",
    };

    const arr = c.hermes_array_create(rt, method_names.len) orelse return null;

    for (method_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register usercommand API as HostObject
/// Note: This should be merged with existing vim.api registration
pub fn register(runtime: *c.OVHermesRuntime, ctx: *UserCommandContext) void {
    c.hermes_register_host_object(
        runtime,
        "vimUserCommand",
        userCommandHostObjectGet,
        null, // No setter (methods only)
        userCommandHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

/// Legacy registration for direct function access
pub fn registerLegacy(runtime: *c.OVHermesRuntime, ctx: *UserCommandContext) void {
    c.hermes_register_host_function(runtime, "createUserCommand", createUserCommand, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "deleteUserCommand", deleteUserCommand, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "bufCreateUserCommand", bufCreateUserCommand, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "bufDeleteUserCommand", bufDeleteUserCommand, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "getUserCommands", getUserCommands, @ptrCast(ctx));
}
