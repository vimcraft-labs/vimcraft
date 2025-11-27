/// Manual libuv bindings for async subprocess support
/// These avoid @cImport circular type issues with uv_stream_t ↔ uv_read_cb
///
/// Only includes types needed for process spawning with stdio pipes.
/// For other libuv operations, use the existing libuv.zig with @cImport.
const std = @import("std");

// ============================================================================
// Type definitions
// All types are opaque to avoid Zig 0.15 @cImport circular dependency issues
// with uv_stream_t <-> uv_read_cb
// ============================================================================

/// Opaque libuv loop type
pub const uv_loop_t = anyopaque;

/// Opaque libuv handle type (base class)
pub const uv_handle_t = anyopaque;

/// Opaque libuv stream type (base for pipe, tcp, tty)
pub const uv_stream_t = anyopaque;

/// Opaque libuv pipe type
pub const uv_pipe_t = anyopaque;

/// Opaque libuv process type
pub const uv_process_t = anyopaque;

/// Opaque write request type
pub const uv_write_t = anyopaque;

/// Opaque timer type
pub const uv_timer_t = anyopaque;

// ============================================================================
// Callback Types
// ============================================================================

/// Exit callback: called when process exits
/// void (*uv_exit_cb)(uv_process_t*, int64_t exit_status, int term_signal)
pub const uv_exit_cb = ?*const fn (?*uv_process_t, i64, c_int) callconv(.c) void;

/// Alloc callback: allocates buffer for reading
/// void (*uv_alloc_cb)(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf)
pub const uv_alloc_cb = ?*const fn (?*uv_handle_t, usize, *uv_buf_t) callconv(.c) void;

/// Read callback: called when data is read
/// void (*uv_read_cb)(uv_stream_t* stream, ssize_t nread, const uv_buf_t* buf)
pub const uv_read_cb = ?*const fn (?*uv_stream_t, isize, *const uv_buf_t) callconv(.c) void;

/// Write callback: called when write completes
/// void (*uv_write_cb)(uv_write_t* req, int status)
pub const uv_write_cb = ?*const fn (?*uv_write_t, c_int) callconv(.c) void;

/// Close callback: called when handle is closed
/// void (*uv_close_cb)(uv_handle_t* handle)
pub const uv_close_cb = ?*const fn (?*uv_handle_t) callconv(.c) void;

/// Timer callback: called when timer fires
/// void (*uv_timer_cb)(uv_timer_t* handle)
pub const uv_timer_cb = ?*const fn (?*uv_timer_t) callconv(.c) void;

// ============================================================================
// Buffer Type
// ============================================================================

/// uv_buf_t - buffer descriptor
pub const uv_buf_t = extern struct {
    base: [*]u8,
    len: usize,
};

/// Create a uv_buf_t from a slice
pub fn uv_buf_init(base: [*]u8, len: usize) uv_buf_t {
    return .{ .base = base, .len = len };
}

// ============================================================================
// stdio Flags and Container
// ============================================================================

/// stdio flags for uv_spawn
pub const UV_IGNORE: c_uint = 0x00;
pub const UV_CREATE_PIPE: c_uint = 0x01;
pub const UV_INHERIT_FD: c_uint = 0x02;
pub const UV_INHERIT_STREAM: c_uint = 0x04;
pub const UV_READABLE_PIPE: c_uint = 0x10;
pub const UV_WRITABLE_PIPE: c_uint = 0x20;
pub const UV_NONBLOCK_PIPE: c_uint = 0x40;

/// stdio container for process options
pub const uv_stdio_container_t = extern struct {
    flags: c_uint,
    data: extern union {
        stream: ?*uv_stream_t,
        fd: c_int,
    },
};

// ============================================================================
// Process Options
// ============================================================================

/// Process spawn options
pub const uv_process_options_t = extern struct {
    exit_cb: uv_exit_cb,
    file: [*:0]const u8,
    args: [*:null]const ?[*:0]const u8,
    env: ?[*:null]const ?[*:0]const u8,
    cwd: ?[*:0]const u8,
    flags: c_uint,
    stdio_count: c_int,
    stdio: [*]uv_stdio_container_t,
    uid: c_uint, // uv_uid_t
    gid: c_uint, // uv_gid_t
};

// ============================================================================
// Handle Sizes (for allocation)
// These are platform-specific, using generous sizes that work everywhere
// ============================================================================

/// Size of uv_pipe_t handle (platform max ~304 bytes, use 512 for safety)
pub const UV_PIPE_SIZE: usize = 512;

/// Size of uv_process_t handle (platform max ~136 bytes, use 256 for safety)
pub const UV_PROCESS_SIZE: usize = 256;

