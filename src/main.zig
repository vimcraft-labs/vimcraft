const std = @import("std");
const Buffer = @import("buffer/buffer.zig").Buffer;
const Display = @import("display/display.zig").Display;
const Mode = @import("mode/mode.zig").Mode;
const ModeManager = @import("mode/mode.zig").ModeManager;
const movement = @import("movement/movement.zig");
const debug_log = @import("debug/log.zig");
const TestHarness = @import("test/harness.zig").TestHarness;
const highlights = @import("config/highlights.zig");
const ConfigPaths = @import("config/loader.zig").ConfigPaths;
const ConfigWatcher = @import("config/watcher.zig").ConfigWatcher;
const jsi_api = @import("jsi/jsi_api.zig");
const event_loop = @import("event_loop/libuv.zig");

// Import Hermes C API (use hermes_c namespace to avoid shadowing)
const hermes_c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

/// OpenVim - Neovim-compatible editor written in Zig
/// Phase 1+2+3+4: Text display, Vim navigation, text editing, and JavaScript config
///
/// Modes:
///   openvim <file>           - Interactive editor
///   openvim --debug <file>   - Interactive editor with Chrome DevTools debugging
///   openvim --test <file>    - Run test script
///   openvim --repl           - Interactive debugging REPL
///   openvim --help           - Show help

/// Pending command for multi-key sequences (like dd, dw)
const PendingCommand = struct {
    char: ?u8 = null,

    fn set(self: *PendingCommand, c: u8) void {
        self.char = c;
    }

    fn clear(self: *PendingCommand) void {
        self.char = null;
    }

    fn get(self: *const PendingCommand) ?u8 {
        return self.char;
    }
};

/// Global debugger state (for on-demand debugging via :debug command)
const DebuggerState = struct {
    runtime: ?*hermes_c.OVHermesRuntime = null,
    debugger_ptr: ?*anyopaque = null,
    port: u16 = 9229,
    allocator: ?std.mem.Allocator = null,

    fn deinit(self: *DebuggerState) void {
        if (self.debugger_ptr) |ptr| {
            if (self.allocator) |alloc| {
                const Debugger = @import("debug/debugger.zig").Debugger;
                const debugger = @as(*Debugger, @ptrCast(@alignCast(ptr)));
                debugger.deinit();
                alloc.destroy(debugger);
            }
        }
    }
};

/// State for configuration hot reload
const ReloadState = struct {
    highlight_config: *highlights.HighlightConfig,
    debugger_state: *DebuggerState,
    allocator: std.mem.Allocator,
    needs_reload: bool = false,
    config_path: []const u8,

    fn markForReload(self: *ReloadState) void {
        self.needs_reload = true;
    }

    fn reload(self: *ReloadState) !void {
        if (!self.needs_reload) return;

        // Re-execute the configuration file
        if (self.debugger_state.runtime) |runtime| {
            // Re-register console.log with debugger before reloading
            // This ensures console.log works in the reloaded config
            if (self.debugger_state.debugger_ptr) |debugger_ptr| {
                jsi_api.registerConsoleWithDebugger(runtime, debugger_ptr);
            }

            jsi_api.loadConfig(runtime, self.config_path, self.allocator) catch |err| {
                const stderr = std.io.getStdErr().writer();
                stderr.print("Reload failed: {}\n", .{err}) catch {};
                self.needs_reload = false;
                return err;
            };
        }

        self.needs_reload = false;
    }
};

