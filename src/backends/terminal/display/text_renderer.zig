const std = @import("std");
const highlights = @import("../../../editor/config/highlights.zig");
const ListChars = @import("../../../editor/config/listchars.zig").ListChars;
const char_width = @import("char_width.zig");
const Cell = @import("screen_grid.zig").Cell;
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const HighlightRegistry = @import("../../../system/jsi/highlight_api.zig").HighlightRegistry;
const Style = @import("../../../system/jsi/highlight_api.zig").Style;
const Color = @import("../../../system/jsi/highlight_api.zig").Color;

// ============================================================================
// Shared Text Rendering Module
// ============================================================================
// This module provides unified text rendering functions used by both:
// - layer_renderer.zig (single-window mode)
// - window_renderer.zig (multi-window mode)
//
// This eliminates DRY violations and ensures consistent behavior for:
// - Listchars (tabs, spaces, trailing whitespace, EOL)
// - Syntax highlighting
// - Wide character support (emoji, CJK)
// - Namespace highlights (LSP diagnostics)

/// Pre-computed listchars highlight colors (performance optimization)
/// Computed once per frame/window to avoid repeated registry lookups
pub const ListCharsColors = struct {
    ws_fg: ?highlights.Color, // Whitespace foreground (space, tab)
    ws_bg: ?highlights.Color, // Whitespace background
    sk_fg: ?highlights.Color, // SpecialKey foreground (trail, eol)
    sk_bg: ?highlights.Color, // SpecialKey background
};

/// Compute listchars highlight colors from registry (call once per frame/window)
/// Uses Neovim-compatible fallback chain: Whitespace → SpecialKey → NonText → Normal
pub fn computeListCharsColors(
    registry: *const HighlightRegistry,
    normal_fg: ?highlights.Color,
    normal_bg: ?highlights.Color,
) ListCharsColors {
    const whitespace_style = registry.get("Whitespace");
    const special_key_style = registry.get("SpecialKey");
    const non_text_style = registry.get("NonText");

    const whitespace_fg = if (whitespace_style.fg) |c| convertColor(c) else null;
    const whitespace_bg = if (whitespace_style.bg) |c| convertColor(c) else null;
    const special_key_fg = if (special_key_style.fg) |c| convertColor(c) else null;
    const special_key_bg = if (special_key_style.bg) |c| convertColor(c) else null;
    const non_text_fg = if (non_text_style.fg) |c| convertColor(c) else null;
    const non_text_bg = if (non_text_style.bg) |c| convertColor(c) else null;

    return .{
        // Whitespace colors: Whitespace → SpecialKey → NonText → Normal
        .ws_fg = whitespace_fg orelse special_key_fg orelse non_text_fg orelse normal_fg,
        .ws_bg = whitespace_bg orelse special_key_bg orelse non_text_bg orelse normal_bg,
        // SpecialKey colors: SpecialKey → NonText → Normal
        .sk_fg = special_key_fg orelse non_text_fg orelse normal_fg,
        .sk_bg = special_key_bg orelse non_text_bg orelse normal_bg,
    };
}

/// Render context for text rendering
pub const RenderContext = struct {
    grid: *ScreenGrid,
    row: usize, // Screen row
    start_col: usize, // Starting column (after gutter)
    max_col: usize, // Maximum column (region boundary)
    fg_color: ?highlights.Color,
    bg_color: ?highlights.Color,
    list_enabled: bool,
    listchars: *const ListChars,
    lc_colors: ListCharsColors,
    /// Optional syntax highlight map (byte offset → Style)
    /// If null, no syntax highlighting is applied
    syntax_map: ?*const std.AutoHashMap(usize, Style),
};

