const std = @import("std");
const Display = @import("display.zig").Display;

/// Enter raw terminal mode (disable line buffering, echo)
pub fn enterRawMode(self: *Display) !void {
    const stdin = std.fs.File.stdin();
    const builtin = @import("builtin");

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
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
        try write(self, "\x1b[?1049h");

        // Enable mouse tracking
        // SGR mode (1006): Better coordinate support (handles terminals larger than 223 cols)
        // Button tracking (1000): Report button press/release events
        try write(self, "\x1b[?1006h"); // Enable SGR mouse mode
        try write(self, "\x1b[?1000h"); // Enable mouse button tracking

        // Enable bracketed paste mode
        // This wraps pasted content in ESC[200~ ... ESC[201~ sequences
        // Allows us to distinguish between typed and pasted text
        try write(self, "\x1b[?2004h"); // Enable bracketed paste mode
    }
}

/// Exit raw terminal mode (restore normal terminal)
pub fn exitRawMode(self: *Display) void {
    const stdin = std.fs.File.stdin();
    const builtin = @import("builtin");

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        // Disable bracketed paste mode
        write(self, "\x1b[?2004l") catch {}; // Disable bracketed paste mode

        // Disable mouse tracking
        write(self, "\x1b[?1000l") catch {}; // Disable mouse button tracking
        write(self, "\x1b[?1006l") catch {}; // Disable SGR mouse mode

        // Exit alternate screen buffer (restores original terminal content)
        write(self, "\x1b[?1049l") catch {};

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
    try write(self, "\x1b[2J");
}

/// Move cursor to position (0-indexed)
pub fn moveCursor(self: *Display, row: usize, col: usize) !void {
    try print(self, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

/// Hide cursor
pub fn hideCursor(self: *Display) !void {
    try write(self, "\x1b[?25l");
}

/// Show cursor
pub fn showCursor(self: *Display) !void {
    try write(self, "\x1b[?25h");
}

/// Set cursor to block shape (normal mode)
pub fn setCursorBlock(self: *Display) !void {
    try write(self, "\x1b[2 q");
}

/// Set cursor to bar/vertical line shape (insert mode)
pub fn setCursorBar(self: *Display) !void {
    try write(self, "\x1b[6 q");
}

/// Set cursor to underline shape (replace mode, if needed later)
pub fn setCursorUnderline(self: *Display) !void {
    try write(self, "\x1b[4 q");
}

/// Set cursor color using OSC 12 escape sequence
/// Takes a Color from highlights config and applies it to the cursor
/// This works in most modern terminals (xterm, iTerm2, kitty, alacritty, etc.)
pub fn setCursorColor(self: *Display, color: @import("../../../editor/config/highlights.zig").Color) !void {
    // OSC 12 ; color ST
    // color format: rgb:rr/gg/bb (hex values)
    var buf: [64]u8 = undefined;
    const color_str = try std.fmt.bufPrint(&buf, "\x1b]12;rgb:{x:0>2}/{x:0>2}/{x:0>2}\x07", .{
        color.r,
        color.g,
        color.b,
    });
    try write(self, color_str);
}

/// Reset cursor color to terminal default
pub fn resetCursorColor(self: *Display) !void {
    try write(self, "\x1b]112\x07");
}

/// Helper to write bytes to stdout
fn write(self: *Display, bytes: []const u8) !void {
    return self.stdout.writeAll(bytes);
}

/// Helper to print formatted output to stdout
fn print(self: *Display, comptime format: []const u8, args: anytype) !void {
    // Format to a temporary buffer, then write it
    const formatted = try std.fmt.bufPrint(&self.stdout_buf, format, args);
    try self.stdout.writeAll(formatted);
}