/// Command buffer for command mode
const CommandBuffer = struct {
    buffer: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) CommandBuffer {
        return .{ .buffer = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *CommandBuffer) void {
        self.buffer.deinit();
    }

    fn clear(self: *CommandBuffer) void {
        self.buffer.clearRetainingCapacity();
    }

    fn append(self: *CommandBuffer, char: u8) !void {
        try self.buffer.append(char);
    }

    fn backspace(self: *CommandBuffer) void {
        if (self.buffer.items.len > 0) {
            _ = self.buffer.pop();
        }
    }

    fn getString(self: *const CommandBuffer) []const u8 {
        return self.buffer.items;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize libuv event loop
    try event_loop.init();
    defer event_loop.deinit();

    // Initialize debug logging
    try debug_log.init();
    defer debug_log.deinit();

    // Parse command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Show help if no arguments
    if (args.len < 2) {
        printHelp();
        return;
    }

    const first_arg = args[1];

    // Route to appropriate mode
    if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
        printHelp();
        return;
    } else if (std.mem.eql(u8, first_arg, "--debug")) {
        if (args.len < 3) {
            std.debug.print("Error: --debug requires a file\n", .{});
            std.debug.print("Usage: openvim --debug <file>\n", .{});
            return;
        }
        return try runEditorWithDebugger(allocator, args[2]);
    } else if (std.mem.eql(u8, first_arg, "--test")) {
        if (args.len < 3) {
            std.debug.print("Error: --test requires a test file\n", .{});
            std.debug.print("Usage: openvim --test <test_file>\n", .{});
            return;
        }
        return try runTestMode(allocator, args[2]);
    } else if (std.mem.eql(u8, first_arg, "--repl")) {
        return try runREPL(allocator);
    } else {
        // Default: run as interactive editor
        return try runEditor(allocator, first_arg);
    }
}

/// Print help message
fn printHelp() void {
    const help =
        \\OpenVim - Neovim-compatible text editor
        \\
        \\Usage:
        \\  openvim <file>                 Open file in interactive editor
        \\  openvim --debug <file>         Open file with Chrome DevTools debugging
        \\  openvim --test <test_file>     Run automated test script
        \\  openvim --repl                 Interactive debugging REPL
        \\  openvim --help                 Show this help message
        \\
        \\Interactive Mode:
        \\  Normal Vim keybindings (hjkl, i/a/o, dd/dw, u, :w, :q, :debug, etc.)
        \\
        \\Test Mode:
        \\  Run .test files with scripted commands
        \\  Commands: LOAD, CMD, DUMP, DISPLAY, ASSERT_*
        \\  See TEST_HARNESS.md for details
        \\
        \\REPL Mode:
        \\  Type commands interactively and see results
        \\  Useful for debugging and experimentation
        \\  Type 'help' for available commands, 'quit' to exit
        \\
        \\Examples:
        \\  openvim myfile.txt          # Edit a file
        \\  openvim --test bug.test     # Run test script
        \\  openvim --repl              # Start debugging REPL
        \\
    ;
    std.debug.print("{s}", .{help});
}

/// Load configuration from ~/.config/openvim/init.js
fn loadConfigFromJs(allocator: std.mem.Allocator, config: *highlights.HighlightConfig, debugger_state: *DebuggerState) !void {
    // Get config paths
    var paths = try ConfigPaths.init(allocator);
    defer paths.deinit();

    // Ensure config directory exists
    try paths.ensureConfigDir();

    // Create default init.js if it doesn't exist
    try paths.createDefaultInitJs();

    if (paths.initJsExists()) {

        // Create Hermes runtime
        const runtime_nullable = hermes_c.hermes_runtime_create();
        if (runtime_nullable == null) {
            std.debug.print("ERROR: Failed to create Hermes runtime\n", .{});
            return error.HermesInitFailed;
        }
        const runtime = runtime_nullable.?;

        // Store runtime in debugger_state (for :debug command)
        // NOTE: Runtime will be destroyed when program exits
        // DO NOT defer destroy here - we need it for :debug command
        debugger_state.runtime = runtime;

        // Register JSI host functions (zigSetHighlight, zigSetOption)
        // Timer system is also initialized here
        jsi_api.initJSI(allocator, runtime, config);

        // Load and execute init.js
        jsi_api.loadConfig(runtime, paths.init_js_path, allocator) catch |err| {
            std.debug.print("WARNING: Failed to load init.js: {}\n", .{err});
            std.debug.print("Using default configuration\n", .{});
            // Fall back to defaults
            const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
            config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
            config.cursorline_enabled = true;
            return;
        };
    } else {
        // Use defaults
        const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
        config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
        config.cursorline_enabled = true;
    }
}

