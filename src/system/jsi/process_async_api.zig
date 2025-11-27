/// Async Process API for JavaScript plugins
/// Provides Node.js-style async subprocess spawning with stdio pipes
///
/// API:
/// - process.spawnAsync(cmd, args?, opts?) - Spawn persistent subprocess
/// - proc.stdin.write(data) - Write to stdin
/// - proc.onStdout(callback) - Handle stdout data
/// - proc.onStderr(callback) - Handle stderr data
/// - proc.onExit(callback) - Handle process exit
/// - proc.kill(signal?) - Kill process
///
/// Uses manual libuv bindings to avoid @cImport circular type issues.
/// See src/system/event_loop/libuv_process.zig for details.
///
/// THREADING MODEL:
/// ================
/// This module uses libuv's SINGLE-THREADED event loop model. All callbacks
/// (exit, read, write, close) run on the main thread during uv_run().
/// There is NO concurrent access from multiple threads.
///
/// The mutexes (registry_mutex, pool_mutex) exist for:
/// 1. Defensive coding / future-proofing
/// 2. Clarity about which data structures are shared state
/// 3. Potential future JS worker thread support
///
/// Key implications:
/// - Callbacks cannot race with each other (they run sequentially)
/// - A callback cannot interrupt another callback mid-execution
/// - State changes made in one callback are immediately visible to subsequent callbacks
/// - No TOCTOU races possible within a single uv_run() iteration
const std = @import("std");
const c = @import("c_api.zig").c;
const uv = @import("../event_loop/libuv_process.zig");
const event_loop = @import("../event_loop/libuv.zig");
const debug_log = @import("../../backends/headless/log.zig");

// ============================================================================
// Configuration
// ============================================================================

/// Maximum concurrent async processes
const MAX_ASYNC_PROCESSES: usize = 32;

/// Maximum output buffer size per read (64KB)
const READ_BUFFER_SIZE: usize = 64 * 1024;

/// Maximum pending writes per process
const MAX_PENDING_WRITES: usize = 16;

/// Maximum environment variables allowed
const MAX_ENV_VARS: usize = 256;

// ============================================================================
// Context
// ============================================================================

pub const AsyncProcessContext = struct {
    allocator: std.mem.Allocator,
    runtime: ?*c.OVHermesRuntime = null,
};

var global_ctx: ?*AsyncProcessContext = null;
var process_id_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(1);

// ============================================================================
// Process State
// ============================================================================

/// State for a single async process
const AsyncProcess = struct {
    id: usize,
    allocator: std.mem.Allocator,

    // libuv handles (with embedded storage)
    process: uv.ProcessHandle = .{},
    stdin_pipe: uv.PipeHandle = .{},
    stdout_pipe: uv.PipeHandle = .{},
    stderr_pipe: uv.PipeHandle = .{},
    timeout_timer: uv.TimerHandle = .{},

    // Process info
    pid: c_int = -1,
    exited: bool = false,
    exit_code: i64 = 0,
    exit_signal: c_int = 0,

    // stdin state - tracks whether stdin pipe was initialized
    // When stdin: 'null' is used, stdin_enabled is false and writes should fail
    stdin_enabled: bool = true,

    // Timeout/detach options
    timeout_ms: ?u64 = null,
    timeout_active: bool = false,
    timed_out: bool = false,
    detached: bool = false,

    // Buffered output mode - collect all output until EOF
    stdout_buffered: bool = false,
    stderr_buffered: bool = false,
    stdout_collected: std.ArrayList(u8) = undefined,
    stderr_collected: std.ArrayList(u8) = undefined,

    // Handle close tracking
    handles_to_close: u8 = 0,
    handles_closed: u8 = 0,

    // Read buffers (reusable)
    stdout_buffer: [READ_BUFFER_SIZE]u8 = undefined,
    stderr_buffer: [READ_BUFFER_SIZE]u8 = undefined,

    // Pending writes list
    pending_writes: std.ArrayList(*WriteData) = undefined,

    /// Initialize the process state
    pub fn init(allocator: std.mem.Allocator, id: usize) AsyncProcess {
        return .{
            .id = id,
            .allocator = allocator,
            .pending_writes = .{},
            .stdout_collected = .{},
            .stderr_collected = .{},
        };
    }

    /// Cleanup resources
    /// FIX #13: Clear request data before freeing to prevent writeCallback
    /// from accessing freed memory if it runs after deinit
    pub fn deinit(self: *AsyncProcess) void {
        // Free any pending writes
        for (self.pending_writes.items) |write_data| {
            // Clear request data so writeCallback sees null and returns early
            uv.setReqData(@ptrCast(write_data.request.ptr()), null);
            self.allocator.free(write_data.data);
            self.allocator.destroy(write_data);
        }
        self.pending_writes.deinit(self.allocator);

        // Free collected output buffers
        self.stdout_collected.deinit(self.allocator);
        self.stderr_collected.deinit(self.allocator);
    }
};

/// Data for a write operation
const WriteData = struct {
    process: *AsyncProcess,
    request: uv.WriteRequest = .{},
    data: []u8,
    buf: uv.uv_buf_t = undefined,
};

// ============================================================================
// Process Registry
// ============================================================================

var process_registry: std.AutoHashMap(usize, *AsyncProcess) = undefined;
var registry_mutex: std.Thread.Mutex = .{};
var registry_initialized: bool = false;

// Process pool - reuse process memory instead of freeing to avoid use-after-free
// libuv maintains internal handle lists that may still reference closed handles
// even after close callbacks complete. By keeping memory alive and reusing it,
// we avoid both use-after-free and unbounded memory growth.
var free_process_pool: std.ArrayList(*AsyncProcess) = undefined;
var pool_mutex: std.Thread.Mutex = .{};
var pool_initialized: bool = false;
var pool_allocator: std.mem.Allocator = undefined;

/// Maximum number of processes to keep in pool (prevents memory bloat)
const MAX_POOL_SIZE: usize = 8;

fn initRegistry(allocator: std.mem.Allocator) void {
    if (registry_initialized) return;
    process_registry = std.AutoHashMap(usize, *AsyncProcess).init(allocator);
    registry_initialized = true;

    if (!pool_initialized) {
        // In Zig 0.15, ArrayList is unmanaged - just initialize empty
        // and pass allocator to methods like append()
        free_process_pool = .{};
        pool_allocator = allocator;
        pool_initialized = true;
    }
}

