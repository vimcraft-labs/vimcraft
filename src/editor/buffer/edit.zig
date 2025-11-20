const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Cursor = @import("buffer.zig").Cursor;
const Change = @import("buffer.zig").Change;

/// Edit operations module - provides high-level text editing commands
/// This module implements Vim's delete, change, and yank operators
///
/// Design Philosophy:
/// - All edit operations go through this module for consistency
/// - Transactions track changes for undo/redo
/// - Operations are composable with motions
/// - Registers store deleted/yanked text
/// Range of text to operate on (byte offsets)
pub const Range = struct {
    start: usize, // Inclusive start byte offset
    end: usize, // Exclusive end byte offset

    /// Create a range from two cursor positions
    pub fn fromCursors(buffer: *const Buffer, start_cursor: Cursor, end_cursor: Cursor) Range {
        const start_offset = buffer.content.byteOfLine(start_cursor.row) + start_cursor.col;
        const end_offset = buffer.content.byteOfLine(end_cursor.row) + end_cursor.col;

        return .{
            .start = @min(start_offset, end_offset),
            .end = @max(start_offset, end_offset),
        };
    }

    /// Create a range for a single character at cursor
    pub fn forChar(buffer: *const Buffer) Range {
        const offset = buffer.getCursorOffset();
        return .{
            .start = offset,
            .end = offset + 1,
        };
    }

    /// Create a range for current line (includes newline)
    pub fn forLine(buffer: *const Buffer, line_num: usize) Range {
        if (line_num >= buffer.lineCount()) {
            const content_len = buffer.content.len();
            return .{ .start = content_len, .end = content_len };
        }

        const line_start = buffer.content.byteOfLine(line_num);
        const line_end = if (line_num + 1 < buffer.lineCount())
            buffer.content.byteOfLine(line_num + 1)
        else
            buffer.content.len();

        return .{
            .start = line_start,
            .end = line_end,
        };
    }

    /// Get the text content for this range
    /// Returns owned memory (caller must free with buffer's allocator)
    pub fn getText(self: Range, buffer: *const Buffer) ![]const u8 {
        const start = @min(self.start, buffer.content.len());
        const end = @min(self.end, buffer.content.len());

        // Extract text from Rope
        var text_rope = try buffer.content.slice(start, end);
        defer text_rope.deinit();

        return try text_rope.toString();
    }

    /// Check if range is empty
    pub fn isEmpty(self: Range) bool {
        return self.start >= self.end;
    }

    /// Get length in bytes
    pub fn len(self: Range) usize {
        return if (self.end > self.start) self.end - self.start else 0;
    }
};

/// Motion type for delete/change/yank operators
pub const MotionType = enum {
    char, // Character-wise (x, dw, d$)
    line, // Line-wise (dd, yy)
    block, // Block-wise (visual block)
};

/// Delete operation result
pub const DeleteResult = struct {
    deleted_text: []const u8, // Text that was deleted (caller must free)
    cursor_after: Cursor, // Where cursor should be after delete
};

