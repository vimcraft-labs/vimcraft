const std = @import("std");
const Display = @import("display.zig").Display;
const ViewportState = @import("display.zig").ViewportState;
const Window = @import("../../../editor/window.zig").Window;
const WindowId = @import("../../../editor/window.zig").WindowId;
const BufferId = @import("../../../editor/window.zig").BufferId;

// ============================================================================
// ViewportState Unit Tests
// ============================================================================
// Tests for the ViewportState struct which provides an immutable viewport
// snapshot for the unified render path. ViewportState enables:
// 1. Testable renderers - can pass mock viewport without full Display
// 2. Explicit data flow - visible in function signatures
// 3. Zero-cost abstraction - passed via registers, no memory access

// ----------------------------------------------------------------------------
// Direct Construction Tests
// ----------------------------------------------------------------------------

test "ViewportState: direct construction with all fields" {
    const viewport = ViewportState{
        .top = 10,
        .left = 5,
        .height = 24,
        .width = 80,
        .gutter_width = 4,
    };

    try std.testing.expectEqual(@as(usize, 10), viewport.top);
    try std.testing.expectEqual(@as(usize, 5), viewport.left);
    try std.testing.expectEqual(@as(usize, 24), viewport.height);
    try std.testing.expectEqual(@as(usize, 80), viewport.width);
}

test "ViewportState: default/zero values" {
    const viewport = ViewportState{
        .top = 0,
        .left = 0,
        .height = 0,
        .width = 0,
        .gutter_width = 0,
    };

    try std.testing.expectEqual(@as(usize, 0), viewport.top);
    try std.testing.expectEqual(@as(usize, 0), viewport.left);
    try std.testing.expectEqual(@as(usize, 0), viewport.height);
    try std.testing.expectEqual(@as(usize, 0), viewport.width);
}

test "ViewportState: large values (stress test)" {
    // Test with large values that might occur in big files
    const viewport = ViewportState{
        .top = 1_000_000, // 1 million lines scrolled
        .left = 10_000, // Wide horizontal scroll
        .height = 100, // Large terminal
        .width = 300, // Wide terminal
        .gutter_width = 6, // Line numbers with wide gutter
    };

    try std.testing.expectEqual(@as(usize, 1_000_000), viewport.top);
    try std.testing.expectEqual(@as(usize, 10_000), viewport.left);
    try std.testing.expectEqual(@as(usize, 100), viewport.height);
    try std.testing.expectEqual(@as(usize, 300), viewport.width);
}

// ----------------------------------------------------------------------------
// fromDisplay Factory Tests
// ----------------------------------------------------------------------------

test "ViewportState.fromDisplay: creates viewport from Display state" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    // Set up display state
    display.viewport_top = 15;
    display.viewport_left = 3;
    display.terminal_rows = 25;
    display.terminal_cols = 80;

    const viewport = ViewportState.fromDisplay(&display);

    try std.testing.expectEqual(@as(usize, 15), viewport.top);
    try std.testing.expectEqual(@as(usize, 3), viewport.left);
    // Height should be terminal_rows - 1 (for statusline)
    try std.testing.expectEqual(@as(usize, 24), viewport.height);
    try std.testing.expectEqual(@as(usize, 80), viewport.width);
}

test "ViewportState.fromDisplay: handles single row terminal" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    // Edge case: terminal with only 1 row
    display.terminal_rows = 1;
    display.terminal_cols = 40;
    display.viewport_top = 0;
    display.viewport_left = 0;

    const viewport = ViewportState.fromDisplay(&display);

    // Height should be 1 when terminal_rows is 1 (minimum)
    try std.testing.expectEqual(@as(usize, 1), viewport.height);
    try std.testing.expectEqual(@as(usize, 40), viewport.width);
}

test "ViewportState.fromDisplay: handles zero row terminal" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    // Edge case: terminal_rows = 0 (shouldn't happen but should be handled)
    display.terminal_rows = 0;
    display.terminal_cols = 80;

    const viewport = ViewportState.fromDisplay(&display);

    // Height should be 1 (minimum, prevents underflow)
    try std.testing.expectEqual(@as(usize, 1), viewport.height);
}

test "ViewportState.fromDisplay: viewport scrolled far down" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    // Simulate scrolling down a large file
    display.viewport_top = 50000;
    display.viewport_left = 0;
    display.terminal_rows = 30;
    display.terminal_cols = 120;

    const viewport = ViewportState.fromDisplay(&display);

    try std.testing.expectEqual(@as(usize, 50000), viewport.top);
    try std.testing.expectEqual(@as(usize, 29), viewport.height);
    try std.testing.expectEqual(@as(usize, 120), viewport.width);
}

// ----------------------------------------------------------------------------
// fromWindow Factory Tests
// ----------------------------------------------------------------------------

test "ViewportState.fromWindow: creates viewport from Window state" {
    const allocator = std.testing.allocator;

    // Create a mock window
    var window = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 1 });
    defer window.deinit();

    // Set window viewport and dimensions
    window.viewport.top_line = 20;
    window.viewport.left_col = 10;
    window.height = 15;
    window.width = 60;

    const viewport = ViewportState.fromWindow(&window, 24, 80, 4); // 4 = typical gutter width

    try std.testing.expectEqual(@as(usize, 20), viewport.top);
    try std.testing.expectEqual(@as(usize, 10), viewport.left);
    try std.testing.expectEqual(@as(usize, 15), viewport.height);
    try std.testing.expectEqual(@as(usize, 60), viewport.width);
    try std.testing.expectEqual(@as(usize, 4), viewport.gutter_width);
}

