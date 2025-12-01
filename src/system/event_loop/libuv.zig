const std = @import("std");

// Import libuv C API
pub const uv = @cImport({
    @cInclude("uv.h");
});

/// Global libuv event loop
var loop: ?*uv.uv_loop_t = null;

/// Initialize the libuv event loop
pub fn init() !void {
    if (loop != null) return; // Already initialized

    loop = uv.uv_default_loop();
    if (loop == null) {
        return error.LibuvInitFailed;
    }
}

/// Get the global event loop
pub fn getLoop() ?*uv.uv_loop_t {
    return loop;
}

/// Run the event loop (non-blocking)
/// Returns true if there are active handles/requests
pub fn runOnce() bool {
    if (loop == null) return false;

    // CRITICAL: Update libuv's cached time before running
    // Without this, timers scheduled with delay=0 may not fire promptly
    // because libuv compares against its cached "now" time.
    // This enables setTimeout(0) to fire on the next runOnce() call.
    uv.uv_update_time(loop);

    const result = uv.uv_run(loop, uv.UV_RUN_NOWAIT);
    return result != 0;
}

/// Run the event loop (blocking until timeout or event)
/// timeout_ms: milliseconds to wait, or null for no timeout
pub fn runWithTimeout(timeout_ms: ?i32) void {
    if (loop == null) return;

    if (timeout_ms) |ms| {
        // Use uv_run with UV_RUN_ONCE which will block until at least one event
        // The timeout will be handled by timer subsystem
        _ = uv.uv_run(loop, uv.UV_RUN_ONCE);
        _ = ms; // Timeout handled by uv_timer_t
    } else {
        _ = uv.uv_run(loop, uv.UV_RUN_NOWAIT);
    }
}

/// Stop the event loop
pub fn stop() void {
    if (loop) |l| {
        uv.uv_stop(l);
    }
}

/// Callback for uv_walk to close all handles
fn closeAllHandlesCallback(handle: [*c]uv.uv_handle_t, _: ?*anyopaque) callconv(.c) void {
    if (handle != null and uv.uv_is_closing(handle) == 0) {
        uv.uv_close(handle, null);
    }
}

/// Clean up and close the event loop
/// Properly closes all handles before calling uv_loop_close
pub fn deinit() void {
    // CRITICAL: When using uv_default_loop(), we should do NOTHING during cleanup.
    // The default loop is a static singleton managed by libuv itself.
    // All handles are owned by their respective subsystems (ConfigWatcher, timers, etc.)
    // which close them when they deinit. We must not interfere with this process.
    //
    // Attempting to:
    // - uv_walk() and close handles → use-after-free segfault
    // - uv_loop_close() the default loop → corrupts singleton state
    // - uv_run() during shutdown → crashes if handles are in inconsistent state
    //
    // The correct pattern: Just set loop to null and let the OS clean up on exit.

    loop = null;
}

/// Check if loop is alive (has active handles)
pub fn isAlive() bool {
    if (loop) |l| {
        return uv.uv_loop_alive(l) != 0;
    }
    return false;
}