/// Run the interactive editor (normal mode)
fn runEditor(allocator: std.mem.Allocator, filepath: []const u8) !void {

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = try Display.init(allocator);
    defer display.deinit();
    var mode_manager = ModeManager.init();
    var cmd_buffer = CommandBuffer.init(allocator);
    defer cmd_buffer.deinit();
    var pending_cmd = PendingCommand{};

    // Initialize debugger state (for :debug command)
    var debugger_state = DebuggerState{ .allocator = allocator };
    defer debugger_state.deinit();

    // Initialize highlight configuration
    var highlight_config = highlights.HighlightConfig.init(allocator);
    defer highlight_config.deinit();

    // Load configuration from init.js (Phase 4!)
    try loadConfigFromJs(allocator, &highlight_config, &debugger_state);
    defer jsi_api.deinitTimers(); // Clean up timers on exit (even on error)

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

    // Initial render
    {
        const status = try allocator.dupe(u8, mode_manager.getModeString());
        defer allocator.free(status);
        try display.render(&buffer, status, &highlight_config);
        try display.setCursorBlock(); // Start in normal mode with block cursor
        try display.flush();
    }

    // Main event loop - render only after state changes
    var running = true;
    while (running) {
        // Run libuv event loop to process timers and async events (non-blocking)
        _ = event_loop.runOnce();

        // Handle input with short timeout to keep UI responsive
        // libuv handles timer firing, so we just need to poll for input
        running = try handleInputWithTimeout(&buffer, &display, &mode_manager, &cmd_buffer, &pending_cmd, allocator, &debugger_state, 10);

        // Render after input (something changed)
        const status = if (mode_manager.isCommand())
            try std.fmt.allocPrint(allocator, ":{s}", .{cmd_buffer.getString()})
        else
            try allocator.dupe(u8, mode_manager.getModeString());
        defer allocator.free(status);

        try display.render(&buffer, status, &highlight_config);

        // Set cursor shape based on mode
        if (mode_manager.isInsert()) {
            try display.setCursorBar(); // Thin bar in insert mode
        } else {
            try display.setCursorBlock(); // Block in normal/command mode
        }

        try display.flush();
    }

    // Clean exit
    try display.clearScreen();
    try display.moveCursor(0, 0);
}

/// Launch Chrome DevTools automatically (like React Native does)
fn launchChromeDevTools(port: u16) !void {
    const allocator = std.heap.page_allocator;

    // Build the DevTools URL
    const url = try std.fmt.allocPrint(
        allocator,
        "devtools://devtools/bundled/inspector.html?ws=localhost:{d}",
        .{port},
    );
    defer allocator.free(url);

    // Platform-specific Chrome launch commands
    const builtin = @import("builtin");
    const os = builtin.os.tag;

    var argv: []const []const u8 = undefined;

    if (os == .macos) {
        // macOS: use 'open' command
        argv = &[_][]const u8{ "open", "-a", "Google Chrome", url };
    } else if (os == .linux) {
        // Linux: try common Chrome executables
        argv = &[_][]const u8{ "google-chrome", url };
    } else if (os == .windows) {
        // Windows: use 'start' command
        argv = &[_][]const u8{ "cmd", "/c", "start", "chrome", url };
    } else {
        return error.UnsupportedPlatform;
    }

    // Launch Chrome in background (don't wait for it to close)
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    // Don't wait for Chrome to exit - let it run independently
    // (calling wait() would block until Chrome closes)
}

