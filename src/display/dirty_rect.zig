const std = @import("std");

/// Dirty rectangle for tracking changed regions
/// Used for incremental rendering optimization
pub const DirtyRect = struct {
    row: usize,
    col: usize,
    height: usize,
    width: usize,

    /// Create a dirty rect from a single cell
    pub fn fromCell(row: usize, col: usize) DirtyRect {
        return .{
            .row = row,
            .col = col,
            .height = 1,
            .width = 1,
        };
    }

    /// Expand to include another cell
    pub fn expand(self: *DirtyRect, row: usize, col: usize) void {
        const min_row = @min(self.row, row);
        const min_col = @min(self.col, col);
        const max_row = @max(self.row + self.height - 1, row);
        const max_col = @max(self.col + self.width - 1, col);

        self.row = min_row;
        self.col = min_col;
        self.height = max_row - min_row + 1;
        self.width = max_col - min_col + 1;
    }

    /// Check if rect contains a cell
    pub fn contains(self: DirtyRect, row: usize, col: usize) bool {
        return row >= self.row and
            row < self.row + self.height and
            col >= self.col and
            col < self.col + self.width;
    }

    /// Merge with another dirty rect (returns minimum bounding box)
    pub fn merge(self: DirtyRect, other: DirtyRect) DirtyRect {
        const min_row = @min(self.row, other.row);
        const min_col = @min(self.col, other.col);
        const max_row = @max(self.row + self.height - 1, other.row + other.height - 1);
        const max_col = @max(self.col + self.width - 1, other.col + other.width - 1);

        return .{
            .row = min_row,
            .col = min_col,
            .height = max_row - min_row + 1,
            .width = max_col - min_col + 1,
        };
    }

    /// Check if two rects overlap
    pub fn overlaps(self: DirtyRect, other: DirtyRect) bool {
        return !(self.row + self.height <= other.row or
            other.row + other.height <= self.row or
            self.col + self.width <= other.col or
            other.col + other.width <= self.col);
    }

    /// Calculate area (for optimization decisions)
    pub fn area(self: DirtyRect) usize {
        return self.height * self.width;
    }
};

/// Dirty rectangle tracker for a layer
/// Tracks which regions of a layer have changed
pub const DirtyRectTracker = struct {
    /// List of dirty rectangles
    rects: std.ArrayList(DirtyRect),

    /// Allocator
    allocator: std.mem.Allocator,

    /// Is the entire layer dirty?
    full_dirty: bool,

    /// Initialize tracker
    pub fn init(allocator: std.mem.Allocator) DirtyRectTracker {
        return .{
            .rects = .empty,
            .allocator = allocator,
            .full_dirty = false,
        };
    }

    /// Deinitialize tracker
    pub fn deinit(self: *DirtyRectTracker) void {
        self.rects.deinit(self.allocator);
    }

    /// Mark entire layer as dirty
    pub fn markFullDirty(self: *DirtyRectTracker) void {
        self.full_dirty = true;
        self.rects.clearRetainingCapacity();
    }

    /// Mark a cell as dirty
    pub fn markCell(self: *DirtyRectTracker, row: usize, col: usize) !void {
        if (self.full_dirty) return; // Already fully dirty

        // Try to extend an existing rect
        for (self.rects.items) |*rect| {
            // If cell is adjacent to this rect, expand it
            const adjacent_horiz = (row >= rect.row and row <= rect.row + rect.height) and
                (col >= rect.col and col <= rect.col + rect.width + 1);
            const adjacent_vert = (col >= rect.col and col <= rect.col + rect.width) and
                (row >= rect.row and row <= rect.row + rect.height + 1);

            if (adjacent_horiz or adjacent_vert) {
                rect.expand(row, col);
                return;
            }
        }

        // Create new rect
        try self.rects.append(self.allocator, DirtyRect.fromCell(row, col));
    }

    /// Mark a rectangle as dirty
    pub fn markRect(self: *DirtyRectTracker, rect: DirtyRect) !void {
        if (self.full_dirty) return;

        // Try to merge with existing rects
        var merged = false;
        for (self.rects.items) |*existing| {
            if (existing.overlaps(rect)) {
                existing.* = existing.merge(rect);
                merged = true;
                break;
            }
        }

        if (!merged) {
            try self.rects.append(self.allocator, rect);
        }
    }

    /// Clear all dirty rects
    pub fn clear(self: *DirtyRectTracker) void {
        self.rects.clearRetainingCapacity();
        self.full_dirty = false;
    }

    /// Check if tracker has any dirty regions
    pub fn hasDirty(self: *DirtyRectTracker) bool {
        return self.full_dirty or self.rects.items.len > 0;
    }

    /// Get dirty rectangles (for rendering)
    pub fn getDirtyRects(self: *DirtyRectTracker) []const DirtyRect {
        return self.rects.items;
    }

    /// Optimize rects (merge overlapping, remove redundant)
    pub fn optimize(self: *DirtyRectTracker) !void {
        if (self.full_dirty or self.rects.items.len <= 1) return;

        // Simple optimization: merge overlapping rects
        var i: usize = 0;
        while (i < self.rects.items.len) {
            var j: usize = i + 1;
            while (j < self.rects.items.len) {
                if (self.rects.items[i].overlaps(self.rects.items[j])) {
                    // Merge j into i
                    self.rects.items[i] = self.rects.items[i].merge(self.rects.items[j]);
                    // Remove j
                    _ = self.rects.orderedRemove(j);
                    // Don't increment j, check same position again
                } else {
                    j += 1;
                }
            }
            i += 1;
        }

        // If we have too many rects, just mark full dirty (optimization threshold)
        if (self.rects.items.len > 10) {
            self.markFullDirty();
        }
    }
};

