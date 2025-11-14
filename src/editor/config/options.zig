const std = @import("std");

/// Option type classification
pub const OptionType = enum {
    boolean,
    number,
    string,
};

/// Option value (tagged union)
pub const OptionValue = union(OptionType) {
    boolean: bool,
    number: i64,
    string: []const u8,

    /// Create a boolean option value
    pub fn fromBool(value: bool) OptionValue {
        return .{ .boolean = value };
    }

    /// Create a number option value
    pub fn fromNumber(value: i64) OptionValue {
        return .{ .number = value };
    }

    /// Create a string option value (caller must manage memory)
    pub fn fromString(value: []const u8) OptionValue {
        return .{ .string = value };
    }

    /// Free string memory if needed
    pub fn deinit(self: *OptionValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }

    /// Clone an option value (deep copy strings)
    pub fn clone(self: OptionValue, allocator: std.mem.Allocator) !OptionValue {
        return switch (self) {
            .boolean => |v| .{ .boolean = v },
            .number => |v| .{ .number = v },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
        };
    }
};

/// Option metadata (name, type, default, scope)
pub const OptionMeta = struct {
    name: []const u8,
    short_name: ?[]const u8 = null,
    type: OptionType,
    default: OptionValue,
    scope: Scope,

    pub const Scope = enum {
        global, // Global to all buffers/windows
        buffer, // Buffer-local (each buffer has own value)
        window, // Window-local (each window has own value)
    };
};

/// Option scope for get/set operations
pub const OptionScope = enum {
    global, // Global options only
    local, // Buffer/window local (with fallback to global)
    force_local, // Force buffer/window local (no fallback)
};

/// Options Manager - stores and manages editor options with scope support
pub const OptionsManager = struct {
    allocator: std.mem.Allocator,
    global_options: std.StringHashMap(OptionValue), // Global options
    buffer_local_options: std.StringHashMap(OptionValue), // Buffer-local options
    window_local_options: std.StringHashMap(OptionValue), // Window-local options (future)

    pub fn init(allocator: std.mem.Allocator) OptionsManager {
        return .{
            .allocator = allocator,
            .global_options = std.StringHashMap(OptionValue).init(allocator),
            .buffer_local_options = std.StringHashMap(OptionValue).init(allocator),
            .window_local_options = std.StringHashMap(OptionValue).init(allocator),
        };
    }

    pub fn deinit(self: *OptionsManager) void {
        // Free global options
        {
            var iter = self.global_options.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var value = entry.value_ptr.*;
                value.deinit(self.allocator);
            }
            self.global_options.deinit();
        }

        // Free buffer-local options
        {
            var iter = self.buffer_local_options.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var value = entry.value_ptr.*;
                value.deinit(self.allocator);
            }
            self.buffer_local_options.deinit();
        }

        // Free window-local options
        {
            var iter = self.window_local_options.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var value = entry.value_ptr.*;
                value.deinit(self.allocator);
            }
            self.window_local_options.deinit();
        }
    }

    /// Set an option value (defaults to global scope for backward compatibility)
    pub fn set(self: *OptionsManager, name: []const u8, value: OptionValue) !void {
        try self.setWithScope(name, value, .global);
    }

    /// Set an option value with explicit scope
    pub fn setWithScope(self: *OptionsManager, name: []const u8, value: OptionValue, scope: OptionScope) !void {
        // Clone the value first (deep copy strings)
        var cloned = try value.clone(self.allocator);
        errdefer cloned.deinit(self.allocator);

        // Select the appropriate storage based on scope
        const storage = switch (scope) {
            .global => &self.global_options,
            .local, .force_local => &self.buffer_local_options, // For now, local = buffer-local
        };

        // Check if option already exists - if so, just update the value
        if (storage.getPtr(name)) |existing_value_ptr| {
            // Free the old value
            existing_value_ptr.deinit(self.allocator);
            // Update with new value
            existing_value_ptr.* = cloned;
        } else {
            // New option - duplicate the key and insert
            const owned_key = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(owned_key);
            try storage.put(owned_key, cloned);
        }
    }

    /// Get an option value (defaults to local scope with global fallback)
    pub fn get(self: *const OptionsManager, name: []const u8) ?OptionValue {
        return self.getWithScope(name, .local);
    }

    /// Get an option value with explicit scope
    pub fn getWithScope(self: *const OptionsManager, name: []const u8, scope: OptionScope) ?OptionValue {
        return switch (scope) {
            .global => self.global_options.get(name),
            .local => {
                // Try buffer-local first, then fallback to global
                if (self.buffer_local_options.get(name)) |value| {
                    return value;
                }
                return self.global_options.get(name);
            },
            .force_local => self.buffer_local_options.get(name), // No fallback
        };
    }

    /// Check if an option exists (checks all scopes)
    pub fn has(self: *const OptionsManager, name: []const u8) bool {
        return self.buffer_local_options.contains(name) or self.global_options.contains(name);
    }

    /// Check if an option exists in a specific scope
    pub fn hasWithScope(self: *const OptionsManager, name: []const u8, scope: OptionScope) bool {
        return switch (scope) {
            .global => self.global_options.contains(name),
            .local => self.buffer_local_options.contains(name) or self.global_options.contains(name),
            .force_local => self.buffer_local_options.contains(name),
        };
    }

    /// Remove an option (from global scope by default)
    pub fn remove(self: *OptionsManager, name: []const u8) void {
        self.removeWithScope(name, .global);
    }

    /// Remove an option from a specific scope
    pub fn removeWithScope(self: *OptionsManager, name: []const u8, scope: OptionScope) void {
        const storage = switch (scope) {
            .global => &self.global_options,
            .local, .force_local => &self.buffer_local_options,
        };

        if (storage.fetchRemove(name)) |entry| {
            // Free both key and value
            self.allocator.free(entry.key);
            var value = entry.value;
            value.deinit(self.allocator);
        }
    }

    /// Get option as boolean (returns null if wrong type or doesn't exist)
    pub fn getBoolean(self: *const OptionsManager, name: []const u8) ?bool {
        const value = self.get(name) orelse return null;
        return switch (value) {
            .boolean => |v| v,
            else => null,
        };
    }

    /// Get option as number (returns null if wrong type or doesn't exist)
    pub fn getNumber(self: *const OptionsManager, name: []const u8) ?i64 {
        const value = self.get(name) orelse return null;
        return switch (value) {
            .number => |v| v,
            else => null,
        };
    }

    /// Get option as string (returns null if wrong type or doesn't exist)
    pub fn getString(self: *const OptionsManager, name: []const u8) ?[]const u8 {
        const value = self.get(name) orelse return null;
        return switch (value) {
            .string => |s| s,
            else => null,
        };
    }

    /// Set boolean option (type-safe, defaults to global scope)
    pub fn setBoolean(self: *OptionsManager, name: []const u8, value: bool) !void {
        try self.set(name, .{ .boolean = value });
    }

    /// Set boolean option with explicit scope (type-safe)
    pub fn setBooleanWithScope(self: *OptionsManager, name: []const u8, value: bool, scope: OptionScope) !void {
        try self.setWithScope(name, .{ .boolean = value }, scope);
    }

    /// Set number option (type-safe, defaults to global scope)
    pub fn setNumber(self: *OptionsManager, name: []const u8, value: i64) !void {
        try self.set(name, .{ .number = value });
    }

    /// Set number option with explicit scope (type-safe)
    pub fn setNumberWithScope(self: *OptionsManager, name: []const u8, value: i64, scope: OptionScope) !void {
        try self.setWithScope(name, .{ .number = value }, scope);
    }

    /// Set string option (type-safe, makes a copy, defaults to global scope)
    pub fn setString(self: *OptionsManager, name: []const u8, value: []const u8) !void {
        // Pass the slice to set(), which will duplicate it via clone()
        try self.set(name, .{ .string = value });
    }

    /// Set string option with explicit scope (type-safe, makes a copy)
    pub fn setStringWithScope(self: *OptionsManager, name: []const u8, value: []const u8, scope: OptionScope) !void {
        try self.setWithScope(name, .{ .string = value }, scope);
    }
};

