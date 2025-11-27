/// PTY (Pseudo-Terminal) API for JavaScript plugins
/// Provides spawnPty() for interactive terminal programs (fzf, htop, shells)
///
/// API:
/// - process.spawnPty(cmd, args?, opts?) -> PtyProcess
/// - pty.write(data) - Write to PTY
/// - pty.resize(rows, cols) - Resize terminal
/// - pty.onData(callback) - Handle PTY output
/// - pty.onExit(callback) - Handle process exit
/// - pty.kill(signal?) - Kill process
///
/// Key differences from spawn():
/// - Single bidirectional stream (no separate stdout/stderr)
/// - Supports terminal resize
/// - Programs see a real TTY
const std = @import("std");
const c = @import("c_api.zig").c;
const pty = @import("../event_loop/libuv_pty.zig");
const uv = @import("../event_loop/libuv_process.zig");
const event_loop = @import("../event_loop/libuv.zig");
const debug_log = @import("../../backends/headless/log.zig");

// ============================================================================
// Configuration
// ============================================================================

const MAX_PTY_PROCESSES: usize = 16;
const READ_BUFFER_SIZE: usize = 64 * 1024;
const MAX_ENV_VARS: usize = 256;

// ============================================================================
// Context
// ============================================================================

pub const PtyContext = struct {
    allocator: std.mem.Allocator,
    runtime: ?*c.OVHermesRuntime = null,
};

var global_ctx: ?*PtyContext = null;
var pty_id_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(1);

// ============================================================================
// PTY Process State
// ============================================================================

const PtyProcess = struct {
    id: usize,
    allocator: std.mem.Allocator,

    // PTY state
    master_fd: c_int = -1,
    pid: c_int = -1,
    exited: bool = false,
    exit_code: c_int = 0,
    exit_signal: c_int = 0,

    // libuv poll handle for watching master_fd
    poll_handle: pty.PollHandle = .{},
    poll_active: bool = false,

    // Timer for checking child exit (since we use poll, not process handle)
    check_timer: uv.TimerHandle = .{},
    check_timer_active: bool = false,

    // Timeout
    timeout_timer: uv.TimerHandle = .{},
    timeout_active: bool = false,
    timeout_ms: ?u64 = null,
    timed_out: bool = false,

    // Read buffer
    read_buffer: [READ_BUFFER_SIZE]u8 = undefined,

    // Handle close tracking
    handles_to_close: u8 = 0,
    handles_closed: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, id: usize) PtyProcess {
        return .{
            .id = id,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PtyProcess) void {
        // Close master_fd if still open
        if (self.master_fd >= 0) {
            pty.closePty(self.master_fd);
            self.master_fd = -1;
        }
    }
};

// ============================================================================
// Registry
// ============================================================================

var pty_registry: std.AutoHashMap(usize, *PtyProcess) = undefined;
var registry_mutex: std.Thread.Mutex = .{};
var registry_initialized: bool = false;

var free_pty_pool: std.ArrayList(*PtyProcess) = undefined;
var pool_mutex: std.Thread.Mutex = .{};
var pool_initialized: bool = false;
var pool_allocator: std.mem.Allocator = undefined;

const MAX_POOL_SIZE: usize = 4;

fn initRegistry(allocator: std.mem.Allocator) void {
    if (registry_initialized) return;
    pty_registry = std.AutoHashMap(usize, *PtyProcess).init(allocator);
    registry_initialized = true;

    if (!pool_initialized) {
        free_pty_pool = .{};
        pool_allocator = allocator;
        pool_initialized = true;
    }
}

fn getOrCreatePty(allocator: std.mem.Allocator, id: usize) !*PtyProcess {
    if (pool_initialized) {
        pool_mutex.lock();
        defer pool_mutex.unlock();

        if (free_pty_pool.items.len > 0) {
            const proc = free_pty_pool.items[free_pty_pool.items.len - 1];
            free_pty_pool.items.len -= 1;
            proc.* = PtyProcess.init(allocator, id);
            return proc;
        }
    }

    const proc = try allocator.create(PtyProcess);
    proc.* = PtyProcess.init(allocator, id);
    return proc;
}

