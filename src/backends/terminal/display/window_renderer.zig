const std = @import("std");
const Display = @import("display.zig").Display;
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const Window = @import("../../../editor/window.zig").Window;
const WindowId = @import("../../../editor/window.zig").WindowId;
const Editor = @import("../../../editor/editor.zig").Editor;
const highlights = @import("../../../editor/config/highlights.zig");
const VisualState = @import("../../../editor/visual/visual.zig").VisualState;
const YankHighlight = @import("../../../editor/visual/yank_highlight.zig").YankHighlight;
const Position = @import("../../../editor/visual/visual.zig").Position;
const char_width = @import("char_width.zig");
const ListChars = @import("../../../editor/config/listchars.zig").ListChars;
const gutter = @import("gutter.zig");
const Cell = @import("screen_grid.zig").Cell;
const Layer = @import("layer.zig").Layer;
const HighlightRegistry = @import("../../../system/jsi/highlight_api.zig").HighlightRegistry;
const Style = @import("../../../system/jsi/highlight_api.zig").Style;
const Color = @import("../../../system/jsi/highlight_api.zig").Color;

// Syntax highlighting support
const Syntax = @import("../../../editor/treesitter/syntax.zig").Syntax;
const SyntaxHighlighter = @import("../../../editor/treesitter/syntax_highlighter.zig").SyntaxHighlighter;
const Range = @import("../../../editor/treesitter/highlight.zig").Range;

// ============================================================================
// Window Renderer
// ============================================================================
// Renders a single window's content to a specific region of the compositor's layers.
// Each window has its own viewport, cursor position, gutter configuration, etc.
//
// This follows Neovim's architecture where windows are rendered to a shared
// frame buffer with proper clipping to window bounds.

/// Region on screen where a window renders
pub const WindowRegion = struct {
    /// Top-left row (0-indexed)
    row: usize,
    /// Top-left column (0-indexed)
    col: usize,
    /// Height in rows (excluding statusline)
    height: usize,
    /// Width in columns
    width: usize,
};

/// Window rendering context
pub const WindowRenderContext = struct {
    /// Window being rendered
    window: *Window,
    /// Buffer displayed in window
    buffer: *Buffer,
    /// Window region on screen
    region: WindowRegion,
    /// Whether this is the active (focused) window
    is_active: bool,
    /// Highlight registry
    registry: *const HighlightRegistry,
    /// Visual mode state (if active in this window)
    visual_state: *const VisualState,
    /// Yank highlight state (if active in this window)
    yank_highlight: *const YankHighlight,
    /// Whether cursorline is enabled
    cursorline_enabled: bool,
    /// Whether listchars are enabled
    list_enabled: bool,
    /// Listchars configuration
    listchars: *const ListChars,
    /// Tree-sitter syntax for highlighting (null if unavailable)
    syntax: ?*Syntax = null,
};

/// Render a window to the display's layers
/// This clips all rendering to the window's region
pub fn renderWindow(
    display: *Display,
    ctx: *const WindowRenderContext,
) !void {
    const window = ctx.window;
    const buffer = ctx.buffer;
    const region = ctx.region;

    // Calculate gutter width for this window
    const gutter_width = calculateWindowGutterWidth(window, buffer);

    // Ensure window cursor is visible in viewport
    ensureCursorVisible(window, buffer, region.height);

    // Render base layer (text content)
    try renderWindowBaseLayer(display, ctx, gutter_width);

    // Render gutter layer (line numbers)
    try renderWindowGutterLayer(display, ctx, gutter_width);

    // Render cursor layer (cursorline highlight)
    if (ctx.cursorline_enabled and ctx.is_active) {
        try renderWindowCursorLayer(display, ctx, gutter_width);
    }

    // Render selection layer (visual mode)
    if (ctx.visual_state.active and ctx.is_active) {
        try renderWindowSelectionLayer(display, ctx, gutter_width);
    }

    // Render yank highlight layer
    if (ctx.yank_highlight.active and ctx.yank_highlight.isVisible() and ctx.is_active) {
        try renderWindowYankLayer(display, ctx, gutter_width);
    }

    // Mark window as rendered
    window.needs_redraw = false;
}

