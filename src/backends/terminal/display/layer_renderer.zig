const std = @import("std");
const Display = @import("display.zig").Display;
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../../editor/editor.zig").Editor;
const EditorContext = @import("../../headless/editor_context.zig").EditorContext;
const highlights = @import("../../../editor/config/highlights.zig");
const VisualState = @import("../../../editor/visual/visual.zig").VisualState;
const YankHighlight = @import("../../../editor/visual/yank_highlight.zig").YankHighlight;
const Position = @import("../../../editor/visual/visual.zig").Position;
const char_width = @import("char_width.zig");
const ListChars = @import("../../../editor/config/listchars.zig").ListChars;
const SyntaxHighlighter = @import("../../../editor/treesitter/syntax_highlighter.zig").SyntaxHighlighter;
const Range = @import("../../../editor/treesitter/highlight.zig").Range;
const Style = @import("../../../system/jsi/highlight_api.zig").Style;
const Color = @import("../../../system/jsi/highlight_api.zig").Color;
const HighlightRegistry = @import("../../../system/jsi/highlight_api.zig").HighlightRegistry;

// Shared listchars rendering (DRY: used by both layer_renderer and window_renderer)
const listchars_renderer = @import("listchars_renderer.zig");

// ============================================================================
// PHASE 2.5: Layer-based Rendering Pipeline
// ============================================================================
// These functions replace the monolithic updateGridFromBuffer with clean
// separation of concerns - each layer handles one visual aspect

/// Update all layers from buffer state (Phase 2.5)
/// This is the new rendering entry point that replaces updateGridFromBuffer
/// Generic over Editor/EditorContext types (both have same fields)
/// Uses unified HighlightRegistry (Neovim/Helix pattern - ONE system for all highlights)
pub fn updateLayers(
    self: *Display,
    editor: anytype,
    _: []const u8, // status - not used yet, will be for status layer
    registry: *const HighlightRegistry,
    visual_state: *const VisualState,
    yank_highlight: *const YankHighlight,
    cursorline_enabled: bool,
    list_enabled: bool,
    listchars: *const ListChars,
) !void {
    // Get buffer from editor (handles both Editor and EditorContext types)
    const T = @TypeOf(editor);
    const buffer = if (T == *Editor)
        editor.getCurrentBuffer() orelse return error.NoCurrentBuffer
    else if (T == *EditorContext)
        editor.buffer()
    else
        &editor.buffer; // Duck-typed fallback for MockEditor in benchmarks

    const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

    // Clear layers that ALWAYS need full rebuild
    self.base_layer.clear();
    self.gutter_layer.clear();
    self.cursor_layer.clear();
    self.yank_layer.clear();

    // CRITICAL FIX: Don't clear selection layer on every render!
    // Selection layer should only be cleared when:
    // - Visual mode deactivates (!visual_state.active)
    // - Visual mode type changes (char → line → block)
    // - Viewport changes significantly
    // For cursor movements within visual mode, use incremental updates
    if (!visual_state.active) {
        // Visual mode inactive - clear selection layer
        self.selection_layer.clear();
    }
    // Note: virtual_text_layer is managed by plugins via JSI

    // Update each layer in logical order (not z-order)
    // All layers now use unified registry (Neovim/Helix pattern)
    try updateBaseLayer(self, editor, registry, text_rows, list_enabled, listchars);
    try updateGutterLayer(self, buffer, registry, text_rows);
    try updateSelectionLayer(self, buffer, visual_state, registry, text_rows);
    try updateYankLayer(self, buffer, yank_highlight, registry, text_rows);
    try updateCursorLayer(self, buffer, registry, cursorline_enabled, text_rows);

    // Virtual text layer is updated by plugins, so skip it here
}

// ListCharsColors is now in shared listchars_renderer module (DRY)
const ListCharsColors = listchars_renderer.ListCharsColors;