/// Get a process from the pool or allocate a new one
/// Thread-safe: uses pool_mutex for synchronization
fn getOrCreateProcess(allocator: std.mem.Allocator, id: usize) !*AsyncProcess {
    // Try to get from pool first (thread-safe)
    if (pool_initialized) {
        pool_mutex.lock();
        defer pool_mutex.unlock();

        if (free_process_pool.items.len > 0) {
            const proc = free_process_pool.items[free_process_pool.items.len - 1];
            free_process_pool.items.len -= 1;
            // Reset the process for reuse
            proc.* = AsyncProcess.init(allocator, id);
            debug_log.log("[ASYNC_PROC] Reusing process from pool, pool size now: {d}", .{
                free_process_pool.items.len,
            });
            return proc;
        }
    }

    // Allocate new process (outside lock - allocation can be slow)
    const proc = try allocator.create(AsyncProcess);
    proc.* = AsyncProcess.init(allocator, id);
    return proc;
}

/// Return a process to the pool for reuse
/// Thread-safe: uses pool_mutex for synchronization
fn returnToPool(proc: *AsyncProcess) void {
    // Clean up any pending writes first (outside lock)
    proc.deinit();

    if (!pool_initialized) {
        // Pool not initialized - this shouldn't happen in normal usage
        debug_log.log("[ASYNC_PROC] Pool not initialized, freeing process memory", .{});
        proc.allocator.destroy(proc);
        return;
    }

    pool_mutex.lock();
    defer pool_mutex.unlock();

    // FIX #1: Check if this process is already anywhere in the pool
    // This prevents duplicate entries which could cause double-free
    for (free_process_pool.items) |existing| {
        if (existing == proc) {
            debug_log.log("[ASYNC_PROC] Process already in pool, skipping", .{});
            return;
        }
    }

    // If pool is full, free the oldest entry to make room
    if (free_process_pool.items.len >= MAX_POOL_SIZE) {
        const oldest = free_process_pool.orderedRemove(0);
        debug_log.log("[ASYNC_PROC] Pool full, freeing oldest entry", .{});
        oldest.allocator.destroy(oldest);
    }

    // Add to pool for reuse
    free_process_pool.append(pool_allocator, proc) catch {
        debug_log.log("[ASYNC_PROC] Failed to add to pool, freeing process", .{});
        // Can't add to pool - free the process to avoid leak
        proc.allocator.destroy(proc);
        return;
    };

    debug_log.log("[ASYNC_PROC] Returned process to pool, pool size now: {d}", .{
        free_process_pool.items.len,
    });
}

fn getProcess(id: usize) ?*AsyncProcess {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return process_registry.get(id);
}

fn registerProcess(proc: *AsyncProcess) !void {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    if (process_registry.count() >= MAX_ASYNC_PROCESSES) {
        return error.TooManyProcesses;
    }
    try process_registry.put(proc.id, proc);
}

fn unregisterProcess(id: usize) void {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    _ = process_registry.remove(id);
}

// ============================================================================
// libuv Callbacks
// ============================================================================

/// FIX #6: Dummy buffer for allocCallback when handle data is null
/// Using undefined pointer could cause issues if libuv validates the pointer
var dummy_alloc_buffer: [1]u8 = undefined;

/// Allocation callback for read operations
/// NOTE: This runs on the main thread because we use uv_run(UV_RUN_NOWAIT)
fn allocCallback(handle: ?*uv.uv_handle_t, suggested_size: usize, buf: *uv.uv_buf_t) callconv(.c) void {
    _ = suggested_size;

    const data = uv.getHandleData(handle);
    if (data == null) {
        // FIX #6: Use valid pointer instead of undefined
        buf.* = uv.uv_buf_init(&dummy_alloc_buffer, 0);
        return;
    }

    const proc: *AsyncProcess = @ptrCast(@alignCast(data));

    // Determine if this is stdout or stderr based on handle address
    const stdout_addr = @intFromPtr(proc.stdout_pipe.handle());
    const handle_addr = @intFromPtr(handle);

    if (handle_addr == stdout_addr) {
        buf.* = uv.uv_buf_init(&proc.stdout_buffer, proc.stdout_buffer.len);
    } else {
        buf.* = uv.uv_buf_init(&proc.stderr_buffer, proc.stderr_buffer.len);
    }
}

/// Read callback for stdout
fn stdoutReadCallback(stream: ?*uv.uv_stream_t, nread: isize, buf: *const uv.uv_buf_t) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(stream));
    if (data == null) return;

    const proc: *AsyncProcess = @ptrCast(@alignCast(data));

    if (nread > 0) {
        const chunk = buf.base[0..@intCast(nread)];
        if (proc.stdout_buffered) {
            // Buffered mode: accumulate data until EOF
            proc.stdout_collected.appendSlice(proc.allocator, chunk) catch {
                debug_log.log("[ASYNC_PROC] Failed to buffer stdout data", .{});
            };
        } else {
            // Streaming mode: deliver immediately to JavaScript
            deliverStdoutData(proc.id, chunk);
        }
    } else if (nread < 0) {
        // EOF or error - stop reading
        _ = uv.readStop(stream) catch {};
    }
}

/// Read callback for stderr
fn stderrReadCallback(stream: ?*uv.uv_stream_t, nread: isize, buf: *const uv.uv_buf_t) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(stream));
    if (data == null) return;

    const proc: *AsyncProcess = @ptrCast(@alignCast(data));

    if (nread > 0) {
        const chunk = buf.base[0..@intCast(nread)];
        if (proc.stderr_buffered) {
            // Buffered mode: accumulate data until EOF
            proc.stderr_collected.appendSlice(proc.allocator, chunk) catch {
                debug_log.log("[ASYNC_PROC] Failed to buffer stderr data", .{});
            };
        } else {
            // Streaming mode: deliver immediately to JavaScript
            deliverStderrData(proc.id, chunk);
        }
    } else if (nread < 0) {
        // EOF or error - stop reading
        _ = uv.readStop(stream) catch {};
    }
}

