const std = @import("std");
const highlights = @import("highlights.zig");

// Test Color parsing from hex strings
test "Color: parse hex with #" {
    const color = try highlights.Color.fromHex("#FF5500");
    try std.testing.expectEqual(@as(u8, 0xFF), color.r);
    try std.testing.expectEqual(@as(u8, 0x55), color.g);
    try std.testing.expectEqual(@as(u8, 0x00), color.b);
}

test "Color: parse hex without #" {
    const color = try highlights.Color.fromHex("00FF00");
    try std.testing.expectEqual(@as(u8, 0x00), color.r);
    try std.testing.expectEqual(@as(u8, 0xFF), color.g);
    try std.testing.expectEqual(@as(u8, 0x00), color.b);
}

test "Color: parse invalid hex returns error" {
    const result = highlights.Color.fromHex("invalid");
    try std.testing.expectError(error.InvalidHexColor, result);
}

test "Color: ANSI background escape code" {
    const color = highlights.Color{ .r = 255, .g = 85, .b = 0 };
    var buf: [32]u8 = undefined;
    const bg = try color.toAnsiBg(&buf);
    try std.testing.expectEqualStrings("\x1b[48;2;255;85;0m", bg);
}

test "Color: ANSI foreground escape code" {
    const color = highlights.Color{ .r = 0, .g = 255, .b = 0 };
    var buf: [32]u8 = undefined;
    const fg = try color.toAnsiFg(&buf);
    try std.testing.expectEqualStrings("\x1b[38;2;0;255;0m", fg);
}

// Test HighlightConfig
test "HighlightConfig: setHighlight for CursorLine" {
    const allocator = std.testing.allocator;
    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const cursorline_hl = highlights.Highlight{
        .bg = highlights.Color{ .r = 43, .g = 43, .b = 43 },
    };
    config.setHighlight("CursorLine", cursorline_hl);

    const retrieved = config.getHighlight("CursorLine");
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.bg != null);
    try std.testing.expectEqual(@as(u8, 43), retrieved.?.bg.?.r);
}

test "HighlightConfig: setHighlight for Cursor" {
    const allocator = std.testing.allocator;
    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const cursor_hl = highlights.Highlight{
        .bg = highlights.Color{ .r = 174, .g = 175, .b = 173 }, // #aeafad
    };
    config.setHighlight("Cursor", cursor_hl);

    const retrieved = config.getHighlight("Cursor");
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.bg != null);
    try std.testing.expectEqual(@as(u8, 174), retrieved.?.bg.?.r);
    try std.testing.expectEqual(@as(u8, 175), retrieved.?.bg.?.g);
    try std.testing.expectEqual(@as(u8, 173), retrieved.?.bg.?.b);
}

test "HighlightConfig: setHighlight for Visual" {
    const allocator = std.testing.allocator;
    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const visual_hl = highlights.Highlight{
        .bg = highlights.Color{ .r = 40, .g = 52, .b = 87 }, // #283457
    };
    config.setHighlight("Visual", visual_hl);

    const retrieved = config.getHighlight("Visual");
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.bg != null);
    try std.testing.expectEqual(@as(u8, 40), retrieved.?.bg.?.r);
}

test "HighlightConfig: cursorline_enabled defaults to true" {
    const allocator = std.testing.allocator;
    const config = highlights.HighlightConfig.init(allocator);
    // No defer deinit needed - no cleanup required for this test

    try std.testing.expect(config.cursorline_enabled);
}

test "HighlightConfig: multiple highlights" {
    const allocator = std.testing.allocator;
    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    // Set multiple highlights (simulating init.js)
    config.setHighlight("Normal", highlights.Highlight{
        .bg = try highlights.Color.fromHex("#1A1B26"),
        .fg = try highlights.Color.fromHex("#ABB2BF"),
    });
    config.setHighlight("Cursor", highlights.Highlight{
        .bg = try highlights.Color.fromHex("#aeafad"),
    });
    config.setHighlight("CursorLine", highlights.Highlight{
        .bg = try highlights.Color.fromHex("#2b2b2b"),
    });
    config.setHighlight("Visual", highlights.Highlight{
        .bg = try highlights.Color.fromHex("#283457"),
    });

    // Verify all highlights are set correctly
    const normal = config.getHighlight("Normal");
    try std.testing.expect(normal != null);
    try std.testing.expect(normal.?.bg != null);
    try std.testing.expectEqual(@as(u8, 0x1A), normal.?.bg.?.r);

    const cursor = config.getHighlight("Cursor");
    try std.testing.expect(cursor != null);
    try std.testing.expect(cursor.?.bg != null);
    try std.testing.expectEqual(@as(u8, 0xae), cursor.?.bg.?.r);

    const cursorline = config.getHighlight("CursorLine");
    try std.testing.expect(cursorline != null);
    try std.testing.expect(cursorline.?.bg != null);
    try std.testing.expectEqual(@as(u8, 0x2b), cursorline.?.bg.?.r);

    const visual = config.getHighlight("Visual");
    try std.testing.expect(visual != null);
    try std.testing.expect(visual.?.bg != null);
    try std.testing.expectEqual(@as(u8, 0x28), visual.?.bg.?.r);
}