/// Size of uv_write_t request (platform max ~192 bytes, use 256 for safety)
pub const UV_WRITE_SIZE: usize = 256;

/// Size of uv_timer_t handle (platform max ~152 bytes, use 256 for safety)
pub const UV_TIMER_SIZE: usize = 256;

// ============================================================================
// Process Flags
// ============================================================================

/// UV_PROCESS_DETACHED - Spawn the child process in a detached state.
/// This makes it a process group leader, enabling it to keep running after
/// the parent exits. Note: the child process will still keep the parent's
/// event loop alive unless the parent calls uv_unref() on the child's handle.
pub const UV_PROCESS_DETACHED: c_uint = 1 << 3; // (1 << 3) = 8

// ============================================================================
// External Function Declarations (using libuv C ABI)
// ============================================================================

extern "c" fn uv_pipe_init(loop: ?*uv_loop_t, handle: ?*uv_pipe_t, ipc: c_int) c_int;
extern "c" fn uv_pipe_open(handle: ?*uv_pipe_t, file: c_int) c_int;

extern "c" fn uv_spawn(
    loop: ?*uv_loop_t,
    handle: ?*uv_process_t,
    options: *const uv_process_options_t,
) c_int;

extern "c" fn uv_process_kill(handle: ?*uv_process_t, signum: c_int) c_int;
extern "c" fn uv_process_get_pid(handle: ?*const uv_process_t) c_int;

extern "c" fn uv_read_start(
    stream: ?*uv_stream_t,
    alloc_cb: uv_alloc_cb,
    read_cb: uv_read_cb,
) c_int;

extern "c" fn uv_read_stop(stream: ?*uv_stream_t) c_int;

extern "c" fn uv_write(
    req: ?*uv_write_t,
    handle: ?*uv_stream_t,
    bufs: [*]const uv_buf_t,
    nbufs: c_uint,
    cb: uv_write_cb,
) c_int;

extern "c" fn uv_close(handle: ?*uv_handle_t, close_cb: uv_close_cb) void;

extern "c" fn uv_is_closing(handle: ?*const uv_handle_t) c_int;

extern "c" fn uv_handle_set_data(handle: ?*uv_handle_t, data: ?*anyopaque) void;
extern "c" fn uv_handle_get_data(handle: ?*const uv_handle_t) ?*anyopaque;

extern "c" fn uv_req_set_data(req: ?*anyopaque, data: ?*anyopaque) void;
extern "c" fn uv_req_get_data(req: ?*const anyopaque) ?*anyopaque;

// Timer functions
extern "c" fn uv_timer_init(loop: ?*uv_loop_t, handle: ?*uv_timer_t) c_int;
extern "c" fn uv_timer_start(handle: ?*uv_timer_t, cb: uv_timer_cb, timeout: u64, repeat: u64) c_int;
extern "c" fn uv_timer_stop(handle: ?*uv_timer_t) c_int;

// Handle reference counting (for detached processes)
extern "c" fn uv_unref(handle: ?*uv_handle_t) void;

/// uv_run_mode constants
pub const UV_RUN_DEFAULT: c_uint = 0;
pub const UV_RUN_ONCE: c_uint = 1;
pub const UV_RUN_NOWAIT: c_uint = 2;

/// Run the event loop
pub extern "c" fn uv_run(loop: ?*uv_loop_t, mode: c_uint) c_int;

// ============================================================================
// Public API Wrappers
// ============================================================================

/// Initialize a pipe handle
pub fn pipeInit(loop: ?*uv_loop_t, handle: ?*uv_pipe_t, ipc: bool) !void {
    const result = uv_pipe_init(loop, handle, if (ipc) 1 else 0);
    if (result < 0) return error.PipeInitFailed;
}

/// Spawn a process
pub fn spawn(
    loop: ?*uv_loop_t,
    handle: ?*uv_process_t,
    options: *const uv_process_options_t,
) !void {
    const result = uv_spawn(loop, handle, options);
    if (result < 0) return error.SpawnFailed;
}

/// Kill a process
pub fn processKill(handle: ?*uv_process_t, signum: c_int) !void {
    const result = uv_process_kill(handle, signum);
    if (result < 0) return error.KillFailed;
}

/// Get process PID
pub fn getProcessPid(handle: ?*const uv_process_t) c_int {
    return uv_process_get_pid(handle);
}

/// Start reading from a stream
pub fn readStart(
    stream: ?*uv_stream_t,
    alloc_cb: uv_alloc_cb,
    read_cb: uv_read_cb,
) !void {
    const result = uv_read_start(stream, alloc_cb, read_cb);
    if (result < 0) return error.ReadStartFailed;
}

/// Stop reading from a stream
pub fn readStop(stream: ?*uv_stream_t) !void {
    const result = uv_read_stop(stream);
    if (result < 0) return error.ReadStopFailed;
}

