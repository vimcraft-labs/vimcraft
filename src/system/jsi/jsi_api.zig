/// JSI API - Main Integration Module
/// Coordinates all JSI API modules and provides unified initialization
/// This file has been refactored from 1824 lines into 8 focused modules
const std = @import("std");
const highlights = @import("../../editor/config/highlights.zig");
const OptionsManager = @import("../../editor/config/options.zig").OptionsManager;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;
const EventEmitter = @import("event_emitter.zig").EventEmitter;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// Import all JSI API modules
pub const helpers = @import("helpers.zig");
pub const config_api = @import("config_api.zig");
pub const console_api = @import("console_api.zig");
pub const timer_api = @import("timer_api.zig");
pub const animation_api = @import("animation_api.zig");
pub const cursor_api = @import("cursor_api.zig");
pub const layer_api = @import("layer_api.zig");
pub const motion_api = @import("motion_api.zig");
pub const keymap_api = @import("keymap_api.zig");
pub const filetype_api = @import("filetype_api.zig");
pub const buffer_api = @import("buffer_api.zig");
pub const event_api = @import("event_api.zig");
pub const highlight_api = @import("highlight_api.zig");
pub const module_api = @import("module_api.zig");
pub const metrics_api = @import("metrics_api.zig");
pub const autocmd_api = @import("autocmd_api.zig");
pub const usercommand_api = @import("usercommand_api.zig");
pub const loader = @import("loader.zig");
pub const fs_api = @import("fs_api.zig");
pub const process_api = @import("process_api.zig");
pub const process_async_api = @import("process_async_api.zig");
pub const pty_api = @import("pty_api.zig");
pub const fetch_api = @import("fetch_api.zig");
pub const e2e_api = @import("e2e_api.zig");
pub const api_buffer = @import("api_buffer.zig");
pub const api_window = @import("api_window.zig");
pub const namespace_api = @import("namespace_api.zig");

// Import new transpiler system
const transpiler = @import("../transpiler/loader.zig");
const cache_module = @import("../transpiler/cache.zig");

/// Context struct for host functions
pub const JSIContext = struct {
    config: *highlights.HighlightConfig,
    display: *Display,
};

/// Global state for cleanup
pub var global_config_ctx: ?*config_api.ConfigContext = null;
pub var global_motion_ctx: ?*motion_api.MotionContext = null;
pub var global_keymap_ctx: ?*keymap_api.KeymapContext = null;
pub var global_highlight_ctx: ?*highlight_api.HighlightContext = null;
pub var global_event_emitter: ?*EventEmitter = null;
pub var global_autocmd_manager: ?*autocmd_api.AutocmdManager = null;
pub var global_usercommand_ctx: ?*usercommand_api.UserCommandContext = null;
pub var global_allocator: ?std.mem.Allocator = null;
pub var global_fs_ctx: ?*fs_api.FsContext = null;
pub var global_process_ctx: ?*process_api.ProcessContext = null;
pub var global_process_async_ctx: ?*process_async_api.AsyncProcessContext = null;
pub var global_pty_ctx: ?*pty_api.PtyContext = null;
pub var global_fetch_ctx: ?*fetch_api.FetchContext = null;
pub var global_e2e_ctx: ?*e2e_api.E2EContext = null;

/// Global transpiler cache state (initialized in main.zig)
pub var global_cache_dir: ?[]const u8 = null;
pub var global_cache_stats: cache_module.CacheStats = .{};

