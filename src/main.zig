const std = @import("std");
const Buffer = @import("editor/buffer/buffer.zig").Buffer;
const Display = @import("backends/terminal/display/display.zig").Display;
const Mode = @import("editor/mode/mode.zig").Mode;
const ModeManager = @import("editor/mode/mode.zig").ModeManager;
const movement = @import("editor/movement/movement.zig");
const debug_log = @import("backends/debug/log.zig");
const TestHarness = @import("tools/test/harness.zig").TestHarness;
const highlights = @import("editor/config/highlights.zig");
const ConfigPaths = @import("editor/config/loader.zig").ConfigPaths;
const ConfigWatcher = @import("editor/config/watcher.zig").ConfigWatcher;
const jsi_api = @import("system/jsi/jsi_api.zig");
const event_loop = @import("system/event_loop/libuv.zig");
const EventLoopProcessor = @import("system/event_loop/processor.zig").EventLoopProcessor;
const debug_protocol = @import("debug.zig");
const VisualState = @import("backends/terminal/visual/visual.zig").VisualState;
const VisualMode = @import("backends/terminal/visual/visual.zig").VisualMode;
const Position = @import("backends/terminal/visual/visual.zig").Position;
const YankHighlight = @import("backends/terminal/visual/yank_highlight.zig").YankHighlight;
const RegisterManager = @import("editor/register/register.zig").RegisterManager;
const yank = @import("editor/buffer/yank.zig");
const paste = @import("editor/buffer/paste.zig");
const cellwidth = @import("backends/terminal/display/cellwidth.zig");
const EditOps = @import("editor/buffer/edit.zig").EditOps;
const ListChars = @import("editor/config/listchars.zig").ListChars;

// Import Hermes C API (use hermes_c namespace to avoid shadowing)
const hermes_c = @cImport({
    @cInclude("system/jsi/hermes_c_api.h");
});

/// Vimcraft - Neovim-compatible editor written in Zig
/// Phase 1+2+3+4: Text display, Vim navigation, text editing, and JavaScript config
///
/// Modes:
///   vimc <file>           - Interactive editor
///   vimc --debug <file>   - Interactive editor with Chrome DevTools debugging
///   vimc --test <file>    - Run test script
///   vimc --repl           - Interactive debugging REPL
///   vimc --help           - Show help
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

/// Pending register selection (after pressing ")
const PendingRegister = struct {
    waiting_for_name: bool = false, // Waiting for register name after "
    selected: ?u8 = null, // Selected register (a-z, A-Z, ", etc.)

    fn startSelection(self: *PendingRegister) void {
        self.waiting_for_name = true;
    }

    fn setRegister(self: *PendingRegister, reg: u8) void {
        self.selected = reg;
        self.waiting_for_name = false;
    }

    fn clear(self: *PendingRegister) void {
        self.waiting_for_name = false;
        self.selected = null;
    }

    fn isWaitingForName(self: *const PendingRegister) bool {
        return self.waiting_for_name;
    }

    fn getSelected(self: *const PendingRegister) ?u8 {
        return self.selected;
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
                const Debugger = @import("backends/debug/debugger.zig").Debugger;
                const debugger = @as(*Debugger, @ptrCast(@alignCast(ptr)));
                debugger.deinit();
                alloc.destroy(debugger);
            }
        }
    }
};

/// Global debugger pointer for logger callback (Terminal backend with --debug mode)
var global_debugger: ?*anyopaque = null;

/// Render source type
pub const RenderSource = enum {
    input,
    config,
    timer,
};

/// Check if JavaScript modified editor state and mark for re-render
/// Used in both normal and debug mode event loops
inline fn checkJavaScriptStateChanges(editor: anytype, needs_render: *bool) void {
    if (editor.js_state_dirty) {
        needs_render.* = true;
    }
}

/// Render statistics for debugging and profiling
pub const RenderStats = struct {
    total_renders: usize = 0,
    renders_from_input: usize = 0,
    renders_from_config: usize = 0,
    renders_from_timer: usize = 0,
    loop_iterations: usize = 0,
    start_time_ms: i64 = 0,

    pub fn init() RenderStats {
        return .{
            .start_time_ms = std.time.milliTimestamp(),
        };
    }

    pub fn recordRender(self: *RenderStats, source: RenderSource) void {
        self.total_renders += 1;
        switch (source) {
            .input => self.renders_from_input += 1,
            .config => self.renders_from_config += 1,
            .timer => self.renders_from_timer += 1,
        }
    }

    pub fn getRendersPerSecond(self: *const RenderStats) f64 {
        const elapsed_ms = std.time.milliTimestamp() - self.start_time_ms;
        if (elapsed_ms <= 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_renders)) / (@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
    }

    pub fn getIdlePercentage(self: *const RenderStats) f64 {
        if (self.loop_iterations == 0) return 100.0;
        const idle_iterations = self.loop_iterations - self.total_renders;
        return (@as(f64, @floatFromInt(idle_iterations)) / @as(f64, @floatFromInt(self.loop_iterations))) * 100.0;
    }
};

