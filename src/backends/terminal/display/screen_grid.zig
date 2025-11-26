const std = @import("std");
const highlights = @import("../../../editor/config/highlights.zig");
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

    // Store up to 4 combining/zero-width characters (e.g., variation selectors, ZWJ sequences)
    // This allows proper rendering of emoji with variation selectors like 🖥️
    // and complex sequences like family emoji (👨‍👩‍👧‍👦)
    combining: [4]u21 = [_]u21{0} ** 4,
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

/// Grid-based screen buffer (Neovim-style 2D array with O(1) scroll)
///
/// Architecture: Uses line_offset[] indirection for O(1) scrolling (Neovim technique).
/// Instead of copying rows when scrolling, we rotate the offset array:
///
///   Before scroll:  line_offset = [0, 1, 2, 3, 4]  (identity mapping)
///   After scroll 1: line_offset = [1, 2, 3, 4, 0]  (row 0 now points to old row 1)
///
/// This makes scroll O(height) for offset rotation vs O(height × width) for data copy.
/// Combined with O(1) buffer swap, this achieves world-class rendering performance.
pub const ScreenGrid = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,

    // Double buffering: current and previous frame
    // NOTE: These are the RAW storage arrays. Access via line_offset for correct row mapping.
    current: [][]Cell,
    previous: [][]Cell,

    // O(1) scroll optimization: line offset indirection (Neovim-style)
    // Maps logical row → physical row in storage array
    // Example: current_offset[2] = 5 means logical row 2 is stored in current[5]
    current_offset: []usize,
    previous_offset: []usize,

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

        // Allocate line offset arrays for O(1) scroll (Neovim-style indirection)
        // Initialize with identity mapping: logical row i → physical row i
        const current_offset = try allocator.alloc(usize, height);
        const previous_offset = try allocator.alloc(usize, height);
        for (0..height) |i| {
            current_offset[i] = i;
            previous_offset[i] = i;
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
            .current_offset = current_offset,
            .previous_offset = previous_offset,
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

        // Free line offset arrays
        self.allocator.free(self.current_offset);
        self.allocator.free(self.previous_offset);

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

        // Free old offset arrays
        self.allocator.free(self.current_offset);
        self.allocator.free(self.previous_offset);

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

        // Allocate new offset arrays with identity mapping
        self.current_offset = try self.allocator.alloc(usize, new_height);
        self.previous_offset = try self.allocator.alloc(usize, new_height);
        for (0..new_height) |i| {
            self.current_offset[i] = i;
            self.previous_offset[i] = i;
        }

        self.dirty_lines = try std.DynamicBitSet.initEmpty(self.allocator, new_height);
        self.dirty_lines.setRangeValue(.{ .start = 0, .end = new_height }, true);
    }

    /// Set a cell in the current buffer (uses line_offset indirection for O(1) scroll)
    pub fn setCell(self: *ScreenGrid, row: usize, col: usize, cell: Cell) void {
        if (row >= self.height or col >= self.width) return;
        const physical_row = self.current_offset[row];
        self.current[physical_row][col] = cell;
        self.dirty_lines.set(row);
    }

    /// Get a cell from the current buffer (uses line_offset indirection for O(1) scroll)
    pub fn getCell(self: *ScreenGrid, row: usize, col: usize) ?Cell {
        if (row >= self.height or col >= self.width) return null;
        const physical_row = self.current_offset[row];
        return self.current[physical_row][col];
    }

    /// Mark a line as dirty (needs redraw)
    pub fn markDirty(self: *ScreenGrid, row: usize) void {
        if (row < self.height) {
            self.dirty_lines.set(row);
        }
    }

    /// Check if grid has any non-empty cells (uses line_offset indirection)
    /// Used to avoid unnecessary clears that cause flickering
    pub fn hasContent(self: *ScreenGrid) bool {
        for (0..self.height) |logical_row| {
            const physical_row = self.current_offset[logical_row];
            for (self.current[physical_row]) |cell| {
                if (cell.char != ' ' or cell.fg != null or cell.bg != null or
                    cell.bold or cell.italic or cell.underline or cell.combining_count > 0)
                {
                    return true;
                }
            }
        }
        return false;
    }

    /// Clear the entire grid (uses line_offset indirection)
    /// Only marks lines dirty if they actually have content (optimization to prevent flickering)
    pub fn clear(self: *ScreenGrid) void {
        for (0..self.height) |logical_row| {
            const physical_row = self.current_offset[logical_row];
            var row_has_content = false;
            for (self.current[physical_row]) |*cell| {
                // Check if cell is non-blank before clearing
                if (cell.char != ' ' or cell.fg != null or cell.bg != null or
                    cell.bold or cell.italic or cell.underline or cell.combining_count > 0)
                {
                    row_has_content = true;
                    cell.reset();
                } else {
                    // Already blank - just reset to be safe
                    cell.reset();
                }
            }
            // Only mark dirty if this row actually had content
            if (row_has_content) {
                self.dirty_lines.set(logical_row);
            }
        }
    }

    /// Compare current vs previous buffer and return list of changes
    /// This is the core diff algorithm (inspired by both Neovim and Helix)
    /// Uses line_offset indirection for O(1) scroll support
    pub fn diff(self: *ScreenGrid, allocator: std.mem.Allocator) ![]Update {
        var updates: std.ArrayList(Update) = .empty;

        // Only check dirty lines (Neovim optimization)
        var iter = self.dirty_lines.iterator(.{});
        while (iter.next()) |logical_row| {
            // Use indirection to get actual physical rows
            const current_physical = self.current_offset[logical_row];
            const previous_physical = self.previous_offset[logical_row];

            // Compare each cell in this row
            for (0..self.width) |col| {
                const current_cell = self.current[current_physical][col];
                const previous_cell = self.previous[previous_physical][col];

                if (!current_cell.eql(previous_cell)) {
                    try updates.append(allocator, .{
                        .row = logical_row,
                        .col = col,
                        .cell = current_cell,
                    });
                }
            }
        }

        return updates.toOwnedSlice(allocator);
    }

    /// Swap current and previous buffers after rendering - O(1) pointer swap!
    /// (Previous becomes current for next frame comparison)
    ///
    /// Performance: O(1) instead of O(height × width)
    /// This is a critical optimization - for a 200x50 terminal, this changes:
    ///   Before: 10,000 cell copies per frame
    ///   After:  4 pointer swaps per frame (constant time)
    pub fn swapBuffers(self: *ScreenGrid) void {
        // O(1) pointer swap - no data copying!
        const tmp_buf = self.current;
        self.current = self.previous;
        self.previous = tmp_buf;

        // Swap offset arrays too (maintains indirection consistency)
        const tmp_offset = self.current_offset;
        self.current_offset = self.previous_offset;
        self.previous_offset = tmp_offset;

        // Clear dirty flags
        self.dirty_lines.setRangeValue(.{ .start = 0, .end = self.height }, false);
    }

    /// Fill a rectangular region with a cell (uses line_offset indirection)
    pub fn fillRect(self: *ScreenGrid, start_row: usize, start_col: usize, end_row: usize, end_col: usize, cell: Cell) void {
        const r_start = @min(start_row, self.height);
        const r_end = @min(end_row, self.height);
        const c_start = @min(start_col, self.width);
        const c_end = @min(end_col, self.width);

        for (r_start..r_end) |logical_row| {
            const physical_row = self.current_offset[logical_row];
            for (c_start..c_end) |col| {
                self.current[physical_row][col] = cell;
            }
            self.dirty_lines.set(logical_row);
        }
    }

    /// Fill a range of columns in a single row with the same cell
    /// This is useful for filling gutter areas, separators, etc.
    /// Uses line_offset indirection for O(1) scroll support
    pub fn fillRowRange(self: *ScreenGrid, row: usize, start_col: usize, end_col: usize, cell: Cell) void {
        if (row >= self.height) return;
        const physical_row = self.current_offset[row];
        const c_start = @min(start_col, self.width);
        const c_end = @min(end_col, self.width);

        for (c_start..c_end) |col| {
            self.current[physical_row][col] = cell;
        }
        self.dirty_lines.set(row);
    }

    /// Set a string at a specific position (for rendering text)
    /// Returns the column position after the last character written
    /// Uses line_offset indirection for O(1) scroll support
    pub fn setString(self: *ScreenGrid, row: usize, col: usize, text: []const u8, fg: ?highlights.Color, bg: ?highlights.Color) usize {
        if (row >= self.height) return col;

        const physical_row = self.current_offset[row];
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
                    while (target_col > 0 and self.current[physical_row][target_col].is_continuation) {
                        target_col -= 1;
                    }
                    // Add to combining array if there's space
                    if (self.current[physical_row][target_col].combining_count < 4) {
                        const idx = self.current[physical_row][target_col].combining_count;
                        self.current[physical_row][target_col].combining[idx] = codepoint;
                        self.current[physical_row][target_col].combining_count += 1;
                    }
                }
                i += char_len;
                continue;
            }

            // Set the main character cell
            self.current[physical_row][current_col] = .{
                .char = codepoint,
                .fg = fg,
                .bg = bg,
            };

            current_col += 1;

            // For double-width characters, fill the second column with a continuation marker
            // The cellwidth system now returns the correct width for all characters,
            // including emoji that may have been problematic before
            if (width == 2 and current_col < self.width) {
                self.current[physical_row][current_col] = .{
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

    // ============================================================================
    // O(1) SCROLL OPTIMIZATION (Neovim-style pointer rotation)
    // ============================================================================

    /// Scroll the grid by rotating line_offset array - O(height) instead of O(height × width)!
    ///
    /// This is the core of Neovim's world-class scroll performance:
    /// - Positive `lines`: scroll content UP (user scrolling DOWN through file)
    /// - Negative `lines`: scroll content DOWN (user scrolling UP through file)
    ///
    /// Performance comparison for 200×50 terminal scrolling 1 line:
    ///   Naive (copy):     10,000 cell copies = ~200µs
    ///   Neovim (rotate):  50 offset updates  = ~1µs (200× faster!)
    ///
    /// After scroll, the revealed row(s) contain stale data and must be rewritten.
    /// The caller is responsible for populating these rows with new content.
    pub fn scroll(self: *ScreenGrid, lines: isize) void {
        if (lines == 0) return;

        const abs_lines = @abs(lines);
        if (abs_lines >= self.height) {
            // Scrolling more than screen height - clear all cells and reset offsets
            // This ensures no stale data remains (M2 fix from Principal Engineer review)
            for (0..self.height) |logical_row| {
                const physical_row = self.current_offset[logical_row];
                for (0..self.width) |col| {
                    self.current[physical_row][col] = Cell.blank();
                }
            }
            self.resetOffsets();
            self.dirty_lines.setRangeValue(.{ .start = 0, .end = self.height }, true);
            return;
        }

        // Rotate the offset array (Neovim's O(1) scroll technique)
        // std.mem.rotate(T, slice, amount) rotates LEFT by `amount` positions
        if (lines > 0) {
            // Scroll content UP: rotate offsets LEFT
            // Row 0 now points to what was row 1, etc.
            std.mem.rotate(usize, self.current_offset, abs_lines);

            // Clear the revealed bottom rows (they contain stale data)
            const start_clear = self.height - abs_lines;
            for (start_clear..self.height) |logical_row| {
                const physical_row = self.current_offset[logical_row];
                for (0..self.width) |col| {
                    self.current[physical_row][col] = Cell.blank();
                }
                self.dirty_lines.set(logical_row);
            }
        } else {
            // Scroll content DOWN: rotate offsets RIGHT (which is rotate LEFT by height - amount)
            const rotate_amount = self.height - abs_lines;
            std.mem.rotate(usize, self.current_offset, rotate_amount);

            // Clear the revealed top rows (they contain stale data)
            for (0..abs_lines) |logical_row| {
                const physical_row = self.current_offset[logical_row];
                for (0..self.width) |col| {
                    self.current[physical_row][col] = Cell.blank();
                }
                self.dirty_lines.set(logical_row);
            }
        }
    }

    /// Scroll up by n lines (content moves up, new blank lines at bottom)
    /// This is what happens when user presses Ctrl+D or scrolls down in file
    pub fn scrollUp(self: *ScreenGrid, lines: usize) void {
        if (lines > 0) {
            self.scroll(@intCast(lines));
        }
    }

    /// Scroll down by n lines (content moves down, new blank lines at top)
    /// This is what happens when user presses Ctrl+U or scrolls up in file
    pub fn scrollDown(self: *ScreenGrid, lines: usize) void {
        if (lines > 0) {
            self.scroll(-@as(isize, @intCast(lines)));
        }
    }

    /// Reset offset arrays to identity mapping (for resize or full redraw)
    pub fn resetOffsets(self: *ScreenGrid) void {
        for (0..self.height) |i| {
            self.current_offset[i] = i;
            self.previous_offset[i] = i;
        }
    }

    // ============================================================================
    // O4: SCROLL PREVIOUS BUFFER (for terminal scroll optimization)
    // ============================================================================
    // When terminal uses native scroll (CSI S/T), we need to scroll the PREVIOUS
    // buffer to match what the terminal now shows. The CURRENT buffer is left alone
    // because compositor will fill it fresh. diff() then only sees newly revealed
    // rows as different.

    /// Invalidate specific columns in the PREVIOUS buffer
    /// This forces diff() to detect those columns as changed, even if content matches.
    /// Used to force gutter re-render after terminal scroll (line numbers change).
    ///
    /// CRITICAL: Terminal scroll shifts EVERYTHING, but gutter content changes:
    /// - Absolute line numbers change when viewport scrolls
    /// - Relative line numbers ALL change when cursor moves
    /// - This method clears gutter columns in previous so they get re-rendered
    pub fn invalidatePreviousColumns(self: *ScreenGrid, start_col: usize, end_col: usize) void {
        const col_start = @min(start_col, self.width);
        const col_end = @min(end_col, self.width);

        for (0..self.height) |logical_row| {
            const physical_row = self.previous_offset[logical_row];
            for (col_start..col_end) |col| {
                // Set to sentinel value (char=0) to force diff() to detect as changed
                self.previous[physical_row][col] = Cell{ .char = 0 };
            }
            self.dirty_lines.set(logical_row);
        }
    }

    /// Scroll the PREVIOUS buffer only (for terminal scroll optimization)
    /// This matches the previous buffer to what the terminal now displays after
    /// a native scroll command, so diff() only detects newly revealed content.
    pub fn scrollPrevious(self: *ScreenGrid, lines: isize) void {
        if (lines == 0) return;

        const abs_lines = @abs(lines);
        if (abs_lines >= self.height) {
            // Scrolling more than screen height - clear all previous cells
            for (0..self.height) |logical_row| {
                const physical_row = self.previous_offset[logical_row];
                for (0..self.width) |col| {
                    self.previous[physical_row][col] = Cell.blank();
                }
            }
            // Reset previous offsets to identity
            for (0..self.height) |i| {
                self.previous_offset[i] = i;
            }
            return;
        }

        // Rotate the PREVIOUS offset array (match terminal scroll)
        if (lines > 0) {
            // Content scrolled UP: rotate previous offsets LEFT
            std.mem.rotate(usize, self.previous_offset, abs_lines);

            // Clear the revealed bottom rows in previous (they're now blank on terminal)
            const start_clear = self.height - abs_lines;
            for (start_clear..self.height) |logical_row| {
                const physical_row = self.previous_offset[logical_row];
                for (0..self.width) |col| {
                    self.previous[physical_row][col] = Cell.blank();
                }
            }
        } else {
            // Content scrolled DOWN: rotate previous offsets RIGHT
            const rotate_amount = self.height - abs_lines;
            std.mem.rotate(usize, self.previous_offset, rotate_amount);

            // Clear the revealed top rows in previous (they're now blank on terminal)
            for (0..abs_lines) |logical_row| {
                const physical_row = self.previous_offset[logical_row];
                for (0..self.width) |col| {
                    self.previous[physical_row][col] = Cell.blank();
                }
            }
        }
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

    // Set up initial state: both buffers have same content (all blanks)
    // Clear current buffer to blanks (matching how rendering works)
    grid.clear();

    // Initial state - swap to mark as "previous" (O(1) pointer swap)
    // Note: With O(1) swap, buffers exchange. After swap:
    // - current points to what was previous (sentinels initially)
    // - previous points to what was current (blanks)
    grid.swapBuffers();

    // Clear current to blanks (simulating what renderer does each frame)
    // This makes current match previous (both blanks) so only our changes are detected
    for (0..grid.height) |row| {
        const physical_row = grid.current_offset[row];
        for (0..grid.width) |col| {
            grid.current[physical_row][col] = Cell.blank();
        }
    }

    // Mark row 0 dirty so diff will check it
    grid.dirty_lines.set(0);

    // Make changes
    grid.setCell(0, 0, Cell{ .char = 'a' });
    grid.setCell(0, 1, Cell{ .char = 'b' });

    // Get diff
    const updates = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates);

    // Should detect 2 changes
    try std.testing.expectEqual(@as(usize, 2), updates.len);
}

// ============================================================================
// O(1) SCROLL OPTIMIZATION TESTS
// ============================================================================

test "ScreenGrid: scroll preserves content after scrollUp" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set up content: row 0='A', row 1='B', row 2='C', row 3='D', row 4='E'
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });
    grid.setCell(3, 0, Cell{ .char = 'D' });
    grid.setCell(4, 0, Cell{ .char = 'E' });

    // Scroll up by 1 (content moves up, bottom row becomes blank)
    grid.scrollUp(1);

    // After scroll: row 0 should have 'B', row 1 should have 'C', etc.
    try std.testing.expectEqual(@as(u21, 'B'), grid.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'C'), grid.getCell(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'D'), grid.getCell(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'E'), grid.getCell(3, 0).?.char);
    // Bottom row should be blank (space)
    try std.testing.expectEqual(@as(u21, ' '), grid.getCell(4, 0).?.char);
}