/// Initialize JSI runtime and register all host functions
/// editor_or_context can be either *Editor or *EditorContext - both have logger field
pub fn initJSI(
    allocator: std.mem.Allocator,
    runtime: *c.OVHermesRuntime,
    config: *highlights.HighlightConfig,
    options_mgr: *OptionsManager,
    editor_or_context: anytype,
    display: ?*Display,
) void {
    // Create ConfigContext for config API (heap-allocated, lives as long as runtime)
    const cfg_ctx = allocator.create(config_api.ConfigContext) catch @panic("Failed to allocate ConfigContext");

    // Get js_state_dirty pointer based on editor type
    const js_state_dirty_ptr: ?*bool = blk: {
        const T = @TypeOf(editor_or_context);
        if (T == *Editor) {
            break :blk &editor_or_context.js_state_dirty;
        } else {
            break :blk null; // EditorContext doesn't have js_state_dirty
        }
    };

    cfg_ctx.* = config_api.ConfigContext{
        .highlight_config = config,
        .options_manager = options_mgr,
        .allocator = allocator,
        .display = display, // Pass display for options that control display (e.g., vim.opt.number)
        .js_state_dirty = js_state_dirty_ptr,
        .buffer = blk: {
            const T = @TypeOf(editor_or_context);
            if (T == *Editor) {
                // Editor uses multi-buffer architecture - get current buffer
                // Note: This pointer becomes stale when user switches buffers,
                // but vim.bo operations are typically done on current buffer
                break :blk editor_or_context.getCurrentBuffer();
            } else if (T == *EditorContext) {
                // EditorContext has buffer() accessor method
                break :blk editor_or_context.buffer();
            } else {
                // Fallback for other types (shouldn't happen in practice)
                break :blk null;
            }
        },
        .editor = blk: {
            const T = @TypeOf(editor_or_context);
            if (T == *Editor) {
                break :blk editor_or_context;
            } else if (T == *EditorContext) {
                // EditorContext wraps an Editor - get pointer to it for tree-sitter parsing
                break :blk &editor_or_context.editor;
            } else {
                break :blk null;
            }
        },
        // Module system (Phase 4)
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };

    // Store for cleanup in deinitJSI()
    global_config_ctx = cfg_ctx;
    global_allocator = allocator;

    // Register configuration API (setHighlight, setOption, getOption)
    config_api.register(runtime, cfg_ctx);
    config_api.registerLegacy(runtime, cfg_ctx); // Register helper functions (getAllOptions, getAllOptionsWithScope)

    // Register console API (consoleLog)
    console_api.register(runtime);
    console_api.setEditor(editor_or_context);

    // Register timer API (setTimeout, setInterval, clearTimer)
    timer_api.register(runtime, allocator);

    // Register animation frame API (requestAnimationFrame)
    animation_api.register(runtime, allocator);

    // Register cursor API (getCursorPosition, hide, show)
    // Register for both Editor and EditorContext
    // Pass display for cursor visibility control (hide/show during animations)
    const T = @TypeOf(editor_or_context);
    if (T == *Editor) {
        cursor_api.register(runtime, editor_or_context, display);
    } else if (T == *EditorContext) {
        // EditorContext has its own display - pass pointer to it
        cursor_api.registerForEditorContext(runtime, editor_or_context, &editor_or_context.display);
    }

    // Register filetype API (vim.filetype.match)
    // Both Editor and EditorContext have ts_loader, so register for both
    filetype_api.register(runtime, editor_or_context, allocator);

    // Register buffer API (vim.buffer.getContent, vim.buffer.getLineContent, etc.)
    // Only register for Editor (not EditorContext) - needs multi-buffer support
    // EditorContext uses headless mode and doesn't need JavaScript buffer access
    if (T == *Editor) {
        buffer_api.register(runtime, editor_or_context);
    }

    // Register layer API (createLayer, renderVirtualText, setLayerOpacity, etc.)
    // Pass js_state_dirty_ptr so layer changes trigger full render (not cursor-only optimization)
    layer_api.register(runtime, display, js_state_dirty_ptr);
    layer_api.registerLegacy(runtime, display); // Register global functions for smear plugin backwards compat

    // Register cursor API legacy functions (getCursorPosition as global) for smear plugin backwards compat
    if (T == *Editor) {
        cursor_api.registerLegacy(runtime, editor_or_context);
    }

    // Register motion API (vim.motion.* functions)
    // Register for both Editor and EditorContext
    if (T == *Editor) {
        const motion_ctx = allocator.create(motion_api.MotionContext) catch @panic("Failed to allocate MotionContext");
        // TODO: This is problematic - buffer pointer becomes stale when user switches buffers
        // Need to refactor MotionContext to store *Editor instead and call getCurrentBuffer()
        const current_buffer = editor_or_context.getCurrentBuffer() orelse @panic("No current buffer for motion API");
        motion_ctx.* = motion_api.MotionContext{
            .buffer = current_buffer,
            .viewport_top = &editor_or_context.viewport_top,
            .viewport_height = if (display) |d| d.terminal_rows - 1 else 24,
            .js_state_dirty = &editor_or_context.js_state_dirty,
        };
        global_motion_ctx = motion_ctx;
        motion_api.register(runtime, motion_ctx);
    } else if (T == *EditorContext) {
        // EditorContext - use accessor methods for buffer/viewport
        const motion_ctx = allocator.create(motion_api.MotionContext) catch @panic("Failed to allocate MotionContext");
        motion_ctx.* = motion_api.MotionContext{
            .buffer = editor_or_context.buffer(),
            .viewport_top = &editor_or_context.display.viewport_top,
            .viewport_height = if (display) |d| d.terminal_rows - 1 else 24,
            .js_state_dirty = null, // EditorContext doesn't need dirty tracking
        };
        global_motion_ctx = motion_ctx;
        motion_api.register(runtime, motion_ctx);
    }

    // Register keymap API (vim.keymap.set/del)
    // Now register for both Editor and EditorContext (both have keymap_mgr)
    if (T == *Editor) {
        const keymap_ctx = keymap_api.KeymapContext.init(
            allocator,
            &editor_or_context.keymap_mgr,
            runtime,
        ) catch @panic("Failed to allocate KeymapContext");
        global_keymap_ctx = keymap_ctx;
        keymap_api.register(runtime, keymap_ctx);
    } else if (T == *EditorContext) {
        const keymap_ctx = keymap_api.KeymapContext.init(
            allocator,
            editor_or_context.keymap_mgr(),
            runtime,
        ) catch @panic("Failed to allocate KeymapContext");
        global_keymap_ctx = keymap_ctx;
        keymap_api.register(runtime, keymap_ctx);
    }

    // Register event API (vim.on, vim.off, vim.emit) and autocmd API
    // Now register for both Editor and EditorContext (E2E tests need autocmd API)
    if (T == *Editor) {
        const emitter = allocator.create(EventEmitter) catch @panic("Failed to allocate EventEmitter");
        emitter.* = EventEmitter.init(allocator, runtime);
        global_event_emitter = emitter;

        // Store in Editor for use by native code (buffer operations, mode changes)
        editor_or_context.event_emitter = emitter;

        // Register vim.on(), vim.off(), vim.emit() JavaScript API
        event_api.register(runtime, emitter);

        // Register autocmd API (vim.api.createAutoCommand, vim.api.deleteAutoCommand, etc.)
        const autocmd_mgr = allocator.create(autocmd_api.AutocmdManager) catch @panic("Failed to allocate AutocmdManager");
        autocmd_mgr.* = autocmd_api.AutocmdManager.init(allocator, runtime, emitter) catch @panic("Failed to init AutocmdManager");

        global_autocmd_manager = autocmd_mgr;
        autocmd_api.initAutocmdManager(autocmd_mgr);
        autocmd_api.register(runtime);

        // Store in Editor for use by native code (firing autocmds on BufEnter, etc.)
        editor_or_context.autocmd_manager = autocmd_mgr;

        // Register user command API (vim.api.createUserCommand, vim.api.delUserCommand, etc.)
        const usercommand_ctx = usercommand_api.UserCommandContext.init(allocator, runtime) catch @panic("Failed to allocate UserCommandContext");
        global_usercommand_ctx = usercommand_ctx;
        usercommand_api.register(runtime, usercommand_ctx);
        usercommand_api.registerLegacy(runtime, usercommand_ctx); // Register global functions for runtime.js

        // Store in Editor for use by native code (executing user commands)
        editor_or_context.usercommand_ctx = usercommand_ctx;
    } else if (T == *EditorContext) {
        // EditorContext (headless mode) - also needs event + autocmd API for E2E tests
        const emitter = allocator.create(EventEmitter) catch @panic("Failed to allocate EventEmitter");
        emitter.* = EventEmitter.init(allocator, runtime);
        global_event_emitter = emitter;

        // Register vim.on(), vim.off(), vim.emit() JavaScript API
        event_api.register(runtime, emitter);

        // Register autocmd API (vim.api.createAutoCommand, vim.api.deleteAutoCommand, etc.)
        const autocmd_mgr = allocator.create(autocmd_api.AutocmdManager) catch @panic("Failed to allocate AutocmdManager");
        autocmd_mgr.* = autocmd_api.AutocmdManager.init(allocator, runtime, emitter) catch @panic("Failed to init AutocmdManager");
        global_autocmd_manager = autocmd_mgr;
        autocmd_api.initAutocmdManager(autocmd_mgr);
        autocmd_api.register(runtime);

        // Store in inner Editor for use by native code (firing autocmds on CursorMoved, etc.)
        editor_or_context.editor.autocmd_manager = autocmd_mgr;

        // Register user command API (for completeness in headless mode)
        const usercommand_ctx = usercommand_api.UserCommandContext.init(allocator, runtime) catch @panic("Failed to allocate UserCommandContext");
        global_usercommand_ctx = usercommand_ctx;
        usercommand_api.register(runtime, usercommand_ctx);
        usercommand_api.registerLegacy(runtime, usercommand_ctx); // Register global functions for runtime.js

        // Store in inner Editor for use by native code (executing user commands)
        editor_or_context.editor.usercommand_ctx = usercommand_ctx;
    }

    // Register highlight API (vim.api.setHighlight, vim.api.getHighlight)
    // Both Editor and EditorContext have highlight_registry
    const hl_ctx = allocator.create(highlight_api.HighlightContext) catch @panic("Failed to allocate HighlightContext");
    hl_ctx.* = highlight_api.HighlightContext{
        .registry = if (T == *Editor)
            &editor_or_context.highlight_registry
        else if (T == *EditorContext)
            editor_or_context.highlight_registry()
        else
            &editor_or_context.highlight_registry, // Duck-typed fallback
        .allocator = allocator,
        .js_state_dirty = js_state_dirty_ptr,
    };
    global_highlight_ctx = hl_ctx;
    highlight_api.register(runtime, hl_ctx);

    // Register module API (require() - Phase 4)
    module_api.register(runtime, cfg_ctx);

    // Register metrics API (vim.metrics - performance tracking)
    metrics_api.register(runtime);

    // Register fs API (global fs object)
    const fs_ctx = allocator.create(fs_api.FsContext) catch @panic("Failed to allocate FsContext");
    fs_ctx.* = fs_api.FsContext{
        .allocator = allocator,
    };
    global_fs_ctx = fs_ctx;
    fs_api.register(runtime, fs_ctx);

    // Register process API (global process object)
    const proc_ctx = allocator.create(process_api.ProcessContext) catch @panic("Failed to allocate ProcessContext");
    proc_ctx.* = process_api.ProcessContext{
        .allocator = allocator,
    };
    global_process_ctx = proc_ctx;
    process_api.register(runtime, proc_ctx);

    // Register async process API (process.spawnAsync for persistent subprocesses with stdio)
    const proc_async_ctx = allocator.create(process_async_api.AsyncProcessContext) catch @panic("Failed to allocate AsyncProcessContext");
    proc_async_ctx.* = process_async_api.AsyncProcessContext{
        .allocator = allocator,
    };
    global_process_async_ctx = proc_async_ctx;
    process_async_api.register(runtime, proc_async_ctx);

    // Register PTY API (process.spawnPty for interactive terminal programs)
    const pty_ctx = allocator.create(pty_api.PtyContext) catch @panic("Failed to allocate PtyContext");
    pty_ctx.* = pty_api.PtyContext{
        .allocator = allocator,
    };
    global_pty_ctx = pty_ctx;
    pty_api.register(runtime, pty_ctx);

    // Register fetch API (global fetch function)
    const fetch_ctx = allocator.create(fetch_api.FetchContext) catch @panic("Failed to allocate FetchContext");
    fetch_ctx.* = fetch_api.FetchContext{
        .allocator = allocator,
    };
    global_fetch_ctx = fetch_ctx;
    fetch_api.register(runtime, fetch_ctx);

    // Register E2E API (vim.e2e - E2E testing and plugin development debugging)
    // Available in ALL modes (Editor + EditorContext) - difference is rendering backend, not API
    // CRITICAL: Use function pointer for getCurrentBuffer to support multi-window (splits)
    // A static buffer pointer becomes stale after :vsplit creates a new window/buffer
    if (T == *Editor) {
        const e2e_ctx = allocator.create(e2e_api.E2EContext) catch @panic("Failed to allocate E2EContext");
        e2e_ctx.* = e2e_api.E2EContext{
            .allocator = allocator,
            .get_current_buffer_fn = &getCurrentBufferWrapper,
            .mode_manager = &editor_or_context.mode_manager,
            .visual_state = &editor_or_context.visual_state,
            .register_mgr = &editor_or_context.register_mgr,
            .editor = @ptrCast(editor_or_context),
            .execute_keys_fn = &executeKeysWrapper,
            .js_state_dirty = &editor_or_context.js_state_dirty,
            .display = display, // Wire display for PTY capture
        };
        global_e2e_ctx = e2e_ctx;
        e2e_api.register(runtime, e2e_ctx);
    } else if (T == *EditorContext) {
        // EditorContext (headless mode) - uses accessor methods
        const e2e_ctx = allocator.create(e2e_api.E2EContext) catch @panic("Failed to allocate E2EContext");
        e2e_ctx.* = e2e_api.E2EContext{
            .allocator = allocator,
            .get_current_buffer_fn = &getCurrentBufferWrapperContext,
            .mode_manager = editor_or_context.mode_manager(),
            .visual_state = editor_or_context.visual_state(),
            .register_mgr = editor_or_context.register_mgr(),
            .editor = @ptrCast(editor_or_context),
            .execute_keys_fn = &executeKeysWrapperContext,
            .js_state_dirty = null, // EditorContext doesn't need dirty tracking
            .display = &editor_or_context.display, // Wire display for PTY capture
        };
        global_e2e_ctx = e2e_ctx;
        e2e_api.register(runtime, e2e_ctx);
    }

    // Register vim.api buffer functions (getCurrentBuf, bufGetLines, etc.)
    // Register for both Editor and EditorContext
    if (T == *Editor) {
        api_buffer.registerForEditor(runtime, editor_or_context, allocator);
    } else if (T == *EditorContext) {
        api_buffer.registerForEditorContext(runtime, editor_or_context, allocator);
    }

    // Register vim.api window functions (getCurrentWin, winGetCursor, etc.)
    // Register for both Editor and EditorContext
    if (T == *Editor) {
        api_window.registerForEditor(runtime, editor_or_context, allocator);
    } else if (T == *EditorContext) {
        api_window.registerForEditorContext(runtime, editor_or_context, allocator);
    }

    // Register namespace API (createNamespace, bufAddHighlight, bufClearNamespace)
    // These are required for LSP diagnostics and plugins that need to highlight buffer regions
    if (T == *Editor) {
        namespace_api.registerForEditor(runtime, editor_or_context, allocator, js_state_dirty_ptr);
    } else if (T == *EditorContext) {
        namespace_api.registerForEditorContext(runtime, editor_or_context, allocator);
    }

    // JSI functions registered (silent mode)
}

