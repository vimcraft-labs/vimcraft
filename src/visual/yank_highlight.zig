const std = @import("std");
const Position = @import("visual.zig").Position;
const VisualMode = @import("visual.zig").VisualMode;

/// Yank highlight state - shows briefly after yanking
/// Provides visual feedback to confirm what was yanked
pub const YankHighlight = struct {
    active: bool = false,
    mode: VisualMode = .char,
    start: Position = .{ .line = 0, .col = 0 },
    end: Position = .{ .line = 0, .col = 0 },
    timestamp_ms: i64 = 0,

    /// Initialize yank highlight for a region
    pub fn init(start_pos: Position, end_pos: Position, mode: VisualMode) YankHighlight {
        // Normalize so start is always before end
        var start = start_pos;
        var end = end_pos;

        if (!start_pos.lessThan(end_pos)) {
            start = end_pos;
            end = start_pos;
        }

        return .{
            .active = true,
            .mode = mode,
            .start = start,
            .end = end,
            .timestamp_ms = std.time.milliTimestamp(),
        };
    }

    /// Check if highlight should still be visible
    /// Highlights last for 250ms
    pub fn isVisible(self: *const YankHighlight) bool {
        if (!self.active) return false;

        const now = std.time.milliTimestamp();
        const elapsed = now - self.timestamp_ms;
        return elapsed < 250; // 250ms highlight duration
    }

    /// Deactivate highlight
    pub fn deactivate(self: *YankHighlight) void {
        self.active = false;
    }

    /// Check if position is within yank highlight
    pub fn contains(self: *const YankHighlight, pos: Position) bool {
        if (!self.active) return false;

        switch (self.mode) {
            .char => {
                // Character-wise: check if position is between start and end
                if (pos.line < self.start.line or pos.line > self.end.line) {
                    return false;
                }
                if (pos.line == self.start.line and pos.col < self.start.col) {
                    return false;
                }
                if (pos.line == self.end.line and pos.col > self.end.col) {
                    return false;
                }
                return true;
            },
            .line => {
                // Line-wise: entire lines are highlighted
                return pos.line >= self.start.line and pos.line <= self.end.line;
            },
            .block => {
                // Block-wise: rectangular highlight
                return pos.line >= self.start.line and
                    pos.line <= self.end.line and
                    pos.col >= self.start.col and
                    pos.col <= self.end.col;
            },
        }
    }
};

// Tests
test "YankHighlight: initialize" {
    const start = Position{ .line = 0, .col = 5 };
    const end = Position{ .line = 0, .col = 10 };
    const yh = YankHighlight.init(start, end, .char);

    try std.testing.expect(yh.active);
    try std.testing.expectEqual(@as(usize, 5), yh.start.col);
    try std.testing.expectEqual(@as(usize, 10), yh.end.col);
}

test "YankHighlight: normalize positions" {
    // Start > end should be swapped
    const start = Position{ .line = 0, .col = 10 };
    const end = Position{ .line = 0, .col = 5 };
    const yh = YankHighlight.init(start, end, .char);

    try std.testing.expectEqual(@as(usize, 5), yh.start.col);
    try std.testing.expectEqual(@as(usize, 10), yh.end.col);
}

test "YankHighlight: contains (character-wise)" {
    const yh = YankHighlight.init(
        .{ .line = 0, .col = 5 },
        .{ .line = 0, .col = 10 },
        .char,
    );

    try std.testing.expect(yh.contains(.{ .line = 0, .col = 7 }));
    try std.testing.expect(!yh.contains(.{ .line = 0, .col = 3 }));
    try std.testing.expect(!yh.contains(.{ .line = 0, .col = 12 }));
}

test "YankHighlight: contains (line-wise)" {
    const yh = YankHighlight.init(
        .{ .line = 2, .col = 0 },
        .{ .line = 5, .col = 0 },
        .line,
    );

    try std.testing.expect(yh.contains(.{ .line = 3, .col = 10 }));
    try std.testing.expect(yh.contains(.{ .line = 2, .col = 0 }));
    try std.testing.expect(yh.contains(.{ .line = 5, .col = 20 }));
    try std.testing.expect(!yh.contains(.{ .line = 1, .col = 0 }));
    try std.testing.expect(!yh.contains(.{ .line = 6, .col = 0 }));
}

test "YankHighlight: deactivate" {
    var yh = YankHighlight.init(
        .{ .line = 0, .col = 0 },
        .{ .line = 0, .col = 5 },
        .char,
    );

    try std.testing.expect(yh.active);
    yh.deactivate();
    try std.testing.expect(!yh.active);
    try std.testing.expect(!yh.contains(.{ .line = 0, .col = 2 }));
}