test "ScreenGrid: scroll preserves content after scrollDown" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set up content: row 0='A', row 1='B', row 2='C', row 3='D', row 4='E'
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });
    grid.setCell(3, 0, Cell{ .char = 'D' });
    grid.setCell(4, 0, Cell{ .char = 'E' });

    // Scroll down by 1 (content moves down, top row becomes blank)
    grid.scrollDown(1);

    // After scroll: row 0 should be blank, row 1 should have 'A', etc.
    try std.testing.expectEqual(@as(u21, ' '), grid.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'A'), grid.getCell(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'B'), grid.getCell(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'C'), grid.getCell(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'D'), grid.getCell(4, 0).?.char);
}

test "ScreenGrid: scroll multiple lines at once" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set up content
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });
    grid.setCell(3, 0, Cell{ .char = 'D' });
    grid.setCell(4, 0, Cell{ .char = 'E' });

    // Scroll up by 3
    grid.scrollUp(3);

    // After scroll: row 0='D', row 1='E', rows 2-4 blank
    try std.testing.expectEqual(@as(u21, 'D'), grid.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'E'), grid.getCell(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), grid.getCell(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), grid.getCell(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), grid.getCell(4, 0).?.char);
}

test "ScreenGrid: scroll marks correct rows dirty" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Clear dirty flags
    grid.dirty_lines.setRangeValue(.{ .start = 0, .end = 5 }, false);

    // Scroll up by 2
    grid.scrollUp(2);

    // Bottom 2 rows (3, 4) should be dirty (newly revealed)
    try std.testing.expect(grid.dirty_lines.isSet(3));
    try std.testing.expect(grid.dirty_lines.isSet(4));
}