/// Wrapper function for Editor.executeKeys that matches E2EContext function pointer signature
fn executeKeysWrapper(editor_ptr: *anyopaque, keys_str: []const u8) anyerror!void {
    const editor: *Editor = @ptrCast(@alignCast(editor_ptr));
    _ = try editor.executeKeys(keys_str);
}

/// Wrapper function for EditorContext.executeKeys that matches E2EContext function pointer signature
fn executeKeysWrapperContext(ctx_ptr: *anyopaque, keys_str: []const u8) anyerror!void {
    const ctx: *EditorContext = @ptrCast(@alignCast(ctx_ptr));
    try ctx.executeKeys(keys_str);
}

// Import Buffer type for getCurrentBuffer wrappers
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;

/// Wrapper function for Editor.getCurrentBuffer that matches E2EContext function pointer signature
/// This is critical for multi-window support - E2EContext must dynamically fetch the current buffer
/// instead of caching a stale pointer that becomes invalid after :vsplit
fn getCurrentBufferWrapper(editor_ptr: *anyopaque) ?*Buffer {
    const editor: *Editor = @ptrCast(@alignCast(editor_ptr));
    return editor.getCurrentBuffer();
}

/// Wrapper function for EditorContext.buffer() that matches E2EContext function pointer signature
fn getCurrentBufferWrapperContext(ctx_ptr: *anyopaque) ?*Buffer {
    const ctx: *EditorContext = @ptrCast(@alignCast(ctx_ptr));
    return ctx.buffer();
}

