const std = @import("std");
const Rope = @import("rope.zig").Rope;
const Syntax = @import("../treesitter/syntax.zig").Syntax;

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

/// Transaction for grouping multiple changes into a single undo unit
const Transaction = struct {
    start_offset: usize,
    current_offset: usize, // Track current position during transaction (line_starts may be stale)
    text_buffer: std.ArrayList(u8),
    cursor_start: Cursor,
    cursor_end: Cursor,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, offset: usize, cursor: Cursor) Transaction {
        return .{
            .start_offset = offset,
            .current_offset = offset,
            .text_buffer = .empty,
            .cursor_start = cursor,
            .cursor_end = cursor,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Transaction) void {
        self.text_buffer.deinit(self.allocator);
    }
};

/// Text buffer implementation using Rope data structure for O(log n) edits
/// Rope provides efficient insert/delete operations for large files
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    content: Rope,
    cursor: Cursor,
    filepath: ?[]const u8,
    filetype: ?[]const u8 = null, // Detected filetype (e.g., "rust", "javascript")
    modified: bool,

    // Undo/redo
    undo_stack: std.ArrayList(Change),
    redo_stack: std.ArrayList(Change),

    // Transaction grouping (for paste operations)
    active_transaction: ?Transaction = null,

    // Version tracking for ArrayBuffer safety
    // Incremented on any modification - used to detect use-after-free in JavaScript
    version: u64 = 0,

    // Tree-sitter syntax highlighting (per-buffer, following Neovim's architecture)
    // Each buffer owns its own Syntax instance for proper floating window highlighting
    syntax: ?*Syntax = null,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{
            .allocator = allocator,
            .content = Rope.init(allocator),
            .cursor = Cursor.init(),
            .filepath = null,
            .filetype = null,
            .modified = false,
            .undo_stack = .empty,
            .redo_stack = .empty,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.content.deinit();
        if (self.filepath) |path| {
            self.allocator.free(path);
        }
        if (self.filetype) |ft| {
            self.allocator.free(ft);
        }

        // Clean up syntax highlighting
        self.deinitSyntax();

        // Clean up active transaction if any
        if (self.active_transaction) |*trans| {
            trans.deinit();
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
        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Read entire file into content
        const max_size = 100 * 1024 * 1024; // 100MB limit
        const file_contents = try file.readToEndAlloc(self.allocator, max_size);
        defer self.allocator.free(file_contents);

        // Load into Rope (replaces ArrayList appendSlice + buildLineIndex)
        self.content.deinit(); // Clear existing content
        self.content = try Rope.fromString(self.allocator, file_contents);

        // Store filepath
        self.filepath = try self.allocator.dupe(u8, path);

        self.modified = false;
    }

    // NOTE: buildLineIndex() removed - Rope tracks line positions internally

    /// Get total number of lines
    /// NOTE: Adjusts for editor semantics where trailing newline doesn't create empty line
    /// e.g., "Hello\nWorld\n" has 2 lines, not 3, empty buffer has 0 lines
    pub fn lineCount(self: *const Buffer) usize {
        const len = self.content.len();
        if (len == 0) return 0; // Empty buffer has 0 lines

        const rope_lines = self.content.lineCount();

        // Check if buffer ends with newline (creating empty last line)
        const last_byte = self.content.byteAt(len - 1);
        if (last_byte != null and last_byte.? == '\n') {
            // Trailing newline - don't count empty last line
            return rope_lines - 1;
        }

        return rope_lines;
    }

    /// Get line by index (0-based)
    /// Returns OWNED slice (must be freed by caller) including newline if present
    /// Returns null if line_num is out of bounds
    pub fn getLine(self: *const Buffer, line_num: usize) ?[]const u8 {
        if (line_num >= self.lineCount()) return null;

        const start = self.content.byteOfLine(line_num);
        const end = if (line_num + 1 < self.lineCount())
            self.content.byteOfLine(line_num + 1)
        else
            self.content.len();

        // Slice the rope (creates new rope, then convert to string)
        var line_rope = self.content.slice(start, end) catch return null;
        defer line_rope.deinit();

        // Convert to owned string (caller must free with Rope's allocator)
        return line_rope.toString() catch null;
    }

    /// Get line length (in bytes, includes newline if present)
    pub fn getLineLength(self: *const Buffer, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        defer self.allocator.free(line); // Free owned memory
        return line.len;
    }

    /// Get visual line length (excludes newline)
    pub fn getLineLengthVisual(self: *const Buffer, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        defer self.allocator.free(line); // Free owned memory
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
        if (self.cursor.row >= self.lineCount()) return self.content.len();

        const line_start = self.content.byteOfLine(self.cursor.row);
        return line_start + self.cursor.col;
    }

    /// Get character at cursor (returns null if at end of line/file)
    pub fn getCharAtCursor(self: *const Buffer) ?u8 {
        const offset = self.getCursorOffset();
        if (offset >= self.content.len()) return null;
        return self.content.byteAt(offset);
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
        return self.content.len() == 0;
    }

    // ===== Text Modification Functions =====

    /// Increment buffer version (invalidates external ArrayBuffers)
    /// Call this BEFORE any modification to buffer content
    /// Public so edit/paste/visual_ops modules can call it
    pub fn incrementVersion(self: *Buffer) void {
        self.version +%= 1; // Wrapping add (u64 overflow is fine)
    }

    /// Start a transaction for grouping multiple changes
    pub fn beginTransaction(self: *Buffer) void {
        if (self.active_transaction == null) {
            const offset = self.getCursorOffset();
            self.active_transaction = Transaction.init(self.allocator, offset, self.cursor);
        }
    }

    /// Commit the active transaction to undo stack
    pub fn commitTransaction(self: *Buffer) !void {
        if (self.active_transaction) |*trans| {
            // NOTE: With Rope, line tracking is automatic - no rebuild needed!

            // CRITICAL: Cursor position might be invalid
            // During transaction, cursor.row is incremented for '\n', but line_starts
            // wasn't rebuilt, so cursor.row might point past the end of actual lines.
            // Clamp cursor to valid range after rebuild.
            if (self.cursor.row >= self.lineCount()) {
                if (self.lineCount() > 0) {
                    self.cursor.row = self.lineCount() - 1;
                    // Position at end of last line
                    const line_len = self.getLineLengthVisual(self.cursor.row);
                    self.cursor.col = line_len;
                } else {
                    self.cursor.row = 0;
                    self.cursor.col = 0;
                }
            }

            // Only create change if there's actual content
            if (trans.text_buffer.items.len > 0) {
                const change = Change{
                    .offset = trans.start_offset,
                    .deleted_text = try self.allocator.alloc(u8, 0),
                    .inserted_text = try self.allocator.dupe(u8, trans.text_buffer.items),
                    .cursor_before = trans.cursor_start,
                    .cursor_after = self.cursor, // Use clamped cursor position
                };
                try self.undo_stack.append(self.allocator, change);

                // Clear redo stack
                for (self.redo_stack.items) |*c| {
                    c.deinit(self.allocator);
                }
                self.redo_stack.clearRetainingCapacity();
            }

            trans.deinit();
            self.active_transaction = null;
        }
    }

    /// Discard the active transaction without creating undo entry
    /// Used when manually creating a combined undo entry
    pub fn discardTransaction(self: *Buffer) void {
        if (self.active_transaction) |*trans| {
            // NOTE: With Rope, line tracking is automatic - no rebuild needed!

            trans.deinit();
            self.active_transaction = null;
        }
    }

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
        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

        // During transactions, use tracked offset
        // Otherwise, calculate from cursor position
        const offset = if (self.active_transaction) |trans|
            trans.current_offset
        else
            self.getCursorOffset();

        // Insert character using Rope (automatic line tracking - O(log n)!)
        const char_str = &[_]u8{char};
        try self.content.insert(offset, char_str);

        // NOTE: With Rope, line tracking is automatic - no rebuild needed!

        // Update cursor position
        if (char == '\n') {
            // Newline - move to next line, col 0
            self.cursor.row += 1;
            self.cursor.col = 0;
        } else {
            // Regular character - move cursor forward
            self.cursor.col += 1;
        }

        // If we're in a transaction, update tracked offset and buffer
        if (self.active_transaction) |*trans| {
            try trans.text_buffer.append(self.allocator, char);
            trans.cursor_end = self.cursor;
            trans.current_offset += 1; // Track next insertion position

            // DEBUG: Removed logging
        } else {
            // No transaction - record individual change (normal typing)
            const cursor_before = Cursor{
                .row = if (char == '\n' and self.cursor.row > 0) self.cursor.row - 1 else self.cursor.row,
                .col = if (char == '\n') 0 else if (self.cursor.col > 0) self.cursor.col - 1 else 0,
                .goal_column = null,
            };

            const change = Change{
                .offset = offset,
                .deleted_text = try self.allocator.alloc(u8, 0),
                .inserted_text = try self.allocator.dupe(u8, &[_]u8{char}),
                .cursor_before = cursor_before,
                .cursor_after = self.cursor,
            };
            try self.recordChange(change);
        }

        self.modified = true;
    }

    /// Delete character at cursor (like 'x' in Vim)
    pub fn deleteChar(self: *Buffer) !void {
        const offset = self.getCursorOffset();
        if (offset >= self.content.len()) return; // Nothing to delete

        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

        const cursor_before = self.cursor;
        const deleted_char = self.content.byteAt(offset) orelse return; // Get char before deleting

        // Delete character using Rope (automatic line tracking!)
        try self.content.delete(offset, offset + 1);

        // Clamp cursor to line length
        const line_len = self.getLineLength(self.cursor.row);
        if (line_len > 0 and self.cursor.col >= line_len) {
            self.cursor.col = line_len - 1;
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

        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

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
        const deleted_char = self.content.byteAt(offset) orelse return;

        // Delete character using Rope (automatic line tracking!)
        try self.content.delete(offset, offset + 1);

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

        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

        // Reverse the change
        if (change.inserted_text.len > 0) {
            // Remove inserted text using Rope
            const end_offset = change.offset + change.inserted_text.len;
            try self.content.delete(change.offset, end_offset);
        }

        if (change.deleted_text.len > 0) {
            // Re-insert deleted text using Rope
            try self.content.insert(change.offset, change.deleted_text);
        }

        // Restore cursor position
        self.cursor = change.cursor_before;

        // Move change to redo stack
        try self.redo_stack.append(self.allocator, change);
    }

    /// Redo last undone change
    pub fn redo(self: *Buffer) !void {
        const change = self.redo_stack.pop() orelse return; // Nothing to redo

        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

        // Reapply the change
        if (change.deleted_text.len > 0) {
            // Remove text again using Rope
            const end_offset = change.offset + change.deleted_text.len;
            try self.content.delete(change.offset, end_offset);
        }

        if (change.inserted_text.len > 0) {
            // Re-insert text using Rope
            try self.content.insert(change.offset, change.inserted_text);
        }

        // Restore cursor position
        self.cursor = change.cursor_after;

        // Move change back to undo stack
        try self.undo_stack.append(self.allocator, change);
    }

    /// Delete entire line (dd)
    pub fn deleteLine(self: *Buffer) !void {
        if (self.lineCount() == 0) return;

        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

        const cursor_before = self.cursor;
        const line_num = self.cursor.row;

        // Get line start and end positions using Rope
        const line_start = self.content.byteOfLine(line_num);
        const line_end = if (line_num + 1 < self.lineCount())
            self.content.byteOfLine(line_num + 1)
        else
            self.content.len();

        // Save deleted text (need to extract from Rope)
        var deleted_rope = try self.content.slice(line_start, line_end);
        defer deleted_rope.deinit();
        const deleted_text = try deleted_rope.toString();

        // Delete the line using Rope (automatic line tracking!)
        try self.content.delete(line_start, line_end);

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
        defer self.allocator.free(line); // Free owned memory from getLine()

        // Invalidate external ArrayBuffers before modification
        self.incrementVersion();

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

        const line_start = self.content.byteOfLine(self.cursor.row);
        const end_offset = line_start + col;
        const delete_count = end_offset - start_offset;

        if (delete_count == 0) return;

        // Save deleted text (extract from Rope)
        var deleted_rope = try self.content.slice(start_offset, end_offset);
        defer deleted_rope.deinit();
        const deleted_text = try deleted_rope.toString();

        // Delete characters using Rope (automatic line tracking!)
        try self.content.delete(start_offset, end_offset);

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

    /// Set filetype (allocates and copies string, frees previous if any)
    /// Pass null to clear filetype
    pub fn setFiletype(self: *Buffer, ft: ?[]const u8) !void {
        // Free previous filetype if any
        if (self.filetype) |old_ft| {
            self.allocator.free(old_ft);
        }

        // Set new filetype (allocate and copy)
        if (ft) |new_ft| {
            self.filetype = try self.allocator.dupe(u8, new_ft);
        } else {
            self.filetype = null;
        }
    }

    // ===== Syntax Highlighting Functions =====

    /// Initialize syntax highlighting for this buffer
    /// Called when filetype is set or changed
    /// Requires: parser - shared Parser instance from Editor
    ///           lang - TSLanguage pointer for the filetype
    ///           lang_name - language name for query loading (e.g., "typescript")
    pub fn initSyntax(
        self: *Buffer,
        parser: anytype, // *Parser
        lang: anytype, // *const c.TSLanguage
        lang_name: []const u8,
    ) !void {
        // Clean up existing syntax if any
        self.deinitSyntax();

        // Get buffer content as string for parsing
        const source = self.content.toString() catch return;
        defer self.allocator.free(source);

        // Parse the content with tree-sitter
        const tree = parser.parseString(null, source) catch return;

        // Allocate Syntax on the heap (Buffer owns it)
        const syntax_ptr = self.allocator.create(Syntax) catch return;
        errdefer self.allocator.destroy(syntax_ptr);

        // Initialize the Syntax instance
        syntax_ptr.* = Syntax.init(self.allocator, tree, lang, lang_name) catch {
            self.allocator.destroy(syntax_ptr);
            return;
        };

        self.syntax = syntax_ptr;
    }

    /// Clean up syntax highlighting
    /// Called on deinit or when filetype changes
    pub fn deinitSyntax(self: *Buffer) void {
        if (self.syntax) |syntax_ptr| {
            syntax_ptr.deinit();
            self.allocator.destroy(syntax_ptr);
            self.syntax = null;
        }
    }

    /// Save buffer to file
    pub fn saveFile(self: *Buffer) !void {
        const path = self.filepath orelse return error.NoFilepath;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Convert Rope to string and write to file
        const content_str = try self.content.toString();
        defer self.allocator.free(content_str); // Free with same allocator Rope used

        try file.writeAll(content_str);
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
    const tmp_path = "/tmp/vimcraft_test.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello\nWorld\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    try std.testing.expectEqual(@as(usize, 2), buffer.lineCount());

    const line1 = buffer.getLine(0).?;
    defer allocator.free(line1); // Free owned memory
    try std.testing.expectEqualStrings("Hello\n", line1);

    const line2 = buffer.getLine(1).?;
    defer allocator.free(line2); // Free owned memory
    try std.testing.expectEqualStrings("World\n", line2);
}

test "Buffer: cursor movement" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Load content
    const tmp_path = "/tmp/vimcraft_test_cursor.txt";
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

test "Buffer: paste with tab during transaction" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Buffer starts empty (Rope.init already called in Buffer.init)

    // Simulate what bracketed paste does:
    // 1. Start transaction
    buffer.beginTransaction();

    // 2. Insert "hello\tworld\n" character by character
    const paste_content = "hello\tworld\n";
    for (paste_content) |char| {
        try buffer.insertChar(char);
    }

    // 3. Commit transaction
    try buffer.commitTransaction();

    // Verify final content using Rope.toString()
    const content_str = try buffer.content.toString();
    defer allocator.free(content_str); // Free with same allocator Rope used
    try std.testing.expectEqualStrings("hello\tworld\n", content_str);

    // Verify line count (terminal \n doesn't create new line in line_starts)
    try std.testing.expectEqual(@as(usize, 1), buffer.lineCount());

    // Verify cursor position
    // During transaction, cursor was incremented to (1,0) for the '\n'
    // After commit, cursor is clamped because lineCount=1 but cursor.row was 1
    // So cursor should be clamped to (0, 11) - end of the line
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 11), buffer.cursor.col); // At end of "hello\tworld"

    // Verify line content
    const line1 = buffer.getLine(0).?;
    defer allocator.free(line1); // Free owned memory
    try std.testing.expectEqualStrings("hello\tworld\n", line1);
}