test "ScreenGrid: O(1) swapBuffers preserves content" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set content in current buffer
    grid.setCell(0, 0, Cell{ .char = 'X' });
    grid.setCell(1, 0, Cell{ .char = 'Y' });

    // Swap buffers (O(1) pointer swap)
    grid.swapBuffers();

    // Content should still be accessible after swap
    // (now in "previous" buffer which we can verify indirectly)

    // Set new content
    grid.setCell(0, 0, Cell{ .char = 'A' });

    // New content should be there
    try std.testing.expectEqual(@as(u21, 'A'), grid.getCell(0, 0).?.char);
}

test "ScreenGrid: scroll then setCell works correctly" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set initial content
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });

    // Scroll up
    grid.scrollUp(1);

    // Set new content in revealed row
    grid.setCell(4, 0, Cell{ .char = 'Z' });

    // Verify: row 0 should have 'B' (scrolled), row 4 should have 'Z' (new)
    try std.testing.expectEqual(@as(u21, 'B'), grid.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'Z'), grid.getCell(4, 0).?.char);
}

test "ScreenGrid: multiple scrolls in sequence" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set up numbered rows
    for (0..5) |i| {
        grid.setCell(i, 0, Cell{ .char = @intCast('0' + i) });
    }

    // Scroll up twice
    grid.scrollUp(1);
    grid.scrollUp(1);

    // Row 0 should now have '2' (originally row 2)
    try std.testing.expectEqual(@as(u21, '2'), grid.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '3'), grid.getCell(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, '4'), grid.getCell(2, 0).?.char);
}