/// Ensure cursor is visible within window viewport
fn ensureCursorVisible(window: *Window, buffer: *const Buffer, visible_height: usize) void {
    const scrolloff = window.options.scrolloff;
    const cursor_row = window.cursor.row;

    // Clamp cursor to buffer bounds
    const max_row = if (buffer.lineCount() > 0) buffer.lineCount() - 1 else 0;
    if (window.cursor.row > max_row) {
        window.cursor.row = max_row;
    }

    // Vertical scrolling
    if (visible_height > 0) {
        if (cursor_row < window.viewport.top_line + scrolloff) {
            window.viewport.top_line = if (cursor_row > scrolloff)
                cursor_row - scrolloff
            else
                0;
        } else if (cursor_row >= window.viewport.top_line + visible_height - scrolloff) {
            window.viewport.top_line = cursor_row -| (visible_height -| scrolloff -| 1);
        }
    }

    // Update cursor screen position
    window.viewport.cursor_screen_row = cursor_row -| window.viewport.top_line;
    window.viewport.cursor_screen_col = window.cursor.col -| window.viewport.left_col;
}

/// Calculate gutter width for a window
fn calculateWindowGutterWidth(window: *const Window, buffer: *const Buffer) usize {
    var width: usize = 0;

    // Sign column
    if (window.options.signcolumn == .yes) {
        width += 2;
    }

    // Line numbers
    if (window.options.number or window.options.relativenumber) {
        const line_count = buffer.lineCount();
        const digits = if (line_count > 0)
            std.math.log10(line_count) + 1
        else
            1;
        width += @max(digits, 4) + 1; // minimum 4 digits + 1 space
    }

    return width;
}

/// Render window text content to base layer
fn renderWindowBaseLayer(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    const buffer = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;

    // Get Normal highlight from registry
    const normal_style = ctx.registry.get("Normal");
    const fg_color = if (normal_style.fg) |c| convertColor(c) else null;
    const bg_color = if (normal_style.bg) |c| convertColor(c) else null;

    // Create syntax highlighter if syntax is available
    var syntax_highlighter: ?SyntaxHighlighter = null;
    if (ctx.syntax) |syntax| {
        syntax_highlighter = SyntaxHighlighter.init(
            display.allocator,
            syntax,
            ctx.registry,
        );
    }

    var row: usize = 0;
    while (row < region.height) : (row += 1) {
        const line_num = window.viewport.top_line + row;
        const screen_row = region.row + row;

        // Skip if outside layer bounds
        if (screen_row >= display.base_layer.grid.height) continue;

        if (line_num < buffer.lineCount()) {
            const line = buffer.getLine(line_num) orelse continue;
            defer buffer.allocator.free(line);

            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;

            // Apply horizontal scroll
            const h_offset = window.viewport.left_col;
            const start_byte = if (h_offset > 0)
                char_width.displayColumnToByte(line_without_newline, h_offset)
            else
                0;
            const remaining = line_without_newline[start_byte..];

            // Calculate absolute byte offset in buffer for tree-sitter
            const line_byte_offset = buffer.content.byteOfLine(line_num);
            const text_byte_offset = line_byte_offset + start_byte;

            // Build syntax highlight map for this line (if syntax available)
            var highlight_map = std.AutoHashMap(usize, Style).init(display.allocator);
            defer highlight_map.deinit();

            if (syntax_highlighter) |*sh| {
                const range = Range{
                    .start_byte = @intCast(text_byte_offset),
                    .end_byte = @intCast(text_byte_offset + remaining.len),
                };

                var iter = sh.highlights(range) catch null;
                if (iter) |*it| {
                    defer it.deinit();
                    while (it.next()) |styled| {
                        const range_start = if (styled.range.start_byte >= text_byte_offset)
                            styled.range.start_byte - text_byte_offset
                        else
                            0;
                        const range_end = if (styled.range.end_byte >= text_byte_offset)
                            @min(styled.range.end_byte - text_byte_offset, remaining.len)
                        else
                            0;

                        var byte_offset = range_start;
                        while (byte_offset < range_end) : (byte_offset += 1) {
                            highlight_map.put(byte_offset, styled.style) catch {};
                        }
                    }
                }
            }

            // Render text to base layer (clipped to window region)
            const start_col = region.col + gutter_width;
            var screen_col: usize = start_col;
            var byte_idx: usize = 0;

            while (byte_idx < remaining.len and screen_col < region.col + region.width) {
                const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                if (byte_idx + char_len > remaining.len) break;

                const codepoint = std.unicode.utf8Decode(remaining[byte_idx..][0..char_len]) catch ' ';

                // Get display width of character (1 for normal, 2 for wide chars like emoji/CJK)
                const display_width = char_width.codepointWidth(codepoint);

                // Skip zero-width characters (combining marks, variation selectors)
                if (display_width == 0) {
                    byte_idx += char_len;
                    continue;
                }

                // Look up syntax highlight for this character
                const syntax_style = highlight_map.get(byte_idx);
                const char_fg = if (syntax_style) |style|
                    if (style.fg) |c| convertColor(c) else fg_color
                else
                    fg_color;
                const char_bg = if (syntax_style) |style|
                    if (style.bg) |c| convertColor(c) else bg_color
                else
                    bg_color;

                // Clip to window bounds
                if (screen_col >= region.col + gutter_width and screen_col < region.col + region.width) {
                    display.base_layer.grid.setCell(screen_row, screen_col, .{
                        .char = codepoint,
                        .fg = char_fg,
                        .bg = char_bg,
                    });

                    // For wide characters (width 2), set continuation marker on next cell
                    if (display_width == 2 and screen_col + 1 < region.col + region.width) {
                        display.base_layer.grid.setCell(screen_row, screen_col + 1, .{
                            .char = ' ',
                            .fg = char_fg,
                            .bg = char_bg,
                            .is_continuation = true,
                        });
                    }
                }

                screen_col += display_width;
                byte_idx += char_len;
            }

            // Fill rest of line with spaces
            while (screen_col < region.col + region.width) : (screen_col += 1) {
                display.base_layer.grid.setCell(screen_row, screen_col, .{
                    .char = ' ',
                    .bg = bg_color,
                });
            }
        } else {
            // Empty line indicator (~)
            const start_col = region.col + gutter_width;
            display.base_layer.grid.setCell(screen_row, start_col, .{
                .char = '~',
                .fg = fg_color,
                .bg = bg_color,
            });

            // Fill rest with spaces
            var col = start_col + 1;
            while (col < region.col + region.width) : (col += 1) {
                display.base_layer.grid.setCell(screen_row, col, .{
                    .char = ' ',
                    .bg = bg_color,
                });
            }
        }
    }

    display.base_layer.markDirty();
}

