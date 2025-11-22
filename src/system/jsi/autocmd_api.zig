/// AutoCommand API - Neovim-compatible autocommand system
///
/// Implements vim.api.createAutoCommand() following Neovim's API:
/// https://neovim.io/doc/user/api.html#nvim_create_autocmd()
///
/// Usage:
///   vim.api.createAutoCommand('BufEnter', {
///       pattern: '*.js',
///       callback: (ev) => console.log('Entered JS file:', ev.file),
///   });
///
///   vim.api.createAutoCommand(['BufRead', 'BufNewFile'], {
///       pattern: ['*.ts', '*.tsx'],
///       group: 'typescript',
///       callback: (ev) => { /* ... */ },
///   });
///
/// Events are emitted from Zig side when actions occur (BufEnter, BufWrite, etc.)

const std = @import("std");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Autocmd entry - stores callback and metadata
pub const AutocmdEntry = struct {
    id: u32,
    group: ?[]const u8,
    pattern: ?[]const u8, // Pattern to match (e.g., "*.js")
    callback: *c.OVHermesValue,
    once: bool, // If true, remove after first execution
    desc: ?[]const u8, // Description for :autocmd listing
};

/// Autocmd Manager - manages autocommands with Neovim-compatible API
pub const AutocmdManager = struct {
    /// Map of event name -> list of autocmds
    autocmds: std.StringHashMap(std.ArrayListUnmanaged(AutocmdEntry)),

    /// Map of group name -> list of autocmd IDs in that group
    groups: std.StringHashMap(std.ArrayListUnmanaged(u32)),

    /// Next autocmd ID (monotonically increasing)
    next_id: u32,

    /// EventEmitter for actually firing callbacks
    event_emitter: *EventEmitter,

    /// Runtime for creating JS values
    runtime: *c.OVHermesRuntime,

    /// Allocator
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime, event_emitter: *EventEmitter) Self {
        return .{
            .autocmds = std.StringHashMap(std.ArrayListUnmanaged(AutocmdEntry)).init(allocator),
            .groups = std.StringHashMap(std.ArrayListUnmanaged(u32)).init(allocator),
            .next_id = 1,
            .event_emitter = event_emitter,
            .runtime = runtime,
            .allocator = allocator,
        };
    }

    /// Create an autocommand
    /// Returns autocmd ID (can be used with deleteAutoCommand)
    pub fn createAutoCommand(
        self: *Self,
        events: []const []const u8,
        opts: AutocmdOpts,
    ) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        // Clone callback to prevent GC
        const callback_clone = c.hermes_value_clone(self.runtime, opts.callback) orelse
            return error.CloneFailed;
        errdefer c.hermes_value_destroy(callback_clone);

        // Clone strings that need to persist
        const owned_pattern = if (opts.pattern) |p| try self.allocator.dupe(u8, p) else null;
        errdefer if (owned_pattern) |p| self.allocator.free(p);

        const owned_group = if (opts.group) |g| try self.allocator.dupe(u8, g) else null;
        errdefer if (owned_group) |g| self.allocator.free(g);

        const owned_desc = if (opts.desc) |d| try self.allocator.dupe(u8, d) else null;
        errdefer if (owned_desc) |d| self.allocator.free(d);

        const entry = AutocmdEntry{
            .id = id,
            .group = owned_group,
            .pattern = owned_pattern,
            .callback = callback_clone,
            .once = opts.once,
            .desc = owned_desc,
        };

        // Register for each event
        for (events) |event| {
            const owned_event = try self.allocator.dupe(u8, event);
            errdefer self.allocator.free(owned_event);

            const result = try self.autocmds.getOrPut(owned_event);
            if (!result.found_existing) {
                result.value_ptr.* = .empty;
            } else {
                // Key already exists, free our duplicate
                self.allocator.free(owned_event);
            }

            try result.value_ptr.append(self.allocator, entry);
        }

        // Track in group if specified
        if (owned_group) |group| {
            const group_result = try self.groups.getOrPut(group);
            if (!group_result.found_existing) {
                group_result.value_ptr.* = .empty;
            }
            try group_result.value_ptr.append(self.allocator, id);
        }

        return id;
    }

    /// Delete an autocommand by ID
    pub fn deleteAutoCommand(self: *Self, id: u32) void {
        var iter = self.autocmds.iterator();
        while (iter.next()) |entry| {
            var list = entry.value_ptr.*;
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i].id == id) {
                    // Free resources
                    const item = list.items[i];
                    c.hermes_value_destroy(item.callback);
                    if (item.pattern) |p| self.allocator.free(p);
                    if (item.group) |g| self.allocator.free(g);
                    if (item.desc) |d| self.allocator.free(d);

                    _ = list.swapRemove(i);
                    entry.value_ptr.* = list;
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Clear all autocommands in a group
    pub fn clearGroup(self: *Self, group_name: []const u8) void {
        if (self.groups.get(group_name)) |ids| {
            for (ids.items) |id| {
                self.deleteAutoCommand(id);
            }
        }

        // Remove group entry
        if (self.groups.fetchRemove(group_name)) |kv| {
            var list = kv.value;
            list.deinit(self.allocator);
        }
    }

    /// Execute autocommands for an event
    /// Called from Zig when events occur (e.g., buffer enter, file write)
    pub fn execAutocmds(self: *Self, event: []const u8, ev_data: AutocmdEventData) !void {
        const list = self.autocmds.get(event) orelse return;

        // Create event object to pass to callbacks
        const ev_obj = try self.createEventObject(event, ev_data);
        defer c.hermes_value_destroy(ev_obj);

        var to_remove = std.ArrayListUnmanaged(u32).empty;
        defer to_remove.deinit(self.allocator);

        for (list.items) |entry| {
            // Check pattern match if pattern specified
            if (entry.pattern) |pattern| {
                if (!matchPattern(pattern, ev_data.file orelse "")) {
                    continue; // Pattern doesn't match, skip
                }
            }

            // Call the callback
            const args = [_]*c.OVHermesValue{ev_obj};
            const c_args: [*c]?*c.OVHermesValue = @ptrCast(@constCast(&args));
            const result = c.hermes_call_function(
                self.runtime,
                entry.callback,
                c_args,
                1,
            );

            if (result) |r| {
                c.hermes_value_destroy(r);
            }

            // Mark for removal if once
            if (entry.once) {
                try to_remove.append(self.allocator, entry.id);
            }
        }

        // Remove "once" autocmds
        for (to_remove.items) |id| {
            self.deleteAutoCommand(id);
        }
    }

    /// Create event object passed to callbacks
    /// { event: string, buf: number, file: string, match: string }
    fn createEventObject(self: *Self, event: []const u8, data: AutocmdEventData) !*c.OVHermesValue {
        const obj = c.hermes_value_create_object(self.runtime) orelse
            return error.CreateObjectFailed;

        // event
        if (c.hermes_value_create_string(self.runtime, event.ptr, event.len)) |ev_str| {
            c.hermes_value_set_property(self.runtime, obj, "event", ev_str);
            c.hermes_value_destroy(ev_str);
        }

        // buf
        const buf_num = c.hermes_value_create_number(self.runtime, @floatFromInt(data.buf));
        if (buf_num) |bn| {
            c.hermes_value_set_property(self.runtime, obj, "buf", bn);
            c.hermes_value_destroy(bn);
        }

        // file
        if (data.file) |file| {
            if (c.hermes_value_create_string(self.runtime, file.ptr, file.len)) |file_str| {
                c.hermes_value_set_property(self.runtime, obj, "file", file_str);
                c.hermes_value_destroy(file_str);
            }
        }

        // match (same as file for now)
        if (data.match) |match| {
            if (c.hermes_value_create_string(self.runtime, match.ptr, match.len)) |match_str| {
                c.hermes_value_set_property(self.runtime, obj, "match", match_str);
                c.hermes_value_destroy(match_str);
            }
        }

        return obj;
    }

    pub fn deinit(self: *Self) void {
        // Free all autocmd entries
        var iter = self.autocmds.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |item| {
                c.hermes_value_destroy(item.callback);
                if (item.pattern) |p| self.allocator.free(p);
                if (item.group) |g| self.allocator.free(g);
                if (item.desc) |d| self.allocator.free(d);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.autocmds.deinit();

        // Free groups
        var group_iter = self.groups.iterator();
        while (group_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.groups.deinit();
    }
};

/// Options for createAutoCommand
pub const AutocmdOpts = struct {
    callback: *c.OVHermesValue,
    pattern: ?[]const u8 = null,
    group: ?[]const u8 = null,
    once: bool = false,
    desc: ?[]const u8 = null,
};

/// Event data passed to autocmd callbacks
pub const AutocmdEventData = struct {
    buf: u32 = 0,
    file: ?[]const u8 = null,
    match: ?[]const u8 = null,
};

/// Simple glob pattern matching (supports * wildcard)
/// Public for testing
pub fn matchPattern(pattern: []const u8, filename: []const u8) bool {
    // Handle exact match
    if (std.mem.eql(u8, pattern, "*")) return true;

    // Handle *.ext pattern
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..]; // ".ext"
        return std.mem.endsWith(u8, filename, ext);
    }

    // Handle exact match
    if (std.mem.eql(u8, pattern, filename)) return true;

    // Handle basename match
    const basename = std.fs.path.basename(filename);
    if (std.mem.eql(u8, pattern, basename)) return true;

    return false;
}