/// State for configuration hot reload
const ReloadState = struct {
    highlight_config: *highlights.HighlightConfig,
    debugger_state: *DebuggerState,
    allocator: std.mem.Allocator,
    needs_reload: bool = false,
    config_path: []const u8,
    // Compositor invalidation: safer and simpler than full renderHeadless()
    display: ?*Display = null,

    fn markForReload(self: *ReloadState) void {
        self.needs_reload = true;
    }

    fn reload(self: *ReloadState) !void {
        if (!self.needs_reload) return;

        // Clear all active timers (setInterval, setTimeout) before reloading
        // This prevents duplicate timers from accumulating across reloads
        jsi_api.clearAllTimers();

        // Re-execute the configuration file
        if (self.debugger_state.runtime) |runtime| {
            // Re-register console.log with debugger before reloading
            // This ensures console.log works in the reloaded config
            if (self.debugger_state.debugger_ptr) |debugger_ptr| {
                jsi_api.registerConsoleWithDebugger(@ptrCast(runtime), debugger_ptr);
            }

            jsi_api.loadConfig(@ptrCast(runtime), self.config_path, self.allocator) catch |err| {
                var stderr_buf: [256]u8 = undefined;
                var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
                const stderr = &stderr_writer.interface;
                stderr.print("Reload failed: {}\n", .{err}) catch {};
                self.needs_reload = false;
                return err;
            };
        }

        // CRITICAL FIX: Invalidate compositor to force recomposite on next render
        // This is simpler and safer than calling renderHeadless():
        // - No performance cost (deferred to next render)
        // - No lifetime/pointer safety issues
        // - No error handling complexity
        // - Works for ALL config changes (not just visual options)
        // Next render() will automatically recomposite with new config state
        if (self.display) |display| {
            // Mark ALL layers dirty to ensure complete recomposite
            // This prevents 1-frame visual glitches when gutter width changes
            display.gutter_layer.markDirty();
            display.base_layer.markDirty();
            display.cursor_layer.markDirty();
            display.selection_layer.markDirty();
            display.yank_layer.markDirty();
            display.virtual_text_layer.markDirty();
            // Note: compositor.composite() will be called in next render()
            // This ensures gutter width changes are reflected for all layers
        }

        self.needs_reload = false;
    }
};