fn returnToPool(proc: *PtyProcess) void {
    proc.deinit();

    if (!pool_initialized) {
        proc.allocator.destroy(proc);
        return;
    }

    pool_mutex.lock();
    defer pool_mutex.unlock();

    for (free_pty_pool.items) |existing| {
        if (existing == proc) return;
    }

    if (free_pty_pool.items.len >= MAX_POOL_SIZE) {
        const oldest = free_pty_pool.orderedRemove(0);
        oldest.allocator.destroy(oldest);
    }

    free_pty_pool.append(pool_allocator, proc) catch {
        proc.allocator.destroy(proc);
    };
}

fn getPty(id: usize) ?*PtyProcess {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return pty_registry.get(id);
}

fn registerPty(proc: *PtyProcess) !void {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    if (pty_registry.count() >= MAX_PTY_PROCESSES) {
        return error.TooManyProcesses;
    }
    try pty_registry.put(proc.id, proc);
}

fn unregisterPty(id: usize) void {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    _ = pty_registry.remove(id);
}

// ============================================================================
// libuv Callbacks
// ============================================================================

/// Poll callback - called when PTY has data to read
fn pollCallback(handle: ?*pty.uv_poll_t, status: c_int, events: c_int) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(handle));
    if (data == null) return;

    const proc: *PtyProcess = @ptrCast(@alignCast(data));

    if (status < 0) {
        // Error - likely PTY closed
        debug_log.log("[PTY] Poll error for pty {d}: status={d}", .{ proc.id, status });
        return;
    }

    if (events & pty.UV_READABLE != 0) {
        // Data available to read
        const bytes_read = pty.readPty(proc.master_fd, &proc.read_buffer) catch |err| {
            debug_log.log("[PTY] Read error for pty {d}: {}", .{ proc.id, err });
            return;
        };

        if (bytes_read > 0) {
            deliverPtyData(proc.id, proc.read_buffer[0..bytes_read]);
        }
    }
}

/// Timer callback - periodically check if child has exited
fn checkExitCallback(timer: ?*uv.uv_timer_t) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(timer));
    if (data == null) return;

    const proc: *PtyProcess = @ptrCast(@alignCast(data));

    if (proc.exited) return;

    // Check if child has exited
    if (pty.checkChildExited(proc.pid)) |result| {
        proc.exited = true;

        // Handle timeout
        var final_code = result.code;
        if (proc.timed_out and result.signal != 0) {
            final_code = 124;
        }
        proc.exit_code = final_code;
        proc.exit_signal = result.signal;

        debug_log.log("[PTY] Process {d} exited: code={d}, signal={d}", .{
            proc.id,
            final_code,
            result.signal,
        });

        // Drain any remaining output
        drainPtyOutput(proc);

        // Deliver exit event
        deliverPtyExit(proc.id, final_code, result.signal);

        // Close handles
        closePtyHandles(proc);
    }
}

/// Timeout callback
fn timeoutCallback(timer: ?*uv.uv_timer_t) callconv(.c) void {
    const data = uv.getHandleData(@ptrCast(timer));
    if (data == null) return;

    const proc: *PtyProcess = @ptrCast(@alignCast(data));

    if (proc.exited) return;

    debug_log.log("[PTY] Process {d} timed out, sending SIGTERM", .{proc.id});
    proc.timed_out = true;

    pty.killProcess(proc.pid, 15) catch {
        _ = pty.killProcess(proc.pid, 9) catch {};
    };
}

