/// Keymap Module
/// Manages custom key mappings (vim.keymap.set/del)
/// Allows users to bind keys to commands or JavaScript callbacks
const std = @import("std");

/// Mode for key mapping
pub const Mode = enum {
    normal,
    insert,
    visual,
    command,

    /// Parse mode from string ('n', 'i', 'v', 'c')
    pub fn fromString(s: []const u8) ?Mode {
        if (s.len != 1) return null;
        return switch (s[0]) {
            'n' => .normal,
            'i' => .insert,
            'v' => .visual,
            'c' => .command,
            else => null,
        };
    }

    pub fn toString(self: Mode) []const u8 {
        return switch (self) {
            .normal => "n",
            .insert => "i",
            .visual => "v",
            .command => "c",
        };
    }
};

/// Right-hand side of mapping (what gets executed)
pub const MappingRHS = union(enum) {
    /// String of keys to execute (e.g., "Hzz")
    keys: []const u8,

    /// JavaScript callback function ID
    /// The actual function is stored in JSI runtime
    callback: u32,

    pub fn deinit(self: *MappingRHS, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .keys => |k| allocator.free(k),
            .callback => {}, // Callback cleanup handled by JSI
        }
    }
};

/// Options for key mapping
pub const KeymapOpts = struct {
    /// Prevent recursive mapping (default: false)
    noremap: bool = false,

    /// Don't show command in status line (default: false)
    silent: bool = false,

    /// Buffer-local mapping (default: false, global)
    buffer: bool = false,
};

/// Single keymap entry
pub const KeymapEntry = struct {
    /// Left-hand side (key to press)
    lhs: []const u8,

    /// Right-hand side (what to execute)
    rhs: MappingRHS,

    /// Mode this mapping applies to
    mode: Mode,

    /// Mapping options
    opts: KeymapOpts,

    /// Buffer ID for buffer-local mappings (null = global)
    /// For now, Vimcraft has single-buffer support, so 0 = current buffer
    /// Later, this will support actual buffer IDs
    buffer_id: ?usize,

    pub fn deinit(self: *KeymapEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.lhs);
        self.rhs.deinit(allocator);
    }
};

/// Key for HashMap (mode + lhs)
const MapKey = struct {
    mode: Mode,
    lhs: []const u8,

    /// Create hash key string: "mode:lhs" (e.g., "n:H")
    pub fn toString(self: MapKey, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ self.mode.toString(), self.lhs });
    }
};

/// Result of looking up a key mapping (Helix-style)
/// This enables stateful pending keys without needing a typeahead buffer
pub const LookupResult = union(enum) {
    /// Full match found - execute this mapping
    matched: *const KeymapEntry,

    /// Partial match - need more keys (e.g., "j" when "jk" is mapped)
    /// Caller should wait for next key OR timeout
    pending,

    /// No match found - fall through to built-in commands
    not_found,
};