/// Render window gutter (line numbers) to gutter layer
fn renderWindowGutterLayer(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    if (gutter_width == 0) return;

    // buffer is accessed via ctx when needed for line count bounds checking
    _ = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;

    var row: usize = 0;
    while (row < region.height) : (row += 1) {
        const line_num = window.viewport.top_line + row;
        const screen_row = region.row + row;

        // Skip if outside layer bounds
        if (screen_row >= display.gutter_layer.grid.height) continue;

        // Get line number style
        const is_cursor_line = (line_num == window.cursor.row);
        const line_nr_style = if (is_cursor_line)
            ctx.registry.get("CursorLineNr")
        else
            ctx.registry.get("LineNr");

        const gutter_fg = if (line_nr_style.fg) |c| convertColor(c) else null;
        const gutter_bg = if (line_nr_style.bg) |c| convertColor(c) else null;

        // Render line number
        if (window.options.number or window.options.relativenumber) {
            const display_num = if (window.options.relativenumber and !is_cursor_line)
                if (line_num > window.cursor.row)
                    line_num - window.cursor.row
                else
                    window.cursor.row - line_num
            else
                line_num + 1; // Convert to 1-indexed

            var buf: [16]u8 = undefined;
            const num_str = std.fmt.bufPrint(&buf, "{d: >4} ", .{display_num}) catch " 0 ";

            var gutter_col: usize = 0;
            for (num_str) |ch| {
                if (gutter_col >= gutter_width) break;
                display.gutter_layer.grid.setCell(screen_row, region.col + gutter_col, .{
                    .char = ch,
                    .fg = gutter_fg,
                    .bg = gutter_bg,
                });
                gutter_col += 1;
            }

            // Pad remaining gutter space
            while (gutter_col < gutter_width) : (gutter_col += 1) {
                display.gutter_layer.grid.setCell(screen_row, region.col + gutter_col, .{
                    .char = ' ',
                    .fg = gutter_fg,
                    .bg = gutter_bg,
                });
            }
        }
    }

    display.gutter_layer.markDirty();
}

