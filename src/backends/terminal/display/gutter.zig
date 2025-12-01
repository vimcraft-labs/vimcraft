const std = @import("std");

/// Gutter column renderer function type
/// Parameters: line_num (0-indexed), cursor_line, buf (output buffer)
/// Returns: number of characters written to buf
pub const GutterRenderer = *const fn (line_num: usize, cursor_line: usize, buf: []u8) usize;

/// Gutter column definition
pub const GutterColumn = struct {
    /// Unique identifier for this gutter column
    name: []const u8,
    /// Render function
    renderer: GutterRenderer,
    /// Cached width (0 = needs recalculation)
    cached_width: usize = 0,
    /// Cache key (e.g., line count for line numbers)
    cache_key: usize = 0,
    /// Whether this column is enabled
    enabled: bool = true,
};

/// Gutter manager - handles all gutter columns
pub const GutterManager = struct {
    columns: std.ArrayList(GutterColumn),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GutterManager {
        return .{
            .columns = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GutterManager) void {
        self.columns.deinit(self.allocator);
    }

    /// Register a new gutter column
    pub fn registerColumn(self: *GutterManager, name: []const u8, renderer: GutterRenderer) !void {
        const column = GutterColumn{
            .name = name,
            .renderer = renderer,
        };
        try self.columns.append(self.allocator, column);
    }

    /// Enable/disable a gutter column by name
    pub fn setColumnEnabled(self: *GutterManager, name: []const u8, enabled: bool) void {
        for (self.columns.items) |*col| {
            if (std.mem.eql(u8, col.name, name)) {
                col.enabled = enabled;
                break;
            }
        }
    }

    /// Get a gutter column by name
    pub fn getColumn(self: *GutterManager, name: []const u8) ?*GutterColumn {
        for (self.columns.items) |*col| {
            if (std.mem.eql(u8, col.name, name)) {
                return col;
            }
        }
        return null;
    }

    /// Calculate total gutter width (sum of enabled columns)
    pub fn getTotalWidth(self: *GutterManager) usize {
        var total: usize = 0;
        for (self.columns.items) |col| {
            if (col.enabled) {
                total += col.cached_width;
            }
        }
        return total;
    }

    /// Render all enabled gutter columns for a line
    /// Returns: number of characters written
    pub fn renderLine(self: *GutterManager, line_num: usize, cursor_line: usize, buf: []u8) usize {
        var offset: usize = 0;
        for (self.columns.items) |col| {
            if (col.enabled and col.cached_width > 0) {
                // Slice buffer to exact column width so renderer knows its boundaries
                const col_end = @min(offset + col.cached_width, buf.len);
                const col_buf = buf[offset..col_end];
                const written = col.renderer(line_num, cursor_line, col_buf);
                offset += written;
            }
        }
        return offset;
    }
};

/// Line number configuration
pub const LineNumberConfig = struct {
    /// Show absolute line numbers
    number: bool = false,
    /// Show relative line numbers
    relative_number: bool = false,
    /// Minimum width for line number column (Neovim's numberwidth option)
    /// Default is 4 to match Neovim. Valid range: 1-20
    min_width: u8 = 4,

    /// Get the effective mode
    pub fn getMode(self: LineNumberConfig) LineNumberMode {
        if (self.relative_number and self.number) return .hybrid;
        if (self.relative_number) return .relative;
        if (self.number) return .absolute;
        return .none;
    }
};

/// Sign column configuration (Neovim-compatible)
pub const SignColumnConfig = struct {
    mode: SignColumnMode = .no,

    pub const SignColumnMode = enum {
        no, // Never show sign column
        yes, // Always show sign column (2 chars wide)
        auto, // Show only when signs exist
        // TODO: number (merge with line numbers)
    };

    pub fn parseMode(str: []const u8) SignColumnMode {
        if (std.mem.eql(u8, str, "yes")) return .yes;
        if (std.mem.eql(u8, str, "auto")) return .auto;
        return .no;
    }
};

pub const LineNumberMode = enum {
    none,
    absolute,
    relative,
    hybrid, // Both absolute on cursor line, relative elsewhere
};

/// Calculate width needed for line numbers with configurable minimum width
/// Uses fast integer log10 (Helix approach)
/// IMPORTANT: Includes 1 space separator after the number
/// @param line_count: Number of lines in buffer
/// @param min_width: Minimum digit width (Neovim's numberwidth option, default 4)
/// @return: Total width including separator space
pub fn calculateLineNumberWidthWithMin(line_count: usize, min_width: u8) usize {
    // Count digits needed for largest line number
    var digits: usize = 1;
    if (line_count > 0) {
        var count = line_count;
        while (count >= 10) {
            digits += 1;
            count /= 10;
        }
    }
    // Use configured minimum width, plus 1 for the space separator
    return @max(digits, min_width) + 1;
}

/// Calculate width needed for line numbers (uses default min_width of 4)
/// Kept for backward compatibility
pub fn calculateLineNumberWidth(line_count: usize) usize {
    return calculateLineNumberWidthWithMin(line_count, 4);
}

/// Absolute line number renderer
/// Renders right-aligned line number with 1 space separator
pub fn renderAbsoluteLineNumber(line_num: usize, cursor_line: usize, buf: []u8) usize {
    _ = cursor_line;
    // Display line numbers as 1-indexed
    const display_num = line_num + 1;

    // Count digits to determine padding
    var num_digits: usize = 1;
    var temp = display_num;
    while (temp >= 10) {
        num_digits += 1;
        temp /= 10;
    }

    // Calculate padding for right-alignment
    // buf.len is the cached_width (digits + 1 space)
    const total_width = buf.len;
    if (total_width == 0) return 0;

    // Right-align: add padding spaces, then number, then 1 separator space
    const num_width = num_digits; // Just the digits
    const padding = if (total_width > num_width + 1)
        total_width - num_width - 1 // -1 for the separator space
    else
        0;

    var offset: usize = 0;

    // Add left padding spaces for right-alignment
    for (0..padding) |_| {
        if (offset >= buf.len) return offset;
        buf[offset] = ' ';
        offset += 1;
    }

    // Add the number
    const formatted = std.fmt.bufPrint(buf[offset..], "{d}", .{display_num}) catch return offset;
    offset += formatted.len;

    // Add 1 separator space
    if (offset < buf.len) {
        buf[offset] = ' ';
        offset += 1;
    }

    return offset;
}

/// Relative line number renderer
/// Renders right-aligned relative distance with 1 space separator
pub fn renderRelativeLineNumber(line_num: usize, cursor_line: usize, buf: []u8) usize {
    const distance = if (line_num >= cursor_line)
        line_num - cursor_line
    else
        cursor_line - line_num;

    // Count digits
    var num_digits: usize = 1;
    var temp = distance;
    while (temp >= 10) {
        num_digits += 1;
        temp /= 10;
    }

    // Calculate padding for right-alignment
    const total_width = buf.len;
    if (total_width == 0) return 0;

    const num_width = num_digits;
    const padding = if (total_width > num_width + 1)
        total_width - num_width - 1
    else
        0;

    var offset: usize = 0;

    // Add left padding
    for (0..padding) |_| {
        if (offset >= buf.len) return offset;
        buf[offset] = ' ';
        offset += 1;
    }

    // Add the number
    const formatted = std.fmt.bufPrint(buf[offset..], "{d}", .{distance}) catch return offset;
    offset += formatted.len;

    // Add separator space
    if (offset < buf.len) {
        buf[offset] = ' ';
        offset += 1;
    }

    return offset;
}

/// Hybrid line number renderer (absolute on cursor line, relative elsewhere)
pub fn renderHybridLineNumber(line_num: usize, cursor_line: usize, buf: []u8) usize {
    if (line_num == cursor_line) {
        return renderAbsoluteLineNumber(line_num, cursor_line, buf);
    } else {
        return renderRelativeLineNumber(line_num, cursor_line, buf);
    }
}

/// Sign column renderer (placeholder for diagnostics/git/marks)
/// Returns 2 chars: "[sign] " or "  "
pub fn renderSignColumn(line_num: usize, cursor_line: usize, buf: []u8) usize {
    _ = line_num;
    _ = cursor_line;
    // TODO: Look up actual signs for this line
    // For now, render empty sign column (2 spaces)
    if (buf.len >= 2) {
        buf[0] = ' ';
        buf[1] = ' ';
        return 2;
    }
    return 0;
}

test "calculateLineNumberWidth" {
    // Now enforces minimum 4 digits + 1 space = 5 chars (matching window_renderer)
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(0)); // min 4 digits + 1 space
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(9)); // min 4 digits + 1 space
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(10)); // min 4 digits + 1 space
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(99)); // min 4 digits + 1 space
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(100)); // min 4 digits + 1 space
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(1000)); // 4 digits + 1 space
    try std.testing.expectEqual(@as(usize, 6), calculateLineNumberWidth(10000)); // 5 digits + 1 space
}