/// Close callback
fn closeCallback(handle: ?*uv.uv_handle_t) callconv(.c) void {
    const data = uv.getHandleData(handle);
    if (data == null) return;

    const proc: *PtyProcess = @ptrCast(@alignCast(data));
    proc.handles_closed += 1;

    if (proc.handles_closed >= proc.handles_to_close) {
        unregisterPty(proc.id);
        returnToPool(proc);
    }
}

/// Drain remaining PTY output after process exits
fn drainPtyOutput(proc: *PtyProcess) void {
    // Read any remaining data in the PTY buffer
    // Limit iterations to prevent blocking event loop if process keeps producing data
    const MAX_DRAIN_ITERATIONS = 100; // ~6.4MB max with 64KB buffer
    var iterations: usize = 0;
    while (iterations < MAX_DRAIN_ITERATIONS) : (iterations += 1) {
        const bytes_read = pty.readPty(proc.master_fd, &proc.read_buffer) catch break;
        if (bytes_read == 0) break;
        deliverPtyData(proc.id, proc.read_buffer[0..bytes_read]);
    }
}

/// Close all PTY handles
fn closePtyHandles(proc: *PtyProcess) void {
    proc.handles_closed = 0;
    var expected: u8 = 0;

    // Stop and close poll handle
    if (proc.poll_active) {
        _ = pty.pollStop(proc.poll_handle.ptr()) catch {};
        if (!uv.isClosing(proc.poll_handle.handle())) {
            uv.setHandleData(proc.poll_handle.handle(), proc);
            uv.close(proc.poll_handle.handle(), closeCallback);
            expected += 1;
        }
    }

    // Stop and close check timer
    if (proc.check_timer_active) {
        _ = uv.timerStop(proc.check_timer.ptr()) catch {};
        if (!uv.isClosing(proc.check_timer.handle())) {
            uv.setHandleData(proc.check_timer.handle(), proc);
            uv.close(proc.check_timer.handle(), closeCallback);
            expected += 1;
        }
    }

    // Stop and close timeout timer
    if (proc.timeout_active) {
        _ = uv.timerStop(proc.timeout_timer.ptr()) catch {};
        if (!uv.isClosing(proc.timeout_timer.handle())) {
            uv.setHandleData(proc.timeout_timer.handle(), proc);
            uv.close(proc.timeout_timer.handle(), closeCallback);
            expected += 1;
        }
    }

    proc.handles_to_close = expected;

    // Close the PTY fd
    if (proc.master_fd >= 0) {
        pty.closePty(proc.master_fd);
        proc.master_fd = -1;
    }

    if (expected == 0) {
        unregisterPty(proc.id);
        returnToPool(proc);
    }
}

// ============================================================================
// JavaScript Event Delivery
// ============================================================================

fn deliverPtyData(pty_id: usize, data: []const u8) void {
    const ctx = global_ctx orelse return;
    const rt = ctx.runtime orelse return;

    const global = c.hermes_get_global_object(rt);
    if (global == null) return;
    defer c.hermes_object_destroy(global);

    const callback_fn = c.hermes_object_get_property(rt, global, "__handlePtyEvent");
    if (callback_fn == null) return;
    defer c.hermes_value_destroy(callback_fn);

    if (!c.hermes_value_is_function(rt, callback_fn)) return;

    const id_val = c.hermes_value_create_number(rt, @floatFromInt(pty_id));
    if (id_val == null) return;
    defer c.hermes_value_destroy(id_val);

    const event_val = c.hermes_value_create_string(rt, "data", 4);
    if (event_val == null) return;
    defer c.hermes_value_destroy(event_val);

    const data_obj = c.hermes_value_create_object(rt);
    if (data_obj == null) return;
    defer c.hermes_value_destroy(data_obj);

    const data_str = c.hermes_value_create_string(rt, data.ptr, data.len);
    if (data_str) |v| {
        c.hermes_value_set_property(rt, data_obj, "data", v);
        c.hermes_value_destroy(v);
    }

    var args = [_]?*c.OVHermesValue{ id_val, event_val, data_obj };
    const result = c.hermes_call_function(rt, callback_fn, &args, 3);
    if (result != null) c.hermes_value_destroy(result);

    _ = c.hermes_drain_microtasks(rt, -1);
}