/// Render a line of text with full feature support
/// Returns the ending column (for filling rest of line)
///
/// Features:
/// - Listchars (tabs, spaces, nbsp, trailing whitespace, EOL)
/// - Syntax highlighting (when syntax_map provided)
/// - Wide character support (emoji, CJK)
/// - Zero-width character handling (combining marks)
pub fn renderTextLine(ctx: RenderContext, text: []const u8) usize {
    var screen_col = ctx.start_col;
    var byte_idx: usize = 0;

    // Track trailing whitespace position for listchars.trail
    var last_non_space_col = ctx.start_col;

    while (byte_idx < text.len and screen_col < ctx.max_col) {
        const char_len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + char_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[byte_idx..][0..char_len]) catch ' ';

        // Get display width (1 for normal, 2 for wide chars, 0 for combining)
        const display_width = char_width.codepointWidth(codepoint);

        // Skip zero-width characters (combining marks, variation selectors)
        if (display_width == 0) {
            byte_idx += char_len;
            continue;
        }

        // Get syntax highlight for this character (if available)
        var char_fg = ctx.fg_color;
        var char_bg = ctx.bg_color;
        if (ctx.syntax_map) |syn_map| {
            if (syn_map.get(byte_idx)) |style| {
                if (style.fg) |c| char_fg = convertColor(c);
                if (style.bg) |c| char_bg = convertColor(c);
            }
        }

        // Handle tabs specially (expand to multiple cells)
        if (ctx.list_enabled and codepoint == '\t' and ctx.listchars.tab[0] != 0) {
            screen_col = renderTab(ctx.grid, ctx.row, screen_col, ctx.max_col, ctx.listchars, ctx.lc_colors);
            last_non_space_col = screen_col;
            byte_idx += char_len;
            continue;
        }

        // Apply listchars replacements for spaces/nbsp
        var display_char = codepoint;
        var use_ws_colors = false;

        if (ctx.list_enabled) {
            switch (codepoint) {
                ' ' => {
                    if (ctx.listchars.space != 0) {
                        display_char = ctx.listchars.space;
                        use_ws_colors = true;
                    }
                },
                0xA0 => { // Non-breaking space
                    if (ctx.listchars.nbsp != 0) {
                        display_char = ctx.listchars.nbsp;
                        use_ws_colors = true;
                    }
                },
                else => {
                    // Non-whitespace - update trailing space tracker
                    last_non_space_col = screen_col + display_width;
                },
            }
        } else {
            // Track non-space even without listchars
            if (codepoint != ' ' and codepoint != '\t') {
                last_non_space_col = screen_col + display_width;
            }
        }

        // Apply colors
        const final_fg = if (use_ws_colors) ctx.lc_colors.ws_fg else char_fg;
        const final_bg = if (use_ws_colors) ctx.lc_colors.ws_bg else char_bg;

        // Render cell
        if (screen_col < ctx.max_col) {
            ctx.grid.setCell(ctx.row, screen_col, .{
                .char = display_char,
                .fg = final_fg,
                .bg = final_bg,
            });

            // Handle wide characters (set continuation marker)
            if (display_width == 2 and screen_col + 1 < ctx.max_col) {
                ctx.grid.setCell(ctx.row, screen_col + 1, .{
                    .char = ' ',
                    .fg = final_fg,
                    .bg = final_bg,
                    .is_continuation = true,
                });
            }
        }

        screen_col += display_width;
        byte_idx += char_len;
    }

    // Mark trailing spaces with trail character
    if (ctx.list_enabled and ctx.listchars.trail != 0) {
        var trail_col = last_non_space_col;
        while (trail_col < screen_col and trail_col < ctx.max_col) : (trail_col += 1) {
            ctx.grid.setCell(ctx.row, trail_col, .{
                .char = ctx.listchars.trail,
                .fg = ctx.lc_colors.sk_fg,
                .bg = ctx.lc_colors.sk_bg,
            });
        }
    }

    // Render EOL character if configured
    if (ctx.list_enabled and ctx.listchars.eol != 0 and screen_col < ctx.max_col) {
        ctx.grid.setCell(ctx.row, screen_col, .{
            .char = ctx.listchars.eol,
            .fg = ctx.lc_colors.sk_fg,
            .bg = ctx.lc_colors.sk_bg,
        });
        screen_col += 1;
    }

    return screen_col;
}

/// Render a tab character with listchars expansion
/// Returns the ending column
fn renderTab(
    grid: *ScreenGrid,
    row: usize,
    start_col: usize,
    max_col: usize,
    listchars: *const ListChars,
    colors: ListCharsColors,
) usize {
    var col = start_col;

    // Render tab start character
    if (col < max_col) {
        grid.setCell(row, col, .{
            .char = listchars.tab[0],
            .fg = colors.ws_fg,
            .bg = colors.ws_bg,
        });
        col += 1;
    }

    // Calculate remaining tab width
    const tab_width = char_width.getTabWidth();
    if (tab_width > 1) {
        const chars_to_fill = tab_width - 1;
        const middle_count = if (listchars.tab[2] != 0 and chars_to_fill > 0)
            chars_to_fill - 1
        else
            chars_to_fill;

        // Render middle characters
        if (listchars.tab[1] != 0) {
            var i: usize = 0;
            while (i < middle_count and col < max_col) : (i += 1) {
                grid.setCell(row, col, .{
                    .char = listchars.tab[1],
                    .fg = colors.ws_fg,
                    .bg = colors.ws_bg,
                });
                col += 1;
            }
        }

        // Render end character
        if (listchars.tab[2] != 0 and col < max_col) {
            grid.setCell(row, col, .{
                .char = listchars.tab[2],
                .fg = colors.ws_fg,
                .bg = colors.ws_bg,
            });
            col += 1;
        }
    }

    return col;
}

/// Fill remaining columns with spaces (for clearing line end)
pub fn fillRemainder(
    grid: *ScreenGrid,
    row: usize,
    start_col: usize,
    end_col: usize,
    bg_color: ?highlights.Color,
) void {
    var col = start_col;
    while (col < end_col) : (col += 1) {
        grid.setCell(row, col, .{
            .char = ' ',
            .fg = null,
            .bg = bg_color,
        });
    }
}

/// Render empty line indicator (~)
pub fn renderEmptyLineIndicator(
    grid: *ScreenGrid,
    row: usize,
    col: usize,
    end_col: usize,
    fg_color: ?highlights.Color,
    bg_color: ?highlights.Color,
) void {
    // Render ~ character
    grid.setCell(row, col, .{
        .char = '~',
        .fg = fg_color,
        .bg = bg_color,
    });

    // Fill rest with spaces
    fillRemainder(grid, row, col + 1, end_col, bg_color);
}

/// Convert from highlight_api.Color to highlights.Color
// Use shared color conversion (DRY)
fn convertColor(c: Color) highlights.Color {
    return highlights.Color.fromApiColor(c);
}