/// Re-register console.log with debugger pointer
/// This should be called after debugger is created to enable Chrome Console output
pub fn registerConsoleWithDebugger(runtime: *c.OVHermesRuntime, debugger_ptr: *anyopaque) void {
    console_api.registerWithDebugger(runtime, debugger_ptr);
}

/// Clean up JSI resources (called before runtime destruction)
pub fn deinitJSI() void {
    if (global_config_ctx) |ctx| {
        // Clean up module cache (destroy cached Hermes values AND free keys)
        var iter = ctx.module_cache.iterator();
        while (iter.next()) |entry| {
            c.hermes_value_destroy(entry.value_ptr.exports);
            // CRITICAL FIX: Free the cache key (allocated in module_api.zig:315)
            ctx.allocator.free(entry.key_ptr.*);
        }
        ctx.module_cache.deinit();

        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_config_ctx = null;
    }
    if (global_motion_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_motion_ctx = null;
    }
    if (global_keymap_ctx) |ctx| {
        ctx.deinit(); // KeymapContext has its own deinit that frees itself
        global_keymap_ctx = null;
    }
    if (global_highlight_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_highlight_ctx = null;
    }
    if (global_event_emitter) |emitter| {
        emitter.deinit(); // Clean up all event listeners
        if (global_allocator) |alloc| {
            alloc.destroy(emitter);
        }
        global_event_emitter = null;
    }
    if (global_autocmd_manager) |mgr| {
        mgr.deinit(); // Clean up all autocmds
        if (global_allocator) |alloc| {
            alloc.destroy(mgr);
        }
        global_autocmd_manager = null;
    }
    if (global_usercommand_ctx) |ctx| {
        ctx.deinit(); // Clean up all user commands
        global_usercommand_ctx = null;
    }
    // Clean up filetype context (no deinit needed, just free the struct)
    filetype_api.deinit();
    // Clean up fs context
    if (global_fs_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_fs_ctx = null;
    }
    // Clean up process context
    if (global_process_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_process_ctx = null;
    }
    // Clean up async process context (kills all running processes)
    process_async_api.deinit();
    if (global_process_async_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_process_async_ctx = null;
    }
    // Clean up PTY context (kills all running PTY processes)
    pty_api.deinit();
    if (global_pty_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_pty_ctx = null;
    }
    // Clean up fetch context and module state (queue, in-flight tracker)
    fetch_api.deinit(); // CRITICAL: Clean up fetch queue and in-flight requests
    if (global_fetch_ctx) |ctx| {
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_fetch_ctx = null;
    }
    // Clean up e2e context
    if (global_e2e_ctx) |ctx| {
        e2e_api.deinit(); // Clean up test suites
        if (global_allocator) |alloc| {
            alloc.destroy(ctx);
        }
        global_e2e_ctx = null;
    }
    // Clean up api_buffer context
    api_buffer.deinit();
    // Clean up api_window context
    api_window.deinit();
    // Clean up namespace context
    namespace_api.deinit();
    global_allocator = null;
}