/// Edit operations context
pub const EditOps = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EditOps {
        return .{ .allocator = allocator };
    }

    /// Delete text in range
    /// This is the core delete operation that all delete commands use
    pub fn deleteRange(self: *EditOps, buffer: *Buffer, range: Range, motion_type: MotionType) !DeleteResult {
        if (range.isEmpty()) {
            return DeleteResult{
                .deleted_text = try self.allocator.alloc(u8, 0),
                .cursor_after = buffer.cursor,
            };
        }

        // Invalidate external ArrayBuffers before modification
        buffer.incrementVersion();

        const cursor_before = buffer.cursor;

        // Save deleted text (getText now returns owned memory)
        const deleted_text = try range.getText(buffer);

        // Delete the text using Rope (automatic line tracking - O(log n)!)
        try buffer.content.delete(range.start, range.end);

        // NOTE: With Rope, line tracking is automatic - no rebuild needed!

        // Determine cursor position after delete
        const cursor_after = try self.calculateCursorAfterDelete(buffer, range, motion_type, cursor_before);
        buffer.cursor = cursor_after;

        // Record change for undo
        const change = Change{
            .offset = range.start,
            .deleted_text = try self.allocator.dupe(u8, deleted_text),
            .inserted_text = try self.allocator.alloc(u8, 0),
            .cursor_before = cursor_before,
            .cursor_after = cursor_after,
        };
        try buffer.recordChange(change);

        buffer.modified = true;

        return DeleteResult{
            .deleted_text = deleted_text,
            .cursor_after = cursor_after,
        };
    }

    /// Calculate where cursor should be after delete
    fn calculateCursorAfterDelete(
        self: *EditOps,
        buffer: *Buffer,
        range: Range,
        motion_type: MotionType,
        cursor_before: Cursor,
    ) !Cursor {
        _ = self;

        switch (motion_type) {
            .char => {
                // Character delete: cursor stays at deletion point
                // Clamp to line length
                if (buffer.lineCount() == 0) {
                    return Cursor{ .row = 0, .col = 0 };
                }

                var cursor = cursor_before;

                // Find which line contains the deletion point
                // With Rope, we can iterate through lines to find which contains the offset
                var line_num: usize = 0;
                while (line_num < buffer.lineCount()) : (line_num += 1) {
                    const line_start = buffer.content.byteOfLine(line_num);
                    const line_end = if (line_num + 1 < buffer.lineCount())
                        buffer.content.byteOfLine(line_num + 1)
                    else
                        buffer.content.len();

                    if (range.start >= line_start and range.start < line_end) {
                        cursor.row = line_num;
                        cursor.col = range.start - line_start;
                        break;
                    }
                }

                // Clamp column to line length
                const line_len = buffer.getLineLength(cursor.row);
                if (line_len > 0 and cursor.col >= line_len) {
                    cursor.col = line_len - 1;
                }
                if (cursor.col > 0 and line_len == 0) {
                    cursor.col = 0;
                }

                return cursor;
            },
            .line => {
                // Line delete: cursor moves to start of line where deletion occurred
                if (buffer.lineCount() == 0) {
                    return Cursor{ .row = 0, .col = 0 };
                }

                // Find which line the deletion started at
                var line_num: usize = 0;
                while (line_num < buffer.lineCount()) : (line_num += 1) {
                    const line_start = buffer.content.byteOfLine(line_num);
                    if (line_start > range.start) {
                        // We've passed the deletion point, so it was on the previous line
                        if (line_num > 0) line_num -= 1;
                        break;
                    }
                }

                // Clamp to valid line range
                if (line_num >= buffer.lineCount()) {
                    line_num = buffer.lineCount() - 1;
                }

                return Cursor{ .row = line_num, .col = 0 };
            },
            .block => {
                // Block delete: not implemented yet
                return cursor_before;
            },
        }
    }

    /// Delete single character under cursor (x command)
    pub fn deleteCharAtCursor(self: *EditOps, buffer: *Buffer) !DeleteResult {
        const range = Range.forChar(buffer);
        return try self.deleteRange(buffer, range, .char);
    }

    /// Delete entire line (dd command)
    pub fn deleteCurrentLine(self: *EditOps, buffer: *Buffer) !DeleteResult {
        const range = Range.forLine(buffer, buffer.cursor.row);
        return try self.deleteRange(buffer, range, .line);
    }

    /// Delete multiple lines (e.g., 3dd)
    pub fn deleteLines(self: *EditOps, buffer: *Buffer, count: usize) !DeleteResult {
        if (count == 0) return try self.deleteCurrentLine(buffer);

        const start_line = buffer.cursor.row;
        const end_line = @min(start_line + count, buffer.lineCount());

        if (start_line >= buffer.lineCount()) {
            return DeleteResult{
                .deleted_text = try self.allocator.alloc(u8, 0),
                .cursor_after = buffer.cursor,
            };
        }

        // Calculate range spanning multiple lines
        const range_start = buffer.content.byteOfLine(start_line);
        const range_end = if (end_line < buffer.lineCount())
            buffer.content.byteOfLine(end_line)
        else
            buffer.content.len();

        const range = Range{ .start = range_start, .end = range_end };
        return try self.deleteRange(buffer, range, .line);
    }

    /// Delete from cursor to end of word (dw command)
    pub fn deleteWord(self: *EditOps, buffer: *Buffer) !DeleteResult {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            return DeleteResult{
                .deleted_text = try self.allocator.alloc(u8, 0),
                .cursor_after = buffer.cursor,
            };
        };
        defer buffer.allocator.free(line); // getLine() returns owned memory

        const start_offset = buffer.getCursorOffset();
        var col = buffer.cursor.col;

        // Skip current word
        while (col < line.len and isWordChar(line[col])) {
            col += 1;
        }

        // Skip only actual whitespace (space/tab) after word, not punctuation
        while (col < line.len and isWhitespace(line[col]) and line[col] != '\n') {
            col += 1;
        }

        // If we didn't move, we're at whitespace - skip to next word
        if (col == buffer.cursor.col) {
            while (col < line.len and isWhitespace(line[col]) and line[col] != '\n') {
                col += 1;
            }
        }

        const end_offset = buffer.content.byteOfLine(buffer.cursor.row) + col;
        const range = Range{ .start = start_offset, .end = end_offset };

        return try self.deleteRange(buffer, range, .char);
    }

    /// Delete to end of line (d$ command)
    pub fn deleteToEndOfLine(self: *EditOps, buffer: *Buffer) !DeleteResult {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            return DeleteResult{
                .deleted_text = try self.allocator.alloc(u8, 0),
                .cursor_after = buffer.cursor,
            };
        };
        defer buffer.allocator.free(line); // getLine() returns owned memory

        const start_offset = buffer.getCursorOffset();
        const line_start = buffer.content.byteOfLine(buffer.cursor.row);

        // Delete to end of line (excluding newline)
        var end_col = line.len;
        if (end_col > 0 and line[end_col - 1] == '\n') {
            end_col -= 1;
        }

        const end_offset = line_start + end_col;
        const range = Range{ .start = start_offset, .end = end_offset };

        return try self.deleteRange(buffer, range, .char);
    }

    /// Delete to start of line (d0 command)
    pub fn deleteToStartOfLine(self: *EditOps, buffer: *Buffer) !DeleteResult {
        const line_start = buffer.content.byteOfLine(buffer.cursor.row);
        const cursor_offset = buffer.getCursorOffset();

        const range = Range{ .start = line_start, .end = cursor_offset };
        return try self.deleteRange(buffer, range, .char);
    }

    /// Change operation - delete and enter insert mode
    /// Returns the deleted text (caller must free)
    pub fn changeRange(self: *EditOps, buffer: *Buffer, range: Range, motion_type: MotionType) ![]const u8 {
        const result = try self.deleteRange(buffer, range, motion_type);
        // Note: Caller (input handler) will enter insert mode after this
        return result.deleted_text;
    }

    // ========== Yank Operations (read-only text extraction) ==========

    /// Extract text from cursor to end of line (y$ command)
    /// Returns text (caller must free)
    pub fn yankToEndOfLine(self: *EditOps, buffer: *const Buffer) ![]const u8 {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            return try self.allocator.alloc(u8, 0);
        };
        defer buffer.allocator.free(line); // getLine() returns owned memory

        const start_col = buffer.cursor.col;
        var end_col = line.len;

        // Exclude trailing newline
        if (end_col > 0 and line[end_col - 1] == '\n') {
            end_col -= 1;
        }

        if (start_col >= end_col) {
            return try self.allocator.alloc(u8, 0);
        }

        return try self.allocator.dupe(u8, line[start_col..end_col]);
    }

    /// Extract text from start of line to cursor (y0 command)
    /// Returns text (caller must free)
    pub fn yankToStartOfLine(self: *EditOps, buffer: *const Buffer) ![]const u8 {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            return try self.allocator.alloc(u8, 0);
        };
        defer buffer.allocator.free(line); // getLine() returns owned memory

        const end_col = @min(buffer.cursor.col, line.len);
        return try self.allocator.dupe(u8, line[0..end_col]);
    }

    /// Extract word from cursor position (yw command)
    /// Returns text (caller must free)
    pub fn yankWord(self: *EditOps, buffer: *const Buffer) ![]const u8 {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            return try self.allocator.alloc(u8, 0);
        };
        defer buffer.allocator.free(line); // getLine() returns owned memory

        const start_col = buffer.cursor.col;
        var col = start_col;

        // Skip current word
        while (col < line.len and isWordChar(line[col])) {
            col += 1;
        }

        // Skip only actual whitespace (space/tab) after word, not punctuation
        while (col < line.len and isWhitespace(line[col]) and line[col] != '\n') {
            col += 1;
        }

        // If we didn't move, we're at whitespace - skip to next word
        if (col == start_col) {
            while (col < line.len and isWhitespace(line[col]) and line[col] != '\n') {
                col += 1;
            }
        }

        if (start_col >= col) {
            return try self.allocator.alloc(u8, 0);
        }

        return try self.allocator.dupe(u8, line[start_col..col]);
    }

    /// Helper: Check if character is word constituent
    fn isWordChar(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_';
    }

    /// Helper: Check if character is whitespace (space or tab)
    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t';
    }
};

