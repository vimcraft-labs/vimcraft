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

    // Calculate insertion offset (after cursor)
    var insert_offset = buffer.getCursorOffset();

    // Move one character forward (paste AFTER cursor)
    const line = buffer.getLine(buffer.cursor.row) orelse return cursor_before;
    if (buffer.cursor.col < line.len and line[buffer.cursor.col] != '\n') {
        insert_offset += 1;
    }

    // Insert the text
    try buffer.content.insertSlice(buffer.allocator, insert_offset, text);

    // Rebuild line index
    try buffer.buildLineIndex();

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

    // Calculate insertion offset (at cursor)
    const insert_offset = buffer.getCursorOffset();

    // Insert the text
    try buffer.content.insertSlice(buffer.allocator, insert_offset, text);

    // Rebuild line index
    try buffer.buildLineIndex();

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

    // Get current line
    const current_line = buffer.getLine(buffer.cursor.row) orelse return cursor_before;

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

    // Insert the text
    try buffer.content.insertSlice(buffer.allocator, insert_offset, paste_text);

    // Rebuild line index (multi-line paste requires full rebuild)
    try buffer.buildLineIndex();

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

    // Insert the text
    try buffer.content.insertSlice(buffer.allocator, insert_offset, paste_text);

    // Rebuild line index (multi-line paste requires full rebuild)
    try buffer.buildLineIndex();

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

    const cursor_before = buffer.cursor;

    // Move to end of current line
    const current_line = buffer.getLine(buffer.cursor.row) orelse return buffer.cursor;
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

    // Insert at end of current line
    try buffer.content.insertSlice(buffer.allocator, line_end_offset, final_paste_text);

    // Rebuild line index
    try buffer.buildLineIndex();

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

    const cursor_before = buffer.cursor;

    // Move to start of current line
    const line_start_offset = if (buffer.cursor.row < buffer.line_starts.items.len)
        buffer.line_starts.items[buffer.cursor.row]
    else
        buffer.content.items.len;

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

    // Insert at start of current line
    try buffer.content.insertSlice(buffer.allocator, line_start_offset, paste_text);

    // Rebuild line index
    try buffer.buildLineIndex();

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

// ===== Block-wise Paste (Stubs for Week 5) =====

/// Paste block-wise text after cursor
fn pasteBlockWiseAfter(_: *Buffer, _: *const YankReg) !Cursor {
    // TODO: Week 5
    return error.NotImplemented;
}

/// Paste block-wise text before cursor
fn pasteBlockWiseBefore(_: *Buffer, _: *const YankReg) !Cursor {
    // TODO: Week 5
    return error.NotImplemented;
}

// ===== Tests =====

test "paste: single line after cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/openvim_paste_test.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello World\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to position 5 ('o' in "Hello")
    buffer.moveCursorTo(0, 5);

    // Put "XXX" in register
    const text = [_][]const u8{"XXX"};
    try register_mgr.setRegister('"', &text, .char_wise);

    // Paste after cursor (should insert after 'o')
    _ = try pasteAfter(&buffer, &register_mgr, '"');

    // Check result: "Hello XXXWorld\n"
    const line = buffer.getLine(0).?;
    try std.testing.expectEqualStrings("HelloXXX World\n", line);

    // Check cursor position (should be on last 'X')
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 8), buffer.cursor.col); // Position of last X
}

test "paste: single line before cursor" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create buffer with content
    const tmp_path = "/tmp/openvim_paste_before.txt";
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
    const tmp_path = "/tmp/openvim_paste_multi.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Line 1\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Set cursor to position 4 ('e' in "Line")
    buffer.moveCursorTo(0, 4);

    // Put multi-line text in register
    const text = [_][]const u8{ "AAA", "BBB" };
    try register_mgr.setRegister('"', &text, .char_wise);

    // Paste after cursor
    _ = try pasteAfter(&buffer, &register_mgr, '"');

    // Check result: "Line AAA\nBBB 1\n"
    // Line 0: "Line AAA\n"
    // Line 1: "BBB 1\n"
    const line0 = buffer.getLine(0).?;
    const line1 = buffer.getLine(1).?;
    try std.testing.expectEqualStrings("Line AAA\n", line0);
    try std.testing.expectEqualStrings("BBB 1\n", line1);

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
    const tmp_path = "/tmp/openvim_paste_empty.txt";
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