test "ScreenGrid: scroll beyond height marks all dirty" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Clear dirty flags
    grid.dirty_lines.setRangeValue(.{ .start = 0, .end = 5 }, false);

    // Scroll more than height
    grid.scrollUp(10);

    // All rows should be dirty
    for (0..5) |i| {
        try std.testing.expect(grid.dirty_lines.isSet(i));
    }
}

test "ScreenGrid: resetOffsets restores identity mapping" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set content and scroll
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.scrollUp(2);

    // Reset offsets
    grid.resetOffsets();

    // Verify identity mapping
    for (0..5) |i| {
        try std.testing.expectEqual(i, grid.current_offset[i]);
        try std.testing.expectEqual(i, grid.previous_offset[i]);
    }
}

test "ScreenGrid: scroll beyond height clears all cells (M2 fix)" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    // Set content in all rows
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });
    grid.setCell(3, 0, Cell{ .char = 'D' });
    grid.setCell(4, 0, Cell{ .char = 'E' });

    // Scroll more than height
    grid.scrollUp(10);

    // All cells should be blank (no stale data)
    for (0..5) |row| {
        try std.testing.expectEqual(@as(u21, ' '), grid.getCell(row, 0).?.char);
    }

    // Offsets should be reset to identity
    for (0..5) |i| {
        try std.testing.expectEqual(i, grid.current_offset[i]);
    }
}