fn deliverPtyExit(pty_id: usize, exit_code: c_int, signal: c_int) void {
    const ctx = global_ctx orelse return;
    const rt = ctx.runtime orelse return;

    const global = c.hermes_get_global_object(rt);
    if (global == null) return;
    defer c.hermes_object_destroy(global);

    const callback_fn = c.hermes_object_get_property(rt, global, "__handlePtyEvent");
    if (callback_fn == null) return;
    defer c.hermes_value_destroy(callback_fn);

    if (!c.hermes_value_is_function(rt, callback_fn)) return;

    const id_val = c.hermes_value_create_number(rt, @floatFromInt(pty_id));
    if (id_val == null) return;
    defer c.hermes_value_destroy(id_val);

    const event_val = c.hermes_value_create_string(rt, "exit", 4);
    if (event_val == null) return;
    defer c.hermes_value_destroy(event_val);

    const data_obj = c.hermes_value_create_object(rt);
    if (data_obj == null) return;
    defer c.hermes_value_destroy(data_obj);

    const code_val = c.hermes_value_create_number(rt, @floatFromInt(exit_code));
    if (code_val) |v| {
        c.hermes_value_set_property(rt, data_obj, "code", v);
        c.hermes_value_destroy(v);
    }

    if (signal != 0) {
        const sig_name = getSignalName(@intCast(signal));
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

    var args = [_]?*c.OVHermesValue{ id_val, event_val, data_obj };
    const result = c.hermes_call_function(rt, callback_fn, &args, 3);
    if (result != null) c.hermes_value_destroy(result);

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
    return "UNKNOWN";
}

// ============================================================================
// Native Functions
// ============================================================================

/// __spawnPty(cmd, args, opts) -> pty_id
pub export fn spawnPty(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "spawnPty requires at least 1 argument (cmd)");
        return null;
    }

    const ctx = global_ctx orelse {
        c.hermes_throw_error(runtime, "PTY system not initialized");
        return null;
    };

    const loop = event_loop.getLoop() orelse {
        c.hermes_throw_error(runtime, "Event loop not available");
        return null;
    };

    // Get command
    const cmd_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid command");
        return null;
    };
    var cmd_len: usize = 0;
    const cmd_ptr = c.hermes_value_get_string(runtime, cmd_val, &cmd_len);
    if (cmd_ptr == null or cmd_len == 0) {
        c.hermes_throw_error(runtime, "Invalid command string");
        return null;
    }

    // Get options and build env array
    var rows: u16 = 24;
    var cols: u16 = 80;
    var term_owned: ?[]u8 = null; // Owned copy of term string
    var cwd: ?[*:0]const u8 = null;
    var timeout_ms: ?u64 = null;

    var env_list: std.ArrayList(?[*:0]const u8) = .{};
    defer {
        freeArgv(ctx.allocator, env_list.items);
        env_list.deinit(ctx.allocator);
    }
    var has_env = false;

    if (arg_count >= 3) {
        const opts_val = args[2];
        if (opts_val != null and c.hermes_value_is_object(opts_val)) {
            // rows
            const rows_prop = c.hermes_value_get_property(runtime, opts_val, "rows");
            if (rows_prop != null and c.hermes_value_is_number(rows_prop)) {
                rows = @intFromFloat(c.hermes_value_get_number(rows_prop));
            }
            if (rows_prop != null) c.hermes_value_destroy(rows_prop);

            // cols
            const cols_prop = c.hermes_value_get_property(runtime, opts_val, "cols");
            if (cols_prop != null and c.hermes_value_is_number(cols_prop)) {
                cols = @intFromFloat(c.hermes_value_get_number(cols_prop));
            }
            if (cols_prop != null) c.hermes_value_destroy(cols_prop);

            // term - copy immediately before Hermes value is destroyed
            const term_prop = c.hermes_value_get_property(runtime, opts_val, "term");
            if (term_prop != null and c.hermes_value_is_string(term_prop)) {
                var term_len: usize = 0;
                const term_ptr = c.hermes_value_get_string(runtime, term_prop, &term_len);
                if (term_ptr != null and term_len > 0) {
                    // Copy string before destroying Hermes value to avoid use-after-free
                    term_owned = ctx.allocator.dupe(u8, term_ptr[0..term_len]) catch null;
                }
            }
            if (term_prop != null) c.hermes_value_destroy(term_prop);

            // cwd
            const cwd_prop = c.hermes_value_get_property(runtime, opts_val, "cwd");
            if (cwd_prop != null and c.hermes_value_is_string(cwd_prop)) {
                var cwd_len: usize = 0;
                const cwd_ptr = c.hermes_value_get_string(runtime, cwd_prop, &cwd_len);
                if (cwd_ptr != null and cwd_len > 0) {
                    cwd = ctx.allocator.dupeZ(u8, cwd_ptr[0..cwd_len]) catch null;
                }
            }
            if (cwd_prop != null) c.hermes_value_destroy(cwd_prop);

            // timeout
            const timeout_prop = c.hermes_value_get_property(runtime, opts_val, "timeout");
            if (timeout_prop != null and c.hermes_value_is_number(timeout_prop)) {
                const val = c.hermes_value_get_number(timeout_prop);
                if (val > 0) timeout_ms = @intFromFloat(val);
            }
            if (timeout_prop != null) c.hermes_value_destroy(timeout_prop);

            // env - passed as array of "KEY=VALUE" strings from JS wrapper
            const env_prop = c.hermes_value_get_property(runtime, opts_val, "envArray");
            if (env_prop != null and !c.hermes_value_is_undefined(env_prop)) {
                defer c.hermes_value_destroy(env_prop);
                var i: usize = 0;
                var idx_buf: [16]u8 = undefined;
                while (i < MAX_ENV_VARS) : (i += 1) {
                    const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch break;
                    idx_buf[idx_str.len] = 0;
                    const elem = c.hermes_value_get_property(runtime, env_prop, @ptrCast(&idx_buf));
                    if (elem == null or c.hermes_value_is_undefined(elem)) break;
                    defer c.hermes_value_destroy(elem);

                    if (c.hermes_value_is_string(elem)) {
                        var env_len: usize = 0;
                        const env_ptr = c.hermes_value_get_string(runtime, elem, &env_len);
                        if (env_ptr != null and env_len > 0) {
                            const env_copy = ctx.allocator.dupeZ(u8, env_ptr[0..env_len]) catch continue;
                            env_list.append(ctx.allocator, env_copy) catch {
                                ctx.allocator.free(env_copy);
                            };
                            has_env = true;
                        }
                    }
                }
            }
        }
    }

    // Add null terminator to env list if we have env vars
    if (has_env) {
        env_list.append(ctx.allocator, null) catch {};
    }

    // Build argv
    var argv_list: std.ArrayList(?[*:0]const u8) = .{};
    defer argv_list.deinit(ctx.allocator);

    const cmd_copy = ctx.allocator.dupeZ(u8, cmd_ptr[0..cmd_len]) catch {
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };
    argv_list.append(ctx.allocator, cmd_copy) catch {
        ctx.allocator.free(cmd_copy);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Add args
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
                        };
                    }
                }
            }
        }
    }

    argv_list.append(ctx.allocator, null) catch {
        freeArgv(ctx.allocator, argv_list.items);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Get term string - use owned copy if provided, otherwise default
    const term_str = term_owned orelse "xterm-256color";
    defer if (term_owned) |t| ctx.allocator.free(t);

    // Create term string (null-terminated)
    const term_z = ctx.allocator.dupeZ(u8, term_str) catch {
        freeArgv(ctx.allocator, argv_list.items);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };
    defer ctx.allocator.free(term_z);

    // Fork PTY
    const fork_result = pty.forkPty(rows, cols) catch {
        freeArgv(ctx.allocator, argv_list.items);
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Failed to fork PTY");
        return null;
    };

    if (fork_result.pid == 0) {
        // Child process - exec command
        const env_ptr: ?[*:null]const ?[*:0]const u8 = if (has_env)
            @ptrCast(env_list.items.ptr)
        else
            null;

        pty.execCommand(
            cmd_copy,
            @ptrCast(argv_list.items.ptr),
            env_ptr,
            cwd,
            term_z,
        );
        // execCommand never returns
    }

    // Parent process
    const pty_id = pty_id_counter.fetchAdd(1, .monotonic);
    const proc = getOrCreatePty(ctx.allocator, pty_id) catch {
        pty.closePty(fork_result.master_fd);
        _ = pty.killProcess(fork_result.pid, 9) catch {};
        freeArgv(ctx.allocator, argv_list.items);
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    proc.master_fd = fork_result.master_fd;
    proc.pid = fork_result.pid;
    proc.timeout_ms = timeout_ms;

    // Set non-blocking mode
    pty.setNonBlocking(fork_result.master_fd) catch {
        returnToPool(proc);
        _ = pty.killProcess(fork_result.pid, 9) catch {};
        freeArgv(ctx.allocator, argv_list.items);
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Failed to set non-blocking mode");
        return null;
    };

    // Initialize poll handle
    pty.pollInit(loop, proc.poll_handle.ptr(), fork_result.master_fd) catch {
        returnToPool(proc);
        _ = pty.killProcess(fork_result.pid, 9) catch {};
        freeArgv(ctx.allocator, argv_list.items);
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Failed to init poll handle");
        return null;
    };

    uv.setHandleData(proc.poll_handle.handle(), proc);
    pty.pollStart(proc.poll_handle.ptr(), pty.UV_READABLE, pollCallback) catch {
        returnToPool(proc);
        _ = pty.killProcess(fork_result.pid, 9) catch {};
        freeArgv(ctx.allocator, argv_list.items);
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Failed to start poll");
        return null;
    };
    proc.poll_active = true;

    // Initialize check timer (to detect child exit)
    const check_timer_ok = blk: {
        uv.timerInit(loop, proc.check_timer.ptr()) catch {
            debug_log.log("[PTY] Warning: failed to init check timer for pty {d}", .{pty_id});
            break :blk false;
        };
        uv.setHandleData(proc.check_timer.handle(), proc);
        uv.timerStart(proc.check_timer.ptr(), checkExitCallback, 100, 100) catch {
            debug_log.log("[PTY] Warning: failed to start check timer for pty {d}", .{pty_id});
            // Close the initialized handle to prevent leak
            uv.close(proc.check_timer.handle(), null);
            break :blk false;
        };
        break :blk true;
    };
    proc.check_timer_active = check_timer_ok;

    // Initialize timeout timer if specified
    if (timeout_ms) |ms| {
        const timeout_ok = blk: {
            uv.timerInit(loop, proc.timeout_timer.ptr()) catch {
                debug_log.log("[PTY] Warning: failed to init timeout timer for pty {d}", .{pty_id});
                break :blk false;
            };
            uv.setHandleData(proc.timeout_timer.handle(), proc);
            uv.timerStart(proc.timeout_timer.ptr(), timeoutCallback, ms, 0) catch {
                debug_log.log("[PTY] Warning: failed to start timeout timer for pty {d}", .{pty_id});
                // Close the initialized handle to prevent leak
                uv.close(proc.timeout_timer.handle(), null);
                break :blk false;
            };
            break :blk true;
        };
        proc.timeout_active = timeout_ok;
    }

    // Register
    registerPty(proc) catch {
        closePtyHandles(proc);
        _ = pty.killProcess(fork_result.pid, 9) catch {};
        freeArgv(ctx.allocator, argv_list.items);
        if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);
        c.hermes_throw_error(runtime, "Too many PTY processes");
        return null;
    };

    // Cleanup
    freeArgv(ctx.allocator, argv_list.items);
    if (cwd) |d| ctx.allocator.free(d[0..std.mem.len(d) + 1]);

    debug_log.log("[PTY] Spawned pty {d}, pid={d}, {d}x{d}", .{ pty_id, fork_result.pid, cols, rows });

    return c.hermes_value_create_number(runtime, @floatFromInt(pty_id));
}

