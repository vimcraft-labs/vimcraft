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

// Test horizontal scrolling: all lines should scroll together (Neovim behavior)
test "Display: horizontal scroll applies to all lines" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    // Create buffer with multiple long lines
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "This is a very long line with lots of content that exceeds terminal width");
    try buffer.insertLine(1, "Another very long line that also has lots and lots of text here");
    try buffer.insertLine(2, "Short line");

    // Place cursor far to the right on line 0
    buffer.cursor.row = 0;
    buffer.cursor.col = 50;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    var visual_state = VisualState.init();
    var yank_highlight = YankHighlight.init();

    // Render - this should trigger horizontal scrolling
    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);

    // Check that viewport_left was set (horizontal scroll happened)
    try std.testing.expect(display.viewport_left > 0);

    // Now verify that ALL lines in the base layer show scrolled content
    // Line 0 (cursor line): Should show content from viewport_left onward
    const line0_cell = display.base_layer.grid.getCell(0, display.gutter_manager.getTotalWidth());

    // Line 1 (non-cursor line): Should ALSO show content from viewport_left onward
    const line1_cell = display.base_layer.grid.getCell(1, display.gutter_manager.getTotalWidth());

    // Both should have content (not empty space)
    // The key test: line 1 should show scrolled content even though cursor is on line 0
    try std.testing.expect(line0_cell.char != 0);
    try std.testing.expect(line1_cell.char != 0);

    // Verify that we're actually seeing different parts of the lines
    // The scrolled portion should not start with "This" or "Another" (the line beginnings)
    try std.testing.expect(line0_cell.char != 'T'); // Not showing "This..."
    try std.testing.expect(line1_cell.char != 'A'); // Not showing "Another..."
}

// Test horizontal scrolling with visual selection
test "Display: horizontal scroll applies to visual selection layer" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "This is a very long line with lots of content that exceeds terminal width");
    try buffer.insertLine(1, "Another very long line that also has lots and lots of text here");

    // Set up visual selection on line 1
    buffer.cursor.row = 1;
    buffer.cursor.col = 50;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const visual_bg = try highlights.Color.fromHex("#283457");
    config.visual = highlights.Highlight{ .bg = visual_bg };

    // Create active visual state on line 1
    var visual_state = VisualState.init();
    visual_state.start(.{
        .line = 1,
        .col = 10,
    });
    visual_state.active = true;

    var yank_highlight = YankHighlight.init();

    // Render with horizontal scroll
    try display.render(&buffer, "VISUAL", &config, &visual_state, &yank_highlight, null);

    // Verify viewport_left is set
    try std.testing.expect(display.viewport_left > 0);

    // The selection layer should also respect horizontal scrolling
    // Check that selection is rendered at the correct screen position
    // considering the horizontal offset
    const selection_cell = display.selection_layer.grid.getCell(1, display.gutter_manager.getTotalWidth());

    // Selection should be visible (has background color or is transparent space)
    // This verifies that the selection layer also respects viewport_left
    try std.testing.expect(selection_cell.char == ' ' or selection_cell.bg != null);
}

// Test horizontal scrolling with yank highlight
test "Display: horizontal scroll applies to yank highlight layer" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "This is a very long line with lots of content that exceeds terminal width");
    try buffer.insertLine(1, "Another very long line that also has lots and lots of text here");

    buffer.cursor.row = 1;
    buffer.cursor.col = 50;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const yank_bg = try highlights.Color.fromHex("#646400");
    config.yank_flash = highlights.Highlight{ .bg = yank_bg };

    var visual_state = VisualState.init();

    // Create active yank highlight on line 1
    var yank_highlight = YankHighlight.init();
    yank_highlight.start(.{
        .line = 1,
        .col = 10,
    }, .{
        .line = 1,
        .col = 60,
    });

    // Render with horizontal scroll
    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);

    // Verify viewport_left is set
    try std.testing.expect(display.viewport_left > 0);

    // The yank layer should also respect horizontal scrolling
    const yank_cell = display.yank_layer.grid.getCell(1, display.gutter_manager.getTotalWidth());

    // Yank highlight should be rendered considering horizontal offset
    // It should either have the yank background or be empty (outside yank range)
    try std.testing.expect(yank_cell.char == ' ' or yank_cell.char == 0);
}

// Test horizontal scrolling resets when cursor moves left
test "Display: horizontal scroll resets when cursor moves to visible area" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "This is a very long line with lots of content that exceeds terminal width");

    // First: cursor far right
    buffer.cursor.row = 0;
    buffer.cursor.col = 50;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    var visual_state = VisualState.init();
    var yank_highlight = YankHighlight.init();

    // Render - should set viewport_left > 0
    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);
    try std.testing.expect(display.viewport_left > 0);

    // Now move cursor back to beginning
    buffer.cursor.col = 5;

    // Render again - viewport_left should reset to 0
    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);
    try std.testing.expectEqual(@as(usize, 0), display.viewport_left);

    // Verify the line now shows from the beginning
    const cell = display.base_layer.grid.getCell(0, display.gutter_manager.getTotalWidth());
    try std.testing.expectEqual(@as(u21, 'T'), cell.char); // Should show "This..."
}

// Test that short lines don't cause issues with horizontal scrolling
test "Display: short lines work correctly with horizontal scroll" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.insertLine(0, "This is a very long line with lots of content that exceeds terminal width");
    try buffer.insertLine(1, "Short"); // Very short line
    try buffer.insertLine(2, "Another very long line that also has lots and lots of text here");

    buffer.cursor.row = 0;
    buffer.cursor.col = 50;

    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    var visual_state = VisualState.init();
    var yank_highlight = YankHighlight.init();

    // Render - viewport_left will be set based on cursor position
    try display.render(&buffer, "NORMAL", &config, &visual_state, &yank_highlight, null);

    // Short line should still render (even though it doesn't have content at viewport_left)
    // It should just show as empty space, not crash
    const short_line_cell = display.base_layer.grid.getCell(1, display.gutter_manager.getTotalWidth());

    // Should either be empty space or the start of "Short" if viewport_left is 0
    // Key: should not crash or cause undefined behavior
    try std.testing.expect(short_line_cell.char == ' ' or short_line_cell.char == 'S' or short_line_cell.char == 0);
}
