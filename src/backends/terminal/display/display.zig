const std = @import("std");
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../../editor/editor.zig").Editor;
const EditorContext = @import("../../headless/editor_context.zig").EditorContext;
const debug_log = @import("../../headless/log.zig");
const highlights = @import("../../../editor/config/highlights.zig");
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const Cell = @import("screen_grid.zig").Cell;
const Update = @import("screen_grid.zig").Update;
const VisualState = @import("../../../editor/visual/visual.zig").VisualState;
const YankHighlight = @import("../../../editor/visual/yank_highlight.zig").YankHighlight;
const Position = @import("../../../editor/visual/visual.zig").Position;
const char_width = @import("char_width.zig");
const gutter = @import("gutter.zig");
const VirtualTextRenderer = @import("virtual_text.zig").VirtualTextRenderer;
const ListChars = @import("../../../editor/config/listchars.zig").ListChars;

// Multi-layer rendering system (Phase 2)
const Layer = @import("layer.zig").Layer;
const LayerManager = @import("layer.zig").LayerManager;
const ZIndex = @import("layer.zig").ZIndex;
const Compositor = @import("compositor.zig").Compositor;

// Refactored modules (Phase 2.5)
const terminal_control = @import("terminal_control.zig");
const layer_renderer = @import("layer_renderer.zig");
const output_renderer = @import("output_renderer.zig");

// Highlight registry (for StatusLine highlight support)
const highlight_api = @import("../../../system/jsi/highlight_api.zig");

/// Rendering performance statistics
/// Tracks real-time metrics for debug protocol get_render_stats command
pub const RenderStatistics = struct {
    // Frame timing
    last_render_start_ns: i128 = 0,
    last_render_duration_ns: i128 = 0,
    total_render_time_ns: i128 = 0,
    max_render_duration_ns: i128 = 0,
    total_renders: usize = 0,

    // Cursor escape codes sent (for flickering diagnosis)
    cursor_hide_codes: usize = 0,
    cursor_show_codes: usize = 0,
    cursor_shape_codes: usize = 0,
    cursor_position_codes: usize = 0,

    // Synchronized update codes sent
    sync_update_begin_codes: usize = 0,
    sync_update_end_codes: usize = 0,

    // Compositor stats from last render
    layers_composited_last: usize = 0,
    cells_updated_last: usize = 0,
    cells_blended_last: usize = 0,

    pub fn recordRenderStart(self: *RenderStatistics) void {
        self.last_render_start_ns = std.time.nanoTimestamp();
    }

    pub fn recordRenderEnd(self: *RenderStatistics) void {
        const end_ns = std.time.nanoTimestamp();
        self.last_render_duration_ns = end_ns - self.last_render_start_ns;
        self.total_render_time_ns += self.last_render_duration_ns;
        self.total_renders += 1;

        if (self.last_render_duration_ns > self.max_render_duration_ns) {
            self.max_render_duration_ns = self.last_render_duration_ns;
        }
    }

    pub fn getAverageRenderDurationMs(self: *const RenderStatistics) f64 {
        if (self.total_renders == 0) return 0.0;
        const avg_ns = @as(f64, @floatFromInt(self.total_render_time_ns)) / @as(f64, @floatFromInt(self.total_renders));
        return avg_ns / 1_000_000.0; // Convert ns to ms
    }

    pub fn getLastRenderDurationMs(self: *const RenderStatistics) f64 {
        const ns = @as(f64, @floatFromInt(self.last_render_duration_ns));
        return ns / 1_000_000.0;
    }

    pub fn getMaxRenderDurationMs(self: *const RenderStatistics) f64 {
        const ns = @as(f64, @floatFromInt(self.max_render_duration_ns));
        return ns / 1_000_000.0;
    }
};

/// Sentinel value for uninitialized cursor position (forces first cursor move on launch)
const CURSOR_POS_UNINITIALIZED: usize = std.math.maxInt(usize);

