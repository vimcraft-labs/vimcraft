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

// Syntax highlighting support (with language injection support via LanguageTree)
const LanguageTree = @import("../../../editor/treesitter/language_tree.zig").LanguageTree;
const LanguageTreeHighlighter = @import("../../../editor/treesitter/syntax_highlighter.zig").LanguageTreeHighlighter;
const Range = @import("../../../editor/treesitter/highlight.zig").Range;

// Highlight cache for efficient repeated rendering
const HighlightCache = @import("../../../editor/highlight_cache.zig").HighlightCache;
const StyleSpan = @import("../../../editor/highlight_cache.zig").StyleSpan;

// Namespace highlights (LSP diagnostics, plugin highlights)
const namespace_api = @import("../../../system/jsi/namespace_api.zig");

// Shared sign rendering (DRY: used by both layer_renderer and window_renderer)
const sign_renderer = @import("sign_renderer.zig");

// Shared listchars rendering (DRY: used by both layer_renderer and window_renderer)
const listchars_renderer = @import("listchars_renderer.zig");

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
    /// Buffer ID for namespace highlight lookups (0 = use buffer_id from window)
    buffer_handle: i64 = 0,
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
    /// LanguageTree for highlighting with injection support (null if unavailable)
    language_tree: ?*LanguageTree = null,
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

    // Render extmark virtual text (Neovim-style virt_text)
    try renderWindowVirtualText(display, ctx, gutter_width);

    // Mark window as rendered
    window.needs_redraw = false;
}

/// Ensure cursor is visible within window viewport (public version for display.zig)
/// This is the single source of truth for viewport scrolling calculations.
pub fn ensureCursorVisibleWithHeight(window: *Window, buffer: *const Buffer, visible_height: usize) void {
    ensureCursorVisible(window, buffer, visible_height);
}

/// Ensure cursor is visible within window viewport
fn ensureCursorVisible(window: *Window, buffer: *const Buffer, visible_height: usize) void {
    const scrolloff = window.options.scrolloff;
    const cursor_row = window.cursor.row;
    const old_top_line = window.viewport.top_line;

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

    // DEBUG: Log when viewport actually scrolls
    if (window.viewport.top_line != old_top_line) {
        std.log.debug("VIEWPORT_SCROLL: window_renderer.ensureCursorVisible: top_line {d} -> {d}, cursor_row={d}, visible_height={d}, scrolloff={d}, is_float={}", .{
            old_top_line,
            window.viewport.top_line,
            cursor_row,
            visible_height,
            scrolloff,
            window.isFloating(),
        });
    }

    // Update cursor screen position
    window.viewport.cursor_screen_row = cursor_row -| window.viewport.top_line;
    window.viewport.cursor_screen_col = window.cursor.col -| window.viewport.left_col;
}

/// Calculate gutter width for a specific window
/// Uses window-specific options including numberwidth for minimum line number field width
/// This must be used consistently for both rendering and cursor positioning
pub fn calculateWindowGutterWidth(window: *const Window, buffer: *const Buffer) usize {
    var width: usize = 0;

    // Sign column
    if (window.options.signcolumn == .yes) {
        width += 2;
    }

    // Line numbers - use window's numberwidth setting for minimum field width
    if (window.options.number or window.options.relativenumber) {
        width += gutter.calculateLineNumberWidthWithMin(buffer.lineCount(), window.options.numberwidth);
    }

    return width;
}

/// Render window text content to base layer
// Debug timing flag - set to false for production
const RENDER_TIMING_DEBUG = false;

