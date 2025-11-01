const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const debug_log = @import("../debug/log.zig");

/// Terminal display manager
/// Handles rendering buffer content to terminal using ANSI escape codes
pub const Display = struct {
    stdout: std.fs.File.Writer,
    terminal_rows: usize,
    terminal_cols: usize,
    viewport_top: usize, // First visible line number
    viewport_left: usize, // Horizontal scroll offset for current line

    pub fn init() Display {
        return .{
            .stdout = std.io.getStdOut().writer(),
            .terminal_rows = 24, // Default, will be updated by getTerminalSize
            .terminal_cols = 80,
            .viewport_top = 0,
            .viewport_left = 0,
        };
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

    /// Get terminal size (uses TIOCGWINSZ ioctl)
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
                    self.terminal_rows = winsize.row;
                    self.terminal_cols = winsize.col;
                }
                // If ioctl fails or returns invalid size, keep defaults (24x80)
            }
            // If not a TTY, keep defaults
        }
    }

    /// Render buffer content to screen
    pub fn render(self: *Display, buffer: *const Buffer, status: []const u8) !void {
        // Update terminal size (handles resize and ensures correct dimensions)
        try self.getTerminalSize();

        debug_log.log("=== RENDER START ===", .{});
        debug_log.log("Terminal size: {}x{}", .{ self.terminal_rows, self.terminal_cols });
        debug_log.log("Buffer cursor: row={}, col={}", .{ buffer.cursor.row, buffer.cursor.col });

        try self.hideCursor();
        defer self.showCursor() catch {};

        // Clear screen and reset cursor
        try self.clearScreen();
        try self.moveCursor(0, 0);

        // Adjust viewport to keep cursor visible
        self.adjustViewport(buffer);

        // Adjust horizontal scroll for cursor line
        if (buffer.cursor.col >= self.viewport_left + self.terminal_cols) {
            // Cursor is off right edge, scroll right
            self.viewport_left = buffer.cursor.col - self.terminal_cols + 1;
        } else if (buffer.cursor.col < self.viewport_left) {
            // Cursor is off left edge, scroll left
            self.viewport_left = buffer.cursor.col;
        }

        // Calculate visible area (reserve last line for status)
        const text_rows = if (self.terminal_rows > 1) self.terminal_rows - 1 else 1;

        // Render visible lines
        var row: usize = 0;
        debug_log.log("Rendering {} text rows", .{text_rows});
        while (row < text_rows) : (row += 1) {
            const line_num = self.viewport_top + row;

            try self.moveCursor(row, 0);

            if (line_num < buffer.lineCount()) {
                const line = buffer.getLine(line_num).?;
                debug_log.log("Line {}: raw_len={}, content=[{s}]", .{ line_num, line.len, line });

                // Strip trailing newline (we render it by moving to next row, not by printing \n)
                const line_without_newline = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                debug_log.log("Line {}: after strip len={}, content=[{s}]", .{ line_num, line_without_newline.len, line_without_newline });

                // Apply horizontal scroll only to the cursor line
                const h_offset = if (line_num == buffer.cursor.row) self.viewport_left else 0;
                const start_col = @min(h_offset, line_without_newline.len);
                const remaining = line_without_newline[start_col..];

                // Truncate to terminal width to prevent terminal from wrapping
                const visible_line = if (remaining.len > self.terminal_cols)
                    remaining[0..self.terminal_cols]
                else
                    remaining;

                debug_log.log("Line {}: visible_len={}, will render=[{s}]", .{ line_num, visible_line.len, visible_line });
                try self.stdout.writeAll(visible_line);
            } else {
                // Empty line indicator (Vim-style ~)
                try self.stdout.writeAll("~");
            }

            // Clear to end of line
            try self.stdout.writeAll("\x1b[K");
        }

        // Render status line
        try self.renderStatusLine(buffer, status);

        // Position cursor at buffer cursor location
        const screen_row = if (buffer.cursor.row >= self.viewport_top)
            buffer.cursor.row - self.viewport_top
        else
            0;

        // Adjust cursor column for horizontal scroll
        const screen_col = if (buffer.cursor.col >= self.viewport_left)
            buffer.cursor.col - self.viewport_left
        else
            0;

        // Clamp to terminal width to prevent wrapping
        const clamped_col = @min(screen_col, self.terminal_cols - 1);
        try self.moveCursor(screen_row, clamped_col);
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