/// __ptyWrite(id, data) -> boolean
pub export fn ptyWrite(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 2) return c.hermes_value_create_boolean(runtime, false);

    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(id_val)) return c.hermes_value_create_boolean(runtime, false);
    const pty_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    const data_val = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    var data_len: usize = 0;
    const data_ptr = c.hermes_value_get_string(runtime, data_val, &data_len);
    if (data_ptr == null or data_len == 0) return c.hermes_value_create_boolean(runtime, false);

    const proc = getPty(pty_id) orelse return c.hermes_value_create_boolean(runtime, false);
    if (proc.exited or proc.master_fd < 0) return c.hermes_value_create_boolean(runtime, false);

    _ = pty.writePty(proc.master_fd, data_ptr[0..data_len]) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

/// __ptyResize(id, rows, cols) -> boolean
pub export fn ptyResize(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 3) return c.hermes_value_create_boolean(runtime, false);

    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(id_val)) return c.hermes_value_create_boolean(runtime, false);
    const pty_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    const rows_val = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    const cols_val = args[2] orelse return c.hermes_value_create_boolean(runtime, false);

    if (!c.hermes_value_is_number(rows_val) or !c.hermes_value_is_number(cols_val)) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    const rows: u16 = @intFromFloat(c.hermes_value_get_number(rows_val));
    const cols: u16 = @intFromFloat(c.hermes_value_get_number(cols_val));

    const proc = getPty(pty_id) orelse return c.hermes_value_create_boolean(runtime, false);
    if (proc.exited or proc.master_fd < 0) return c.hermes_value_create_boolean(runtime, false);

    pty.resizePty(proc.master_fd, rows, cols) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    debug_log.log("[PTY] Resized pty {d} to {d}x{d}", .{ pty_id, cols, rows });

    return c.hermes_value_create_boolean(runtime, true);
}