/// Exit callback when process terminates
fn exitCallback(handle: ?*uv.uv_process_t, exit_status: i64, term_signal: c_int) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(handle));
    if (data == null) return;

    const proc: *AsyncProcess = @ptrCast(@alignCast(data));

    proc.exited = true;

    // Handle timeout: set exit code to 124 (like Neovim's vim.system)
    var final_exit_code = exit_status;
    if (proc.timed_out and (exit_status == 0 or exit_status == 1 or term_signal != 0)) {
        final_exit_code = 124;
    }
    proc.exit_code = final_exit_code;
    proc.exit_signal = term_signal;

    debug_log.log("[ASYNC_PROC] Process {d} exited: code={d}, signal={d}, timed_out={}", .{
        proc.id,
        final_exit_code,
        term_signal,
        proc.timed_out,
    });

    // Stop reading from pipes
    _ = uv.readStop(proc.stdout_pipe.stream()) catch {};
    _ = uv.readStop(proc.stderr_pipe.stream()) catch {};

    // Deliver buffered output before exit event
    if (proc.stdout_buffered and proc.stdout_collected.items.len > 0) {
        deliverStdoutData(proc.id, proc.stdout_collected.items);
    }
    if (proc.stderr_buffered and proc.stderr_collected.items.len > 0) {
        deliverStderrData(proc.id, proc.stderr_collected.items);
    }

    // Deliver exit event to JavaScript
    deliverExitEvent(proc.id, final_exit_code, term_signal);

    // Close all handles
    closeProcessHandles(proc);
}

/// Write callback when write completes
fn writeCallback(req: ?*uv.uv_write_t, status: c_int) callconv(.c) void {
    const data = uv.getReqData(@ptrCast(req));
    if (data == null) return;

    const write_data: *WriteData = @ptrCast(@alignCast(data));
    const proc = write_data.process;

    if (status < 0) {
        debug_log.log("[ASYNC_PROC] Write failed for process {d}: status={d}", .{ proc.id, status });
    }

    // Remove from pending writes
    for (proc.pending_writes.items, 0..) |item, i| {
        if (item == write_data) {
            _ = proc.pending_writes.orderedRemove(i);
            break;
        }
    }

    // Free write data
    proc.allocator.free(write_data.data);
    proc.allocator.destroy(write_data);
}

/// Close callback for handles
fn closeCallback(handle: ?*uv.uv_handle_t) callconv(.c) void {
    const data = uv.getHandleData(handle);
    if (data == null) return;

    const proc: *AsyncProcess = @ptrCast(@alignCast(data));
    proc.handles_closed += 1;

    debug_log.log("[ASYNC_PROC] Handle closed for process {d}: {d}/{d}", .{
        proc.id,
        proc.handles_closed,
        proc.handles_to_close,
    });

    // All handles closed - return to pool for reuse
    // We don't free because libuv might still have stale pointers
    // to this handle in internal data structures
    if (proc.handles_closed >= proc.handles_to_close) {
        unregisterProcess(proc.id);
        returnToPool(proc);
    }
}

/// Timeout callback - kills process after timeout expires
fn timeoutCallback(timer: ?*uv.uv_timer_t) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(timer));
    if (data == null) return;

    const proc: *AsyncProcess = @ptrCast(@alignCast(data));

    if (proc.exited) {
        // Process already exited, just close the timer
        return;
    }

    debug_log.log("[ASYNC_PROC] Process {d} timed out after {?d}ms, sending SIGTERM", .{
        proc.id,
        proc.timeout_ms,
    });

    proc.timed_out = true;

    // Send SIGTERM first (allows graceful shutdown)
    uv.processKill(proc.process.ptr(), 15) catch {
        // If SIGTERM fails, try SIGKILL
        _ = uv.processKill(proc.process.ptr(), 9) catch {};
    };
}

/// Close all handles for a process
/// FIX #2: Only count handles that we're actually closing to avoid
/// premature pool return when some handles are already closing
fn closeProcessHandles(proc: *AsyncProcess) void {
    // Reset counters
    proc.handles_closed = 0;
    var expected_callbacks: u8 = 0;

    // Only close and count handles that aren't already closing
    if (!uv.isClosing(proc.process.handle())) {
        uv.setHandleData(proc.process.handle(), proc);
        uv.close(proc.process.handle(), closeCallback);
        expected_callbacks += 1;
    }

    // Only close stdin if it was initialized (not with stdin: 'null')
    if (proc.stdin_enabled and !uv.isClosing(proc.stdin_pipe.handle())) {
        uv.setHandleData(proc.stdin_pipe.handle(), proc);
        uv.close(proc.stdin_pipe.handle(), closeCallback);
        expected_callbacks += 1;
    }

    if (!uv.isClosing(proc.stdout_pipe.handle())) {
        uv.setHandleData(proc.stdout_pipe.handle(), proc);
        uv.close(proc.stdout_pipe.handle(), closeCallback);
        expected_callbacks += 1;
    }

    if (!uv.isClosing(proc.stderr_pipe.handle())) {
        uv.setHandleData(proc.stderr_pipe.handle(), proc);
        uv.close(proc.stderr_pipe.handle(), closeCallback);
        expected_callbacks += 1;
    }

    // Close timeout timer if it was active
    if (proc.timeout_active and !uv.isClosing(proc.timeout_timer.handle())) {
        // Stop the timer first
        _ = uv.timerStop(proc.timeout_timer.ptr()) catch {};
        uv.setHandleData(proc.timeout_timer.handle(), proc);
        uv.close(proc.timeout_timer.handle(), closeCallback);
        expected_callbacks += 1;
    }

    proc.handles_to_close = expected_callbacks;

    // Edge case: all handles were already closing
    // Return to pool immediately since no callbacks will fire
    if (expected_callbacks == 0) {
        debug_log.log("[ASYNC_PROC] All handles already closing for process {d}", .{proc.id});
        unregisterProcess(proc.id);
        returnToPool(proc);
    }
}

// ============================================================================
// JavaScript Event Delivery
// ============================================================================

fn deliverStdoutData(proc_id: usize, data: []const u8) void {
    deliverProcessEvent(proc_id, "stdout", data, null, null);
}

fn deliverStderrData(proc_id: usize, data: []const u8) void {
    deliverProcessEvent(proc_id, "stderr", data, null, null);
}

fn deliverExitEvent(proc_id: usize, exit_code: i64, signal: c_int) void {
    deliverProcessEvent(proc_id, "exit", null, exit_code, signal);
}

