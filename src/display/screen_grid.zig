const std = @import("std");
const highlights = @import("../config/highlights.zig");

/// A single cell in the terminal grid
pub const Cell = struct {
    char: u21, // Unicode codepoint
    fg: ?highlights.Color = null,
    bg: ?highlights.Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,

    /// Check if two cells are equal (for diffing)
    pub fn eql(self: Cell, other: Cell) bool {
        if (self.char != other.char) return false;
        if (self.bold != other.bold) return false;
        if (self.italic != other.italic) return false;
        if (self.underline != other.underline) return false;

        // Compare colors (handle null cases)
        if (self.fg == null and other.fg != null) return false;
        if (self.fg != null and other.fg == null) return false;
        if (self.fg) |fg| {
            if (other.fg) |other_fg| {
                if (fg.r != other_fg.r or fg.g != other_fg.g or fg.b != other_fg.b) return false;
            }
        }

        if (self.bg == null and other.bg != null) return false;
        if (self.bg != null and other.bg == null) return false;
        if (self.bg) |bg| {
            if (other.bg) |other_bg| {
                if (bg.r != other_bg.r or bg.g != other_bg.g or bg.b != other_bg.b) return false;
            }
        }

        return true;
    }

    /// Create a blank cell (space with no attributes)
    pub fn blank() Cell {
        return .{ .char = ' ' };
    }

    /// Reset cell to blank state
    pub fn reset(self: *Cell) void {
        self.* = Cell.blank();
    }
};

/// Represents a changed cell position and its new content
pub const Update = struct {
    row: usize,
    col: usize,
    cell: Cell,
};

/// Grid-based screen buffer (Neovim-style 2D array)
pub const ScreenGrid = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,

    // Double buffering: current and previous frame
    current: [][]Cell,
    previous: [][]Cell,

    // Track which lines have changed
    dirty_lines: std.DynamicBitSet,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !ScreenGrid {
        // Allocate current buffer
        const current = try allocator.alloc([]Cell, height);
        for (current) |*row| {
            row.* = try allocator.alloc(Cell, width);
            for (row.*) |*cell| {
                cell.* = Cell.blank();
            }
        }

        // Allocate previous buffer
        const previous = try allocator.alloc([]Cell, height);
        for (previous) |*row| {
            row.* = try allocator.alloc(Cell, width);
            for (row.*) |*cell| {
                cell.* = Cell.blank();
            }
        }

        // Initialize dirty tracking
        var dirty_lines = try std.DynamicBitSet.initEmpty(allocator, height);
        dirty_lines.setRangeValue(.{ .start = 0, .end = height }, true); // All dirty initially

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .current = current,
            .previous = previous,
            .dirty_lines = dirty_lines,
        };
    }

    pub fn deinit(self: *ScreenGrid) void {
        // Free current buffer
        for (self.current) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.current);

        // Free previous buffer
        for (self.previous) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.previous);

        // Free dirty tracking
        self.dirty_lines.deinit();
    }

    /// Resize the grid (reallocate buffers)
    pub fn resize(self: *ScreenGrid, new_width: usize, new_height: usize) !void {
        // Free old buffers
        for (self.current) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.current);

        for (self.previous) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.previous);

        self.dirty_lines.deinit();

        // Allocate new buffers
        self.width = new_width;
        self.height = new_height;

        self.current = try self.allocator.alloc([]Cell, new_height);
        for (self.current) |*row| {
            row.* = try self.allocator.alloc(Cell, new_width);
            for (row.*) |*cell| {
                cell.* = Cell.blank();
            }
        }

        self.previous = try self.allocator.alloc([]Cell, new_height);
        for (self.previous) |*row| {
            row.* = try self.allocator.alloc(Cell, new_width);
            for (row.*) |*cell| {
                cell.* = Cell.blank();
            }
        }

        self.dirty_lines = try std.DynamicBitSet.initEmpty(self.allocator, new_height);
        self.dirty_lines.setRangeValue(.{ .start = 0, .end = new_height }, true);
    }

    /// Set a cell in the current buffer
    pub fn setCell(self: *ScreenGrid, row: usize, col: usize, cell: Cell) void {
        if (row >= self.height or col >= self.width) return;
        self.current[row][col] = cell;
        self.dirty_lines.set(row);
    }

    /// Get a cell from the current buffer
    pub fn getCell(self: *ScreenGrid, row: usize, col: usize) ?Cell {
        if (row >= self.height or col >= self.width) return null;
        return self.current[row][col];
    }

    /// Mark a line as dirty (needs redraw)
    pub fn markDirty(self: *ScreenGrid, row: usize) void {
        if (row < self.height) {
            self.dirty_lines.set(row);
        }
    }

    /// Clear the entire grid
    pub fn clear(self: *ScreenGrid) void {
        for (self.current, 0..) |row, r| {
            for (row, 0..) |*cell, c| {
                cell.reset();
                self.dirty_lines.set(r);
                _ = c;
            }
        }
    }

    /// Compare current vs previous buffer and return list of changes
    /// This is the core diff algorithm (inspired by both Neovim and Helix)
    pub fn diff(self: *ScreenGrid, allocator: std.mem.Allocator) ![]Update {
        var updates = std.ArrayList(Update).init(allocator);

        // Only check dirty lines (Neovim optimization)
        var iter = self.dirty_lines.iterator(.{});
        while (iter.next()) |row| {
            // Compare each cell in this row
            for (0..self.width) |col| {
                const current_cell = self.current[row][col];
                const previous_cell = self.previous[row][col];

                if (!current_cell.eql(previous_cell)) {
                    try updates.append(.{
                        .row = row,
                        .col = col,
                        .cell = current_cell,
                    });
                }
            }
        }

        return updates.toOwnedSlice();
    }

    /// Swap current and previous buffers after rendering
    /// (Previous becomes current for next frame comparison)
    pub fn swapBuffers(self: *ScreenGrid) void {
        // Copy current to previous
        for (self.current, 0..) |row, r| {
            for (row, 0..) |cell, c| {
                self.previous[r][c] = cell;
            }
        }

        // Clear dirty flags
        self.dirty_lines.setRangeValue(.{ .start = 0, .end = self.height }, false);
    }

    /// Fill a rectangular region with a cell
    pub fn fillRect(self: *ScreenGrid, start_row: usize, start_col: usize, end_row: usize, end_col: usize, cell: Cell) void {
        const r_start = @min(start_row, self.height);
        const r_end = @min(end_row, self.height);
        const c_start = @min(start_col, self.width);
        const c_end = @min(end_col, self.width);

        for (r_start..r_end) |row| {
            for (c_start..c_end) |col| {
                self.current[row][col] = cell;
            }
            self.dirty_lines.set(row);
        }
    }

    /// Set a string at a specific position (for rendering text)
    /// Returns the column position after the last character written
    pub fn setString(self: *ScreenGrid, row: usize, col: usize, text: []const u8, fg: ?highlights.Color, bg: ?highlights.Color) usize {
        if (row >= self.height) return col;

        var current_col = col;
        var i: usize = 0;
        while (i < text.len) {
            if (current_col >= self.width) break;

            const char_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            if (i + char_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i..][0..char_len]) catch ' ';

            self.current[row][current_col] = .{
                .char = codepoint,
                .fg = fg,
                .bg = bg,
            };

            current_col += 1;
            i += char_len;
        }

        self.dirty_lines.set(row);
        return current_col; // Return ending column
    }
};