test "calculateLineNumberWidthWithMin" {
    // Test with min_width = 1 (minimal gutter)
    try std.testing.expectEqual(@as(usize, 2), calculateLineNumberWidthWithMin(0, 1)); // 1 digit + 1 space
    try std.testing.expectEqual(@as(usize, 2), calculateLineNumberWidthWithMin(9, 1)); // 1 digit + 1 space
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidthWithMin(10, 1)); // 2 digits + 1 space
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidthWithMin(99, 1)); // 2 digits + 1 space
    try std.testing.expectEqual(@as(usize, 4), calculateLineNumberWidthWithMin(100, 1)); // 3 digits + 1 space

    // Test with min_width = 2 (user wants compact gutter)
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidthWithMin(0, 2)); // min 2 + 1 space
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidthWithMin(9, 2)); // min 2 + 1 space
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidthWithMin(57, 2)); // 2 digits + 1 space
    try std.testing.expectEqual(@as(usize, 4), calculateLineNumberWidthWithMin(100, 2)); // 3 digits + 1 space

    // Test with min_width = 6 (user wants extra padding)
    try std.testing.expectEqual(@as(usize, 7), calculateLineNumberWidthWithMin(0, 6)); // min 6 + 1 space
    try std.testing.expectEqual(@as(usize, 7), calculateLineNumberWidthWithMin(99999, 6)); // 5 digits but min 6 + 1 space
    try std.testing.expectEqual(@as(usize, 7), calculateLineNumberWidthWithMin(100000, 6)); // 6 digits + 1 space
    try std.testing.expectEqual(@as(usize, 8), calculateLineNumberWidthWithMin(1000000, 6)); // 7 digits + 1 space
}