fn renderWindowBaseLayer(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    const buffer = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;

    // Timing instrumentation (disabled in production)
    const start_time = if (RENDER_TIMING_DEBUG) std.time.nanoTimestamp() else 0;
    var setup_time: i128 = 0;
    var syntax_time: i128 = 0;
    var namespace_time: i128 = 0;
    var char_loop_time: i128 = 0;
    const is_floating = window.isFloating();

    // Select target layer: floating windows use float_layer (z=250) to appear above cursor layer (z=200)
    const target_layer = if (is_floating) display.float_layer else display.base_layer;

    // Get Normal or NormalFloat highlight from registry
    // Floating windows use NormalFloat to properly occlude lower layers (e.g., CursorLine)
    const normal_style = if (is_floating)
        ctx.registry.get("NormalFloat")
    else
        ctx.registry.get("Normal");
    const fg_color = if (normal_style.fg) |c| convertColor(c) else null;
    // Floating windows MUST have a background to occlude lower layers
    // Fallback to dark gray if NormalFloat.bg is not set
    const default_float_bg = highlights.Color{ .r = 0x1a, .g = 0x1b, .b = 0x26 };
    const bg_color: ?highlights.Color = if (normal_style.bg) |c|
        convertColor(c)
    else if (is_floating)
        default_float_bg
    else
        null;

    // Pre-compute listchars colors using shared module (DRY)
    const lc_colors = listchars_renderer.ListCharsColors.fromRegistry(ctx.registry, convertColor);

    // Create LanguageTree highlighter if available
    // Supports language injections (e.g., JS in Markdown code blocks)
    var lang_tree_highlighter: ?LanguageTreeHighlighter = null;
    var has_lang_tree_debug = false;
    if (ctx.language_tree) |lang_tree| {
        lang_tree_highlighter = LanguageTreeHighlighter.init(
            display.allocator,
            lang_tree,
            ctx.registry,
        );
        has_lang_tree_debug = true;
    }

    // Get or create highlight cache for this buffer
    const highlight_cache: ?*HighlightCache = buffer.getOrCreateHighlightCache() catch null;

    // Capture setup time (before main loop)
    if (RENDER_TIMING_DEBUG) {
        setup_time = std.time.nanoTimestamp() - start_time;
    }

    var row: usize = 0;
    while (row < region.height) : (row += 1) {
        const line_num = window.viewport.top_line + row;
        const screen_row = region.row + row;

        // Skip if outside layer bounds
        if (screen_row >= display.base_layer.grid.height) continue;

        if (line_num < buffer.lineCount()) {
            const line = buffer.getLine(line_num) orelse continue;
            // getLine returns borrowed slice from cache - no free needed

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

            // Build syntax highlight map for this line
            // PERFORMANCE: Check cache first, only compute via tree-sitter on cache miss
            const syntax_start = if (RENDER_TIMING_DEBUG) std.time.nanoTimestamp() else 0;

            // PERF FIX: Use direct span lookup for cache hits instead of O(bytes) hashmap
            // Cache stores spans as (start_byte, end_byte, style) - we walk through them
            // during rendering instead of pre-populating a per-byte hashmap.

            // For cache miss, we still need a hashmap (built during tree-sitter iteration)
            var highlight_map = std.AutoHashMap(usize, Style).init(display.allocator);
            defer highlight_map.deinit();

            // Track concealed byte offsets (for conceallevel >= 2)
            var conceal_set = std.AutoHashMap(usize, void).init(display.allocator);
            defer conceal_set.deinit();

            // Check window's conceal level (0=show, 1=replace, 2=hide, 3=completely hide)
            const conceal_level = window.options.conceallevel;

            // Cached spans for O(spans) lookup instead of O(bytes) hashmap
            var cached_spans: ?[]const StyleSpan = null;
            var cache_hit = false;
            var span_idx: usize = 0; // Current span index (advances as byte_idx increases)

            // Try to get cached highlights first - O(1) cache lookup
            if (highlight_cache) |cache| {
                if (cache.getStyleLine(line_num)) |cached_styles| {
                    // Cache hit! Store spans for direct lookup during char loop
                    // NO hashmap population here - that was the O(bytes) bottleneck!
                    cached_spans = cached_styles.spans;
                    cache_hit = true;
                }
            }

            // Cache miss - compute via tree-sitter and cache the result
            if (!cache_hit) {
                if (lang_tree_highlighter) |*lth| {
                    const range = Range{
                        .start_byte = @intCast(text_byte_offset),
                        .end_byte = @intCast(text_byte_offset + remaining.len),
                    };

                    // Temporary buffer for spans to cache
                    var spans_to_cache: std.ArrayList(StyleSpan) = .empty;
                    defer spans_to_cache.deinit(display.allocator);

                    var iter = lth.highlights(range) catch null;
                    if (iter) |*it| {
                        defer it.deinit();
                        // MultiTreeStyledHighlightIterator.next() returns !?StyledHighlight
                        while (it.next() catch null) |styled| {
                            const range_start = if (styled.range.start_byte >= text_byte_offset)
                                styled.range.start_byte - text_byte_offset
                            else
                                0;
                            const range_end = if (styled.range.end_byte >= text_byte_offset)
                                @min(styled.range.end_byte - text_byte_offset, remaining.len)
                            else
                                0;

                            // Populate highlight_map for rendering
                            var byte_offset = range_start;
                            while (byte_offset < range_end) : (byte_offset += 1) {
                                highlight_map.put(byte_offset, styled.style) catch {};
                                // Track concealed bytes (for conceallevel >= 2)
                                if (styled.conceal != null and conceal_level >= 2) {
                                    conceal_set.put(byte_offset, {}) catch {};
                                }
                            }

                            // Collect span for caching (relative to line start, not scroll)
                            const cache_start = if (styled.range.start_byte >= line_byte_offset)
                                @as(u32, @intCast(styled.range.start_byte - line_byte_offset))
                            else
                                0;
                            const cache_end = if (styled.range.end_byte >= line_byte_offset)
                                @as(u32, @intCast(@min(styled.range.end_byte - line_byte_offset, line_without_newline.len)))
                            else
                                0;

                            if (cache_start < cache_end) {
                                spans_to_cache.append(display.allocator, StyleSpan{
                                    .start_byte = cache_start,
                                    .end_byte = cache_end,
                                    .style = styled.style,
                                }) catch {};
                            }
                        }
                    }

                    // Store in cache for next render
                    if (highlight_cache) |cache| {
                        cache.setStyleLine(line_num, spans_to_cache.items) catch {};
                    }
                }
            }

            // Accumulate syntax highlighting time
            if (RENDER_TIMING_DEBUG) {
                syntax_time += std.time.nanoTimestamp() - syntax_start;
            }

            // Render text to base layer (clipped to window region)
            const start_col = region.col + gutter_width;
            var screen_col: usize = start_col;
            var byte_idx: usize = 0;
            var last_non_space_col: usize = start_col; // For trailing space detection (listchars)

            // PERFORMANCE FIX: Collect namespace highlights for this line ONCE (outside char loop)
            // Previous code was O(chars × highlights) - now O(highlights) per line
            const namespace_start = if (RENDER_TIMING_DEBUG) std.time.nanoTimestamp() else 0;

            const NamespaceHighlight = struct {
                col_start: usize,
                col_end: usize,
                fg: ?highlights.Color,
                bg: ?highlights.Color,
            };
            var ns_highlights: [32]NamespaceHighlight = undefined; // Stack buffer, max 32 highlights per line
            var ns_highlight_count: usize = 0;

            const buf_handle = ctx.buffer_handle;
            if (namespace_api.getBufferHighlights(buf_handle)) |buf_hls| {
                var hl_iter = buf_hls.iterHighlightsForLine(line_num);
                while (hl_iter.next()) |hl| {
                    if (ns_highlight_count >= 32) break; // Safety limit
                    const hl_style = ctx.registry.get(hl.hl_group);
                    ns_highlights[ns_highlight_count] = .{
                        .col_start = hl.col_start,
                        .col_end = hl.col_end,
                        .fg = if (hl_style.fg) |c| convertColor(c) else null,
                        .bg = if (hl_style.bg) |c| convertColor(c) else null,
                    };
                    ns_highlight_count += 1;
                }
            }

            if (RENDER_TIMING_DEBUG) {
                namespace_time += std.time.nanoTimestamp() - namespace_start;
            }

            const char_loop_start = if (RENDER_TIMING_DEBUG) std.time.nanoTimestamp() else 0;

            while (byte_idx < remaining.len and screen_col < region.col + region.width) {
                const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                if (byte_idx + char_len > remaining.len) break;

                // Skip concealed characters (conceallevel >= 2)
                // This hides markdown code fence delimiters (```typescript) in popups
                if (conceal_set.contains(byte_idx)) {
                    byte_idx += char_len;
                    continue;
                }

                const codepoint = std.unicode.utf8Decode(remaining[byte_idx..][0..char_len]) catch ' ';

                // Get display width of character (1 for normal, 2 for wide chars like emoji/CJK)
                const display_width = char_width.codepointWidth(codepoint);

                // Skip zero-width characters (combining marks, variation selectors)
                if (display_width == 0) {
                    byte_idx += char_len;
                    continue;
                }

                // Look up syntax highlight for this character
                // PERF FIX: Use advancing span index for O(spans) total per line
                // Since byte_idx only increases, we advance span_idx past expired spans
                const syntax_style: ?Style = if (cached_spans) |spans| blk: {
                    // Byte position relative to line start (spans use line-relative offsets)
                    const line_byte = start_byte + byte_idx;

                    // Advance past spans that end before current byte (O(spans) total)
                    while (span_idx < spans.len and spans[span_idx].end_byte <= line_byte) {
                        span_idx += 1;
                    }

                    // Check if current byte is within the current span
                    if (span_idx < spans.len) {
                        const span = spans[span_idx];
                        if (line_byte >= span.start_byte and line_byte < span.end_byte) {
                            break :blk span.style;
                        }
                    }
                    break :blk null;
                } else highlight_map.get(byte_idx); // Fallback to hashmap for cache miss

                var char_fg = if (syntax_style) |style|
                    if (style.fg) |c| convertColor(c) else fg_color
                else
                    fg_color;
                var char_bg = if (syntax_style) |style|
                    if (style.bg) |c| convertColor(c) else bg_color
                else
                    bg_color;

                // Apply namespace highlights (LSP diagnostics, plugin highlights)
                // PERFORMANCE: Now O(highlights) instead of O(chars × highlights)
                const buffer_col = start_byte + byte_idx;
                for (ns_highlights[0..ns_highlight_count]) |hl| {
                    if (buffer_col >= hl.col_start and buffer_col < hl.col_end) {
                        if (hl.fg) |c| char_fg = c;
                        if (hl.bg) |c| char_bg = c;
                        break; // First matching highlight wins
                    }
                }

                // Handle listchars replacements using shared module (DRY)
                if (ctx.list_enabled) {
                    if (codepoint == '\t') {
                        // Tab: use shared tab renderer
                        const max_col = region.col + region.width;
                        if (screen_col >= region.col + gutter_width and screen_col < max_col) {
                            const tab_result = listchars_renderer.renderTab(
                                &display.base_layer.grid,
                                screen_row,
                                screen_col,
                                max_col,
                                ctx.listchars,
                                lc_colors,
                            );
                            if (tab_result.cols_consumed > 0) {
                                screen_col += tab_result.cols_consumed;
                                if (tab_result.is_non_space) {
                                    last_non_space_col = screen_col;
                                }
                                byte_idx += char_len;
                                continue;
                            }
                        }
                    } else if (listchars_renderer.getCharReplacement(codepoint, ctx.listchars, lc_colors)) |replacement| {
                        // Space/nbsp replacement
                        if (screen_col >= region.col + gutter_width and screen_col < region.col + region.width) {
                            target_layer.grid.setCell(screen_row, screen_col, .{
                                .char = replacement.char,
                                .fg = replacement.fg,
                                .bg = replacement.bg,
                            });
                        }
                        if (replacement.is_non_space) {
                            last_non_space_col = screen_col + 1;
                        }
                        screen_col += 1;
                        byte_idx += char_len;
                        continue;
                    } else if (listchars_renderer.isNonSpace(codepoint)) {
                        last_non_space_col = screen_col + 1;
                    }
                } else {
                    // Track last non-space column even when listchars disabled
                    if (listchars_renderer.isNonSpace(codepoint)) {
                        last_non_space_col = screen_col + 1;
                    }
                }

                // Clip to window bounds
                if (screen_col >= region.col + gutter_width and screen_col < region.col + region.width) {
                    target_layer.grid.setCell(screen_row, screen_col, .{
                        .char = codepoint,
                        .fg = char_fg,
                        .bg = char_bg,
                    });

                    // For wide characters (width 2), set continuation marker on next cell
                    if (display_width == 2 and screen_col + 1 < region.col + region.width) {
                        target_layer.grid.setCell(screen_row, screen_col + 1, .{
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

            // Accumulate char loop time
            if (RENDER_TIMING_DEBUG) {
                char_loop_time += std.time.nanoTimestamp() - char_loop_start;
            }

            // Post-process: mark trailing spaces using shared module (DRY)
            if (ctx.list_enabled) {
                listchars_renderer.markTrailingSpaces(
                    &target_layer.grid,
                    screen_row,
                    last_non_space_col,
                    screen_col,
                    ctx.listchars,
                    lc_colors,
                );

                // Render EOL character if configured
                screen_col += listchars_renderer.renderEol(
                    &target_layer.grid,
                    screen_row,
                    screen_col,
                    region.col + region.width,
                    ctx.listchars,
                    lc_colors,
                );
            }

            // Fill rest of line with spaces
            while (screen_col < region.col + region.width) : (screen_col += 1) {
                target_layer.grid.setCell(screen_row, screen_col, .{
                    .char = ' ',
                    .bg = bg_color,
                });
            }
        } else {
            // Empty line indicator (~)
            const start_col = region.col + gutter_width;
            target_layer.grid.setCell(screen_row, start_col, .{
                .char = '~',
                .fg = fg_color,
                .bg = bg_color,
            });

            // Fill rest with spaces
            var col = start_col + 1;
            while (col < region.col + region.width) : (col += 1) {
                target_layer.grid.setCell(screen_row, col, .{
                    .char = ' ',
                    .bg = bg_color,
                });
            }
        }
    }

    // Debug timing output (disabled in production via RENDER_TIMING_DEBUG flag)
    if (RENDER_TIMING_DEBUG) {
        std.debug.print("RENDER: syntax={d:.1}ms\n", .{
            @as(f64, @floatFromInt(syntax_time)) / 1_000_000.0,
        });
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

    const buffer = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;

    // Get LineNr style for background of empty gutter lines
    const line_nr_style = ctx.registry.get("LineNr");
    const gutter_bg = if (line_nr_style.bg) |c| convertColor(c) else null;

    var row: usize = 0;
    while (row < region.height) : (row += 1) {
        const line_num = window.viewport.top_line + row;
        const screen_row = region.row + row;

        // Skip if outside layer bounds
        if (screen_row >= display.gutter_layer.grid.height) continue;

        // Neovim behavior: lines beyond EOF have empty gutter (no line numbers)
        if (line_num >= buffer.lineCount()) {
            // Fill gutter with empty space for virtual lines (~ lines)
            display.gutter_layer.grid.fillRowRange(screen_row, region.col, region.col + gutter_width, .{ .char = ' ', .bg = gutter_bg });
            continue;
        }

        // Get line number style for actual buffer lines
        const is_cursor_line = (line_num == window.cursor.row);
        const style = if (is_cursor_line)
            ctx.registry.get("CursorLineNr")
        else
            line_nr_style;

        const gutter_fg = if (style.fg) |c| convertColor(c) else null;
        const style_bg = if (style.bg) |c| convertColor(c) else gutter_bg;

        // Render sign column first (if enabled)
        var gutter_offset: usize = 0;
        if (window.options.signcolumn == .yes) {
            // Use shared sign renderer for consistent UTF-8 handling
            const sign = sign_renderer.lookupSignByHandle(ctx.buffer_handle, line_num);
            var sign_fg = gutter_fg;
            if (sign.hl_group) |hl_group| {
                const sign_style = ctx.registry.get(hl_group);
                if (sign_style.fg) |fg| {
                    sign_fg = convertColor(fg);
                }
            }

            display.gutter_layer.grid.setCell(screen_row, region.col, .{
                .char = sign.chars.char_0,
                .fg = sign_fg,
                .bg = style_bg,
            });
            display.gutter_layer.grid.setCell(screen_row, region.col + 1, .{
                .char = sign.chars.char_1,
                .fg = sign_fg,
                .bg = style_bg,
            });
            gutter_offset = 2;
        }

        // Render line number after sign column
        if (window.options.number or window.options.relativenumber) {
            // Calculate line number width using window's numberwidth setting
            const line_num_width = gutter.calculateLineNumberWidthWithMin(buffer.lineCount(), window.options.numberwidth);

            // Allocate buffer for line number rendering
            var render_buf: [16]u8 = undefined;
            const num_buf = render_buf[0..line_num_width];

            // Use shared gutter renderer for consistent behavior
            const rendered_len = if (window.options.relativenumber and !is_cursor_line)
                gutter.renderRelativeLineNumber(line_num, window.cursor.row, num_buf)
            else
                gutter.renderAbsoluteLineNumber(line_num, window.cursor.row, num_buf);

            // Render the generated line number to gutter layer (after sign column)
            var num_col: usize = 0;
            while (num_col < rendered_len and num_col < line_num_width) : (num_col += 1) {
                display.gutter_layer.grid.setCell(screen_row, region.col + gutter_offset + num_col, .{
                    .char = num_buf[num_col],
                    .fg = gutter_fg,
                    .bg = style_bg,
                });
            }

            // Pad remaining line number space
            while (num_col < line_num_width) : (num_col += 1) {
                display.gutter_layer.grid.setCell(screen_row, region.col + gutter_offset + num_col, .{
                    .char = ' ',
                    .fg = gutter_fg,
                    .bg = style_bg,
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

    // Render cursorline background for TEXT AREA ONLY (not gutter)
    // Neovim-compatible: CursorLine = text area, CursorLineNr = gutter
    // The gutter layer handles cursor line highlighting via CursorLineNr
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
                // getLine returns borrowed slice from cache - no free needed

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
                var highlighted_any = false;

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
                            .char = 0, // Null char = background overlay, shows underlying text
                            .bg = visual_bg,
                        });
                        highlighted_any = true;
                    }

                    screen_col += 1;
                    byte_idx += char_len;
                }

                // Neovim behavior: empty lines in visual selection still highlight first cell
                // This makes the selection visible even on blank lines
                if (!highlighted_any and remaining.len == 0) {
                    const first_col = region.col + gutter_width;
                    if (first_col < region.col + region.width) {
                        display.selection_layer.grid.setCell(screen_row, first_col, .{
                            .char = 0, // Null char = background overlay
                            .bg = visual_bg,
                        });
                    }
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
                // getLine returns borrowed slice from cache - no free needed

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

    display.yank_layer.markDirty();
}

/// Render extmark virtual text to virtual_text_layer
/// Supports virt_text_pos: eol (end of line), overlay (at position), rightAlign, inline
/// This is the Neovim-compatible extmarks API for displaying diagnostic messages, hints, etc.
fn renderWindowVirtualText(
    display: *Display,
    ctx: *const WindowRenderContext,
    gutter_width: usize,
) !void {
    const buffer = ctx.buffer;
    const window = ctx.window;
    const region = ctx.region;
    const buf_handle = ctx.buffer_handle;

    // Get extmarks for this buffer
    const buf_exts = namespace_api.getBufferExtmarks(buf_handle) orelse return;
    const extmarks = buf_exts.getAll();

    // Process each extmark with virt_text
    for (extmarks) |ext| {
        const virt_text = ext.virt_text orelse continue;
        if (virt_text.len == 0) continue;

        // Check if extmark line is visible in viewport
        if (ext.line < window.viewport.top_line or
            ext.line >= window.viewport.top_line + region.height)
        {
            continue;
        }

        const screen_row = region.row + (ext.line - window.viewport.top_line);

        // Skip if outside layer bounds
        if (screen_row >= display.virtual_text_layer.grid.height) continue;

        // Calculate starting screen column based on virt_text_pos
        var screen_col: usize = switch (ext.virt_text_pos) {
            .eol => blk: {
                // End of line: after all text content
                if (ext.line < buffer.lineCount()) {
                    const line = buffer.getLine(ext.line) orelse break :blk region.col + gutter_width;
                    // getLine returns borrowed slice from cache - no free needed

                    const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                        line[0 .. line.len - 1]
                    else
                        line;

                    // Calculate display width of line (accounting for wide chars)
                    const line_display_width = char_width.stringWidth(line_without_newline);

                    // Apply horizontal scroll offset
                    const visible_width = if (line_display_width > window.viewport.left_col)
                        line_display_width - window.viewport.left_col
                    else
                        0;

                    // Position after line content + 1 space separator
                    break :blk region.col + gutter_width + visible_width + 1;
                }
                break :blk region.col + gutter_width;
            },
            .overlay => blk: {
                // Overlay: at extmark column position
                break :blk region.col + gutter_width + (ext.col -| window.viewport.left_col);
            },
            .rightAlign => blk: {
                // Right align: calculate total virt_text width and align to right edge
                var total_width: usize = 0;
                for (virt_text) |chunk| {
                    total_width += char_width.stringWidth(chunk.text);
                }
                const right_edge = region.col + region.width;
                break :blk if (right_edge > total_width) right_edge - total_width else region.col + gutter_width;
            },
            .@"inline" => blk: {
                // Inline: at extmark column position (same as overlay for now)
                // Full inline support would require shifting text, which is complex
                break :blk region.col + gutter_width + (ext.col -| window.viewport.left_col);
            },
        };

        // Render each chunk of virtual text
        for (virt_text) |chunk| {
            // Get highlight colors for this chunk
            var fg_color: ?highlights.Color = null;
            var bg_color: ?highlights.Color = null;

            if (chunk.hl_group) |hl_group| {
                const style = ctx.registry.get(hl_group);
                if (style.fg) |c| fg_color = convertColor(c);
                if (style.bg) |c| bg_color = convertColor(c);
            }

            // Render each character in the chunk
            var byte_idx: usize = 0;
            while (byte_idx < chunk.text.len and screen_col < region.col + region.width) {
                const char_len = std.unicode.utf8ByteSequenceLength(chunk.text[byte_idx]) catch 1;
                if (byte_idx + char_len > chunk.text.len) break;

                const codepoint = std.unicode.utf8Decode(chunk.text[byte_idx..][0..char_len]) catch ' ';
                const display_width = char_width.codepointWidth(codepoint);

                // Skip zero-width characters
                if (display_width == 0) {
                    byte_idx += char_len;
                    continue;
                }

                // Set cell in virtual text layer
                if (screen_col >= region.col and screen_col < region.col + region.width) {
                    display.virtual_text_layer.grid.setCell(screen_row, screen_col, .{
                        .char = codepoint,
                        .fg = fg_color,
                        .bg = bg_color,
                    });

                    // Handle wide characters
                    if (display_width == 2 and screen_col + 1 < region.col + region.width) {
                        display.virtual_text_layer.grid.setCell(screen_row, screen_col + 1, .{
                            .char = ' ',
                            .fg = fg_color,
                            .bg = bg_color,
                            .is_continuation = true,
                        });
                    }
                }

                screen_col += display_width;
                byte_idx += char_len;
            }
        }
    }

    display.virtual_text_layer.markDirty();
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

    // Format status text: filename [+] row:col
    // NOTE: Mode indicator is shown on the global command line (last row), not here
    // This matches Neovim's behavior where showmode displays on the command line
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
// Use shared color conversion (DRY)
fn convertColor(api_color: Color) highlights.Color {
    return highlights.Color.fromApiColor(api_color);
}

// ============================================================================
// Floating Window Border Rendering
// ============================================================================
// Renders borders around floating windows using Unicode box-drawing characters.
// Neovim-compatible border styles: none, single, double, rounded, solid, shadow
//
// Border layout (for a 3x5 content window):
//   ┌─────┐  <- top border row (row-1)
//   │     │  <- content rows with left (col-1) and right (col+width) borders
//   │     │
//   │     │
//   └─────┘  <- bottom border row (row+height)
//
// The border is rendered AROUND the window region, not inside it.

const BorderStyle = @import("../../../editor/window.zig").BorderStyle;
const FloatingConfig = @import("../../../editor/window.zig").FloatingConfig;

/// Border character set for different styles
const BorderChars = struct {
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
    horizontal: u21,
    vertical: u21,
};

/// Get border characters for a given style
fn getBorderChars(style: BorderStyle) ?BorderChars {
    return switch (style) {
        .none => null,
        .single => .{
            .top_left = '┌',
            .top_right = '┐',
            .bottom_left = '└',
            .bottom_right = '┘',
            .horizontal = '─',
            .vertical = '│',
        },
        .double => .{
            .top_left = '╔',
            .top_right = '╗',
            .bottom_left = '╚',
            .bottom_right = '╝',
            .horizontal = '═',
            .vertical = '║',
        },
        .rounded => .{
            .top_left = '╭',
            .top_right = '╮',
            .bottom_left = '╰',
            .bottom_right = '╯',
            .horizontal = '─',
            .vertical = '│',
        },
        .solid => .{
            .top_left = '█',
            .top_right = '█',
            .bottom_left = '█',
            .bottom_right = '█',
            .horizontal = '▀',
            .vertical = '█',
        },
        .shadow => .{
            // Shadow style: thin border with shadow effect
            // The shadow is rendered separately on the right and bottom
            .top_left = '┌',
            .top_right = '┐',
            .bottom_left = '└',
            .bottom_right = '┘',
            .horizontal = '─',
            .vertical = '│',
        },
    };
}

/// Render border around a floating window
/// This renders to the float_layer (z=250) so it appears above cursor layer
/// override_row/col: Optional position overrides for cursor-relative floats
/// (used when viewport scrolls after float creation)
pub fn renderFloatingWindowBorder(
    display: *Display,
    window: *const Window,
    registry: *const HighlightRegistry,
    override_row: ?usize,
    override_col: ?usize,
) void {
    // Only render border for floating windows
    const config = window.floating_config orelse return;
    if (config.hide) return;

    // Get border characters for the style
    const border_chars = getBorderChars(config.border) orelse return;

    // Get FloatBorder highlight (Neovim uses FloatBorder for all border elements)
    const border_style = registry.get("FloatBorder");
    const fg_color = if (border_style.fg) |c| convertColor(c) else highlights.Color{ .r = 128, .g = 128, .b = 128 };
    // Border MUST have background to occlude lower layers - fallback to dark gray
    const default_float_bg = highlights.Color{ .r = 0x1a, .g = 0x1b, .b = 0x26 };
    const bg_color: ?highlights.Color = if (border_style.bg) |c| convertColor(c) else default_float_bg;

    // Get window region (this is the CONTENT area, border is OUTSIDE it)
    // Use overrides if provided (for cursor-relative floats after viewport scroll)
    const content_row = override_row orelse window.screen_row;
    const content_col = override_col orelse window.screen_col;
    const content_height = window.height;
    const content_width = window.width;

    // Border positions (outside content area)
    // Note: We need to ensure border doesn't go out of bounds
    const border_top: usize = if (content_row > 0) content_row - 1 else 0;
    const border_left: usize = if (content_col > 0) content_col - 1 else 0;
    const border_bottom: usize = content_row + content_height;
    const border_right: usize = content_col + content_width;

    const grid_height = display.float_layer.grid.height;
    const grid_width = display.float_layer.grid.width;

    // Render top border row
    if (border_top < grid_height and content_row > 0) {
        // Top-left corner
        if (border_left < grid_width and content_col > 0) {
            display.float_layer.grid.setCell(border_top, border_left, .{
                .char = border_chars.top_left,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Top horizontal line
        var col = content_col;
        while (col < border_right and col < grid_width) : (col += 1) {
            display.float_layer.grid.setCell(border_top, col, .{
                .char = border_chars.horizontal,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Top-right corner
        if (border_right < grid_width) {
            display.float_layer.grid.setCell(border_top, border_right, .{
                .char = border_chars.top_right,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Render title in top border if present
        if (config.title) |title| {
            renderBorderTitle(display, border_top, content_col, content_width, title, config.title_pos, fg_color, bg_color, grid_width);
        }
    }

    // Render left and right vertical borders
    var row = content_row;
    while (row < border_bottom and row < grid_height) : (row += 1) {
        // Left border
        if (border_left < grid_width and content_col > 0) {
            display.float_layer.grid.setCell(row, border_left, .{
                .char = border_chars.vertical,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Right border
        if (border_right < grid_width) {
            display.float_layer.grid.setCell(row, border_right, .{
                .char = border_chars.vertical,
                .fg = fg_color,
                .bg = bg_color,
            });
        }
    }

    // Render bottom border row
    if (border_bottom < grid_height) {
        // Bottom-left corner
        if (border_left < grid_width and content_col > 0) {
            display.float_layer.grid.setCell(border_bottom, border_left, .{
                .char = border_chars.bottom_left,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Bottom horizontal line
        var col = content_col;
        while (col < border_right and col < grid_width) : (col += 1) {
            display.float_layer.grid.setCell(border_bottom, col, .{
                .char = border_chars.horizontal,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Bottom-right corner
        if (border_right < grid_width) {
            display.float_layer.grid.setCell(border_bottom, border_right, .{
                .char = border_chars.bottom_right,
                .fg = fg_color,
                .bg = bg_color,
            });
        }

        // Render footer in bottom border if present
        if (config.footer) |footer| {
            renderBorderTitle(display, border_bottom, content_col, content_width, footer, config.footer_pos, fg_color, bg_color, grid_width);
        }
    }

    // Render shadow effect for shadow border style
    if (config.border == .shadow) {
        renderShadowEffect(display, content_row, content_col, content_height, content_width, grid_height, grid_width);
    }

    display.float_layer.markDirty();
}

/// Render title/footer text within the border
/// Uses UTF-8 safe truncation to avoid breaking multi-byte sequences
fn renderBorderTitle(
    display: *Display,
    row: usize,
    content_col: usize,
    content_width: usize,
    text: []const u8,
    pos: FloatingConfig.TitlePos,
    fg_color: highlights.Color,
    bg_color: ?highlights.Color,
    grid_width: usize,
) void {
    if (text.len == 0) return;
    if (content_width < 4) return; // Need at least some space for title

    // Calculate available width (leave 1 char on each side for corners/borders)
    const available_width = content_width;

    // UTF-8 safe truncation: find proper byte boundary and display width
    var display_width: usize = 0;
    var truncated_byte_len: usize = 0;
    var byte_idx: usize = 0;

    while (byte_idx < text.len) {
        const char_len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + char_len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[byte_idx..][0..char_len]) catch ' ';
        const char_width_val = char_width.codepointWidth(codepoint);

        // Would this character exceed available width?
        if (display_width + char_width_val > available_width) break;

        display_width += char_width_val;
        truncated_byte_len = byte_idx + char_len;
        byte_idx += char_len;
    }

    if (truncated_byte_len == 0) return;
    const display_text = text[0..truncated_byte_len];

    // Calculate starting position based on alignment (use display_width, not byte length)
    const start_col: usize = switch (pos) {
        .left => content_col + 1,
        .center => content_col + (available_width -| display_width) / 2,
        .right => blk: {
            // Avoid underflow: ensure we don't go below content_col
            if (available_width > display_width + 1) {
                break :blk content_col + available_width - display_width - 1;
            } else {
                break :blk content_col + 1;
            }
        },
    };

    // Render title characters (properly handling UTF-8 and wide chars)
    var col = start_col;
    byte_idx = 0;
    while (byte_idx < display_text.len) {
        if (col >= grid_width) break;
        if (col >= content_col + content_width) break;

        const char_len = std.unicode.utf8ByteSequenceLength(display_text[byte_idx]) catch 1;
        if (byte_idx + char_len > display_text.len) break;

        const codepoint = std.unicode.utf8Decode(display_text[byte_idx..][0..char_len]) catch ' ';
        const char_display_width = char_width.codepointWidth(codepoint);

        // Skip zero-width characters
        if (char_display_width == 0) {
            byte_idx += char_len;
            continue;
        }

        if (col >= content_col) {
            display.float_layer.grid.setCell(row, col, .{
                .char = codepoint,
                .fg = fg_color,
                .bg = bg_color,
            });

            // Handle wide characters (e.g., CJK, emoji)
            if (char_display_width == 2 and col + 1 < grid_width and col + 1 < content_col + content_width) {
                display.float_layer.grid.setCell(row, col + 1, .{
                    .char = ' ',
                    .fg = fg_color,
                    .bg = bg_color,
                    .is_continuation = true,
                });
            }
        }

        col += char_display_width;
        byte_idx += char_len;
    }
}

/// Render shadow effect (bottom-right shadow)
fn renderShadowEffect(
    display: *Display,
    content_row: usize,
    content_col: usize,
    content_height: usize,
    content_width: usize,
    grid_height: usize,
    grid_width: usize,
) void {
    const shadow_color = highlights.Color{ .r = 64, .g = 64, .b = 64 };

    // Shadow on right side (1 column to the right of the right border)
    const shadow_right_col = content_col + content_width + 1;
    if (shadow_right_col < grid_width) {
        var row = content_row + 1;
        while (row <= content_row + content_height + 1 and row < grid_height) : (row += 1) {
            display.float_layer.grid.setCell(row, shadow_right_col, .{
                .char = ' ',
                .fg = null,
                .bg = shadow_color,
            });
        }
    }

    // Shadow on bottom (1 row below the bottom border)
    const shadow_bottom_row = content_row + content_height + 1;
    if (shadow_bottom_row < grid_height) {
        var col = content_col + 1;
        while (col <= content_col + content_width + 1 and col < grid_width) : (col += 1) {
            display.float_layer.grid.setCell(shadow_bottom_row, col, .{
                .char = ' ',
                .fg = null,
                .bg = shadow_color,
            });
        }
    }
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