fn deliverProcessEvent(
    proc_id: usize,
    event_type: []const u8,
    data: ?[]const u8,
    exit_code: ?i64,
    signal: ?c_int,
) void {
    const ctx = global_ctx orelse return;
    const rt = ctx.runtime orelse return;

    // Get __handleProcessEvent function
    const global = c.hermes_get_global_object(rt);
    if (global == null) return;
    defer c.hermes_object_destroy(global);

    const callback_fn = c.hermes_object_get_property(rt, global, "__handleProcessEvent");
    if (callback_fn == null) return;
    defer c.hermes_value_destroy(callback_fn);

    if (!c.hermes_value_is_function(rt, callback_fn)) return;

    // Create arguments: (id, event, data)
    const id_val = c.hermes_value_create_number(rt, @floatFromInt(proc_id));
    if (id_val == null) return;
    defer c.hermes_value_destroy(id_val);

    const event_val = c.hermes_value_create_string(rt, event_type.ptr, event_type.len);
    if (event_val == null) return;
    defer c.hermes_value_destroy(event_val);

    // Create event data object
    const data_obj = c.hermes_value_create_object(rt);
    if (data_obj == null) return;
    defer c.hermes_value_destroy(data_obj);

    if (data) |d| {
        const data_str = c.hermes_value_create_string(rt, d.ptr, d.len);
        if (data_str) |v| {
            c.hermes_value_set_property(rt, data_obj, "data", v);
            c.hermes_value_destroy(v);
        }
    }

    if (exit_code) |code| {
        const code_val = c.hermes_value_create_number(rt, @floatFromInt(code));
        if (code_val) |v| {
            c.hermes_value_set_property(rt, data_obj, "code", v);
            c.hermes_value_destroy(v);
        }
    }

    if (signal) |sig| {
        if (sig != 0) {
            const sig_name = getSignalName(@intCast(sig));
            const sig_val = c.hermes_value_create_string(rt, sig_name.ptr, sig_name.len);
            if (sig_val) |v| {
                c.hermes_value_set_property(rt, data_obj, "signal", v);
                c.hermes_value_destroy(v);
            }
        } else {
            const null_val = c.hermes_value_create_null(rt);
            if (null_val) |v| {
                c.hermes_value_set_property(rt, data_obj, "signal", v);
                c.hermes_value_destroy(v);
            }
        }
    }

    // Call __handleProcessEvent(id, event, data)
    var args = [_]?*c.OVHermesValue{ id_val, event_val, data_obj };
    const result = c.hermes_call_function(rt, callback_fn, &args, 3);
    if (result != null) {
        c.hermes_value_destroy(result);
    }

    // Drain microtasks for Promise callbacks
    _ = c.hermes_drain_microtasks(rt, -1);
}

fn getSignalName(sig: u32) []const u8 {
    const SIG = std.posix.SIG;
    if (sig == SIG.HUP) return "SIGHUP";
    if (sig == SIG.INT) return "SIGINT";
    if (sig == SIG.QUIT) return "SIGQUIT";
    if (sig == SIG.KILL) return "SIGKILL";
    if (sig == SIG.TERM) return "SIGTERM";
    if (sig == SIG.USR1) return "SIGUSR1";
    if (sig == SIG.USR2) return "SIGUSR2";
    if (sig == SIG.PIPE) return "SIGPIPE";
    if (sig == SIG.SEGV) return "SIGSEGV";
    return "UNKNOWN";
}

// ============================================================================
// Native Functions (called from JavaScript)
// ============================================================================