/// Update base layer: Render buffer text content (z=0)
/// Generic over Editor/EditorContext types (both have same fields)
fn updateBaseLayer(
    self: *Display,
    editor: anytype,
    registry: *const HighlightRegistry,
    text_rows: usize,
    list_enabled: bool,
    listchars: *const ListChars,
) !void {
    // Get buffer from editor (handles both Editor and EditorContext types)
    const T = @TypeOf(editor);
    const buffer = if (T == *Editor)
        editor.getCurrentBuffer() orelse return error.NoCurrentBuffer
    else if (T == *EditorContext)
        editor.buffer()
    else
        &editor.buffer; // Duck-typed fallback for MockEditor in benchmarks
    const gutter_width = self.gutter_manager.getTotalWidth();

    // Get Normal highlight from unified registry (Neovim/Helix pattern)
    const normal_style = registry.get("Normal");
    const fg_color = if (normal_style.fg) |c| convertColor(c) else null;
    const bg_color = if (normal_style.bg) |c| convertColor(c) else null;

    // Get EndOfBuffer highlight for ~ characters (Neovim: defaults to NonText)
    // Fallback chain: EndOfBuffer → NonText → Normal
    const eob_style = registry.get("EndOfBuffer");
    const non_text_style = registry.get("NonText");
    const eob_fg = if (eob_style.fg) |c| convertColor(c) else if (non_text_style.fg) |c| convertColor(c) else fg_color;
    const eob_bg = if (eob_style.bg) |c| convertColor(c) else if (non_text_style.bg) |c| convertColor(c) else bg_color;

    // Pre-compute listchars colors using shared module (DRY)
    const lc_colors = if (list_enabled)
        ListCharsColors.fromRegistry(registry, convertColor)
    else
        undefined; // Won't be used if list_enabled = false

    // Create syntax highlighter if tree-sitter syntax available (per-buffer)
    // Following Neovim architecture: each buffer owns its own Syntax for proper
    // floating window highlighting (e.g., LSP hover with markdown syntax)
    var syntax_highlighter: ?SyntaxHighlighter = null;
    if (buffer.syntax) |syntax| {
        // Get registry based on editor type (Editor has .highlight_registry field, EditorContext has method)
        const registry_ptr = if (T == *Editor)
            &editor.highlight_registry
        else if (T == *EditorContext)
            editor.highlight_registry()
        else
            &editor.highlight_registry; // Duck-typed fallback

        // SAFETY: Syntax and HighlightRegistry outlive this function
        syntax_highlighter = SyntaxHighlighter.init(
            self.allocator, // Use Display's allocator (not page_allocator)
            syntax,
            registry_ptr,
        );
    }

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = self.viewport_top + row;

        if (line_num < buffer.lineCount()) {
            const line = buffer.getLine(line_num).?;
            defer buffer.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;

            // Apply horizontal scroll (Neovim behavior: all lines scroll together)
            const h_offset = self.viewport_left;
            const start_col = if (h_offset > 0)
                char_width.displayColumnToByte(line_without_newline, h_offset)
            else
                0;
            const remaining = line_without_newline[start_col..];

            // Calculate absolute byte offset in buffer for tree-sitter
            const line_byte_offset = buffer.content.byteOfLine(line_num);
            const text_byte_offset = line_byte_offset + start_col;

            // Render text to base layer
            // Priority: Syntax highlighting > listchars > plain text
            // Gracefully fall back to listchars/plain text if syntax highlighting fails
            const end_col = if (syntax_highlighter) |*sh| blk: {
                break :blk renderWithSyntaxHighlight(self, sh, row, gutter_width, remaining, text_byte_offset, list_enabled, listchars, lc_colors, fg_color, bg_color) catch {
                    // Syntax highlighting failed (missing query file, etc.) - fall back to listchars or plain text
                    break :blk if (list_enabled)
                        try renderWithListChars(self, row, gutter_width, remaining, listchars, lc_colors, fg_color, bg_color)
                    else
                        self.base_layer.grid.setString(row, gutter_width, remaining, fg_color, bg_color);
                };
            } else if (list_enabled)
                try renderWithListChars(self, row, gutter_width, remaining, listchars, lc_colors, fg_color, bg_color)
            else
                self.base_layer.grid.setString(row, gutter_width, remaining, fg_color, bg_color);

            // Fill rest of line (only if there's space remaining)
            if (end_col < self.terminal_cols) {
                for (end_col..self.terminal_cols) |col| {
                    self.base_layer.grid.setCell(row, col, .{ .char = ' ', .bg = bg_color });
                }
            }
        } else {
            // Empty line indicator (~) - uses EndOfBuffer highlight group (defaults to NonText)
            self.base_layer.grid.setCell(row, gutter_width, .{ .char = '~', .fg = eob_fg, .bg = eob_bg });
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
    registry: *const HighlightRegistry,
    text_rows: usize,
) !void {
    const gutter_width = self.gutter_manager.getTotalWidth();
    if (gutter_width == 0) return;

    // Get LineNr style for background of empty gutter lines
    const line_nr_style = registry.get("LineNr");
    const empty_gutter_bg = if (line_nr_style.bg) |c| convertColor(c) else null;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = self.viewport_top + row;

        // Neovim behavior: lines beyond EOF have empty gutter (no line numbers)
        if (line_num >= buffer.lineCount()) {
            // Fill gutter with empty space for virtual lines (~ lines)
            self.gutter_layer.grid.fillRowRange(row, 0, gutter_width, .{ .char = ' ', .bg = empty_gutter_bg });
            continue;
        }

        // Render gutter content for actual buffer lines
        var gutter_buf: [32]u8 = undefined;
        const gutter_str_len = self.gutter_manager.renderLine(
            line_num,
            buffer.cursor.row,
            &gutter_buf,
        );
        const gutter_str = gutter_buf[0..gutter_str_len];

        // Get line number highlights from unified registry
        const is_cursor_line = (line_num == buffer.cursor.row);
        const style = if (is_cursor_line)
            registry.get("CursorLineNr")
        else
            line_nr_style;

        const gutter_fg = if (style.fg) |c| convertColor(c) else null;
        const gutter_bg = if (style.bg) |c| convertColor(c) else empty_gutter_bg;

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
pub fn updateSelectionLayer(
    self: *Display,
    buffer: *const Buffer,
    visual_state: *const VisualState,
    registry: *const HighlightRegistry,
    text_rows: usize,
) !void {
    if (!visual_state.active) return;

    // CRITICAL FIX: Clear selection layer ONLY when visual mode is active
    // This ensures we rebuild the selection on each cursor movement
    // without the flicker caused by clearing in updateLayers()
    self.selection_layer.clear();

    const cursor_pos = Position{
        .line = buffer.cursor.row,
        .col = buffer.cursor.col,
    };
    const visual_range = visual_state.getRange(cursor_pos);

    // Get Visual highlight from unified registry
    const visual_style = registry.get("Visual");
    const visual_bg = if (visual_style.bg) |c|
        convertColor(c)
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
                defer buffer.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll (Neovim behavior: all lines scroll together)
                const h_offset = self.viewport_left;
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
    registry: *const HighlightRegistry,
    text_rows: usize,
) !void {
    if (!yank_highlight.active or !yank_highlight.isVisible()) return;

    // Get YankFlash highlight from unified registry
    const yank_style = registry.get("YankFlash");
    const yank_bg = if (yank_style.bg) |c|
        convertColor(c)
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
                defer buffer.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll (Neovim behavior: all lines scroll together)
                const h_offset = self.viewport_left;
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

/// Convert tree-sitter Style.Color to terminal highlights.Color
// Use shared color conversion (DRY)
fn convertColor(api_color: Color) highlights.Color {
    return highlights.Color.fromApiColor(api_color);
}

/// Render text with syntax highlighting from tree-sitter
///
/// This function applies syntax highlighting to text using the SyntaxHighlighter.
/// It queries tree-sitter for highlight ranges, builds a style map, then renders
/// each character with the appropriate colors from the theme.
///
/// Integration with listchars:
/// - If list_enabled=true, invisible characters (tabs, spaces) are replaced per listchars config
/// - Syntax highlighting colors take precedence over listchars colors for non-whitespace
/// - Listchars use Whitespace/SpecialKey highlight groups (separate from syntax theme)
///
/// Parameters:
/// - self: Display instance
/// - highlighter: SyntaxHighlighter with Syntax + HighlightRegistry
/// - row: Screen row to render to (0-indexed)
/// - start_col: Starting column (typically gutter_width)
/// - text: UTF-8 encoded text to render (without trailing newline)
/// - text_byte_offset: Byte offset of text in buffer (for tree-sitter range calculation)
/// - list_enabled: Whether listchars replacement is enabled
/// - listchars: Configuration for invisible character symbols
/// - lc_colors: Pre-computed listchars colors
/// - fg_color: Normal foreground color (fallback)
/// - bg_color: Normal background color (fallback)
///
/// Returns: Final column position after rendering
fn renderWithSyntaxHighlight(
    self: *Display,
    highlighter: *SyntaxHighlighter,
    row: usize,
    start_col: usize,
    text: []const u8,
    text_byte_offset: usize,
    list_enabled: bool,
    listchars: *const ListChars,
    lc_colors: ListCharsColors,
    fg_color: ?highlights.Color,
    bg_color: ?highlights.Color,
) !usize {
    // Get syntax highlights for this text range
    const range = Range{
        .start_byte = @intCast(text_byte_offset),
        .end_byte = @intCast(text_byte_offset + text.len),
    };

    var iter = try highlighter.highlights(range);
    defer iter.deinit();

    // Build highlight map (byte offset → Style)
    // We use a simple array since we're only rendering one line at a time
    var highlight_map = std.AutoHashMap(usize, Style).init(self.allocator);
    defer highlight_map.deinit();

    while (iter.next()) |styled| {
        // Convert absolute byte offsets to text-relative offsets
        const range_start = if (styled.range.start_byte >= text_byte_offset)
            styled.range.start_byte - text_byte_offset
        else
            0;

        const range_end = if (styled.range.end_byte >= text_byte_offset)
            @min(styled.range.end_byte - text_byte_offset, text.len)
        else
            0;

        // Apply style to ALL bytes in the range, not just the first byte
        var byte_offset = range_start;
        while (byte_offset < range_end) : (byte_offset += 1) {
            try highlight_map.put(byte_offset, styled.style);
        }
    }

    // Render text character by character with syntax colors
    // Note: lc_colors.ws_fg/ws_bg used by shared module, sk_fg/sk_bg for EOL
    const sk_fg = lc_colors.sk_fg;
    const sk_bg = lc_colors.sk_bg;
    var col = start_col;
    var byte_idx: usize = 0;
    var last_non_space_col = start_col;

    while (byte_idx < text.len and col < self.terminal_cols) {
        const char_len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + char_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[byte_idx .. byte_idx + char_len]) catch text[byte_idx];
        var display_char = codepoint;

        // Look up syntax highlight for this character
        const syntax_style = highlight_map.get(byte_idx);

        // Extract syntax colors (if available)
        const syntax_fg = if (syntax_style) |style|
            if (style.fg) |c| convertColor(c) else null
        else
            null;
        const syntax_bg = if (syntax_style) |style|
            if (style.bg) |c| convertColor(c) else null
        else
            null;

        // Handle listchars replacements using shared module (DRY)
        if (list_enabled) {
            if (codepoint == '\t') {
                // Tab: use shared tab renderer
                const tab_result = listchars_renderer.renderTab(
                    &self.base_layer.grid,
                    row,
                    col,
                    self.terminal_cols,
                    listchars,
                    lc_colors,
                );
                if (tab_result.cols_consumed > 0) {
                    col += tab_result.cols_consumed;
                    if (tab_result.is_non_space) {
                        last_non_space_col = col;
                    }
                    byte_idx += char_len;
                    continue;
                }
                // Fall through to render tab as regular char if no listchar configured
            } else if (listchars_renderer.getCharReplacement(codepoint, listchars, lc_colors)) |replacement| {
                // Space/nbsp replacement
                display_char = replacement.char;
                // Use replacement colors for whitespace chars
                self.base_layer.grid.setCell(row, col, .{
                    .char = replacement.char,
                    .fg = replacement.fg,
                    .bg = replacement.bg,
                });
                col += 1;
                if (replacement.is_non_space) {
                    last_non_space_col = col;
                }
                byte_idx += char_len;
                continue;
            } else if (listchars_renderer.isNonSpace(codepoint)) {
                last_non_space_col = col + 1;
            }
        } else {
            if (listchars_renderer.isNonSpace(codepoint)) {
                last_non_space_col = col + 1;
            }
        }

        // Render regular character with syntax colors
        self.base_layer.grid.setCell(row, col, .{
            .char = display_char,
            .fg = syntax_fg orelse fg_color,
            .bg = syntax_bg orelse bg_color,
        });
        col += 1;
        byte_idx += char_len;
    }

    // Post-process: mark trailing spaces using shared module (DRY)
    if (list_enabled) {
        listchars_renderer.markTrailingSpaces(
            &self.base_layer.grid,
            row,
            last_non_space_col,
            col,
            listchars,
            lc_colors,
        );
    }

    // Render EOL character if configured
    if (list_enabled and listchars.eol != 0 and col < self.terminal_cols) {
        self.base_layer.grid.setCell(row, col, .{
            .char = listchars.eol,
            .fg = sk_fg,
            .bg = sk_bg,
        });
        col += 1;
    }

    return col;
}

/// Render text with invisible character replacements (listchars)
///
/// This function processes text character-by-character, replacing invisible characters
/// (tabs, spaces, nbsp, eol, trailing spaces) with visible symbols according to the
/// listchars configuration. It applies appropriate highlight colors using Neovim's
/// highlight group fallback chain.
///
/// Highlight Color Fallback Chain (Neovim-compatible):
/// - Whitespace characters (tab, space, nbsp):
///   Whitespace.fg → SpecialKey.fg → NonText.fg → Normal.fg
/// - Special characters (eol, trail):
///   SpecialKey.fg → NonText.fg → Normal.fg
///
/// Background Color Behavior:
/// - If Whitespace.bg/SpecialKey.bg is set, applies to the entire cell
/// - If null, uses Normal.bg (allowing transparency for layer blending)
/// - This matches Neovim's behavior where highlight groups can have partial colors
///
/// Parameters:
/// - row: Screen row to render to (0-indexed)
/// - start_col: Starting column (typically gutter_width)
/// - text: UTF-8 encoded text to render (without trailing newline)
/// - listchars: Configuration for invisible character symbols
/// - colors: Pre-computed highlight colors (for performance - computed once per frame)
/// - fg_color: Normal foreground color (fallback for non-listchars text)
/// - bg_color: Normal background color (fallback for non-listchars text)
///
/// Returns: Final column position after rendering (used for line-end padding)
///
/// Performance: Colors are pre-computed in updateBaseLayer() to avoid redundant
/// optional unwraps on every line (saves ~200ns per line × 1000 lines = 200µs per frame).
fn renderWithListChars(
    self: *Display,
    row: usize,
    start_col: usize,
    text: []const u8,
    listchars: *const ListChars,
    colors: ListCharsColors,
    fg_color: ?highlights.Color,
    bg_color: ?highlights.Color,
) !usize {
    // Use shared listchars_renderer module (DRY - same logic as renderWithSyntaxHighlight)
    var col = start_col;
    var byte_idx: usize = 0;
    var last_non_space_col = start_col;

    while (byte_idx < text.len and col < self.terminal_cols) {
        const char_len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + char_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[byte_idx .. byte_idx + char_len]) catch text[byte_idx];

        // Handle tabs using shared module
        if (codepoint == '\t') {
            const tab_result = listchars_renderer.renderTab(
                &self.base_layer.grid,
                row,
                col,
                self.terminal_cols,
                listchars,
                colors,
            );
            if (tab_result.cols_consumed > 0) {
                col += tab_result.cols_consumed;
                if (tab_result.is_non_space) {
                    last_non_space_col = col;
                }
                byte_idx += char_len;
                continue;
            }
            // Fall through to render tab as regular char if no listchar configured
        }

        // Handle space/nbsp replacements using shared module
        if (listchars_renderer.getCharReplacement(codepoint, listchars, colors)) |replacement| {
            self.base_layer.grid.setCell(row, col, .{
                .char = replacement.char,
                .fg = replacement.fg,
                .bg = replacement.bg,
            });
            col += 1;
            if (replacement.is_non_space) {
                last_non_space_col = col;
            }
            byte_idx += char_len;
            continue;
        }

        // Track non-space characters for trailing detection
        if (listchars_renderer.isNonSpace(codepoint)) {
            last_non_space_col = col + 1;
        }

        // Render regular character
        self.base_layer.grid.setCell(row, col, .{
            .char = codepoint,
            .fg = fg_color,
            .bg = bg_color,
        });
        col += 1;
        byte_idx += char_len;
    }

    // Post-process: mark trailing spaces using shared module (DRY)
    listchars_renderer.markTrailingSpaces(
        &self.base_layer.grid,
        row,
        last_non_space_col,
        col,
        listchars,
        colors,
    );

    // Render EOL using shared module (DRY)
    col += listchars_renderer.renderEol(
        &self.base_layer.grid,
        row,
        col,
        self.terminal_cols,
        listchars,
        colors,
    );

    return col;
}

/// Update cursor layer: Render cursor line highlight (z=200)
fn updateCursorLayer(
    self: *Display,
    buffer: *const Buffer,
    registry: *const HighlightRegistry,
    cursorline_enabled: bool,
    text_rows: usize,
) !void {
    if (!cursorline_enabled) return;

    const cursor_line = buffer.cursor.row;
    if (cursor_line < self.viewport_top or cursor_line >= self.viewport_top + text_rows) return;

    const screen_row = cursor_line - self.viewport_top;

    // Get CursorLine highlight from unified registry
    const cursorline_style = registry.get("CursorLine");
    if (cursorline_style.bg == null) return; // No cursorline if bg not set

    const cursorline_bg = convertColor(cursorline_style.bg.?);

    // Render cursorline background for TEXT AREA ONLY (not gutter)
    // Neovim-compatible: CursorLine = text area, CursorLineNr = gutter
    // The gutter layer handles cursor line highlighting via CursorLineNr
    const gutter_width = self.gutter_manager.getTotalWidth();
    for (gutter_width..self.terminal_cols) |col| {
        self.cursor_layer.grid.setCell(screen_row, col, .{
            .char = 0, // NULL character - won't hide base layer text
            .bg = cursorline_bg,
        });
    }

    self.cursor_layer.markDirty();
}
