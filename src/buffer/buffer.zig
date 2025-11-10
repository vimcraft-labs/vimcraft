const std = @import("std");

/// Cursor position in the buffer
pub const Cursor = struct {
    row: usize = 0, // 0-indexed line number
    col: usize = 0, // 0-indexed column number (byte offset, not character)
    goal_column: ?usize = null, // Target column for vertical movements (sticky column)

    pub fn init() Cursor {
        return .{ .row = 0, .col = 0, .goal_column = null };
    }
};

/// Change type for undo/redo
pub const Change = struct {
    offset: usize, // Byte offset in buffer
    deleted_text: []const u8, // Text that was deleted (owned, must free)
    inserted_text: []const u8, // Text that was inserted (owned, must free)
    cursor_before: Cursor, // Cursor position before change
    cursor_after: Cursor, // Cursor position after change

    pub fn deinit(self: *Change, allocator: std.mem.Allocator) void {
        allocator.free(self.deleted_text);
        allocator.free(self.inserted_text);
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

    // Undo/redo
    undo_stack: std.ArrayList(Change),
    redo_stack: std.ArrayList(Change),

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{
            .allocator = allocator,
            .content = .empty,
            .line_starts = .empty,
            .cursor = Cursor.init(),
            .filepath = null,
            .modified = false,
            .undo_stack = .empty,
            .redo_stack = .empty,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.content.deinit(self.allocator);
        self.line_starts.deinit(self.allocator);
        if (self.filepath) |path| {
            self.allocator.free(path);
        }

        // Clean up undo/redo stacks
        for (self.undo_stack.items) |*change| {
            change.deinit(self.allocator);
        }
        self.undo_stack.deinit(self.allocator);

        for (self.redo_stack.items) |*change| {
            change.deinit(self.allocator);
        }
        self.redo_stack.deinit(self.allocator);
    }

    /// Load file from path
    pub fn loadFile(self: *Buffer, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Read entire file into content
        const max_size = 100 * 1024 * 1024; // 100MB limit
        const file_contents = try file.readToEndAlloc(self.allocator, max_size);
        defer self.allocator.free(file_contents);

        // Copy to our ArrayList
        try self.content.appendSlice(self.allocator, file_contents);

        // Store filepath
        self.filepath = try self.allocator.dupe(u8, path);

        // Build line index
        try self.buildLineIndex();

        self.modified = false;
    }

    /// Build index of line start positions
    pub fn buildLineIndex(self: *Buffer) !void {
        self.line_starts.clearRetainingCapacity();

        // First line starts at 0
        try self.line_starts.append(self.allocator, 0);

        // Find all newline positions
        for (self.content.items, 0..) |byte, i| {
            if (byte == '\n' and i + 1 < self.content.items.len) {
                try self.line_starts.append(self.allocator, i + 1);
            }
        }
    }

    /// Get total number of lines
    pub fn lineCount(self: *const Buffer) usize {
        if (self.line_starts.items.len == 0) return 0;
        return self.line_starts.items.len;
    }

    /// Get line by index (0-based)
    /// Returns slice pointing into buffer content (includes newline if present)
    pub fn getLine(self: *const Buffer, line_num: usize) ?[]const u8 {
        if (line_num >= self.lineCount()) return null;

        const start = self.line_starts.items[line_num];
        const end = if (line_num + 1 < self.line_starts.items.len)
            self.line_starts.items[line_num + 1] // Include up to start of next line
        else
            self.content.items.len;

        return self.content.items[start..end];
    }

    /// Get line length (in bytes, includes newline if present)
    pub fn getLineLength(self: *const Buffer, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        return line.len;
    }

    /// Get visual line length (excludes newline)
    pub fn getLineLengthVisual(self: *const Buffer, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        // Exclude newline for visual length
        return if (line.len > 0 and line[line.len - 1] == '\n')
            line.len - 1
        else
            line.len;
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

    // ===== Text Modification Functions =====

    /// Record a change for undo/redo
    pub fn recordChange(self: *Buffer, change: Change) !void {
        try self.undo_stack.append(self.allocator, change);
        // Clear redo stack when new change is made
        for (self.redo_stack.items) |*c| {
            c.deinit(self.allocator);
        }
        self.redo_stack.clearRetainingCapacity();
    }

    /// Insert character at cursor position
    pub fn insertChar(self: *Buffer, char: u8) !void {
        const offset = self.getCursorOffset();
        const cursor_before = self.cursor;

        // Insert character
        try self.content.insert(self.allocator, offset, char);

        // Rebuild line index after insertion (offsets have shifted)
        try self.buildLineIndex();

        // Update cursor position
        if (char == '\n') {
            // Newline - move to next line, col 0
            self.cursor.row += 1;
            self.cursor.col = 0;
        } else {
            // Regular character - move cursor forward
            self.cursor.col += 1;
        }

        // Record change for undo
        const change = Change{
            .offset = offset,
            .deleted_text = try self.allocator.alloc(u8, 0), // Empty - nothing deleted
            .inserted_text = try self.allocator.dupe(u8, &[_]u8{char}),
            .cursor_before = cursor_before,
            .cursor_after = self.cursor,
        };
        try self.recordChange(change);

        self.modified = true;
    }

    /// Delete character at cursor (like 'x' in Vim)
    pub fn deleteChar(self: *Buffer) !void {
        const offset = self.getCursorOffset();
        if (offset >= self.content.items.len) return; // Nothing to delete

        const cursor_before = self.cursor;
        const deleted_char = self.content.items[offset];

        // Delete character
        _ = self.content.orderedRemove(offset);

        // Rebuild line index if newline was deleted
        if (deleted_char == '\n') {
            try self.buildLineIndex();
            // Cursor stays at same position
        } else {
            // Clamp cursor to line length
            const line_len = self.getLineLength(self.cursor.row);
            if (line_len > 0 and self.cursor.col >= line_len) {
                self.cursor.col = line_len - 1;
            }
        }

        // Record change for undo
        const change = Change{
            .offset = offset,
            .deleted_text = try self.allocator.dupe(u8, &[_]u8{deleted_char}),
            .inserted_text = try self.allocator.alloc(u8, 0), // Empty - nothing inserted
            .cursor_before = cursor_before,
            .cursor_after = self.cursor,
        };
        try self.recordChange(change);

        self.modified = true;
    }

    /// Delete character before cursor (backspace)
    pub fn deleteCharBefore(self: *Buffer) !void {
        if (self.cursor.col == 0 and self.cursor.row == 0) return; // Nothing to delete

        const cursor_before = self.cursor;

        // Move cursor back
        if (self.cursor.col > 0) {
            self.cursor.col -= 1;
        } else {
            // At start of line - join with previous line
            self.cursor.row -= 1;
            self.cursor.col = self.getLineLengthVisual(self.cursor.row);
        }

        const offset = self.getCursorOffset();
        const deleted_char = self.content.items[offset];

        // Delete character
        _ = self.content.orderedRemove(offset);

        // Rebuild line index after deletion (offsets have shifted)
        try self.buildLineIndex();

        // Record change for undo
        const change = Change{
            .offset = offset,
            .deleted_text = try self.allocator.dupe(u8, &[_]u8{deleted_char}),
            .inserted_text = try self.allocator.alloc(u8, 0),
            .cursor_before = cursor_before,
            .cursor_after = self.cursor,
        };
        try self.recordChange(change);

        self.modified = true;
    }

    /// Undo last change
    pub fn undo(self: *Buffer) !void {
        const change = self.undo_stack.pop() orelse return; // Nothing to undo

        // Reverse the change
        if (change.inserted_text.len > 0) {
            // Remove inserted text
            for (0..change.inserted_text.len) |_| {
                _ = self.content.orderedRemove(change.offset);
            }
        }

        if (change.deleted_text.len > 0) {
            // Re-insert deleted text
            try self.content.insertSlice(self.allocator, change.offset, change.deleted_text);
        }

        // Restore cursor position
        self.cursor = change.cursor_before;

        // Rebuild line index
        try self.buildLineIndex();

        // Move change to redo stack
        try self.redo_stack.append(self.allocator, change);
    }

    /// Redo last undone change
    pub fn redo(self: *Buffer) !void {
        const change = self.redo_stack.pop() orelse return; // Nothing to redo

        // Reapply the change
        if (change.deleted_text.len > 0) {
            // Remove text again
            for (0..change.deleted_text.len) |_| {
                _ = self.content.orderedRemove(change.offset);
            }
        }

        if (change.inserted_text.len > 0) {
            // Re-insert text
            try self.content.insertSlice(self.allocator, change.offset, change.inserted_text);
        }

        // Restore cursor position
        self.cursor = change.cursor_after;

        // Rebuild line index
        try self.buildLineIndex();

        // Move change back to undo stack
        try self.undo_stack.append(self.allocator, change);
    }

    /// Delete entire line (dd)
    pub fn deleteLine(self: *Buffer) !void {
        if (self.lineCount() == 0) return;

        const cursor_before = self.cursor;
        const line_num = self.cursor.row;

        // Get line start and end positions
        const line_start = self.line_starts.items[line_num];
        const line_end = if (line_num + 1 < self.line_starts.items.len)
            self.line_starts.items[line_num + 1]
        else
            self.content.items.len;

        // Save deleted text
        const deleted_text = try self.allocator.dupe(u8, self.content.items[line_start..line_end]);

        // Delete the line (including newline)
        var i: usize = line_end;
        while (i > line_start) {
            i -= 1;
            _ = self.content.orderedRemove(line_start);
        }

        // Rebuild line index
        try self.buildLineIndex();

        // Move cursor to start of current line (or previous line if we deleted last line)
        if (self.lineCount() > 0) {
            if (line_num >= self.lineCount()) {
                self.cursor.row = self.lineCount() - 1;
            } else {
                self.cursor.row = line_num;
            }
            self.cursor.col = 0;
        } else {
            self.cursor.row = 0;
            self.cursor.col = 0;
        }

        // Record change
        const change = Change{
            .offset = line_start,
            .deleted_text = deleted_text,
            .inserted_text = try self.allocator.alloc(u8, 0),
            .cursor_before = cursor_before,
            .cursor_after = self.cursor,
        };
        try self.recordChange(change);

        self.modified = true;
    }

    /// Delete word forward (dw)
    pub fn deleteWord(self: *Buffer) !void {
        const line = self.getLine(self.cursor.row) orelse return;
        const cursor_before = self.cursor;
        const start_offset = self.getCursorOffset();

        var col = self.cursor.col;

        // Skip current word
        while (col < line.len and isWordChar(line[col])) {
            col += 1;
        }

        // Skip whitespace
        while (col < line.len and !isWordChar(line[col]) and line[col] != '\n') {
            col += 1;
        }

        // If we didn't move, delete to end of line
        if (col == self.cursor.col) {
            const line_len = self.getLineLength(self.cursor.row);
            col = line_len;
        }

        const end_offset = self.line_starts.items[self.cursor.row] + col;
        const delete_count = end_offset - start_offset;

        if (delete_count == 0) return;

        // Save deleted text
        const deleted_text = try self.allocator.dupe(u8, self.content.items[start_offset..end_offset]);

        // Delete characters
        for (0..delete_count) |_| {
            _ = self.content.orderedRemove(start_offset);
        }

        // Rebuild line index if needed
        for (deleted_text) |c| {
            if (c == '\n') {
                try self.buildLineIndex();
                break;
            }
        }

        // Cursor stays at same position
        // Clamp to line length
        const new_line_len = self.getLineLength(self.cursor.row);
        if (new_line_len > 0 and self.cursor.col >= new_line_len) {
            self.cursor.col = new_line_len - 1;
        }

        // Record change
        const change = Change{
            .offset = start_offset,
            .deleted_text = deleted_text,
            .inserted_text = try self.allocator.alloc(u8, 0),
            .cursor_before = cursor_before,
            .cursor_after = self.cursor,
        };
        try self.recordChange(change);

        self.modified = true;
    }

    /// Check if character is word constituent (helper for deleteWord)
    fn isWordChar(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_';
    }

    /// Save buffer to file
    pub fn saveFile(self: *Buffer) !void {
        const path = self.filepath orelse return error.NoFilepath;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(self.content.items);
        self.modified = false;
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
    try std.testing.expectEqualStrings("Hello\n", line1);

    const line2 = buffer.getLine(1).?;
    try std.testing.expectEqualStrings("World\n", line2);
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
