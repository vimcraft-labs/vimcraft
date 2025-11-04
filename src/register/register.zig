const std = @import("std");

/// Motion type for yanked text (affects paste behavior)
pub const MotionType = enum {
    char_wise,  // Character-wise: 'v' or 'yw'
    line_wise,  // Line-wise: 'V' or 'yy'
    block_wise, // Block-wise: Ctrl-V

    pub fn toString(self: MotionType) []const u8 {
        return switch (self) {
            .char_wise => "char",
            .line_wise => "line",
            .block_wise => "block",
        };
    }
};

/// Register content (yanked/deleted text)
pub const YankReg = struct {
    lines: std.ArrayList([]const u8),
    motion_type: MotionType,
    width: usize, // For block_wise only (rectangle width)
    timestamp: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) YankReg {
        return .{
            .lines = .empty,
            .motion_type = .char_wise,
            .width = 0,
            .timestamp = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *YankReg) void {
        // Free all line strings
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
    }

    /// Check if register is empty
    pub fn isEmpty(self: *const YankReg) bool {
        return self.lines.items.len == 0;
    }

    /// Clear register contents
    pub fn clear(self: *YankReg) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        self.width = 0;
    }

    /// Set register contents
    pub fn set(
        self: *YankReg,
        text_lines: []const []const u8,
        mtype: MotionType,
    ) !void {
        self.clear();
        self.motion_type = mtype;
        self.timestamp = std.time.milliTimestamp();

        for (text_lines) |line| {
            const owned = try self.allocator.dupe(u8, line);
            try self.lines.append(self.allocator, owned);
        }
    }

    /// Get text as single string (with newlines)
    pub fn getText(self: *const YankReg, allocator: std.mem.Allocator) ![]const u8 {
        if (self.isEmpty()) return allocator.dupe(u8, "");

        var total_len: usize = 0;
        for (self.lines.items) |line| {
            total_len += line.len + 1; // +1 for newline
        }

        var result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        for (self.lines.items) |line| {
            @memcpy(result[pos .. pos + line.len], line);
            pos += line.len;
            result[pos] = '\n';
            pos += 1;
        }

        return result;
    }
};

