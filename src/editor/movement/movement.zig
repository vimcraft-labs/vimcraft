const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const grapheme = @import("ghostty_grapheme");

/// Movement primitives for cursor navigation
/// Implements Vim-style movement commands
/// Move left (h)
/// Returns true if cursor moved, false if already at boundary
pub fn moveLeft(buffer: *Buffer) bool {
    if (buffer.cursor.col > 0) {
        const line = buffer.getLine(buffer.cursor.row) orelse {
            buffer.cursor.col -= 1;
            buffer.cursor.goal_column = buffer.cursor.col;
            return true;
        };
        defer buffer.allocator.free(line);

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
        buffer.cursor.goal_column = buffer.cursor.col;
        return true;
    }
    return false; // Already at left boundary
}

/// Move right (l)
/// Returns true if cursor moved, false if already at boundary
/// In normal mode, cursor stops ON the last character (not after it)
pub fn moveRight(buffer: *Buffer) bool {
    const line = buffer.getLine(buffer.cursor.row) orelse return false;
    defer buffer.allocator.free(line);
    // Use visual length (excludes newline) - Vim behavior: cursor stops ON last char in normal mode
    const visual_len = buffer.getLineLengthVisual(buffer.cursor.row);

    if (visual_len > 0 and buffer.cursor.col < visual_len - 1) {
        var pos = buffer.cursor.col;
        var state: grapheme.BreakState = .{};

        // Skip the first UTF-8 character
        var prev_start = pos;
        const first_len = std.unicode.utf8ByteSequenceLength(line[pos]) catch 1;
        pos += first_len;

        // Keep going until we find a grapheme break (but don't go past last visible char)
        while (pos < visual_len - 1) {
            // Decode previous codepoint (from prev_start to pos)
            const cp1 = std.unicode.utf8Decode(line[prev_start..pos]) catch break;

            // Decode current codepoint
            const curr_len = std.unicode.utf8ByteSequenceLength(line[pos]) catch break;
            if (pos + curr_len > visual_len) break;
            const cp2 = std.unicode.utf8Decode(line[pos..][0..curr_len]) catch break;

            // Check for grapheme break
            if (grapheme.graphemeBreak(cp1, cp2, &state)) {
                break; // Found a break, stop here
            }

            // No break, update prev_start and keep going
            prev_start = pos;
            pos += curr_len;
        }

        buffer.cursor.col = @min(pos, visual_len - 1);
        buffer.cursor.goal_column = buffer.cursor.col;
        return true;
    }
    return false; // Already at right boundary
}

/// Move right for INSERT MODE - allows cursor to go AFTER last character
/// This is the Vim behavior: in insert mode, cursor can be at position visual_len (after last char)
/// Returns true if cursor moved, false if already at boundary
pub fn moveRightInsert(buffer: *Buffer) bool {
    // In insert mode, cursor can go up to visual_len (AFTER last visible char)
    const visual_len = buffer.getLineLengthVisual(buffer.cursor.row);

    // Can move if cursor is before the end position (visual_len)
    if (buffer.cursor.col < visual_len) {
        buffer.cursor.col += 1;
        buffer.cursor.goal_column = buffer.cursor.col;
        return true;
    }
    return false; // Already at right boundary (after last char)
}

