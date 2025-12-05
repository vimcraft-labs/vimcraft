const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Cursor = @import("buffer.zig").Cursor;
const Change = @import("buffer.zig").Change;
const RegisterManager = @import("../register/register.zig").RegisterManager;
const YankReg = @import("../register/register.zig").YankReg;
const MotionType = @import("../register/register.zig").MotionType;

/// Paste text from register after cursor (p command)
/// Returns new cursor position
pub fn pasteAfter(
    buffer: *Buffer,
    register_mgr: *RegisterManager,
    regname: u8,
) !Cursor {
    const reg = register_mgr.get(regname) orelse return error.InvalidRegister;
    if (reg.isEmpty()) return buffer.cursor; // Nothing to paste

    return switch (reg.motion_type) {
        .char_wise => try pasteCharWiseAfter(buffer, reg),
        .line_wise => try pasteLineWiseAfter(buffer, reg),
        .block_wise => try pasteBlockWiseAfter(buffer, reg),
    };
}

/// Paste text from register before cursor (P command)
/// Returns new cursor position
pub fn pasteBefore(
    buffer: *Buffer,
    register_mgr: *RegisterManager,
    regname: u8,
) !Cursor {
    const reg = register_mgr.get(regname) orelse return error.InvalidRegister;
    if (reg.isEmpty()) return buffer.cursor; // Nothing to paste

    return switch (reg.motion_type) {
        .char_wise => try pasteCharWiseBefore(buffer, reg),
        .line_wise => try pasteLineWiseBefore(buffer, reg),
        .block_wise => try pasteBlockWiseBefore(buffer, reg),
    };
}

// ===== Character-wise Paste =====

/// Paste character-wise text after cursor
fn pasteCharWiseAfter(buffer: *Buffer, reg: *const YankReg) !Cursor {
    const cursor_before = buffer.cursor;

    // Single line paste
    if (reg.lines.items.len == 1) {
        return try pasteSingleLineAfter(buffer, reg.lines.items[0], cursor_before);
    }

    // Multi-line paste
    return try pasteMultiLineCharWiseAfter(buffer, reg.lines.items, cursor_before);
}

/// Paste character-wise text before cursor
fn pasteCharWiseBefore(buffer: *Buffer, reg: *const YankReg) !Cursor {
    const cursor_before = buffer.cursor;

    // Single line paste
    if (reg.lines.items.len == 1) {
        return try pasteSingleLineBefore(buffer, reg.lines.items[0], cursor_before);
    }

    // Multi-line paste
    return try pasteMultiLineCharWiseBefore(buffer, reg.lines.items, cursor_before);
}