// ============================================================================
// JavaScript API
// ============================================================================

/// Global autocmd manager (set during init)
var global_autocmd_manager: ?*AutocmdManager = null;

/// Initialize autocmd manager
pub fn initAutocmdManager(manager: *AutocmdManager) void {
    global_autocmd_manager = manager;
}

/// vim.api.createAutoCommand(event, opts)
///
/// Creates an autocommand event handler.
///
/// Arguments:
///   event: string | string[] - Event name(s) to trigger on
///   opts: { callback, pattern?, group?, once?, desc? }
///
/// Returns: number (autocmd ID)
pub export fn apiCreateAutoCommand(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (arg_count < 2) {
        c.hermes_throw_error(rt, "createAutoCommand requires 2 arguments (event, opts)");
        return null;
    }

    const manager = global_autocmd_manager orelse {
        c.hermes_throw_error(rt, "Autocmd manager not initialized");
        return null;
    };

    // Parse event argument (string only for now, array support can be added later)
    // TODO: Add array support when hermes_value_is_array is added to C API
    var events_buf: [16][]const u8 = undefined;
    var events_count: usize = 0;

    if (c.hermes_value_is_string(args[0])) {
        var len: usize = 0;
        const ptr = c.hermes_value_get_string(rt, args[0], &len);
        if (ptr != null and len > 0) {
            events_buf[0] = ptr[0..len];
            events_count = 1;
        }
    }

    if (events_count == 0) {
        c.hermes_throw_error(rt, "createAutoCommand: event must be a string");
        return null;
    }

    // Parse opts object
    const opts_val = args[1] orelse {
        c.hermes_throw_error(rt, "createAutoCommand: opts is required");
        return null;
    };

    if (!c.hermes_value_is_object(opts_val)) {
        c.hermes_throw_error(rt, "createAutoCommand: opts must be an object");
        return null;
    }

    // Get callback (required)
    const callback = c.hermes_value_get_property(rt, opts_val, "callback") orelse {
        c.hermes_throw_error(rt, "createAutoCommand: opts.callback is required");
        return null;
    };
    defer c.hermes_value_destroy(callback);

    if (!c.hermes_value_is_function(rt, callback)) {
        c.hermes_throw_error(rt, "createAutoCommand: opts.callback must be a function");
        return null;
    }

    // Get optional pattern
    var pattern_slice: ?[]const u8 = null;
    if (c.hermes_value_get_property(rt, opts_val, "pattern")) |pattern_val| {
        defer c.hermes_value_destroy(pattern_val);
        if (c.hermes_value_is_string(pattern_val)) {
            var len: usize = 0;
            const ptr = c.hermes_value_get_string(rt, pattern_val, &len);
            if (ptr != null and len > 0) {
                pattern_slice = ptr[0..len];
            }
        }
    }

    // Get optional group
    var group_slice: ?[]const u8 = null;
    if (c.hermes_value_get_property(rt, opts_val, "group")) |group_val| {
        defer c.hermes_value_destroy(group_val);
        if (c.hermes_value_is_string(group_val)) {
            var len: usize = 0;
            const ptr = c.hermes_value_get_string(rt, group_val, &len);
            if (ptr != null and len > 0) {
                group_slice = ptr[0..len];
            }
        }
    }

    // Get optional once
    var once: bool = false;
    if (c.hermes_value_get_property(rt, opts_val, "once")) |once_val| {
        defer c.hermes_value_destroy(once_val);
        if (c.hermes_value_is_boolean(once_val)) {
            once = c.hermes_value_get_boolean(once_val);
        }
    }

    // Get optional desc
    var desc_slice: ?[]const u8 = null;
    if (c.hermes_value_get_property(rt, opts_val, "desc")) |desc_val| {
        defer c.hermes_value_destroy(desc_val);
        if (c.hermes_value_is_string(desc_val)) {
            var len: usize = 0;
            const ptr = c.hermes_value_get_string(rt, desc_val, &len);
            if (ptr != null and len > 0) {
                desc_slice = ptr[0..len];
            }
        }
    }

    // Create the autocmd
    const opts = AutocmdOpts{
        .callback = callback,
        .pattern = pattern_slice,
        .group = group_slice,
        .once = once,
        .desc = desc_slice,
    };

    const id = manager.createAutoCommand(events_buf[0..events_count], opts) catch |err| {
        var err_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&err_buf, "createAutoCommand failed: {s}", .{@errorName(err)}) catch "createAutoCommand failed";
        c.hermes_throw_error(rt, msg.ptr);
        return null;
    };

    return c.hermes_value_create_number(rt, @floatFromInt(id));
}