/// Clamp cursor to valid position for NORMAL mode
/// Call this when exiting insert mode to ensure cursor is ON a character, not after
pub fn clampCursorForNormalMode(buffer: *Buffer) void {
    const visual_len = buffer.getLineLengthVisual(buffer.cursor.row);
    if (visual_len == 0) {
        buffer.cursor.col = 0;
    } else if (buffer.cursor.col >= visual_len) {
        // Cursor is past last char, move it back to last char
        buffer.cursor.col = visual_len - 1;
    }
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Move up (k)
/// Returns true if cursor moved, false if already at boundary
pub fn moveUp(buffer: *Buffer) bool {
    if (buffer.cursor.row > 0) {
        // Set goal column to current column if not already set
        if (buffer.cursor.goal_column == null) {
            buffer.cursor.goal_column = buffer.cursor.col;
        }

        buffer.cursor.row -= 1;

        // Try to restore goal column, but clamp to line length
        const goal = buffer.cursor.goal_column.?;
        const line_len = buffer.getLineLength(buffer.cursor.row);
        const visual_len = if (line_len > 0) line_len - 1 else 0; // Exclude newline

        if (visual_len == 0) {
            // Empty line
            buffer.cursor.col = 0;
        } else if (goal < visual_len) {
            // Can restore goal column
            buffer.cursor.col = goal;
        } else {
            // Line is shorter, move to end but keep goal column
            buffer.cursor.col = visual_len;
        }
        return true;
    }
    return false; // Already at top
}

/// Move down (j)
/// Returns true if cursor moved, false if already at boundary
pub fn moveDown(buffer: *Buffer) bool {
    if (buffer.cursor.row + 1 < buffer.lineCount()) {
        // Set goal column to current column if not already set
        if (buffer.cursor.goal_column == null) {
            buffer.cursor.goal_column = buffer.cursor.col;
        }

        buffer.cursor.row += 1;

        // Try to restore goal column, but clamp to line length
        const goal = buffer.cursor.goal_column.?;
        const line_len = buffer.getLineLength(buffer.cursor.row);
        const visual_len = if (line_len > 0) line_len - 1 else 0; // Exclude newline

        if (visual_len == 0) {
            // Empty line
            buffer.cursor.col = 0;
        } else if (goal < visual_len) {
            // Can restore goal column
            buffer.cursor.col = goal;
        } else {
            // Line is shorter, move to end but keep goal column
            buffer.cursor.col = visual_len;
        }
        return true;
    }
    return false; // Already at bottom
}

/// Move to start of line (0)
pub fn moveToLineStart(buffer: *Buffer) void {
    buffer.cursor.col = 0;
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Move to end of line ($)
pub fn moveToLineEnd(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse {
        buffer.cursor.col = 0;
        buffer.cursor.goal_column = buffer.cursor.col;
        return;
    };
    defer buffer.allocator.free(line);

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
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Move to first non-blank character of line (^)
pub fn moveToFirstNonBlank(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;
    defer buffer.allocator.free(line);

    for (line, 0..) |char, i| {
        if (char != ' ' and char != '\t') {
            buffer.cursor.col = i;
            buffer.cursor.goal_column = buffer.cursor.col;
            return;
        }
    }

    // Line is all whitespace, move to start
    buffer.cursor.col = 0;
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Move to top of file (gg)
pub fn moveToFileStart(buffer: *Buffer) void {
    buffer.cursor.row = 0;
    buffer.cursor.col = 0;
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Move to bottom of file (G)
pub fn moveToFileEnd(buffer: *Buffer) void {
    if (buffer.lineCount() > 0) {
        buffer.cursor.row = buffer.lineCount() - 1;
        moveToLineEnd(buffer); // This already sets goal_column
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
    defer buffer.allocator.free(line);

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
            moveToFirstNonBlank(buffer); // This already sets goal_column
        } else {
            buffer.cursor.col = if (line.len > 0) line.len - 1 else 0;
            buffer.cursor.goal_column = buffer.cursor.col;
        }
    } else {
        buffer.cursor.col = col;
        buffer.cursor.goal_column = buffer.cursor.col;
    }
}

/// Move to previous word start (b)
pub fn moveWordBackward(buffer: *Buffer) void {
    // If at start of line, wrap to end of previous line
    if (buffer.cursor.col == 0) {
        if (buffer.cursor.row > 0) {
            buffer.cursor.row -= 1;
            moveToLineEnd(buffer);
            // Continue searching backward from end of previous line
            // (don't return - fall through to word search logic)
        } else {
            // At start of buffer, can't move back
            return;
        }
    }

    const line = buffer.getLine(buffer.cursor.row) orelse return;
    defer buffer.allocator.free(line);

    // Handle case where we're already at column 0 after line wrap
    if (buffer.cursor.col == 0) {
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

    // If we stopped on non-word char (and not at start of line), move forward one
    // Don't increment if col == 0, as that's the beginning of the line
    if (col > 0 and !isWordChar(line[col]) and col < line.len - 1) {
        col += 1;
    }

    buffer.cursor.col = col;
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Move to word end (e)
pub fn moveWordEnd(buffer: *Buffer) void {
    const line = buffer.getLine(buffer.cursor.row) orelse return;
    defer buffer.allocator.free(line);

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
    buffer.cursor.goal_column = buffer.cursor.col;
}

/// Scroll half page down (Ctrl+D)
pub fn scrollHalfPageDown(buffer: *Buffer, viewport_height: usize) void {
    // Set goal column to current column if not already set
    if (buffer.cursor.goal_column == null) {
        buffer.cursor.goal_column = buffer.cursor.col;
    }

    const half = viewport_height / 2;
    const new_row = @min(buffer.cursor.row + half, buffer.lineCount() -| 1);
    buffer.cursor.row = new_row;

    // Try to restore goal column, but clamp to line length
    const goal = buffer.cursor.goal_column.?;
    const line_len = buffer.getLineLength(buffer.cursor.row);
    const visual_len = if (line_len > 0) line_len - 1 else 0; // Exclude newline

    if (visual_len == 0) {
        buffer.cursor.col = 0;
    } else if (goal < visual_len) {
        buffer.cursor.col = goal;
    } else {
        buffer.cursor.col = visual_len;
    }
}

/// Restore cursor to goal column (sticky column), clamped to line length
/// Used when 'startofline' is off to preserve horizontal cursor position
fn restoreGoalColumn(buffer: *Buffer) void {
    const goal = buffer.cursor.goal_column orelse buffer.cursor.col;
    const line_len = buffer.getLineLength(buffer.cursor.row);
    const visual_len = if (line_len > 0) line_len - 1 else 0; // Exclude newline

    if (visual_len == 0) {
        buffer.cursor.col = 0;
    } else if (goal < visual_len) {
        buffer.cursor.col = goal;
    } else {
        // Clamp to last valid position in normal mode (visual_len - 1)
        buffer.cursor.col = visual_len - 1;
    }
}

/// Scroll half page up (Ctrl+U)
pub fn scrollHalfPageUp(buffer: *Buffer, viewport_height: usize) void {
    // Set goal column to current column if not already set
    if (buffer.cursor.goal_column == null) {
        buffer.cursor.goal_column = buffer.cursor.col;
    }

    const half = viewport_height / 2;
    buffer.cursor.row -|= half;

    // Try to restore goal column, but clamp to line length
    const goal = buffer.cursor.goal_column.?;
    const line_len = buffer.getLineLength(buffer.cursor.row);
    const visual_len = if (line_len > 0) line_len - 1 else 0; // Exclude newline

    if (visual_len == 0) {
        buffer.cursor.col = 0;
    } else if (goal < visual_len) {
        buffer.cursor.col = goal;
    } else {
        buffer.cursor.col = visual_len;
    }
}

/// Move to top of viewport (H - High)
/// If start_of_line is true, moves cursor to first non-blank character (Vim default)
/// If start_of_line is false, preserves the "sticky column" position (modern preference)
pub fn moveToViewportTop(buffer: *Buffer, viewport_top: usize, start_of_line: bool) void {
    // Set goal column if not already set (for preserving sticky column)
    if (buffer.cursor.goal_column == null) {
        buffer.cursor.goal_column = buffer.cursor.col;
    }

    buffer.cursor.row = viewport_top;

    if (start_of_line) {
        moveToFirstNonBlank(buffer);
    } else {
        // Restore goal column, clamped to line length
        restoreGoalColumn(buffer);
    }
}

/// Move to middle of viewport (M - Middle)
/// If start_of_line is true, moves cursor to first non-blank character (Vim default)
/// If start_of_line is false, preserves the "sticky column" position (modern preference)
pub fn moveToViewportMiddle(buffer: *Buffer, viewport_top: usize, viewport_height: usize, start_of_line: bool) void {
    // Set goal column if not already set (for preserving sticky column)
    if (buffer.cursor.goal_column == null) {
        buffer.cursor.goal_column = buffer.cursor.col;
    }

    const middle = viewport_top + (viewport_height / 2);
    buffer.cursor.row = @min(middle, buffer.lineCount() -| 1);

    if (start_of_line) {
        moveToFirstNonBlank(buffer);
    } else {
        restoreGoalColumn(buffer);
    }
}

/// Move to bottom of viewport (L - Low)
/// If start_of_line is true, moves cursor to first non-blank character (Vim default)
/// If start_of_line is false, preserves the "sticky column" position (modern preference)
pub fn moveToViewportBottom(buffer: *Buffer, viewport_top: usize, viewport_height: usize, start_of_line: bool) void {
    // Set goal column if not already set (for preserving sticky column)
    if (buffer.cursor.goal_column == null) {
        buffer.cursor.goal_column = buffer.cursor.col;
    }

    // Calculate bottom line (viewport_top + height - 1, clamped to buffer end)
    // CRITICAL: Use saturating addition to prevent overflow when viewport_top is huge
    const bottom = (viewport_top +| viewport_height) -| 1;
    buffer.cursor.row = @min(bottom, buffer.lineCount() -| 1);

    if (start_of_line) {
        moveToFirstNonBlank(buffer);
    } else {
        restoreGoalColumn(buffer);
    }
}

/// Center current line in viewport (zz)
/// Returns the new viewport_top position
pub fn centerLineInViewport(cursor_row: usize, viewport_height: usize, buffer_line_count: usize) usize {
    const half_height = viewport_height / 2;

    // Try to center the cursor line
    if (cursor_row >= half_height) {
        const new_top = cursor_row - half_height;
        // Make sure we don't scroll past the end
        const max_top = if (buffer_line_count > viewport_height)
            buffer_line_count - viewport_height
        else
            0;
        return @min(new_top, max_top);
    }

    // Cursor is in the first half of the file, show from top
    return 0;
}

/// Move current line to top of viewport (zt)
/// Returns the new viewport_top position
pub fn moveLineToViewportTop(cursor_row: usize, buffer_line_count: usize, viewport_height: usize) usize {
    _ = viewport_height;
    _ = buffer_line_count;
    return cursor_row;
}

/// Move current line to bottom of viewport (zb)
/// Returns the new viewport_top position
pub fn moveLineToViewportBottom(cursor_row: usize, viewport_height: usize, buffer_line_count: usize) usize {
    // Try to position cursor line at bottom
    if (cursor_row + 1 >= viewport_height) {
        const new_top = (cursor_row + 1) - viewport_height;
        // Make sure we don't scroll past the end
        const max_top = if (buffer_line_count > viewport_height)
            buffer_line_count - viewport_height
        else
            0;
        return @min(new_top, max_top);
    }

    // File is too short, show from top
    return 0;
}

// Tests
test "Movement: basic hjkl" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Create test file
    const tmp_path = "/tmp/vimcraft_test_movement.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abc\ndef\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Test right movement
    try std.testing.expect(moveRight(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    try std.testing.expect(moveRight(&buffer));
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);

    // Test down movement
    try std.testing.expect(moveDown(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);

    // Test left movement
    try std.testing.expect(moveLeft(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // Test up movement
    try std.testing.expect(moveUp(&buffer));
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
}

test "Movement: line start/end" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_line.txt";
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

    const tmp_path = "/tmp/vimcraft_test_word.txt";
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

test "Movement: 'b' wraps to previous line and finds word start" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_b_wrap.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("hello world\ntest line\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 1, col 0 (at 't' in "test")
    buffer.cursor.row = 1;
    buffer.cursor.col = 0;

    // Press 'b' - should wrap to previous line and find start of "world"
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor.col); // 'w' in "world"

    // Press 'b' again - should find start of "hello"
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col); // 'h' in "hello"

    // Press 'b' again at start of buffer - should stay at (0, 0)
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);
}

test "Movement: 'b' handles line starting with non-word characters" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_b_punct.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("  hello world\ntest\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 1, col 0
    buffer.cursor.row = 1;
    buffer.cursor.col = 0;

    // Press 'b' - should wrap to previous line and find "world"
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 8), buffer.cursor.col); // 'w' in "world"

    // Press 'b' - should find "hello" (skip leading spaces)
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col); // 'h' in "hello"

    // Press 'b' - should go to start of line (col 0) even though it's a space
    moveWordBackward(&buffer);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col); // Should be at col 0, not stuck at col 1
}

test "Movement: 'l' stops ON last character (Vim normal mode behavior)" {
    // This test verifies the fix for cursor going past the last character.
    // In Vim normal mode, the cursor should stop ON the last character, not AFTER it.
    // For line "abc\n", cursor can be at 0='a', 1='b', 2='c' (NOT 3=newline)
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_cursor_boundary.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abc\n"); // 3 chars + newline
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at column 0 (on 'a')
    buffer.cursor.col = 0;

    // Move right to 'b' (col 1)
    try std.testing.expect(moveRight(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // Move right to 'c' (col 2) - this is the last visible character
    try std.testing.expect(moveRight(&buffer));
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);

    // Try to move right again - should FAIL (already at last char)
    // This is the key fix: cursor should NOT move past 'c' to the newline
    try std.testing.expect(!moveRight(&buffer)); // Returns false = couldn't move
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col); // Still on 'c'
}

test "Movement: moveRightInsert allows cursor AFTER last character (insert mode)" {
    // In insert mode, cursor CAN go after the last character (for appending)
    // For line "abc\n", cursor can be at 0='a', 1='b', 2='c', 3=after 'c'
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_insert_cursor.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abc\n"); // 3 chars + newline
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);
    buffer.cursor.col = 0;

    // Move through all characters
    try std.testing.expect(moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col); // on 'b'

    try std.testing.expect(moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col); // on 'c'

    // In insert mode, can move PAST 'c' (the key difference from normal mode!)
    try std.testing.expect(moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor.col); // AFTER 'c'

    // Now at end, can't move further
    try std.testing.expect(!moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor.col); // Still after 'c'
}

test "Movement: normal vs insert mode cursor boundary comparison" {
    // This test demonstrates the key difference between normal and insert mode
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_mode_comparison.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("xy\n"); // 2 chars + newline, visual_len = 2
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // NORMAL MODE: max position is 1 (on 'y')
    buffer.cursor.col = 0;
    try std.testing.expect(moveRight(&buffer)); // 0 -> 1
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);
    try std.testing.expect(!moveRight(&buffer)); // Cannot go past 'y'
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // INSERT MODE: max position is 2 (after 'y')
    buffer.cursor.col = 0;
    try std.testing.expect(moveRightInsert(&buffer)); // 0 -> 1
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);
    try std.testing.expect(moveRightInsert(&buffer)); // 1 -> 2 (AFTER 'y')
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);
    try std.testing.expect(!moveRightInsert(&buffer)); // Cannot go past position 2
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);
}