/// __spawnAsync(cmd, args, opts) -> process_id
pub export fn spawnAsync(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "spawnAsync requires at least 1 argument (cmd)");
        return null;
    }

    const ctx = global_ctx orelse {
        c.hermes_throw_error(runtime, "Async process system not initialized");
        return null;
    };

    const loop = event_loop.getLoop() orelse {
        c.hermes_throw_error(runtime, "Event loop not available");
        return null;
    };

    // Get command string
    const cmd_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid command argument");
        return null;
    };
    var cmd_len: usize = 0;
    const cmd_ptr = c.hermes_value_get_string(runtime, cmd_val, &cmd_len);
    if (cmd_ptr == null or cmd_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get command string");
        return null;
    }

    // Get or create process state (may reuse from pool)
    const proc_id = process_id_counter.fetchAdd(1, .monotonic);
    const proc = getOrCreateProcess(ctx.allocator, proc_id) catch {
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Build argv (uses optional type to support null terminator)
    var argv_list: std.ArrayList(?[*:0]const u8) = .{};
    defer argv_list.deinit(ctx.allocator);

    // Add command
    const cmd_copy = ctx.allocator.dupeZ(u8, cmd_ptr[0..cmd_len]) catch {
        returnToPool(proc);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };
    argv_list.append(ctx.allocator, cmd_copy) catch {
        ctx.allocator.free(cmd_copy);
        returnToPool(proc);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Add args if provided
    if (arg_count >= 2) {
        const args_val = args[1];
        if (args_val != null and !c.hermes_value_is_undefined(args_val)) {
            var i: usize = 0;
            var idx_buf: [16]u8 = undefined;
            while (i < 100) : (i += 1) {
                const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch break;
                idx_buf[idx_str.len] = 0;
                const elem = c.hermes_value_get_property(runtime, args_val, @ptrCast(&idx_buf));
                if (elem == null or c.hermes_value_is_undefined(elem)) break;
                defer c.hermes_value_destroy(elem);

                if (c.hermes_value_is_string(elem)) {
                    var arg_len: usize = 0;
                    const arg_ptr = c.hermes_value_get_string(runtime, elem, &arg_len);
                    if (arg_ptr != null and arg_len > 0) {
                        const arg_copy = ctx.allocator.dupeZ(u8, arg_ptr[0..arg_len]) catch continue;
                        argv_list.append(ctx.allocator, arg_copy) catch {
                            ctx.allocator.free(arg_copy);
                            continue;
                        };
                    }
                }
            }
        }
    }

    // Null-terminate argv
    argv_list.append(ctx.allocator, null) catch {
        for (argv_list.items) |arg| {
            if (arg) |a| ctx.allocator.free(a[0..std.mem.len(a) + 1]);
        }
        returnToPool(proc);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Get options (cwd, env, clearEnv, stdin, timeout, detach, stdoutBuffered, stderrBuffered)
    var cwd: ?[*:0]const u8 = null;
    var env_obj: ?*c.OVHermesValue = null;
    var clear_env: bool = false;
    var stdin_null: bool = false;
    var timeout_ms: ?u64 = null;
    var detach: bool = false;
    var stdout_buffered: bool = false;
    var stderr_buffered: bool = false;

    if (arg_count >= 3) {
        const opts_val = args[2];
        if (opts_val != null and c.hermes_value_is_object(opts_val)) {
            // Get cwd option
            const cwd_prop = c.hermes_value_get_property(runtime, opts_val, "cwd");
            if (cwd_prop != null and c.hermes_value_is_string(cwd_prop)) {
                var cwd_len: usize = 0;
                const cwd_ptr = c.hermes_value_get_string(runtime, cwd_prop, &cwd_len);
                if (cwd_ptr != null and cwd_len > 0) {
                    cwd = ctx.allocator.dupeZ(u8, cwd_ptr[0..cwd_len]) catch null;
                }
            }
            if (cwd_prop != null) c.hermes_value_destroy(cwd_prop);

            // Get env option (object with key-value pairs)
            const env_prop = c.hermes_value_get_property(runtime, opts_val, "env");
            if (env_prop != null and c.hermes_value_is_object(env_prop)) {
                env_obj = env_prop;
                // Don't destroy env_prop - we keep it for buildEnvArray
            } else if (env_prop != null) {
                c.hermes_value_destroy(env_prop);
            }

            // Get clearEnv option (boolean)
            const clear_env_prop = c.hermes_value_get_property(runtime, opts_val, "clearEnv");
            if (clear_env_prop != null) {
                if (c.hermes_value_is_boolean(clear_env_prop)) {
                    clear_env = c.hermes_value_get_boolean(clear_env_prop);
                }
                c.hermes_value_destroy(clear_env_prop);
            }

            // Get stdin option (string: 'pipe' or 'null')
            const stdin_prop = c.hermes_value_get_property(runtime, opts_val, "stdin");
            if (stdin_prop != null) {
                if (c.hermes_value_is_string(stdin_prop)) {
                    var stdin_len: usize = 0;
                    const stdin_ptr = c.hermes_value_get_string(runtime, stdin_prop, &stdin_len);
                    if (stdin_ptr != null and stdin_len > 0) {
                        const stdin_str = stdin_ptr[0..stdin_len];
                        if (std.mem.eql(u8, stdin_str, "null") or std.mem.eql(u8, stdin_str, "ignore")) {
                            stdin_null = true;
                        }
                    }
                }
                c.hermes_value_destroy(stdin_prop);
            }

            // Get timeout option (number in milliseconds)
            const timeout_prop = c.hermes_value_get_property(runtime, opts_val, "timeout");
            if (timeout_prop != null) {
                if (c.hermes_value_is_number(timeout_prop)) {
                    const timeout_val = c.hermes_value_get_number(timeout_prop);
                    if (timeout_val > 0) {
                        timeout_ms = @intFromFloat(timeout_val);
                    }
                }
                c.hermes_value_destroy(timeout_prop);
            }

            // Get detach option (boolean)
            const detach_prop = c.hermes_value_get_property(runtime, opts_val, "detach");
            if (detach_prop != null) {
                if (c.hermes_value_is_boolean(detach_prop)) {
                    detach = c.hermes_value_get_boolean(detach_prop);
                }
                c.hermes_value_destroy(detach_prop);
            }

            // Get stdoutBuffered option (boolean) - collect all stdout until EOF
            const stdout_buf_prop = c.hermes_value_get_property(runtime, opts_val, "stdoutBuffered");
            if (stdout_buf_prop != null) {
                if (c.hermes_value_is_boolean(stdout_buf_prop)) {
                    stdout_buffered = c.hermes_value_get_boolean(stdout_buf_prop);
                }
                c.hermes_value_destroy(stdout_buf_prop);
            }

            // Get stderrBuffered option (boolean) - collect all stderr until EOF
            const stderr_buf_prop = c.hermes_value_get_property(runtime, opts_val, "stderrBuffered");
            if (stderr_buf_prop != null) {
                if (c.hermes_value_is_boolean(stderr_buf_prop)) {
                    stderr_buffered = c.hermes_value_get_boolean(stderr_buf_prop);
                }
                c.hermes_value_destroy(stderr_buf_prop);
            }
        }
    }

    // Build environment array (merges with current env unless clearEnv is true)
    const custom_env = buildEnvArray(runtime, ctx.allocator, env_obj, clear_env);
    defer {
        if (custom_env) |env| {
            // Free all env strings and count them
            var count: usize = 0;
            while (env[count]) |entry| : (count += 1) {
                ctx.allocator.free(entry[0 .. std.mem.len(entry) + 1]);
            }
            // FIX: Free the backing array (count entries + 1 null terminator)
            // Need to cast away const since we're freeing memory we allocated
            const slice_ptr: [*]?[*:0]const u8 = @ptrCast(@constCast(env));
            ctx.allocator.free(slice_ptr[0 .. count + 1]);
        }
    }

    // Clean up env_obj now that we've extracted the data
    if (env_obj) |obj| {
        c.hermes_value_destroy(obj);
    }

    // Initialize pipes - track state for proper cleanup on failure
    var pipe_state = PipeInitState{};

    // Only initialize stdin pipe if not using stdin: 'null'
    if (!stdin_null) {
        uv.pipeInit(loop, proc.stdin_pipe.ptr(), false) catch {
            cleanup(ctx.allocator, proc, argv_list.items, cwd);
            c.hermes_throw_error(runtime, "Failed to init stdin pipe");
            return null;
        };
        pipe_state.stdin_init = true;
    }

    uv.pipeInit(loop, proc.stdout_pipe.ptr(), false) catch {
        cleanupWithPipes(ctx.allocator, proc, argv_list.items, cwd, pipe_state);
        c.hermes_throw_error(runtime, "Failed to init stdout pipe");
        return null;
    };
    pipe_state.stdout_init = true;

    uv.pipeInit(loop, proc.stderr_pipe.ptr(), false) catch {
        cleanupWithPipes(ctx.allocator, proc, argv_list.items, cwd, pipe_state);
        c.hermes_throw_error(runtime, "Failed to init stderr pipe");
        return null;
    };
    pipe_state.stderr_init = true;

    // Set up stdio containers
    var stdio: [3]uv.uv_stdio_container_t = undefined;

    // stdin - writable from parent, or ignored if stdin: 'null'
    if (stdin_null) {
        stdio[0].flags = uv.UV_IGNORE;
        stdio[0].data.fd = -1;
    } else {
        stdio[0].flags = uv.UV_CREATE_PIPE | uv.UV_READABLE_PIPE;
        stdio[0].data.stream = proc.stdin_pipe.stream();
    }

    // stdout - readable by parent
    stdio[1].flags = uv.UV_CREATE_PIPE | uv.UV_WRITABLE_PIPE;
    stdio[1].data.stream = proc.stdout_pipe.stream();

    // stderr - readable by parent
    stdio[2].flags = uv.UV_CREATE_PIPE | uv.UV_WRITABLE_PIPE;
    stdio[2].data.stream = proc.stderr_pipe.stream();

    // Set up process options
    const options = uv.uv_process_options_t{
        .exit_cb = exitCallback,
        .file = cmd_copy,
        .args = @ptrCast(argv_list.items.ptr),
        .env = custom_env,
        .cwd = cwd,
        .flags = if (detach) uv.UV_PROCESS_DETACHED else 0,
        .stdio_count = 3,
        .stdio = &stdio,
        .uid = 0,
        .gid = 0,
    };

    // Set process data pointer for callbacks
    uv.setHandleData(proc.process.handle(), proc);
    uv.setHandleData(proc.stdout_pipe.handle(), proc);
    uv.setHandleData(proc.stderr_pipe.handle(), proc);

    // Spawn the process
    uv.spawn(loop, proc.process.ptr(), &options) catch {
        // All 3 pipes are initialized, use proper cleanup
        cleanupWithPipes(ctx.allocator, proc, argv_list.items, cwd, pipe_state);
        c.hermes_throw_error(runtime, "Failed to spawn process");
        return null;
    };

    proc.pid = uv.getProcessPid(proc.process.ptr());

    // Track stdin state for processWrite validation
    proc.stdin_enabled = !stdin_null;

    // Store buffered mode flags
    proc.stdout_buffered = stdout_buffered;
    proc.stderr_buffered = stderr_buffered;
    proc.detached = detach;
    proc.timeout_ms = timeout_ms;

    // For detached processes, unref the handle so it doesn't keep the event loop alive
    if (detach) {
        uv.unref(proc.process.handle());
        debug_log.log("[ASYNC_PROC] Process {d} is detached", .{proc.id});
    }

    // Start timeout timer if specified
    if (timeout_ms) |ms| {
        uv.timerInit(loop, proc.timeout_timer.ptr()) catch {
            debug_log.log("[ASYNC_PROC] Failed to init timeout timer", .{});
        };
        uv.setHandleData(proc.timeout_timer.handle(), proc);
        uv.timerStart(proc.timeout_timer.ptr(), timeoutCallback, ms, 0) catch {
            debug_log.log("[ASYNC_PROC] Failed to start timeout timer", .{});
        };
        proc.timeout_active = true;
        debug_log.log("[ASYNC_PROC] Started {d}ms timeout for process {d}", .{ ms, proc.id });
    }

    // Start reading from stdout/stderr
    uv.readStart(proc.stdout_pipe.stream(), allocCallback, stdoutReadCallback) catch {
        debug_log.log("[ASYNC_PROC] Failed to start stdout read", .{});
    };

    uv.readStart(proc.stderr_pipe.stream(), allocCallback, stderrReadCallback) catch {
        debug_log.log("[ASYNC_PROC] Failed to start stderr read", .{});
    };

    // Register process
    registerProcess(proc) catch {
        // Process and all pipes are initialized, kill process and close handles
        _ = uv.processKill(proc.process.ptr(), 9) catch {};
        // Note: closeProcessHandles will free proc when all handles are closed
        closeProcessHandles(proc);
        // Free argv/cwd - proc will be freed in closeCallback
        for (argv_list.items) |arg| {
            if (arg) |a| ctx.allocator.free(a[0..std.mem.len(a) + 1]);
        }
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Too many concurrent processes");
        return null;
    };

    // Free argv strings (libuv has copied them)
    for (argv_list.items) |arg| {
        if (arg) |a| ctx.allocator.free(a[0..std.mem.len(a) + 1]);
    }
    if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);

    debug_log.log("[ASYNC_PROC] Spawned process {d}, pid={d}", .{ proc_id, proc.pid });

    return c.hermes_value_create_number(runtime, @floatFromInt(proc_id));
}

/// Track which pipes were initialized for proper cleanup on spawn failure
const PipeInitState = struct {
    stdin_init: bool = false,
    stdout_init: bool = false,
    stderr_init: bool = false,
};

fn cleanup(
    allocator: std.mem.Allocator,
    proc: *AsyncProcess,
    argv: []?[*:0]const u8,
    cwd: ?[*:0]const u8,
) void {
    _ = allocator;
    // Free argv strings
    for (argv) |arg| {
        if (arg) |a| proc.allocator.free(a[0..std.mem.len(a) + 1]);
    }
    if (cwd) |d| proc.allocator.free(d[0..std.mem.len(d) + 1]);
    returnToPool(proc);
}

/// Cleanup with proper libuv handle closing
/// This is needed when pipes were initialized but spawn failed
fn cleanupWithPipes(
    allocator: std.mem.Allocator,
    proc: *AsyncProcess,
    argv: []?[*:0]const u8,
    cwd: ?[*:0]const u8,
    pipe_state: PipeInitState,
) void {
    _ = allocator;
    // Free argv strings
    for (argv) |arg| {
        if (arg) |a| proc.allocator.free(a[0..std.mem.len(a) + 1]);
    }
    if (cwd) |d| proc.allocator.free(d[0..std.mem.len(d) + 1]);

    // Count how many pipes need to be closed
    var pipes_to_close: u8 = 0;
    if (pipe_state.stdin_init) pipes_to_close += 1;
    if (pipe_state.stdout_init) pipes_to_close += 1;
    if (pipe_state.stderr_init) pipes_to_close += 1;

    if (pipes_to_close == 0) {
        // No pipes to close, return to pool
        returnToPool(proc);
        return;
    }

    // Close initialized pipes
    proc.handles_to_close = pipes_to_close;
    proc.handles_closed = 0;

    // Set up close tracking - ONLY set data on handles that will be closed
    if (pipe_state.stdin_init) {
        uv.setHandleData(proc.stdin_pipe.handle(), proc);
        uv.close(proc.stdin_pipe.handle(), closeCallback);
    }
    if (pipe_state.stdout_init) {
        uv.setHandleData(proc.stdout_pipe.handle(), proc);
        uv.close(proc.stdout_pipe.handle(), closeCallback);
    }
    if (pipe_state.stderr_init) {
        uv.setHandleData(proc.stderr_pipe.handle(), proc);
        uv.close(proc.stderr_pipe.handle(), closeCallback);
    }

    // NOTE: The proc memory will be kept alive in closeCallback
    // (returned to pool) to avoid use-after-free
}

/// __processWrite(id, data) -> boolean
pub export fn processWrite(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "processWrite requires 2 arguments (id, data)");
        return null;
    }

    const ctx = global_ctx orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };

    // FIX #9: Validate process ID is a number before converting
    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(id_val)) {
        return c.hermes_value_create_boolean(runtime, false);
    }
    const proc_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    // Get data
    const data_val = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    var data_len: usize = 0;
    const data_ptr = c.hermes_value_get_string(runtime, data_val, &data_len);
    if (data_ptr == null or data_len == 0) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Find process
    const proc = getProcess(proc_id) orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (proc.exited) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Check if stdin is available (fails when spawned with stdin: 'null')
    if (!proc.stdin_enabled) {
        debug_log.log("[ASYNC_PROC] Write rejected: stdin disabled for process {d}", .{proc_id});
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Check pending write limit
    if (proc.pending_writes.items.len >= MAX_PENDING_WRITES) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Allocate write data
    const write_data = ctx.allocator.create(WriteData) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    write_data.* = .{
        .process = proc,
        .data = ctx.allocator.dupe(u8, data_ptr[0..data_len]) catch {
            ctx.allocator.destroy(write_data);
            return c.hermes_value_create_boolean(runtime, false);
        },
    };

    // Set up buffer
    write_data.buf = uv.uv_buf_init(write_data.data.ptr, write_data.data.len);

    // Set request data
    uv.setReqData(write_data.request.ptr(), write_data);

    // Add to pending writes
    proc.pending_writes.append(ctx.allocator, write_data) catch {
        ctx.allocator.free(write_data.data);
        ctx.allocator.destroy(write_data);
        return c.hermes_value_create_boolean(runtime, false);
    };

    // Perform write
    const bufs = [_]uv.uv_buf_t{write_data.buf};
    uv.write(write_data.request.ptr(), proc.stdin_pipe.stream(), &bufs, writeCallback) catch {
        // Remove from pending writes
        _ = proc.pending_writes.pop();
        ctx.allocator.free(write_data.data);
        ctx.allocator.destroy(write_data);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

/// __processKill(id, signal?) -> boolean
pub export fn processKill(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "processKill requires at least 1 argument (id)");
        return null;
    }

    // FIX #9: Validate process ID is a number before converting
    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(id_val)) {
        return c.hermes_value_create_boolean(runtime, false);
    }
    const proc_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    // Get signal (default SIGTERM = 15)
    var signal: c_int = 15;
    if (arg_count >= 2) {
        const sig_val = args[1];
        if (sig_val != null and c.hermes_value_is_number(sig_val)) {
            const sig_num = c.hermes_value_get_number(sig_val);
            // Validate signal is in valid range (1-31 for standard signals)
            if (sig_num >= 1 and sig_num <= 31) {
                signal = @intFromFloat(sig_num);
            }
        } else if (sig_val != null and c.hermes_value_is_string(sig_val)) {
            var sig_len: usize = 0;
            const sig_ptr = c.hermes_value_get_string(runtime, sig_val, &sig_len);
            if (sig_ptr != null) {
                signal = parseSignalName(sig_ptr[0..sig_len]);
            }
        }
    }

    // Find process
    const proc = getProcess(proc_id) orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (proc.exited) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Kill process
    uv.processKill(proc.process.ptr(), signal) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    debug_log.log("[ASYNC_PROC] Killed process {d} with signal {d}", .{ proc_id, signal });

    return c.hermes_value_create_boolean(runtime, true);
}