// Tests
test "OptionsManager: init and deinit" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expect(mgr.options.count() == 0);
}

test "OptionsManager: set and get boolean" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.setBoolean("number", true);

    const value = mgr.getBoolean("number");
    try std.testing.expect(value != null);
    try std.testing.expect(value.? == true);
}

test "OptionsManager: set and get number" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.setNumber("tabstop", 4);

    const value = mgr.getNumber("tabstop");
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(i64, 4), value.?);
}

test "OptionsManager: set and get string" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.setString("clipboard", "unnamed");

    const value = mgr.getString("clipboard");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("unnamed", value.?);
}

test "OptionsManager: overwrite existing option" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.setBoolean("number", false);
    try mgr.setBoolean("number", true);

    const value = mgr.getBoolean("number");
    try std.testing.expect(value.? == true);
}

test "OptionsManager: remove option" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.setBoolean("number", true);
    try std.testing.expect(mgr.has("number"));

    mgr.remove("number");
    try std.testing.expect(!mgr.has("number"));
}

test "OptionsManager: type mismatch returns null" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.setBoolean("number", true);

    // Try to get as number (should return null)
    const value = mgr.getNumber("number");
    try std.testing.expect(value == null);
}

test "OptionsManager: string memory management" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    // Set string multiple times (should not leak)
    try mgr.setString("clipboard", "unnamed");
    try mgr.setString("clipboard", "unnamedplus");
    try mgr.setString("clipboard", "autoselect");

    const value = mgr.getString("clipboard");
    try std.testing.expectEqualStrings("autoselect", value.?);
}

test "OptionsManager: buffer-local option overrides global" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    // Set global option
    try mgr.setBooleanWithScope("number", false, .global);

    // Set buffer-local option
    try mgr.setBooleanWithScope("number", true, .local);

    // Getting with local scope should return buffer-local value
    const local_value = mgr.getWithScope("number", .local);
    try std.testing.expect(local_value != null);
    try std.testing.expect(local_value.?.boolean == true);

    // Getting with global scope should return global value
    const global_value = mgr.getWithScope("number", .global);
    try std.testing.expect(global_value != null);
    try std.testing.expect(global_value.?.boolean == false);
}

test "OptionsManager: local fallback to global" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    // Set only global option (no buffer-local)
    try mgr.setBooleanWithScope("cursorLine", true, .global);

    // Getting with local scope should fallback to global
    const value = mgr.getWithScope("cursorLine", .local);
    try std.testing.expect(value != null);
    try std.testing.expect(value.?.boolean == true);
}

test "OptionsManager: force_local does not fallback" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    // Set only global option
    try mgr.setBooleanWithScope("tabStop", true, .global);

    // Getting with force_local should NOT fallback to global
    const value = mgr.getWithScope("tabStop", .force_local);
    try std.testing.expect(value == null);
}

test "OptionsManager: remove buffer-local preserves global" {
    const allocator = std.testing.allocator;
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    // Set both global and buffer-local
    try mgr.setBooleanWithScope("number", false, .global);
    try mgr.setBooleanWithScope("number", true, .local);

    // Remove buffer-local
    mgr.removeWithScope("number", .local);

    // Should now get global value
    const value = mgr.getWithScope("number", .local);
    try std.testing.expect(value != null);
    try std.testing.expect(value.?.boolean == false);
}
