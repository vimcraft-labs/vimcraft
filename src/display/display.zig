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
const char_width = @import("char_width.zig");
const gutter = @import("gutter.zig");

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

    // Grid-based rendering
    grid: ScreenGrid,
    output_buf: std.ArrayList(u8), // Batch output (Neovim + Helix pattern)

    // Gutter system (line numbers, signs, etc.)
    gutter_manager: gutter.GutterManager,
    line_number_config: gutter.LineNumberConfig,
    sign_column_config: gutter.SignColumnConfig,

    // Cache for gutter width calculation (Neovim optimization)
    cached_line_count: usize, // Track line count for cache invalidation

    pub fn init(allocator: std.mem.Allocator) !Display {
        const grid = try ScreenGrid.init(allocator, 80, 24);
        const gutter_mgr = gutter.GutterManager.init(allocator);

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
            .gutter_manager = gutter_mgr,
            .line_number_config = .{}, // Default: no line numbers
            .sign_column_config = .{}, // Default: no sign column
            .cached_line_count = 0,
        };
    }

    pub fn deinit(self: *Display) void {
        self.grid.deinit();
        self.output_buf.deinit(self.allocator);
        self.gutter_manager.deinit();
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
        }
    }

    /// Exit raw terminal mode (restore normal terminal)
    pub fn exitRawMode(self: *Display) void {
        const stdin = std.fs.File.stdin();
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux or builtin.os.tag == .macos)
        {
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
    pub fn render(self: *Display, buffer: *const Buffer, status: []const u8, config: *const highlights.HighlightConfig, visual_state: *const VisualState, yank_highlight: *const YankHighlight) !void {
        // Update terminal size (handles resize and ensures correct dimensions)
        try self.getTerminalSize();

        // Update gutter cache (Neovim optimization: invalidate on line count change)
        self.updateGutterCache(buffer);

        debug_log.log("=== RENDER START (Grid-based) ===", .{});
        debug_log.log("Terminal size: {}x{}", .{ self.terminal_rows, self.terminal_cols });

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

        if (buffer.cursor.col >= self.viewport_left + text_cols) {
            self.viewport_left = buffer.cursor.col - text_cols + 1;
        } else if (buffer.cursor.col < self.viewport_left) {
            self.viewport_left = buffer.cursor.col;
        }

        // STEP 1: Update grid from buffer content (render to memory)
        try self.updateGridFromBuffer(buffer, status, config, visual_state, yank_highlight);

        // STEP 2: Compute diff (what changed since last frame)
        const updates = try self.grid.diff(self.allocator);
        defer self.allocator.free(updates);

        debug_log.log("Diff found {} changed cells", .{updates.len});

        // STEP 3: Render only changed cells with optimizations
        try self.renderUpdates(updates);

        // STEP 4: Swap buffers (current becomes previous for next frame)
        self.grid.swapBuffers();

        // Position cursor at buffer cursor location (add gutter offset)
        const screen_row = if (buffer.cursor.row >= self.viewport_top)
            buffer.cursor.row - self.viewport_top
        else
            0;

        const screen_col_text = if (buffer.cursor.col >= self.viewport_left)
            buffer.cursor.col - self.viewport_left
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
                const gutter_fg = if (config.line_nr) |ln| ln.fg else null;
                const gutter_bg = if (config.line_nr) |ln| ln.bg else null;

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

                // Apply horizontal scroll only to cursor line
                const h_offset = if (line_num == buffer.cursor.row) self.viewport_left else 0;
                const start_col = @min(h_offset, line_without_newline.len);
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

                // Fill rest of line from where text ended
                // Use null background for padding (don't extend cursorline to padding)
                const padding_bg = if (config.normal) |n| n.bg else null;
                for (end_col..self.terminal_cols) |fill_col| {
                    self.grid.setCell(row, fill_col, .{ .char = ' ', .bg = padding_bg });
                }
            } else {
                // Empty line indicator (Vim-style ~) - render after gutter
                // Gutter already rendered above (if gutter_width > 0)
                self.grid.setCell(row, gutter_width, .{ .char = '~', .bg = null });
                // Clear rest of line - explicitly set no background
                for ((gutter_width + 1)..self.terminal_cols) |col| {
                    self.grid.setCell(row, col, .{ .char = ' ', .bg = null });
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

        for (updates) |update| {
            // Skip continuation cells - terminals handle double-width chars automatically
            // The double-width character's background extends across both columns
            if (update.cell.is_continuation) {
                continue;
            }

            // HELIX OPTIMIZATION 1: Skip cursor movement if adjacent
            // If we're printing at (last_col + 1, same_row), terminal auto-advances
            const is_adjacent = if (last_pos) |pos|
                (update.row == pos.row and update.col == pos.col + 1)
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
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(update.cell.char, &buf) catch 1;
            try buf_writer.writeAll(buf[0..len]);

            // Write any combining characters (variation selectors, combining marks)
            for (0..update.cell.combining_count) |i| {
                const combining_len = std.unicode.utf8Encode(update.cell.combining[i], &buf) catch 1;
                try buf_writer.writeAll(buf[0..combining_len]);
            }

            // Track position for adjacent detection
            last_pos = .{ .row = update.row, .col = update.col };
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
};