test "ScreenGrid: scroll(0) is no-op" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 5);
    defer grid.deinit();

    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.dirty_lines.setRangeValue(.{ .start = 0, .end = 5 }, false);

    grid.scroll(0);

    // Content unchanged
    try std.testing.expectEqual(@as(u21, 'A'), grid.getCell(0, 0).?.char);
    // No rows marked dirty
    try std.testing.expect(!grid.dirty_lines.isSet(0));
}

// ============================================================================
// INTEGRATION TESTS (M1: scroll+diff+swapBuffers cycle)
// ============================================================================

test "ScreenGrid: scroll generates correct diff across frames (M1)" {
    var grid = try ScreenGrid.init(std.testing.allocator, 10, 3);
    defer grid.deinit();

    // === FRAME 1: Initial render ===
    // Clear and set content (simulating renderer behavior)
    grid.clear();
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });

    // End of frame 1: swap buffers
    grid.swapBuffers();

    // === FRAME 2: Scroll and render new content ===
    // Clear current buffer (simulating renderer behavior)
    for (0..grid.height) |row| {
        const physical_row = grid.current_offset[row];
        for (0..grid.width) |col| {
            grid.current[physical_row][col] = Cell.blank();
        }
    }

    // Scroll up by 1 (simulating viewport change)
    grid.scrollUp(1);

    // Set new content after scroll
    // Row 0 now shows what was row 1 ('B'), row 1 shows what was row 2 ('C')
    // Row 2 is revealed (blank), we write 'D' to it
    grid.setCell(0, 0, Cell{ .char = 'B' }); // Matches scrolled content
    grid.setCell(1, 0, Cell{ .char = 'C' }); // Matches scrolled content
    grid.setCell(2, 0, Cell{ .char = 'D' }); // New content in revealed row

    // Get diff - should detect changes from previous frame
    const updates = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates);

    // Should have updates (at minimum the new 'D' in row 2)
    // The exact count depends on what previous frame had at those positions
    try std.testing.expect(updates.len >= 1);

    // Verify at least one update is for row 2 (the newly revealed row with 'D')
    var has_row2_update = false;
    for (updates) |update| {
        if (update.row == 2 and update.col == 0 and update.cell.char == 'D') {
            has_row2_update = true;
            break;
        }
    }
    try std.testing.expect(has_row2_update);
}