/// Keymap Manager - stores and retrieves key mappings
/// Uses Helix-style stateful pending keys (no typeahead buffer needed)
pub const KeymapManager = struct {
    allocator: std.mem.Allocator,
    mappings: std.StringHashMap(KeymapEntry),

    /// Pending keys accumulated from partial matches (Helix-style)
    /// Example: User types "j" when "jk" is mapped → pending_keys = "j"
    /// When user types "k" next → pending_keys + "k" = "jk" → matched!
    ///
    /// NOTE: This is cleared on:
    /// - Full match found (mapping executed)
    /// - No prefix match (not_found)
    /// - ESC pressed (cancellation)
    pending_keys: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) KeymapManager {
        return .{
            .allocator = allocator,
            .mappings = std.StringHashMap(KeymapEntry).init(allocator),
            .pending_keys = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *KeymapManager) void {
        // Free all entries
        var iter = self.mappings.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*); // Free the key string
            var val = entry.value_ptr;
            val.deinit(self.allocator);
        }
        self.mappings.deinit();
        self.pending_keys.deinit(self.allocator);
    }

    /// Clear pending keys (called on ESC, mode change, or after match)
    pub fn clearPending(self: *KeymapManager) void {
        self.pending_keys.clearRetainingCapacity();
    }

    /// Set a key mapping
    pub fn set(
        self: *KeymapManager,
        mode: Mode,
        lhs: []const u8,
        rhs: MappingRHS,
        opts: KeymapOpts,
        buffer_id: ?usize, // null = global, 0 = current buffer (for now)
    ) !void {
        // Create composite key that includes buffer_id for uniqueness
        // Format: "mode:lhs" (global) or "mode:lhs:bufN" (buffer-local)
        const key = if (buffer_id) |buf_id|
            try std.fmt.allocPrint(self.allocator, "{s}:{s}:buf{}", .{ mode.toString(), lhs, buf_id })
        else
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ mode.toString(), lhs });
        errdefer self.allocator.free(key);

        // If mapping already exists, remove old one
        if (self.mappings.fetchRemove(key)) |old| {
            self.allocator.free(old.key); // Free old key
            var old_entry = old.value;
            old_entry.deinit(self.allocator);
        }

        // Create new entry
        const lhs_copy = try self.allocator.dupe(u8, lhs);
        errdefer self.allocator.free(lhs_copy);

        const entry = KeymapEntry{
            .lhs = lhs_copy,
            .rhs = rhs,
            .mode = mode,
            .opts = opts,
            .buffer_id = buffer_id,
        };

        try self.mappings.put(key, entry);
    }

    /// Delete a key mapping (both global and buffer-local)
    pub fn del(self: *KeymapManager, mode: Mode, lhs: []const u8, buffer_id: ?usize) !void {
        const key = if (buffer_id) |buf_id|
            try std.fmt.allocPrint(self.allocator, "{s}:{s}:buf{}", .{ mode.toString(), lhs, buf_id })
        else
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ mode.toString(), lhs });
        defer self.allocator.free(key);

        if (self.mappings.fetchRemove(key)) |removed| {
            self.allocator.free(removed.key);
            var entry = removed.value;
            entry.deinit(self.allocator);
        }
    }

    /// Get a key mapping (returns pointer to entry, valid until next set/del)
    pub fn get(self: *KeymapManager, mode: Mode, lhs: []const u8, buffer_id: ?usize) !?*const KeymapEntry {
        const key = if (buffer_id) |buf_id|
            try std.fmt.allocPrint(self.allocator, "{s}:{s}:buf{}", .{ mode.toString(), lhs, buf_id })
        else
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ mode.toString(), lhs });
        defer self.allocator.free(key);

        return self.mappings.getPtr(key);
    }

    /// Lookup mapping for current input in given mode (Helix-style stateful approach)
    /// This accumulates pending keys across calls until match or timeout
    ///
    /// Neovim precedence: buffer-local first, then global
    ///
    /// Returns:
    /// - .matched: Full mapping found, execute it (pending_keys cleared)
    /// - .pending: Partial match, wait for more keys (input accumulated in pending_keys)
    /// - .not_found: No match, fall through to built-in (pending_keys cleared)
    ///
    /// NOTE: setTimeout timeout integration happens in Phase 4.5
    /// For now, caller should handle ESC to cancel pending state
    pub fn lookup(self: *KeymapManager, mode: Mode, input: []const u8, current_buffer_id: usize) !LookupResult {
        // Concatenate pending_keys with new input to form full input string
        // Track whether we allocated so we can free properly
        const full_input_allocated = self.pending_keys.items.len > 0;
        const full_input = if (full_input_allocated)
            try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.pending_keys.items, input })
        else
            input;
        defer if (full_input_allocated) self.allocator.free(full_input);

        // Try to find full match (buffer-local first, then global - Neovim precedence)
        if (try self.get(mode, full_input, current_buffer_id) orelse try self.get(mode, full_input, null)) |entry| {
            // Full match found - clear pending and return
            self.clearPending();
            return .{ .matched = entry };
        }

        // No full match - check if input is prefix of longer mapping
        if (self.hasPrefix(mode, full_input, current_buffer_id)) {
            // Partial match - accumulate input and return pending
            try self.pending_keys.appendSlice(self.allocator, input);
            return .pending;
        }

        // No match and no prefix - clear pending and return not_found
        self.clearPending();
        return .not_found;
    }

    /// Check if input is a PREFIX of any mapping (for timeout support)
    /// Returns true if there exist mappings that START with this input
    /// Example: if "jk" is mapped, then "j" is a prefix
    pub fn hasPrefix(self: *KeymapManager, mode: Mode, input: []const u8, current_buffer_id: usize) bool {
        // Check all mappings
        var iter = self.mappings.iterator();
        while (iter.next()) |entry| {
            const mapping = entry.value_ptr;

            // Skip if wrong mode
            if (mapping.mode != mode) continue;

            // Check if this mapping's lhs starts with our input
            if (std.mem.startsWith(u8, mapping.lhs, input) and mapping.lhs.len > input.len) {
                // Found a longer mapping that starts with our input
                // Check scope: buffer-local has precedence
                if (mapping.buffer_id) |buf_id| {
                    if (buf_id == current_buffer_id) {
                        return true;
                    }
                } else {
                    // Global mapping - only matters if no buffer-local prefix exists
                    // For simplicity, return true (conservative approach)
                    return true;
                }
            }
        }

        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "KeymapManager: set and get string mapping" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Set mapping: H -> Hzz in normal mode (global)
    const keys = try allocator.dupe(u8, "Hzz");
    try mgr.set(.normal, "H", .{ .keys = keys }, .{ .noremap = true }, null);

    // Get mapping
    const entry = try mgr.get(.normal, "H", null);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(Mode.normal, entry.?.mode);
    try std.testing.expectEqualStrings("H", entry.?.lhs);
    try std.testing.expectEqual(true, entry.?.opts.noremap);
    try std.testing.expect(entry.?.buffer_id == null); // Global mapping

    switch (entry.?.rhs) {
        .keys => |k| try std.testing.expectEqualStrings("Hzz", k),
        .callback => try std.testing.expect(false), // Should be keys, not callback
    }
}

