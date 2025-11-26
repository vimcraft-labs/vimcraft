/// Process API for JavaScript plugins
/// Provides Node.js-style process information and child process spawning
///
/// Includes both synchronous spawn() and async spawnAsync() for LSP/long-running processes.
/// Async implementation uses libuv for event-loop integration.
const std = @import("std");
const c = @import("c_api.zig").c;
const builtin = @import("builtin");
const event_loop = @import("../event_loop/libuv.zig");
const uv = event_loop.uv;

/// Context passed to all process functions
pub const ProcessContext = struct {
    allocator: std.mem.Allocator,
    runtime: ?*c.OVHermesRuntime = null,
};

// ============================================================================
// Async Process Management (for LSP, long-running subprocesses)
// ============================================================================

/// Global context for async process callbacks
var global_process_ctx: ?*ProcessContext = null;

/// Async process handle - tracks a running subprocess
const AsyncProcess = struct {
    id: u32,
    allocator: std.mem.Allocator,

    // libuv handles
    process: uv.uv_process_t,
    stdin_pipe: uv.uv_pipe_t,
    stdout_pipe: uv.uv_pipe_t,
    stderr_pipe: uv.uv_pipe_t,

    // Process state
    running: bool = true,
    exit_code: i64 = 0,
    exit_signal: i32 = 0,

    // Read buffers
    stdout_buf: std.ArrayList(u8),
    stderr_buf: std.ArrayList(u8),
};

/// Registry of active async processes
var async_processes: std.AutoHashMapUnmanaged(u32, *AsyncProcess) = .empty;
var next_process_id: u32 = 1;

/// Pending events to deliver to JavaScript
const ProcessEvent = struct {
    process_id: u32,
    event_type: EventType,
    data: ?[]const u8,
    code: i64,
    signal: i32,

    const EventType = enum {
        stdout,
        stderr,
        exit,
        @"error",
    };
};

var pending_events: std.ArrayListUnmanaged(ProcessEvent) = .empty;
var pending_events_allocator: ?std.mem.Allocator = null;

// ============================================================================
// Host Object Getter
// ============================================================================

pub export fn processHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    // Properties (not functions)
    if (std.mem.eql(u8, name, "platform")) {
        const platform = switch (builtin.os.tag) {
            .macos => "darwin",
            .linux => "linux",
            .windows => "windows",
            else => "unknown",
        };
        return c.hermes_value_create_string(runtime, platform.ptr, platform.len);
    }

    if (std.mem.eql(u8, name, "arch")) {
        const arch = switch (builtin.cpu.arch) {
            .aarch64 => "arm64",
            .x86_64 => "x64",
            .x86 => "x86",
            else => "unknown",
        };
        return c.hermes_value_create_string(runtime, arch.ptr, arch.len);
    }

    if (std.mem.eql(u8, name, "env")) {
        return createEnvObject(runtime);
    }

    // Functions
    const FunctionMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "cwd", cwd },
        .{ "spawn", spawn },
        .{ "spawnAsync", spawnAsync },
        .{ "killProcess", killProcess },
        .{ "writeToProcess", writeToProcess },
        .{ "exit", exit },
    });

    const func = FunctionMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

// ============================================================================
// Process Functions
// ============================================================================

/// process.cwd() -> string
fn cwd(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    var buf: [4096]u8 = undefined;
    const current_dir = std.posix.getcwd(&buf) catch {
        c.hermes_throw_error(runtime, "Failed to get current directory");
        return null;
    };
    return c.hermes_value_create_string(runtime, current_dir.ptr, current_dir.len);
}

