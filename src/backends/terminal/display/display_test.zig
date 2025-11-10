const std = @import("std");
const Display = @import("display.zig").Display;
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const highlights = @import("../../../editor/config/highlights.zig");
const VisualState = @import("../visual/visual.zig").VisualState;
const YankHighlight = @import("../visual/yank_highlight.zig").YankHighlight;

// Test that cursorline highlight is actually rendered to the cursor layer
test "Display: cursorline renders to cursor layer" {
    const allocator = std.testing.allocator;

    // Create display
    var display = try Display.init(allocator);
    defer display.deinit();

    // Create buffer with some content
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "Line 1");
    try buffer.insertLine(1, "Line 2");
    try buffer.insertLine(2, "Line 3");
    buffer.cursor.row = 1; // Cursor on line 2

    // Configure highlights
    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const cursorline_color = try highlights.Color.fromHex("#2b2b2b");
    config.cursorline = highlights.Highlight{ .bg = cursorline_color };
    config.cursorline_enabled = true;

    // Create visual state (not active)
    var visual_state = VisualState.init();

    // Create yank highlight (not active)
    var yank_highlight = YankHighlight.init();

    // Render (this should populate the cursor layer)
    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);

    // CRITICAL TEST: Check that cursor layer has background color at cursor line
    // Cursor is on row 1, so screen_row should be 1 (viewport_top is 0 by default)
    const screen_row = 1;

    // The cursor layer should have cursorline background in all columns of that row
    const cell = display.cursor_layer.grid.getCell(screen_row, 0);

    // Verify background color is set
    try std.testing.expect(cell.bg != null);
    if (cell.bg) |bg| {
        try std.testing.expectEqual(@as(u8, 0x2b), bg.r);
        try std.testing.expectEqual(@as(u8, 0x2b), bg.g);
        try std.testing.expectEqual(@as(u8, 0x2b), bg.b);
    }

    // Verify the cell char is 0 (null) to allow base layer text through
    try std.testing.expectEqual(@as(u21, 0), cell.char);
}

// Test that cursorline respects cursorline_enabled flag
test "Display: cursorline disabled when cursorline_enabled is false" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "Line 1");
    buffer.cursor.row = 0;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const cursorline_color = try highlights.Color.fromHex("#2b2b2b");
    config.cursorline = highlights.Highlight{ .bg = cursorline_color };
    config.cursorline_enabled = false; // DISABLED

    var visual_state = VisualState.init();
    var yank_highlight = YankHighlight.init();

    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);

    // Cursor layer should NOT have background (cursorline disabled)
    const screen_row = 0;
    const cell = display.cursor_layer.grid.getCell(screen_row, 0);

    // Background should be null (no cursorline)
    try std.testing.expect(cell.bg == null);
}

// Test that cursorline is not rendered when cursorline highlight is not configured
test "Display: no cursorline when highlight not configured" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "Line 1");
    buffer.cursor.row = 0;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    // No cursorline color configured (config.cursorline is null)
    config.cursorline_enabled = true; // Enabled but no color

    var visual_state = VisualState.init();
    var yank_highlight = YankHighlight.init();

    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);

    // Cursor layer should NOT have background (no color configured)
    const screen_row = 0;
    const cell = display.cursor_layer.grid.getCell(screen_row, 0);

    try std.testing.expect(cell.bg == null);
}
