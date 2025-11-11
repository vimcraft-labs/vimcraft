const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Cursor = @import("buffer.zig").Cursor;
const Change = @import("buffer.zig").Change;
const VisualState = @import("../../backends/terminal/visual/visual.zig").VisualState;
const VisualMode = @import("../../backends/terminal/visual/visual.zig").VisualMode;
const Position = @import("../../backends/terminal/visual/visual.zig").Position;
const RegisterManager = @import("../register/register.zig").RegisterManager;
const MotionType = @import("../register/register.zig").MotionType;
const yank = @import("yank.zig");

/// Delete visual selection
/// Returns deleted text lines (owned, caller must free)
pub fn deleteVisualSelection(
    buffer: *Buffer,
    visual: VisualState,
    cursor_pos: Position,
    register_mgr: *RegisterManager,
    regname: u8,
    allocator: std.mem.Allocator,
) !void {
    // First, yank the selection to the register
    try yank.yankVisualSelection(buffer, visual, cursor_pos, register_mgr, regname, allocator);

    // Extract text to get range information
    const lines = try yank.extractVisualSelection(buffer, visual, cursor_pos, allocator);
    defer yank.freeLines(lines, allocator);

    const range = visual.getRange(cursor_pos);

    // Perform deletion based on visual mode type
    switch (visual.mode) {
        .char => try deleteCharWise(buffer, range.start, range.end),
        .line => try deleteLineWise(buffer, range.start.line, range.end.line),
        .block => try deleteBlockWise(buffer, range.start, range.end),
    }
}

/// Delete character-wise selection
fn deleteCharWise(buffer: *Buffer, start: Position, end: Position) !void {
    const cursor_before = buffer.cursor;

    // Calculate byte offsets
    const start_offset = buffer.line_starts.items[start.line] + start.col;
    var end_offset: usize = undefined;

    if (end.line >= buffer.line_starts.items.len) {
        end_offset = buffer.content.items.len;
    } else if (end.line + 1 < buffer.line_starts.items.len) {
        end_offset = buffer.line_starts.items[end.line] + end.col + 1; // +1 for inclusive
    } else {
        end_offset = @min(buffer.line_starts.items[end.line] + end.col + 1, buffer.content.items.len);
    }

    // Ensure end_offset doesn't exceed content length
    end_offset = @min(end_offset, buffer.content.items.len);

    if (start_offset >= end_offset) return; // Nothing to delete

    // Save deleted text for undo
    const deleted_text = try buffer.allocator.dupe(u8, buffer.content.items[start_offset..end_offset]);

    // Delete the range
    var i: usize = end_offset;
    while (i > start_offset) {
        i -= 1;
        _ = buffer.content.orderedRemove(start_offset);
    }

    // Rebuild line index
    try buffer.buildLineIndex();

    // Position cursor at start of deletion
    buffer.cursor = Cursor{
        .row = start.line,
        .col = start.col,
    };

    // Clamp cursor to valid position
    if (buffer.cursor.row >= buffer.lineCount()) {
        buffer.cursor.row = if (buffer.lineCount() > 0) buffer.lineCount() - 1 else 0;
    }
    const line_len = buffer.getLineLength(buffer.cursor.row);
    if (line_len > 0 and buffer.cursor.col >= line_len) {
        buffer.cursor.col = line_len - 1;
    }

    // Record change for undo
    const change = Change{
        .offset = start_offset,
        .deleted_text = deleted_text,
        .inserted_text = try buffer.allocator.alloc(u8, 0),
        .cursor_before = cursor_before,
        .cursor_after = buffer.cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
}

/// Delete line-wise selection
fn deleteLineWise(buffer: *Buffer, start_line: usize, end_line: usize) !void {
    const cursor_before = buffer.cursor;

    // Calculate byte offsets for entire lines
    const start_offset = buffer.line_starts.items[start_line];
    const end_offset = if (end_line + 1 < buffer.line_starts.items.len)
        buffer.line_starts.items[end_line + 1]
    else
        buffer.content.items.len;

    if (start_offset >= end_offset) return;

    // Save deleted text for undo
    const deleted_text = try buffer.allocator.dupe(u8, buffer.content.items[start_offset..end_offset]);

    // Delete the lines
    var i: usize = end_offset;
    while (i > start_offset) {
        i -= 1;
        _ = buffer.content.orderedRemove(start_offset);
    }

    // Rebuild line index
    try buffer.buildLineIndex();

    // Position cursor at start of deletion (or previous line if we deleted last line)
    buffer.cursor = Cursor{
        .row = if (start_line < buffer.lineCount()) start_line else if (buffer.lineCount() > 0) buffer.lineCount() - 1 else 0,
        .col = 0,
    };

    // Record change for undo
    const change = Change{
        .offset = start_offset,
        .deleted_text = deleted_text,
        .inserted_text = try buffer.allocator.alloc(u8, 0),
        .cursor_before = cursor_before,
        .cursor_after = buffer.cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
}

/// Delete block-wise (rectangular) selection
fn deleteBlockWise(buffer: *Buffer, start: Position, end: Position) !void {
    const cursor_before = buffer.cursor;

    // Normalize column range
    const start_col = @min(start.col, end.col);
    const end_col = @max(start.col, end.col);

    // Delete from each line
    var line_num = start.line;
    while (line_num <= end.line) : (line_num += 1) {
        if (line_num >= buffer.lineCount()) break;

        const line = buffer.getLine(line_num) orelse continue;
        const line_start_offset = buffer.line_starts.items[line_num];

        // Calculate actual deletion range on this line
        const actual_start = @min(start_col, line.len);
        const actual_end = @min(end_col + 1, line.len); // +1 for inclusive

        if (actual_start >= actual_end) continue;

        // Delete the segment
        const delete_offset = line_start_offset + actual_start;
        const delete_count = actual_end - actual_start;

        for (0..delete_count) |_| {
            _ = buffer.content.orderedRemove(delete_offset);
        }
    }

    // Rebuild line index
    try buffer.buildLineIndex();

    // Position cursor at start of block
    buffer.cursor = Cursor{
        .row = start.line,
        .col = start_col,
    };

    // Clamp cursor
    if (buffer.cursor.row >= buffer.lineCount()) {
        buffer.cursor.row = if (buffer.lineCount() > 0) buffer.lineCount() - 1 else 0;
    }
    const line_len = buffer.getLineLength(buffer.cursor.row);
    if (line_len > 0 and buffer.cursor.col >= line_len) {
        buffer.cursor.col = line_len - 1;
    }

    // Record change for undo (simplified - doesn't track block deletion perfectly)
    const change = Change{
        .offset = buffer.getCursorOffset(),
        .deleted_text = try buffer.allocator.alloc(u8, 0), // Block delete undo is complex
        .inserted_text = try buffer.allocator.alloc(u8, 0),
        .cursor_before = cursor_before,
        .cursor_after = buffer.cursor,
    };
    try buffer.undo_stack.append(buffer.allocator, change);

    buffer.modified = true;
}

/// Change visual selection (delete and enter insert mode)
/// Caller should enter insert mode after this function returns
pub fn changeVisualSelection(
    buffer: *Buffer,
    visual: VisualState,
    cursor_pos: Position,
    register_mgr: *RegisterManager,
    regname: u8,
    allocator: std.mem.Allocator,
) !void {
    // Change is just delete + enter insert mode (caller handles mode change)
    try deleteVisualSelection(buffer, visual, cursor_pos, register_mgr, regname, allocator);
}

// Tests
test "visual_ops: delete single line character-wise" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    // Create file with content
    const tmp_path = "/tmp/vimcraft_visual_delete_test.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello World\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual select "World" (positions 6-10)
    const visual = VisualState.init(.{ .line = 0, .col = 6 }, .char);
    const cursor_pos = Position{ .line = 0, .col = 10 };

    // Delete selection
    try deleteVisualSelection(&buffer, visual, cursor_pos, &register_mgr, '"', allocator);

    // Check result: "Hello \n"
    const line = buffer.getLine(0).?;
    try std.testing.expectEqualStrings("Hello \n", line);

    // Check cursor is at start of deletion (col 6)
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor.col);

    // Check register has the deleted text
    const reg = register_mgr.get('"').?;
    try std.testing.expectEqual(@as(usize, 1), reg.lines.items.len);
    try std.testing.expectEqualStrings("World", reg.lines.items[0]);
}