/// __ptyKill(id, signal?) -> boolean
pub export fn ptyKill(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) return c.hermes_value_create_boolean(runtime, false);

    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(id_val)) return c.hermes_value_create_boolean(runtime, false);
    const pty_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    var signal: c_int = 15; // SIGTERM
    if (arg_count >= 2) {
        const sig_val = args[1];
        if (sig_val != null and c.hermes_value_is_number(sig_val)) {
            const sig_num = c.hermes_value_get_number(sig_val);
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

    const proc = getPty(pty_id) orelse return c.hermes_value_create_boolean(runtime, false);
    if (proc.exited) return c.hermes_value_create_boolean(runtime, false);

    pty.killProcess(proc.pid, signal) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    debug_log.log("[PTY] Killed pty {d} with signal {d}", .{ pty_id, signal });

    return c.hermes_value_create_boolean(runtime, true);
}

/// __ptyGetPid(id) -> number
pub export fn ptyGetPid(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) return c.hermes_value_create_number(runtime, -1);

    const id_val = args[0] orelse return c.hermes_value_create_number(runtime, -1);
    if (!c.hermes_value_is_number(id_val)) return c.hermes_value_create_number(runtime, -1);
    const pty_id: usize = @intFromFloat(c.hermes_value_get_number(id_val));

    const proc = getPty(pty_id) orelse return c.hermes_value_create_number(runtime, -1);

    return c.hermes_value_create_number(runtime, @floatFromInt(proc.pid));
}

