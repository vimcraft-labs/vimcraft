const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const debug_log = @import("../debug/log.zig");
const highlights = @import("../config/highlights.zig");
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const Cell = @import("screen_grid.zig").Cell;
const Update = @import("screen_grid.zig").Update;
const VisualState = @import("../visual/visual.zig").VisualState;
const YankHighlight = @import("../visual/yank_highlight.zig").YankHighlight;
const Position = @import("../visual/visual.zig").Position;
const CursorPosition = @import("../core/editor.zig").CursorPosition;
const char_width = @import("char_width.zig");
const gutter = @import("gutter.zig");
const VirtualTextRenderer = @import("virtual_text.zig").VirtualTextRenderer;

// Multi-layer rendering system (Phase 2)
const Layer = @import("layer.zig").Layer;
const LayerManager = @import("layer.zig").LayerManager;
const ZIndex = @import("layer.zig").ZIndex;
const Compositor = @import("compositor.zig").Compositor;

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
    viewport_left: usize, // Horizontal scroll offset for current line

    // Grid-based rendering (legacy - will be replaced by compositor output)
    grid: ScreenGrid,
    output_buf: std.ArrayList(u8), // Batch output (Neovim + Helix pattern)

    // Multi-layer rendering system (Phase 2)
    layer_manager: LayerManager,
    compositor: Compositor,
    base_layer: *Layer,          // Buffer content (z=0)
    gutter_layer: *Layer,        // Line numbers, signs (z=100)
    cursor_layer: *Layer,        // Cursor highlight (z=200)
    virtual_text_layer: *Layer,  // Plugin overlays (z=300)
    selection_layer: *Layer,     // Visual mode (z=400)
    yank_layer: *Layer,          // Yank highlight (z=500)

    // Gutter system (line numbers, signs, etc.)
    gutter_manager: gutter.GutterManager,
    line_number_config: gutter.LineNumberConfig,
    sign_column_config: gutter.SignColumnConfig,

    // Cache for gutter width calculation (Neovim optimization)
    cached_line_count: usize, // Track line count for cache invalidation

    // Virtual text renderer (Neovim-style extmarks/virt_text)
    // Plugins can use this to overlay arbitrary text on the screen
    virtual_text: VirtualTextRenderer,

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
        gutter_layer.setCacheable(true); // Gutter rarely changes
        virtual_text.setCacheable(true); // Plugin-managed

        // Create compositor
        var compositor = try Compositor.init(allocator, 24, 80);
        errdefer compositor.deinit();

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
    }

    /// Helper to get a buffered writer for stdout
    // Direct access to stdout for writing - simpler in Zig 0.15.2
    fn write(self: *Display, bytes: []const u8) !void {
        return self.stdout.writeAll(bytes);
    }

    fn print(self: *Display, comptime format: []const u8, args: anytype) !void {
        // Format to a temporary buffer, then write it
        const formatted = try std.fmt.bufPrint(&self.stdout_buf, format, args);
        try self.stdout.writeAll(formatted);
    }

    /// Enter raw terminal mode (disable line buffering, echo)
    pub fn enterRawMode(self: *Display) !void {
        const stdin = std.fs.File.stdin();
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux or builtin.os.tag == .macos)
        {
            // Only enter raw mode if stdin is a TTY
            if (!std.posix.isatty(stdin.handle)) {
                return error.NotATTY;
            }

            var termios = try std.posix.tcgetattr(stdin.handle);

            // Disable canonical mode and echo
            termios.lflag.ECHO = false;
            termios.lflag.ICANON = false;

            // Disable Ctrl-C and Ctrl-Z
            termios.lflag.ISIG = false;

            // Disable Ctrl-S and Ctrl-Q
            termios.iflag.IXON = false;

            // Disable CR-to-NL translation
            termios.iflag.ICRNL = false;

            // Set blocking read (waits for at least 1 character)
            // VMIN=1: Block until at least 1 byte available
            // VTIME=0: No timeout, pure blocking
            termios.cc[@intFromEnum(std.posix.V.MIN)] = 1;
            termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;

            try std.posix.tcsetattr(stdin.handle, .FLUSH, termios);

            // Enter alternate screen buffer
            // This allows text selection in the normal terminal
            try self.write("\x1b[?1049h");

            // Enable mouse tracking
            // SGR mode (1006): Better coordinate support (handles terminals larger than 223 cols)
            // Button tracking (1000): Report button press/release events
            try self.write("\x1b[?1006h"); // Enable SGR mouse mode
            try self.write("\x1b[?1000h"); // Enable mouse button tracking
        }
    }

    /// Exit raw terminal mode (restore normal terminal)
    pub fn exitRawMode(self: *Display) void {
        const stdin = std.fs.File.stdin();
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux or builtin.os.tag == .macos)
        {
            // Disable mouse tracking
            self.write("\x1b[?1000l") catch {}; // Disable mouse button tracking
            self.write("\x1b[?1006l") catch {}; // Disable SGR mouse mode

            // Exit alternate screen buffer (restores original terminal content)
            self.write("\x1b[?1049l") catch {};

            var termios = std.posix.tcgetattr(stdin.handle) catch return;

            // Re-enable canonical mode and echo
            termios.lflag.ECHO = true;
            termios.lflag.ICANON = true;
            termios.lflag.ISIG = true;
            termios.iflag.IXON = true;
            termios.iflag.ICRNL = true;

            std.posix.tcsetattr(stdin.handle, .FLUSH, termios) catch {};
        }
    }

    /// Clear entire screen
    pub fn clearScreen(self: *Display) !void {
        try self.write("\x1b[2J");
    }

    /// Move cursor to position (0-indexed)
    pub fn moveCursor(self: *Display, row: usize, col: usize) !void {
        try self.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
    }

    /// Hide cursor
    pub fn hideCursor(self: *Display) !void {
        try self.write("\x1b[?25l");
    }

    /// Show cursor
    pub fn showCursor(self: *Display) !void {
        try self.write("\x1b[?25h");
    }

    /// Set cursor to block shape (normal mode)
    pub fn setCursorBlock(self: *Display) !void {
        try self.write("\x1b[2 q");
    }

    /// Set cursor to bar/vertical line shape (insert mode)
    pub fn setCursorBar(self: *Display) !void {
        try self.write("\x1b[6 q");
    }

    /// Set cursor to underline shape (replace mode, if needed later)
    pub fn setCursorUnderline(self: *Display) !void {
        try self.write("\x1b[4 q");
    }

    /// Set cursor color using OSC 12 escape sequence
    /// Takes a Color from highlights config and applies it to the cursor
    /// This works in most modern terminals (xterm, iTerm2, kitty, alacritty, etc.)
    pub fn setCursorColor(self: *Display, color: highlights.Color) !void {
        // OSC 12 ; color ST
        // color format: rgb:rr/gg/bb (hex values)
        var buf: [64]u8 = undefined;
        const color_str = try std.fmt.bufPrint(&buf, "\x1b]12;rgb:{x:0>2}/{x:0>2}/{x:0>2}\x07", .{
            color.r,
            color.g,
            color.b,
        });
        try self.write(color_str);
    }

    /// Reset cursor color to terminal default
    pub fn resetCursorColor(self: *Display) !void {
        try self.write("\x1b]112\x07");
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
        self.gutter_manager.setColumnEnabled("line_numbers", false);

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
                col.enabled = true;
            } else {
                // Register new line number column
                try self.gutter_manager.registerColumn("line_numbers", renderer);
            }
        }
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
                    const new_width = gutter.calculateLineNumberWidth(line_count);
                    col.cached_width = new_width;
                    col.cache_key = line_count;
                }
            }
        }
    }

    /// Get terminal size (uses TIOCGWINSZ ioctl) and resize grid if needed
    pub fn getTerminalSize(self: *Display) !void {
        const stdout = std.fs.File.stdout();
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux or builtin.os.tag == .macos)
        {
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
    pub fn render(
        self: *Display,
        buffer: *const Buffer,
        status: []const u8,
        config: *const highlights.HighlightConfig,
        visual_state: *const VisualState,
        yank_highlight: *const YankHighlight,
        cursor_override: ?CursorPosition,
    ) !void {
        // Update terminal size (handles resize and ensures correct dimensions)
        try self.getTerminalSize();

        // Update gutter cache (Neovim optimization: invalidate on line count change)
        self.updateGutterCache(buffer);

        // Hide cursor during render
        try self.hideCursor();
        defer self.showCursor() catch {};

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

        // PHASE 2.5: Multi-layer rendering pipeline (ACTIVATED!)
        // STEP 1: Update all layers from buffer state
        try self.updateLayers(buffer, status, config, visual_state, yank_highlight);

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
        try self.renderUpdates(updates);

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

    /// Update grid from buffer content (Step 1: logical → grid)
    fn updateGridFromBuffer(self: *Display, buffer: *const Buffer, status: []const u8, config: *const highlights.HighlightConfig, visual_state: *const VisualState, yank_highlight: *const YankHighlight) !void {
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

        // Cache visual state to ensure consistency during this render frame
        const visual_active = visual_state.active;
        const cursor_pos = if (visual_active) Position{
            .line = buffer.cursor.row,
            .col = buffer.cursor.col,
        } else Position{ .line = 0, .col = 0 }; // Unused if not active
        const visual_range = if (visual_active) visual_state.getRange(cursor_pos) else undefined;

        // Check if yank highlight is visible (time-based)
        const yank_active = yank_highlight.active and yank_highlight.isVisible();

        // Get gutter width for positioning
        const gutter_width = self.gutter_manager.getTotalWidth();
        const text_cols = if (self.terminal_cols > gutter_width)
            self.terminal_cols - gutter_width
        else
            self.terminal_cols;

        // Render text lines to grid
        var row: usize = 0;
        while (row < text_rows) : (row += 1) {
            const line_num = self.viewport_top + row;

            // Render gutter columns (line numbers, signs, etc.)
            if (gutter_width > 0) {
                var gutter_buf: [32]u8 = undefined;
                const gutter_str_len = self.gutter_manager.renderLine(
                    line_num,
                    buffer.cursor.row,
                    &gutter_buf,
                );
                const gutter_str = gutter_buf[0..gutter_str_len];

                // Render gutter to grid with line number highlight
                // Use CursorLineNr for cursor line, LineNr for others
                const is_cursor_line = (line_num == buffer.cursor.row);
                const line_nr_hl = if (is_cursor_line and config.cursorline_nr != null)
                    config.cursorline_nr.?
                else if (config.line_nr != null)
                    config.line_nr.?
                else
                    null;

                const gutter_fg = if (line_nr_hl) |hl| hl.fg else null;
                const gutter_bg = if (line_nr_hl) |hl| hl.bg else null;

                var gutter_col: usize = 0;
                var byte_idx: usize = 0;
                while (byte_idx < gutter_str.len and gutter_col < gutter_width) {
                    const char_len = std.unicode.utf8ByteSequenceLength(gutter_str[byte_idx]) catch 1;
                    if (byte_idx + char_len > gutter_str.len) break;

                    const codepoint = std.unicode.utf8Decode(gutter_str[byte_idx..][0..char_len]) catch ' ';
                    self.grid.setCell(row, gutter_col, .{
                        .char = codepoint,
                        .fg = gutter_fg,
                        .bg = gutter_bg,
                    });

                    gutter_col += 1;
                    byte_idx += char_len;
                }

                // Pad remaining gutter space
                while (gutter_col < gutter_width) : (gutter_col += 1) {
                    self.grid.setCell(row, gutter_col, .{
                        .char = ' ',
                        .fg = gutter_fg,
                        .bg = gutter_bg,
                    });
                }
            }

            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num).?;

                // Strip trailing newline
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                // Apply horizontal scroll only to cursor line (convert display column to byte position)
                // Use padding-aware version to handle visual padding correctly
                const h_offset = if (line_num == buffer.cursor.row) self.viewport_left else 0;
                const start_col = if (h_offset > 0)
                    char_width.displayColumnToByte(line_without_newline, h_offset)
                else
                    0;
                const remaining = line_without_newline[start_col..];

                // Apply background colors: Normal -> CursorLine (if on cursor line)
                const is_cursor_line = (line_num == buffer.cursor.row);

                // Default to Normal highlight colors
                const fg_color = if (config.normal) |n| n.fg else null;
                var bg_color = if (config.normal) |n| n.bg else null;

                // Override with CursorLine if applicable (disabled in visual mode like Neovim)
                if (is_cursor_line and !visual_active and config.cursorline_enabled and config.cursorline != null) {
                    bg_color = config.cursorline.?.bg;
                }

                // Check if this line could be in visual selection or yank highlight (using cached state)
                const line_in_selection = visual_active and
                    (line_num >= visual_range.start.line and line_num <= visual_range.end.line);
                const line_in_yank = yank_active and
                    (line_num >= yank_highlight.start.line and line_num <= yank_highlight.end.line);

                // Fast path: Use setString for lines without any highlighting
                // Avoid fast path on cursorline to properly handle double-width char backgrounds
                const use_fast_path = !line_in_selection and !line_in_yank and !is_cursor_line;
                const end_col = if (use_fast_path) blk: {
                    break :blk self.grid.setString(row, gutter_width, remaining, fg_color, bg_color);
                } else blk: {
                    // Slow path: Character-by-character for visual/yank highlighting
                    // NOTE: Buffer positions are in BYTES, not character counts
                    var screen_col: usize = gutter_width; // Start after gutter
                    var byte_idx: usize = 0;

                    // Pre-calculate highlight backgrounds
                    const visual_bg = if (config.visual) |v|
                        v.bg
                    else
                        highlights.Color{ .r = 80, .g = 80, .b = 80 }; // Default gray

                    const yank_bg = if (config.yank_flash) |y|
                        y.bg
                    else
                        highlights.Color{ .r = 100, .g = 100, .b = 50 }; // Default yellow-ish

                    while (byte_idx < remaining.len and screen_col < (gutter_width + text_cols)) {
                        // Decode UTF-8 character
                        const char_len = std.unicode.utf8ByteSequenceLength(remaining[byte_idx]) catch 1;
                        if (byte_idx + char_len > remaining.len) break;

                        const codepoint = std.unicode.utf8Decode(remaining[byte_idx..][0..char_len]) catch ' ';
                        const width = char_width.codepointWidth(codepoint);

                        // Handle zero-width characters (combining marks, variation selectors)
                        // Attach them to the previous cell's combining array
                        if (width == 0) {
                            if (screen_col > 0) {
                                // Find the actual character cell (skip continuation cells)
                                var target_col = screen_col - 1;
                                while (target_col > 0 and self.grid.current[row][target_col].is_continuation) {
                                    target_col -= 1;
                                }
                                // Add to combining array if there's space
                                if (self.grid.current[row][target_col].combining_count < 2) {
                                    const idx = self.grid.current[row][target_col].combining_count;
                                    self.grid.current[row][target_col].combining[idx] = codepoint;
                                    self.grid.current[row][target_col].combining_count += 1;
                                }
                            }
                            byte_idx += char_len;
                            continue;
                        }

                        // Check if character start position is in selection or yank highlight
                        const buffer_col = start_col + byte_idx;
                        const char_pos = Position{
                            .line = line_num,
                            .col = buffer_col,
                        };

                        // Yank highlight takes priority over visual selection
                        const final_bg = if (yank_active and yank_highlight.contains(char_pos))
                            yank_bg
                        else if (visual_active and visual_state.contains(cursor_pos, char_pos))
                            visual_bg
                        else
                            bg_color;

                        // Set the main character cell
                        self.grid.setCell(row, screen_col, .{
                            .char = codepoint,
                            .fg = fg_color,
                            .bg = final_bg,
                        });

                        screen_col += 1;

                        // For double-width characters, fill the second column with continuation marker
                        // The cellwidth system now returns the correct width for all characters,
                        // including emoji that may have been problematic before
                        if (width == 2 and screen_col < (gutter_width + text_cols)) {
                            self.grid.setCell(row, screen_col, .{
                                .char = ' ', // Placeholder (not rendered to terminal)
                                .fg = fg_color,
                                .bg = final_bg, // Same background as the main character
                                .is_continuation = true, // Mark as continuation
                            });
                            screen_col += 1;
                        }

                        byte_idx += char_len;
                    }

                    break :blk screen_col;
                };

                // TODO: Neovim-style wide cursor for double-width chars (Phase 5: Polish)
                // Currently disabled - needs investigation into JSI config loading timing
                // The logic below should apply cursor background to both cells of double-width chars
                // if (is_cursor_line and config.cursor) |cursor_hl| { ... }

                // Fill rest of line from where text ended
                // Extend cursorline background to full width (Vim/Neovim behavior)
                // bg_color already has cursorline applied if is_cursor_line is true
                for (end_col..self.terminal_cols) |fill_col| {
                    self.grid.setCell(row, fill_col, .{ .char = ' ', .bg = bg_color });
                }
            } else {
                // Empty line indicator (Vim-style ~) - render after gutter with Normal colors
                // Gutter already rendered above (if gutter_width > 0)
                const normal_fg = if (config.normal) |n| n.fg else null;
                const normal_bg = if (config.normal) |n| n.bg else null;
                self.grid.setCell(row, gutter_width, .{ .char = '~', .fg = normal_fg, .bg = normal_bg });
                // Fill rest of line with Normal background
                for ((gutter_width + 1)..self.terminal_cols) |col| {
                    self.grid.setCell(row, col, .{ .char = ' ', .bg = normal_bg });
                }
            }
        }

        // Render status line to grid
        const status_row = self.terminal_rows - 1;
        try self.updateStatusLineInGrid(status_row, buffer, status);
    }

    /// Update status line in grid
    fn updateStatusLineInGrid(self: *Display, row: usize, buffer: *const Buffer, status: []const u8) !void {
        const filename = buffer.filepath orelse "[No Name]";
        const modified = if (buffer.modified) " [+]" else "";

        const position = try std.fmt.allocPrint(
            self.allocator,
            " {s}{s} | {s} | {d},{d}",
            .{ filename, modified, status, buffer.cursor.row + 1, buffer.cursor.col + 1 },
        );
        defer self.allocator.free(position);

        // Status line uses inverted colors (Neovim-style)
        // We'll implement this by setting all cells with a special attribute
        // For now, just render the text
        for (0..self.terminal_cols) |col| {
            if (col < position.len) {
                const char = position[col];
                self.grid.setCell(row, col, .{ .char = char });
            } else {
                self.grid.setCell(row, col, .{ .char = ' ' });
            }
        }
    }

    // ============================================================================
    // PHASE 2.5: Layer-based Rendering Pipeline
    // ============================================================================
    // These functions replace the monolithic updateGridFromBuffer with clean
    // separation of concerns - each layer handles one visual aspect

    /// Update all layers from buffer state (Phase 2.5)
    /// This is the new rendering entry point that replaces updateGridFromBuffer
    fn updateLayers(
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
        try self.updateBaseLayer(buffer, config, text_rows);
        try self.updateGutterLayer(buffer, config, text_rows);
        try self.updateSelectionLayer(buffer, visual_state, config, text_rows);
        try self.updateYankLayer(buffer, yank_highlight, config, text_rows);
        try self.updateCursorLayer(buffer, config, text_rows);

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
                _ = self.base_layer.grid.setString(row, gutter_width, remaining, fg_color, bg_color);

                // Fill rest of line
                for ((gutter_width + remaining.len)..self.terminal_cols) |col| {
                    self.base_layer.grid.setCell(row, col, .{ .char = ' ', .bg = bg_color });
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
                .char = 0,  // NULL character - won't hide base layer text
                .bg = cursorline_bg,
            });
        }

        self.cursor_layer.markDirty();
    }

    /// Render updates to terminal (Step 3: optimized output)
    /// This implements Helix's optimizations: adjacent cell skipping and attribute tracking
    fn renderUpdates(self: *Display, updates: []const Update) !void {
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
        try self.write(self.output_buf.items);
    }

    /// Helper: Compare two colors
    fn colorEql(a: highlights.Color, b: highlights.Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b;
    }

    /// Render status line at bottom of screen
    fn renderStatusLine(self: *Display, buffer: *const Buffer, status: []const u8) !void {
        const status_row = self.terminal_rows - 1;
        try self.moveCursor(status_row, 0);

        // Inverse video for status line
        try self.write("\x1b[7m");

        // File info
        const filename = buffer.filepath orelse "[No Name]";
        const modified = if (buffer.modified) " [+]" else "";
        const position = try std.fmt.allocPrint(
            std.heap.page_allocator,
            " {s}{s} | {s} | {d},{d}",
            .{ filename, modified, status, buffer.cursor.row + 1, buffer.cursor.col + 1 },
        );
        defer std.heap.page_allocator.free(position);

        // Truncate if too long
        const visible_status = if (position.len > self.terminal_cols)
            position[0..self.terminal_cols]
        else
            position;

        try self.write(visible_status);

        // Pad remaining space
        if (visible_status.len < self.terminal_cols) {
            var i: usize = 0;
            while (i < self.terminal_cols - visible_status.len) : (i += 1) {
                try self.write(" ");
            }
        }

        // Reset attributes
        try self.write("\x1b[0m");
    }

    /// Adjust viewport to keep cursor visible
    fn adjustViewport(self: *Display, buffer: *const Buffer) void {
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

        // Scroll down if cursor is below viewport
        if (buffer.cursor.row >= self.viewport_top + text_rows) {
            self.viewport_top = buffer.cursor.row - text_rows + 1;
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
