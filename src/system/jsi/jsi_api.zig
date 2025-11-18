/// JSI API - Main Integration Module
/// Coordinates all JSI API modules and provides unified initialization
/// This file has been refactored from 1824 lines into 8 focused modules
const std = @import("std");
const highlights = @import("../../editor/config/highlights.zig");
const OptionsManager = @import("../../editor/config/options.zig").OptionsManager;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const Editor = @import("../../editor/editor.zig").Editor;

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
pub const loader = @import("loader.zig");

/// Context struct for host functions
pub const JSIContext = struct {
    config: *highlights.HighlightConfig,
    display: *Display,
};

/// Global state for cleanup
var global_config_ctx: ?*config_api.ConfigContext = null;
var global_motion_ctx: ?*motion_api.MotionContext = null;
var global_keymap_ctx: ?*keymap_api.KeymapContext = null;
var global_allocator: ?std.mem.Allocator = null;

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
                break :blk &editor_or_context.buffer;
            } else {
                break :blk &editor_or_context.buffer;
            }
        },
    };

    // Store for cleanup in deinitJSI()
    global_config_ctx = cfg_ctx;
    global_allocator = allocator;

    // Register configuration API (setHighlight, setOption, getOption)
    config_api.register(runtime, cfg_ctx);

    // Register console API (consoleLog)
    console_api.register(runtime);
    console_api.setEditor(editor_or_context);

    // Register timer API (setTimeout, setInterval, clearTimer)
    timer_api.register(runtime, allocator);

    // Register animation frame API (requestAnimationFrame)
    animation_api.register(runtime, allocator);

    // Register cursor API (getCursorPosition, setCursorRenderPosition, clearCursorRenderPosition)
    // Only register if we have an Editor (not EditorContext)
    const T = @TypeOf(editor_or_context);
    if (T == *Editor) {
        cursor_api.register(runtime, editor_or_context);

        // Register filetype API (vim.filetype.match)
        // Only register for Editor since it needs access to ts_loader
        filetype_api.register(runtime, editor_or_context);
    }

    // Register layer API (createLayer, renderVirtualText, setLayerOpacity, etc.)
    layer_api.register(runtime, display);

    // Register motion API (vim.motion.* functions)
    // Register for both Editor and EditorContext
    if (T == *Editor) {
        const motion_ctx = allocator.create(motion_api.MotionContext) catch @panic("Failed to allocate MotionContext");
        motion_ctx.* = motion_api.MotionContext{
            .buffer = &editor_or_context.buffer,
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
    global_allocator = null;
}

// Re-export commonly used functions from modules for backwards compatibility
pub const processTimerQueue = timer_api.processQueue;
pub const processAnimationFrames = animation_api.processFrames;
pub const clearAllTimers = timer_api.clearAll;
pub const deinitTimers = timer_api.deinit;
pub const loadPlugin = loader.loadPlugin;
pub const loadConfig = loader.loadConfig;