test "Movement: empty line handling" {
    // Empty lines should handle cursor position correctly
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_empty_line.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("\n"); // Just a newline (empty line)
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);
    buffer.cursor.col = 0;

    // On empty line, neither normal nor insert mode should move right
    try std.testing.expect(!moveRight(&buffer));
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);

    try std.testing.expect(!moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);
}

test "Movement: single character line" {
    // Single char line: "a\n" -> visual_len = 1
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_single_char.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("a\n"); // 1 char + newline
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);
    buffer.cursor.col = 0;

    // NORMAL MODE: Already on last char, can't move right
    try std.testing.expect(!moveRight(&buffer));
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);

    // INSERT MODE: Can move to position 1 (after 'a')
    try std.testing.expect(moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // Can't go further
    try std.testing.expect(!moveRightInsert(&buffer));
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);
}

test "Movement: line without trailing newline (last line of file)" {
    // Last line might not have newline: "abc" -> visual_len = 3
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_no_newline.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abc"); // NO trailing newline
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);
    buffer.cursor.col = 0;

    // NORMAL MODE: max position is 2 (on 'c')
    try std.testing.expect(moveRight(&buffer)); // 0 -> 1
    try std.testing.expect(moveRight(&buffer)); // 1 -> 2
    try std.testing.expect(!moveRight(&buffer)); // Cannot go past 'c'
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor.col);

    // INSERT MODE: max position is 3 (after 'c')
    buffer.cursor.col = 2;
    try std.testing.expect(moveRightInsert(&buffer)); // 2 -> 3
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor.col);
    try std.testing.expect(!moveRightInsert(&buffer)); // Cannot go past 3
}

