const std = @import("std");
const Display = @import("display.zig").Display;
const highlights = @import("../../../editor/config/highlights.zig");
const Update = @import("screen_grid.zig").Update;

/// Render updates to terminal (Step 3: optimized output)
/// This implements Helix's optimizations: adjacent cell skipping and attribute tracking
pub fn renderUpdates(self: *Display, updates: []const Update) !void {
    if (updates.len == 0) return;

    // Clear output buffer
    self.output_buf.clearRetainingCapacity();
    const buf_writer = self.output_buf.writer(self.allocator);

    // Track state to minimize ANSI codes (Helix optimization)
    var current_fg: ?highlights.Color = null;
    var current_bg: ?highlights.Color = null;
    var current_bold: bool = false;
    var current_italic: bool = false;
    var current_underline: bool = false;
    var last_pos: ?struct { row: usize, col: usize } = null;
    var last_had_combining: bool = false; // Track if last rendered cell had combining chars

    for (updates) |update| {
        // Skip continuation cells - terminals handle double-width chars automatically
        // The double-width character's background extends across both columns
        if (update.cell.is_continuation) {
            // DON'T update last_pos here! We didn't send anything to the terminal,
            // so the terminal cursor is still where the double-width char left it.
            // The last_pos was already correctly set after rendering the emoji.
            continue;
        }

        // HELIX OPTIMIZATION 1: Skip cursor movement if adjacent
        // Terminal cursor auto-advances after rendering a character
        // last_pos tracks where the terminal cursor currently is
        // EXCEPTION: After writing combining characters, always reposition cursor
        // because some terminals may have undefined cursor position after combining chars
        const is_adjacent = if (last_pos) |pos|
            (update.row == pos.row and update.col == pos.col and !last_had_combining)
        else
            false;

        if (!is_adjacent) {
            // Move cursor to position
            try buf_writer.print("\x1b[{d};{d}H", .{ update.row + 1, update.col + 1 });
        }

        // HELIX OPTIMIZATION 2: Only send attribute changes
        // Foreground color
        if (update.cell.fg) |fg| {
            if (current_fg == null or !colorEql(current_fg.?, fg)) {
                var buf: [32]u8 = undefined;
                const fg_code = try fg.toAnsiFg(&buf);
                try buf_writer.writeAll(fg_code);
                current_fg = fg;
            }
        } else if (current_fg != null) {
            try buf_writer.writeAll("\x1b[39m"); // Reset FG
            current_fg = null;
        }

        // Background color
        if (update.cell.bg) |bg| {
            if (current_bg == null or !colorEql(current_bg.?, bg)) {
                var buf: [32]u8 = undefined;
                const bg_code = try bg.toAnsiBg(&buf);
                try buf_writer.writeAll(bg_code);
                current_bg = bg;
            }
        } else if (current_bg != null) {
            try buf_writer.writeAll("\x1b[49m"); // Reset BG
            current_bg = null;
        }

        // Bold
        if (update.cell.bold != current_bold) {
            if (update.cell.bold) {
                try buf_writer.writeAll("\x1b[1m");
            } else {
                try buf_writer.writeAll("\x1b[22m");
            }
            current_bold = update.cell.bold;
        }

        // Italic
        if (update.cell.italic != current_italic) {
            if (update.cell.italic) {
                try buf_writer.writeAll("\x1b[3m");
            } else {
                try buf_writer.writeAll("\x1b[23m");
            }
            current_italic = update.cell.italic;
        }

        // Underline
        if (update.cell.underline != current_underline) {
            if (update.cell.underline) {
                try buf_writer.writeAll("\x1b[4m");
            } else {
                try buf_writer.writeAll("\x1b[24m");
            }
            current_underline = update.cell.underline;
        }

        // Write the base character
        // CRITICAL FIX: When char is 0 (null/transparent), render a space to show background
        // This is essential for layers that only provide background color (like virtual text banners)
        const render_char = if (update.cell.char == 0) ' ' else update.cell.char;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(render_char, &buf) catch 1;
        try buf_writer.writeAll(buf[0..len]);

        // Write any combining characters (variation selectors, combining marks)
        for (0..update.cell.combining_count) |i| {
            const combining_len = std.unicode.utf8Encode(update.cell.combining[i], &buf) catch 1;
            try buf_writer.writeAll(buf[0..combining_len]);
        }

        // Track where the terminal cursor is after rendering this character
        // For single-width: cursor advances from col to col+1
        // For double-width: cursor advances from col to col+2
        const char_display_width: usize = if (update.col + 1 < self.grid.width and
            self.grid.current[update.row][update.col + 1].is_continuation)
            2
        else
            1;

        // Store where the terminal cursor IS (not where we rendered)
        // This is used for the adjacency check to skip unnecessary cursor movements
        last_pos = .{ .row = update.row, .col = update.col + char_display_width };

        // Track if this cell had combining characters
        // This affects cursor positioning for the next update
        last_had_combining = (update.cell.combining_count > 0);
    }

    // Reset all attributes at end
    try buf_writer.writeAll("\x1b[0m");

    // NEOVIM + HELIX PATTERN: Single flush (batched output)
    try self.stdout.writeAll(self.output_buf.items);
}

/// Helper: Compare two colors
fn colorEql(a: highlights.Color, b: highlights.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b;
}