test "KeymapManager: set callback mapping" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Set mapping with callback ID (global)
    try mgr.set(.normal, "<leader>w", .{ .callback = 42 }, .{ .silent = true }, null);

    const entry = try mgr.get(.normal, "<leader>w", null);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(Mode.normal, entry.?.mode);
    try std.testing.expectEqual(true, entry.?.opts.silent);

    switch (entry.?.rhs) {
        .keys => try std.testing.expect(false), // Should be callback, not keys
        .callback => |id| try std.testing.expectEqual(@as(u32, 42), id),
    }
}

test "KeymapManager: delete mapping" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Set and then delete (global)
    const keys = try allocator.dupe(u8, "test");
    try mgr.set(.normal, "x", .{ .keys = keys }, .{}, null);

    var entry = try mgr.get(.normal, "x", null);
    try std.testing.expect(entry != null);

    try mgr.del(.normal, "x", null);

    entry = try mgr.get(.normal, "x", null);
    try std.testing.expect(entry == null);
}

test "KeymapManager: mode-specific mappings" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Same key, different modes (global)
    const keys1 = try allocator.dupe(u8, "normal_cmd");
    const keys2 = try allocator.dupe(u8, "insert_cmd");

    try mgr.set(.normal, "jk", .{ .keys = keys1 }, .{}, null);
    try mgr.set(.insert, "jk", .{ .keys = keys2 }, .{}, null);

    // Check normal mode
    const normal_entry = try mgr.get(.normal, "jk", null);
    try std.testing.expect(normal_entry != null);
    switch (normal_entry.?.rhs) {
        .keys => |k| try std.testing.expectEqualStrings("normal_cmd", k),
        .callback => try std.testing.expect(false),
    }

    // Check insert mode
    const insert_entry = try mgr.get(.insert, "jk", null);
    try std.testing.expect(insert_entry != null);
    switch (insert_entry.?.rhs) {
        .keys => |k| try std.testing.expectEqualStrings("insert_cmd", k),
        .callback => try std.testing.expect(false),
    }
}

test "KeymapManager: replace existing mapping" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Set initial mapping (global)
    const keys1 = try allocator.dupe(u8, "old_cmd");
    try mgr.set(.normal, "H", .{ .keys = keys1 }, .{}, null);

    // Replace with new mapping (global)
    const keys2 = try allocator.dupe(u8, "new_cmd");
    try mgr.set(.normal, "H", .{ .keys = keys2 }, .{ .silent = true }, null);

    // Verify new mapping
    const entry = try mgr.get(.normal, "H", null);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(true, entry.?.opts.silent);
    switch (entry.?.rhs) {
        .keys => |k| try std.testing.expectEqualStrings("new_cmd", k),
        .callback => try std.testing.expect(false),
    }
}

test "Mode: fromString and toString" {
    try std.testing.expectEqual(Mode.normal, Mode.fromString("n").?);
    try std.testing.expectEqual(Mode.insert, Mode.fromString("i").?);
    try std.testing.expectEqual(Mode.visual, Mode.fromString("v").?);
    try std.testing.expectEqual(Mode.command, Mode.fromString("c").?);
    try std.testing.expect(Mode.fromString("x") == null);
    try std.testing.expect(Mode.fromString("nope") == null);

    try std.testing.expectEqualStrings("n", Mode.normal.toString());
    try std.testing.expectEqualStrings("i", Mode.insert.toString());
    try std.testing.expectEqualStrings("v", Mode.visual.toString());
    try std.testing.expectEqualStrings("c", Mode.command.toString());
}