/// __processCloseStdin(id) -> boolean
/// Closes the stdin pipe, signaling EOF to the child process.
/// This is essential for CLI tools that wait for EOF before processing input.
pub export fn processCloseStdin(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "processCloseStdin requires 1 argument (id)");
        return null;
    }

    // Validate process ID is a number before converting
    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(id_val)) {
        return c.hermes_value_create_boolean(runtime, false);
    }
    const proc_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    // Find process
    const proc = getProcess(proc_id) orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (proc.exited) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Check if stdin was enabled (fails when spawned with stdin: 'null')
    if (!proc.stdin_enabled) {
        debug_log.log("[ASYNC_PROC] closeStdin rejected: stdin disabled for process {d}", .{proc_id});
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Close stdin pipe (signals EOF to child process)
    if (!uv.isClosing(proc.stdin_pipe.handle())) {
        uv.close(proc.stdin_pipe.handle(), null);
        debug_log.log("[ASYNC_PROC] Closed stdin for process {d}", .{proc_id});
    }

    return c.hermes_value_create_boolean(runtime, true);
}

fn parseSignalName(name: []const u8) c_int {
    const SIG = std.posix.SIG;
    if (std.mem.eql(u8, name, "SIGTERM") or std.mem.eql(u8, name, "TERM")) return @intCast(SIG.TERM);
    if (std.mem.eql(u8, name, "SIGKILL") or std.mem.eql(u8, name, "KILL")) return @intCast(SIG.KILL);
    if (std.mem.eql(u8, name, "SIGINT") or std.mem.eql(u8, name, "INT")) return @intCast(SIG.INT);
    if (std.mem.eql(u8, name, "SIGHUP") or std.mem.eql(u8, name, "HUP")) return @intCast(SIG.HUP);
    if (std.mem.eql(u8, name, "SIGUSR1") or std.mem.eql(u8, name, "USR1")) return @intCast(SIG.USR1);
    if (std.mem.eql(u8, name, "SIGUSR2") or std.mem.eql(u8, name, "USR2")) return @intCast(SIG.USR2);
    return @intCast(SIG.TERM); // default
}