fn parseSignalName(name: []const u8) c_int {
    const SIG = std.posix.SIG;
    if (std.mem.eql(u8, name, "SIGTERM") or std.mem.eql(u8, name, "TERM")) return @intCast(SIG.TERM);
    if (std.mem.eql(u8, name, "SIGKILL") or std.mem.eql(u8, name, "KILL")) return @intCast(SIG.KILL);
    if (std.mem.eql(u8, name, "SIGINT") or std.mem.eql(u8, name, "INT")) return @intCast(SIG.INT);
    if (std.mem.eql(u8, name, "SIGHUP") or std.mem.eql(u8, name, "HUP")) return @intCast(SIG.HUP);
    return @intCast(SIG.TERM);
}

fn freeArgv(allocator: std.mem.Allocator, argv: []?[*:0]const u8) void {
    for (argv) |arg| {
        if (arg) |a| {
            // dupeZ allocates len + 1 bytes (including null terminator)
            // std.mem.len gives us the length without null, so +1 for the full allocation
            const len = std.mem.len(a);
            // Cast to get rid of const for free - the memory was allocated by us
            const ptr: [*]u8 = @constCast(a);
            allocator.free(ptr[0 .. len + 1]);
        }
    }
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, ctx: *PtyContext) void {
    ctx.runtime = runtime;
    global_ctx = ctx;

    initRegistry(ctx.allocator);

    c.hermes_register_host_function(runtime, "__spawnPty", spawnPty, null);
    c.hermes_register_host_function(runtime, "__ptyWrite", ptyWrite, null);
    c.hermes_register_host_function(runtime, "__ptyResize", ptyResize, null);
    c.hermes_register_host_function(runtime, "__ptyKill", ptyKill, null);
    c.hermes_register_host_function(runtime, "__ptyGetPid", ptyGetPid, null);

    debug_log.log("[PTY] Registered PTY API", .{});
}

