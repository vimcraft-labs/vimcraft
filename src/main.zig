const std = @import("std");
const Buffer = @import("buffer/buffer.zig").Buffer;
const Display = @import("display/display.zig").Display;
const Mode = @import("mode/mode.zig").Mode;
const ModeManager = @import("mode/mode.zig").ModeManager;
const movement = @import("movement/movement.zig");

/// OpenVim - Neovim-compatible editor written in Zig
/// Phase 1+2: Text display and Vim navigation

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: openvim <filename>\n", .{});
        return;
    }

    const filepath = args[1];

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = Display.init();
    var mode_manager = ModeManager.init();

    // Load file
    buffer.loadFile(filepath) catch |err| {
        std.debug.print("Error loading file: {}\n", .{err});
        return;
    };

    // Enter raw terminal mode
    try display.enterRawMode();
    defer display.exitRawMode();

    // Get terminal size
    try display.getTerminalSize();

    // Main event loop
    var running = true;
    while (running) {
        // Render
        try display.render(&buffer, mode_manager.getModeString());
        try display.flush();

        // Handle input
        running = try handleInput(&buffer, &display, &mode_manager);
    }

    // Clean exit
    try display.clearScreen();
    try display.moveCursor(0, 0);
}

/// Handle keyboard input
/// Returns false to quit
fn handleInput(buffer: *Buffer, display: *Display, mode_manager: *ModeManager) !bool {
    const stdin = std.io.getStdIn();
    var buf: [16]u8 = undefined;

    // Read input (non-blocking)
    const bytes_read = try stdin.read(&buf);
    if (bytes_read == 0) {
        // No input, sleep briefly to avoid busy loop
        std.time.sleep(10 * std.time.ns_per_ms);
        return true;
    }

    const input = buf[0..bytes_read];

    // Handle based on mode
    if (mode_manager.isNormal()) {
        return try handleNormalMode(buffer, display, mode_manager, input);
    } else if (mode_manager.isInsert()) {
        return try handleInsertMode(buffer, mode_manager, input);
    }

    return true;
}

/// Handle input in Normal mode
fn handleNormalMode(
    buffer: *Buffer,
    display: *Display,
    mode_manager: *ModeManager,
    input: []const u8,
) !bool {
    // Single character commands
    if (input.len == 1) {
        const char = input[0];

        switch (char) {
            'q' => return false, // Quit

            // Basic movement (hjkl)
            'h' => movement.moveLeft(buffer),
            'j' => movement.moveDown(buffer),
            'k' => movement.moveUp(buffer),
            'l' => movement.moveRight(buffer),

            // Line movement
            '0' => movement.moveToLineStart(buffer),
            '$' => movement.moveToLineEnd(buffer),
            '^' => movement.moveToFirstNonBlank(buffer),

            // Word movement
            'w' => movement.moveWordForward(buffer),
            'b' => movement.moveWordBackward(buffer),
            'e' => movement.moveWordEnd(buffer),

            // Enter insert mode
            'i' => mode_manager.enterInsert(),
            'a' => {
                movement.moveRight(buffer);
                mode_manager.enterInsert();
            },
            'A' => {
                movement.moveToLineEnd(buffer);
                mode_manager.enterInsert();
            },
            'I' => {
                movement.moveToFirstNonBlank(buffer);
                mode_manager.enterInsert();
            },
            'o' => {
                // TODO: Open new line below and enter insert
                mode_manager.enterInsert();
            },
            'O' => {
                // TODO: Open new line above and enter insert
                mode_manager.enterInsert();
            },

            // Ctrl characters need special handling
            4 => { // Ctrl+D
                const viewport_height = display.terminal_rows - 1;
                movement.scrollHalfPageDown(buffer, viewport_height);
            },
            21 => { // Ctrl+U
                const viewport_height = display.terminal_rows - 1;
                movement.scrollHalfPageUp(buffer, viewport_height);
            },

            else => {},
        }
    }

    // Multi-character commands
    if (input.len == 2) {
        // 'gg' - go to top
        if (std.mem.eql(u8, input, "gg")) {
            movement.moveToFileStart(buffer);
        }
    }

    // Check for G (shift+g) - go to bottom
    if (input.len == 1 and input[0] == 'G') {
        movement.moveToFileEnd(buffer);
    }

    return true;
}

/// Handle input in Insert mode
fn handleInsertMode(
    buffer: *Buffer,
    mode_manager: *ModeManager,
    input: []const u8,
) !bool {
    _ = buffer;

    // Escape exits insert mode
    if (input.len == 1 and input[0] == 27) { // ESC
        mode_manager.enterNormal();
        return true;
    }

    // TODO: Handle text insertion
    // For now, just echo the input (debugging)

    return true;
}

// Note: No tests in main.zig - integration tests will be separate
test "main: imports" {
    // Just verify all imports compile
    _ = Buffer;
    _ = Display;
    _ = Mode;
    _ = ModeManager;
    _ = movement;
}
