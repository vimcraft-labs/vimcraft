const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const debug_log = @import("../debug/log.zig");
const highlights = @import("../config/highlights.zig");
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const Cell = @import("screen_grid.zig").Cell;
const Update = @import("screen_grid.zig").Update;

/// Terminal display manager
/// Handles rendering buffer content to terminal using ANSI escape codes
/// Now uses grid-based rendering (Neovim-style) with Helix optimizations
pub const Display = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File.Writer,
    terminal_rows: usize,
    terminal_cols: usize,
    viewport_top: usize, // First visible line number
    viewport_left: usize, // Horizontal scroll offset for current line

    // Grid-based rendering
    grid: ScreenGrid,
    output_buf: std.ArrayList(u8), // Batch output (Neovim + Helix pattern)

    pub fn init(allocator: std.mem.Allocator) !Display {
        const grid = try ScreenGrid.init(allocator, 80, 24);
        return .{
            .allocator = allocator,
            .stdout = std.io.getStdOut().writer(),
            .terminal_rows = 24, // Default, will be updated by getTerminalSize
            .terminal_cols = 80,
            .viewport_top = 0,
            .viewport_left = 0,
            .grid = grid,
            .output_buf = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Display) void {
        self.grid.deinit();
        self.output_buf.deinit();
    }

    /// Enter raw terminal mode (disable line buffering, echo)
    pub fn enterRawMode(self: *Display) !void {
        const stdin = std.io.getStdIn();
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
            try self.stdout.writeAll("\x1b[?1049h");
        }
    }

    /// Exit raw terminal mode (restore normal terminal)
    pub fn exitRawMode(self: *Display) void {
        const stdin = std.io.getStdIn();
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux or builtin.os.tag == .macos)
        {
            // Exit alternate screen buffer (restores original terminal content)
            self.stdout.writeAll("\x1b[?1049l") catch {};

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
        try self.stdout.writeAll("\x1b[2J");
    }

    /// Move cursor to position (0-indexed)
    pub fn moveCursor(self: *Display, row: usize, col: usize) !void {
        try self.stdout.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
    }

    /// Hide cursor
    pub fn hideCursor(self: *Display) !void {
        try self.stdout.writeAll("\x1b[?25l");
    }

    /// Show cursor
    pub fn showCursor(self: *Display) !void {
        try self.stdout.writeAll("\x1b[?25h");
    }

    /// Set cursor to block shape (normal mode)
    pub fn setCursorBlock(self: *Display) !void {
        try self.stdout.writeAll("\x1b[2 q");
    }

    /// Set cursor to bar/vertical line shape (insert mode)
    pub fn setCursorBar(self: *Display) !void {
        try self.stdout.writeAll("\x1b[6 q");
    }

    /// Set cursor to underline shape (replace mode, if needed later)
    pub fn setCursorUnderline(self: *Display) !void {
        try self.stdout.writeAll("\x1b[4 q");
    }

    /// Get terminal size (uses TIOCGWINSZ ioctl) and resize grid if needed
    pub fn getTerminalSize(self: *Display) !void {
        const stdout = std.io.getStdOut();
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
    pub fn render(self: *Display, buffer: *const Buffer, status: []const u8, config: *const highlights.HighlightConfig) !void {
        // Update terminal size (handles resize and ensures correct dimensions)
        try self.getTerminalSize();

        debug_log.log("=== RENDER START (Grid-based) ===", .{});
        debug_log.log("Terminal size: {}x{}", .{ self.terminal_rows, self.terminal_cols });

        // Hide cursor during render
        try self.hideCursor();
        defer self.showCursor() catch {};

        // Adjust viewport to keep cursor visible
        self.adjustViewport(buffer);

        // Adjust horizontal scroll for cursor line
        if (buffer.cursor.col >= self.viewport_left + self.terminal_cols) {
            self.viewport_left = buffer.cursor.col - self.terminal_cols + 1;
        } else if (buffer.cursor.col < self.viewport_left) {
            self.viewport_left = buffer.cursor.col;
        }

        // STEP 1: Update grid from buffer content (render to memory)
        try self.updateGridFromBuffer(buffer, status, config);

        // STEP 2: Compute diff (what changed since last frame)
        const updates = try self.grid.diff(self.allocator);
        defer self.allocator.free(updates);

        debug_log.log("Diff found {} changed cells", .{updates.len});

        // STEP 3: Render only changed cells with optimizations
        try self.renderUpdates(updates);

        // STEP 4: Swap buffers (current becomes previous for next frame)
        self.grid.swapBuffers();

        // Position cursor at buffer cursor location
        const screen_row = if (buffer.cursor.row >= self.viewport_top)
            buffer.cursor.row - self.viewport_top
        else
            0;

        const screen_col = if (buffer.cursor.col >= self.viewport_left)
            buffer.cursor.col - self.viewport_left
        else
            0;

        const clamped_col = @min(screen_col, self.terminal_cols - 1);
        try self.moveCursor(screen_row, clamped_col);
    }

    /// Update grid from buffer content (Step 1: logical → grid)
    fn updateGridFromBuffer(self: *Display, buffer: *const Buffer, status: []const u8, config: *const highlights.HighlightConfig) !void {
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

        // Render text lines to grid
        var row: usize = 0;
        while (row < text_rows) : (row += 1) {
            const line_num = self.viewport_top + row;

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

                // Override with CursorLine if applicable
                if (is_cursor_line and config.cursorline_enabled and config.cursorline != null) {
                    bg_color = config.cursorline.?.bg;
                }

                // Write line to grid and get actual ending column
                const end_col = self.grid.setString(row, 0, remaining, fg_color, bg_color);

                // Fill rest of line from where text ended (either with cursor bg or clear it)
                // This ensures old background colors are properly cleared
                for (end_col..self.terminal_cols) |col| {
                    self.grid.setCell(row, col, .{ .char = ' ', .bg = bg_color });
                }
            } else {
                // Empty line indicator (Vim-style ~) - no background
                self.grid.setCell(row, 0, .{ .char = '~', .bg = null });
                // Clear rest of line - explicitly set no background
                for (1..self.terminal_cols) |col| {
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
        const writer = self.output_buf.writer();

        // Track state to minimize ANSI codes (Helix optimization)
        var current_fg: ?highlights.Color = null;
        var current_bg: ?highlights.Color = null;
        var current_bold: bool = false;
        var current_italic: bool = false;
        var current_underline: bool = false;
        var last_pos: ?struct { row: usize, col: usize } = null;

        for (updates) |update| {
            // HELIX OPTIMIZATION 1: Skip cursor movement if adjacent
            // If we're printing at (last_col + 1, same_row), terminal auto-advances
            const is_adjacent = if (last_pos) |pos|
                (update.row == pos.row and update.col == pos.col + 1)
            else
                false;

            if (!is_adjacent) {
                // Move cursor to position
                try writer.print("\x1b[{d};{d}H", .{ update.row + 1, update.col + 1 });
            }

            // HELIX OPTIMIZATION 2: Only send attribute changes
            // Foreground color
            if (update.cell.fg) |fg| {
                if (current_fg == null or !colorEql(current_fg.?, fg)) {
                    var buf: [32]u8 = undefined;
                    const fg_code = try fg.toAnsiFg(&buf);
                    try writer.writeAll(fg_code);
                    current_fg = fg;
                }
            } else if (current_fg != null) {
                try writer.writeAll("\x1b[39m"); // Reset FG
                current_fg = null;
            }

            // Background color
            if (update.cell.bg) |bg| {
                if (current_bg == null or !colorEql(current_bg.?, bg)) {
                    var buf: [32]u8 = undefined;
                    const bg_code = try bg.toAnsiBg(&buf);
                    try writer.writeAll(bg_code);
                    current_bg = bg;
                }
            } else if (current_bg != null) {
                try writer.writeAll("\x1b[49m"); // Reset BG
                current_bg = null;
            }

            // Bold
            if (update.cell.bold != current_bold) {
                if (update.cell.bold) {
                    try writer.writeAll("\x1b[1m");
                } else {
                    try writer.writeAll("\x1b[22m");
                }
                current_bold = update.cell.bold;
            }

            // Italic
            if (update.cell.italic != current_italic) {
                if (update.cell.italic) {
                    try writer.writeAll("\x1b[3m");
                } else {
                    try writer.writeAll("\x1b[23m");
                }
                current_italic = update.cell.italic;
            }

            // Underline
            if (update.cell.underline != current_underline) {
                if (update.cell.underline) {
                    try writer.writeAll("\x1b[4m");
                } else {
                    try writer.writeAll("\x1b[24m");
                }
                current_underline = update.cell.underline;
            }

            // Write the character
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(update.cell.char, &buf) catch 1;
            try writer.writeAll(buf[0..len]);

            // Track position for adjacent detection
            last_pos = .{ .row = update.row, .col = update.col };
        }

        // Reset all attributes at end
        try writer.writeAll("\x1b[0m");

        // NEOVIM + HELIX PATTERN: Single flush (batched output)
        try self.stdout.writeAll(self.output_buf.items);
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
        try self.stdout.writeAll("\x1b[7m");

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

        try self.stdout.writeAll(visible_status);

        // Pad remaining space
        if (visible_status.len < self.terminal_cols) {
            var i: usize = 0;
            while (i < self.terminal_cols - visible_status.len) : (i += 1) {
                try self.stdout.writeAll(" ");
            }
        }

        // Reset attributes
        try self.stdout.writeAll("\x1b[0m");
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
        const stdout = std.io.getStdOut();
        try stdout.sync();
    }
};
