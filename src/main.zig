const std = @import("std");
const Buffer = @import("editor/buffer/buffer.zig").Buffer;
const Display = @import("backends/terminal/display/display.zig").Display;
const Mode = @import("editor/mode/mode.zig").Mode;
const ModeManager = @import("editor/mode/mode.zig").ModeManager;
const movement = @import("editor/movement/movement.zig");
const debug_log = @import("backends/headless/log.zig");
const TestHarness = @import("tools/test/harness.zig").TestHarness;
const highlights = @import("editor/config/highlights.zig");
const ConfigPaths = @import("editor/config/loader.zig").ConfigPaths;
const ConfigWatcher = @import("editor/config/watcher.zig").ConfigWatcher;
const jsi_api = @import("system/jsi/jsi_api.zig");
const event_loop = @import("system/event_loop/libuv.zig");
const EventLoopProcessor = @import("system/event_loop/processor.zig").EventLoopProcessor;
const VisualState = @import("editor/visual/visual.zig").VisualState;
const VisualMode = @import("editor/visual/visual.zig").VisualMode;
const Position = @import("editor/visual/visual.zig").Position;
const YankHighlight = @import("editor/visual/yank_highlight.zig").YankHighlight;
const RegisterManager = @import("editor/register/register.zig").RegisterManager;
const yank = @import("editor/buffer/yank.zig");
const paste = @import("editor/buffer/paste.zig");
const cellwidth = @import("backends/terminal/display/cellwidth.zig");
const EditOps = @import("editor/buffer/edit.zig").EditOps;
const ListChars = @import("editor/config/listchars.zig").ListChars;
const metrics_mod = @import("core/metrics.zig");
const Metrics = metrics_mod.Metrics;

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
                const Debugger = @import("backends/headless/debugger.zig").Debugger;
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

/// Render throttle to prevent plugin spam
/// Limits maximum render rate to prevent plugins from freezing the editor
/// Default: 60 FPS (16.67ms per frame)
pub const RenderThrottle = struct {
    max_renders_per_sec: u64 = 60,
    last_render_time_ns: i128 = 0,
    min_frame_time_ns: i128,

    pub fn init(max_fps: u64) RenderThrottle {
        const fps = if (max_fps > 0) max_fps else 60;
        return .{
            .max_renders_per_sec = fps,
            .min_frame_time_ns = @divTrunc(1_000_000_000, @as(i128, @intCast(fps))),
        };
    }

    pub fn shouldRender(self: *RenderThrottle) bool {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_render_time_ns;
        if (elapsed >= self.min_frame_time_ns) {
            self.last_render_time_ns = now;
            return true;
        }
        return false;
    }

    pub fn forceRender(self: *RenderThrottle) void {
        self.last_render_time_ns = std.time.nanoTimestamp();
    }
};