test "ViewportState.fromWindow: clamps to terminal size" {
    const allocator = std.testing.allocator;

    var window = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 1 });
    defer window.deinit();

    // Window larger than terminal (e.g., after terminal resize)
    window.viewport.top_line = 0;
    window.viewport.left_col = 0;
    window.height = 100; // Larger than terminal
    window.width = 200; // Larger than terminal

    const viewport = ViewportState.fromWindow(&window, 24, 80, 4);

    // Should be clamped to terminal size
    try std.testing.expectEqual(@as(usize, 24), viewport.height);
    try std.testing.expectEqual(@as(usize, 80), viewport.width);
}

test "ViewportState.fromWindow: window smaller than terminal" {
    const allocator = std.testing.allocator;

    var window = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 1 });
    defer window.deinit();

    // Split window - smaller than terminal
    window.viewport.top_line = 5;
    window.viewport.left_col = 0;
    window.height = 10;
    window.width = 40;

    const viewport = ViewportState.fromWindow(&window, 24, 80, 4);

    // Should use window size (not clamped)
    try std.testing.expectEqual(@as(usize, 10), viewport.height);
    try std.testing.expectEqual(@as(usize, 40), viewport.width);
}

test "ViewportState.fromWindow: zero-size window" {
    const allocator = std.testing.allocator;

    var window = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 1 });
    defer window.deinit();

    // Edge case: minimized or zero-size window
    window.height = 0;
    window.width = 0;

    const viewport = ViewportState.fromWindow(&window, 24, 80, 4);

    try std.testing.expectEqual(@as(usize, 0), viewport.height);
    try std.testing.expectEqual(@as(usize, 0), viewport.width);
}

// ----------------------------------------------------------------------------
// Immutability Tests
// ----------------------------------------------------------------------------

test "ViewportState: is immutable after creation" {
    const viewport = ViewportState{
        .top = 10,
        .left = 5,
        .height = 24,
        .width = 80,
        .gutter_width = 4,
    };

    // ViewportState should be immutable - these values should not change
    // This test ensures the struct is used correctly as a snapshot
    try std.testing.expectEqual(@as(usize, 10), viewport.top);
    try std.testing.expectEqual(@as(usize, 5), viewport.left);
    try std.testing.expectEqual(@as(usize, 24), viewport.height);
    try std.testing.expectEqual(@as(usize, 80), viewport.width);

    // Attempting to modify should not affect original (if copied)
    var viewport_copy = viewport;
    viewport_copy.top = 999;

    // Original unchanged
    try std.testing.expectEqual(@as(usize, 10), viewport.top);
    // Copy changed
    try std.testing.expectEqual(@as(usize, 999), viewport_copy.top);
}

// ----------------------------------------------------------------------------
// Equality Tests
// ----------------------------------------------------------------------------

test "ViewportState: equality comparison" {
    const v1 = ViewportState{ .top = 10, .left = 5, .height = 24, .width = 80, .gutter_width = 4 };
    const v2 = ViewportState{ .top = 10, .left = 5, .height = 24, .width = 80, .gutter_width = 4 };
    const v3 = ViewportState{ .top = 11, .left = 5, .height = 24, .width = 80, .gutter_width = 4 };

    // Same values should be equal
    try std.testing.expect(std.meta.eql(v1, v2));

    // Different values should not be equal
    try std.testing.expect(!std.meta.eql(v1, v3));
}

// ----------------------------------------------------------------------------
// Consistency Tests (fromDisplay vs fromWindow)
// ----------------------------------------------------------------------------

test "ViewportState: fromDisplay and fromWindow produce consistent results" {
    const allocator = std.testing.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    display.viewport_top = 100;
    display.viewport_left = 20;
    display.terminal_rows = 25;
    display.terminal_cols = 80;

    var window = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 1 });
    defer window.deinit();

    // Configure window to match display (single-window mode)
    window.viewport.top_line = 100;
    window.viewport.left_col = 20;
    window.height = 24; // terminal_rows - 1 for statusline
    window.width = 80;

    const from_display = ViewportState.fromDisplay(&display);
    const gutter_width = display.gutter_manager.getTotalWidth();
    const from_window = ViewportState.fromWindow(&window, 25, 80, gutter_width);

    // In single-window mode, both should produce equivalent viewports
    try std.testing.expectEqual(from_display.top, from_window.top);
    try std.testing.expectEqual(from_display.left, from_window.left);
    try std.testing.expectEqual(from_display.height, from_window.height);
    try std.testing.expectEqual(from_display.width, from_window.width);
    try std.testing.expectEqual(from_display.gutter_width, from_window.gutter_width);
}

// ----------------------------------------------------------------------------
// Size Calculations
// ----------------------------------------------------------------------------

test "ViewportState: visible area calculation" {
    const viewport = ViewportState{
        .top = 0,
        .left = 0,
        .height = 24,
        .width = 80,
        .gutter_width = 4,
    };

    // Visible area = height * width
    const visible_cells = viewport.height * viewport.width;
    try std.testing.expectEqual(@as(usize, 1920), visible_cells);
}

test "ViewportState: visible line range" {
    const viewport = ViewportState{
        .top = 100,
        .left = 0,
        .height = 24,
        .width = 80,
        .gutter_width = 4,
    };

    // First visible line
    try std.testing.expectEqual(@as(usize, 100), viewport.top);

    // Last visible line (exclusive)
    const last_visible = viewport.top + viewport.height;
    try std.testing.expectEqual(@as(usize, 124), last_visible);
}