/// Command buffer for command mode
const CommandBuffer = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) CommandBuffer {
        return .{
            .buffer = .empty,
            .allocator = allocator,
        };
    }

    fn deinit(self: *CommandBuffer) void {
        self.buffer.deinit(self.allocator);
    }

    fn clear(self: *CommandBuffer) void {
        self.buffer.clearRetainingCapacity();
    }

    fn append(self: *CommandBuffer, char: u8) !void {
        try self.buffer.append(self.allocator, char);
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
    } else if (std.mem.eql(u8, first_arg, "--debug-protocol")) {
        return try runDebugProtocol(allocator);
    } else if (std.mem.eql(u8, first_arg, "--debug")) {
        if (args.len < 3) {
            std.debug.print("Error: --debug requires a file\n", .{});
            std.debug.print("Usage: vimc --debug <file>\n", .{});
            return;
        }
        return try runEditorWithDebugger(allocator, args[2]);
    } else if (std.mem.eql(u8, first_arg, "--test")) {
        if (args.len < 3) {
            std.debug.print("Error: --test requires a test file\n", .{});
            std.debug.print("Usage: vimc --test <test_file>\n", .{});
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
        \\Vimcraft - Neovim-compatible text editor
        \\
        \\Usage:
        \\  vimc <file>                 Open file in interactive editor
        \\  vimc --debug <file>         Open file with Chrome DevTools debugging
        \\  vimc --debug-protocol       Start debug protocol server (for ovdb)
        \\  vimc --test <test_file>     Run automated test script
        \\  vimc --repl                 Interactive debugging REPL
        \\  vimc --help                 Show this help message
        \\
        \\Interactive Mode:
        \\  Normal Vim keybindings (hjkl, i/a/o, dd/dw, u, :w, :q, :debug, etc.)
        \\
        \\Debug Protocol Mode:
        \\  JSON-based protocol for automated testing and LLM verification
        \\  Used by ovdb debugger tool (see tools/ovdb/)
        \\  Communicates via stdin/stdout
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
        \\  vimc myfile.txt            # Edit a file
        \\  vimc --test bug.test       # Run test script
        \\  vimc --repl                # Start debugging REPL
        \\  vimc --debug-protocol      # Start debug server (used by ovdb)
        \\
    ;
    std.debug.print("{s}", .{help});
}

/// Load configuration from ~/.config/vimcraft/init.js
/// NOTE: Caller must call jsi_api.initJSI() before calling this function
fn loadConfigFromJs(allocator: std.mem.Allocator, config: *highlights.HighlightConfig, debugger_state: *DebuggerState) !void {
    // Get config paths
    var paths = try ConfigPaths.init(allocator);
    defer paths.deinit();

    // Ensure config directory exists
    try paths.ensureConfigDir();

    // Create default init.js if it doesn't exist
    try paths.createDefaultInitJs();

    if (paths.initJsExists()) {

        // Get runtime from debugger_state (initialized by caller)
        const runtime = debugger_state.runtime orelse {
            std.debug.print("ERROR: Runtime not initialized\n", .{});
            return error.RuntimeNotInitialized;
        };

        // Load and execute init.js
        jsi_api.loadConfig(@ptrCast(runtime), paths.init_js_path, allocator) catch |err| {
            std.debug.print("WARNING: Failed to load init.js: {}\n", .{err});
            std.debug.print("Using default configuration\n", .{});
            // Fall back to defaults
            const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
            config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
            config.cursorline_enabled = true;
            return;
        };

        // NOTE: Plugins are NOT loaded here anymore!
        // Caller must load plugins AFTER configuring gutter to ensure getGutterWidth() returns correct value
    } else {
        // Use defaults
        const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
        config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
        config.cursorline_enabled = true;
    }
}

/// Run debug protocol server (headless, stdin/stdout communication)
fn runDebugProtocol(allocator: std.mem.Allocator) !void {
    const EditorContext = @import("backends/debug/editor_context.zig").EditorContext;

    // Create headless editor context (includes Display for visual debugging)
    var editor_ctx = try EditorContext.init(allocator);
    defer editor_ctx.deinit();

    // Initialize JavaScript runtime for plugins (headless mode)
    var debugger_state = DebuggerState{ .allocator = allocator };
    defer debugger_state.deinit();

    var highlight_config = highlights.HighlightConfig.init(allocator);
    defer highlight_config.deinit();

    const OptionsManager = @import("editor/config/options.zig").OptionsManager;
    var options_mgr = OptionsManager.init(allocator);
    defer options_mgr.deinit();

    // Wire options manager to editor context
    editor_ctx.options_manager = &options_mgr;

    // Initialize JavaScript runtime for config loading
    const runtime_nullable = hermes_c.hermes_runtime_create();
    if (runtime_nullable == null) {
        std.debug.print("ERROR: Failed to create Hermes runtime\n", .{});
        return error.HermesInitFailed;
    }
    const runtime = runtime_nullable.?;
    defer hermes_c.hermes_runtime_destroy(runtime);

    // Store runtime in debugger state
    debugger_state.runtime = runtime;

    // Register JSI host functions for EditorContext (headless mode)
    jsi_api.initJSI(allocator, @ptrCast(runtime), &highlight_config, &options_mgr, &editor_ctx, &editor_ctx.display);
    defer jsi_api.deinitJSI(); // Clean up ConfigContext BEFORE runtime destruction

    // Load JavaScript config and plugins for headless debugging
    // NOTE: Display exists but won't render output (no terminal flush)
    // This allows visual debugging commands to inspect layer state
    try loadConfigFromJs(allocator, &highlight_config, &debugger_state);

    // Ensure cursorline has a default color if not set by init.js
    // This is critical for visual debugging commands (get_layer, get_output_grid)
    if (highlight_config.cursorline == null) {
        const cursorline_bg = try highlights.Color.fromHex("#1E202F");
        highlight_config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
    }

    // Apply sign column config BEFORE loading plugins (headless mode)
    // This ensures getGutterWidth() returns correct value during plugin initialization
    try editor_ctx.display.setSignColumn(highlight_config.signcolumn_mode);

    // NOW load plugins with correct gutter width (headless mode)
    var plugin_paths = try ConfigPaths.init(allocator);
    defer plugin_paths.deinit();
    if (plugin_paths.initJsExists()) {
        var plugin_files = try plugin_paths.getPluginFiles(allocator);
        defer {
            for (plugin_files.items) |path| {
                allocator.free(path);
            }
            plugin_files.deinit(allocator);
        }

        for (plugin_files.items) |plugin_path| {
            jsi_api.loadPlugin(@ptrCast(runtime), plugin_path, allocator) catch |err| {
                const filename = std.fs.path.basename(plugin_path);
                std.debug.print("WARNING: Failed to load plugin {s}: {}\n", .{ filename, err });
            };
        }
    }

    // Create debug server with editor context (has Display for visual debugging)
    var server = debug_protocol.server.Server.init(
        allocator,
        .{ .use_stdio = true },
        &editor_ctx,
        &highlight_config, // Pass highlight_config for display.render()
    );
    defer server.deinit();

    // Start server with integrated event loop (supports animations and timers)
    // The server now uses non-blocking stdin reads with poll() and interleaves:
    // 1. Process stdin commands (non-blocking with 10ms poll timeout)
    // 2. Run event_loop.runOnce()
    // 3. Process timer queue
    // 4. Process animation frame callbacks
    // This enables animated plugins like Smear cursor in headless debug mode!
    try server.start();

    // Cleanup timers after server shuts down
    jsi_api.deinitTimers();
}

/// Run the interactive editor (normal mode)
fn runEditor(allocator: std.mem.Allocator, filepath: []const u8) !void {
    const Editor = @import("editor/editor.zig").Editor;
    const TerminalBackend = @import("backends/terminal/backend.zig").TerminalBackend;

    // Initialize cellwidth system for proper character width handling
    try cellwidth.initGlobal(allocator);
    defer cellwidth.deinitGlobal(allocator);

    // Create headless editor core
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Load file into editor
    editor.buffer.loadFile(filepath) catch |err| {
        std.debug.print("Error loading file: {}\n", .{err});
        return;
    };

    // Initialize display (terminal-specific)
    var display = try Display.init(allocator);
    defer display.deinit();
    try display.setLineNumbers(true);

    // Initialize debugger state (for :debug command)
    var debugger_state = DebuggerState{ .allocator = allocator };
    defer debugger_state.deinit();

    // Initialize highlight configuration
    var highlight_config = highlights.HighlightConfig.init(allocator);
    defer highlight_config.deinit();

    const OptionsManager = @import("editor/config/options.zig").OptionsManager;
    var options_mgr = OptionsManager.init(allocator);
    defer options_mgr.deinit();

    // Wire options manager to editor core
    editor.options_manager = &options_mgr;

    // Get config paths for hot reload
    var paths = try ConfigPaths.init(allocator);
    defer paths.deinit();
    try paths.ensureConfigDir();
    try paths.createDefaultInitJs();

    // Set up hot reload state BEFORE loading config
    var reload_state = ReloadState{
        .highlight_config = &highlight_config,
        .debugger_state = &debugger_state,
        .allocator = allocator,
        .config_path = paths.init_js_path,
        .display = &display,
    };

    // Initialize JavaScript runtime for config loading
    // CRITICAL: Runtime must live for entire function (not just the if block)
    // Otherwise processTimerQueue() in main loop will access freed memory → segfault
    const runtime_nullable = hermes_c.hermes_runtime_create();
    var runtime: ?*hermes_c.OVHermesRuntime = null;
    defer {
        if (runtime) |rt| {
            hermes_c.hermes_runtime_destroy(rt);
        }
    }

    if (runtime_nullable != null) {
        runtime = runtime_nullable.?;

        // Store runtime in debugger state
        debugger_state.runtime = runtime;

        // Register JSI host functions (pass editor for cursor hooks and display for trail rendering)
        jsi_api.initJSI(allocator, @ptrCast(runtime.?), &highlight_config, &options_mgr, &editor, &display);
        defer jsi_api.deinitJSI(); // Clean up ConfigContext BEFORE runtime destruction

        // Load configuration from init.js (but don't load plugins yet)
        try loadConfigFromJs(allocator, &highlight_config, &debugger_state);

        // CRITICAL: Apply sign column config BEFORE loading plugins
        // This ensures getGutterWidth() returns the correct value when plugins initialize
        try display.setSignColumn(highlight_config.signcolumn_mode);
    }

    // Enter raw terminal mode
    try display.enterRawMode();
    defer display.exitRawMode();

    // Get terminal size BEFORE loading plugins
    // CRITICAL: getTerminalSize() calls resizeAll() which CLEARS layer content!
    // Plugins must load AFTER terminal size is determined to avoid losing their rendered content
    try display.getTerminalSize();

    // NOW load plugins AFTER terminal size is set (prevents grid.resize() from clearing content)
    if (runtime) |rt| {
        if (paths.initJsExists()) {
            var plugin_files = try paths.getPluginFiles(allocator);
            defer {
                for (plugin_files.items) |path| {
                    allocator.free(path);
                }
                plugin_files.deinit(allocator);
            }

            for (plugin_files.items) |plugin_path| {
                jsi_api.loadPlugin(@ptrCast(rt), plugin_path, allocator) catch |err| {
                    const filename = std.fs.path.basename(plugin_path);
                    std.debug.print("WARNING: Failed to load plugin {s}: {}\n", .{ filename, err });
                };
            }
        }
    }

    // Apply cursor color if configured
    if (highlight_config.cursor) |cursor_hl| {
        if (cursor_hl.bg) |cursor_bg| {
            try display.setCursorColor(cursor_bg);
        }
    }

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
                watcher = w;
            } else |_| {
                w.close();
                var i: u8 = 0;
                while (i < 5) : (i += 1) {
                    _ = event_loop.runOnce();
                }
            }
        } else |_| {}
    }

    // Create terminal backend (wraps Editor core with terminal I/O)
    var backend = TerminalBackend.init(
        allocator,
        &editor,
        &display,
        &highlight_config,
    );
    defer backend.deinit();

    // Initial render
    try backend.render();

    // Main event loop - simplified!
    var running = true;
    var needs_render = false;
    var render_stats = RenderStats.init();
    var event_processor = EventLoopProcessor.init(allocator);

    while (running) {
        render_stats.loop_iterations += 1;

        // Process event loop: libuv + timers + animation frames
        if (event_processor.tick()) {
            needs_render = true;
        }

        // Check if config needs reload
        if (reload_state.needs_reload) {
            reload_state.reload() catch {};
            needs_render = true;
        }

        // Check if cursor override is active (animated cursor plugin)
        // Use lightweight cursor-only update instead of full render
        if (editor.cursor_render_override.active) {
            if (editor.cursor_render_override.get()) |pos| {
                display.updateCursorOnly(pos.row, pos.col) catch {};
            }
        }

        // Check if yank highlight is active and needs rendering
        if (editor.yank_highlight.active and editor.yank_highlight.isVisible()) {
            needs_render = true;
        }

        // Check if JavaScript modified editor state (via vim.motion, etc.)
        checkJavaScriptStateChanges(&editor, &needs_render);

        // Handle input via TerminalBackend (all vim logic in Editor core!)
        running = try backend.handleInput(10, &needs_render);

        // Render if state changed
        if (needs_render) {
            const render_source: RenderSource = if (reload_state.needs_reload)
                .config
            else if (editor.yank_highlight.active)
                .timer
            else
                .input;
            render_stats.recordRender(render_source);

            try backend.render();
            needs_render = false;
            editor.js_state_dirty = false; // Reset flag after render completes
        }
    }

    // Clean exit
    try display.clearScreen();
    try display.moveCursor(0, 0);

    // Close file watcher
    if (watcher) |w| {
        w.close();
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            _ = event_loop.runOnce();
        }
    }

    // Deinit timers AFTER event loop is done
    // This ensures all timer callbacks have been processed
    jsi_api.deinitTimers();
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
    const Editor = @import("editor/editor.zig").Editor;
    const TerminalBackend = @import("backends/terminal/backend.zig").TerminalBackend;
    const Debugger = @import("backends/debug/debugger.zig").Debugger;

    // Initialize cellwidth system
    try cellwidth.initGlobal(allocator);
    defer cellwidth.deinitGlobal(allocator);

    // Create headless editor core
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Load file into editor
    editor.buffer.loadFile(filepath) catch |err| {
        std.debug.print("Error loading file: {}\n", .{err});
        return;
    };

    // Initialize display (terminal-specific)
    var display = try Display.init(allocator);
    defer display.deinit();
    try display.setLineNumbers(true);

    // Initialize debugger state
    var debugger_state = DebuggerState{};

    // Initialize highlight configuration
    var highlight_config = highlights.HighlightConfig.init(allocator);
    defer highlight_config.deinit();

    const OptionsManager = @import("editor/config/options.zig").OptionsManager;
    var options_mgr = OptionsManager.init(allocator);
    defer options_mgr.deinit();

    // Wire options manager to editor core
    editor.options_manager = &options_mgr;

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
        .display = &display,
    };

    // Create Hermes runtime (must stay alive for debugger)
    // CRITICAL: Runtime must live for entire function (not just initialization block)
    // Otherwise processTimerQueue() in main loop will access freed memory → segfault
    const runtime_nullable = hermes_c.hermes_runtime_create();
    if (runtime_nullable == null) {
        std.debug.print("ERROR: Failed to create Hermes runtime\n", .{});
        return error.HermesInitFailed;
    }
    const runtime = runtime_nullable.?;
    defer hermes_c.hermes_runtime_destroy(runtime);

    // Store runtime in debugger state
    debugger_state.runtime = runtime;

    // Register JSI host functions (including cursor hooks for plugins and trail rendering)
    jsi_api.initJSI(allocator, @ptrCast(runtime), &highlight_config, &options_mgr, &editor, &display);
    defer jsi_api.deinitJSI(); // Clean up ConfigContext BEFORE runtime destruction

    // Create and start CDP debugger BEFORE loading config
    var debugger = try Debugger.init(runtime, 9229);
    defer debugger.deinit();
    try debugger.start();

    // Re-register console.log with debugger
    jsi_api.registerConsoleWithDebugger(@ptrCast(runtime), debugger.handle);

    // Register editor.logger callback to forward logs to Chrome Debugger (Phase 3)
    // Store debugger pointer in global for callback access
    global_debugger = @ptrCast(&debugger);

    const LogEntry = @import("editor/log.zig").LogEntry;
    const DebuggerLogLevel = @import("backends/debug/debugger.zig").LogLevel;

    const logCallback = struct {
        fn callback(entry: LogEntry) void {
            // Get debugger from global state
            if (global_debugger) |ptr| {
                const dbg: *Debugger = @ptrCast(@alignCast(ptr));

                // Map core.log.LogLevel to debug.debugger.LogLevel
                const level: DebuggerLogLevel = switch (entry.level) {
                    .debug => .debug,
                    .info => .info,
                    .warning => .warning,
                    .err => .err,
                };

                // Forward to Chrome Debugger
                dbg.log(entry.message, level);
            }
        }
    }.callback;

    // Register the callback with editor.logger
    editor.logger.setCallback(logCallback);

    // Auto-launch Chrome DevTools
    launchChromeDevTools(9229) catch {};

    // Wait for debugger to connect
    var wait_count: usize = 0;
    while (wait_count < 50 and !debugger.isConnected()) {
        std.Thread.sleep(100 * std.time.ns_per_ms);
        wait_count += 1;
    }

    // Load configuration from init.js (but NOT plugins yet)
    if (paths.initJsExists()) {
        debugger.log("Vimcraft: Loading init.js...", .info);
        jsi_api.loadConfig(@ptrCast(runtime), paths.init_js_path, allocator) catch |err| {
            const msg = try std.fmt.allocPrint(allocator, "Failed to load init.js: {}", .{err});
            defer allocator.free(msg);
            debugger.log(msg, .err);
            std.debug.print("WARNING: Failed to load init.js: {}\n", .{err});
            const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
            highlight_config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
            highlight_config.cursorline_enabled = true;
        };
    }

    // Apply sign column config BEFORE loading plugins
    // This ensures getGutterWidth() returns correct value during plugin initialization
    try display.setSignColumn(highlight_config.signcolumn_mode);

    // Enter raw terminal mode
    try display.enterRawMode();
    defer display.exitRawMode();

    // Get terminal size BEFORE loading plugins
    // CRITICAL: getTerminalSize() calls resizeAll() which CLEARS layer content!
    // Plugins must load AFTER terminal size is determined to avoid losing their rendered content
    try display.getTerminalSize();

    // NOW load plugins AFTER terminal size is set (prevents grid.resize() from clearing content)
    if (paths.initJsExists()) {
        var plugin_files = try paths.getPluginFiles(allocator);
        defer {
            for (plugin_files.items) |path| {
                allocator.free(path);
            }
            plugin_files.deinit(allocator);
        }

        if (plugin_files.items.len > 0) {
            const msg = try std.fmt.allocPrint(allocator, "Loading {} plugin(s)", .{plugin_files.items.len});
            defer allocator.free(msg);
            debugger.log(msg, .info);
        }

        for (plugin_files.items) |plugin_path| {
            const filename = std.fs.path.basename(plugin_path);
            const msg = try std.fmt.allocPrint(allocator, "  Loading plugin: {s}", .{filename});
            defer allocator.free(msg);
            debugger.log(msg, .info);

            jsi_api.loadPlugin(@ptrCast(runtime), plugin_path, allocator) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "  WARNING: Failed to load {s}: {}", .{ filename, err });
                defer allocator.free(err_msg);
                debugger.log(err_msg, .warning);
            };
        }
    }

    // Apply cursor color if configured
    if (highlight_config.cursor) |cursor_hl| {
        if (cursor_hl.bg) |cursor_bg| {
            try display.setCursorColor(cursor_bg);
        }
    }

    // Set up hot reload watcher
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
                watcher = w;
            } else |_| {
                w.close();
                var i: u8 = 0;
                while (i < 5) : (i += 1) {
                    _ = event_loop.runOnce();
                }
            }
        } else |_| {}
    }

    // Create terminal backend (wraps Editor core)
    var backend = TerminalBackend.init(
        allocator,
        &editor,
        &display,
        &highlight_config,
    );
    defer backend.deinit();

    // Initial render
    try backend.render();

    // Main event loop - simplified!
    var running = true;
    var needs_render = false;
    var render_stats = RenderStats.init();
    var event_processor = EventLoopProcessor.init(allocator);

    while (running) {
        render_stats.loop_iterations += 1;

        // Process event loop: libuv + timers + animation frames
        if (event_processor.tick()) {
            needs_render = true;
        }

        // Check config reload
        if (reload_state.needs_reload) {
            reload_state.reload() catch {};
            needs_render = true;
        }

        // Check if cursor override is active (animated cursor plugin)
        // Use lightweight cursor-only update instead of full render
        if (editor.cursor_render_override.active) {
            if (editor.cursor_render_override.get()) |pos| {
                display.updateCursorOnly(pos.row, pos.col) catch {};
            }
        }

        // Check if yank highlight is active and needs rendering
        if (editor.yank_highlight.active and editor.yank_highlight.isVisible()) {
            needs_render = true;
        }

        // Check if JavaScript modified editor state (via vim.motion, etc.)
        checkJavaScriptStateChanges(&editor, &needs_render);

        // Handle input via TerminalBackend
        running = try backend.handleInput(10, &needs_render);

        // Render if needed
        if (needs_render) {
            const render_source: RenderSource = if (reload_state.needs_reload)
                .config
            else if (editor.yank_highlight.active)
                .timer
            else
                .input;
            render_stats.recordRender(render_source);

            try backend.render();
            needs_render = false;
            editor.js_state_dirty = false; // Reset flag after render completes
        }
    }

    // Clean exit
    try display.clearScreen();
    try display.moveCursor(0, 0);

    // Close watcher
    if (watcher) |w| {
        w.close();
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            _ = event_loop.runOnce();
        }
    }

    // Deinit timers AFTER event loop is done
    jsi_api.deinitTimers();

    std.debug.print("\n🐛 Debugger shutting down...\n", .{});
}

