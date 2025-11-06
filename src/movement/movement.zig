const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const grapheme = @import("ghostty_grapheme");

/// Movement primitives for cursor navigation
/// Implements Vim-style movement commands

/// Move left (h)
pub fn moveLeft(buffer: *Buffer) void {
    if (buffer.cursor.col > 0) {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            buffer.cursor.col -= 1;
            return;
        };

        // Find the start of the current grapheme cluster by walking backwards
        var pos = buffer.cursor.col;

        // Move back one byte to start searching
        pos -= 1;
        while (pos > 0 and (line[pos] & 0b1100_0000) == 0b1000_0000) {
            pos -= 1; // Skip UTF-8 continuation bytes to find codepoint start
        }

        // Now walk backwards through codepoints until we find a grapheme break
        var state: grapheme.BreakState = .{};
        var cluster_start = pos;

        while (cluster_start > 0) {
            // Find previous codepoint start
            var prev_pos = cluster_start - 1;
            while (prev_pos > 0 and (line[prev_pos] & 0b1100_0000) == 0b1000_0000) {
                prev_pos -= 1;
            }

            // Decode both codepoints
            const cp1 = std.unicode.utf8Decode(line[prev_pos..cluster_start]) catch break;

            const curr_len = std.unicode.utf8ByteSequenceLength(line[cluster_start]) catch break;
            if (cluster_start + curr_len > line.len) break;
            const cp2 = std.unicode.utf8Decode(line[cluster_start..][0..curr_len]) catch break;

            // Check for grapheme break
            if (grapheme.graphemeBreak(cp1, cp2, &state)) {
                break; // Found a break, cluster starts here
            }

            // No break, this codepoint is part of the cluster
            cluster_start = prev_pos;
        }

        buffer.cursor.col = cluster_start;
    }
}

/// Move right (l)
pub fn moveRight(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;
    const line_len = buffer.getLineLength(buffer.cursor.row);

    if (line_len > 0 and buffer.cursor.col < line_len - 1) {
        var pos = buffer.cursor.col;
        var state: grapheme.BreakState = .{};

        // Skip the first UTF-8 character
        var prev_start = pos;
        const first_len = std.unicode.utf8ByteSequenceLength(line[pos]) catch 1;
        pos += first_len;

        // Keep going until we find a grapheme break
        while (pos < line_len - 1) {
            // Decode previous codepoint (from prev_start to pos)
            const cp1 = std.unicode.utf8Decode(line[prev_start..pos]) catch break;

            // Decode current codepoint
            const curr_len = std.unicode.utf8ByteSequenceLength(line[pos]) catch break;
            if (pos + curr_len > line_len) break;
            const cp2 = std.unicode.utf8Decode(line[pos..][0..curr_len]) catch break;

            // Check for grapheme break
            if (grapheme.graphemeBreak(cp1, cp2, &state)) {
                break; // Found a break, stop here
            }

            // No break, update prev_start and keep going
            prev_start = pos;
            pos += curr_len;
        }

        buffer.cursor.col = @min(pos, line_len - 1);
    }
}

/// Move up (k)
pub fn moveUp(buffer: *Buffer) void {
    if (buffer.cursor.row > 0) {
        buffer.cursor.row -= 1;
        // Clamp column to new line length
        const line_len = buffer.getLineLength(buffer.cursor.row);
        if (line_len > 0 and buffer.cursor.col >= line_len) {
            buffer.cursor.col = line_len - 1;
        }
    }
}

/// Move down (j)
pub fn moveDown(buffer: *Buffer) void {
    if (buffer.cursor.row + 1 < buffer.lineCount()) {
        buffer.cursor.row += 1;
        // Clamp column to new line length
        const line_len = buffer.getLineLength(buffer.cursor.row);
        if (line_len > 0 and buffer.cursor.col >= line_len) {
            buffer.cursor.col = line_len - 1;
        }
    }
}

/// Move to start of line (0)
pub fn moveToLineStart(buffer: *Buffer) void {
    buffer.cursor.col = 0;
}

/// Move to end of line ($)
pub fn moveToLineEnd(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse {
        buffer.cursor.col = 0;
        return;
    };

    // Get visual length (exclude newline)
    const visual_len = if (line.len > 0 and line[line.len - 1] == '\n')
        line.len - 1
    else
        line.len;

    if (visual_len > 0) {
        buffer.cursor.col = visual_len - 1;
    } else {
        buffer.cursor.col = 0;
    }
}

/// Move to first non-blank character of line (^)
pub fn moveToFirstNonBlank(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;

    for (line, 0..) |char, i| {
        if (char != ' ' and char != '\t') {
            buffer.cursor.col = i;
            return;
        }
    }

    // Line is all whitespace, move to start
    buffer.cursor.col = 0;
}

