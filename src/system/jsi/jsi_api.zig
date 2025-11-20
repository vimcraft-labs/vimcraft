/// JSI API - Main Integration Module
/// Coordinates all JSI API modules and provides unified initialization
/// This file has been refactored from 1824 lines into 8 focused modules
const std = @import("std");
const highlights = @import("../../editor/config/highlights.zig");
const OptionsManager = @import("../../editor/config/options.zig").OptionsManager;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const Editor = @import("../../editor/editor.zig").Editor;
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
pub const loader = @import("loader.zig");

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
pub var global_allocator: ?std.mem.Allocator = null;

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
                // Editor uses multi-buffer architecture - can't store static pointer
                // vim.bo won't work for Editor (needs refactoring to call getCurrentBuffer())
                break :blk null;
            } else {
                // EditorContext has single buffer field
                break :blk &editor_or_context.buffer;
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

    // Register cursor API (getCursorPosition)
    // Only register if we have an Editor (not EditorContext)
    const T = @TypeOf(editor_or_context);
    if (T == *Editor) {
        cursor_api.register(runtime, editor_or_context);
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
    layer_api.register(runtime, display);

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
    } else {
        // EditorContext - get viewport_top from display, no js_state_dirty (headless mode)
        const motion_ctx = allocator.create(motion_api.MotionContext) catch @panic("Failed to allocate MotionContext");
        motion_ctx.* = motion_api.MotionContext{
            .buffer = &editor_or_context.buffer,
            .viewport_top = &editor_or_context.display.viewport_top,
            .viewport_height = if (display) |d| d.terminal_rows - 1 else 24,
            .js_state_dirty = null, // EditorContext doesn't need dirty tracking
        };
        global_motion_ctx = motion_ctx;
        motion_api.register(runtime, motion_ctx);
    }

    // Register keymap API (vim.keymap.set/del)
    // Now register for both Editor and EditorContext (both have keymap_mgr)
    const keymap_ctx = keymap_api.KeymapContext.init(
        allocator,
        &editor_or_context.keymap_mgr,
        runtime,
    ) catch @panic("Failed to allocate KeymapContext");
    global_keymap_ctx = keymap_ctx;
    keymap_api.register(runtime, keymap_ctx);

    // Register event API (vim.on, vim.off, vim.emit) - Only for Editor (Phase 4 autocommands)
    // EditorContext doesn't need events (headless debug mode)
    if (T == *Editor) {
        const emitter = allocator.create(EventEmitter) catch @panic("Failed to allocate EventEmitter");
        emitter.* = EventEmitter.init(allocator, runtime);
        global_event_emitter = emitter;

        // Store in Editor for use by native code (buffer operations, mode changes)
        editor_or_context.event_emitter = emitter;

        // Register vim.on(), vim.off(), vim.emit() JavaScript API
        event_api.register(runtime, emitter);
    }

    // Register highlight API (vim.api.setHighlight, vim.api.getHighlight)
    // Both Editor and EditorContext have highlight_registry
    const hl_ctx = allocator.create(highlight_api.HighlightContext) catch @panic("Failed to allocate HighlightContext");
    hl_ctx.* = highlight_api.HighlightContext{
        .registry = &editor_or_context.highlight_registry,
        .allocator = allocator,
        .js_state_dirty = js_state_dirty_ptr,
    };
    global_highlight_ctx = hl_ctx;
    highlight_api.register(runtime, hl_ctx);

    // Register module API (require() - Phase 4)
    module_api.register(runtime, cfg_ctx);

    // Register metrics API (vim.metrics - performance tracking)
    metrics_api.register(runtime);

    // JSI functions registered (silent mode)
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
    // Clean up filetype context (no deinit needed, just free the struct)
    filetype_api.deinit();
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
pub const clearAllTimers = timer_api.clearAll;
pub const deinitTimers = timer_api.deinit;

/// Load plugin file (NO wrapper - assumes runtime.js already loaded)
/// Uses new transpiler system for TypeScript support and WyHash caching
pub fn loadPlugin(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Get cache directory from global state (initialized in main.zig)
    const cache_dir = global_cache_dir orelse return error.CacheNotInitialized;

    // Setup loader config
    const loader_config = transpiler.LoaderConfig{
        .cache_dir = cache_dir,
        .enable_cache = true,
        .stats = &global_cache_stats,
    };

    // Load module (transpile + compile + cache)
    const bytecode = try transpiler.loadModule(allocator, loader_config, filepath);
    defer allocator.free(bytecode);

    // Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[JSI] Plugin error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
}

/// Load config file (WITH runtime.js wrapper for vim.* globals)
/// Uses new transpiler system for TypeScript support and WyHash caching
/// Bundles dependencies using esbuild.build() to support imports
pub fn loadConfig(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Get cache directory from global state
    const cache_dir = global_cache_dir orelse return error.CacheNotInitialized;

    // Load runtime wrapper
    const runtime_wrapper = @embedFile("runtime.js");

    // Setup loader config
    const loader_config = transpiler.LoaderConfig{
        .cache_dir = cache_dir,
        .enable_cache = true,
        .stats = &global_cache_stats,
    };

    // Bundle config with dependencies + wrap with runtime.js
    // This uses esbuild.build() to resolve imports, then wraps the bundle
    const bytecode = try transpiler.loadConfigWithBundle(
        allocator,
        loader_config,
        filepath,
        runtime_wrapper,
    );
    defer allocator.free(bytecode);

    // Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[JSI] JavaScript error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
}
