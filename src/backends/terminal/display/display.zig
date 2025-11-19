const std = @import("std");
const Buffer = @import("../../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../../editor/editor.zig").Editor;
const debug_log = @import("../../debug/log.zig");
const highlights = @import("../../../editor/config/highlights.zig");
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const Cell = @import("screen_grid.zig").Cell;
const Update = @import("screen_grid.zig").Update;
const VisualState = @import("../visual/visual.zig").VisualState;
const YankHighlight = @import("../visual/yank_highlight.zig").YankHighlight;
const Position = @import("../visual/visual.zig").Position;
const CursorPosition = @import("../../../editor/editor.zig").CursorPosition;
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
    pub fn clearScreen(self: *Display) !void {
        return terminal_control.clearScreen(self);
    }

    /// Move cursor to position (0-indexed)
    pub fn moveCursor(self: *Display, row: usize, col: usize) !void {
        return terminal_control.moveCursor(self, row, col);
    }

    /// Hide cursor
    pub fn hideCursor(self: *Display) !void {
        return terminal_control.hideCursor(self);
    }

    /// Show cursor
    pub fn showCursor(self: *Display) !void {
        return terminal_control.showCursor(self);
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
                    }
                }
                // If ioctl fails or returns invalid size, keep defaults (24x80)
            }
            // If not a TTY, keep defaults
        }
    }

    /// Render buffer content to screen using grid-based rendering
    /// This is the main rendering function following Neovim's architecture
    /// If cursor_override is provided and active, it will be used instead of buffer.cursor for cursor positioning
    /// Generic over Editor/EditorContext types (both have same fields)
    pub fn render(
        self: *Display,
        editor: anytype,
        status: []const u8,
        config: *const highlights.HighlightConfig,
        visual_state: *const VisualState,
        yank_highlight: *const YankHighlight,
        cursor_override: ?CursorPosition,
        list_enabled: bool,
        listchars: *const ListChars,
    ) !void {
        const buffer = &editor.buffer;

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

        // PHASE 2.5: Multi-layer rendering pipeline (ACTIVATED!)
        // STEP 1: Update all layers from buffer state
        try layer_renderer.updateLayers(self, editor, status, config, visual_state, yank_highlight, list_enabled, listchars);

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

        // STEP 4: Render only changed cells with optimizations
        try output_renderer.renderUpdates(self, updates);

        // STEP 5: Swap buffers (current becomes previous for next frame)
        output.swapBuffers();

        // Position cursor at buffer cursor location or override (add gutter offset)
        // Use cursor_override if provided (for animated cursor plugins)
        const cursor_row = if (cursor_override) |override| override.row else buffer.cursor.row;
        const cursor_col_display = if (cursor_override) |override|
            override.col
        else
            cursor_display_col;

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
        try self.moveCursor(screen_row, clamped_col);
    }

    /// Headless render: Update compositor state WITHOUT writing to stdout
    /// This is used by the debug protocol to update layer state for inspection
    /// while keeping stdout clean for JSON responses
    /// Generic over Editor/EditorContext types (both have same fields)
    pub fn renderHeadless(
        self: *Display,
        editor: anytype,
        status: []const u8,
        config: *const highlights.HighlightConfig,
        visual_state: *const VisualState,
        yank_highlight: *const YankHighlight,
        list_enabled: bool,
        listchars: *const ListChars,
    ) !void {
        const buffer = &editor.buffer;

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
        try layer_renderer.updateLayers(self, editor, status, config, visual_state, yank_highlight, list_enabled, listchars);

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

    /// Flush output buffer
    pub fn flush(_: *Display) !void {
        const stdout = std.fs.File.stdout();
        try stdout.sync();
    }

    /// Update cursor position only (lightweight, for animations)
    /// This bypasses the full render pipeline and just moves the cursor
    /// Used by animated cursor plugins to avoid expensive grid updates
    pub fn updateCursorOnly(self: *Display, row: usize, col: usize) !void {
        // Get gutter width
        const gutter_width = self.gutter_manager.getTotalWidth();

        // Calculate screen position
        const screen_row = if (row >= self.viewport_top)
            row - self.viewport_top
        else
            0;

        const screen_col_text = if (col >= self.viewport_left)
            col - self.viewport_left
        else
            0;

        const screen_col = gutter_width + screen_col_text;
        const clamped_col = @min(screen_col, self.terminal_cols - 1);

        // Just move cursor - no grid update, no diff
        try self.moveCursor(screen_row, clamped_col);
    }
};