/// Clear all event listeners (for config reload)
/// This prevents duplicate callbacks when init.js is reloaded
pub fn clearAllEventListeners() void {
    if (global_event_emitter) |emitter| {
        emitter.removeAll();
    }
}

/// Clear all cached modules (for config reload)
/// This ensures require() returns fresh exports after reload
/// Critical for hot reload: modules are re-executed on next require()
pub fn clearAllModuleCache() void {
    if (global_config_ctx) |ctx| {
        // Iterate through all cached modules
        var iter = ctx.module_cache.iterator();
        while (iter.next()) |entry| {
            // Destroy Hermes value (the exports object)
            c.hermes_value_destroy(entry.value_ptr.exports);

            // Free the cache key (allocated in module_api.zig:322)
            ctx.allocator.free(entry.key_ptr.*);
        }

        // Clear HashMap but keep it ready for reuse
        // (unlike deinit(), this allows new modules to be cached after reload)
        ctx.module_cache.clearAndFree();
    }
}

// Re-export commonly used functions from modules for backwards compatibility
pub const processTimerQueue = timer_api.processQueue;
pub const processAnimationFrames = animation_api.processFrames;
pub const processFetchQueue = fetch_api.processQueue;
pub const clearAllTimers = timer_api.clearAll;
pub const deinitTimers = timer_api.deinit;
pub const deinitFetch = fetch_api.deinit;