/// Register Manager - manages all 39 Neovim registers
pub const RegisterManager = struct {
    registers: [39]YankReg,
    allocator: std.mem.Allocator,

    // Register indices (Neovim-compatible)
    // 0       = unnamed register (last yank/delete)
    // 1-9     = numbered registers (delete history, 1=most recent)
    // 10-35   = named registers (a-z)
    // 36      = small delete register (-)
    // 37      = primary selection (*)
    // 38      = clipboard (+)

    pub const UNNAMED = 0;
    pub const NUMBERED_START = 1;
    pub const NUMBERED_END = 9;
    pub const NAMED_START = 10;
    pub const NAMED_END = 35;
    pub const SMALL_DELETE = 36;
    pub const PRIMARY_SELECTION = 37;
    pub const CLIPBOARD = 38;

    pub fn init(allocator: std.mem.Allocator) RegisterManager {
        var rm: RegisterManager = .{
            .registers = undefined,
            .allocator = allocator,
        };

        // Initialize all registers
        for (&rm.registers) |*reg| {
            reg.* = YankReg.init(allocator);
        }

        return rm;
    }

    pub fn deinit(self: *RegisterManager) void {
        for (&self.registers) |*reg| {
            reg.deinit();
        }
    }

    /// Convert register character to index
    pub fn charToIndex(c: u8) ?usize {
        return switch (c) {
            '"' => UNNAMED, // Unnamed register
            '0'...'9' => |d| d - '0', // Numbered: 0-9
            'a'...'z' => |ch| NAMED_START + (ch - 'a'), // Named: a-z → 10-35
            'A'...'Z' => |ch| NAMED_START + (ch - 'A'), // Uppercase maps to same as lowercase
            '-' => SMALL_DELETE, // Small delete
            '*' => PRIMARY_SELECTION, // Primary selection
            '+' => CLIPBOARD, // Clipboard
            else => null,
        };
    }

    /// Convert register index to character
    pub fn indexToChar(idx: usize) u8 {
        return switch (idx) {
            UNNAMED => '"',
            NUMBERED_START...NUMBERED_END => @as(u8, @intCast(idx + '0')),
            NAMED_START...NAMED_END => @as(u8, @intCast(idx - NAMED_START + 'a')),
            SMALL_DELETE => '-',
            PRIMARY_SELECTION => '*',
            CLIPBOARD => '+',
            else => '?',
        };
    }

    /// Check if register name indicates append mode (uppercase)
    pub fn isAppendRegister(c: u8) bool {
        return c >= 'A' and c <= 'Z';
    }

    /// Get register by name
    pub fn get(self: *RegisterManager, name: u8) ?*YankReg {
        const idx = charToIndex(name) orelse return null;
        if (idx >= 39) return null;
        return &self.registers[idx];
    }

    /// Set register contents
    pub fn setRegister(
        self: *RegisterManager,
        name: u8,
        text_lines: []const []const u8,
        mtype: MotionType,
    ) !void {
        const reg = self.get(name) orelse return error.InvalidRegister;
        try reg.set(text_lines, mtype);
    }

    /// Yank text to register
    pub fn yank(
        self: *RegisterManager,
        regname: u8,
        text_lines: []const []const u8,
        mtype: MotionType,
    ) !void {
        // Handle append mode (uppercase registers)
        if (isAppendRegister(regname)) {
            const lowercase = regname + ('a' - 'A');
            const reg = self.get(lowercase) orelse return error.InvalidRegister;

            // Append to existing contents
            for (text_lines) |line| {
                const owned = try self.allocator.dupe(u8, line);
                try reg.lines.append(self.allocator, owned);
            }
            reg.timestamp = std.time.milliTimestamp();
        } else {
            // Normal yank (replace contents)
            try self.setRegister(regname, text_lines, mtype);

            // Also update unnamed register (unless yanking to unnamed)
            if (regname != '"') {
                try self.setRegister('"', text_lines, mtype);
            }
        }
    }

    /// Rotate numbered registers (for delete history)
    pub fn rotateNumbered(self: *RegisterManager) !void {
        // Shift 1→2, 2→3, ..., 8→9
        // Register 9 contents are discarded
        var i: usize = NUMBERED_END;
        while (i > NUMBERED_START) : (i -= 1) {
            const src = &self.registers[i - 1];
            const dst = &self.registers[i];

            // Clear destination
            dst.clear();

            // Copy source to destination
            for (src.lines.items) |line| {
                const copy = try self.allocator.dupe(u8, line);
                try dst.lines.append(self.allocator, copy);
            }
            dst.motion_type = src.motion_type;
            dst.width = src.width;
            dst.timestamp = src.timestamp;
        }

        // Clear register 1 (will be filled with next delete)
        self.registers[NUMBERED_START].clear();
    }
};

// Tests
test "Register: init and deinit" {
    const allocator = std.testing.allocator;
    var rm = RegisterManager.init(allocator);
    defer rm.deinit();

    try std.testing.expect(rm.registers[0].isEmpty());
}

test "Register: char to index conversion" {
    try std.testing.expectEqual(@as(?usize, 0), RegisterManager.charToIndex('"'));
    try std.testing.expectEqual(@as(?usize, 1), RegisterManager.charToIndex('1'));
    try std.testing.expectEqual(@as(?usize, 9), RegisterManager.charToIndex('9'));
    try std.testing.expectEqual(@as(?usize, 10), RegisterManager.charToIndex('a'));
    try std.testing.expectEqual(@as(?usize, 35), RegisterManager.charToIndex('z'));
    try std.testing.expectEqual(@as(?usize, 10), RegisterManager.charToIndex('A')); // Same as 'a'
    try std.testing.expectEqual(@as(?usize, 36), RegisterManager.charToIndex('-'));
    try std.testing.expectEqual(@as(?usize, 37), RegisterManager.charToIndex('*'));
    try std.testing.expectEqual(@as(?usize, 38), RegisterManager.charToIndex('+'));
    try std.testing.expectEqual(@as(?usize, null), RegisterManager.charToIndex('?'));
}