/// Paste single line of text after cursor
fn pasteSingleLineAfter(buffer: *Buffer, text: []const u8, cursor_before: Cursor) !Cursor {
    if (text.len == 0) return cursor_before;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    // Calculate insertion offset (after cursor)
    var insert_offset = buffer.getCursorOffset();

    // Move one character forward (paste AFTER cursor)
    const line = buffer.getLine(buffer.cursor.row) orelse return cursor_before;
    // getLine returns borrowed slice from cache - no free needed
    if (buffer.cursor.col < line.len and line[buffer.cursor.col] != '\n') {
        insert_offset += 1;
    }

    // Insert the text using Rope (automatic line tracking - O(log n)!)
    try buffer.content.insert(insert_offset, text);

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Update cursor to end of pasted text
    const new_cursor = Cursor{
        .row = cursor_before.row,
        .col = cursor_before.col + 1 + text.len - 1, // +1 for 'after', -1 to land on last char
    };

    buffer.cursor = new_cursor;

    // Record change for undo
    const change = Change{
        .offset = insert_offset,
        .deleted_text = try buffer.allocator.alloc(u8, 0),
        .inserted_text = try buffer.allocator.dupe(u8, text),
        .cursor_before = cursor_before,
        .cursor_after = new_cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
    return new_cursor;
}

/// Paste single line of text before cursor
fn pasteSingleLineBefore(buffer: *Buffer, text: []const u8, cursor_before: Cursor) !Cursor {
    if (text.len == 0) return cursor_before;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    // Calculate insertion offset (at cursor)
    const insert_offset = buffer.getCursorOffset();

    // Insert the text using Rope (automatic line tracking!)
    try buffer.content.insert(insert_offset, text);

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Update cursor to end of pasted text
    const new_cursor = Cursor{
        .row = cursor_before.row,
        .col = cursor_before.col + text.len - 1, // Land on last character
    };

    buffer.cursor = new_cursor;

    // Record change for undo
    const change = Change{
        .offset = insert_offset,
        .deleted_text = try buffer.allocator.alloc(u8, 0),
        .inserted_text = try buffer.allocator.dupe(u8, text),
        .cursor_before = cursor_before,
        .cursor_after = new_cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
    return new_cursor;
}

/// Paste multi-line character-wise text after cursor
fn pasteMultiLineCharWiseAfter(buffer: *Buffer, lines: []const []const u8, cursor_before: Cursor) !Cursor {
    if (lines.len == 0) return cursor_before;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    // Get current line
    const current_line = buffer.getLine(buffer.cursor.row) orelse return cursor_before;
    // getLine returns borrowed slice from cache - no free needed

    // Calculate insertion offset (after cursor)
    var insert_offset = buffer.getCursorOffset();
    if (buffer.cursor.col < current_line.len and current_line[buffer.cursor.col] != '\n') {
        insert_offset += 1;
    }

    // Build complete text to insert (with newlines between lines)
    var total_len: usize = 0;
    for (lines) |line| {
        total_len += line.len + 1; // +1 for newline
    }
    total_len -= 1; // Last line doesn't need trailing newline

    var paste_text = try buffer.allocator.alloc(u8, total_len);
    defer buffer.allocator.free(paste_text);

    var pos: usize = 0;
    for (lines, 0..) |line, i| {
        @memcpy(paste_text[pos .. pos + line.len], line);
        pos += line.len;
        if (i < lines.len - 1) {
            paste_text[pos] = '\n';
            pos += 1;
        }
    }

    // Insert the text using Rope (automatic line tracking!)
    try buffer.content.insert(insert_offset, paste_text);

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Calculate new cursor position (end of pasted text)
    // Multi-line: cursor lands on last line at the end of last pasted text
    const lines_added = lines.len - 1;
    const new_cursor = Cursor{
        .row = cursor_before.row + lines_added,
        .col = lines[lines.len - 1].len - 1, // Last char of last line
    };

    buffer.cursor = new_cursor;

    // Record change for undo
    const change = Change{
        .offset = insert_offset,
        .deleted_text = try buffer.allocator.alloc(u8, 0),
        .inserted_text = try buffer.allocator.dupe(u8, paste_text),
        .cursor_before = cursor_before,
        .cursor_after = new_cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
    return new_cursor;
}

/// Paste multi-line character-wise text before cursor
fn pasteMultiLineCharWiseBefore(buffer: *Buffer, lines: []const []const u8, cursor_before: Cursor) !Cursor {
    if (lines.len == 0) return cursor_before;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    // Calculate insertion offset (at cursor)
    const insert_offset = buffer.getCursorOffset();

    // Build complete text to insert (with newlines between lines)
    var total_len: usize = 0;
    for (lines) |line| {
        total_len += line.len + 1; // +1 for newline
    }
    total_len -= 1; // Last line doesn't need trailing newline

    var paste_text = try buffer.allocator.alloc(u8, total_len);
    defer buffer.allocator.free(paste_text);

    var pos: usize = 0;
    for (lines, 0..) |line, i| {
        @memcpy(paste_text[pos .. pos + line.len], line);
        pos += line.len;
        if (i < lines.len - 1) {
            paste_text[pos] = '\n';
            pos += 1;
        }
    }

    // Insert the text using Rope (automatic line tracking!)
    try buffer.content.insert(insert_offset, paste_text);

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Calculate new cursor position (end of pasted text)
    // Multi-line: cursor lands on last line at the end of last pasted text
    const lines_added = lines.len - 1;
    const new_cursor = Cursor{
        .row = cursor_before.row + lines_added,
        .col = lines[lines.len - 1].len - 1, // Last char of last line
    };

    buffer.cursor = new_cursor;

    // Record change for undo
    const change = Change{
        .offset = insert_offset,
        .deleted_text = try buffer.allocator.alloc(u8, 0),
        .inserted_text = try buffer.allocator.dupe(u8, paste_text),
        .cursor_before = cursor_before,
        .cursor_after = new_cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
    return new_cursor;
}

// ===== Line-wise Paste =====

/// Paste line-wise text after current line
/// Line-wise paste inserts complete lines BELOW the current line
fn pasteLineWiseAfter(buffer: *Buffer, reg: *const YankReg) !Cursor {
    if (reg.lines.items.len == 0) return buffer.cursor;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    const cursor_before = buffer.cursor;

    // Move to end of current line
    const current_line = buffer.getLine(buffer.cursor.row) orelse return buffer.cursor;
    // getLine returns borrowed slice from cache - no free needed
    const line_end_offset = buffer.getCursorOffset() + (current_line.len - buffer.cursor.col);

    // Build text to insert (lines with newlines)
    // Each line should end with a newline
    var total_len: usize = 0;
    for (reg.lines.items) |line| {
        total_len += line.len + 1; // +1 for newline
    }

    var paste_text = try buffer.allocator.alloc(u8, total_len);
    defer buffer.allocator.free(paste_text);

    var pos: usize = 0;
    for (reg.lines.items) |line| {
        @memcpy(paste_text[pos .. pos + line.len], line);
        pos += line.len;
        paste_text[pos] = '\n';
        pos += 1;
    }

    const final_paste_text = paste_text;

    // Insert at end of current line using Rope (automatic line tracking!)
    try buffer.content.insert(line_end_offset, final_paste_text);

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Move cursor to first character of first pasted line
    const new_cursor = Cursor{
        .row = cursor_before.row + 1,
        .col = 0,
    };

    buffer.cursor = new_cursor;

    // Record change for undo
    const change = Change{
        .offset = line_end_offset,
        .deleted_text = try buffer.allocator.alloc(u8, 0),
        .inserted_text = try buffer.allocator.dupe(u8, final_paste_text),
        .cursor_before = cursor_before,
        .cursor_after = new_cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
    return new_cursor;
}

/// Paste line-wise text before current line
/// Line-wise paste inserts complete lines ABOVE the current line
fn pasteLineWiseBefore(buffer: *Buffer, reg: *const YankReg) !Cursor {
    if (reg.lines.items.len == 0) return buffer.cursor;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    const cursor_before = buffer.cursor;

    // Move to start of current line
    const line_start_offset = if (buffer.cursor.row < buffer.lineCount())
        buffer.content.byteOfLine(buffer.cursor.row)
    else
        buffer.content.len();

    // Build text to insert (lines with newlines)
    var total_len: usize = 0;
    for (reg.lines.items) |line| {
        total_len += line.len + 1; // +1 for newline
    }

    var paste_text = try buffer.allocator.alloc(u8, total_len);
    defer buffer.allocator.free(paste_text);

    var pos: usize = 0;
    for (reg.lines.items) |line| {
        @memcpy(paste_text[pos .. pos + line.len], line);
        pos += line.len;
        paste_text[pos] = '\n';
        pos += 1;
    }

    // Insert at start of current line using Rope (automatic line tracking!)
    try buffer.content.insert(line_start_offset, paste_text);

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Move cursor to first character of first pasted line (which is now at current row)
    const new_cursor = Cursor{
        .row = cursor_before.row,
        .col = 0,
    };

    buffer.cursor = new_cursor;

    // Record change for undo
    const change = Change{
        .offset = line_start_offset,
        .deleted_text = try buffer.allocator.alloc(u8, 0),
        .inserted_text = try buffer.allocator.dupe(u8, paste_text),
        .cursor_before = cursor_before,
        .cursor_after = new_cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
    return new_cursor;
}

// ===== Block-wise Paste =====

/// Paste block-wise text after cursor
/// Inserts rectangular block of text starting one column after cursor
fn pasteBlockWiseAfter(buffer: *Buffer, reg: *const YankReg) !Cursor {
    if (reg.lines.items.len == 0) return buffer.cursor;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    const cursor_before = buffer.cursor;
    const start_row = cursor_before.row;
    const start_col = cursor_before.col + 1; // Paste AFTER cursor

    // For each line in the block, insert at the same column
    var line_num: usize = 0;
    while (line_num < reg.lines.items.len) : (line_num += 1) {
        const target_row = start_row + line_num;
        const block_text = reg.lines.items[line_num];

        if (block_text.len == 0) continue; // Skip empty lines in block

        // Ensure target line exists
        while (buffer.lineCount() <= target_row) {
            const offset = buffer.content.len();
            try buffer.content.insert(offset, "\n");
        }

        const target_line = buffer.getLine(target_row) orelse continue;
        // getLine returns borrowed slice from cache - no free needed

        // Calculate offset for insertion
        const line_start_offset = buffer.content.byteOfLine(target_row);

        // If line is shorter than start_col, pad with spaces
        const line_len_without_newline = if (target_line.len > 0 and target_line[target_line.len - 1] == '\n')
            target_line.len - 1
        else
            target_line.len;

        if (start_col > line_len_without_newline) {
            // Need to pad with spaces
            const padding_needed = start_col - line_len_without_newline;
            const insert_offset = line_start_offset + line_len_without_newline;

            // Insert padding + block text
            var padded_text = try buffer.allocator.alloc(u8, padding_needed + block_text.len);
            defer buffer.allocator.free(padded_text);

            @memset(padded_text[0..padding_needed], ' ');
            @memcpy(padded_text[padding_needed..], block_text);

            try buffer.content.insert(insert_offset, padded_text);
        } else {
            // Insert at start_col
            const insert_offset = line_start_offset + start_col;
            try buffer.content.insert(insert_offset, block_text);
        }
    }

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Cursor lands at start of pasted block
    const new_cursor = Cursor{
        .row = start_row,
        .col = start_col,
    };
    buffer.cursor = new_cursor;

    buffer.modified = true;
    return new_cursor;
}

/// Paste block-wise text before cursor
/// Inserts rectangular block of text starting at cursor column
fn pasteBlockWiseBefore(buffer: *Buffer, reg: *const YankReg) !Cursor {
    if (reg.lines.items.len == 0) return buffer.cursor;

    // Invalidate external ArrayBuffers before modification
    buffer.incrementVersion();

    const cursor_before = buffer.cursor;
    const start_row = cursor_before.row;
    const start_col = cursor_before.col; // Paste AT cursor

    // For each line in the block, insert at the same column
    var line_num: usize = 0;
    while (line_num < reg.lines.items.len) : (line_num += 1) {
        const target_row = start_row + line_num;
        const block_text = reg.lines.items[line_num];

        if (block_text.len == 0) continue; // Skip empty lines in block

        // Ensure target line exists
        while (buffer.lineCount() <= target_row) {
            const offset = buffer.content.len();
            try buffer.content.insert(offset, "\n");
        }

        const target_line = buffer.getLine(target_row) orelse continue;
        // getLine returns borrowed slice from cache - no free needed

        // Calculate offset for insertion
        const line_start_offset = buffer.content.byteOfLine(target_row);

        // If line is shorter than start_col, pad with spaces
        const line_len_without_newline = if (target_line.len > 0 and target_line[target_line.len - 1] == '\n')
            target_line.len - 1
        else
            target_line.len;

        if (start_col > line_len_without_newline) {
            // Need to pad with spaces
            const padding_needed = start_col - line_len_without_newline;
            const insert_offset = line_start_offset + line_len_without_newline;

            // Insert padding + block text
            var padded_text = try buffer.allocator.alloc(u8, padding_needed + block_text.len);
            defer buffer.allocator.free(padded_text);

            @memset(padded_text[0..padding_needed], ' ');
            @memcpy(padded_text[padding_needed..], block_text);

            try buffer.content.insert(insert_offset, padded_text);
        } else {
            // Insert at start_col
            const insert_offset = line_start_offset + start_col;
            try buffer.content.insert(insert_offset, block_text);
        }
    }

    // NOTE: With Rope, line tracking is automatic - no rebuild needed!

    // Cursor lands at start of pasted block (same as before)
    const new_cursor = Cursor{
        .row = start_row,
        .col = start_col,
    };
    buffer.cursor = new_cursor;

    buffer.modified = true;
    return new_cursor;
}

// ===== Tests =====

test "paste: single line after cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/vimcraft_paste_test.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello World\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to position 5 (the space between "Hello" and "World")
    // H=0, e=1, l=2, l=3, o=4, space=5, W=6...
    buffer.moveCursorTo(0, 5);

    // Put "XXX" in register
    const text = [_][]const u8{"XXX"};
    try register_mgr.setRegister('"', &text, .char_wise);

    // Paste after cursor (inserts after the space at position 5)
    _ = try pasteAfter(&buffer, &register_mgr, '"');

    // Check result: "Hello XXXWorld\n" - XXX inserted after space, before 'W'
    const line = buffer.getLine(0).?;
    // getLine returns borrowed slice from cache - no free needed
    try std.testing.expectEqualStrings("Hello XXXWorld\n", line);

    // Check cursor position (should be on last 'X' at position 8)
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 8), buffer.cursor.col);
}

test "paste: single line before cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/vimcraft_paste_before.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello World\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to position 6 (' ' before "World")
    buffer.moveCursorTo(0, 6);

    // Put "XXX" in register
    const text = [_][]const u8{"XXX"};
    try register_mgr.setRegister('"', &text, .char_wise);

    // Paste before cursor
    _ = try pasteBefore(&buffer, &register_mgr, '"');

    // Check result: "Hello XXX World\n"
    const line = buffer.getLine(0).?;
    // getLine returns borrowed slice from cache - no free needed
    try std.testing.expectEqualStrings("Hello XXXWorld\n", line);

    // Check cursor position (should be on last 'X')
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 8), buffer.cursor.col);
}

