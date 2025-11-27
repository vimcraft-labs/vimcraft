/// PTY (Pseudo-Terminal) support using POSIX forkpty() + libuv uv_poll_t
///
/// This module provides PTY spawning for interactive terminal programs (fzf, htop, shells).
/// Key differences from pipe-based spawn:
/// - Single bidirectional stream (stdin/stdout/stderr merged)
/// - Supports terminal resize via TIOCSWINSZ ioctl
/// - Programs see a real TTY (isatty() returns true)
///
/// Integration with libuv:
/// - Uses uv_poll_t to watch the PTY master fd for read/write events
/// - Callbacks run on the main thread during uv_run()
const std = @import("std");
const uv = @import("libuv_process.zig");

// ============================================================================
// POSIX PTY and ioctl imports
// ============================================================================

const builtin = @import("builtin");

// Platform-specific PTY header
const c_pty = switch (builtin.os.tag) {
    .macos => @cImport({
        @cInclude("util.h"); // forkpty on macOS
    }),
    else => @cImport({
        @cInclude("pty.h"); // forkpty on Linux
    }),
};

const c = @cImport({
    @cInclude("stdlib.h"); // setenv
    @cInclude("sys/ioctl.h"); // ioctl, TIOCSWINSZ
    @cInclude("termios.h"); // struct termios
    @cInclude("unistd.h"); // read, write, close
    @cInclude("signal.h"); // kill
    @cInclude("sys/wait.h"); // waitpid
    @cInclude("errno.h"); // errno
    @cInclude("fcntl.h"); // O_NONBLOCK
});

// ============================================================================
// libuv poll declarations
// ============================================================================

/// Opaque libuv poll type
pub const uv_poll_t = anyopaque;

/// Poll events
pub const UV_READABLE: c_uint = 1;
pub const UV_WRITABLE: c_uint = 2;
pub const UV_DISCONNECT: c_uint = 4;
pub const UV_PRIORITIZED: c_uint = 8;

/// Poll callback: void (*uv_poll_cb)(uv_poll_t* handle, int status, int events)
pub const uv_poll_cb = ?*const fn (?*uv_poll_t, c_int, c_int) callconv(.c) void;

/// Size of uv_poll_t handle (platform max ~176 bytes, use 256 for safety)
pub const UV_POLL_SIZE: usize = 256;

// External libuv functions for poll
extern "c" fn uv_poll_init(loop: ?*uv.uv_loop_t, handle: ?*uv_poll_t, fd: c_int) c_int;
extern "c" fn uv_poll_start(handle: ?*uv_poll_t, events: c_int, cb: uv_poll_cb) c_int;
extern "c" fn uv_poll_stop(handle: ?*uv_poll_t) c_int;

// ============================================================================
// PTY Handle Types
// ============================================================================

/// Poll handle with embedded storage
pub const PollHandle = struct {
    storage: [UV_POLL_SIZE]u8 align(8) = std.mem.zeroes([UV_POLL_SIZE]u8),

    pub fn ptr(self: *PollHandle) *uv_poll_t {
        return @ptrCast(&self.storage);
    }

    pub fn handle(self: *PollHandle) *uv.uv_handle_t {
        return @ptrCast(&self.storage);
    }
};

/// Window size structure for ioctl
pub const WinSize = extern struct {
    ws_row: c_ushort,
    ws_col: c_ushort,
    ws_xpixel: c_ushort = 0,
    ws_ypixel: c_ushort = 0,
};

// ============================================================================
// PTY Operations
// ============================================================================

/// Spawn a process in a PTY
/// Returns (master_fd, child_pid) on success
pub fn forkPty(
    rows: u16,
    cols: u16,
) !struct { master_fd: c_int, pid: c_int } {
    var master_fd: c_int = undefined;

    // Set up initial window size
    var ws = WinSize{
        .ws_row = rows,
        .ws_col = cols,
    };

    // Fork with PTY (use platform-specific c_pty import)
    const pid = c_pty.forkpty(&master_fd, null, null, @ptrCast(&ws));

    if (pid < 0) {
        return error.ForkPtyFailed;
    }

    return .{
        .master_fd = master_fd,
        .pid = pid,
    };
}