test "Movement: $ (moveToLineEnd) stops ON last char" {
    // $ command in normal mode should stop ON last character
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_dollar.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("hello\n"); // 5 chars + newline
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);
    buffer.cursor.col = 0;

    moveToLineEnd(&buffer);
    // Should be on 'o' (position 4), not after it (position 5)
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.col);
}

test "Movement: cursor boundary with multiple lines" {
    // Test that cursor boundary works correctly across multiple lines
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_multiline.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("ab\ncd\nef\n"); // 3 lines of 2 chars each
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Line 0: "ab\n" -> visual_len = 2, max normal pos = 1
    buffer.cursor.row = 0;
    buffer.cursor.col = 0;
    try std.testing.expect(moveRight(&buffer)); // 0 -> 1
    try std.testing.expect(!moveRight(&buffer)); // Can't go past 'b'
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // Line 1: "cd\n" -> same behavior
    buffer.cursor.row = 1;
    buffer.cursor.col = 0;
    try std.testing.expect(moveRight(&buffer)); // 0 -> 1
    try std.testing.expect(!moveRight(&buffer)); // Can't go past 'd'
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);

    // Line 2: "ef\n" -> same behavior
    buffer.cursor.row = 2;
    buffer.cursor.col = 0;
    try std.testing.expect(moveRight(&buffer)); // 0 -> 1
    try std.testing.expect(!moveRight(&buffer)); // Can't go past 'f'
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.col);
}

