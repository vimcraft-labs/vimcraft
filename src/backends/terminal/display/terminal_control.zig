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

/// Begin synchronized update (DCS = 1 s)
/// Batches all terminal output until endSynchronizedUpdate() is called
/// This prevents tearing/flickering during rendering
/// Supported terminals: iTerm2, Alacritty, WezTerm, tmux
/// Reference: https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036
pub fn beginSynchronizedUpdate(self: *Display) !void {
    if (self.has_sync_mode) {
        // DCS = 1 s ST (Device Control String with parameter 1 and command 's')
        // \x1bP = DCS (Device Control String)
        // = 1 s = synchronized update begin
        // \x1b\\ = ST (String Terminator)
        try write(self, "\x1bP=1s\x1b\\");
    }
}

/// End synchronized update (DCS = 2 s)
/// Flushes all batched terminal output atomically
/// The terminal will update all changes in a single frame, eliminating flicker
pub fn endSynchronizedUpdate(self: *Display) !void {
    if (self.has_sync_mode) {
        // DCS = 2 s ST (synchronized update end)
        try write(self, "\x1bP=2s\x1b\\");
    }
}

/// Set scrolling region (1-indexed, inclusive)
/// CSI {top} ; {bottom} r
/// Lines outside this region won't scroll when scroll commands are issued
/// Used for fast scrolling: instead of re-rendering all lines, scroll the region
/// and only render new lines that appear
pub fn setScrollRegion(self: *Display, top: usize, bottom: usize) !void {
    try print(self, "\x1b[{d};{d}r", .{ top + 1, bottom + 1 });
}

/// Reset scrolling region to full screen
/// CSI r
pub fn resetScrollRegion(self: *Display) !void {
    try write(self, "\x1b[r");
}

/// Scroll content up by n lines (Pan Down - bottom lines become visible)
/// CSI {n} S
/// This makes content move UP, revealing new lines at the BOTTOM
/// Example: Scrolling down in file (Ctrl+D) → content moves up
pub fn scrollUp(self: *Display, lines: usize) !void {
    if (lines == 0) return;
    try print(self, "\x1b[{d}S", .{lines});
}

/// Scroll content down by n lines (Pan Up - top lines become visible)
/// CSI {n} T
/// This makes content move DOWN, revealing new lines at the TOP
/// Example: Scrolling up in file (Ctrl+U) → content moves down
pub fn scrollDown(self: *Display, lines: usize) !void {
    if (lines == 0) return;
    try print(self, "\x1b[{d}T", .{lines});
}

/// Helper to write bytes to stdout (with capture support)
/// Uses Display.writeOutput to capture terminal output when capture_mode is enabled
fn write(self: *Display, bytes: []const u8) !void {
    return self.writeOutput(bytes);
}

/// Helper to print formatted output to stdout (with capture support)
/// Uses Display.printOutput to capture terminal output when capture_mode is enabled
fn print(self: *Display, comptime format: []const u8, args: anytype) !void {
    return self.printOutput(format, args);
}