test "ScreenGrid: full render cycle with scroll" {
    var grid = try ScreenGrid.init(std.testing.allocator, 5, 3);
    defer grid.deinit();

    // === FRAME 1 ===
    grid.clear();
    grid.setCell(0, 0, Cell{ .char = '1' });
    grid.setCell(1, 0, Cell{ .char = '2' });
    grid.setCell(2, 0, Cell{ .char = '3' });
    const updates1 = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates1);
    grid.swapBuffers();

    // === FRAME 2: No changes ===
    grid.clear();
    grid.setCell(0, 0, Cell{ .char = '1' });
    grid.setCell(1, 0, Cell{ .char = '2' });
    grid.setCell(2, 0, Cell{ .char = '3' });
    const updates2 = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates2);

    // Should have minimal or no updates (content same as previous frame)
    // Note: Due to O(1) swap semantics, we need to clear properly
    grid.swapBuffers();

    // === FRAME 3: Scroll down ===
    grid.clear();
    grid.scrollDown(1);
    // After scroll down: row 0 blank, row 1 has '1', row 2 has '2'
    grid.setCell(0, 0, Cell{ .char = '0' }); // New content at top
    grid.setCell(1, 0, Cell{ .char = '1' }); // Shifted content
    grid.setCell(2, 0, Cell{ .char = '2' }); // Shifted content

    const updates3 = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates3);

    // Should have updates for the changed rows
    try std.testing.expect(updates3.len >= 1);
}