/// Run the interactive editor with Chrome DevTools debugging enabled
fn runEditorWithDebugger(allocator: std.mem.Allocator, filepath: []const u8) !void {
    const Debugger = @import("debug/debugger.zig").Debugger;

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = try Display.init(allocator);
    defer display.deinit();
    var mode_manager = ModeManager.init();
    var cmd_buffer = CommandBuffer.init(allocator);
    defer cmd_buffer.deinit();
    var pending_cmd = PendingCommand{};

    // Initialize debugger state (already have debugger running)
    var debugger_state = DebuggerState{};

    // Initialize highlight configuration
    var highlight_config = highlights.HighlightConfig.init(allocator);
    defer highlight_config.deinit();

    // Get config paths
    var paths = try ConfigPaths.init(allocator);
    defer paths.deinit();
    try paths.ensureConfigDir();
    try paths.createDefaultInitJs();

    // Set up hot reload state
    var reload_state = ReloadState{
        .highlight_config = &highlight_config,
        .debugger_state = &debugger_state,
        .allocator = allocator,
        .config_path = paths.init_js_path,
    };

    // Create Hermes runtime (must stay alive for debugger)
    const runtime_nullable = hermes_c.hermes_runtime_create();
    if (runtime_nullable == null) {
        std.debug.print("ERROR: Failed to create Hermes runtime\n", .{});
        return error.HermesInitFailed;
    }
    const runtime = runtime_nullable.?;
    defer hermes_c.hermes_runtime_destroy(runtime);

    // Store runtime in debugger state for hot reload
    debugger_state.runtime = runtime;

    // Register JSI host functions
    // Timer system is also initialized here
    jsi_api.initJSI(allocator, runtime, &highlight_config);
    defer jsi_api.deinitTimers(); // Clean up timers on exit (even on error)

    // Create and start CDP debugger BEFORE loading config
    // This allows Chrome to see console.log from init.js
    var debugger = try Debugger.init(runtime, 9229);
    defer debugger.deinit();

    try debugger.start();

    // Re-register console.log with debugger pointer so messages go to Chrome Console
    jsi_api.registerConsoleWithDebugger(runtime, debugger.handle);

    // Auto-launch Chrome DevTools (silently)
    launchChromeDevTools(9229) catch {};

    // Wait up to 5 seconds for debugger to connect (silently)
    var wait_count: usize = 0;
    while (wait_count < 50 and !debugger.isConnected()) {
        std.time.sleep(100 * std.time.ns_per_ms);
        wait_count += 1;
    }

    // Load configuration from init.js
    if (paths.initJsExists()) {
        debugger.log("OpenVim: Loading init.js...", .info);

        jsi_api.loadConfig(runtime, paths.init_js_path, allocator) catch |err| {
            const msg = try std.fmt.allocPrint(allocator, "Failed to load init.js: {}", .{err});
            defer allocator.free(msg);
            debugger.log(msg, .err);

            std.debug.print("WARNING: Failed to load init.js: {}\n", .{err});
            // Fall back to defaults
            const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
            highlight_config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
            highlight_config.cursorline_enabled = true;
        };
    }

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

    // Set up hot reload watcher AFTER entering raw mode
    const reloadCallback = struct {
        fn callback(user_data: ?*anyopaque) void {
            const state: *ReloadState = @ptrCast(@alignCast(user_data.?));
            state.markForReload();
        }
    }.callback;

    var watcher: ?*ConfigWatcher = null;
    if (paths.initJsExists()) {
        if (ConfigWatcher.init(
            allocator,
            paths.init_js_path,
            reloadCallback,
            &reload_state,
        )) |w| {
            if (w.start()) {
                watcher = w; // Successfully started
            } else |_| {
                // Cleanup failed watcher - even though start() failed,
                // the fs_event handle was initialized, so we need to close it properly
                w.close();
                // Run event loop briefly to process the close callback
                var i: u8 = 0;
                while (i < 5) : (i += 1) {
                    _ = event_loop.runOnce();
                }
            }
        } else |_| {}
    }
    // NOTE: watcher cleanup uses uv_close() callback for proper libuv handle cleanup
    // We call close() and run the event loop to process the callback before other cleanup

    // Initial render
    {
        const status = try allocator.dupe(u8, mode_manager.getModeString());
        defer allocator.free(status);
        try display.render(&buffer, status, &highlight_config);
        try display.setCursorBlock();
        try display.flush();
    }

    // Main event loop
    var running = true;
    while (running) {
        // Run libuv event loop to process timers and async events (non-blocking)
        _ = event_loop.runOnce();

        // Check if config needs reload (triggered by file watcher)
        reload_state.reload() catch {};

        // Handle input with short timeout to keep UI responsive
        // libuv handles timer firing, so we just need to poll for input
        running = try handleInputWithTimeout(&buffer, &display, &mode_manager, &cmd_buffer, &pending_cmd, allocator, &debugger_state, 10);

        const status = if (mode_manager.isCommand())
            try std.fmt.allocPrint(allocator, ":{s}", .{cmd_buffer.getString()})
        else
            try allocator.dupe(u8, mode_manager.getModeString());
        defer allocator.free(status);

        try display.render(&buffer, status, &highlight_config);

        if (mode_manager.isInsert()) {
            try display.setCursorBar();
        } else {
            try display.setCursorBlock();
        }

        try display.flush();
    }

    // Clean exit
    try display.clearScreen();
    try display.moveCursor(0, 0);

    // CRITICAL: Close the file watcher and let event loop process the close callback
    // This properly cleans up the libuv handle and frees all memory without leaks
    if (watcher) |w| {
        w.close();

        // Run event loop a few times to ensure close callback is processed
        // The close callback will free all memory and destroy the struct
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            _ = event_loop.runOnce();
        }
    }

    std.debug.print("\n🐛 Debugger shutting down...\n", .{});
}