/// Render window cursor line highlight to cursor layer
fn renderWindowCursorLayer(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    const window = ctx.window;
    const region = ctx.region;

    // Check if cursor line is visible
    const cursor_line = window.cursor.row;
    if (cursor_line < window.viewport.top_line or
        cursor_line >= window.viewport.top_line + region.height)
    {
        return;
    }

    const screen_row = region.row + (cursor_line - window.viewport.top_line);

    // Get CursorLine highlight
    const cursorline_style = ctx.registry.get("CursorLine");
    if (cursorline_style.bg == null) return;

    const cursorline_bg = convertColor(cursorline_style.bg.?);

    // Render cursorline background (text area only, not gutter)
    const start_col = region.col + gutter_width;
    var col = start_col;
    while (col < region.col + region.width) : (col += 1) {
        display.cursor_layer.grid.setCell(screen_row, col, .{
            .char = 0, // NULL - won't hide base layer text
            .bg = cursorline_bg,
        });
    }

    display.cursor_layer.markDirty();
}

/// Render window visual selection to selection layer
fn renderWindowSelectionLayer(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    const buffer = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;
    const visual_state = ctx.visual_state;

    const cursor_pos = Position{
        .line = window.cursor.row,
        .col = window.cursor.col,
    };
    const visual_range = visual_state.getRange(cursor_pos);

    // Get Visual highlight
    const visual_style = ctx.registry.get("Visual");
    const visual_bg = if (visual_style.bg) |c|
        convertColor(c)
    else
        highlights.Color{ .r = 80, .g = 80, .b = 80 };

    var row: usize = 0;
    while (row < region.height) : (row += 1) {
        const line_num = window.viewport.top_line + row;
        const screen_row = region.row + row;

        // Check if line is in selection range
        if (line_num >= visual_range.start.line and line_num <= visual_range.end.line) {
            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num) orelse continue;
                defer buffer.allocator.free(line);

                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll
                const h_offset = window.viewport.left_col;
                const start_byte = if (h_offset > 0)
                    char_width.displayColumnToByte(line_without_newline, h_offset)
                else
                    0;
                const remaining = line_without_newline[start_byte..];

                // Render selection highlight
                var screen_col: usize = region.col + gutter_width;
                var byte_idx: usize = 0;

                while (byte_idx < remaining.len and screen_col < region.col + region.width) {
                    const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                    if (byte_idx + char_len > remaining.len) break;

                    const buffer_col = start_byte + byte_idx;
                    const char_pos = Position{
                        .line = line_num,
                        .col = buffer_col,
                    };

                    if (visual_state.contains(cursor_pos, char_pos)) {
                        display.selection_layer.grid.setCell(screen_row, screen_col, .{
                            .char = ' ', // Transparent, just background
                            .bg = visual_bg,
                        });
                    }

                    screen_col += 1;
                    byte_idx += char_len;
                }
            }
        }
    }

    display.selection_layer.markDirty();
}

/// Render window yank highlight to yank layer
fn renderWindowYankLayer(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    const buffer = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;
    const yank_highlight = ctx.yank_highlight;

    // Get YankFlash highlight
    const yank_style = ctx.registry.get("YankFlash");
    const yank_bg = if (yank_style.bg) |c|
        convertColor(c)
    else
        highlights.Color{ .r = 100, .g = 100, .b = 50 };

    var row: usize = 0;
    while (row < region.height) : (row += 1) {
        const line_num = window.viewport.top_line + row;
        const screen_row = region.row + row;

        if (line_num >= yank_highlight.start.line and line_num <= yank_highlight.end.line) {
            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num) orelse continue;
                defer buffer.allocator.free(line);

                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll
                const h_offset = window.viewport.left_col;
                const start_byte = if (h_offset > 0)
                    char_width.displayColumnToByte(line_without_newline, h_offset)
                else
                    0;
                const remaining = line_without_newline[start_byte..];

                var screen_col: usize = region.col + gutter_width;
                var byte_idx: usize = 0;

                while (byte_idx < remaining.len and screen_col < region.col + region.width) {
                    const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                    if (byte_idx + char_len > remaining.len) break;

                    const buffer_col = start_byte + byte_idx;
                    const char_pos = Position{
                        .line = line_num,
                        .col = buffer_col,
                    };

                    if (yank_highlight.contains(char_pos)) {
                        display.yank_layer.grid.setCell(screen_row, screen_col, .{
                            .char = ' ',
                            .bg = yank_bg,
                        });
                    }

                    screen_col += 1;
                    byte_idx += char_len;
                }
            }
        }
    }

    display.yank_layer.markDirty();
}

