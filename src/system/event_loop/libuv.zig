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
    if (loop) |l| {
        // First, close all active handles
        uv.uv_walk(l, closeAllHandlesCallback, null);

        // Run the loop until all handles are closed
        // UV_RUN_DEFAULT will block until no more active handles
        var iterations: u32 = 0;
        while (uv.uv_loop_alive(l) != 0 and iterations < 1000) : (iterations += 1) {
            _ = uv.uv_run(l, uv.UV_RUN_NOWAIT);
        }

        // Now safe to close the loop
        _ = uv.uv_loop_close(l);
        loop = null;
    }
}

/// Check if loop is alive (has active handles)
pub fn isAlive() bool {
    if (loop) |l| {
        return uv.uv_loop_alive(l) != 0;
    }
    return false;
}