/// Load plugin file (NO wrapper - assumes runtime.js already loaded)
/// Uses esbuild bundling to resolve imports (e.g., './src/index')
///
/// Cache invalidation strategy: DIRECTORY-BASED MTIME TRACKING
/// - Scans ALL .ts/.js files in plugin directory (recursively)
/// - Uses latest mtime across all source files as cache key
/// - Only bundles on cache miss (fast path: ~0.5ms stat calls vs ~10-50ms bundle)
///
/// This fixes the bug where editing src/cursor.ts wouldn't invalidate cache
/// because the old mtime-based caching only checked index.ts mtime.
pub fn loadPlugin(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Get cache directory from global state (initialized in main.zig)
    const cache_dir = global_cache_dir orelse return error.CacheNotInitialized;

    const esbuild = @import("../transpiler/esbuild.zig");
    const hermes = @import("../transpiler/hermes.zig");
    const cache = @import("../transpiler/cache.zig");

    // Expand ~ to home directory
    const expanded_path = if (std.mem.startsWith(u8, filepath, "~/")) blk: {
        const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
        break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, filepath[1..] });
    } else try allocator.dupe(u8, filepath);
    defer allocator.free(expanded_path);

    // STEP 1: Get plugin directory (parent of index.ts)
    const plugin_dir = std.fs.path.dirname(expanded_path) orelse {
        std.log.err("Cannot determine plugin directory for: {s}", .{filepath});
        return error.InvalidPath;
    };

    // STEP 2: Scan ALL source files in plugin directory and find latest mtime
    // This ensures cache invalidates when ANY .ts/.js file changes
    const latest_mtime: i128 = blk: {
        if (getLatestMtimeInDir(plugin_dir, allocator)) |mtime_opt| {
            if (mtime_opt) |mtime| {
                break :blk mtime;
            }
        } else |err| {
            std.log.warn("Failed to scan plugin directory {s}: {}, falling back to index.ts mtime", .{ plugin_dir, err });
        }
        // Fallback: use index.ts mtime only
        const stat = std.fs.cwd().statFile(expanded_path) catch {
            return error.PathNotFound;
        };
        break :blk stat.mtime;
    };

    // STEP 3: Compute cache key from path + latest mtime of ANY source file
    const path_hash = std.hash.Wyhash.hash(0, expanded_path);
    const cache_key = try std.fmt.allocPrint(allocator, "{x:0>16}_{d}", .{ path_hash, latest_mtime });
    defer allocator.free(cache_key);

    const cache_path = try std.fmt.allocPrint(allocator, "{s}/{s}.hbc", .{ cache_dir, cache_key });
    defer allocator.free(cache_path);

    // STEP 4: Try to load from cache (FAST PATH: ~0.5ms)
    // Cache hit means: same path + no source file changed since last bundle
    if (cache.loadFromCache(allocator, cache_path)) |bytecode| {
        defer allocator.free(bytecode);
        global_cache_stats.recordHit();
        const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);
        if (result == null) {
            const err_msg = c.hermes_get_exception_message(runtime);
            std.debug.print("[JSI] Plugin error: {s}\n", .{err_msg});
            return error.JSError;
        }
        defer c.hermes_value_destroy(result);
        return;
    } else |_| {
        // Cache miss - need to bundle and compile
    }

    // STEP 5: Cache miss - bundle plugin with esbuild (~10-50ms)
    const bundled_js = esbuild.buildWithCacheDir(allocator, expanded_path, cache_dir) catch |err| {
        std.log.err("esbuild bundle failed for plugin {s}: {}", .{ filepath, err });
        return error.TranspileFailed;
    };
    defer allocator.free(bundled_js);

    // STEP 6: Compile bundled JS to Hermes bytecode
    const bytecode = hermes.compile(allocator, bundled_js) catch |err| {
        std.log.err("Hermes compilation failed for plugin {s}: {}", .{ filepath, err });
        return error.CompileFailed;
    };
    defer allocator.free(bytecode);

    // STEP 7: Save to cache
    cache.saveToCache(cache_path, bytecode) catch {};
    global_cache_stats.recordMiss(bytecode.len);

    // STEP 8: Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[JSI] Plugin error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
}