// ============================================================================
// Environment Variable Helpers
// ============================================================================

/// Build environment array from JavaScript object for libuv
/// Returns null-terminated array of "KEY=value" strings, or null if no env provided
/// If clearEnv is false (default), merges with current environment
fn buildEnvArray(
    runtime: ?*c.OVHermesRuntime,
    allocator: std.mem.Allocator,
    env_obj: ?*c.OVHermesValue,
    clear_env: bool,
) ?[*:null]const ?[*:0]const u8 {
    // Start with current environment unless clearEnv is true
    var env_list: std.ArrayList(?[*:0]const u8) = .{};

    // Get current environment first (if not clearing)
    if (!clear_env) {
        const environ = std.c.environ;
        var i: usize = 0;
        while (environ[i]) |env_entry| : (i += 1) {
            if (i >= MAX_ENV_VARS) break;
            // Duplicate the string
            const len = std.mem.len(env_entry);
            const copy = allocator.allocSentinel(u8, len, 0) catch continue;
            @memcpy(copy, env_entry[0..len]);
            env_list.append(allocator, copy) catch {
                allocator.free(copy);
                continue;
            };
        }
    }

    // Add/override with custom env vars from JS object
    if (env_obj) |obj| {
        // Get Object.keys() to enumerate properties
        // We use __keys workaround since Hermes doesn't expose Object.keys easily
        var key_buf: [256]u8 = undefined;

        // Try to get properties by iterating (Hermes doesn't expose Object.keys easily)
        // We use a workaround: try to get __envKeys property if set by JS wrapper
        const keys_prop = c.hermes_value_get_property(runtime, obj, "__keys");
        if (keys_prop != null and !c.hermes_value_is_undefined(keys_prop)) {
            defer c.hermes_value_destroy(keys_prop);

            // Iterate through keys array
            var idx: usize = 0;
            var idx_str_buf: [16]u8 = undefined;
            while (idx < MAX_ENV_VARS) : (idx += 1) {
                const idx_str = std.fmt.bufPrint(&idx_str_buf, "{d}", .{idx}) catch break;
                idx_str_buf[idx_str.len] = 0;
                const key_val = c.hermes_value_get_property(runtime, keys_prop, @ptrCast(&idx_str_buf));
                if (key_val == null or c.hermes_value_is_undefined(key_val)) break;
                defer c.hermes_value_destroy(key_val);

                if (!c.hermes_value_is_string(key_val)) continue;

                var key_len: usize = 0;
                const key_ptr = c.hermes_value_get_string(runtime, key_val, &key_len);
                if (key_ptr == null or key_len == 0 or key_len >= key_buf.len) continue;

                // Get the value for this key
                @memcpy(key_buf[0..key_len], key_ptr[0..key_len]);
                key_buf[key_len] = 0;

                const val_prop = c.hermes_value_get_property(runtime, obj, @ptrCast(&key_buf));
                if (val_prop == null or c.hermes_value_is_undefined(val_prop)) continue;
                defer c.hermes_value_destroy(val_prop);

                if (!c.hermes_value_is_string(val_prop)) continue;

                var val_len: usize = 0;
                const val_ptr = c.hermes_value_get_string(runtime, val_prop, &val_len);
                if (val_ptr == null) continue;

                // Build "KEY=value" string
                const env_str = buildEnvString(allocator, key_ptr[0..key_len], val_ptr[0..val_len]) orelse continue;

                // Remove existing entry with same key (for override)
                removeEnvByKey(&env_list, allocator, key_ptr[0..key_len]);

                env_list.append(allocator, env_str) catch {
                    // Convert sentinel pointer to slice for freeing
                    const len = std.mem.len(env_str);
                    allocator.free(env_str[0 .. len + 1]);
                    continue;
                };
            }
        }
    }

    if (env_list.items.len == 0) {
        env_list.deinit(allocator);
        return null;
    }

    // Allocate exact-sized array (count + 1 for null terminator)
    // This ensures free() size matches allocation size
    const final_array = allocator.alloc(?[*:0]const u8, env_list.items.len + 1) catch {
        freeEnvArray(allocator, env_list.items);
        env_list.deinit(allocator);
        return null;
    };

    // Copy items to final array
    @memcpy(final_array[0..env_list.items.len], env_list.items);
    final_array[env_list.items.len] = null; // null terminator

    // Free the ArrayList's internal buffer (not the strings, they're now in final_array)
    env_list.deinit(allocator);

    // Convert to sentinel-terminated pointer
    return @ptrCast(final_array.ptr);
}