test "paste: multi-line character-wise after cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/vimcraft_paste_multi.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Line 1\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to position 4 (the space between "Line" and "1")
    // L=0, i=1, n=2, e=3, space=4, 1=5
    buffer.moveCursorTo(0, 4);

    // Put multi-line text in register
    const text = [_][]const u8{ "AAA", "BBB" };
    try register_mgr.setRegister('"', &text, .char_wise);

    // Paste after cursor (inserts after space)
    _ = try pasteAfter(&buffer, &register_mgr, '"');

    // Check result: "Line AAA\nBBB1\n"
    // Multi-line char-wise paste: first line appends after cursor, last line
    // joins with remainder of original line (no space added)
    // Line 0: "Line AAA\n" (original "Line " + "AAA\n")
    // Line 1: "BBB1\n" ("BBB" + remaining "1\n")
    const line0 = buffer.getLine(0).?;
    // getLine returns borrowed slice from cache - no free needed
    const line1 = buffer.getLine(1).?;
    // getLine returns borrowed slice from cache - no free needed
    try std.testing.expectEqualStrings("Line AAA\n", line0);
    try std.testing.expectEqualStrings("BBB1\n", line1);

    // Check cursor position (should be on last char of last pasted line)
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col); // Last 'B'
}

test "paste: empty register returns unchanged cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/vimcraft_paste_empty.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Test\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    buffer.moveCursorTo(0, 2);
    const cursor_before = buffer.cursor;

    // Try to paste from empty register
    const cursor_after = try pasteAfter(&buffer, &register_mgr, '"');

    // Cursor should be unchanged
    try std.testing.expectEqual(cursor_before.row, cursor_after.row);
    try std.testing.expectEqual(cursor_before.col, cursor_after.col);
}