// Tests
test "EditOps: delete single char" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Setup buffer with content using Rope
    buffer.content.deinit();
    buffer.content = try @import("rope.zig").Rope.fromString(allocator, "Hello\n");
    buffer.cursor = .{ .row = 0, .col = 1 }; // Cursor on 'e'

    var edit_ops = EditOps.init(allocator);
    const result = try edit_ops.deleteCharAtCursor(&buffer);
    defer allocator.free(result.deleted_text);

    try std.testing.expectEqualStrings("e", result.deleted_text);

    // Verify buffer content
    const content = try buffer.content.toString();
    defer allocator.free(content);
    try std.testing.expectEqualStrings("Hllo\n", content);
}

test "EditOps: delete line" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Setup buffer with content using Rope
    buffer.content.deinit();
    buffer.content = try @import("rope.zig").Rope.fromString(allocator, "Line1\nLine2\nLine3\n");
    buffer.cursor = .{ .row = 1, .col = 0 }; // Cursor on Line2

    var edit_ops = EditOps.init(allocator);
    const result = try edit_ops.deleteCurrentLine(&buffer);
    defer allocator.free(result.deleted_text);

    try std.testing.expectEqualStrings("Line2\n", result.deleted_text);

    // Verify buffer content
    const content = try buffer.content.toString();
    defer allocator.free(content);
    try std.testing.expectEqualStrings("Line1\nLine3\n", content);

    try std.testing.expectEqual(@as(usize, 1), result.cursor_after.row);
    try std.testing.expectEqual(@as(usize, 0), result.cursor_after.col);
}

test "EditOps: delete word" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Setup buffer with content using Rope
    buffer.content.deinit();
    buffer.content = try @import("rope.zig").Rope.fromString(allocator, "Hello World\n");
    buffer.cursor = .{ .row = 0, .col = 0 }; // Cursor on 'H'

    var edit_ops = EditOps.init(allocator);
    const result = try edit_ops.deleteWord(&buffer);
    defer allocator.free(result.deleted_text);

    try std.testing.expectEqualStrings("Hello ", result.deleted_text);

    // Verify buffer content
    const content = try buffer.content.toString();
    defer allocator.free(content);
    try std.testing.expectEqualStrings("World\n", content);
}