/// Handle keyboard input with timeout (for timer support)
/// Returns false to quit
fn handleInputWithTimeout(
    buffer: *Buffer,
    display: *Display,
    mode_manager: *ModeManager,
    cmd_buffer: *CommandBuffer,
    pending_cmd: *PendingCommand,
    allocator: std.mem.Allocator,
    debugger_state: *DebuggerState,
    timeout_ms: ?i64,
) !bool {
    const stdin = std.io.getStdIn();
    var buf: [16]u8 = undefined;

    // Use poll() to wait for input with timeout
    const posix = std.posix;
    var poll_fds = [_]posix.pollfd{
        .{
            .fd = stdin.handle,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    // Convert timeout to milliseconds for poll()
    // If no timers, use 100ms default to avoid busy-waiting
    const poll_timeout: i32 = if (timeout_ms) |t|
        @intCast(@min(t, std.math.maxInt(i32)))
    else
        100;

    const poll_result = try posix.poll(&poll_fds, poll_timeout);

    // If no input available (timeout or no data), return true (continue)
    if (poll_result == 0 or poll_fds[0].revents == 0) {
        return true;
    }

    // Read input (non-blocking)
    const bytes_read = try stdin.read(&buf);
    if (bytes_read == 0) {
        return true;
    }

    const input = buf[0..bytes_read];

    // Handle based on mode
    if (mode_manager.isNormal()) {
        return try handleNormalMode(buffer, display, mode_manager, cmd_buffer, pending_cmd, input);
    } else if (mode_manager.isInsert()) {
        return try handleInsertMode(buffer, mode_manager, input);
    } else if (mode_manager.isVisual()) {
        return try handleVisualMode(buffer, mode_manager, input);
    } else if (mode_manager.isCommand()) {
        return try handleCommandMode(buffer, mode_manager, cmd_buffer, allocator, input, debugger_state);
    }

    return true;
}

/// Handle input in Normal mode
fn handleNormalMode(
    buffer: *Buffer,
    display: *Display,
    mode_manager: *ModeManager,
    cmd_buffer: *CommandBuffer,
    pending_cmd: *PendingCommand,
    input: []const u8,
) !bool {
    // Check for pending command first (e.g., waiting for second 'd' in 'dd')
    if (pending_cmd.get()) |pending| {
        if (input.len == 1) {
            const char = input[0];

            // Handle pending 'd' commands
            if (pending == 'd') {
                switch (char) {
                    'd' => try buffer.deleteLine(), // dd - delete line
                    'w' => try buffer.deleteWord(), // dw - delete word
                    else => {}, // Invalid combo, just ignore
                }
                pending_cmd.clear();
                return true;
            }
        }

        // Clear pending command if we didn't match
        pending_cmd.clear();
    }

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

            // Delete operations
            'x' => try buffer.deleteChar(),
            'd' => {
                // Wait for next character (dd, dw, etc.)
                pending_cmd.set('d');
            },

            // Undo/redo
            'u' => try buffer.undo(),

            // Enter command mode
            ':' => {
                cmd_buffer.clear();
                mode_manager.enterCommand();
            },

            // Enter visual mode
            'v' => mode_manager.enterVisual(),

            // Enter insert mode
            'i' => mode_manager.enterInsert(),
            'a' => {
                movement.moveRight(buffer);
                mode_manager.enterInsert();
            },
            'A' => {
                movement.moveToLineEnd(buffer);
                movement.moveRight(buffer); // Move one more to be AFTER last char
                mode_manager.enterInsert();
            },
            'I' => {
                movement.moveToFirstNonBlank(buffer);
                mode_manager.enterInsert();
            },
            'o' => {
                // Open new line below and enter insert
                movement.moveToLineEnd(buffer);
                try buffer.insertChar('\n');
                mode_manager.enterInsert();
            },
            'O' => {
                // Open new line above and enter insert
                movement.moveToLineStart(buffer);
                try buffer.insertChar('\n');
                movement.moveUp(buffer);
                mode_manager.enterInsert();
            },

            // Ctrl characters need special handling
            4 => { // Ctrl+D
                const viewport_height = display.terminal_rows - 1;
                movement.scrollHalfPageDown(buffer, viewport_height);
            },
            18 => { // Ctrl+R
                try buffer.redo();
            },
            21 => { // Ctrl+U
                const viewport_height = display.terminal_rows - 1;
                movement.scrollHalfPageUp(buffer, viewport_height);
            },

            else => {},
        }
    }

    // Arrow keys (escape sequences: ESC [ A/B/C/D)
    if (input.len == 3 and input[0] == 27 and input[1] == '[') {
        switch (input[2]) {
            'A' => movement.moveUp(buffer),    // Up arrow
            'B' => movement.moveDown(buffer),  // Down arrow
            'C' => movement.moveRight(buffer), // Right arrow
            'D' => movement.moveLeft(buffer),  // Left arrow
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
    // Escape exits insert mode
    if (input.len == 1 and input[0] == 27) { // ESC
        mode_manager.enterNormal();
        return true;
    }

    // Arrow keys (escape sequences: ESC [ A/B/C/D)
    if (input.len == 3 and input[0] == 27 and input[1] == '[') {
        switch (input[2]) {
            'A' => movement.moveUp(buffer),    // Up arrow
            'B' => movement.moveDown(buffer),  // Down arrow
            'C' => movement.moveRight(buffer), // Right arrow
            'D' => movement.moveLeft(buffer),  // Left arrow
            else => {},
        }
        return true;
    }

    // Handle special keys
    if (input.len == 1) {
        const char = input[0];

        switch (char) {
            127, 8 => { // Backspace (127 on macOS, 8 on some systems)
                try buffer.deleteCharBefore();
            },
            13 => { // Enter
                try buffer.insertChar('\n');
            },
            else => {
                // Regular character - insert it
                if (char >= 32 and char < 127) { // Printable ASCII
                    try buffer.insertChar(char);
                }
            },
        }
    }

    return true;
}

/// Handle input in Visual mode
fn handleVisualMode(
    buffer: *Buffer,
    mode_manager: *ModeManager,
    input: []const u8,
) !bool {
    // Escape exits visual mode
    if (input.len == 1 and input[0] == 27) { // ESC
        mode_manager.enterNormal();
        return true;
    }

    // Navigation in visual mode (extends selection)
    if (input.len == 1) {
        const char = input[0];

        switch (char) {
            // hjkl navigation
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

            // File movement
            'G' => movement.moveToFileEnd(buffer),

            // Exit visual mode
            'v' => mode_manager.enterNormal(),

            else => {},
        }
    }

    // Arrow keys (escape sequences: ESC [ A/B/C/D)
    if (input.len == 3 and input[0] == 27 and input[1] == '[') {
        switch (input[2]) {
            'A' => movement.moveUp(buffer),    // Up arrow
            'B' => movement.moveDown(buffer),  // Down arrow
            'C' => movement.moveRight(buffer), // Right arrow
            'D' => movement.moveLeft(buffer),  // Left arrow
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

    return true;
}

/// Handle input in Command mode
fn handleCommandMode(
    buffer: *Buffer,
    mode_manager: *ModeManager,
    cmd_buffer: *CommandBuffer,
    allocator: std.mem.Allocator,
    input: []const u8,
    debugger_state: ?*DebuggerState,
) !bool {
    if (input.len != 1) return true;

    const char = input[0];

    switch (char) {
        27 => { // ESC - exit command mode
            cmd_buffer.clear();
            mode_manager.enterNormal();
        },
        13 => { // Enter - execute command
            const cmd = cmd_buffer.getString();

            // Execute command
            if (std.mem.eql(u8, cmd, "w")) {
                // Save file
                buffer.saveFile() catch |err| {
                    std.debug.print("Error saving file: {}\n", .{err});
                };
            } else if (std.mem.eql(u8, cmd, "q")) {
                // Quit
                cmd_buffer.clear();
                mode_manager.enterNormal();
                return false;
            } else if (std.mem.eql(u8, cmd, "wq")) {
                // Save and quit
                buffer.saveFile() catch |err| {
                    std.debug.print("Error saving file: {}\n", .{err});
                };
                return false;
            } else if (std.mem.eql(u8, cmd, "debug")) {
                // Launch Chrome DevTools debugging
                if (debugger_state) |state| {
                    if (state.debugger_ptr == null and state.runtime != null) {
                        // Create debugger on-demand (allocate on heap for persistence)
                        const Debugger = @import("debug/debugger.zig").Debugger;
                        const debugger_heap = try allocator.create(Debugger);
                        debugger_heap.* = try Debugger.init(state.runtime.?, state.port);

                        // Start the debugger
                        try debugger_heap.start();

                        // Re-register console.log with debugger so messages go to Chrome Console
                        jsi_api.registerConsoleWithDebugger(state.runtime.?, debugger_heap.handle);

                        // Launch Chrome (silently)
                        launchChromeDevTools(state.port) catch {};

                        // Store the debugger pointer
                        state.debugger_ptr = debugger_heap;
                    } else if (state.debugger_ptr != null) {
                        // Already debugging - just relaunch Chrome
                        launchChromeDevTools(state.port) catch {};
                    }
                }
            } else {
                // Unknown command - just ignore for now
            }

            cmd_buffer.clear();
            mode_manager.enterNormal();
        },
        127, 8 => { // Backspace
            cmd_buffer.backspace();
        },
        else => {
            // Add character to command buffer
            if (char >= 32 and char < 127) { // Printable ASCII
                try cmd_buffer.append(char);
            }
        },
    }

    return true;
}

/// Run test mode - execute test script from file
fn runTestMode(allocator: std.mem.Allocator, test_file_path: []const u8) !void {
    const stdout = std.io.getStdOut();

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = try Display.init(allocator);
    defer display.deinit();
    var mode_manager = ModeManager.init();
    var harness = TestHarness.init(allocator, &buffer, &display, &mode_manager, stdout);

    try stdout.writer().print("=== OpenVim Test Mode ===\n", .{});
    try stdout.writer().print("Running: {s}\n\n", .{test_file_path});

    // Read test file
    const test_file = try std.fs.cwd().openFile(test_file_path, .{});
    defer test_file.close();

    var buf_reader = std.io.bufferedReader(test_file.reader());
    var reader = buf_reader.reader();
    var line_buf: [1024]u8 = undefined;
    var line_num: usize = 0;

    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        line_num += 1;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        const cmd_type = parts.next() orelse continue;

        if (std.mem.eql(u8, cmd_type, "LOAD")) {
            const filepath = parts.rest();
            try stdout.writer().print("\n>>> LOAD {s}\n", .{filepath});
            buffer.loadFile(filepath) catch |err| {
                try stdout.writer().print("ERROR: {}\n", .{err});
                continue;
            };
            try harness.dumpState();
        } else if (std.mem.eql(u8, cmd_type, "CMD")) {
            try harness.executeCommand(parts.rest());
        } else if (std.mem.eql(u8, cmd_type, "DISPLAY")) {
            const width = try std.fmt.parseInt(usize, parts.rest(), 10);
            try harness.dumpDisplay(width);
        } else if (std.mem.eql(u8, cmd_type, "DUMP")) {
            try harness.dumpState();
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_CURSOR")) {
            var args_iter = std.mem.splitScalar(u8, parts.rest(), ' ');
            const row = try std.fmt.parseInt(usize, args_iter.next() orelse "", 10);
            const col = try std.fmt.parseInt(usize, args_iter.next() orelse "", 10);
            try harness.assertCursor(row, col);
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_LINE")) {
            var args_iter = std.mem.splitScalar(u8, parts.rest(), ' ');
            const line_idx = try std.fmt.parseInt(usize, args_iter.next() orelse "", 10);
            try harness.assertLine(line_idx, args_iter.rest());
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_LINES")) {
            const count = try std.fmt.parseInt(usize, parts.rest(), 10);
            try harness.assertLineCount(count);
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_MODE")) {
            try harness.assertMode(parts.rest());
        } else if (std.mem.eql(u8, cmd_type, "SLEEP")) {
            const ms = try std.fmt.parseInt(u64, parts.rest(), 10);
            std.time.sleep(ms * std.time.ns_per_ms);
        } else {
            try stdout.writer().print("WARN: Unknown command at line {}: {s}\n", .{ line_num, cmd_type });
        }
    }

    try stdout.writer().print("\n=== Test Complete ===\n", .{});
}

/// Run interactive REPL mode for debugging
fn runREPL(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    try stdout.writer().print("\n=== OpenVim Debug REPL ===\n", .{});
    try stdout.writer().print("Interactive debugging mode\n", .{});
    try stdout.writer().print("Type 'help' for commands, 'quit' to exit\n\n", .{});

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = try Display.init(allocator);
    defer display.deinit();
    var mode_manager = ModeManager.init();
    var harness = TestHarness.init(allocator, &buffer, &display, &mode_manager, stdout);

    var buf_reader = std.io.bufferedReader(stdin.reader());
    var reader = buf_reader.reader();
    var line_buf: [1024]u8 = undefined;

    while (true) {
        try stdout.writer().writeAll("> ");

        const line = reader.readUntilDelimiterOrEof(&line_buf, '\n') catch |err| {
            try stdout.writer().print("Error: {}\n", .{err});
            continue;
        };

        if (line == null) break;

        const trimmed = std.mem.trim(u8, line.?, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
            try stdout.writer().print("Goodbye!\n", .{});
            break;
        }

        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        const cmd_type = parts.next() orelse continue;

        if (std.mem.eql(u8, cmd_type, "help")) {
            try stdout.writer().writeAll(
                \\Commands:
                \\  LOAD <file>         - Load file into buffer
                \\  CMD <command>       - Execute editor command
                \\  DISPLAY <width>     - Show visual display
                \\  DUMP                - Show buffer state
                \\  ASSERT_CURSOR r c   - Assert cursor position
                \\  ASSERT_LINE n text  - Assert line content
                \\  ASSERT_LINES count  - Assert line count
                \\  ASSERT_MODE mode    - Assert mode
                \\  help                - Show this help
                \\  quit/exit           - Exit REPL
                \\
            );
        } else if (std.mem.eql(u8, cmd_type, "LOAD")) {
            buffer.loadFile(parts.rest()) catch |err| {
                try stdout.writer().print("ERROR: {}\n", .{err});
                continue;
            };
            try harness.dumpState();
        } else if (std.mem.eql(u8, cmd_type, "CMD")) {
            harness.executeCommand(parts.rest()) catch |err| {
                try stdout.writer().print("ERROR: {}\n", .{err});
            };
        } else if (std.mem.eql(u8, cmd_type, "DISPLAY")) {
            const width = std.fmt.parseInt(usize, parts.rest(), 10) catch 80;
            try harness.dumpDisplay(width);
        } else if (std.mem.eql(u8, cmd_type, "DUMP")) {
            try harness.dumpState();
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_CURSOR")) {
            var args_iter = std.mem.splitScalar(u8, parts.rest(), ' ');
            const row = std.fmt.parseInt(usize, args_iter.next() orelse "", 10) catch {
                try stdout.writer().print("ERROR: Invalid arguments\n", .{});
                continue;
            };
            const col = std.fmt.parseInt(usize, args_iter.next() orelse "", 10) catch {
                try stdout.writer().print("ERROR: Invalid arguments\n", .{});
                continue;
            };
            harness.assertCursor(row, col) catch {};
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_LINE")) {
            var args_iter = std.mem.splitScalar(u8, parts.rest(), ' ');
            const line_idx = std.fmt.parseInt(usize, args_iter.next() orelse "", 10) catch {
                try stdout.writer().print("ERROR: Invalid line number\n", .{});
                continue;
            };
            harness.assertLine(line_idx, args_iter.rest()) catch {};
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_LINES")) {
            const count = std.fmt.parseInt(usize, parts.rest(), 10) catch {
                try stdout.writer().print("ERROR: Invalid count\n", .{});
                continue;
            };
            harness.assertLineCount(count) catch {};
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_MODE")) {
            harness.assertMode(parts.rest()) catch {};
        } else {
            try stdout.writer().print("Unknown command: {s}\n", .{cmd_type});
            try stdout.writer().print("Type 'help' for available commands\n", .{});
        }
    }
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