test "paste: block-wise after cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/vimcraft_paste_block_after.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abcdef\nghijkl\nmnopqr\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to column 2 on line 0
    buffer.moveCursorTo(0, 2);

    // Put block text in register (3 lines of "XXX")
    const block_text = [_][]const u8{ "XXX", "YYY", "ZZZ" };
    try register_mgr.setRegister('"', &block_text, .block_wise);

    // Paste block after cursor (should insert after column 2)
    _ = try pasteAfter(&buffer, &register_mgr, '"');

    // Check result:
    // Line 0: "abcXXXdef\n"
    // Line 1: "ghiYYYjkl\n"
    // Line 2: "mnoZZZpqr\n"
    const line0 = buffer.getLine(0).?;
    // getLine returns borrowed slice from cache - no free needed
    const line1 = buffer.getLine(1).?;
    // getLine returns borrowed slice from cache - no free needed
    const line2 = buffer.getLine(2).?;
    // getLine returns borrowed slice from cache - no free needed

    try std.testing.expectEqualStrings("abcXXXdef\n", line0);
    try std.testing.expectEqualStrings("ghiYYYjkl\n", line1);
    try std.testing.expectEqualStrings("mnoZZZpqr\n", line2);

    // Cursor should be at start of pasted block (row 0, col 3)
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor.col);
}