pub fn deinit() void {
    if (!registry_initialized) return;

    // During shutdown, just kill processes and stop handles.
    // Don't destroy structs yet - libuv's handle close will do that.
    // Note: We set data pointers to null so libuv callbacks don't crash.

    registry_mutex.lock();
    var iter = pty_registry.valueIterator();
    while (iter.next()) |proc| {
        // Kill if still running
        if (!proc.*.exited) {
            _ = pty.killProcess(proc.*.pid, 9) catch {};
        }

        // Close master fd
        if (proc.*.master_fd >= 0) {
            pty.closePty(proc.*.master_fd);
            proc.*.master_fd = -1;
        }

        // Stop timers and poll (libuv will close them during event_loop.deinit)
        if (proc.*.poll_active) {
            _ = pty.pollStop(proc.*.poll_handle.ptr()) catch {};
            // Clear data pointer so close callback doesn't use freed memory
            uv.setHandleData(proc.*.poll_handle.handle(), null);
            proc.*.poll_active = false;
        }
        if (proc.*.check_timer_active) {
            _ = uv.timerStop(proc.*.check_timer.ptr()) catch {};
            uv.setHandleData(proc.*.check_timer.handle(), null);
            proc.*.check_timer_active = false;
        }
        if (proc.*.timeout_active) {
            _ = uv.timerStop(proc.*.timeout_timer.ptr()) catch {};
            uv.setHandleData(proc.*.timeout_timer.handle(), null);
            proc.*.timeout_active = false;
        }
    }
    registry_mutex.unlock();

    // Mark as deinitialized but DON'T destroy structs or free hashmap yet.
    // The event loop's closeAllHandlesCallback will clean up libuv handles,
    // and since we cleared data pointers, our callbacks won't be called.
    // This is a controlled memory leak at shutdown - acceptable for cleanup.
    registry_initialized = false;
    pool_initialized = false;
    global_ctx = null;
}