/// Build a "KEY=value" string
fn buildEnvString(allocator: std.mem.Allocator, key: []const u8, value: []const u8) ?[*:0]const u8 {
    const total_len = key.len + 1 + value.len; // key + '=' + value
    const result = allocator.allocSentinel(u8, total_len, 0) catch return null;
    @memcpy(result[0..key.len], key);
    result[key.len] = '=';
    @memcpy(result[key.len + 1 ..][0..value.len], value);
    return result;
}

/// Remove existing env entry by key (for override)
fn removeEnvByKey(env_list: *std.ArrayList(?[*:0]const u8), allocator: std.mem.Allocator, key: []const u8) void {
    var i: usize = 0;
    while (i < env_list.items.len) {
        if (env_list.items[i]) |entry| {
            const entry_slice = std.mem.span(entry);
            // Check if this entry starts with "key="
            if (entry_slice.len > key.len and
                std.mem.eql(u8, entry_slice[0..key.len], key) and
                entry_slice[key.len] == '=')
            {
                allocator.free(entry[0 .. entry_slice.len + 1]);
                _ = env_list.orderedRemove(i);
                continue; // Don't increment i
            }
        }
        i += 1;
    }
}

/// Free all strings in env array
fn freeEnvArray(allocator: std.mem.Allocator, env: []?[*:0]const u8) void {
    for (env) |entry| {
        if (entry) |e| {
            allocator.free(e[0 .. std.mem.len(e) + 1]);
        }
    }
}

// ============================================================================
// Initialization
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, ctx: *AsyncProcessContext) void {
    ctx.runtime = runtime;
    global_ctx = ctx;

    initRegistry(ctx.allocator);

    // Register native functions
    c.hermes_register_host_function(runtime, "__spawnAsync", spawnAsync, null);
    c.hermes_register_host_function(runtime, "__processWrite", processWrite, null);
    c.hermes_register_host_function(runtime, "__processKill", processKill, null);
    c.hermes_register_host_function(runtime, "__processCloseStdin", processCloseStdin, null);

    debug_log.log("[ASYNC_PROC] Registered async process API", .{});
}

pub fn deinit() void {
    if (!registry_initialized) return;

    // Mark as not initialized to prevent any new operations
    registry_initialized = false;
    pool_initialized = false;

    // Kill all running processes
    // Don't try to close handles or free memory - just kill processes
    // and let the OS clean up when the process exits.
    //
    // The issue is that libuv_loop_close requires ALL handles to be closed,
    // and properly closing handles requires running the event loop.
    // Rather than fight with libuv's cleanup requirements, we simply
    // kill processes and let the OS handle the rest.
    registry_mutex.lock();
    var iter = process_registry.valueIterator();
    while (iter.next()) |proc| {
        if (!proc.*.exited) {
            _ = uv.processKill(proc.*.process.ptr(), 9) catch {};
        }
    }
    registry_mutex.unlock();

    global_ctx = null;
}
