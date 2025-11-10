const std = @import("std");
const Display = @import("display.zig").Display;
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const highlights = @import("../../../editor/config/highlights.zig");
const VisualState = @import("../visual/visual.zig").VisualState;
const YankHighlight = @import("../visual/yank_highlight.zig").YankHighlight;
const Position = @import("../visual/visual.zig").Position;
const char_width = @import("char_width.zig");

// ============================================================================
// PHASE 2.5: Layer-based Rendering Pipeline
// ============================================================================
// These functions replace the monolithic updateGridFromBuffer with clean
// separation of concerns - each layer handles one visual aspect

/// Update all layers from buffer state (Phase 2.5)
/// This is the new rendering entry point that replaces updateGridFromBuffer
pub fn updateLayers(
    self: *Display,
    buffer: *const Buffer,
    _: []const u8, // status - not used yet, will be for status layer
    config: *const highlights.HighlightConfig,
    visual_state: *const VisualState,
    yank_highlight: *const YankHighlight,
) !void {
    const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

    // Clear all layers
    self.base_layer.clear();
    self.gutter_layer.clear();
    self.cursor_layer.clear();
    self.selection_layer.clear();
    self.yank_layer.clear();
    // Note: virtual_text_layer is managed by plugins via JSI

    // Update each layer in logical order (not z-order)
    try updateBaseLayer(self, buffer, config, text_rows);
    try updateGutterLayer(self, buffer, config, text_rows);
    try updateSelectionLayer(self, buffer, visual_state, config, text_rows);
    try updateYankLayer(self, buffer, yank_highlight, config, text_rows);
    try updateCursorLayer(self, buffer, config, text_rows);

    // Virtual text layer is updated by plugins, so skip it here
}

/// Update base layer: Render buffer text content (z=0)
fn updateBaseLayer(
    self: *Display,
    buffer: *const Buffer,
    config: *const highlights.HighlightConfig,
    text_rows: usize,
) !void {
    const gutter_width = self.gutter_manager.getTotalWidth();

    const fg_color = if (config.normal) |n| n.fg else null;
    const bg_color = if (config.normal) |n| n.bg else null;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = self.viewport_top + row;

        if (line_num < buffer.lineCount()) {
            const line = buffer.getLine(line_num).?;
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;

            // Apply horizontal scroll
            const h_offset = if (line_num == buffer.cursor.row) self.viewport_left else 0;
            const start_col = if (h_offset > 0)
                char_width.displayColumnToByte(line_without_newline, h_offset)
            else
                0;
            const remaining = line_without_newline[start_col..];

            // Render text to base layer
            const end_col = self.base_layer.grid.setString(row, gutter_width, remaining, fg_color, bg_color);

            // Fill rest of line (only if there's space remaining)
            if (end_col < self.terminal_cols) {
                for (end_col..self.terminal_cols) |col| {
                    self.base_layer.grid.setCell(row, col, .{ .char = ' ', .bg = bg_color });
                }
            }
        } else {
            // Empty line indicator (~)
            self.base_layer.grid.setCell(row, gutter_width, .{ .char = '~', .fg = fg_color, .bg = bg_color });
            for ((gutter_width + 1)..self.terminal_cols) |col| {
                self.base_layer.grid.setCell(row, col, .{ .char = ' ', .bg = bg_color });
            }
        }
    }

    self.base_layer.markDirty();
}

/// Update gutter layer: Render line numbers and signs (z=100)
fn updateGutterLayer(
    self: *Display,
    buffer: *const Buffer,
    config: *const highlights.HighlightConfig,
    text_rows: usize,
) !void {
    const gutter_width = self.gutter_manager.getTotalWidth();
    if (gutter_width == 0) return;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = self.viewport_top + row;

        // Render gutter content
        var gutter_buf: [32]u8 = undefined;
        const gutter_str_len = self.gutter_manager.renderLine(
            line_num,
            buffer.cursor.row,
            &gutter_buf,
        );
        const gutter_str = gutter_buf[0..gutter_str_len];

        // Determine colors
        const is_cursor_line = (line_num == buffer.cursor.row);
        const line_nr_hl = if (is_cursor_line and config.cursorline_nr != null)
            config.cursorline_nr.?
        else if (config.line_nr != null)
            config.line_nr.?
        else
            null;

        const gutter_fg = if (line_nr_hl) |hl| hl.fg else null;
        const gutter_bg = if (line_nr_hl) |hl| hl.bg else null;

        // Render gutter characters
        var gutter_col: usize = 0;
        var byte_idx: usize = 0;
        while (byte_idx < gutter_str.len and gutter_col < gutter_width) {
            const char_len = std.unicode.utf8ByteSequenceLength(gutter_str[byte_idx]) catch 1;
            if (byte_idx + char_len > gutter_str.len) break;

            const codepoint = std.unicode.utf8Decode(gutter_str[byte_idx..][0..char_len]) catch ' ';
            self.gutter_layer.grid.setCell(row, gutter_col, .{
                .char = codepoint,
                .fg = gutter_fg,
                .bg = gutter_bg,
            });

            gutter_col += 1;
            byte_idx += char_len;
        }

        // Pad remaining gutter space
        while (gutter_col < gutter_width) : (gutter_col += 1) {
            self.gutter_layer.grid.setCell(row, gutter_col, .{
                .char = ' ',
                .fg = gutter_fg,
                .bg = gutter_bg,
            });
        }
    }

    self.gutter_layer.markDirty();
}