/// Directories to exclude from mtime scanning (common build outputs, dependencies)
const EXCLUDED_DIRS = [_][]const u8{ "node_modules", ".git", "dist", "build", "target", "zig-out", "zig-cache" };

/// Check if path contains any excluded directory
fn isExcludedPath(path: []const u8) bool {
    for (EXCLUDED_DIRS) |excluded| {
        if (std.mem.indexOf(u8, path, excluded) != null) return true;
    }
    return false;
}

/// Scan directory recursively for .ts/.js files and return latest mtime
/// Returns null if no source files found
fn getLatestMtimeInDir(dir_path: []const u8, allocator: std.mem.Allocator) !?i128 {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        return err;
    };
    defer dir.close();

    var latest_mtime: ?i128 = null;

    // Use passed allocator (proper memory management, cleaned up by caller's arena)
    var walker = dir.walk(allocator) catch |err| {
        return err;
    };
    defer walker.deinit();

    while (walker.next() catch null) |entry| {
        // Fast rejection: skip non-files first
        if (entry.kind != .file) continue;

        // Skip excluded directories (node_modules, .git, build outputs)
        if (isExcludedPath(entry.path)) continue;

        // Only check .ts, .tsx, .js, .jsx files
        const ext = std.fs.path.extension(entry.basename);
        const is_source = std.mem.eql(u8, ext, ".ts") or
            std.mem.eql(u8, ext, ".tsx") or
            std.mem.eql(u8, ext, ".js") or
            std.mem.eql(u8, ext, ".jsx");

        if (!is_source) continue;

        // Get file mtime
        const stat = entry.dir.statFile(entry.basename) catch continue;

        if (latest_mtime == null or stat.mtime > latest_mtime.?) {
            latest_mtime = stat.mtime;
        }
    }

    return latest_mtime;
}

