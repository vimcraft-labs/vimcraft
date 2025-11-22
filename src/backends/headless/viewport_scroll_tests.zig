const std = @import("std");
const EditorContext = @import("editor_context.zig").EditorContext;

/// Viewport scroll tests using debug protocol pattern
/// These tests verify that viewport scrolling works correctly when cursor
/// moves beyond viewport boundaries.
///
/// Key scenarios tested:
/// 1. Scroll down: cursor moves past bottom of viewport (j key)
/// 2. Scroll up: cursor moves above top of viewport (k key)
/// 3. Half-page scroll: Ctrl+D, Ctrl+U
/// 4. File navigation: gg, G
/// 5. Viewport adjustment: zz, zt, zb

// ============================================================================
// Test Helpers
// ============================================================================

/// Create a test file with numbered lines
fn createTestBuffer(ctx: *EditorContext, line_count: usize) !void {
    // Get buffer through accessor method
    const buffer = ctx.buffer();

    // Clear existing content
    buffer.content.deinit();
    const Rope = @import("../../editor/buffer/rope.zig").Rope;
    buffer.content = try Rope.fromString(ctx.allocator, "");

    // Build content with numbered lines
    var content_builder: std.ArrayList(u8) = .empty;
    defer content_builder.deinit(ctx.allocator);

    for (0..line_count) |i| {
        const line = try std.fmt.allocPrint(ctx.allocator, "line {d}\n", .{i + 1});
        defer ctx.allocator.free(line);
        try content_builder.appendSlice(ctx.allocator, line);
    }

    // Replace buffer content
    buffer.content.deinit();
    buffer.content = try Rope.fromString(ctx.allocator, content_builder.items);

    // Reset cursor to start
    buffer.cursor.row = 0;
    buffer.cursor.col = 0;
}

/// Set viewport dimensions for testing
fn setViewportSize(ctx: *EditorContext, height: usize, width: usize) void {
    ctx.display.terminal_rows = height + 1; // +1 for status line
    ctx.display.terminal_cols = width;
}

/// Get current viewport top line
fn getViewportTop(ctx: *EditorContext) usize {
    return ctx.display.viewport_top;
}

/// Get effective text rows (viewport height minus status line)
fn getTextRows(ctx: *EditorContext) usize {
    return if (ctx.display.terminal_rows > 1) ctx.display.terminal_rows - 1 else 1;
}

// ============================================================================
// Scroll Down Tests (j key past viewport bottom)
// ============================================================================

test "Viewport: scroll down when cursor moves past viewport bottom" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 30-line buffer with 10-line viewport
    try createTestBuffer(&ctx, 30);
    setViewportSize(&ctx, 10, 80); // 10 text rows + 1 status = 11 terminal rows

    // Initial state
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));

    // Move down 15 times (past the 10-line viewport)
    try ctx.executeKeys("jjjjjjjjjjjjjjj"); // 15 j's

    // Cursor should be at line 15 (0-indexed)
    try std.testing.expectEqual(@as(usize, 15), ctx.buffer().cursor.row);

    // Viewport should have scrolled to keep cursor visible
    // viewport_top should be cursor_row - text_rows + 1 = 15 - 10 + 1 = 6
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);

    // Verify cursor is within visible viewport
    try std.testing.expect(ctx.buffer().cursor.row >= viewport_top);
    try std.testing.expect(ctx.buffer().cursor.row < viewport_top + text_rows);
}

test "Viewport: scroll down one line at a time at viewport edge" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 20-line buffer with 5-line viewport
    try createTestBuffer(&ctx, 20);
    setViewportSize(&ctx, 5, 80);

    // Move to last visible line (line 4, 0-indexed)
    try ctx.executeKeys("jjjj"); // Move to line 4

    try std.testing.expectEqual(@as(usize, 4), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));

    // Move one more line - this should trigger scroll
    try ctx.executeKeys("j");

    try std.testing.expectEqual(@as(usize, 5), ctx.buffer().cursor.row);
    // Viewport should scroll by 1
    try std.testing.expectEqual(@as(usize, 1), getViewportTop(&ctx));
}

test "Viewport: scroll stops at end of file" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 10-line buffer with 5-line viewport
    try createTestBuffer(&ctx, 10);
    setViewportSize(&ctx, 5, 80);

    // Try to move past end of file
    try ctx.executeKeys("jjjjjjjjjjjjjjjjjjjj"); // 20 j's, but only 10 lines

    // Cursor should be at last line (line 9, 0-indexed)
    try std.testing.expectEqual(@as(usize, 9), ctx.buffer().cursor.row);

    // Viewport should show last lines
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);
    try std.testing.expect(ctx.buffer().cursor.row < viewport_top + text_rows);
}