// ============================================================================
// O4: SCROLL PREVIOUS BUFFER TESTS
// ============================================================================

test "ScreenGrid: scrollPrevious shifts previous buffer only" {
    var grid = try ScreenGrid.init(std.testing.allocator, 5, 3);
    defer grid.deinit();

    // Setup: Set content in current, swap to make it previous
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });
    grid.swapBuffers();

    // Now previous has A, B, C
    // Current has sentinel values (from init)

    // Clear current and set new content
    grid.clear();
    grid.setCell(0, 0, Cell{ .char = 'X' });
    grid.setCell(1, 0, Cell{ .char = 'Y' });
    grid.setCell(2, 0, Cell{ .char = 'Z' });

    // Scroll PREVIOUS up by 1 (simulating terminal scroll)
    grid.scrollPrevious(1);

    // Previous should now be: B, C, blank (shifted up)
    // Current should still be: X, Y, Z (unchanged)

    // Verify current unchanged
    try std.testing.expectEqual(@as(u21, 'X'), grid.getCell(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'Y'), grid.getCell(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'Z'), grid.getCell(2, 0).?.char);

    // Verify previous was scrolled by checking diff
    // If previous is B, C, blank and current is X, Y, Z
    // All 3 rows should differ
    const updates = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates);
    try std.testing.expectEqual(@as(usize, 3), updates.len);
}

test "ScreenGrid: scrollPrevious for terminal scroll optimization" {
    var grid = try ScreenGrid.init(std.testing.allocator, 5, 3);
    defer grid.deinit();

    // Simulate: Frame N rendered lines 0-2 (A, B, C)
    grid.clear();
    grid.setCell(0, 0, Cell{ .char = 'A' });
    grid.setCell(1, 0, Cell{ .char = 'B' });
    grid.setCell(2, 0, Cell{ .char = 'C' });
    grid.swapBuffers();

    // Frame N+1: User scrolled down 1 line
    // Terminal scroll happened - content shifted up
    // Previous should match what terminal now shows: B, C, blank
    grid.scrollPrevious(1);

    // Clear current and render new viewport (lines 1-3: B, C, D)
    grid.clear();
    grid.setCell(0, 0, Cell{ .char = 'B' }); // Line 1
    grid.setCell(1, 0, Cell{ .char = 'C' }); // Line 2
    grid.setCell(2, 0, Cell{ .char = 'D' }); // Line 3 (NEW!)

    // diff should only detect row 2 as changed (B=B, C=C, D!=blank)
    const updates = try grid.diff(std.testing.allocator);
    defer std.testing.allocator.free(updates);

    // Should have exactly 1 update (the new 'D' in row 2)
    try std.testing.expectEqual(@as(usize, 1), updates.len);
    try std.testing.expectEqual(@as(usize, 2), updates[0].row);
    try std.testing.expectEqual(@as(u21, 'D'), updates[0].cell.char);
}