// ============================================================================
// startofline Option Tests (H/M/L viewport movement)
// ============================================================================

test "Viewport H: startofline=false preserves sticky column" {
    // When startofline is OFF (default), H should preserve the horizontal cursor position
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_h_startofline.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        // 20 lines with varying indentation
        try file.writeAll(
            \\    first line with indent
            \\    second line
            \\third line no indent
            \\    fourth line
            \\fifth
            \\    sixth line
            \\seventh line
            \\    eighth line
            \\ninth line
            \\    tenth line
            \\eleventh
            \\    twelfth line
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 5, column 10 (in the middle of "sixth line")
    buffer.cursor.row = 5;
    buffer.cursor.col = 10;
    buffer.cursor.goal_column = 10; // Set sticky column

    // Press H (viewport top) with startofline=false
    const viewport_top: usize = 0;
    moveToViewportTop(&buffer, viewport_top, false);

    // Should be on row 0, but column should be preserved (clamped to line length)
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    // "    first line with indent" has 25 chars, col 10 is preserved
    try std.testing.expectEqual(@as(usize, 10), buffer.cursor.col);
}

test "Viewport H: startofline=true moves to first non-blank" {
    // When startofline is ON, H should move to first non-blank character
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_h_sol_true.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\    first line with indent
            \\second line
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 1, column 5
    buffer.cursor.row = 1;
    buffer.cursor.col = 5;
    buffer.cursor.goal_column = 5;

    // Press H with startofline=true
    moveToViewportTop(&buffer, 0, true);

    // Should be on row 0, column 4 (first non-blank, after 4 spaces)
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.col);
}

