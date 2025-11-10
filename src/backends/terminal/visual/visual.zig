const std = @import("std");

/// Position in buffer (line, column)
pub const Position = struct {
    line: usize,
    col: usize,

    pub fn equals(self: Position, other: Position) bool {
        return self.line == other.line and self.col == other.col;
    }

    pub fn lessThan(self: Position, other: Position) bool {
        if (self.line < other.line) return true;
        if (self.line > other.line) return false;
        return self.col < other.col;
    }
};

/// Visual mode types (Neovim-compatible)
pub const VisualMode = enum {
    char, // 'v' - character-wise selection
    line, // 'V' - line-wise selection
    block, // Ctrl-V - block-wise (rectangular) selection

    pub fn toString(self: VisualMode) []const u8 {
        return switch (self) {
            .char => "VISUAL",
            .line => "VISUAL LINE",
            .block => "VISUAL BLOCK",
        };
    }
};

/// Visual mode state
/// Tracks the selection from anchor point to cursor
pub const VisualState = struct {
    active: bool = false,
    mode: VisualMode = .char,
    anchor: Position, // Start of selection (doesn't move with cursor)

    /// Initialize visual state at given position
    pub fn init(start_pos: Position, visual_mode: VisualMode) VisualState {
        return .{
            .active = true,
            .mode = visual_mode,
            .anchor = start_pos,
        };
    }

    /// Get normalized selection range (start always < end)
    pub fn getRange(self: VisualState, cursor: Position) struct {
        start: Position,
        end: Position,
    } {
        // Normalize so start is always before end
        if (self.anchor.lessThan(cursor)) {
            return .{ .start = self.anchor, .end = cursor };
        } else {
            return .{ .start = cursor, .end = self.anchor };
        }
    }

    /// Check if position is within visual selection
    pub fn contains(self: VisualState, cursor: Position, pos: Position) bool {
        const range = self.getRange(cursor);

        switch (self.mode) {
            .char => {
                // Character-wise: check if position is between start and end
                if (pos.line < range.start.line or pos.line > range.end.line) {
                    return false;
                }
                if (pos.line == range.start.line and pos.col < range.start.col) {
                    return false;
                }
                if (pos.line == range.end.line and pos.col > range.end.col) {
                    return false;
                }
                return true;
            },
            .line => {
                // Line-wise: entire lines are selected
                return pos.line >= range.start.line and pos.line <= range.end.line;
            },
            .block => {
                // Block-wise: rectangular selection
                // (Note: actual implementation needs virtual column calculation)
                return pos.line >= range.start.line and
                    pos.line <= range.end.line and
                    pos.col >= range.start.col and
                    pos.col <= range.end.col;
            },
        }
    }

    /// Deactivate visual mode
    pub fn deactivate(self: *VisualState) void {
        self.active = false;
    }
};

// Tests
test "Visual: initialize character mode" {
    const pos = Position{ .line = 5, .col = 10 };
    const vs = VisualState.init(pos, .char);

    try std.testing.expect(vs.active);
    try std.testing.expectEqual(VisualMode.char, vs.mode);
    try std.testing.expect(vs.anchor.equals(pos));
}

test "Visual: get range (forward selection)" {
    const vs = VisualState.init(.{ .line = 0, .col = 5 }, .char);
    const cursor = Position{ .line = 0, .col = 10 };

    const range = vs.getRange(cursor);
    try std.testing.expectEqual(@as(usize, 5), range.start.col);
    try std.testing.expectEqual(@as(usize, 10), range.end.col);
}

test "Visual: get range (backward selection)" {
    const vs = VisualState.init(.{ .line = 0, .col = 10 }, .char);
    const cursor = Position{ .line = 0, .col = 5 };

    const range = vs.getRange(cursor);
    try std.testing.expectEqual(@as(usize, 5), range.start.col);
    try std.testing.expectEqual(@as(usize, 10), range.end.col);
}

test "Visual: contains (character-wise)" {
    const vs = VisualState.init(.{ .line = 0, .col = 5 }, .char);
    const cursor = Position{ .line = 0, .col = 10 };

    try std.testing.expect(vs.contains(cursor, .{ .line = 0, .col = 7 }));
    try std.testing.expect(!vs.contains(cursor, .{ .line = 0, .col = 3 }));
    try std.testing.expect(!vs.contains(cursor, .{ .line = 0, .col = 12 }));
}

test "Visual: contains (line-wise)" {
    const vs = VisualState.init(.{ .line = 2, .col = 0 }, .line);
    const cursor = Position{ .line = 5, .col = 0 };

    try std.testing.expect(vs.contains(cursor, .{ .line = 3, .col = 10 }));
    try std.testing.expect(vs.contains(cursor, .{ .line = 2, .col = 0 }));
    try std.testing.expect(vs.contains(cursor, .{ .line = 5, .col = 20 }));
    try std.testing.expect(!vs.contains(cursor, .{ .line = 1, .col = 0 }));
    try std.testing.expect(!vs.contains(cursor, .{ .line = 6, .col = 0 }));
}

test "Visual: mode to string" {
    try std.testing.expectEqualStrings("VISUAL", VisualMode.char.toString());
    try std.testing.expectEqualStrings("VISUAL LINE", VisualMode.line.toString());
    try std.testing.expectEqualStrings("VISUAL BLOCK", VisualMode.block.toString());
}

test "Visual: deactivate" {
    var vs = VisualState.init(.{ .line = 0, .col = 0 }, .char);
    try std.testing.expect(vs.active);

    vs.deactivate();
    try std.testing.expect(!vs.active);
}
