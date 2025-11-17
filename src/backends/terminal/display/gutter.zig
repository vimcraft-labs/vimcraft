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
                const remaining = buf[offset..];
                const written = col.renderer(line_num, cursor_line, remaining);
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

/// Calculate width needed for line numbers
/// Uses fast integer log10 (Helix approach)
/// IMPORTANT: Includes trailing space that renderer adds ("{d} ")
pub fn calculateLineNumberWidth(line_count: usize) usize {
    if (line_count == 0) return 2; // "0 " = 1 digit + 1 space
    // Use checked_ilog10 equivalent
    var count = line_count;
    var width: usize = 1;
    while (count >= 10) {
        width += 1;
        count /= 10;
    }
    // Add 1 for trailing space that renderer adds
    return width + 1;
}

/// Absolute line number renderer
pub fn renderAbsoluteLineNumber(line_num: usize, cursor_line: usize, buf: []u8) usize {
    _ = cursor_line;
    // Display line numbers as 1-indexed
    const display_num = line_num + 1;
    const formatted = std.fmt.bufPrint(buf, "{d} ", .{display_num}) catch buf[0..0];
    return formatted.len;
}

/// Relative line number renderer
pub fn renderRelativeLineNumber(line_num: usize, cursor_line: usize, buf: []u8) usize {
    const distance = if (line_num >= cursor_line)
        line_num - cursor_line
    else
        cursor_line - line_num;

    const formatted = std.fmt.bufPrint(buf, "{d} ", .{distance}) catch buf[0..0];
    return formatted.len;
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
    try std.testing.expectEqual(@as(usize, 2), calculateLineNumberWidth(0)); // "0 " = 1 digit + 1 space
    try std.testing.expectEqual(@as(usize, 2), calculateLineNumberWidth(9)); // "9 " = 1 digit + 1 space
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidth(10)); // "10 " = 2 digits + 1 space
    try std.testing.expectEqual(@as(usize, 3), calculateLineNumberWidth(99)); // "99 " = 2 digits + 1 space
    try std.testing.expectEqual(@as(usize, 4), calculateLineNumberWidth(100)); // "100 " = 3 digits + 1 space
    try std.testing.expectEqual(@as(usize, 5), calculateLineNumberWidth(1000)); // "1000 " = 4 digits + 1 space
}