// ============================================================================
// Scroll Up Tests (k key above viewport top)
// ============================================================================

test "Viewport: scroll up when cursor moves above viewport top" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 30-line buffer with 10-line viewport
    try createTestBuffer(&ctx, 30);
    setViewportSize(&ctx, 10, 80);

    // Move to middle of file first
    try ctx.executeKeys("jjjjjjjjjjjjjjjjjjjj"); // 20 j's to line 20

    const initial_viewport_top = getViewportTop(&ctx);
    try std.testing.expect(initial_viewport_top > 0);

    // Now move up 15 times
    try ctx.executeKeys("kkkkkkkkkkkkkkk"); // 15 k's

    // Cursor should be at line 5 (20 - 15)
    try std.testing.expectEqual(@as(usize, 5), ctx.buffer().cursor.row);

    // Viewport should have scrolled up
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);

    // Verify cursor is within visible viewport
    try std.testing.expect(ctx.buffer().cursor.row >= viewport_top);
    try std.testing.expect(ctx.buffer().cursor.row < viewport_top + text_rows);
}

test "Viewport: scroll up one line at a time at viewport edge" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 20-line buffer with 5-line viewport
    try createTestBuffer(&ctx, 20);
    setViewportSize(&ctx, 5, 80);

    // Move down then scroll viewport
    try ctx.executeKeys("jjjjjjjjjj"); // Move to line 10
    const viewport_top_after_down = getViewportTop(&ctx);
    try std.testing.expect(viewport_top_after_down > 0);

    // Move up to top of viewport
    const moves_to_top = ctx.buffer().cursor.row - viewport_top_after_down;
    for (0..moves_to_top) |_| {
        try ctx.executeKeys("k");
    }

    // Now at viewport_top, move up one more - should trigger scroll
    const row_before = ctx.buffer().cursor.row;
    try ctx.executeKeys("k");

    try std.testing.expectEqual(row_before - 1, ctx.buffer().cursor.row);
    // Viewport should have scrolled up by 1
    try std.testing.expectEqual(viewport_top_after_down - 1, getViewportTop(&ctx));
}

test "Viewport: scroll stops at beginning of file" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 10-line buffer
    try createTestBuffer(&ctx, 10);
    setViewportSize(&ctx, 5, 80);

    // Move to middle then try to scroll past beginning
    try ctx.executeKeys("jjjjj"); // Move to line 5
    try ctx.executeKeys("kkkkkkkkkkkkkkkkkkkk"); // 20 k's

    // Cursor should be at line 0
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    // Viewport should be at top
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));
}

// ============================================================================
// Half-Page Scroll Tests (Ctrl+D / Ctrl+U)
// ============================================================================

test "Viewport: Ctrl+D scrolls half page down" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 50-line buffer with 20-line viewport
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 20, 80);

    const initial_row = ctx.buffer().cursor.row;

    // Ctrl+D (ASCII 4) scrolls half page down
    try ctx.executeKeys(&[_]u8{4}); // Ctrl+D

    // Cursor should have moved down by ~half viewport (10 lines for 20-line viewport)
    // Note: EditorContext uses hardcoded 20 for viewport_height in scrollHalfPage
    try std.testing.expect(ctx.buffer().cursor.row > initial_row);
    try std.testing.expect(ctx.buffer().cursor.row >= initial_row + 5); // At least 5 lines
}

test "Viewport: Ctrl+U scrolls half page up" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 50-line buffer
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 20, 80);

    // First move down
    try ctx.executeKeys(&[_]u8{4}); // Ctrl+D
    try ctx.executeKeys(&[_]u8{4}); // Ctrl+D again
    const row_after_down = ctx.buffer().cursor.row;

    // Now Ctrl+U (ASCII 21) scrolls half page up
    try ctx.executeKeys(&[_]u8{21}); // Ctrl+U

    // Cursor should have moved up
    try std.testing.expect(ctx.buffer().cursor.row < row_after_down);
}

test "Viewport: Ctrl+D at end of file" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 10-line buffer (smaller than viewport)
    try createTestBuffer(&ctx, 10);
    setViewportSize(&ctx, 20, 80);

    // Move to near end
    try ctx.executeKeys("G"); // Go to last line

    const row_at_end = ctx.buffer().cursor.row;

    // Try Ctrl+D - should not go past end
    try ctx.executeKeys(&[_]u8{4}); // Ctrl+D

    // Should still be at or near end (can't scroll past file)
    try std.testing.expectEqual(row_at_end, ctx.buffer().cursor.row);
}

// ============================================================================
// File Navigation Tests (gg / G)
// ============================================================================

