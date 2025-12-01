const std = @import("std");
const Display = @import("display.zig").Display;
const Window = @import("../../../editor/window.zig").Window;
const WindowId = @import("../../../editor/window.zig").WindowId;
const WindowLayout = @import("../../../editor/window_layout.zig").WindowLayout;
const LayoutNode = @import("../../../editor/window_layout.zig").LayoutNode;
const SplitDirection = @import("../../../editor/window_layout.zig").SplitDirection;
const highlights = @import("../../../editor/config/highlights.zig");
const Cell = @import("screen_grid.zig").Cell;
const HighlightRegistry = @import("../../../system/jsi/highlight_api.zig").HighlightRegistry;
const Color = @import("../../../system/jsi/highlight_api.zig").Color;

// ============================================================================
// Separator Renderer
// ============================================================================
// Renders separator lines between split windows.
// - Vertical splits: draws a │ (vertical bar) column between windows
// - Horizontal splits: uses statuslines as separators (no additional rendering)
//
// This follows Neovim's approach where vertical separators are drawn with
// the VertSplit highlight group, and horizontal separators are implicit
// (the statusline of the upper window serves as the separator).

/// Box-drawing characters for separators
pub const SeparatorChars = struct {
    /// Vertical separator character (between left/right splits)
    vertical: u21 = '│', // U+2502 BOX DRAWINGS LIGHT VERTICAL

    /// Horizontal separator character (between top/bottom splits)
    /// Note: Usually not rendered since statusline serves this purpose
    horizontal: u21 = '─', // U+2500 BOX DRAWINGS LIGHT HORIZONTAL

    /// Intersection characters
    cross: u21 = '┼', // U+253C BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
    top_tee: u21 = '┬', // U+252C
    bottom_tee: u21 = '┴', // U+2534
    left_tee: u21 = '├', // U+251C
    right_tee: u21 = '┤', // U+2524
};

/// Bounds structure for layout calculations
const Bounds = struct {
    row: usize,
    col: usize,
    height: usize,
    width: usize,
};

/// Render all window separators
pub fn renderSeparators(
    display: *Display,
    layout: *WindowLayout,
    windows: *std.AutoHashMap(WindowId, *Window),
    registry: *const HighlightRegistry,
) void {
    // Get VertSplit highlight from registry
    const vertsplit_style = registry.get("VertSplit");
    const sep_fg = if (vertsplit_style.fg) |c|
        convertColor(c)
    else
        highlights.Color{ .r = 100, .g = 100, .b = 100 };
    const sep_bg = if (vertsplit_style.bg) |c| convertColor(c) else null;

    // Recursively render separators for each split node
    renderNodeSeparators(display, layout.root, windows, sep_fg, sep_bg);

    display.base_layer.markDirty();
}

/// Recursively render separators for a layout node
fn renderNodeSeparators(
    display: *Display,
    node: *LayoutNode,
    windows: *std.AutoHashMap(WindowId, *Window),
    sep_fg: highlights.Color,
    sep_bg: ?highlights.Color,
) void {
    switch (node.*) {
        .window => {
            // Leaf node - no separators to render
        },
        .split => |s| {
            switch (s.direction) {
                .vertical => {
                    // Draw vertical separator between first and second child
                    const first_bounds = getBounds(s.first, windows);

                    // Separator column is immediately after first child
                    const sep_col = first_bounds.col + first_bounds.width;

                    // Draw │ from top to bottom of the split region
                    var row = first_bounds.row;
                    const end_row = first_bounds.row + first_bounds.height;

                    while (row < end_row) : (row += 1) {
                        // Skip if outside grid bounds
                        if (row >= display.base_layer.grid.height) continue;
                        if (sep_col >= display.base_layer.grid.width) continue;

                        display.base_layer.grid.setCell(row, sep_col, .{
                            .char = '│',
                            .fg = sep_fg,
                            .bg = sep_bg,
                        });
                    }
                },
                .horizontal => {
                    // Horizontal splits use statuslines as separators
                    // No additional rendering needed - the statusline of the
                    // upper window naturally separates it from the lower window
                },
            }

            // Recurse into children
            renderNodeSeparators(display, s.first, windows, sep_fg, sep_bg);
            renderNodeSeparators(display, s.second, windows, sep_fg, sep_bg);
        },
    }
}

/// Get the screen bounds of a layout node (including statusline)
fn getBounds(node: *LayoutNode, windows: *std.AutoHashMap(WindowId, *Window)) Bounds {
    switch (node.*) {
        .window => |id| {
            if (windows.get(id)) |win| {
                return .{
                    .row = win.screen_row,
                    .col = win.screen_col,
                    .height = win.height + 1, // Include statusline row
                    .width = win.width,
                };
            }
            return .{ .row = 0, .col = 0, .height = 0, .width = 0 };
        },
        .split => |s| {
            const first = getBounds(s.first, windows);
            const second = getBounds(s.second, windows);
            return .{
                .row = @min(first.row, second.row),
                .col = @min(first.col, second.col),
                .height = @max(first.row + first.height, second.row + second.height) -| @min(first.row, second.row),
                .width = @max(first.col + first.width, second.col + second.width) -| @min(first.col, second.col),
            };
        },
    }
}

/// Convert highlight_api.Color to highlights.Color
// Use shared color conversion (DRY)
fn convertColor(api_color: Color) highlights.Color {
    return highlights.Color.fromApiColor(api_color);
}

// ============================================================================
// Alternative Separator Styles
// ============================================================================
// Neovim supports various separator styles via 'fillchars' option:
//
// Basic ASCII:
//   vert = '|'      Vertical separator
//   horiz = '-'     Horizontal separator (rarely used)
//
// Unicode Box Drawing (default in modern terminals):
//   vert = '│'      U+2502 BOX DRAWINGS LIGHT VERTICAL
//   horiz = '─'     U+2500 BOX DRAWINGS LIGHT HORIZONTAL
//
// Heavy Box Drawing:
//   vert = '┃'      U+2503 BOX DRAWINGS HEAVY VERTICAL
//   horiz = '━'     U+2501 BOX DRAWINGS HEAVY HORIZONTAL
//
// Double Box Drawing:
//   vert = '║'      U+2551 BOX DRAWINGS DOUBLE VERTICAL
//   horiz = '═'     U+2550 BOX DRAWINGS DOUBLE HORIZONTAL
//
// Future: Add 'fillchars' option support in vim.opt

// ============================================================================
// Tests
// ============================================================================

test "getBounds for single window" {
    const allocator = std.testing.allocator;

    var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
    defer windows.deinit();

    const WindowModule = @import("../../../editor/window.zig");
    var window = WindowModule.Window.init(
        allocator,
        WindowModule.WindowId{ .id = 0 },
        @import("../../../editor/window.zig").BufferId{ .id = 0 },
    );
    defer window.deinit();

    window.screen_row = 0;
    window.screen_col = 0;
    window.height = 10;
    window.width = 40;

    try windows.put(WindowModule.WindowId{ .id = 0 }, &window);

    var layout = try WindowLayout.init(allocator, WindowModule.WindowId{ .id = 0 });
    defer layout.deinit();

    const bounds = getBounds(layout.root, &windows);

    try std.testing.expectEqual(@as(usize, 0), bounds.row);
    try std.testing.expectEqual(@as(usize, 0), bounds.col);
    try std.testing.expectEqual(@as(usize, 11), bounds.height); // 10 + 1 for statusline
    try std.testing.expectEqual(@as(usize, 40), bounds.width);
}