/// Render window statusline
pub fn renderWindowStatusline(
    display: *Display,
    window: *const Window,
    buffer: *const Buffer,
    region: WindowRegion,
    is_active: bool,
    registry: *const HighlightRegistry,
) !void {
    const status_row = region.row + region.height;

    // Skip if outside grid bounds
    if (status_row >= display.terminal_rows) return;

    // Get StatusLine or StatusLineNC highlight
    const style = if (is_active)
        registry.get("StatusLine")
    else
        registry.get("StatusLineNC");

    // Format status text
    const filename = buffer.filepath orelse "[No Name]";
    const modified = if (buffer.modified) "[+]" else "";

    var status_buf: [256]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, " {s}{s} {d}:{d}", .{
        filename,
        modified,
        window.cursor.row + 1,
        window.cursor.col + 1,
    }) catch "[Error]";

    // Get colors
    const has_custom_style = style.fg != null or style.bg != null;

    var col: usize = 0;
    while (col < region.width) : (col += 1) {
        const char: u8 = if (col < status.len) status[col] else ' ';
        const screen_col = region.col + col;

        if (screen_col >= display.terminal_cols) break;

        // Create cell with appropriate styling
        var cell = Cell{
            .char = char,
            .fg = null,
            .bg = null,
        };

        if (has_custom_style) {
            if (style.fg) |fg| cell.fg = convertColor(fg);
            if (style.bg) |bg| cell.bg = convertColor(bg);
        } else {
            // Fallback: inverse video
            cell.fg = highlights.Color{ .r = 0, .g = 0, .b = 0 };
            cell.bg = highlights.Color{ .r = 200, .g = 200, .b = 200 };
        }

        // Write directly to base layer (statusline is part of base content)
        display.base_layer.grid.setCell(status_row, screen_col, cell);
    }

    display.base_layer.markDirty();
}

/// Convert highlight_api.Color to highlights.Color
fn convertColor(api_color: Color) highlights.Color {
    return switch (api_color) {
        .rgb => |rgb| highlights.Color{ .r = rgb.r, .g = rgb.g, .b = rgb.b },
        .indexed => |idx| highlights.Color{ .r = idx, .g = idx, .b = idx },
    };
}

// ============================================================================
// Tests
// ============================================================================

test "calculateWindowGutterWidth with number enabled" {
    const allocator = std.testing.allocator;

    // Create mock buffer with 100 lines
    var buffer = try @import("../../../editor/buffer/buffer.zig").Buffer.init(allocator);
    defer buffer.deinit();

    // Add some lines
    try buffer.insertString("line 1\nline 2\nline 3\n");

    // Create window with line numbers enabled
    const WindowModule = @import("../../../editor/window.zig");
    var window = WindowModule.Window.init(
        allocator,
        WindowModule.WindowId{ .id = 0 },
        @import("../../../editor/window.zig").BufferId{ .id = 0 },
    );
    defer window.deinit();

    window.options.number = true;

    const gutter_width = calculateWindowGutterWidth(&window, &buffer);

    // Should be at least 4 digits + 1 space = 5
    try std.testing.expect(gutter_width >= 5);
}

test "calculateWindowGutterWidth with no line numbers" {
    const allocator = std.testing.allocator;

    var buffer = try @import("../../../editor/buffer/buffer.zig").Buffer.init(allocator);
    defer buffer.deinit();

    const WindowModule = @import("../../../editor/window.zig");
    var window = WindowModule.Window.init(
        allocator,
        WindowModule.WindowId{ .id = 0 },
        @import("../../../editor/window.zig").BufferId{ .id = 0 },
    );
    defer window.deinit();

    window.options.number = false;
    window.options.relativenumber = false;

    const gutter_width = calculateWindowGutterWidth(&window, &buffer);

    // Should be 0 without line numbers
    try std.testing.expectEqual(@as(usize, 0), gutter_width);
}