test "Viewport: G moves to end of file and adjusts viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 50-line buffer with 10-line viewport
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 10, 80);

    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);

    // G moves to last line
    try ctx.executeKeys("G");

    // Cursor should be at last line (line 49, 0-indexed)
    try std.testing.expectEqual(@as(usize, 49), ctx.buffer().cursor.row);

    // Viewport should show last lines
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);
    try std.testing.expect(ctx.buffer().cursor.row >= viewport_top);
    try std.testing.expect(ctx.buffer().cursor.row < viewport_top + text_rows);
}

test "Viewport: gg moves to start of file and adjusts viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 50-line buffer with 10-line viewport
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 10, 80);

    // Move to end first
    try ctx.executeKeys("G");
    try std.testing.expectEqual(@as(usize, 49), ctx.buffer().cursor.row);
    try std.testing.expect(getViewportTop(&ctx) > 0);

    // gg moves to first line
    try ctx.executeKeys("gg");

    // Cursor should be at first line
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);

    // Viewport should be at top
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));
}

test "Viewport: G then gg round-trip" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 100);
    setViewportSize(&ctx, 20, 80);

    // Start at beginning
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));

    // Go to end
    try ctx.executeKeys("G");
    try std.testing.expectEqual(@as(usize, 99), ctx.buffer().cursor.row);

    // Go back to start
    try ctx.executeKeys("gg");
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));
}

// ============================================================================
// Viewport Adjustment Tests (zz / zt / zb)
// ============================================================================

test "Viewport: zz centers cursor line in viewport (cursor stays on same line)" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 50-line buffer with 10-line viewport
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 10, 80);

    // Move to line 25 (middle of file)
    for (0..25) |_| {
        try ctx.executeKeys("j");
    }

    // Verify cursor is at line 25 before zz
    try std.testing.expectEqual(@as(usize, 25), ctx.buffer().cursor.row);

    // zz should center the CURRENT LINE (line 25) in the viewport
    // It should NOT move the cursor - only adjust the viewport
    try ctx.executeKeys("zz");

    // CRITICAL: Cursor must stay at line 25 (zz doesn't move cursor)
    try std.testing.expectEqual(@as(usize, 25), ctx.buffer().cursor.row);

    // Viewport should be adjusted so cursor line is in the middle
    // For 10-line viewport with cursor at line 25:
    // viewport_top = cursor_row - (text_rows / 2) = 25 - 5 = 20
    const text_rows = getTextRows(&ctx);
    const expected_viewport_top = ctx.buffer().cursor.row -| (text_rows / 2);
    try std.testing.expectEqual(expected_viewport_top, getViewportTop(&ctx));
}

test "Viewport: zz does not move cursor (only adjusts viewport)" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 100-line buffer with 20-line viewport
    try createTestBuffer(&ctx, 100);
    setViewportSize(&ctx, 20, 80);

    // Move cursor to line 40
    for (0..40) |_| {
        try ctx.executeKeys("j");
    }
    try std.testing.expectEqual(@as(usize, 40), ctx.buffer().cursor.row);

    // Execute zz
    try ctx.executeKeys("zz");

    // Cursor MUST remain at line 40
    try std.testing.expectEqual(@as(usize, 40), ctx.buffer().cursor.row);

    // Viewport should center line 40
    // text_rows = 20, so viewport_top = 40 - 10 = 30
    const text_rows = getTextRows(&ctx);
    const expected_viewport_top = 40 -| (text_rows / 2);
    try std.testing.expectEqual(expected_viewport_top, getViewportTop(&ctx));
}

test "Viewport: zz BUG REPRO - cursor at line 5, viewport shows lines 0-9, zz should NOT move cursor" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 50-line buffer with 10-line viewport
    // This is a specific scenario to reproduce the reported bug
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 10, 80);

    // Move cursor to line 5 (middle of initial viewport)
    try ctx.executeKeys("jjjjj"); // 5 j's
    try std.testing.expectEqual(@as(usize, 5), ctx.buffer().cursor.row);

    // At this point:
    // - Cursor is on line 5
    // - Viewport shows lines 0-9 (viewport_top = 0)
    // - Cursor is visible in viewport (no scrolling happened)
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));

    // Execute zz - this SHOULD:
    // 1. Keep cursor at line 5 (NOT move it!)
    // 2. Adjust viewport so line 5 is centered
    //    viewport_top = cursor_row - (text_rows / 2) = 5 - 5 = 0
    //    (In this case, viewport_top stays at 0 since line 5 is already near center)
    try ctx.executeKeys("zz");

    // CRITICAL: Cursor must NOT have moved!
    // The bug report says zz moves the cursor block instead of scrolling the viewport
    try std.testing.expectEqual(@as(usize, 5), ctx.buffer().cursor.row);

    // Viewport should be adjusted to center line 5
    const text_rows = getTextRows(&ctx);
    const expected_viewport_top = 5 -| (text_rows / 2); // 5 - 5 = 0
    try std.testing.expectEqual(expected_viewport_top, getViewportTop(&ctx));
}