/// Terminal display manager
/// Handles rendering buffer content to terminal using ANSI escape codes
/// Now uses grid-based rendering (Neovim-style) with Helix optimizations
pub const Display = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File,
    stdout_buf: [4096]u8, // Buffer for stdout writer
    terminal_rows: usize,
    terminal_cols: usize,
    viewport_top: usize, // First visible line number
    viewport_left: usize, // Horizontal scroll offset (applies to all lines, Neovim-style)

    // Grid-based rendering (legacy - will be replaced by compositor output)
    grid: ScreenGrid,
    output_buf: std.ArrayList(u8), // Batch output (Neovim + Helix pattern)

    // Multi-layer rendering system (Phase 2)
    layer_manager: LayerManager,
    compositor: Compositor,
    base_layer: *Layer, // Buffer content (z=0)
    gutter_layer: *Layer, // Line numbers, signs (z=100)
    cursor_layer: *Layer, // Cursor highlight (z=200)
    virtual_text_layer: *Layer, // Plugin overlays (z=300)
    selection_layer: *Layer, // Visual mode (z=400)
    yank_layer: *Layer, // Yank highlight (z=500)

    // Gutter system (line numbers, signs, etc.)
    gutter_manager: gutter.GutterManager,
    line_number_config: gutter.LineNumberConfig,
    sign_column_config: gutter.SignColumnConfig,

    // Cache for gutter width calculation (Neovim optimization)
    cached_line_count: usize, // Track line count for cache invalidation

    // Virtual text renderer (Neovim-style extmarks/virt_text)
    // Plugins can use this to overlay arbitrary text on the screen
    virtual_text: VirtualTextRenderer,

    // Cursor shape state (prevent redundant escape codes during rapid input)
    // Only send cursor shape codes when mode changes to prevent flickering
    last_cursor_shape: enum { block, bar, underline } = .block,

    // Cursor position state (prevent redundant position codes during rapid input)
    // Only send cursor position codes when cursor actually moves
    // CRITICAL: Initialize to sentinel values to force first cursor move on launch
    last_cursor_row: usize = CURSOR_POS_UNINITIALIZED,
    last_cursor_col: usize = CURSOR_POS_UNINITIALIZED,

    // Cursor visibility state (prevent redundant hide/show codes)
    // Track whether cursor is currently visible to avoid flickering
    // Sending hide/show on every frame (60 FPS) causes rapid toggling
    last_cursor_visible: bool = true, // Assume visible at startup

    // Terminal capabilities (detected at runtime)
    // Synchronized updates (DCS = 1 s ... DCS = 2 s) for flicker-free rendering
    // Supported by: iTerm2, Alacritty, WezTerm, tmux
    has_sync_mode: bool = true, // Assume true, gracefully degrade if not supported

    // Performance statistics (for debug protocol get_render_stats)
    render_stats: RenderStatistics = .{},

    // ============================================================================
    // O1: CROSS-FRAME ATTRIBUTE TRACKING (30-50% fewer escape codes)
    // ============================================================================
    // Track terminal attribute state ACROSS frames to avoid redundant SGR codes.
    // Unlike within-frame tracking (which resets per frame), this persists the
    // actual terminal state. The terminal remembers attributes until explicitly changed.
    //
    // Example: If frame N ends with fg=red, frame N+1 doesn't need to re-send red
    // unless the first cell needs a different color.
    //
    // CRITICAL: These are initialized to null/false to match terminal default state.
    // On first render, attributes will be sent. On subsequent frames, only changes.
    cross_frame_fg: ?highlights.Color = null,
    cross_frame_bg: ?highlights.Color = null,
    cross_frame_bold: bool = false,
    cross_frame_italic: bool = false,
    cross_frame_underline: bool = false,

    // O3: PRE-ALLOCATED OUTPUT BUFFER (eliminates per-frame allocations)
    // Instead of allocating a new ArrayList each frame, reuse this buffer.
    // Capacity grows as needed but never shrinks (steady-state = zero allocations)
    render_output_buf: std.ArrayList(u8) = .empty,

    // O4: SCROLL REGION STATE (for terminal scroll region integration)
    // Track previous viewport to detect scroll operations
    last_viewport_top: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Display {
        const grid = try ScreenGrid.init(allocator, 80, 24);
        const gutter_mgr = gutter.GutterManager.init(allocator);

        // Create layer manager and layers (Phase 2)
        var layer_manager = LayerManager.init(allocator);
        errdefer layer_manager.deinit();

        // Create layers with default terminal size (24x80)
        const base = try layer_manager.createLayer(ZIndex.BASE, 24, 80, "buffer");
        const gutter_layer = try layer_manager.createLayer(ZIndex.GUTTER, 24, 80, "gutter");
        const cursor = try layer_manager.createLayer(ZIndex.CURSOR, 24, 80, "cursor");
        const virtual_text = try layer_manager.createLayer(ZIndex.VIRTUAL_TEXT, 24, 80, "virtual_text");
        const selection = try layer_manager.createLayer(ZIndex.SELECTION, 24, 80, "selection");
        const yank = try layer_manager.createLayer(ZIndex.SEARCH, 24, 80, "yank"); // Reuse SEARCH z-index

        // PHASE 6: Enable caching for static layers (huge performance win)
        // TEMPORARY FIX: Disable gutter caching due to override bug
        // gutter_layer.setCacheable(true); // Gutter rarely changes
        virtual_text.setCacheable(true); // Plugin-managed

        // Create compositor
        var compositor = try Compositor.init(allocator, 24, 80);
        errdefer compositor.deinit();

        // PERFORMANCE: Initialize displayColumnToByte cache for 15× speedup
        try char_width.initCache(allocator);

        return .{
            .allocator = allocator,
            .stdout = std.fs.File.stdout(),
            .stdout_buf = undefined, // Will be initialized on first use
            .terminal_rows = 24, // Default, will be updated by getTerminalSize
            .terminal_cols = 80,
            .viewport_top = 0,
            .viewport_left = 0,
            .grid = grid,
            .output_buf = .empty,
            .layer_manager = layer_manager,
            .compositor = compositor,
            .base_layer = base,
            .gutter_layer = gutter_layer,
            .cursor_layer = cursor,
            .virtual_text_layer = virtual_text,
            .selection_layer = selection,
            .yank_layer = yank,
            .gutter_manager = gutter_mgr,
            .line_number_config = .{}, // Default: no line numbers
            .sign_column_config = .{}, // Default: no sign column
            .cached_line_count = 0,
            .virtual_text = VirtualTextRenderer.init(allocator),
        };
    }

    pub fn deinit(self: *Display) void {
        self.grid.deinit();
        self.output_buf.deinit(self.allocator);
        self.gutter_manager.deinit();
        self.virtual_text.deinit();

        // Cleanup layer system (Phase 2)
        self.compositor.deinit();
        self.layer_manager.deinit();

        // O3: Free pre-allocated render output buffer
        self.render_output_buf.deinit(self.allocator);

        // PERFORMANCE: Cleanup displayColumnToByte cache
        char_width.deinitCache();
    }

    // ============================================================================
    // Terminal Control Functions (delegated to terminal_control.zig)
    // ============================================================================

    /// Enter raw terminal mode (disable line buffering, echo)
    pub fn enterRawMode(self: *Display) !void {
        return terminal_control.enterRawMode(self);
    }

    /// Exit raw terminal mode (restore normal terminal)
    pub fn exitRawMode(self: *Display) void {
        terminal_control.exitRawMode(self);
    }

    /// Clear entire screen
    /// O1 FIX: Reset cross-frame attribute state after clear (terminal state unknown)
    pub fn clearScreen(self: *Display) !void {
        try terminal_control.clearScreen(self);
        // Terminal is now in default state - reset our tracking to match
        self.resetAttributeState();
    }

    /// Move cursor to position (0-indexed)
    pub fn moveCursor(self: *Display, row: usize, col: usize) !void {
        return terminal_control.moveCursor(self, row, col);
    }

    /// Hide cursor
    /// OPTIMIZATION: Only send hide code if cursor is currently visible
    /// This prevents redundant hide codes from causing flickering during rapid rendering
    pub fn hideCursor(self: *Display) !void {
        if (self.last_cursor_visible) {
            try terminal_control.hideCursor(self);
            self.last_cursor_visible = false;
            self.render_stats.cursor_hide_codes += 1; // Track for performance debugging
        }
    }

    /// Show cursor
    /// OPTIMIZATION: Only send show code if cursor is currently hidden
    /// This prevents redundant show codes from causing flickering during rapid rendering
    pub fn showCursor(self: *Display) !void {
        if (!self.last_cursor_visible) {
            try terminal_control.showCursor(self);
            self.last_cursor_visible = true;
            self.render_stats.cursor_show_codes += 1; // Track for performance debugging
        }
    }

    /// Set cursor to block shape (normal mode)
    pub fn setCursorBlock(self: *Display) !void {
        return terminal_control.setCursorBlock(self);
    }

    /// Set cursor to bar/vertical line shape (insert mode)
    pub fn setCursorBar(self: *Display) !void {
        return terminal_control.setCursorBar(self);
    }

    /// Set cursor to underline shape (replace mode, if needed later)
    pub fn setCursorUnderline(self: *Display) !void {
        return terminal_control.setCursorUnderline(self);
    }

    /// Set cursor color using OSC 12 escape sequence
    pub fn setCursorColor(self: *Display, color: highlights.Color) !void {
        return terminal_control.setCursorColor(self, color);
    }

    /// Reset cursor color to terminal default
    pub fn resetCursorColor(self: *Display) !void {
        return terminal_control.resetCursorColor(self);
    }

    /// Begin synchronized update (prevents terminal flickering)
    pub fn beginSynchronizedUpdate(self: *Display) !void {
        try terminal_control.beginSynchronizedUpdate(self);
        if (self.has_sync_mode) {
            self.render_stats.sync_update_begin_codes += 1;
        }
    }

    /// End synchronized update (flush all batched output atomically)
    pub fn endSynchronizedUpdate(self: *Display) !void {
        try terminal_control.endSynchronizedUpdate(self);
        if (self.has_sync_mode) {
            self.render_stats.sync_update_end_codes += 1;
        }
    }

    /// Set scroll region for fast scrolling (0-indexed)
    /// NOTE: Infrastructure ready, integration into render pipeline pending Phase 6
    pub fn setScrollRegion(self: *Display, top: usize, bottom: usize) !void {
        return terminal_control.setScrollRegion(self, top, bottom);
    }

    /// Reset scroll region to full screen
    /// NOTE: Infrastructure ready, integration into render pipeline pending Phase 6
    pub fn resetScrollRegion(self: *Display) !void {
        return terminal_control.resetScrollRegion(self);
    }

    /// Scroll content up by n lines (for scrolling down in file)
    /// NOTE: Infrastructure ready, integration into render pipeline pending Phase 6
    pub fn scrollUp(self: *Display, lines: usize) !void {
        return terminal_control.scrollUp(self, lines);
    }

    /// Scroll content down by n lines (for scrolling up in file)
    /// NOTE: Infrastructure ready, integration into render pipeline pending Phase 6
    pub fn scrollDown(self: *Display, lines: usize) !void {
        return terminal_control.scrollDown(self, lines);
    }

    /// Configure line number display
    pub fn setLineNumbers(self: *Display, enabled: bool) !void {
        self.line_number_config.number = enabled;
        try self.updateGutterColumns();
    }

    /// Configure relative line number display
    pub fn setRelativeLineNumbers(self: *Display, enabled: bool) !void {
        self.line_number_config.relative_number = enabled;
        try self.updateGutterColumns();
    }

    /// Configure sign column display
    pub fn setSignColumn(self: *Display, mode_str: []const u8) !void {
        self.sign_column_config.mode = gutter.SignColumnConfig.parseMode(mode_str);
        try self.updateGutterColumns();
    }

    /// Update gutter columns based on current configuration
    /// This implements the hybrid Neovim+Helix approach:
    /// - Register line number renderer based on mode (absolute/relative/hybrid)
    /// - Cache width calculation with invalidation on line count change
    fn updateGutterColumns(self: *Display) !void {

        // Sign column comes FIRST (before line numbers) in Neovim
        const sign_mode = self.sign_column_config.mode;
        self.gutter_manager.setColumnEnabled("signs", false);

        if (sign_mode == .yes or sign_mode == .auto) {
            // For now, always show if mode is "yes" (auto will check for actual signs later)
            if (sign_mode == .yes) {
                if (self.gutter_manager.getColumn("signs")) |col| {
                    col.enabled = true;
                } else {
                    try self.gutter_manager.registerColumn("signs", gutter.renderSignColumn);
                    // Set width to 2 for sign column
                    if (self.gutter_manager.getColumn("signs")) |col| {
                        col.cached_width = 2;
                    }
                }
            }
        }

        // Line numbers come SECOND (after signs)
        const line_mode = self.line_number_config.getMode();

        if (line_mode != .none) {
            // Determine which renderer to use
            const renderer: gutter.GutterRenderer = switch (line_mode) {
                .absolute => gutter.renderAbsoluteLineNumber,
                .relative => gutter.renderRelativeLineNumber,
                .hybrid => gutter.renderHybridLineNumber,
                .none => unreachable,
            };

            // Check if line number column already exists
            if (self.gutter_manager.getColumn("line_numbers")) |col| {
                col.renderer = renderer;
                col.enabled = true; // Ensure it's enabled
            } else {
                // Register new line number column
                try self.gutter_manager.registerColumn("line_numbers", renderer);

                // CRITICAL FIX: Set initial width immediately after registration
                // Use a reasonable default since cached_line_count is 0 at startup
                // (updateGutterCache() hasn't run yet). Will be updated on first render.
                if (self.gutter_manager.getColumn("line_numbers")) |col| {
                    const initial_width = if (self.cached_line_count > 0)
                        gutter.calculateLineNumberWidth(self.cached_line_count)
                    else
                        2; // Default: handles files up to 99 lines, updated on first render
                    col.cached_width = initial_width;
                    col.cache_key = self.cached_line_count;
                    col.enabled = true; // Ensure it's enabled
                }
            }
        } else {
            // Only disable if line_mode is .none
            self.gutter_manager.setColumnEnabled("line_numbers", false);
        }

        // CRITICAL: Mark gutter layer as dirty to trigger re-render
        // This ensures changes to line numbers/sign column are immediately visible
        self.gutter_layer.markDirty();
    }

    /// Update gutter width cache if line count changed (Neovim optimization)
    fn updateGutterCache(self: *Display, buffer: *const Buffer) void {
        const line_count = buffer.lineCount();

        // Invalidate cache if line count changed significantly
        if (line_count != self.cached_line_count) {
            self.cached_line_count = line_count;

            // Recalculate line number width if enabled
            if (self.line_number_config.getMode() != .none) {
                if (self.gutter_manager.getColumn("line_numbers")) |col| {
                    const old_width = col.cached_width;
                    const new_width = gutter.calculateLineNumberWidth(line_count);
                    col.cached_width = new_width;
                    col.cache_key = line_count;

                    // CRITICAL: Mark gutter layer dirty if width changed
                    // Without this, gutter doesn't re-render when width changes,
                    // causing buffer content to override gutter area
                    if (old_width != new_width) {
                        self.gutter_layer.markDirty();
                    }
                }
            }
        }
    }

    /// Get terminal size (uses TIOCGWINSZ ioctl) and resize grid if needed
    pub fn getTerminalSize(self: *Display) !void {
        const stdout = std.fs.File.stdout();
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            // Check if stdout is a TTY
            if (std.posix.isatty(stdout.handle)) {
                var winsize: std.posix.winsize = undefined;
                const TIOCGWINSZ = if (builtin.os.tag == .macos) 0x40087468 else std.posix.T.IOCGWINSZ;

                const result = std.posix.system.ioctl(stdout.handle, TIOCGWINSZ, @intFromPtr(&winsize));

                if (result == 0 and winsize.row > 0 and winsize.col > 0) {
                    const new_rows = winsize.row;
                    const new_cols = winsize.col;

                    // Resize grid if terminal size changed
                    if (new_rows != self.terminal_rows or new_cols != self.terminal_cols) {
                        try self.grid.resize(new_cols, new_rows);

                        // Resize all layers (Phase 2)
                        try self.layer_manager.resizeAll(new_rows, new_cols);
                        try self.compositor.resize(new_rows, new_cols);

                        self.terminal_rows = new_rows;
                        self.terminal_cols = new_cols;

                        // O1 FIX: Reset attribute state after resize
                        // Terminal state may be unknown after resize event
                        self.resetAttributeState();

                        // O4: Reset scroll tracking after resize
                        self.last_viewport_top = 0;
                    }
                }
                // If ioctl fails or returns invalid size, keep defaults (24x80)
            }
            // If not a TTY, keep defaults
        }
    }

    /// Render buffer content to screen using grid-based rendering
    /// This is the main rendering function following Neovim's architecture
    /// Generic over Editor/EditorContext types (both have same fields)
    ///
    /// laststatus: Controls status line visibility (Vim/Neovim compatible)
    ///   0 = never show status line
    ///   1 = only if there are at least two windows (not yet implemented, behaves like 2)
    ///   2 = always show status line (default)
    ///   3 = always and ONLY the last window (global statusline, behaves like 2)
    pub fn render(
        self: *Display,
        editor: anytype,
        status: []const u8,
        cursorline_enabled: bool,
        visual_state: *const VisualState,
        yank_highlight: *const YankHighlight,
        list_enabled: bool,
        listchars: *const ListChars,
        laststatus: u8,
    ) !void {
        // Get buffer from editor (handles both Editor and EditorContext types)
        const T = @TypeOf(editor);
        const buffer = if (T == *Editor)
            editor.getCurrentBuffer() orelse return error.NoCurrentBuffer
        else if (T == *EditorContext)
            editor.buffer()
        else
            &editor.buffer; // Duck-typed fallback for MockEditor in benchmarks

        // Update terminal size (handles resize and ensures correct dimensions)
        try self.getTerminalSize();

        // Update gutter cache (Neovim optimization: invalidate on line count change)
        self.updateGutterCache(buffer);

        // Adjust viewport to keep cursor visible
        self.adjustViewport(buffer);

        // Get gutter width for horizontal positioning
        const gutter_width = self.gutter_manager.getTotalWidth();

        // Adjust horizontal scroll for cursor line (account for gutter)
        const text_cols = if (self.terminal_cols > gutter_width)
            self.terminal_cols - gutter_width
        else
            self.terminal_cols;

        // Convert cursor byte position to display column (account for wide chars like emoji)
        // This is needed for both horizontal scroll and cursor positioning
        // Use the padding-aware version to account for visual padding in grid
        const cursor_display_col = if (buffer.cursor.row < buffer.lineCount()) blk: {
            const line = buffer.getLine(buffer.cursor.row) orelse break :blk buffer.cursor.col;
            defer buffer.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;
            break :blk char_width.byteToDisplayColumn(line_without_newline, buffer.cursor.col);
        } else buffer.cursor.col;

        if (cursor_display_col >= self.viewport_left + text_cols) {
            self.viewport_left = cursor_display_col - text_cols + 1;
        } else if (cursor_display_col < self.viewport_left) {
            self.viewport_left = cursor_display_col;
        }

        // PERFORMANCE: Clear displayColumnToByte cache at start of each frame
        // Cache is only valid for one frame (same line may have different content next frame)
        char_width.clearCache();

        // STATISTICS: Record render start time
        self.render_stats.recordRenderStart();

        // OPTIMIZATION: Begin synchronized update to prevent flickering
        // All terminal output will be batched until endSynchronizedUpdate()
        // This ensures atomic screen updates with zero tearing
        try self.beginSynchronizedUpdate();

        // CRITICAL: Ensure synchronized update is ALWAYS ended, even on error
        // If we return early due to error, terminal state becomes broken (cursor flickering!)
        // Use errdefer to cleanup on error, and explicit end at function exit
        errdefer {
            self.endSynchronizedUpdate() catch {};
            self.flush() catch {};
        }

        // CRITICAL FIX: Hide cursor during rendering to prevent flickering
        // Without this, user sees cursor at "last cell" position before final cursor positioning
        // This happens because output_renderer.renderUpdates() moves cursor to each cell as it renders
        try self.hideCursor();

        // O4: Apply terminal scroll optimization if viewport changed
        // This uses native terminal scroll commands (CSI S/T) which is 10-100x faster
        // than re-rendering all lines. The terminal shifts content, we only fill new lines.
        _ = try self.applyTerminalScroll();

        // PHASE 2.5: Multi-layer rendering pipeline (ACTIVATED!)
        // STEP 1: Update all layers from buffer state
        // Get highlight_registry from editor (handles both Editor and EditorContext types)
        const highlight_registry = if (T == *Editor)
            &editor.highlight_registry
        else if (T == *EditorContext)
            editor.highlight_registry()
        else
            &editor.highlight_registry; // Duck-typed fallback for MockEditor in benchmarks
        try layer_renderer.updateLayers(self, editor, status, highlight_registry, visual_state, yank_highlight, cursorline_enabled, list_enabled, listchars);

        // STEP 1.5: Apply virtual text overlay (Neovim-style extmarks)
        // Plugins render arbitrary text via virtual_text_layer
        self.virtual_text.applyToGrid(&self.virtual_text_layer.grid);

        // STEP 2: Composite all layers using Porter-Duff blending
        // PHASE 6 NOTE: Using full composition for now
        // Incremental composition requires cached composition buffers (not yet implemented)
        try self.compositor.composite(self.layer_manager.layers.items);

        // STEP 3: Get composited output and compute diff
        const output = self.compositor.getOutput();
        const updates = try output.diff(self.allocator);
        defer self.allocator.free(updates);

        // STEP 4: Render only changed cells (cursor invisible, so no flickering)
        try output_renderer.renderUpdates(self, updates);

        // STEP 4.5: Render status line on the last row (terminal_rows - 1)
        // Status line is outside the layer system because it doesn't need blending
        // laststatus: 0=never, 1=only if multiple windows, 2=always, 3=global statusline
        // NOTE: 1 and 3 behave like 2 until window splits are implemented
        if (laststatus > 0) {
            try self.renderStatusLine(status, highlight_registry);
        }

        // STEP 5: Swap buffers (current becomes previous for next frame)
        output.swapBuffers();

        // STEP 6: Position cursor at buffer cursor location (add gutter offset)
        const cursor_row = buffer.cursor.row;
        const cursor_col_display = cursor_display_col;

        const screen_row = if (cursor_row >= self.viewport_top)
            cursor_row - self.viewport_top
        else
            0;

        const screen_col_text = if (cursor_col_display >= self.viewport_left)
            cursor_col_display - self.viewport_left
        else
            0;

        const screen_col = gutter_width + screen_col_text;
        const clamped_col = @min(screen_col, self.terminal_cols - 1);

        // CRITICAL FIX: When renderUpdates() renders cells, it moves the terminal cursor
        // around the screen. We must ALWAYS reposition the cursor afterward.
        // The optimization to skip cursor moves is ONLY valid when no cells were rendered
        // (i.e., updates.len == 0), because only then is the terminal cursor still at
        // last_cursor_row/col.
        //
        // BUG SCENARIO (before fix):
        //   1. Cursor at line 22, col 2, screen_row=22
        //   2. Press 'j' → cursor moves to line 23, viewport scrolls
        //   3. New screen_row = 23 - 1 = 22 (same as before!)
        //   4. last_cursor_row == screen_row → skip cursor move
        //   5. BUT terminal cursor is at last rendered cell (end of line), not col 2!
        //   6. User sees cursor at wrong position
        const cursor_moved_by_rendering = updates.len > 0;
        if (cursor_moved_by_rendering or self.last_cursor_row != screen_row or self.last_cursor_col != clamped_col) {
            try self.moveCursor(screen_row, clamped_col);
            self.last_cursor_row = screen_row;
            self.last_cursor_col = clamped_col;
            self.render_stats.cursor_position_codes += 1; // Track for performance debugging
        }

        // Cursor is now at the correct final position
        // Synchronized update will flush everything atomically

        // NOTE: Synchronized update is NOT ended here!
        // backend.render() will set cursor shape AFTER this returns,
        // so we let backend.render() call endSynchronizedUpdate() after cursor shape is set

        // STATISTICS: Record render end time and compositor stats
        self.render_stats.recordRenderEnd();
        self.render_stats.layers_composited_last = self.layer_manager.layers.items.len;
        self.render_stats.cells_updated_last = updates.len;
        // TODO: Get blended cell count from compositor when stats are available
        // self.render_stats.cells_blended_last = compositor_stats.cells_blended;
    }

    /// Headless render: Update compositor state WITHOUT writing to stdout
    /// This is used by the debug protocol to update layer state for inspection
    /// while keeping stdout clean for JSON responses
    /// Generic over Editor/EditorContext types (both have same fields)
    pub fn renderHeadless(
        self: *Display,
        editor: anytype,
        status: []const u8,
        cursorline_enabled: bool,
        visual_state: *const VisualState,
        yank_highlight: *const YankHighlight,
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

        // Update gutter cache (Neovim optimization: invalidate on line count change)
        self.updateGutterCache(buffer);

        // Adjust viewport to keep cursor visible
        self.adjustViewport(buffer);

        // Get gutter width for horizontal positioning
        const gutter_width = self.gutter_manager.getTotalWidth();

        // Adjust horizontal scroll for cursor line (account for gutter)
        const text_cols = if (self.terminal_cols > gutter_width)
            self.terminal_cols - gutter_width
        else
            self.terminal_cols;

        // Convert cursor byte position to display column (account for wide chars like emoji)
        const cursor_display_col = if (buffer.cursor.row < buffer.lineCount()) blk: {
            const line = buffer.getLine(buffer.cursor.row) orelse break :blk buffer.cursor.col;
            defer buffer.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;
            break :blk char_width.byteToDisplayColumn(line_without_newline, buffer.cursor.col);
        } else buffer.cursor.col;

        if (cursor_display_col >= self.viewport_left + text_cols) {
            self.viewport_left = cursor_display_col - text_cols + 1;
        } else if (cursor_display_col < self.viewport_left) {
            self.viewport_left = cursor_display_col;
        }

        // PERFORMANCE: Clear displayColumnToByte cache at start of each frame
        char_width.clearCache();

        // STEP 1: Update all layers from buffer state
        // Get highlight_registry from editor (handles both Editor and EditorContext types)
        const highlight_registry = if (T == *Editor)
            &editor.highlight_registry
        else if (T == *EditorContext)
            editor.highlight_registry()
        else
            &editor.highlight_registry; // Duck-typed fallback for MockEditor in benchmarks
        try layer_renderer.updateLayers(self, editor, status, highlight_registry, visual_state, yank_highlight, cursorline_enabled, list_enabled, listchars);

        // STEP 1.5: Apply virtual text overlay (Neovim-style extmarks)
        self.virtual_text.applyToGrid(&self.virtual_text_layer.grid);

        // STEP 2: Composite all layers using Porter-Duff blending
        try self.compositor.composite(self.layer_manager.layers.items);

        // STEP 3: Compute diff but DON'T render to stdout
        // This updates the compositor output grid for inspection but doesn't write ANSI codes
        const output = self.compositor.getOutput();
        const updates = try output.diff(self.allocator);
        defer self.allocator.free(updates);

        // STEP 4: Swap buffers (current becomes previous for next frame)
        output.swapBuffers();

        // Note: We DON'T call renderUpdates() or moveCursor() here
        // This keeps stdout clean for JSON responses in headless mode
    }

    /// Adjust viewport to keep cursor visible
    fn adjustViewport(self: *Display, buffer: *const Buffer) void {
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

        // Scroll down if cursor is below viewport
        if (buffer.cursor.row >= self.viewport_top + text_rows) {
            // CRITICAL: Use saturating arithmetic to prevent underflow
            // If cursor.row < text_rows, non-saturating would wrap to MAX_USIZE
            self.viewport_top = buffer.cursor.row -| text_rows +| 1;
        }

        // Scroll up if cursor is above viewport
        if (buffer.cursor.row < self.viewport_top) {
            self.viewport_top = buffer.cursor.row;
        }
    }

    /// LIGHTWEIGHT: Render cursor position ONLY (no compositor, no diff, no layers)
    /// This is used when only the cursor moved (buffer content unchanged)
    /// Performance: 1 cursor position code instead of 457!
    /// Generic over Editor/EditorContext types (both have same fields)
    pub fn renderCursorOnly(self: *Display, editor: anytype) !void {
        // Get buffer from editor (handles both Editor and EditorContext types)
        const T = @TypeOf(editor);
        const buffer = if (T == *Editor)
            editor.getCurrentBuffer() orelse return error.NoCurrentBuffer
        else if (T == *EditorContext)
            editor.buffer()
        else
            &editor.buffer; // Duck-typed fallback for MockEditor in benchmarks

        // Adjust viewport to keep cursor visible
        self.adjustViewport(buffer);

        // Get gutter width for horizontal positioning
        const gutter_width = self.gutter_manager.getTotalWidth();

        // Calculate text area width (account for gutter)
        const text_cols = if (self.terminal_cols > gutter_width)
            self.terminal_cols - gutter_width
        else
            self.terminal_cols;

        // Convert cursor byte position to display column (account for wide chars)
        const cursor_display_col = if (buffer.cursor.row < buffer.lineCount()) blk: {
            const line = buffer.getLine(buffer.cursor.row) orelse break :blk buffer.cursor.col;
            defer buffer.allocator.free(line);
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;
            break :blk char_width.byteToDisplayColumn(line_without_newline, buffer.cursor.col);
        } else buffer.cursor.col;

        // Adjust horizontal scroll if needed
        if (cursor_display_col >= self.viewport_left + text_cols) {
            self.viewport_left = cursor_display_col - text_cols + 1;
        } else if (cursor_display_col < self.viewport_left) {
            self.viewport_left = cursor_display_col;
        }

        // Calculate screen position (relative to viewport)
        const screen_row = if (buffer.cursor.row >= self.viewport_top)
            buffer.cursor.row - self.viewport_top
        else
            0;

        const screen_col_text = if (cursor_display_col >= self.viewport_left)
            cursor_display_col - self.viewport_left
        else
            0;

        const screen_col = gutter_width + screen_col_text;
        const clamped_col = @min(screen_col, self.terminal_cols - 1);

        // Begin synchronized update (atomic cursor move)
        try self.beginSynchronizedUpdate();

        // CRITICAL: Ensure synchronized update is ALWAYS ended
        errdefer {
            self.endSynchronizedUpdate() catch {};
            self.flush() catch {};
        }

        // ONLY move cursor if position changed (prevent redundant codes)
        if (self.last_cursor_row != screen_row or self.last_cursor_col != clamped_col) {
            try self.moveCursor(screen_row, clamped_col);
            self.last_cursor_row = screen_row;
            self.last_cursor_col = clamped_col;
            self.render_stats.cursor_position_codes += 1;
        }

        // End synchronized update and flush
        try self.endSynchronizedUpdate();
        try self.flush();
    }

    /// VISUAL MODE OPTIMIZATION: Render cursor + selection layer ONLY
    /// Used when cursor moves in Visual mode (selection changes but buffer doesn't)
    /// Performance: Skips rebuilding base/gutter layers, only updates selection
    pub fn renderVisualCursorMovement(self: *Display, editor: *Editor, visual_state: *const VisualState) !void {
        const buffer = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;

        // Adjust viewport to keep cursor visible
        self.adjustViewport(buffer);

        // Get gutter width for horizontal positioning
        const gutter_width = self.gutter_manager.getTotalWidth();

        // Calculate text area width (account for gutter)
        const text_cols = if (self.terminal_cols > gutter_width)
            self.terminal_cols - gutter_width
        else
            self.terminal_cols;

        // Convert cursor byte position to display column (account for wide chars)
        const cursor_display_col = if (buffer.cursor.row < buffer.lineCount()) blk: {
            const line = buffer.getLine(buffer.cursor.row) orelse break :blk buffer.cursor.col;
            defer buffer.allocator.free(line);
            const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;
            break :blk char_width.byteToDisplayColumn(line_without_newline, buffer.cursor.col);
        } else buffer.cursor.col;

        // Adjust horizontal scroll if needed
        if (cursor_display_col >= self.viewport_left + text_cols) {
            self.viewport_left = cursor_display_col - text_cols + 1;
        } else if (cursor_display_col < self.viewport_left) {
            self.viewport_left = cursor_display_col;
        }

        // Calculate screen position (relative to viewport)
        const screen_row = if (buffer.cursor.row >= self.viewport_top)
            buffer.cursor.row - self.viewport_top
        else
            0;

        const screen_col_text = if (cursor_display_col >= self.viewport_left)
            cursor_display_col - self.viewport_left
        else
            0;

        const screen_col = gutter_width + screen_col_text;
        const clamped_col = @min(screen_col, self.terminal_cols - 1);

        // Begin synchronized update (atomic rendering)
        try self.beginSynchronizedUpdate();

        // CRITICAL: Ensure synchronized update is ALWAYS ended
        errdefer {
            self.endSynchronizedUpdate() catch {};
            self.flush() catch {};
        }

        // STEP 1: Hide cursor to prevent flickering during updates
        // Without this, user sees cursor jump to intermediate positions as cells are rendered
        try self.hideCursor();

        // STEP 2: Update ONLY selection layer (skip base/gutter - they haven't changed)
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;
        try layer_renderer.updateSelectionLayer(self, buffer, visual_state, &editor.highlight_registry, text_rows);

        // STEP 3: Composite layers (selection layer marked dirty, others cached)
        try self.compositor.composite(self.layer_manager.layers.items);

        // STEP 4: Get composited output and compute diff
        const output = self.compositor.getOutput();
        const updates = try output.diff(self.allocator);
        defer self.allocator.free(updates);

        // STEP 5: Render only changed cells (cursor invisible, so no flickering)
        try output_renderer.renderUpdates(self, updates);

        // STEP 6: Swap buffers
        output.swapBuffers();

        // STEP 7: Move cursor to final position
        // CRITICAL FIX: When renderUpdates() renders cells, it moves the terminal cursor
        // around the screen. We must ALWAYS reposition the cursor afterward when there are updates.
        const cursor_moved_by_rendering = updates.len > 0;
        if (cursor_moved_by_rendering or self.last_cursor_row != screen_row or self.last_cursor_col != clamped_col) {
            try self.moveCursor(screen_row, clamped_col);
            self.last_cursor_row = screen_row;
            self.last_cursor_col = clamped_col;
            self.render_stats.cursor_position_codes += 1;
        }

        // STEP 8: Show cursor at final position (no flickering!)
        try self.showCursor();

        // End synchronized update and flush
        try self.endSynchronizedUpdate();
        try self.flush();
    }

    /// Flush output buffer
    pub fn flush(_: *Display) !void {
        const stdout = std.fs.File.stdout();
        try stdout.sync();
    }

    // ============================================================================
    // O4: TERMINAL SCROLL REGION OPTIMIZATION
    // ============================================================================
    // Detect viewport scrolling and use native terminal scroll commands (CSI S/T)
    // instead of re-rendering the entire screen. This is 10-100x faster for scrolling.
    //
    // When viewport scrolls by N lines:
    // 1. Set scroll region to text area (excluding status line)
    // 2. Use CSI S (scroll up) or CSI T (scroll down) to shift content
    // 3. Only render the newly revealed lines
    //
    // This leverages the O(1) scroll in ScreenGrid - terminal handles the shift,
    // we only fill in the new content.

    /// Apply terminal scroll optimization if viewport changed
    /// Returns true if scroll optimization was applied, false if full render needed
    ///
    /// KEY INSIGHT: After terminal scroll, we scroll the PREVIOUS buffer to match
    /// what the terminal now shows. The compositor fills CURRENT normally.
    /// diff() then only sees the newly revealed rows as different.
    ///
    /// Example (scroll down 1 line):
    ///   Terminal scroll: shifts up by 1 (lines[1-23] visible, bottom blank)
    ///   Scroll previous: now represents lines[1-23] + blank (matches terminal)
    ///   Compositor: fills current with lines[1-24]
    ///   diff(): rows 0-22 unchanged, only row 23 differs → 1 row update instead of 24!
    pub fn applyTerminalScroll(self: *Display) !bool {
        // Check if viewport scrolled
        if (self.viewport_top == self.last_viewport_top) {
            return false; // No scroll, do full render
        }

        // CRITICAL: Disable scroll optimization when gutter is visible
        //
        // Terminal scroll (CSI S/T) shifts the ENTIRE screen including gutter columns.
        // There's no way to scroll just the text area while keeping gutter static,
        // unless the terminal supports left/right margins (DECLRMM mode) - most don't.
        //
        // This is how Neovim handles it: only use terminal scroll for full-width
        // operations, or when terminal has left/right margin support.
        // Helix doesn't use terminal scroll at all.
        //
        // With diff-based rendering, scrolling is still fast enough (we only
        // re-render changed cells), and this eliminates all flickering.
        const gutter_width = self.gutter_manager.getTotalWidth();
        if (gutter_width > 0) {
            self.last_viewport_top = self.viewport_top;
            return false; // Use diff-based rendering instead
        }

        const scroll_delta = @as(isize, @intCast(self.viewport_top)) - @as(isize, @intCast(self.last_viewport_top));
        const abs_delta = @abs(scroll_delta);

        // Only use terminal scroll for small deltas (1-10 lines)
        // Larger scrolls are often faster to re-render entirely
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;
        if (abs_delta == 0 or abs_delta > 10 or abs_delta >= text_rows) {
            self.last_viewport_top = self.viewport_top;
            return false; // Too large, do full render
        }

        // Set scroll region (text area only, exclude status line)
        try self.setScrollRegion(0, text_rows - 1);

        // Apply terminal scroll command
        if (scroll_delta > 0) {
            // Viewport moved DOWN (content scrolls UP)
            try terminal_control.scrollUp(self, abs_delta);
        } else {
            // Viewport moved UP (content scrolls DOWN)
            try terminal_control.scrollDown(self, abs_delta);
        }

        // Reset scroll region
        try self.resetScrollRegion();

        // CRITICAL: Scroll the PREVIOUS buffer to match what terminal now shows
        // Do NOT scroll current - compositor will fill it fresh
        // This way, diff() only detects newly revealed content as changed
        const output = self.compositor.getOutput();
        output.scrollPrevious(@intCast(scroll_delta));

        // Update tracking
        self.last_viewport_top = self.viewport_top;

        return true; // Scroll optimization applied
    }

    /// Reset cross-frame attribute state (called when terminal state is unknown)
    /// This forces re-sending all attributes on next render
    pub fn resetAttributeState(self: *Display) void {
        self.cross_frame_fg = null;
        self.cross_frame_bg = null;
        self.cross_frame_bold = false;
        self.cross_frame_italic = false;
        self.cross_frame_underline = false;
    }

    /// Render status line on the last row of the terminal
    /// Status line shows current mode (NORMAL, INSERT, VISUAL, :command)
    /// Uses StatusLine highlight group for styling (Neovim-compatible)
    fn renderStatusLine(self: *Display, status: []const u8, highlight_registry: *const highlight_api.HighlightRegistry) !void {
        if (self.terminal_rows == 0) return;

        const status_row = self.terminal_rows - 1;

        // Move cursor to status line row
        try self.moveCursor(status_row, 0);

        // Get StatusLine style from registry (returns Style with scope fallback)
        const style = highlight_registry.get("StatusLine");

        // Apply StatusLine highlight if fg or bg is set, otherwise fallback to inverse video
        var buf: [32]u8 = undefined;
        const has_custom_style = style.fg != null or style.bg != null;

        if (has_custom_style) {
            // Apply custom StatusLine highlight
            if (style.fg) |fg| {
                const rgb = fg.toRgb();
                const fg_code = try std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b });
                try self.stdout.writeAll(fg_code);
            }
            if (style.bg) |bg| {
                const rgb = bg.toRgb();
                const bg_code = try std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b });
                try self.stdout.writeAll(bg_code);
            }
            if (style.modifiers.bold) {
                try self.stdout.writeAll("\x1b[1m");
            }
            if (style.modifiers.italic) {
                try self.stdout.writeAll("\x1b[3m");
            }
            if (style.modifiers.underline) {
                try self.stdout.writeAll("\x1b[4m");
            }
        } else {
            // Fallback: use inverse video (common status line style)
            try self.stdout.writeAll("\x1b[7m");
        }

        // Write status text
        var col: usize = 0;
        for (status) |char| {
            if (col >= self.terminal_cols) break;
            try self.stdout.writeAll(&[_]u8{char});
            col += 1;
        }

        // Fill rest of line with spaces (background extends to end)
        while (col < self.terminal_cols) : (col += 1) {
            try self.stdout.writeAll(" ");
        }

        // Reset attributes
        try self.stdout.writeAll("\x1b[0m");

        // Reset cross-frame attribute tracking since we manually sent SGR codes
        self.resetAttributeState();
    }
};