test "Register: index to char conversion" {
    try std.testing.expectEqual(@as(u8, '"'), RegisterManager.indexToChar(0));
    try std.testing.expectEqual(@as(u8, '1'), RegisterManager.indexToChar(1));
    try std.testing.expectEqual(@as(u8, 'a'), RegisterManager.indexToChar(10));
    try std.testing.expectEqual(@as(u8, 'z'), RegisterManager.indexToChar(35));
    try std.testing.expectEqual(@as(u8, '-'), RegisterManager.indexToChar(36));
    try std.testing.expectEqual(@as(u8, '*'), RegisterManager.indexToChar(37));
    try std.testing.expectEqual(@as(u8, '+'), RegisterManager.indexToChar(38));
}

test "Register: is append register" {
    try std.testing.expect(RegisterManager.isAppendRegister('A'));
    try std.testing.expect(RegisterManager.isAppendRegister('Z'));
    try std.testing.expect(!RegisterManager.isAppendRegister('a'));
    try std.testing.expect(!RegisterManager.isAppendRegister('"'));
}

test "Register: set and get" {
    const allocator = std.testing.allocator;
    var rm = RegisterManager.init(allocator);
    defer rm.deinit();

    const text = [_][]const u8{"Hello World"};
    try rm.setRegister('"', &text, .char_wise);

    const reg = rm.get('"').?;
    try std.testing.expect(!reg.isEmpty());
    try std.testing.expectEqual(@as(usize, 1), reg.lines.items.len);
    try std.testing.expectEqualStrings("Hello World", reg.lines.items[0]);
    try std.testing.expectEqual(MotionType.char_wise, reg.motion_type);
}

test "Register: yank updates unnamed" {
    const allocator = std.testing.allocator;
    var rm = RegisterManager.init(allocator);
    defer rm.deinit();

    const text = [_][]const u8{"Test"};
    try rm.yank('a', &text, .line_wise);

    // Check register 'a'
    const reg_a = rm.get('a').?;
    try std.testing.expectEqualStrings("Test", reg_a.lines.items[0]);

    // Check unnamed register also updated
    const reg_unnamed = rm.get('"').?;
    try std.testing.expectEqualStrings("Test", reg_unnamed.lines.items[0]);
}

test "Register: append mode" {
    const allocator = std.testing.allocator;
    var rm = RegisterManager.init(allocator);
    defer rm.deinit();

    const text1 = [_][]const u8{"Line 1"};
    const text2 = [_][]const u8{"Line 2"};

    try rm.yank('a', &text1, .line_wise);
    try rm.yank('A', &text2, .line_wise); // Uppercase = append

    const reg_a = rm.get('a').?;
    try std.testing.expectEqual(@as(usize, 2), reg_a.lines.items.len);
    try std.testing.expectEqualStrings("Line 1", reg_a.lines.items[0]);
    try std.testing.expectEqualStrings("Line 2", reg_a.lines.items[1]);
}

test "Register: rotate numbered registers" {
    const allocator = std.testing.allocator;
    var rm = RegisterManager.init(allocator);
    defer rm.deinit();

    // Put text in register 1
    const text = [_][]const u8{"Deleted text"};
    try rm.setRegister('1', &text, .line_wise);

    // Rotate
    try rm.rotateNumbered();

    // Register 1 should be empty now, register 2 should have the text
    try std.testing.expect(rm.registers[1].isEmpty());
    try std.testing.expectEqualStrings("Deleted text", rm.registers[2].lines.items[0]);
}

test "Register: clear" {
    const allocator = std.testing.allocator;
    var rm = RegisterManager.init(allocator);
    defer rm.deinit();

    const text = [_][]const u8{"Test"};
    try rm.setRegister('"', &text, .char_wise);

    const reg = rm.get('"').?;
    try std.testing.expect(!reg.isEmpty());

    reg.clear();
    try std.testing.expect(reg.isEmpty());
}
