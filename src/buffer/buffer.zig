const std = @import("std");

/// Cursor position in the buffer
pub const Cursor = struct {
    row: usize = 0, // 0-indexed line number
    col: usize = 0, // 0-indexed column number (byte offset, not character)

    pub fn init() Cursor {
        return .{ .row = 0, .col = 0 };
    }
};

/// Simple text buffer implementation using ArrayList
/// This is a minimal implementation - will be replaced with rope later for performance
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    content: std.ArrayList(u8),
    line_starts: std.ArrayList(usize), // Byte offsets where each line starts
    cursor: Cursor,
    filepath: ?[]const u8,
    modified: bool,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{
            .allocator = allocator,
            .content = std.ArrayList(u8).init(allocator),
            .line_starts = std.ArrayList(usize).init(allocator),
            .cursor = Cursor.init(),
            .filepath = null,
            .modified = false,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.content.deinit();
        self.line_starts.deinit();
        if (self.filepath) |path| {
            self.allocator.free(path);
        }
    }

    /// Load file from path
    pub fn loadFile(self: *Buffer, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Read entire file into content
        const max_size = 100 * 1024 * 1024; // 100MB limit
        try file.reader().readAllArrayList(&self.content, max_size);

        // Store filepath
        self.filepath = try self.allocator.dupe(u8, path);

        // Build line index
        try self.buildLineIndex();

        self.modified = false;
    }

    /// Build index of line start positions
    fn buildLineIndex(self: *Buffer) !void {
        self.line_starts.clearRetainingCapacity();

        // First line starts at 0
        try self.line_starts.append(0);

        // Find all newline positions
        for (self.content.items, 0..) |byte, i| {
            if (byte == '\n' and i + 1 < self.content.items.len) {
                try self.line_starts.append(i + 1);
            }
        }
    }

    /// Get total number of lines
    pub fn lineCount(self: *const Buffer) usize {
        if (self.line_starts.items.len == 0) return 0;
        return self.line_starts.items.len;
    }

    /// Get line by index (0-based)
    /// Returns slice pointing into buffer content
    pub fn getLine(self: *const Buffer, line_num: usize) ?[]const u8 {
        if (line_num >= self.lineCount()) return null;

        const start = self.line_starts.items[line_num];
        const end = if (line_num + 1 < self.line_starts.items.len)
            self.line_starts.items[line_num + 1] - 1 // Exclude newline
        else
            self.content.items.len;

        return self.content.items[start..end];
    }

    /// Get line length (in bytes)
    pub fn getLineLength(self: *const Buffer, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        return line.len;
    }

    /// Move cursor to position, clamping to valid range
    pub fn moveCursorTo(self: *Buffer, row: usize, col: usize) void {
        // Clamp row to valid range
        const max_row = if (self.lineCount() > 0) self.lineCount() - 1 else 0;
        self.cursor.row = @min(row, max_row);

        // Clamp column to line length
        const line_len = self.getLineLength(self.cursor.row);
        self.cursor.col = @min(col, if (line_len > 0) line_len - 1 else 0);
    }

    /// Move cursor relative to current position
    pub fn moveCursorRelative(self: *Buffer, row_delta: isize, col_delta: isize) void {
        const new_row = @as(isize, @intCast(self.cursor.row)) + row_delta;
        const new_col = @as(isize, @intCast(self.cursor.col)) + col_delta;

        const clamped_row = @max(0, new_row);
        const clamped_col = @max(0, new_col);

        self.moveCursorTo(@intCast(clamped_row), @intCast(clamped_col));
    }

    /// Get byte offset of cursor position
    pub fn getCursorOffset(self: *const Buffer) usize {
        if (self.cursor.row >= self.lineCount()) return self.content.items.len;

        const line_start = self.line_starts.items[self.cursor.row];
        return line_start + self.cursor.col;
    }

    /// Get character at cursor (returns null if at end of line/file)
    pub fn getCharAtCursor(self: *const Buffer) ?u8 {
        const offset = self.getCursorOffset();
        if (offset >= self.content.items.len) return null;
        return self.content.items[offset];
    }

    /// Check if cursor is at end of line
    pub fn isAtEndOfLine(self: *const Buffer) bool {
        const line_len = self.getLineLength(self.cursor.row);
        return self.cursor.col >= line_len;
    }

    /// Check if cursor is at start of line
    pub fn isAtStartOfLine(self: *const Buffer) bool {
        return self.cursor.col == 0;
    }

    /// Check if buffer is empty
    pub fn isEmpty(self: *const Buffer) bool {
        return self.content.items.len == 0;
    }
};

// Tests
test "Buffer: basic initialization" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 0), buffer.lineCount());
    try std.testing.expect(buffer.isEmpty());
}

test "Buffer: load simple content" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Create temp file
    const tmp_path = "/tmp/openvim_test.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello\nWorld\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    try std.testing.expectEqual(@as(usize, 2), buffer.lineCount());

    const line1 = buffer.getLine(0).?;
    try std.testing.expectEqualStrings("Hello", line1);

    const line2 = buffer.getLine(1).?;
    try std.testing.expectEqualStrings("World", line2);
}

test "Buffer: cursor movement" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Load content
    const tmp_path = "/tmp/openvim_test_cursor.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abc\ndef\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Initial cursor position
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);

    // Move cursor
    buffer.moveCursorTo(0, 2);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);
    try std.testing.expectEqual(@as(u8, 'c'), buffer.getCharAtCursor().?);

    // Move to next line
    buffer.moveCursorTo(1, 0);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(u8, 'd'), buffer.getCharAtCursor().?);

    // Move relative
    buffer.moveCursorRelative(0, 1);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);
    try std.testing.expectEqual(@as(u8, 'e'), buffer.getCharAtCursor().?);
}