test "visual_ops: delete line-wise" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    const tmp_path = "/tmp/vimcraft_visual_delete_line.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Line 1\nLine 2\nLine 3\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual line select lines 0-1
    const visual = VisualState.init(.{ .line = 0, .col = 0 }, .line);
    const cursor_pos = Position{ .line = 1, .col = 0 };

    // Delete selection
    try deleteVisualSelection(&buffer, visual, cursor_pos, &register_mgr, '"', allocator);

    // Check result: "Line 3\n"
    try std.testing.expectEqual(@as(usize, 1), buffer.lineCount());
    const line = buffer.getLine(0).?;
    try std.testing.expectEqualStrings("Line 3\n", line);

    // Check cursor at start of remaining line
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);

    // Check register has both deleted lines
    const reg = register_mgr.get('"').?;
    try std.testing.expectEqual(@as(usize, 2), reg.lines.items.len);
    try std.testing.expectEqualStrings("Line 1", reg.lines.items[0]);
    try std.testing.expectEqualStrings("Line 2", reg.lines.items[1]);
}

test "visual_ops: change character-wise enters insert mode" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    const tmp_path = "/tmp/vimcraft_visual_change.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello World\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual select "World"
    const visual = VisualState.init(.{ .line = 0, .col = 6 }, .char);
    const cursor_pos = Position{ .line = 0, .col = 10 };

    // Change selection (delete, caller enters insert mode)
    try changeVisualSelection(&buffer, visual, cursor_pos, &register_mgr, '"', allocator);

    // Check content deleted
    const line = buffer.getLine(0).?;
    try std.testing.expectEqualStrings("Hello \n", line);

    // Check cursor positioned for insertion
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor.col);
}