test "KeymapManager: buffer-local overrides global (Neovim precedence)" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Set global mapping: H -> global_cmd
    const global_keys = try allocator.dupe(u8, "global_cmd");
    try mgr.set(.normal, "H", .{ .keys = global_keys }, .{}, null);

    // Set buffer-local mapping: H -> buffer_cmd (buffer 0)
    const buffer_keys = try allocator.dupe(u8, "buffer_cmd");
    try mgr.set(.normal, "H", .{ .keys = buffer_keys }, .{ .buffer = true }, 0);

    // Lookup should return buffer-local mapping (Neovim precedence)
    const result = try mgr.lookup(.normal, "H", 0);
    switch (result) {
        .matched => |entry| {
            try std.testing.expect(entry.buffer_id != null);
            try std.testing.expectEqual(@as(usize, 0), entry.buffer_id.?);
            switch (entry.rhs) {
                .keys => |k| try std.testing.expectEqualStrings("buffer_cmd", k),
                .callback => try std.testing.expect(false),
            }
        },
        .pending, .not_found => try std.testing.expect(false), // Should match
    }

    // Global mapping still exists
    const global_entry = try mgr.get(.normal, "H", null);
    try std.testing.expect(global_entry != null);
    switch (global_entry.?.rhs) {
        .keys => |k| try std.testing.expectEqualStrings("global_cmd", k),
        .callback => try std.testing.expect(false),
    }
}

test "KeymapManager: fallback to global when no buffer-local exists" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Set only global mapping: K -> global_cmd
    const global_keys = try allocator.dupe(u8, "global_cmd");
    try mgr.set(.normal, "K", .{ .keys = global_keys }, .{}, null);

    // Lookup should fallback to global mapping
    const result = try mgr.lookup(.normal, "K", 0);
    switch (result) {
        .matched => |entry| {
            try std.testing.expect(entry.buffer_id == null); // Global
            switch (entry.rhs) {
                .keys => |k| try std.testing.expectEqualStrings("global_cmd", k),
                .callback => try std.testing.expect(false),
            }
        },
        .pending, .not_found => try std.testing.expect(false), // Should match
    }
}

test "KeymapManager: hasPrefix detects ambiguous mappings (j vs jk)" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Map jk → gg (longer mapping)
    const keys = try allocator.dupe(u8, "gg");
    try mgr.set(.normal, "jk", .{ .keys = keys }, .{}, null);

    // "j" alone is NOT a full mapping, but IS a prefix of "jk"
    const result_j = try mgr.lookup(.normal, "j", 0);
    switch (result_j) {
        .pending => {}, // Expected - "j" is prefix of "jk"
        .matched, .not_found => try std.testing.expect(false), // Should be pending
    }

    const has_partial = mgr.hasPrefix(.normal, "j", 0);
    try std.testing.expect(has_partial == true); // "j" is prefix of "jk"

    // Clear pending state before next lookup (stateful accumulation)
    mgr.clearPending();

    // "jk" is a complete mapping, not a prefix of anything longer
    const result_jk = try mgr.lookup(.normal, "jk", 0);
    switch (result_jk) {
        .matched => |entry| {
            switch (entry.rhs) {
                .keys => |k| try std.testing.expectEqualStrings("gg", k),
                .callback => try std.testing.expect(false),
            }
        },
        .pending, .not_found => try std.testing.expect(false), // Should match
    }

    const has_partial_jk = mgr.hasPrefix(.normal, "jk", 0);
    try std.testing.expect(has_partial_jk == false); // "jk" is NOT a prefix (it's complete)
}

test "KeymapManager: hasPrefix returns false when no longer mappings exist" {
    const allocator = std.testing.allocator;
    var mgr = KeymapManager.init(allocator);
    defer mgr.deinit();

    // Map only j → k (single char, no ambiguity)
    const keys = try allocator.dupe(u8, "k");
    try mgr.set(.normal, "j", .{ .keys = keys }, .{}, null);

    // "j" is a complete mapping, NOT a prefix
    const has_partial = mgr.hasPrefix(.normal, "j", 0);
    try std.testing.expect(has_partial == false);
}