/// Write to a stream
pub fn write(
    req: ?*uv_write_t,
    handle: ?*uv_stream_t,
    bufs: []const uv_buf_t,
    cb: uv_write_cb,
) !void {
    const result = uv_write(req, handle, bufs.ptr, @intCast(bufs.len), cb);
    if (result < 0) return error.WriteFailed;
}

/// Close a handle
pub fn close(handle: ?*uv_handle_t, close_cb: uv_close_cb) void {
    uv_close(handle, close_cb);
}

/// Check if handle is closing
pub fn isClosing(handle: ?*const uv_handle_t) bool {
    return uv_is_closing(handle) != 0;
}

/// Set handle data
pub fn setHandleData(handle: ?*uv_handle_t, data: ?*anyopaque) void {
    uv_handle_set_data(handle, data);
}

/// Get handle data
pub fn getHandleData(handle: ?*const uv_handle_t) ?*anyopaque {
    return uv_handle_get_data(handle);
}

/// Set request data
pub fn setReqData(req: ?*anyopaque, data: ?*anyopaque) void {
    uv_req_set_data(req, data);
}

/// Get request data
pub fn getReqData(req: ?*const anyopaque) ?*anyopaque {
    return uv_req_get_data(req);
}

/// Initialize a timer handle
pub fn timerInit(loop: ?*uv_loop_t, handle: ?*uv_timer_t) !void {
    const result = uv_timer_init(loop, handle);
    if (result < 0) return error.TimerInitFailed;
}

/// Start a timer
pub fn timerStart(handle: ?*uv_timer_t, cb: uv_timer_cb, timeout: u64, repeat: u64) !void {
    const result = uv_timer_start(handle, cb, timeout, repeat);
    if (result < 0) return error.TimerStartFailed;
}

/// Stop a timer
pub fn timerStop(handle: ?*uv_timer_t) !void {
    const result = uv_timer_stop(handle);
    if (result < 0) return error.TimerStopFailed;
}

/// Unref a handle (allows event loop to exit even if handle is active)
pub fn unref(handle: ?*uv_handle_t) void {
    uv_unref(handle);
}

// ============================================================================
// Allocated Handle Types
// These include storage for the opaque libuv handles
// ============================================================================

/// Pipe handle with embedded storage
pub const PipeHandle = struct {
    /// Raw libuv handle storage (must be zeroed for libuv)
    storage: [UV_PIPE_SIZE]u8 align(8) = std.mem.zeroes([UV_PIPE_SIZE]u8),

    /// Get pointer to the libuv handle
    pub fn ptr(self: *PipeHandle) *uv_pipe_t {
        return @ptrCast(&self.storage);
    }

    /// Get as stream pointer (for read/write)
    pub fn stream(self: *PipeHandle) *uv_stream_t {
        return @ptrCast(&self.storage);
    }

    /// Get as generic handle pointer (for close)
    pub fn handle(self: *PipeHandle) *uv_handle_t {
        return @ptrCast(&self.storage);
    }
};

/// Process handle with embedded storage
pub const ProcessHandle = struct {
    /// Raw libuv handle storage (must be zeroed for libuv)
    storage: [UV_PROCESS_SIZE]u8 align(8) = std.mem.zeroes([UV_PROCESS_SIZE]u8),

    /// Get pointer to the libuv handle
    pub fn ptr(self: *ProcessHandle) *uv_process_t {
        return @ptrCast(&self.storage);
    }

    /// Get as generic handle pointer (for close)
    pub fn handle(self: *ProcessHandle) *uv_handle_t {
        return @ptrCast(&self.storage);
    }
};

/// Write request with embedded storage
pub const WriteRequest = struct {
    /// Raw libuv request storage (must be zeroed for libuv)
    storage: [UV_WRITE_SIZE]u8 align(8) = std.mem.zeroes([UV_WRITE_SIZE]u8),

    /// Get pointer to the libuv request
    pub fn ptr(self: *WriteRequest) *uv_write_t {
        return @ptrCast(&self.storage);
    }
};

/// Timer handle with embedded storage
pub const TimerHandle = struct {
    /// Raw libuv handle storage (must be zeroed for libuv)
    storage: [UV_TIMER_SIZE]u8 align(8) = std.mem.zeroes([UV_TIMER_SIZE]u8),

    /// Get pointer to the libuv timer handle
    pub fn ptr(self: *TimerHandle) *uv_timer_t {
        return @ptrCast(&self.storage);
    }

    /// Get as generic handle pointer (for close/unref)
    pub fn handle(self: *TimerHandle) *uv_handle_t {
        return @ptrCast(&self.storage);
    }
};