/// Render statistics for debugging and profiling
pub const RenderStats = struct {
    total_renders: usize = 0,
    renders_from_input: usize = 0,
    renders_from_config: usize = 0,
    renders_from_timer: usize = 0,
    throttled_renders: usize = 0,
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

    pub fn recordThrottle(self: *RenderStats) void {
        self.throttled_renders += 1;
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
    // Editor pointer for triggering re-render after hot reload
    editor: ?*@import("editor/editor.zig").Editor = null,

    fn markForReload(self: *ReloadState) void {
        self.needs_reload = true;
    }

    fn reload(self: *ReloadState) !void {
        if (!self.needs_reload) return;

        // Clear all active timers (setInterval, setTimeout) before reloading
        // This prevents duplicate timers from accumulating across reloads
        jsi_api.clearAllTimers();

        // CRITICAL FIX #9: Clear all event listeners before reloading
        // This prevents duplicate callbacks when init.ts is reloaded
        jsi_api.clearAllEventListeners();

        // CRITICAL FIX #10: Clear all cached modules before reloading
        // This ensures require() returns fresh exports (hot reload support)
        // Without this, require() would return stale cached exports
        jsi_api.clearAllModuleCache();

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

        // CRITICAL: Mark editor state dirty to trigger immediate re-render
        // Without this, hot reload changes won't be visible until cursor moves
        if (self.editor) |ed| {
            ed.js_state_dirty = true;
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

    // Initialize transpiler cache directory
    const transpiler_cache = @import("system/transpiler/cache.zig");
    const cache_dir = try transpiler_cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);
    try transpiler_cache.initCacheDir(cache_dir);

    // Clean up old/excessive cache files (age-based + size-based)
    const cleanup_config = transpiler_cache.CleanupConfig{};
    transpiler_cache.cleanupCache(allocator, cache_dir, cleanup_config) catch |err| {
        std.debug.print("WARNING: Cache cleanup failed: {}\n", .{err});
        // Continue anyway - non-fatal error
    };

    // Store cache_dir in global state for JSI loader functions
    jsi_api.global_cache_dir = cache_dir;

    // Parse command-line arguments using our lightweight CLI parser
    const cli = @import("core/cli.zig");
    var parsed = try cli.parse(allocator);
    defer parsed.deinit();

    // Handle --help and --version first
    if (parsed.help) {
        cli.printHelp();
        return;
    }

    if (parsed.version) {
        cli.printVersion();
        return;
    }

    // Initialize metrics if --metrics flag is present
    var metrics: ?*Metrics = null;
    if (parsed.metrics) {
        metrics = try Metrics.init(allocator);
    }
    defer if (metrics) |m| m.deinit();

    // Route to appropriate command or mode
    if (parsed.command) |cmd| {
        if (std.mem.eql(u8, cmd, "init")) {
            // vimc init - Initialize TypeScript tooling
            const cmd_init = @import("cli/init.zig");
            try cmd_init.execute(allocator, parsed.force);
            return;
        } else if (std.mem.eql(u8, cmd, "run")) {
            // vimc run - Execute TypeScript files
            if (parsed.file_path == null) {
                std.debug.print("Error: 'run' requires a file path\n", .{});
                std.debug.print("Usage: vimc run <file> [--debug] [--no-cache]\n", .{});
                return;
            }
            const cmd_run = @import("cli/run.zig");
            try cmd_run.execute(allocator, parsed.file_path.?, parsed.debug, parsed.no_cache);
            return;
        } else if (std.mem.eql(u8, cmd, "install") or std.mem.eql(u8, cmd, "i")) {
            // vimc install / vimc i - Install plugins from Git URL or local path
            const cmd_install = @import("cli/install.zig");
            const source = parsed.file_path orelse "";
            cmd_install.execute(allocator, source, parsed.force) catch |err| {
                if (err != error.NoSource and err != error.AlreadyExists and err != error.NotImplemented) {
                    std.debug.print("Install failed: {}\n", .{err});
                }
            };
            return;
        } else if (std.mem.eql(u8, cmd, "list") or std.mem.eql(u8, cmd, "ls")) {
            // vimc list / vimc ls - List installed plugins
            const cmd_list = @import("cli/list.zig");
            cmd_list.execute(allocator) catch |err| {
                std.debug.print("List failed: {}\n", .{err});
            };
            return;
        } else if (std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "rm")) {
            // vimc remove / vimc rm - Remove installed plugins
            const cmd_remove = @import("cli/remove.zig");
            const plugin_name = parsed.file_path orelse "";
            cmd_remove.execute(allocator, plugin_name) catch |err| {
                if (err != error.NoPluginName and err != error.PluginNotFound) {
                    std.debug.print("Remove failed: {}\n", .{err});
                }
            };
            return;
        } else if (std.mem.eql(u8, cmd, "types")) {
            // vimc types - Sync vim.d.ts to config directory
            const cmd_types = @import("cli/types.zig");
            cmd_types.execute(allocator, parsed.check) catch |err| {
                if (err == error.TypesOutdated) {
                    // Non-zero exit for CI/CD integration
                    std.process.exit(1);
                }
                std.debug.print("Types sync failed: {}\n", .{err});
            };
            return;
        } else if (std.mem.eql(u8, cmd, "test")) {
            // vimc test - Run E2E tests (PTY + Hermes + JSON report)
            const cmd_test = @import("cli/test.zig");
            const sandbox_path = parsed.file_path orelse {
                std.debug.print("Error: 'test' requires a sandbox path\n", .{});
                std.debug.print("Usage: vimc test <sandbox_path>\n", .{});
                std.debug.print("Example: vimc test tests/e2e/basic\n", .{});
                return;
            };
            const exit_code = cmd_test.execute(allocator, sandbox_path) catch |err| {
                std.debug.print("Test runner failed: {}\n", .{err});
                std.process.exit(1);
            };
            std.process.exit(exit_code);
        } else if (std.mem.eql(u8, cmd, "--test")) {
            if (parsed.file_path == null) {
                std.debug.print("Error: --test requires a test file\n", .{});
                std.debug.print("Usage: vimc --test <test_file>\n", .{});
                return;
            }
            return try runTestMode(allocator, parsed.file_path.?);
        } else if (std.mem.eql(u8, cmd, "--repl")) {
            return try runREPL(allocator);
        } else {
            // First positional argument is a filename
            // Check if --debug flag was set
            if (parsed.debug) {
                // Run with Chrome DevTools debugger
                return try runEditorWithDebugger(allocator, cmd);
            } else {
                // Run normal interactive editor
                return try runEditor(allocator, cmd);
            }
        }
    } else {
        // No command provided - show help
        cli.printHelp();
        return;
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
        \\  vimc test <sandbox>         Run E2E tests (TypeScript + Hermes)
        \\  vimc --test <test_file>     Run legacy test script (.test files)
        \\  vimc --repl                 Interactive debugging REPL
        \\  vimc --help                 Show this help message
        \\
        \\Interactive Mode:
        \\  Normal Vim keybindings (hjkl, i/a/o, dd/dw, u, :w, :q, :debug, etc.)
        \\
        \\E2E Test Mode (vimc test):
        \\  Run TypeScript tests with vim.e2e API
        \\  Sandbox structure: tests/e2e/<name>/{config.ts,e2e.ts}
        \\  JSON output for LLM debugging (state_before, state_after, checkpoints)
        \\
        \\Legacy Test Mode (--test):
        \\  Run .test files with scripted commands
        \\  Commands: LOAD, CMD, DUMP, DISPLAY, ASSERT_*
        \\
        \\REPL Mode:
        \\  Type commands interactively and see results
        \\  Useful for debugging and experimentation
        \\  Type 'help' for available commands, 'quit' to exit
        \\
        \\Examples:
        \\  vimc myfile.txt              # Edit a file
        \\  vimc test tests/e2e/motion   # Run E2E tests
        \\  vimc --test bug.test         # Run legacy test script
        \\  vimc --repl                  # Start debugging REPL
        \\
    ;
    std.debug.print("{s}", .{help});
}

/// Load configuration from ~/.config/vimcraft/init.ts (TypeScript-only)
/// NOTE: Caller must call jsi_api.initJSI() before calling this function
fn loadConfigFromTs(allocator: std.mem.Allocator, config: *highlights.HighlightConfig, debugger_state: *DebuggerState) !void {
    // Get config paths
    var paths = try ConfigPaths.init(allocator);
    defer paths.deinit();

    // Ensure config directory exists
    try paths.ensureConfigDir();

    // Create default init.ts if it doesn't exist (TypeScript-only)
    try paths.createDefaultIndexTs();

    if (paths.indexTsExists()) {

        // Get runtime from debugger_state (initialized by caller)
        const runtime = debugger_state.runtime orelse {
            std.debug.print("ERROR: Runtime not initialized\n", .{});
            return error.RuntimeNotInitialized;
        };

        // Load and execute init.ts (transpiled automatically by loader)
        jsi_api.loadConfig(@ptrCast(runtime), paths.index_ts_path, allocator) catch |err| {
            std.debug.print("WARNING: Failed to load init.ts: {}\n", .{err});
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

    // Load file into editor (this also initializes tree-sitter syntax if available)
    editor.loadFile(filepath) catch |err| {
        std.debug.print("Error loading file: {}\n", .{err});
        return;
    };

    // Initialize display (terminal-specific)
    var display = try Display.init(allocator);
    defer display.deinit();
    try display.setLineNumbers(false); // Default: off (matches Neovim behavior)

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
    try paths.createDefaultIndexTs();

    // Set up hot reload state BEFORE loading config
    var reload_state = ReloadState{
        .highlight_config = &highlight_config,
        .debugger_state = &debugger_state,
        .allocator = allocator,
        .config_path = paths.index_ts_path,
        .display = &display,
        .editor = &editor,
    };

    // Mark Hermes initialization start (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markHermesInitStart();
    }

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

        // Mark Hermes initialization end (if metrics enabled)
        if (metrics_mod.getGlobalMetrics()) |m| {
            m.markHermesInitEnd();
        }

        // Store runtime in debugger state
        debugger_state.runtime = runtime;

        // Register JSI host functions (pass editor for cursor hooks and display for trail rendering)
        jsi_api.initJSI(allocator, @ptrCast(runtime.?), &highlight_config, &options_mgr, &editor, &display);
        defer jsi_api.deinitJSI(); // Clean up ConfigContext BEFORE runtime destruction

        // Mark config load start (if metrics enabled)
        if (metrics_mod.getGlobalMetrics()) |m| {
            m.markConfigLoadStart();
        }

        // Load configuration from init.ts (but don't load plugins yet - TypeScript-only)
        try loadConfigFromTs(allocator, &highlight_config, &debugger_state);

        // Mark config load end (if metrics enabled)
        if (metrics_mod.getGlobalMetrics()) |m| {
            m.markConfigLoadEnd();
        }

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
        if (paths.indexTsExists()) {
            var plugin_files = try paths.discoverPlugins(allocator);
            defer {
                for (plugin_files.items) |*plugin| {
                    plugin.deinit(allocator);
                }
                plugin_files.deinit(allocator);
            }

            for (plugin_files.items) |plugin| {
                if (plugin.has_entry) {
                    const filename = std.fs.path.basename(plugin.index_path);
                    const load_start = std.time.milliTimestamp();

                    jsi_api.loadPlugin(@ptrCast(rt), plugin.index_path, allocator) catch |err| {
                        std.debug.print("WARNING: Failed to load plugin {s}: {}\n", .{ filename, err });
                        continue;
                    };

                    // Record plugin load time (if metrics enabled)
                    if (metrics_mod.getGlobalMetrics()) |m| {
                        const load_time = std.time.milliTimestamp() - load_start;
                        m.recordPluginLoad(filename, load_time) catch {};
                    }
                }
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
    if (paths.indexTsExists()) {
        if (ConfigWatcher.init(
            allocator,
            paths.index_ts_path,
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

    // CRITICAL FIX: Clear screen and hide cursor BEFORE initial render
    // This prevents seeing the cursor at its pre-launch position or the "last cell" position
    try display.clearScreen();
    try display.hideCursor();
    try display.flush(); // CRITICAL: Flush escape codes to terminal BEFORE rendering starts!

    // Initial render
    try backend.render();

    // Mark first render (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markFirstRender();
    }

    // Main event loop - simplified!
    var running = true;
    var needs_render = false;
    var render_stats = RenderStats.init();
    var render_throttle = RenderThrottle.init(60); // 60 FPS max (protection against plugin spam)
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

        // Check if yank highlight is active and needs rendering
        if (editor.yank_highlight.active and editor.yank_highlight.isVisible()) {
            needs_render = true;
        }

        // Check if JavaScript modified editor state (via vim.motion, etc.)
        checkJavaScriptStateChanges(&editor, &needs_render);

        // Handle input via TerminalBackend (all vim logic in Editor core!)
        // Use 1ms timeout for responsive input without CPU spinning
        // 0ms = 100% CPU (causes thermal throttling), 10ms = sluggish, 1ms = perfect balance
        running = try backend.handleInput(1, &needs_render);

        // Render if state changed (with throttling to protect against plugin spam)
        if (needs_render) {
            // Check if we should render based on frame rate limit
            if (render_throttle.shouldRender()) {
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
            } else {
                // Throttled: Skip this render to maintain frame rate limit
                render_stats.recordThrottle();
            }
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
    const Debugger = @import("backends/headless/debugger.zig").Debugger;

    // Initialize cellwidth system
    try cellwidth.initGlobal(allocator);
    defer cellwidth.deinitGlobal(allocator);

    // Create headless editor core
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Load file into editor (this also initializes tree-sitter syntax if available)
    editor.loadFile(filepath) catch |err| {
        std.debug.print("Error loading file: {}\n", .{err});
        return;
    };

    // Initialize display (terminal-specific)
    var display = try Display.init(allocator);
    defer display.deinit();
    try display.setLineNumbers(false); // Default: off (matches Neovim behavior)

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
    try paths.createDefaultIndexTs();

    // Set up hot reload state
    var reload_state = ReloadState{
        .highlight_config = &highlight_config,
        .debugger_state = &debugger_state,
        .allocator = allocator,
        .config_path = paths.index_ts_path,
        .display = &display,
        .editor = &editor,
    };

    // Mark Hermes initialization start (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markHermesInitStart();
    }

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

    // Mark Hermes initialization end (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markHermesInitEnd();
    }

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
    const DebuggerLogLevel = @import("backends/headless/debugger.zig").LogLevel;

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

    // Wait for debugger to connect (increased timeout for slower Chrome launches)
    var wait_count: usize = 0;
    while (wait_count < 100 and !debugger.isConnected()) {
        std.Thread.sleep(100 * std.time.ns_per_ms);
        wait_count += 1;
    }

    // Give Chrome a moment to fully initialize after connection
    // This prevents race condition where messages are sent before Chrome Console is ready
    if (debugger.isConnected()) {
        std.Thread.sleep(200 * std.time.ns_per_ms);
    }

    // Mark config load start (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markConfigLoadStart();
    }

    // Load configuration from init.ts (but NOT plugins yet - TypeScript-only)
    if (paths.indexTsExists()) {
        const load_start = std.time.milliTimestamp();
        const load_result = jsi_api.loadConfig(@ptrCast(runtime), paths.index_ts_path, allocator);
        const load_time = std.time.milliTimestamp() - load_start;

        if (load_result) |_| {
            // Success - log timing
            const msg = try std.fmt.allocPrint(allocator, "[vimc] index.ts loaded in {}ms ⚡", .{load_time});
            defer allocator.free(msg);
            debugger.log(msg, .info);
        } else |err| {
            // Failure - log detailed error
            const msg = try std.fmt.allocPrint(allocator, "❌ Failed to load index.ts: {}", .{err});
            defer allocator.free(msg);
            debugger.log(msg, .err);
            std.debug.print("WARNING: Failed to load index.ts: {}\n", .{err});
            // Fall back to defaults
            const cursorline_bg = try highlights.Color.fromHex("#2b2b2b");
            highlight_config.cursorline = highlights.Highlight{ .bg = cursorline_bg };
            highlight_config.cursorline_enabled = true;
        }
    }

    // Mark config load end (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markConfigLoadEnd();
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
    if (paths.indexTsExists()) {
        var plugin_files = try paths.discoverPlugins(allocator);
        defer {
            for (plugin_files.items) |*plugin| {
                plugin.deinit(allocator);
            }
            plugin_files.deinit(allocator);
        }

        if (plugin_files.items.len > 0) {
            const msg = try std.fmt.allocPrint(allocator, "Loading {} plugin(s)", .{plugin_files.items.len});
            defer allocator.free(msg);
            debugger.log(msg, .info);
        }

        for (plugin_files.items) |plugin| {
            const filename = std.fs.path.basename(plugin.index_path);
            const msg = try std.fmt.allocPrint(allocator, "  Loading plugin: {s}", .{filename});
            defer allocator.free(msg);
            debugger.log(msg, .info);

            if (plugin.has_entry) {
                const load_start = std.time.milliTimestamp();

                jsi_api.loadPlugin(@ptrCast(runtime), plugin.index_path, allocator) catch |err| {
                    const err_msg = try std.fmt.allocPrint(allocator, "  WARNING: Failed to load {s}: {}", .{ filename, err });
                    defer allocator.free(err_msg);
                    debugger.log(err_msg, .warning);
                    continue;
                };

                // Record plugin load time (if metrics enabled)
                if (metrics_mod.getGlobalMetrics()) |m| {
                    const load_time = std.time.milliTimestamp() - load_start;
                    m.recordPluginLoad(filename, load_time) catch {};
                }
            }
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
    if (paths.indexTsExists()) {
        if (ConfigWatcher.init(
            allocator,
            paths.index_ts_path,
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

    // CRITICAL FIX: Clear screen and hide cursor BEFORE initial render
    // This prevents seeing the cursor at its pre-launch position or the "last cell" position
    try display.clearScreen();
    try display.hideCursor();
    try display.flush(); // CRITICAL: Flush escape codes to terminal BEFORE rendering starts!

    // Initial render
    try backend.render();

    // Mark first render (if metrics enabled)
    if (metrics_mod.getGlobalMetrics()) |m| {
        m.markFirstRender();
    }

    // Main event loop - simplified!
    var running = true;
    var needs_render = false;
    var render_stats = RenderStats.init();
    var render_throttle = RenderThrottle.init(60); // 60 FPS max (protection against plugin spam)
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

        // Check if yank highlight is active and needs rendering
        if (editor.yank_highlight.active and editor.yank_highlight.isVisible()) {
            needs_render = true;
        }

        // Check if JavaScript modified editor state (via vim.motion, etc.)
        checkJavaScriptStateChanges(&editor, &needs_render);

        // Handle input via TerminalBackend
        // Use 1ms timeout for responsive input without CPU spinning
        // 0ms = 100% CPU (causes thermal throttling), 10ms = sluggish, 1ms = perfect balance
        running = try backend.handleInput(1, &needs_render);

        // Render if needed (with throttling to protect against plugin spam)
        if (needs_render) {
            // Check if we should render based on frame rate limit
            if (render_throttle.shouldRender()) {
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
            } else {
                // Throttled: Skip this render to maintain frame rate limit
                render_stats.recordThrottle();
            }
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
    try display.setLineNumbers(false); // Default: off (matches Neovim behavior) // Enable line numbers
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
    try display.setLineNumbers(false); // Default: off (matches Neovim behavior) // Enable line numbers
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
    _ = @import("system/jsi/jsi_tests.zig");
    _ = @import("editor/treesitter.zig"); // Tree-sitter tests
    _ = @import("backends/headless/editor_context.zig"); // Headless editor + viewport scroll tests
    _ = @import("backends/terminal/backend.zig"); // Hot reload / render optimization tests
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
pub const __HighlightRegistry = @import("system/jsi/highlight_api.zig").HighlightRegistry;
