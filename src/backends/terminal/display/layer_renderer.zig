const std = @import("std");
const Display = @import("display.zig").Display;
const ViewportState = @import("display.zig").ViewportState;
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../../editor/editor.zig").Editor;
const SearchMatch = @import("../../../editor/editor.zig").SearchMatch;
const EditorContext = @import("../../headless/editor_context.zig").EditorContext;
const highlights = @import("../../../editor/config/highlights.zig");
const VisualState = @import("../../../editor/visual/visual.zig").VisualState;
const YankHighlight = @import("../../../editor/visual/yank_highlight.zig").YankHighlight;
const Position = @import("../../../editor/visual/visual.zig").Position;
const char_width = @import("char_width.zig");
const ListChars = @import("../../../editor/config/listchars.zig").ListChars;
const LanguageTree = @import("../../../editor/treesitter/language_tree.zig").LanguageTree;
const LanguageTreeHighlighter = @import("../../../editor/treesitter/syntax_highlighter.zig").LanguageTreeHighlighter;
const Range = @import("../../../editor/treesitter/highlight.zig").Range;
const Style = @import("../../../system/jsi/highlight_api.zig").Style;
const Color = @import("../../../system/jsi/highlight_api.zig").Color;
const HighlightRegistry = @import("../../../system/jsi/highlight_api.zig").HighlightRegistry;

// Highlight cache for efficient repeated rendering
const HighlightCache = @import("../../../editor/highlight_cache.zig").HighlightCache;
const StyleSpan = @import("../../../editor/highlight_cache.zig").StyleSpan;

// Shared listchars rendering (DRY: used by both layer_renderer and window_renderer)
const listchars_renderer = @import("listchars_renderer.zig");

// Namespace API for extmark signs lookup
const namespace_api = @import("../../../system/jsi/namespace_api.zig");

// Shared sign rendering (DRY: used by both layer_renderer and window_renderer)
const sign_renderer = @import("sign_renderer.zig");

// ============================================================================
// PHASE 2.5: Layer-based Rendering Pipeline
// ============================================================================
// These functions replace the monolithic updateGridFromBuffer with clean
// separation of concerns - each layer handles one visual aspect

/// Update all layers from buffer state (Phase 2.5)
/// This is the new rendering entry point that replaces updateGridFromBuffer
/// Generic over Editor/EditorContext types (both have same fields)
/// Uses unified HighlightRegistry (Neovim/Helix pattern - ONE system for all highlights)
///
/// ViewportState is passed explicitly (zero-cost abstraction):
/// - Makes data flow explicit (renderers declare their inputs)
/// - Enables unit testing with mock viewport
/// - Marginally faster (register vs memory access)
pub fn updateLayers(
    self: *Display,
    editor: anytype,
    viewport: ViewportState,
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

    // Get buffer handle for extmark lookups (signs, virtual text)
    const buffer_handle: i64 = if (T == *Editor) blk: {
        if (editor.current_buffer_id) |bid| {
            break :blk @intCast(bid.id);
        }
        break :blk 0;
    } else 0; // EditorContext doesn't use buffer handles

    // Clear layers that ALWAYS need full rebuild
    self.base_layer.clear();
    self.gutter_layer.clear();
    self.cursor_layer.clear();
    self.yank_layer.clear();
    self.search_layer.clear();

    // Selection layer is cleared in updateSelectionLayer() when visual mode is active.
    // When visual mode is inactive, we clear it here to remove stale selection highlights.
    // NOTE: We cannot optimize selection layer clearing because the selection region
    // changes on EVERY cursor move (it's defined by anchor + cursor position).
    if (!visual_state.active) {
        self.selection_layer.clear();
    }

    // Note: virtual_text_layer is managed by plugins via JSI

    // Get search matches from editor (only for Editor type, not EditorContext)
    const search_matches = if (T == *Editor)
        editor.getSearchMatches()
    else
        &[_]SearchMatch{};
    const search_match_index = if (T == *Editor)
        editor.search_match_index
    else
        null;

    // Update each layer in logical order (not z-order)
    // All layers now use unified registry (Neovim/Helix pattern)
    // Pass viewport to each layer updater for consistent viewport handling
    try updateBaseLayer(self, editor, viewport, registry, list_enabled, listchars);
    try updateGutterLayer(self, buffer, viewport, registry, buffer_handle);
    try updateSelectionLayer(self, buffer, viewport, visual_state, registry);
    try updateYankLayer(self, buffer, viewport, yank_highlight, registry);
    try updateSearchLayer(self, buffer, viewport, search_matches, search_match_index, registry);
    try updateCursorLayer(self, buffer, viewport, registry, cursorline_enabled);

    // Virtual text layer is updated by plugins, so skip it here
}

