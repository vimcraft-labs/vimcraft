const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;

test "Transaction grouping: multiple insertions become single undo" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Create initial content using Rope
    buffer.content.deinit();
    buffer.content = try @import("rope.zig").Rope.fromString(allocator, "Hello\n");

    // Move cursor to end of line (before newline)
    buffer.cursor.row = 0;
    buffer.cursor.col = 5;

    // Start transaction (simulating entering insert mode)
    buffer.beginTransaction();

    // Insert multiple characters (simulating paste)
    try buffer.insertChar(' ');
    try buffer.insertChar('W');
    try buffer.insertChar('o');
    try buffer.insertChar('r');
    try buffer.insertChar('l');
    try buffer.insertChar('d');

    // Commit transaction (simulating exiting insert mode with ESC)
    try buffer.commitTransaction();

    // Verify content
    const content1 = try buffer.content.toString();
    defer allocator.free(content1);
    try std.testing.expectEqualStrings("Hello World\n", content1);

    // Verify cursor position (after 'd')
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 11), buffer.cursor.col);

    // Verify undo stack has ONE entry (not 6)
    try std.testing.expectEqual(@as(usize, 1), buffer.undo_stack.items.len);

    // Undo with single 'u'
    try buffer.undo();

    // Verify ALL characters were removed
    const content2 = try buffer.content.toString();
    defer allocator.free(content2);
    try std.testing.expectEqualStrings("Hello\n", content2);

    // Verify cursor is back to original position
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 5), buffer.cursor.col);

    // Verify undo stack is now empty
    try std.testing.expectEqual(@as(usize, 0), buffer.undo_stack.items.len);

    // Verify redo stack has one entry
    try std.testing.expectEqual(@as(usize, 1), buffer.redo_stack.items.len);
}

test "Transaction grouping: without transaction each char creates undo entry" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Create initial content using Rope
    buffer.content.deinit();
    buffer.content = try @import("rope.zig").Rope.fromString(allocator, "Hello\n");

    buffer.cursor.row = 0;
    buffer.cursor.col = 5;

    // Insert characters WITHOUT transaction (normal typing)
    try buffer.insertChar(' ');
    try buffer.insertChar('W');
    try buffer.insertChar('o');

    // Verify content
    {
        const content = try buffer.content.toString();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello Wo\n", content);
    }

    // Verify undo stack has THREE entries (one per character)
    try std.testing.expectEqual(@as(usize, 3), buffer.undo_stack.items.len);

    // Single undo should only remove last character ('o')
    try buffer.undo();
    {
        const content = try buffer.content.toString();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello W\n", content);
    }

    // Undo again should remove 'W'
    try buffer.undo();
    {
        const content = try buffer.content.toString();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello \n", content);
    }

    // Undo again should remove ' '
    try buffer.undo();
    {
        const content = try buffer.content.toString();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello\n", content);
    }
}