/// Update selection layer: Render visual mode selection (z=400)
fn updateSelectionLayer(
    self: *Display,
    buffer: *const Buffer,
    visual_state: *const VisualState,
    config: *const highlights.HighlightConfig,
    text_rows: usize,
) !void {
    if (!visual_state.active) return;

    const cursor_pos = Position{
        .line = buffer.cursor.row,
        .col = buffer.cursor.col,
    };
    const visual_range = visual_state.getRange(cursor_pos);

    const visual_bg = if (config.visual) |v|
        v.bg
    else
        highlights.Color{ .r = 80, .g = 80, .b = 80 };

    const gutter_width = self.gutter_manager.getTotalWidth();
    const text_cols = if (self.terminal_cols > gutter_width)
        self.terminal_cols - gutter_width
    else
        self.terminal_cols;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = self.viewport_top + row;

        // Check if line is in selection range
        if (line_num >= visual_range.start.line and line_num <= visual_range.end.line) {
            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num).?;
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                const h_offset = if (line_num == buffer.cursor.row) self.viewport_left else 0;
                const start_col = if (h_offset > 0)
                    char_width.displayColumnToByte(line_without_newline, h_offset)
                else
                    0;
                const remaining = line_without_newline[start_col..];

                // Render selection highlight for each character
                var screen_col: usize = gutter_width;
                var byte_idx: usize = 0;

                while (byte_idx < remaining.len and screen_col < (gutter_width + text_cols)) {
                    const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                    if (byte_idx + char_len > remaining.len) break;

                    const buffer_col = start_col + byte_idx;
                    const char_pos = Position{
                        .line = line_num,
                        .col = buffer_col,
                    };

                    if (visual_state.contains(cursor_pos, char_pos)) {
                        // This character is selected - render with visual background
                        self.selection_layer.grid.setCell(row, screen_col, .{
                            .char = ' ', // Transparent char, just background
                            .bg = visual_bg,
                        });
                    }

                    screen_col += 1;
                    byte_idx += char_len;
                }
            }
        }
    }

    self.selection_layer.markDirty();
}

/// Update yank layer: Render yank flash highlight (z=500)
fn updateYankLayer(
    self: *Display,
    buffer: *const Buffer,
    yank_highlight: *const YankHighlight,
    config: *const highlights.HighlightConfig,
    text_rows: usize,
) !void {
    if (!yank_highlight.active or !yank_highlight.isVisible()) return;

    const yank_bg = if (config.yank_flash) |y|
        y.bg
    else
        highlights.Color{ .r = 100, .g = 100, .b = 50 };

    const gutter_width = self.gutter_manager.getTotalWidth();
    const text_cols = if (self.terminal_cols > gutter_width)
        self.terminal_cols - gutter_width
    else
        self.terminal_cols;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = self.viewport_top + row;

        if (line_num >= yank_highlight.start.line and line_num <= yank_highlight.end.line) {
            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num).?;
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                const h_offset = if (line_num == buffer.cursor.row) self.viewport_left else 0;
                const start_col = if (h_offset > 0)
                    char_width.displayColumnToByte(line_without_newline, h_offset)
                else
                    0;
                const remaining = line_without_newline[start_col..];

                var screen_col: usize = gutter_width;
                var byte_idx: usize = 0;

                while (byte_idx < remaining.len and screen_col < (gutter_width + text_cols)) {
                    const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                    if (byte_idx + char_len > remaining.len) break;

                    const buffer_col = start_col + byte_idx;
                    const char_pos = Position{
                        .line = line_num,
                        .col = buffer_col,
                    };

                    if (yank_highlight.contains(char_pos)) {
                        self.yank_layer.grid.setCell(row, screen_col, .{
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

    self.yank_layer.markDirty();
}

/// Update cursor layer: Render cursor line highlight (z=200)
fn updateCursorLayer(
    self: *Display,
    buffer: *const Buffer,
    config: *const highlights.HighlightConfig,
    text_rows: usize,
) !void {
    if (!config.cursorline_enabled or config.cursorline == null) return;

    const cursor_line = buffer.cursor.row;
    if (cursor_line < self.viewport_top or cursor_line >= self.viewport_top + text_rows) return;

    const screen_row = cursor_line - self.viewport_top;
    const cursorline_bg = config.cursorline.?.bg;

    // PHASE 6 FIX: Render cursorline background WITHOUT characters
    // We use char=0 (null) which the blend function will treat as "no character"
    // This allows the background to show through without hiding the base layer text
    for (0..self.terminal_cols) |col| {
        self.cursor_layer.grid.setCell(screen_row, col, .{
            .char = 0, // NULL character - won't hide base layer text
            .bg = cursorline_bg,
        });
    }

    self.cursor_layer.markDirty();
}