/// Load config file (WITH runtime.js wrapper for vim.* globals)
/// Uses new transpiler system for TypeScript support and WyHash caching
/// Bundles dependencies using esbuild.build() to support imports
pub fn loadConfig(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Get cache directory from global state
    const cache_dir = global_cache_dir orelse return error.CacheNotInitialized;

    // Load runtime wrapper (provides vim.* globals)
    // runtime_js is generated from runtime.ts by esbuild at build time (see build/runtime.zig)
    const runtime_wrapper = @embedFile("runtime_js");

    // Setup loader config
    const loader_config = transpiler.LoaderConfig{
        .cache_dir = cache_dir,
        .enable_cache = true,
        .stats = &global_cache_stats,
    };

    // Bundle config with dependencies + wrap with runtime.js
    // This uses esbuild.build() to resolve imports, then wraps the bundle
    const bytecode = transpiler.loadConfigWithBundle(
        allocator,
        loader_config,
        filepath,
        runtime_wrapper,
    ) catch |err| {
        // Log transpile error to stderr (safe, doesn't require JS runtime)
        // Note: Can't use console.log here because runtime.js hasn't loaded yet
        const err_msg = switch (err) {
            error.TranspileFailed => "Config transpile failed. Check for invalid imports (use global LastStatus, not 'import from ./vim')",
            error.CompileFailed => "Hermes compilation failed. Check JavaScript syntax.",
            error.PathNotFound => "Config file not found",
            error.PathTraversal => "Security: path traversal detected",
            error.InvalidPath => "Invalid config path",
            else => "Unknown config loading error",
        };
        std.log.err("[Vimcraft] {s}: {s}", .{ err_msg, filepath });
        return err;
    };
    defer allocator.free(bytecode);

    // Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        // Log JavaScript error to stderr (safe fallback)
        std.log.err("[Vimcraft] JS Error in {s}: {s}", .{ filepath, err_msg });
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
}
