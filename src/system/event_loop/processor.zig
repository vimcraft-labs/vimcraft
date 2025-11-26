const std = @import("std");
const event_loop = @import("libuv.zig");
const jsi_api = @import("../jsi/jsi_api.zig");

/// Event loop processor that handles libuv events, timers, fetch, and animation frames
/// This eliminates code duplication across different run modes (editor, debugger, etc.)
///
/// Pattern:
/// 1. Run libuv event loop once (file watchers, network I/O, etc.)
/// 2. Process JavaScript timer queue (setTimeout/setInterval callbacks)
/// 3. Process async fetch queue (Promise resolution for fetch() calls)
/// 4. Process animation frame callbacks (requestAnimationFrame)
/// 5. Return whether rendering is needed
///
/// Usage:
/// ```zig
/// var processor = EventLoopProcessor.init(allocator);
/// while (running) {
///     const needs_render = processor.tick();
///     if (needs_render) {
///         // Render the display
///     }
/// }
/// ```
pub const EventLoopProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EventLoopProcessor {
        return .{ .allocator = allocator };
    }

    /// Process one iteration of the event loop
    /// Returns true if layers were modified and rendering is needed
    pub fn tick(self: *EventLoopProcessor) bool {
        // STEP 1: Run libuv event loop (timers, file watchers, network I/O)
        // This handles OS-level async operations (including fetch HTTP requests)
        _ = event_loop.runOnce();

        // STEP 2: Process JavaScript timer queue
        // This executes setTimeout/setInterval callbacks that are due
        // React Native pattern: JS manages callbacks, Zig triggers them on main thread
        // IMPORTANT: This must be AFTER libuv but BEFORE any rendering
        jsi_api.processTimerQueue(self.allocator);

        // STEP 3: Process async fetch queue
        // This delivers HTTP response results to JavaScript Promise callbacks
        // React Native pattern: native async work completes, results queued for main thread
        jsi_api.processFetchQueue(self.allocator);

        // STEP 4: Process animation frame callbacks
        // This executes requestAnimationFrame callbacks synchronized with render loop
        // React Native Reanimated pattern: 60fps synchronized animations
        // Returns true if any callbacks modified layer state
        const layers_modified = jsi_api.processAnimationFrames(self.allocator);

        return layers_modified;
    }
};