// ListCharsColors is now in shared listchars_renderer module (DRY)
const ListCharsColors = listchars_renderer.ListCharsColors;

/// Update base layer: Render buffer text content (z=0)
/// Generic over Editor/EditorContext types (both have same fields)
fn updateBaseLayer(
    self: *Display,
    editor: anytype,
    viewport: ViewportState,
    registry: *const HighlightRegistry,
    list_enabled: bool,
    listchars: *const ListChars,
) !void {
    const text_rows = viewport.height;
    // Get buffer from editor (handles both Editor and EditorContext types)
    const T = @TypeOf(editor);
    const buffer = if (T == *Editor)
        editor.getCurrentBuffer() orelse return error.NoCurrentBuffer
    else if (T == *EditorContext)
        editor.buffer()
    else
        &editor.buffer; // Duck-typed fallback for MockEditor in benchmarks
    const gutter_width = viewport.gutter_width;

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

    // Create syntax highlighter if tree-sitter LanguageTree available (per-buffer)
    // Using LanguageTreeHighlighter which supports language injections
    // (e.g., JS in Markdown code blocks, JSX in TypeScript)
    var lang_tree_highlighter: ?LanguageTreeHighlighter = null;
    if (buffer.getLanguageTree()) |lang_tree| {
        lang_tree_highlighter = LanguageTreeHighlighter.init(
            self.allocator,
            lang_tree,
            registry,
        );
    }

    // PERFORMANCE: Get highlight cache for this buffer
    // Cache stores computed tree-sitter styles per line to avoid re-computation
    const highlight_cache: ?*HighlightCache = buffer.getOrCreateHighlightCache() catch null;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = viewport.top + row;

        if (line_num < buffer.lineCount()) {
            const line = buffer.getLine(line_num).?;
            // getLine returns borrowed slice from cache - no free needed
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;

            // Apply horizontal scroll (Neovim behavior: all lines scroll together)
            const h_offset = viewport.left;
            const start_col = if (h_offset > 0)
                char_width.displayColumnToByte(line_without_newline, h_offset)
            else
                0;
            const remaining = line_without_newline[start_col..];

            // Calculate absolute byte offset in buffer for tree-sitter
            const line_byte_offset = buffer.content.byteOfLine(line_num);
            const text_byte_offset = line_byte_offset + start_col;

            // Render text to base layer
            // Priority: Syntax highlighting (cached) > listchars > plain text
            // Gracefully fall back to listchars/plain text if syntax highlighting fails
            const end_col = if (lang_tree_highlighter) |*lth| blk: {
                break :blk renderWithSyntaxHighlight(self, lth, row, gutter_width, remaining, text_byte_offset, line_num, line_byte_offset, highlight_cache, list_enabled, listchars, lc_colors, fg_color, bg_color) catch {
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
    viewport: ViewportState,
    registry: *const HighlightRegistry,
    buffer_handle: i64,
) !void {
    const text_rows = viewport.height;
    const gutter_width = viewport.gutter_width;
    if (gutter_width == 0) return;

    // Get LineNr style for background of empty gutter lines
    const line_nr_style = registry.get("LineNr");
    const empty_gutter_bg = if (line_nr_style.bg) |c| convertColor(c) else null;

    // Get buffer extmarks for sign lookup
    const buf_exts = namespace_api.getBufferExtmarks(buffer_handle);

    // Check if sign column is enabled (signs are rendered directly from extmarks, not gutter_manager)
    const sign_column_enabled = self.sign_column_config.mode == .yes;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = viewport.top + row;

        // Neovim behavior: lines beyond EOF have empty gutter (no line numbers)
        if (line_num >= buffer.lineCount()) {
            // Fill gutter with empty space for virtual lines (~ lines)
            self.gutter_layer.grid.fillRowRange(row, 0, gutter_width, .{ .char = ' ', .bg = empty_gutter_bg });
            continue;
        }

        // Get line number highlights from unified registry
        const is_cursor_line = (line_num == buffer.cursor.row);
        const style = if (is_cursor_line)
            registry.get("CursorLineNr")
        else
            line_nr_style;

        const gutter_fg = if (style.fg) |c| convertColor(c) else null;
        const gutter_bg = if (style.bg) |c| convertColor(c) else empty_gutter_bg;

        var gutter_col: usize = 0;

        // Render sign column FIRST (before line numbers) - matches Neovim layout
        if (sign_column_enabled) {
            // Use shared sign renderer for consistent UTF-8 handling
            const sign = sign_renderer.lookupSign(buf_exts, line_num);
            var sign_fg = gutter_fg;
            if (sign.hl_group) |hl_group| {
                const sign_style = registry.get(hl_group);
                if (sign_style.fg) |fg| {
                    sign_fg = convertColor(fg);
                }
            }

            // Render sign characters
            self.gutter_layer.grid.setCell(row, gutter_col, .{
                .char = sign.chars.char_0,
                .fg = sign_fg,
                .bg = gutter_bg,
            });
            gutter_col += 1;

            self.gutter_layer.grid.setCell(row, gutter_col, .{
                .char = sign.chars.char_1,
                .fg = sign_fg,
                .bg = gutter_bg,
            });
            gutter_col += 1;
        }

        // Render line numbers AFTER sign column
        // Get line number column directly (skip gutter_manager to avoid duplicate sign rendering)
        const line_num_col = self.gutter_manager.getColumn("line_numbers");
        if (line_num_col) |col| {
            if (col.enabled and col.cached_width > 0) {
                var line_num_buf: [32]u8 = undefined;
                const line_num_end = @min(col.cached_width, line_num_buf.len);
                const written = col.renderer(line_num, buffer.cursor.row, line_num_buf[0..line_num_end]);
                const gutter_str = line_num_buf[0..written];

                // Render line number characters
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
            }
        } else {
            // No line_numbers column - use gutter_manager.renderLine for other columns
            // Note: renderSignColumn is a no-op (returns 0), so gutter_buf only contains
            // non-sign columns. Signs were already rendered above from extmarks.
            var gutter_buf: [32]u8 = undefined;
            const gutter_str_len = self.gutter_manager.renderLine(
                line_num,
                buffer.cursor.row,
                &gutter_buf,
            );
            const gutter_str = gutter_buf[0..gutter_str_len];

            // Render gutter characters (starts after sign column which was already rendered)
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
    }

    self.gutter_layer.markDirty();
}

/// Update selection layer: Render visual mode selection (z=400)
pub fn updateSelectionLayer(
    self: *Display,
    buffer: *const Buffer,
    viewport: ViewportState,
    visual_state: *const VisualState,
    registry: *const HighlightRegistry,
) !void {
    const text_rows = viewport.height;
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

    const gutter_width = viewport.gutter_width;
    const text_cols = if (self.terminal_cols > gutter_width)
        self.terminal_cols - gutter_width
    else
        self.terminal_cols;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = viewport.top + row;

        // Check if line is in selection range
        if (line_num >= visual_range.start.line and line_num <= visual_range.end.line) {
            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num).?;
                // getLine returns borrowed slice from cache - no free needed
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll (Neovim behavior: all lines scroll together)
                const h_offset = viewport.left;
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
                            .char = 0, // Null char = background overlay, shows underlying text
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
    viewport: ViewportState,
    yank_highlight: *const YankHighlight,
    registry: *const HighlightRegistry,
) !void {
    const text_rows = viewport.height;
    if (!yank_highlight.active or !yank_highlight.isVisible()) return;

    // Get YankFlash highlight from unified registry
    const yank_style = registry.get("YankFlash");
    const yank_bg = if (yank_style.bg) |c|
        convertColor(c)
    else
        highlights.Color{ .r = 100, .g = 100, .b = 50 };

    const gutter_width = viewport.gutter_width;
    const text_cols = if (self.terminal_cols > gutter_width)
        self.terminal_cols - gutter_width
    else
        self.terminal_cols;

    var row: usize = 0;
    while (row < text_rows) : (row += 1) {
        const line_num = viewport.top + row;

        if (line_num >= yank_highlight.start.line and line_num <= yank_highlight.end.line) {
            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num).?;
                // getLine returns borrowed slice from cache - no free needed
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll (Neovim behavior: all lines scroll together)
                const h_offset = viewport.left;
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
                            .char = 0, // Null char = background overlay, shows underlying text
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

/// Update search layer: Render search match highlights (z=500)
fn updateSearchLayer(
    self: *Display,
    buffer: *const Buffer,
    viewport: ViewportState,
    search_matches: []const SearchMatch,
    current_match_index: ?usize,
    registry: *const HighlightRegistry,
) !void {
    const text_rows = viewport.height;
    if (search_matches.len == 0) return;

    // Get Search highlight from unified registry (Neovim: Search = all matches)
    // IncSearch highlight is for current match (during search)
    const search_style = registry.get("Search");
    const search_bg = if (search_style.bg) |c|
        convertColor(c)
    else
        highlights.Color{ .r = 255, .g = 255, .b = 0 }; // Default: yellow
    const search_fg: ?highlights.Color = if (search_style.fg) |c|
        convertColor(c)
    else
        null; // No default fg, use underlying text color

    // CurSearch highlight for current match (Neovim 0.8+)
    const cursearch_style = registry.get("CurSearch");
    const cursearch_bg = if (cursearch_style.bg) |c|
        convertColor(c)
    else
        highlights.Color{ .r = 255, .g = 128, .b = 0 }; // Default: orange
    const cursearch_fg: ?highlights.Color = if (cursearch_style.fg) |c|
        convertColor(c)
    else
        null;

    const gutter_width = viewport.gutter_width;
    const text_cols = if (self.terminal_cols > gutter_width)
        self.terminal_cols - gutter_width
    else
        self.terminal_cols;

    // Iterate through all search matches
    for (search_matches, 0..) |match, match_idx| {
        // Check if match is in visible viewport
        if (match.line < viewport.top or match.line >= viewport.top + text_rows) {
            continue;
        }

        const screen_row = match.line - viewport.top;

        // Get line content to calculate display column
        if (match.line >= buffer.lineCount()) continue;

        const line = buffer.getLine(match.line).?;
        // getLine returns borrowed slice from cache - no free needed
        const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
            line[0 .. line.len - 1]
        else
            line;

        // Apply horizontal scroll
        const h_offset = viewport.left;
        const start_col = if (h_offset > 0)
            char_width.displayColumnToByte(line_without_newline, h_offset)
        else
            0;

        // Check if match is visible after horizontal scroll
        if (match.col + match.len <= start_col) continue;
        if (match.col >= start_col + text_cols) continue;

        // Calculate visible portion of match
        const visible_start = if (match.col > start_col)
            match.col - start_col
        else
            0;
        const visible_end = @min(match.col + match.len - start_col, text_cols);

        // Use CurSearch for current match, Search for others
        const is_current = current_match_index != null and match_idx == current_match_index.?;
        const bg = if (is_current) cursearch_bg else search_bg;
        const fg = if (is_current) cursearch_fg else search_fg;

        // Render highlight for each column in the match
        var col = visible_start;
        while (col < visible_end) : (col += 1) {
            self.search_layer.grid.setCell(screen_row, gutter_width + col, .{
                .char = 0, // Null char = transparent, shows underlying text
                .bg = bg,
                .fg = fg,
            });
        }
    }

    self.search_layer.markDirty();
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
/// - line_num: Buffer line number (for cache lookup)
/// - line_byte_offset: Byte offset of line start in buffer (for cache span conversion)
/// - highlight_cache: Optional highlight cache for this buffer
/// - list_enabled: Whether listchars replacement is enabled
/// - listchars: Configuration for invisible character symbols
/// - lc_colors: Pre-computed listchars colors
/// - fg_color: Normal foreground color (fallback)
/// - bg_color: Normal background color (fallback)
///
/// Returns: Final column position after rendering
fn renderWithSyntaxHighlight(
    self: *Display,
    highlighter: *LanguageTreeHighlighter,
    row: usize,
    start_col: usize,
    text: []const u8,
    text_byte_offset: usize,
    line_num: usize,
    line_byte_offset: usize,
    highlight_cache: ?*HighlightCache,
    list_enabled: bool,
    listchars: *const ListChars,
    lc_colors: ListCharsColors,
    fg_color: ?highlights.Color,
    bg_color: ?highlights.Color,
) !usize {
    // PERFORMANCE: Check highlight cache first
    // If cached, use O(spans) direct lookup instead of O(bytes) hashmap
    var cached_spans: ?[]const StyleSpan = null;
    var cache_hit = false;
    var span_idx: usize = 0; // Current span index for advancing lookup

    if (highlight_cache) |cache| {
        if (cache.getStyleLine(line_num)) |cached_styles| {
            // Cache hit! Use cached spans for O(spans) lookup
            cached_spans = cached_styles.spans;
            cache_hit = true;
        }
    }

    // Build highlight map only on cache miss
    var highlight_map = std.AutoHashMap(usize, Style).init(self.allocator);
    defer highlight_map.deinit();

    // Temporary buffer for spans to cache
    var spans_to_cache: std.ArrayList(StyleSpan) = .empty;
    defer spans_to_cache.deinit(self.allocator);

    if (!cache_hit) {
        // Cache miss - compute via tree-sitter
        const range = Range{
            .start_byte = @intCast(text_byte_offset),
            .end_byte = @intCast(text_byte_offset + text.len),
        };

        var iter = try highlighter.highlights(range);
        defer iter.deinit();

        while (iter.next() catch null) |styled| {
            const range_start = if (styled.range.start_byte >= text_byte_offset)
                styled.range.start_byte - text_byte_offset
            else
                0;

            const range_end = if (styled.range.end_byte >= text_byte_offset)
                @min(styled.range.end_byte - text_byte_offset, text.len)
            else
                0;

            // Populate hashmap for rendering
            var byte_offset = range_start;
            while (byte_offset < range_end) : (byte_offset += 1) {
                try highlight_map.put(byte_offset, styled.style);
            }

            // Collect span for caching (relative to line start)
            const cache_start = if (styled.range.start_byte >= line_byte_offset)
                @as(u32, @intCast(styled.range.start_byte - line_byte_offset))
            else
                0;
            const cache_end = if (styled.range.end_byte >= line_byte_offset)
                @as(u32, @intCast(@min(styled.range.end_byte - line_byte_offset, text.len + (text_byte_offset - line_byte_offset))))
            else
                0;

            if (cache_start < cache_end) {
                try spans_to_cache.append(self.allocator, StyleSpan{
                    .start_byte = cache_start,
                    .end_byte = cache_end,
                    .style = styled.style,
                });
            }
        }

        // Store in cache for next render
        if (highlight_cache) |cache| {
            cache.setStyleLine(line_num, spans_to_cache.items) catch {};
        }
    }

    // Render text character by character with syntax colors
    const sk_fg = lc_colors.sk_fg;
    const sk_bg = lc_colors.sk_bg;
    var col = start_col;
    var byte_idx: usize = 0;
    var last_non_space_col = start_col;

    // Precompute the scroll offset for span lookup
    const scroll_offset = text_byte_offset - line_byte_offset;

    while (byte_idx < text.len and col < self.terminal_cols) {
        const char_len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + char_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[byte_idx .. byte_idx + char_len]) catch text[byte_idx];
        var display_char = codepoint;

        // Look up syntax highlight for this character
        // PERFORMANCE: Use cached spans O(spans) or hashmap O(1) lookup
        const syntax_style: ?Style = if (cached_spans) |spans| blk: {
            // Byte position relative to line start
            const line_byte = scroll_offset + byte_idx;

            // Advance past expired spans (O(spans) total for entire line)
            while (span_idx < spans.len and spans[span_idx].end_byte <= line_byte) {
                span_idx += 1;
            }

            // Check if current byte is within current span
            if (span_idx < spans.len) {
                const span = spans[span_idx];
                if (line_byte >= span.start_byte and line_byte < span.end_byte) {
                    break :blk span.style;
                }
            }
            break :blk null;
        } else highlight_map.get(byte_idx);

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
    viewport: ViewportState,
    registry: *const HighlightRegistry,
    cursorline_enabled: bool,
) !void {
    const text_rows = viewport.height;
    if (!cursorline_enabled) return;

    const cursor_line = buffer.cursor.row;
    if (cursor_line < viewport.top or cursor_line >= viewport.top + text_rows) return;

    const screen_row = cursor_line - viewport.top;

    // Get CursorLine highlight from unified registry
    const cursorline_style = registry.get("CursorLine");
    if (cursorline_style.bg == null) return; // No cursorline if bg not set

    const cursorline_bg = convertColor(cursorline_style.bg.?);

    // Render cursorline background for TEXT AREA ONLY (not gutter)
    // Neovim-compatible: CursorLine = text area, CursorLineNr = gutter
    // The gutter layer handles cursor line highlighting via CursorLineNr
    const gutter_width = viewport.gutter_width;
    for (gutter_width..self.terminal_cols) |col| {
        self.cursor_layer.grid.setCell(screen_row, col, .{
            .char = 0, // NULL character - won't hide base layer text
            .bg = cursorline_bg,
        });
    }

    self.cursor_layer.markDirty();
}