/// vim.api.deleteAutoCommand(id)
/// Delete an autocommand by ID
pub export fn apiDeleteAutoCommand(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (arg_count < 1) {
        c.hermes_throw_error(rt, "deleteAutoCommand requires 1 argument (id)");
        return null;
    }

    const manager = global_autocmd_manager orelse {
        c.hermes_throw_error(rt, "Autocmd manager not initialized");
        return null;
    };

    if (!c.hermes_value_is_number(args[0])) {
        c.hermes_throw_error(rt, "deleteAutoCommand: id must be a number");
        return null;
    }

    const id_f = c.hermes_value_get_number(args[0]);
    const id: u32 = @intFromFloat(id_f);

    manager.deleteAutoCommand(id);

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.createAutoGroup(name, opts)
/// Create or get an autocommand group
pub export fn apiCreateAutoGroup(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (arg_count < 1) {
        c.hermes_throw_error(rt, "createAutoGroup requires at least 1 argument (name)");
        return null;
    }

    const manager = global_autocmd_manager orelse {
        c.hermes_throw_error(rt, "Autocmd manager not initialized");
        return null;
    };

    if (!c.hermes_value_is_string(args[0])) {
        c.hermes_throw_error(rt, "createAutoGroup: name must be a string");
        return null;
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const group_name = name_ptr[0..name_len];

    // Check opts.clear
    var clear = false;
    if (arg_count >= 2) {
        if (args[1]) |opts_val| {
            if (c.hermes_value_is_object(opts_val)) {
                if (c.hermes_value_get_property(rt, opts_val, "clear")) |clear_val| {
                    defer c.hermes_value_destroy(clear_val);
                    if (c.hermes_value_is_boolean(clear_val)) {
                        clear = c.hermes_value_get_boolean(clear_val);
                    }
                }
            }
        }
    }

    // Clear group if requested
    if (clear) {
        manager.clearGroup(group_name);
    }

    // Return group name as ID (Neovim returns numeric ID, we return name for simplicity)
    return c.hermes_value_create_string(rt, group_name.ptr, group_name.len);
}

/// vim.api.clearAutoCommands(opts)
/// Clear autocommands matching criteria
pub export fn apiClearAutoCommands(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const manager = global_autocmd_manager orelse {
        c.hermes_throw_error(rt, "Autocmd manager not initialized");
        return null;
    };

    if (arg_count >= 1 and args[0] != null) {
        const opts_val = args[0].?;

        // Clear by group
        if (c.hermes_value_get_property(rt, opts_val, "group")) |group_val| {
            defer c.hermes_value_destroy(group_val);
            if (c.hermes_value_is_string(group_val)) {
                var len: usize = 0;
                const ptr = c.hermes_value_get_string(rt, group_val, &len);
                if (ptr != null and len > 0) {
                    manager.clearGroup(ptr[0..len]);
                }
            }
        }
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// Registration
// ============================================================================

/// Register autocmd API functions
pub fn register(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_function(runtime, "vimApiCreateAutoCommand", apiCreateAutoCommand, null);
    c.hermes_register_host_function(runtime, "vimApiDeleteAutoCommand", apiDeleteAutoCommand, null);
    c.hermes_register_host_function(runtime, "vimApiCreateAutoGroup", apiCreateAutoGroup, null);
    c.hermes_register_host_function(runtime, "vimApiClearAutoCommands", apiClearAutoCommands, null);
}

// ============================================================================
// Tests
// ============================================================================

test "matchPattern: glob patterns" {
    // *.js matches .js files
    try std.testing.expect(matchPattern("*.js", "foo.js"));
    try std.testing.expect(matchPattern("*.js", "/path/to/bar.js"));
    try std.testing.expect(!matchPattern("*.js", "foo.ts"));

    // *.ts matches .ts files
    try std.testing.expect(matchPattern("*.ts", "app.ts"));
    try std.testing.expect(!matchPattern("*.ts", "app.js"));

    // * matches everything
    try std.testing.expect(matchPattern("*", "anything.txt"));
    try std.testing.expect(matchPattern("*", ""));

    // Exact match
    try std.testing.expect(matchPattern("Makefile", "Makefile"));
    try std.testing.expect(matchPattern("Makefile", "/path/to/Makefile"));
}

test "matchPattern: extension edge cases" {
    // Multiple dots in filename
    try std.testing.expect(matchPattern("*.js", "foo.bar.js"));
    try std.testing.expect(matchPattern("*.min.js", "app.min.js"));
    try std.testing.expect(!matchPattern("*.min.js", "app.js"));

    // Hidden files with extension
    try std.testing.expect(matchPattern("*.js", ".hidden.js"));

    // No extension
    try std.testing.expect(!matchPattern("*.js", "README"));
    try std.testing.expect(matchPattern("README", "README"));
    try std.testing.expect(matchPattern("README", "/path/to/README"));

    // Note: .* pattern (match hidden files) is NOT supported yet
    // Neovim uses more complex glob matching; we only support *.ext patterns
}

test "matchPattern: path handling" {
    // Full paths with extension matching
    try std.testing.expect(matchPattern("*.zig", "/Users/test/src/main.zig"));
    try std.testing.expect(matchPattern("*.zig", "src/editor/buffer.zig"));

    // Basename matching
    try std.testing.expect(matchPattern("build.zig", "/project/build.zig"));
    try std.testing.expect(matchPattern("build.zig", "build.zig"));
    try std.testing.expect(!matchPattern("build.zig", "other.zig"));

    // Common config files
    try std.testing.expect(matchPattern("*.json", "package.json"));
    try std.testing.expect(matchPattern("*.json", "tsconfig.json"));
    try std.testing.expect(matchPattern("*.toml", "Cargo.toml"));
}

test "matchPattern: TypeScript/JavaScript files" {
    // TypeScript
    try std.testing.expect(matchPattern("*.ts", "index.ts"));
    try std.testing.expect(matchPattern("*.tsx", "App.tsx"));
    try std.testing.expect(!matchPattern("*.ts", "index.tsx")); // .ts doesn't match .tsx

    // JavaScript
    try std.testing.expect(matchPattern("*.js", "index.js"));
    try std.testing.expect(matchPattern("*.jsx", "App.jsx"));
    try std.testing.expect(!matchPattern("*.js", "index.jsx")); // .js doesn't match .jsx

    // Common patterns
    try std.testing.expect(matchPattern("*.d.ts", "types.d.ts"));
    try std.testing.expect(!matchPattern("*.d.ts", "types.ts"));
}