/// process.spawn(command, args?, options?) -> {stdout, stderr, code}
fn spawn(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "process.spawn requires a command argument");
        return null;
    }

    const ctx: *ProcessContext = @ptrCast(@alignCast(context));
    const cmd_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid command argument");
        return null;
    };

    // Get command string
    var cmd_len: usize = 0;
    const cmd_ptr = c.hermes_value_get_string(runtime, cmd_val, &cmd_len);
    if (cmd_ptr == null or cmd_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get command string");
        return null;
    }

    // Build argv
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(ctx.allocator);

    // Add command
    const cmd_copy = ctx.allocator.dupe(u8, cmd_ptr[0..cmd_len]) catch {
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };
    argv.append(ctx.allocator, cmd_copy) catch {
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Add args if provided
    if (arg_count >= 2) {
        const args_val = args[1];
        if (args_val != null) {
            // Check if it's an array by trying to get length
            // TODO: Add hermes_value_is_array to C API for proper type checking
            var i: usize = 0;
            var idx_buf: [16]u8 = undefined;
            while (i < 100) : (i += 1) { // Max 100 args
                const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch break;
                idx_buf[idx_str.len] = 0; // Null terminate
                const elem = c.hermes_value_get_property(runtime, args_val, @ptrCast(&idx_buf));
                if (elem == null or c.hermes_value_is_undefined(elem)) break;

                if (c.hermes_value_is_string(elem)) {
                    var arg_len: usize = 0;
                    const arg_ptr = c.hermes_value_get_string(runtime, elem, &arg_len);
                    if (arg_ptr != null and arg_len > 0) {
                        const arg_copy = ctx.allocator.dupe(u8, arg_ptr[0..arg_len]) catch continue;
                        argv.append(ctx.allocator, arg_copy) catch continue;
                    }
                }
                c.hermes_value_destroy(elem);
            }
        }
    }

    // Get options (cwd) - optional
    var spawn_cwd: ?[]const u8 = null;
    if (arg_count >= 3) {
        const opts_val = args[2];
        if (opts_val != null and c.hermes_value_is_object(opts_val)) {
            const cwd_prop = c.hermes_value_get_property(runtime, opts_val, "cwd");
            if (cwd_prop != null and c.hermes_value_is_string(cwd_prop)) {
                var cwd_len: usize = 0;
                const cwd_ptr = c.hermes_value_get_string(runtime, cwd_prop, &cwd_len);
                if (cwd_ptr != null and cwd_len > 0) {
                    spawn_cwd = ctx.allocator.dupe(u8, cwd_ptr[0..cwd_len]) catch null;
                }
            }
            if (cwd_prop != null) c.hermes_value_destroy(cwd_prop);
        }
    }

    defer {
        for (argv.items) |arg| {
            ctx.allocator.free(arg);
        }
        if (spawn_cwd) |dir| {
            ctx.allocator.free(dir);
        }
    }

    if (argv.items.len == 0) {
        c.hermes_throw_error(runtime, "No command provided");
        return null;
    }

    // Spawn process using Child.init with []const []const u8
    var child = std.process.Child.init(argv.items, ctx.allocator);

    if (spawn_cwd) |dir| {
        child.cwd = dir;
    }

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch {
        c.hermes_throw_error(runtime, "Failed to spawn process");
        return null;
    };

    // Read output using readToEndAlloc (Zig 0.15+ API)
    const stdout = if (child.stdout) |stdout_pipe| blk: {
        break :blk stdout_pipe.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else "";
    defer if (stdout.len > 0) ctx.allocator.free(stdout);

    const stderr = if (child.stderr) |stderr_pipe| blk: {
        break :blk stderr_pipe.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else "";
    defer if (stderr.len > 0) ctx.allocator.free(stderr);

    // Wait for process
    const term = child.wait() catch {
        c.hermes_throw_error(runtime, "Failed to wait for process");
        return null;
    };

    const exit_code: i32 = switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => |sig| -@as(i32, @intCast(sig)),
        else => -1,
    };

    // Create result object
    const obj = c.hermes_value_create_object(runtime);
    if (obj == null) {
        c.hermes_throw_error(runtime, "Failed to create object");
        return null;
    }

    c.hermes_value_set_property(
        runtime,
        obj,
        "stdout",
        c.hermes_value_create_string(runtime, stdout.ptr, stdout.len),
    );

    c.hermes_value_set_property(
        runtime,
        obj,
        "stderr",
        c.hermes_value_create_string(runtime, stderr.ptr, stderr.len),
    );

    c.hermes_value_set_property(
        runtime,
        obj,
        "code",
        c.hermes_value_create_number(runtime, @floatFromInt(exit_code)),
    );

    return obj;
}

/// process.exit(code?) -> void
fn exit(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    var code: u8 = 0;

    if (arg_count >= 1) {
        const code_val = args[0];
        if (code_val != null and c.hermes_value_is_number(code_val)) {
            const code_num = c.hermes_value_get_number(code_val);
            code = @intFromFloat(@max(0, @min(255, code_num)));
        }
    }

    std.posix.exit(code);
}

// ============================================================================
// Helper Functions
// ============================================================================

fn createEnvObject(runtime: ?*c.OVHermesRuntime) ?*c.OVHermesValue {
    const obj = c.hermes_value_create_object(runtime);
    if (obj == null) return null;

    // Get common environment variables
    const env_vars = [_][]const u8{
        "HOME",
        "PATH",
        "USER",
        "SHELL",
        "TERM",
        "EDITOR",
        "LANG",
        "LC_ALL",
        "PWD",
        "TMPDIR",
        "XDG_CONFIG_HOME",
        "XDG_DATA_HOME",
        "XDG_CACHE_HOME",
    };

    for (env_vars) |name| {
        if (std.posix.getenv(name)) |value| {
            c.hermes_value_set_property(
                runtime,
                obj,
                name.ptr,
                c.hermes_value_create_string(runtime, value.ptr, value.len),
            );
        }
    }

    return obj;
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, context: *ProcessContext) void {
    c.hermes_register_host_object(
        runtime,
        "__process",
        processHostObjectGet,
        null, // No setter
        null, // No enumerator
        @ptrCast(context),
    );
}