/// Move to top of file (gg)
pub fn moveToFileStart(buffer: *Buffer) void {
    buffer.cursor.row = 0;
    buffer.cursor.col = 0;
}

/// Move to bottom of file (G)
pub fn moveToFileEnd(buffer: *Buffer) void {
    if (buffer.lineCount() > 0) {
        buffer.cursor.row = buffer.lineCount() - 1;
        moveToLineEnd(buffer);
    }
}

/// Check if character is word constituent
fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '_';
}

/// Move to next word start (w)
pub fn moveWordForward(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;

    var col = buffer.cursor.col;

    // Skip current word
    while (col < line.len and isWordChar(line[col])) {
        col += 1;
    }

    // Skip whitespace
    while (col < line.len and !isWordChar(line[col])) {
        col += 1;
    }

    // If we reached end of line, move to next line
    if (col >= line.len) {
        if (buffer.cursor.row + 1 < buffer.lineCount()) {
            buffer.cursor.row += 1;
            buffer.cursor.col = 0;
            moveToFirstNonBlank(buffer);
        } else {
            buffer.cursor.col = if (line.len > 0) line.len - 1 else 0;
        }
    } else {
        buffer.cursor.col = col;
    }
}

/// Move to previous word start (b)
pub fn moveWordBackward(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;

    if (buffer.cursor.col == 0) {
        // Move to previous line
        if (buffer.cursor.row > 0) {
            buffer.cursor.row -= 1;
            moveToLineEnd(buffer);
        }
        return;
    }

    var col = buffer.cursor.col;

    // Move back one character
    col -= 1;

    // Skip whitespace
    while (col > 0 and !isWordChar(line[col])) {
        col -= 1;
    }

    // Skip word characters to find start of word
    while (col > 0 and isWordChar(line[col])) {
        col -= 1;
    }

    // If we stopped on non-word char, move forward one
    if (!isWordChar(line[col]) and col < line.len - 1) {
        col += 1;
    }

    buffer.cursor.col = col;
}

/// Move to word end (e)
pub fn moveWordEnd(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;

    var col = buffer.cursor.col;

    // Move forward one to start search
    if (col < line.len - 1) {
        col += 1;
    }

    // Skip whitespace
    while (col < line.len and !isWordChar(line[col])) {
        col += 1;
    }

    // Move to end of word
    while (col < line.len and isWordChar(line[col])) {
        col += 1;
    }

    // Move back to last word character
    if (col > 0) {
        col -= 1;
    }

    if (col >= line.len) {
        col = if (line.len > 0) line.len - 1 else 0;
    }

    buffer.cursor.col = col;
}

/// Scroll half page down (Ctrl+D)
pub fn scrollHalfPageDown(buffer: *Buffer, viewport_height: usize) void {
    const half = viewport_height / 2;
    const new_row = @min(buffer.cursor.row + half, buffer.lineCount() -| 1);
    buffer.cursor.row = new_row;

    // Clamp column
    const line_len = buffer.getLineLength(buffer.cursor.row);
    if (line_len > 0 and buffer.cursor.col >= line_len) {
        buffer.cursor.col = line_len - 1;
    }
}

/// Scroll half page up (Ctrl+U)
pub fn scrollHalfPageUp(buffer: *Buffer, viewport_height: usize) void {
    const half = viewport_height / 2;
    buffer.cursor.row -|= half;

    // Clamp column
    const line_len = buffer.getLineLength(buffer.cursor.row);
    if (line_len > 0 and buffer.cursor.col >= line_len) {
        buffer.cursor.col = line_len - 1;
    }
}

// Tests
test "Movement: basic hjkl" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Create test file
    const tmp_path = "/tmp/openvim_test_movement.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abc\ndef\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Test right movement
    moveRight(&buffer);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    moveRight(&buffer);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);

    // Test down movement
    moveDown(&buffer);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);

    // Test left movement
    moveLeft(&buffer);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // Test up movement
    moveUp(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
}

test "Movement: line start/end" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/openvim_test_line.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("hello world\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Move to end
    moveToLineEnd(&buffer);
    try std.testing.expectEqual(@as(usize, 10), buffer.cursor.col); // 'd' position

    // Move to start
    moveToLineStart(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);
}

test "Movement: word forward/backward" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/openvim_test_word.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("hello world test\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Move forward through words
    moveWordForward(&buffer);
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor.col); // 'w' in "world"

    moveWordForward(&buffer);
    try std.testing.expectEqual(@as(usize, 12), buffer.cursor.col); // 't' in "test"

    // Move backward
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor.col); // back to 'w'

    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col); // back to 'h'
}