// Tests
test "Cell: equality" {
    const c1 = Cell{ .char = 'a' };
    const c2 = Cell{ .char = 'a' };
    const c3 = Cell{ .char = 'b' };

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
}

test "Cell: with colors" {
    const red = highlights.Color{ .r = 255, .g = 0, .b = 0 };
    const blue = highlights.Color{ .r = 0, .g = 0, .b = 255 };

    const c1 = Cell{ .char = 'a', .fg = red };
    const c2 = Cell{ .char = 'a', .fg = red };
    const c3 = Cell{ .char = 'a', .fg = blue };

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
}

test "ScreenGrid: init and deinit" {
    var grid = try ScreenGrid.init(std.testing.allocator, 80, 24);
    defer grid.deinit();

    try std.testing.expectEqual(@as(usize, 80), grid.width);
    try std.testing.expectEqual(@as(usize, 24), grid.height);
}

test "ScreenGrid: setCell and getCell" {
    var grid = try ScreenGrid.init(std.testing.allocator, 80, 24);
    defer grid.deinit();

    const cell = Cell{ .char = 'x', .bold = true };
    grid.setCell(5, 10, cell);

    const retrieved = grid.getCell(5, 10).?;
    try std.testing.expect(retrieved.eql(cell));
}

test "ScreenGrid: diff detects changes" {
    var grid = try ScreenGrid.init(std.testing.allocator, 80, 24);
    defer grid.deinit();

    // Initial state - swap to mark as "previous"
    grid.swapBuffers();

    // Make changes
    grid.setCell(0, 0, Cell{ .char = 'a' });
    grid.setCell(0, 1, Cell{ .char = 'b' });

    // Get diff
    const updates = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates);

    // Should detect 2 changes
    try std.testing.expectEqual(@as(usize, 2), updates.len);
}