test "paste: block-wise before cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/vimcraft_paste_block_before.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abcdef\nghijkl\nmnopqr\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to column 2 on line 0
    buffer.moveCursorTo(0, 2);

    // Put block text in register
    const block_text = [_][]const u8{ "XXX", "YYY", "ZZZ" };
    try register_mgr.setRegister('"', &block_text, .block_wise);

    // Paste block before cursor (should insert at column 2)
    _ = try pasteBefore(&buffer, &register_mgr, '"');

    // Check result:
    // Line 0: "abXXXcdef\n"
    // Line 1: "ghYYYijkl\n"
    // Line 2: "mnZZZopqr\n"
    const line0 = buffer.getLine(0).?;
    // getLine returns borrowed slice from cache - no free needed
    const line1 = buffer.getLine(1).?;
    // getLine returns borrowed slice from cache - no free needed
    const line2 = buffer.getLine(2).?;
    // getLine returns borrowed slice from cache - no free needed

    try std.testing.expectEqualStrings("abXXXcdef\n", line0);
    try std.testing.expectEqualStrings("ghYYYijkl\n", line1);
    try std.testing.expectEqualStrings("mnZZZopqr\n", line2);

    // Cursor should be at start of pasted block (row 0, col 2)
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);
}

test "paste: block-wise with padding (short lines)" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with short lines
    const tmp_path = "/tmp/vimcraft_paste_block_pad.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("ab\ncd\nef\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to column 5 (beyond line end - gets clamped by moveCursorTo)
    // Line "ab\n" has length 2, so cursor gets clamped to col 2 (end of line)
    buffer.moveCursorTo(0, 5);

    // Put block text in register
    const block_text = [_][]const u8{ "XXX", "YYY", "ZZZ" };
    try register_mgr.setRegister('"', &block_text, .block_wise);

    // Paste block after cursor
    // cursor.col is clamped to 2, so start_col = 3 (paste AFTER cursor)
    // padding = 3 - 2 = 1 space
    _ = try pasteAfter(&buffer, &register_mgr, '"');

    // Check result - cursor was clamped, so only 1 space of padding
    // Line 0: "ab XXX\n" (1 space padding)
    // Line 1: "cd YYY\n"
    // Line 2: "ef ZZZ\n"
    const line0 = buffer.getLine(0).?;
    // getLine returns borrowed slice from cache - no free needed
    const line1 = buffer.getLine(1).?;
    // getLine returns borrowed slice from cache - no free needed
    const line2 = buffer.getLine(2).?;
    // getLine returns borrowed slice from cache - no free needed

    try std.testing.expectEqualStrings("ab XXX\n", line0);
    try std.testing.expectEqualStrings("cd YYY\n", line1);
    try std.testing.expectEqualStrings("ef ZZZ\n", line2);
}
