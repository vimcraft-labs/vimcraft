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

/// Options Manager - stores and manages editor options
pub const OptionsManager = struct {
    allocator: std.mem.Allocator,
    options: std.StringHashMap(OptionValue),

    pub fn init(allocator: std.mem.Allocator) OptionsManager {
        return .{
            .allocator = allocator,
            .options = std.StringHashMap(OptionValue).init(allocator),
        };
    }

    pub fn deinit(self: *OptionsManager) void {
        // Free all keys and string values
        var iter = self.options.iterator();
        while (iter.next()) |entry| {
            // Free the key (we own it)
            self.allocator.free(entry.key_ptr.*);
            // Free the value (strings only)
            var value = entry.value_ptr.*;
            value.deinit(self.allocator);
        }
        self.options.deinit();
    }

    /// Set an option value
    pub fn set(self: *OptionsManager, name: []const u8, value: OptionValue) !void {
        // Clone the value first (deep copy strings)
        var cloned = try value.clone(self.allocator);
        errdefer cloned.deinit(self.allocator);

        // Check if option already exists - if so, just update the value
        if (self.options.getPtr(name)) |existing_value_ptr| {
            // Free the old value
            existing_value_ptr.deinit(self.allocator);
            // Update with new value
            existing_value_ptr.* = cloned;
        } else {
            // New option - duplicate the key and insert
            const owned_key = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(owned_key);
            try self.options.put(owned_key, cloned);
        }
    }

    /// Get an option value
    pub fn get(self: *const OptionsManager, name: []const u8) ?OptionValue {
        return self.options.get(name);
    }

    /// Check if an option exists
    pub fn has(self: *const OptionsManager, name: []const u8) bool {
        return self.options.contains(name);
    }

    /// Remove an option (reset to default)
    pub fn remove(self: *OptionsManager, name: []const u8) void {
        if (self.options.fetchRemove(name)) |entry| {
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

    /// Set boolean option (type-safe)
    pub fn setBoolean(self: *OptionsManager, name: []const u8, value: bool) !void {
        try self.set(name, .{ .boolean = value });
    }

    /// Set number option (type-safe)
    pub fn setNumber(self: *OptionsManager, name: []const u8, value: i64) !void {
        try self.set(name, .{ .number = value });
    }

    /// Set string option (type-safe, makes a copy)
    pub fn setString(self: *OptionsManager, name: []const u8, value: []const u8) !void {
        // Pass the slice to set(), which will duplicate it via clone()
        try self.set(name, .{ .string = value });
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