test "Viewport L: startofline=false preserves sticky column" {
    // When startofline is OFF, L should preserve the horizontal cursor position
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_l_startofline.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\first line
            \\second line
            \\third line
            \\fourth line
            \\    fifth with indent
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 0, column 5 (on 'l' in "first line")
    buffer.cursor.row = 0;
    buffer.cursor.col = 5;
    buffer.cursor.goal_column = 5;

    // Press L (viewport bottom) with startofline=false
    // viewport_top=0, viewport_height=10 -> bottom = min(9, 4) = 4
    moveToViewportBottom(&buffer, 0, 10, false);

    // Should be on row 4, column 5 preserved
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 5), buffer.cursor.col);
}

test "Viewport L: startofline=true moves to first non-blank" {
    // When startofline is ON, L should move to first non-blank character
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_l_sol_true.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\first line
            \\second line
            \\third line
            \\fourth line
            \\    fifth with indent
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 0, column 5
    buffer.cursor.row = 0;
    buffer.cursor.col = 5;
    buffer.cursor.goal_column = 5;

    // Press L with startofline=true
    moveToViewportBottom(&buffer, 0, 10, true);

    // Should be on row 4, column 4 (first non-blank after 4 spaces)
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.col);
}

test "Viewport M: startofline=false preserves sticky column" {
    // When startofline is OFF, M should preserve the horizontal cursor position
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_m_startofline.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\first line
            \\second line
            \\    third with indent
            \\fourth line
            \\fifth line
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 0, column 6
    buffer.cursor.row = 0;
    buffer.cursor.col = 6;
    buffer.cursor.goal_column = 6;

    // Press M (viewport middle) with startofline=false
    // viewport_top=0, viewport_height=10 -> middle = 5, clamped to 4
    moveToViewportMiddle(&buffer, 0, 10, false);

    // Should be on row 4 (middle clamped), column 6 preserved (but clamped if shorter)
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.row);
    // "fifth line" has 10 chars, col 6 is preserved
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor.col);
}

