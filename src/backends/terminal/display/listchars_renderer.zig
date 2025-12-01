const std = @import("std");
const highlights = @import("../../../editor/config/highlights.zig");
const ListChars = @import("../../../editor/config/listchars.zig").ListChars;
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const char_width = @import("char_width.zig");

/// Pre-computed colors for listchars rendering
/// Computed once per frame for performance
pub const ListCharsColors = struct {
    /// Whitespace colors (for tab, space, nbsp)
    /// Fallback chain: Whitespace → SpecialKey → NonText → Normal
    ws_fg: ?highlights.Color,
    ws_bg: ?highlights.Color,

    /// SpecialKey colors (for trail, eol)
    /// Fallback chain: SpecialKey → NonText → Normal
    sk_fg: ?highlights.Color,
    sk_bg: ?highlights.Color,

    /// Normal colors (default)
    normal_fg: ?highlights.Color,
    normal_bg: ?highlights.Color,

    /// Compute listchars colors from highlight registry
    /// Uses Neovim's highlight group fallback chain
    pub fn fromRegistry(registry: anytype, convertColor: anytype) ListCharsColors {
        const normal_style = registry.get("Normal");
        const normal_fg = if (normal_style.fg) |c| convertColor(c) else null;
        const normal_bg = if (normal_style.bg) |c| convertColor(c) else null;

        const whitespace_style = registry.get("Whitespace");
        const special_key_style = registry.get("SpecialKey");
        const non_text_style = registry.get("NonText");

        // Whitespace colors: Whitespace → SpecialKey → NonText → Normal
        const ws_fg = if (whitespace_style.fg) |c|
            convertColor(c)
        else if (special_key_style.fg) |c|
            convertColor(c)
        else if (non_text_style.fg) |c|
            convertColor(c)
        else
            normal_fg;

        const ws_bg = if (whitespace_style.bg) |c|
            convertColor(c)
        else if (special_key_style.bg) |c|
            convertColor(c)
        else if (non_text_style.bg) |c|
            convertColor(c)
        else
            normal_bg;

        // SpecialKey colors: SpecialKey → NonText → Normal
        const sk_fg = if (special_key_style.fg) |c|
            convertColor(c)
        else if (non_text_style.fg) |c|
            convertColor(c)
        else
            normal_fg;

        const sk_bg = if (special_key_style.bg) |c|
            convertColor(c)
        else if (non_text_style.bg) |c|
            convertColor(c)
        else
            normal_bg;

        return .{
            .ws_fg = ws_fg,
            .ws_bg = ws_bg,
            .sk_fg = sk_fg,
            .sk_bg = sk_bg,
            .normal_fg = normal_fg,
            .normal_bg = normal_bg,
        };
    }
};

/// Result of rendering a tab character
pub const TabRenderResult = struct {
    /// Number of columns consumed
    cols_consumed: usize,
    /// Whether this was a non-space character (for trailing detection)
    is_non_space: bool,
};

/// Render a tab character with listchars support
/// Returns the number of columns consumed
pub fn renderTab(
    grid: *ScreenGrid,
    row: usize,
    start_col: usize,
    max_col: usize,
    listchars: *const ListChars,
    colors: ListCharsColors,
) TabRenderResult {
    var col = start_col;

    if (listchars.tab[0] != 0) {
        // Render first tab character
        if (col < max_col) {
            grid.setCell(row, col, .{
                .char = listchars.tab[0],
                .fg = colors.ws_fg,
                .bg = colors.ws_bg,
            });
            col += 1;
        }

        const tab_width: usize = char_width.getTabWidth();
        if (tab_width > 1) {
            const chars_to_fill = tab_width - 1;

            // Render middle characters
            if (listchars.tab[1] != 0) {
                const middle_count = if (listchars.tab[2] != 0 and chars_to_fill > 0)
                    chars_to_fill - 1
                else
                    chars_to_fill;

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

        return .{ .cols_consumed = col - start_col, .is_non_space = true };
    }

    // No tab replacement configured
    return .{ .cols_consumed = 0, .is_non_space = false };
}

/// Get the replacement character and colors for a codepoint
/// Returns null if no replacement should be made
pub const CharReplacement = struct {
    char: u21,
    fg: ?highlights.Color,
    bg: ?highlights.Color,
    is_non_space: bool,
};

/// Check if a character should be replaced with a listchar
/// Returns the replacement info, or null if no replacement
pub fn getCharReplacement(
    codepoint: u21,
    listchars: *const ListChars,
    colors: ListCharsColors,
) ?CharReplacement {
    switch (codepoint) {
        ' ' => {
            if (listchars.space != 0) {
                return .{
                    .char = listchars.space,
                    .fg = colors.ws_fg,
                    .bg = colors.ws_bg,
                    .is_non_space = false,
                };
            }
        },
        0xA0 => { // Non-breaking space (U+00A0)
            if (listchars.nbsp != 0) {
                return .{
                    .char = listchars.nbsp,
                    .fg = colors.ws_fg,
                    .bg = colors.ws_bg,
                    .is_non_space = false,
                };
            }
        },
        else => {},
    }
    return null;
}

/// Mark trailing spaces in a rendered line
/// Should be called after rendering the line content
pub fn markTrailingSpaces(
    grid: *ScreenGrid,
    row: usize,
    last_non_space_col: usize,
    end_col: usize,
    listchars: *const ListChars,
    colors: ListCharsColors,
) void {
    if (listchars.trail == 0) return;

    var col = last_non_space_col;
    while (col < end_col) : (col += 1) {
        if (grid.getCell(row, col)) |cell| {
            if (cell.char == ' ' or cell.char == listchars.space) {
                grid.setCell(row, col, .{
                    .char = listchars.trail,
                    .fg = colors.sk_fg,
                    .bg = colors.sk_bg,
                });
            }
        }
    }
}

/// Render EOL character if configured
/// Returns 1 if EOL was rendered, 0 otherwise
pub fn renderEol(
    grid: *ScreenGrid,
    row: usize,
    col: usize,
    max_col: usize,
    listchars: *const ListChars,
    colors: ListCharsColors,
) usize {
    if (listchars.eol != 0 and col < max_col) {
        grid.setCell(row, col, .{
            .char = listchars.eol,
            .fg = colors.sk_fg,
            .bg = colors.sk_bg,
        });
        return 1;
    }
    return 0;
}

/// Check if a codepoint is considered "non-space" for trailing detection
pub fn isNonSpace(codepoint: u21) bool {
    return codepoint != ' ' and codepoint != '\t' and codepoint != 0;
}