/// Execute a command in the child process (call after forkpty in child)
pub fn execCommand(
    cmd: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    env: ?[*:null]const ?[*:0]const u8,
    cwd: ?[*:0]const u8,
    term: [*:0]const u8,
) noreturn {
    // Change directory if specified
    if (cwd) |dir| {
        _ = c.chdir(dir);
    }

    // Set TERM environment variable
    _ = c.setenv("TERM", term, 1);

    // Cast to C-compatible types for execve/execvp
    const c_argv: [*c]const [*c]u8 = @ptrCast(@constCast(argv));

    // Execute
    if (env) |e| {
        const c_env: [*c]const [*c]u8 = @ptrCast(@constCast(e));
        _ = c.execve(cmd, c_argv, c_env);
    } else {
        _ = c.execvp(cmd, c_argv);
    }

    // If we get here, exec failed
    c._exit(127);
}

/// Resize a PTY
pub fn resizePty(master_fd: c_int, rows: u16, cols: u16) !void {
    var ws = WinSize{
        .ws_row = rows,
        .ws_col = cols,
    };

    const result = c.ioctl(master_fd, c.TIOCSWINSZ, &ws);
    if (result < 0) {
        return error.ResizeFailed;
    }
}

/// Read from PTY master fd (non-blocking)
pub fn readPty(master_fd: c_int, buf: []u8) !usize {
    const result = c.read(master_fd, buf.ptr, buf.len);
    if (result < 0) {
        // Cross-platform errno access
        const err = switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos => c.__error().*,
            else => c.__errno_location().*,
        };
        if (err == c.EAGAIN or err == c.EWOULDBLOCK) {
            return 0; // Would block, no data available
        }
        return error.ReadFailed;
    }
    return @intCast(result);
}

/// Write to PTY master fd
pub fn writePty(master_fd: c_int, data: []const u8) !usize {
    const result = c.write(master_fd, data.ptr, data.len);
    if (result < 0) {
        return error.WriteFailed;
    }
    return @intCast(result);
}

/// Close PTY master fd
pub fn closePty(master_fd: c_int) void {
    _ = c.close(master_fd);
}

/// Send signal to process
pub fn killProcess(pid: c_int, signal: c_int) !void {
    const result = c.kill(pid, signal);
    if (result < 0) {
        return error.KillFailed;
    }
}

/// Check if child process has exited (non-blocking)
/// Returns null if still running, or (exit_code, signal) if exited
pub fn checkChildExited(pid: c_int) ?struct { code: c_int, signal: c_int } {
    var status: c_int = 0;
    const result = c.waitpid(pid, &status, c.WNOHANG);

    if (result == 0) {
        // Child still running
        return null;
    }

    if (result < 0) {
        // Error or no child
        return .{ .code = -1, .signal = 0 };
    }

    // Child exited
    if (c.WIFEXITED(status)) {
        return .{ .code = c.WEXITSTATUS(status), .signal = 0 };
    } else if (c.WIFSIGNALED(status)) {
        return .{ .code = 128 + c.WTERMSIG(status), .signal = c.WTERMSIG(status) };
    }

    return .{ .code = -1, .signal = 0 };
}

// ============================================================================
// libuv Poll Wrappers
// ============================================================================

/// Initialize a poll handle for a file descriptor
pub fn pollInit(loop: ?*uv.uv_loop_t, handle: ?*uv_poll_t, fd: c_int) !void {
    const result = uv_poll_init(loop, handle, fd);
    if (result < 0) return error.PollInitFailed;
}

/// Start polling for events
pub fn pollStart(handle: ?*uv_poll_t, events: c_int, cb: uv_poll_cb) !void {
    const result = uv_poll_start(handle, events, cb);
    if (result < 0) return error.PollStartFailed;
}

/// Stop polling
pub fn pollStop(handle: ?*uv_poll_t) !void {
    const result = uv_poll_stop(handle);
    if (result < 0) return error.PollStopFailed;
}

// ============================================================================
// Helper: Set fd to non-blocking mode
// ============================================================================

pub fn setNonBlocking(fd: c_int) !void {
    const flags = c.fcntl(fd, c.F_GETFL);
    if (flags < 0) return error.FcntlFailed;

    const result = c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK);
    if (result < 0) return error.FcntlFailed;
}