test "Viewport: zt moves cursor line to top of viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 10, 80);

    // Move to line 25
    for (0..25) |_| {
        try ctx.executeKeys("j");
    }

    // zt moves current line to viewport top
    try ctx.executeKeys("zt");

    // Cursor should still be at line 25
    try std.testing.expectEqual(@as(usize, 25), ctx.buffer().cursor.row);

    // Viewport top should equal cursor line
    try std.testing.expectEqual(ctx.buffer().cursor.row, getViewportTop(&ctx));
}

test "Viewport: zb moves cursor line to bottom of viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 10, 80);

    // Move to line 25
    for (0..25) |_| {
        try ctx.executeKeys("j");
    }

    // zb moves current line to viewport bottom
    try ctx.executeKeys("zb");

    // Cursor should still be at line 25
    try std.testing.expectEqual(@as(usize, 25), ctx.buffer().cursor.row);

    // Cursor should be at bottom of viewport
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);
    const viewport_bottom = viewport_top + text_rows - 1;

    try std.testing.expectEqual(ctx.buffer().cursor.row, viewport_bottom);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Viewport: small file fits entirely in viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 5-line buffer with 20-line viewport
    try createTestBuffer(&ctx, 5);
    setViewportSize(&ctx, 20, 80);

    // Navigate through entire file
    try ctx.executeKeys("G"); // Go to end
    try std.testing.expectEqual(@as(usize, 4), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx)); // No scrolling needed

    try ctx.executeKeys("gg"); // Go to start
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));
}

test "Viewport: single line file" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 1-line buffer
    try createTestBuffer(&ctx, 1);
    setViewportSize(&ctx, 10, 80);

    // j and k should not crash
    try ctx.executeKeys("j");
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);

    try ctx.executeKeys("k");
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);

    // G and gg should work
    try ctx.executeKeys("G");
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);

    try ctx.executeKeys("gg");
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
}

test "Viewport: viewport size equals file size" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup: 10-line buffer with 10-line viewport (exact fit)
    try createTestBuffer(&ctx, 10);
    setViewportSize(&ctx, 10, 80);

    // Navigate to end
    try ctx.executeKeys("G");
    try std.testing.expectEqual(@as(usize, 9), ctx.buffer().cursor.row);
    // Viewport should not need to scroll (file fits exactly)
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));

    // Navigate to start
    try ctx.executeKeys("gg");
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));
}

test "Viewport: rapid j/k movement maintains consistency" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 100);
    setViewportSize(&ctx, 20, 80);

    // Rapid down/up cycles
    for (0..5) |_| {
        try ctx.executeKeys("jjjjjjjjjj"); // 10 down
        try ctx.executeKeys("kkkkkkkkkk"); // 10 up
    }

    // Should end up back at start
    try std.testing.expectEqual(@as(usize, 0), ctx.buffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), getViewportTop(&ctx));
}

// ============================================================================
// Viewport Position Commands (H/M/L)
// ============================================================================

test "Viewport: H moves to top of viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 20, 80);

    // Move down then use H
    try ctx.executeKeys("jjjjjjjjjj"); // Move to line 10

    // H moves to top of visible viewport
    try ctx.executeKeys("H");

    // Cursor should be at viewport_top
    try std.testing.expectEqual(getViewportTop(&ctx), ctx.buffer().cursor.row);
}

test "Viewport: M moves to middle of viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 20, 80);

    // Move down then use M
    try ctx.executeKeys("jjjjjjjjjj"); // Move to line 10

    // M moves to middle of visible viewport
    try ctx.executeKeys("M");

    // Cursor should be near middle of viewport
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);
    const expected_middle = viewport_top + text_rows / 2;

    // Allow ±1 tolerance for odd viewport heights
    const diff = if (ctx.buffer().cursor.row >= expected_middle)
        ctx.buffer().cursor.row - expected_middle
    else
        expected_middle - ctx.buffer().cursor.row;
    try std.testing.expect(diff <= 1);
}

test "Viewport: L moves to bottom of viewport" {
    const allocator = std.testing.allocator;
    var ctx = try EditorContext.init(allocator);
    defer ctx.deinit();

    // Setup
    try createTestBuffer(&ctx, 50);
    setViewportSize(&ctx, 20, 80);

    // L moves to bottom of visible viewport
    try ctx.executeKeys("L");

    // Cursor should be at viewport bottom
    const viewport_top = getViewportTop(&ctx);
    const text_rows = getTextRows(&ctx);
    const expected_bottom = viewport_top + text_rows - 1;

    try std.testing.expectEqual(expected_bottom, ctx.buffer().cursor.row);
}