// Tests
test "DirtyRect basic operations" {
    const allocator = std.testing.allocator;

    var rect = DirtyRect.fromCell(5, 10);
    try std.testing.expectEqual(@as(usize, 5), rect.row);
    try std.testing.expectEqual(@as(usize, 10), rect.col);
    try std.testing.expectEqual(@as(usize, 1), rect.height);
    try std.testing.expectEqual(@as(usize, 1), rect.width);

    // Expand to include adjacent cell
    rect.expand(5, 11);
    try std.testing.expectEqual(@as(usize, 2), rect.width);

    // Check contains
    try std.testing.expect(rect.contains(5, 10));
    try std.testing.expect(rect.contains(5, 11));
    try std.testing.expect(!rect.contains(6, 10));

    _ = allocator;
}

test "DirtyRectTracker operations" {
    const allocator = std.testing.allocator;

    var tracker = DirtyRectTracker.init(allocator);
    defer tracker.deinit();

    // Mark some cells
    try tracker.markCell(5, 10);
    try tracker.markCell(5, 11);
    try tracker.markCell(6, 10);

    try std.testing.expect(tracker.hasDirty());

    // Clear
    tracker.clear();
    try std.testing.expect(!tracker.hasDirty());

    // Test full dirty
    tracker.markFullDirty();
    try std.testing.expect(tracker.hasDirty());
    try std.testing.expect(tracker.full_dirty);
}

test "DirtyRect merge and overlap" {
    const rect1 = DirtyRect{ .row = 0, .col = 0, .height = 5, .width = 5 };
    const rect2 = DirtyRect{ .row = 3, .col = 3, .height = 5, .width = 5 };

    // Should overlap
    try std.testing.expect(rect1.overlaps(rect2));
    try std.testing.expect(rect2.overlaps(rect1));

    // Merge should create bounding box
    const merged = rect1.merge(rect2);
    try std.testing.expectEqual(@as(usize, 0), merged.row);
    try std.testing.expectEqual(@as(usize, 0), merged.col);
    try std.testing.expectEqual(@as(usize, 8), merged.height); // 0 to 7
    try std.testing.expectEqual(@as(usize, 8), merged.width); // 0 to 7

    // Non-overlapping rects
    const rect3 = DirtyRect{ .row = 10, .col = 10, .height = 2, .width = 2 };
    try std.testing.expect(!rect1.overlaps(rect3));
}