/// Run test mode - execute test script from file
fn runTestMode(allocator: std.mem.Allocator, test_file_path: []const u8) !void {
    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = try Display.init(allocator);
    defer display.deinit();
    try display.setLineNumbers(true); // Enable line numbers
    var mode_manager = ModeManager.init();

    // Initialize edit operations (delete, change, yank)
    var edit_ops = EditOps.init(allocator);

    var harness = TestHarness.init(allocator, &buffer, &display, &mode_manager, &edit_ops, stdout_file);

    try stdout.print("=== Vimcraft Test Mode ===\n", .{});
    try stdout.print("Running: {s}\n\n", .{test_file_path});

    // Read test file
    const test_file = try std.fs.cwd().openFile(test_file_path, .{});
    defer test_file.close();

    var test_file_buf: [4096]u8 = undefined;
    var file_reader = test_file.reader(&test_file_buf);
    const reader = &file_reader.interface;
    var line_num: usize = 0;

    while (true) {
        const line = reader.*.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        line_num += 1;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        const cmd_type = parts.next() orelse continue;

        if (std.mem.eql(u8, cmd_type, "LOAD")) {
            const filepath = parts.rest();
            try stdout.print("\n>>> LOAD {s}\n", .{filepath});
            buffer.loadFile(filepath) catch |err| {
                try stdout.print("ERROR: {}\n", .{err});
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
            std.Thread.sleep(ms * std.time.ns_per_ms);
        } else {
            try stdout.print("WARN: Unknown command at line {}: {s}\n", .{ line_num, cmd_type });
        }
    }

    try stdout.print("\n=== Test Complete ===\n", .{});
}

/// Run interactive REPL mode for debugging
fn runREPL(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const stdin_file = std.fs.File.stdin();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = stdin_file.reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    try stdout.print("\n=== Vimcraft Debug REPL ===\n", .{});
    try stdout.print("Interactive debugging mode\n", .{});
    try stdout.print("Type 'help' for commands, 'quit' to exit\n\n", .{});

    // Initialize components
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var display = try Display.init(allocator);
    defer display.deinit();
    try display.setLineNumbers(true); // Enable line numbers
    var mode_manager = ModeManager.init();

    // Initialize edit operations (delete, change, yank)
    var edit_ops = EditOps.init(allocator);

    var harness = TestHarness.init(allocator, &buffer, &display, &mode_manager, &edit_ops, stdout_file);

    while (true) {
        try stdout.writeAll("> ");

        const line = stdin.*.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) break;
            try stdout.print("Error: {}\n", .{err});
            continue;
        };

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
            try stdout.print("Goodbye!\n", .{});
            break;
        }

        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        const cmd_type = parts.next() orelse continue;

        if (std.mem.eql(u8, cmd_type, "help")) {
            try stdout.writeAll(
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
                try stdout.print("ERROR: {}\n", .{err});
                continue;
            };
            try harness.dumpState();
        } else if (std.mem.eql(u8, cmd_type, "CMD")) {
            harness.executeCommand(parts.rest()) catch |err| {
                try stdout.print("ERROR: {}\n", .{err});
            };
        } else if (std.mem.eql(u8, cmd_type, "DISPLAY")) {
            const width = std.fmt.parseInt(usize, parts.rest(), 10) catch 80;
            try harness.dumpDisplay(width);
        } else if (std.mem.eql(u8, cmd_type, "DUMP")) {
            try harness.dumpState();
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_CURSOR")) {
            var args_iter = std.mem.splitScalar(u8, parts.rest(), ' ');
            const row = std.fmt.parseInt(usize, args_iter.next() orelse "", 10) catch {
                try stdout.print("ERROR: Invalid arguments\n", .{});
                continue;
            };
            const col = std.fmt.parseInt(usize, args_iter.next() orelse "", 10) catch {
                try stdout.print("ERROR: Invalid arguments\n", .{});
                continue;
            };
            harness.assertCursor(row, col) catch {};
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_LINE")) {
            var args_iter = std.mem.splitScalar(u8, parts.rest(), ' ');
            const line_idx = std.fmt.parseInt(usize, args_iter.next() orelse "", 10) catch {
                try stdout.print("ERROR: Invalid line number\n", .{});
                continue;
            };
            harness.assertLine(line_idx, args_iter.rest()) catch {};
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_LINES")) {
            const count = std.fmt.parseInt(usize, parts.rest(), 10) catch {
                try stdout.print("ERROR: Invalid count\n", .{});
                continue;
            };
            harness.assertLineCount(count) catch {};
        } else if (std.mem.eql(u8, cmd_type, "ASSERT_MODE")) {
            harness.assertMode(parts.rest()) catch {};
        } else {
            try stdout.print("Unknown command: {s}\n", .{cmd_type});
            try stdout.print("Type 'help' for available commands\n", .{});
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

// Import test files for discovery
comptime {
    _ = @import("backends/terminal/display/cursorline_test.zig");
    _ = @import("editor/config/highlights_test.zig");
    _ = @import("editor/editor_test.zig");
}

// ============================================================================
// Public exports for benchmarks and other tools
// ============================================================================
pub const __Buffer = Buffer;
pub const __Display = Display;
pub const __VisualState = VisualState;
pub const __YankHighlight = YankHighlight;
pub const __RegisterManager = RegisterManager;
pub const __paste = paste;
pub const __highlights = highlights;
pub const __ListChars = @import("editor/config/listchars.zig").ListChars;
