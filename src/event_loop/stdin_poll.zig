const std = @import("std");
const libuv = @import("libuv.zig");
const uv = libuv.uv;

/// Callback type for when stdin has data available
pub const StdinCallback = *const fn () void;

/// Stdin poll handle
var poll_handle: uv.uv_poll_t = undefined;
var poll_initialized = false;
var stdin_callback: ?StdinCallback = null;

/// libuv callback when stdin is readable
fn onStdinReadable(handle: *uv.uv_poll_t, status: c_int, events: c_int) callconv(.C) void {
    _ = handle;

    if (status < 0) {
        // Error occurred
        return;
    }

    if (events & uv.UV_READABLE != 0) {
        // Stdin has data available
        if (stdin_callback) |callback| {
            callback();
        }
    }
}

/// Initialize stdin polling
pub fn init(callback: StdinCallback) !void {
    const loop = libuv.getLoop() orelse return error.EventLoopNotInitialized;

    if (poll_initialized) {
        return; // Already initialized
    }

    stdin_callback = callback;

    // Get stdin file descriptor
    const stdin_fd = std.fs.File.stdin().handle;

    // Initialize poll handle for stdin
    const result = uv.uv_poll_init(loop, &poll_handle, stdin_fd);
    if (result != 0) {
        return error.PollInitFailed;
    }

    poll_initialized = true;
}

/// Start polling stdin for read events
pub fn start() !void {
    if (!poll_initialized) {
        return error.NotInitialized;
    }

    const result = uv.uv_poll_start(&poll_handle, uv.UV_READABLE, onStdinReadable);
    if (result != 0) {
        return error.PollStartFailed;
    }
}

/// Stop polling stdin
pub fn stop() void {
    if (poll_initialized) {
        _ = uv.uv_poll_stop(&poll_handle);
    }
}

/// Cleanup stdin poll handle
pub fn deinit() void {
    if (poll_initialized) {
        stop();
        poll_initialized = false;
        stdin_callback = null;
    }
}
