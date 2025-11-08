const std = @import("std");
const highlights = @import("../config/highlights.zig");
const char_width = @import("char_width.zig");

/// A single cell in the terminal grid
pub const Cell = struct {
    char: u21, // Unicode codepoint (base character)
    fg: ?highlights.Color = null,
    bg: ?highlights.Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    is_continuation: bool = false, // True for the second cell of double-width chars

    // Store up to 2 combining/zero-width characters (e.g., variation selectors)
    // This allows proper rendering of emoji with variation selectors like 🖥️
    combining: [2]u21 = [_]u21{0} ** 2,
    combining_count: u8 = 0,

    /// Check if two cells are equal (for diffing)
    pub fn eql(self: Cell, other: Cell) bool {
        if (self.char != other.char) return false;
        if (self.is_continuation != other.is_continuation) return false;
        if (self.bold != other.bold) return false;
        if (self.italic != other.italic) return false;
        if (self.underline != other.underline) return false;
        if (self.combining_count != other.combining_count) return false;
        for (0..self.combining_count) |i| {
            if (self.combining[i] != other.combining[i]) return false;
        }

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
        // IMPORTANT: Initialize with a sentinel value (char=0) instead of blank (char=' ')
        // This ensures that on first render, ALL cells are detected as changed by diff(),
        // even cells that happen to be spaces with null colors. Without this, spaces
        // with fg=null/bg=null would be equal to blank cells and wouldn't render.
        const previous = try allocator.alloc([]Cell, height);
        for (previous) |*row| {
            row.* = try allocator.alloc(Cell, width);
            for (row.*) |*cell| {
                cell.* = Cell{ .char = 0 }; // Sentinel: char=0 (NUL) won't match any real content
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
                cell.* = Cell{ .char = 0 }; // Sentinel value like in init()
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
        var updates: std.ArrayList(Update) = .empty;

        const debug_log = @import("../debug/log.zig");

        // Count dirty lines for debugging
        var dirty_count: usize = 0;
        var iter_count = self.dirty_lines.iterator(.{});
        while (iter_count.next()) |_| {
            dirty_count += 1;
        }
        debug_log.log("DIFF: Checking {d} dirty lines out of {d} total", .{dirty_count, self.height});

        // Only check dirty lines (Neovim optimization)
        var iter = self.dirty_lines.iterator(.{});
        var cells_checked: usize = 0;
        var cells_changed: usize = 0;
        while (iter.next()) |row| {
            // Compare each cell in this row
            for (0..self.width) |col| {
                const current_cell = self.current[row][col];
                const previous_cell = self.previous[row][col];
                cells_checked += 1;

                if (!current_cell.eql(previous_cell)) {
                    cells_changed += 1;

                    // Debug: Log first few changes with background color info
                    if (cells_changed <= 3) {
                        const cur_bg = if (current_cell.bg) |bg|
                            @as(i32, @intCast(bg.r))
                        else
                            -1;
                        const prev_bg = if (previous_cell.bg) |bg|
                            @as(i32, @intCast(bg.r))
                        else
                            -1;
                        debug_log.log("  Change {d}: row={d} col={d} char={u}→{u} bg={}→{}", .{
                            cells_changed, row, col, previous_cell.char, current_cell.char, prev_bg, cur_bg
                        });
                    }

                    try updates.append(allocator, .{
                        .row = row,
                        .col = col,
                        .cell = current_cell,
                    });
                }
            }
        }

        debug_log.log("DIFF: Checked {d} cells, found {d} changes", .{cells_checked, cells_changed});

        return updates.toOwnedSlice(allocator);
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
            const width = char_width.codepointWidth(codepoint);

            // Handle zero-width characters (combining marks, variation selectors)
            // Attach them to the previous cell's combining array
            if (width == 0) {
                if (current_col > col and current_col > 0) {
                    // Find the actual character cell (skip continuation cells)
                    var target_col = current_col - 1;
                    while (target_col > 0 and self.current[row][target_col].is_continuation) {
                        target_col -= 1;
                    }
                    // Add to combining array if there's space
                    if (self.current[row][target_col].combining_count < 2) {
                        const idx = self.current[row][target_col].combining_count;
                        self.current[row][target_col].combining[idx] = codepoint;
                        self.current[row][target_col].combining_count += 1;
                    }
                }
                i += char_len;
                continue;
            }

            // Set the main character cell
            self.current[row][current_col] = .{
                .char = codepoint,
                .fg = fg,
                .bg = bg,
            };

            current_col += 1;

            // For double-width characters, fill the second column with a continuation marker
            // The cellwidth system now returns the correct width for all characters,
            // including emoji that may have been problematic before
            if (width == 2 and current_col < self.width) {
                self.current[row][current_col] = .{
                    .char = ' ', // Placeholder (not rendered to terminal)
                    .fg = fg,
                    .bg = bg,
                    .is_continuation = true, // Mark as continuation
                };
                current_col += 1;
            }

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
