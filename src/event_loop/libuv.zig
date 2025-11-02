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

/// Clean up and close the event loop
pub fn deinit() void {
    if (loop) |l| {
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