test "Viewport M: startofline=true moves to first non-blank" {
    // When startofline is ON, M should move to first non-blank character
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_m_sol_true.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\first line
            \\second line
            \\    third with indent
            \\fourth line
            \\    fifth with indent
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 0, column 6
    buffer.cursor.row = 0;
    buffer.cursor.col = 6;
    buffer.cursor.goal_column = 6;

    // Press M with startofline=true
    moveToViewportMiddle(&buffer, 0, 10, true);

    // Should be on row 4 (middle), column 4 (first non-blank)
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.col);
}

test "Viewport: sticky column clamps to shorter lines" {
    // When sticky column is larger than target line, clamp to line end
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_sticky_clamp.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\this is a very long first line with lots of characters
            \\short
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 0, column 40 (way past the end of "short")
    buffer.cursor.row = 0;
    buffer.cursor.col = 40;
    buffer.cursor.goal_column = 40;

    // Press L with startofline=false
    moveToViewportBottom(&buffer, 0, 10, false);

    // Should be on row 1, column clamped to line length
    // "short" has 5 chars (0-4), so col should be 4 (last char)
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.col);
    // Goal column should still be 40 (preserved for future movements)
    try std.testing.expectEqual(@as(usize, 40), buffer.cursor.goal_column.?);
}

test "Viewport: empty line handling with startofline=false" {
    // Empty lines should put cursor at column 0
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_test_empty_viewport.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(
            \\first line with text
            \\
            \\
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Start at row 0, column 10
    buffer.cursor.row = 0;
    buffer.cursor.col = 10;
    buffer.cursor.goal_column = 10;

    // Press L with startofline=false (target is empty line at row 1)
    moveToViewportBottom(&buffer, 0, 10, false);

    // Should be on row 1 (empty line), column 0
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);
}
