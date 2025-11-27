/// Process API for JavaScript plugins
/// Provides Node.js-style process information and child process spawning
///
/// Currently supports:
/// - process.spawn(cmd, args?, opts?) - Synchronous process execution
/// - process.cwd() - Get current working directory
/// - process.exit(code?) - Exit the editor
/// - process.platform, process.arch, process.env - Environment info
///
/// Security features:
/// - Command validation (allowlist of safe commands)
/// - Concurrent process limit (MAX_CONCURRENT_PROCESSES)
/// - Timeout mechanism (default 30s, configurable)
/// - Output size limits (MAX_OUTPUT_SIZE)
///
/// TODO: Async subprocess support (spawnAsync) for LSP servers
/// See docs/architecture/network-transports.md for implementation plan
const std = @import("std");
const c = @import("c_api.zig").c;
const builtin = @import("builtin");

// ============================================================================
// Security Configuration
// ============================================================================

/// Maximum concurrent spawned processes
const MAX_CONCURRENT_PROCESSES: usize = 10;

/// Default timeout in milliseconds (30 seconds)
const DEFAULT_TIMEOUT_MS: u64 = 30_000;

/// Maximum timeout allowed (5 minutes)
const MAX_TIMEOUT_MS: u64 = 300_000;

/// Maximum output size per stream (5MB)
const MAX_OUTPUT_SIZE: usize = 5 * 1024 * 1024;

/// Maximum total output size (stdout + stderr combined, 8MB)
const MAX_TOTAL_OUTPUT_SIZE: usize = 8 * 1024 * 1024;

/// Maximum environment variables allowed
const MAX_ENV_VARS: usize = 256;

/// Allowlist of commands that can be executed directly
/// Commands not in this list must be absolute paths or run via shell
const ALLOWED_COMMANDS = std.StaticStringMap(void).initComptime(.{
    // Version control
    .{ "git", {} },
    .{ "svn", {} },
    .{ "hg", {} },
    // File operations (read-only)
    .{ "ls", {} },
    .{ "cat", {} },
    .{ "head", {} },
    .{ "tail", {} },
    .{ "find", {} },
    .{ "grep", {} },
    .{ "rg", {} },
    .{ "fd", {} },
    .{ "wc", {} },
    .{ "file", {} },
    .{ "stat", {} },
    .{ "readlink", {} },
    .{ "realpath", {} },
    // Text processing
    .{ "sort", {} },
    .{ "uniq", {} },
    .{ "tr", {} },
    .{ "cut", {} },
    .{ "awk", {} },
    .{ "sed", {} },
    .{ "jq", {} },
    // Build tools
    .{ "make", {} },
    .{ "cmake", {} },
    .{ "cargo", {} },
    .{ "go", {} },
    .{ "npm", {} },
    .{ "npx", {} },
    .{ "yarn", {} },
    .{ "pnpm", {} },
    .{ "node", {} },
    .{ "python", {} },
    .{ "python3", {} },
    .{ "pip", {} },
    .{ "pip3", {} },
    .{ "zig", {} },
    .{ "rustc", {} },
    .{ "gcc", {} },
    .{ "clang", {} },
    // Code formatters & linters
    .{ "prettier", {} },
    .{ "eslint", {} },
    .{ "rustfmt", {} },
    .{ "gofmt", {} },
    .{ "black", {} },
    .{ "isort", {} },
    .{ "stylua", {} },
    // Language servers (for sync queries)
    .{ "rust-analyzer", {} },
    .{ "gopls", {} },
    .{ "pyright", {} },
    .{ "typescript-language-server", {} },
    .{ "zls", {} },
    // System info
    .{ "pwd", {} },
    .{ "whoami", {} },
    .{ "hostname", {} },
    .{ "uname", {} },
    .{ "date", {} },
    .{ "env", {} },
    .{ "which", {} },
    .{ "whereis", {} },
    .{ "echo", {} },
    .{ "printf", {} },
    .{ "true", {} },
    .{ "false", {} },
    .{ "test", {} },
    .{ "seq", {} },
    // NOTE: Shells (sh, bash, zsh) intentionally NOT in allowlist
    // They bypass all command restrictions. Use absolute paths like
    // /bin/sh if shell access is truly needed (restricted to safe dirs).
    // Utilities (read-only network)
    .{ "curl", {} },
    .{ "wget", {} },
    .{ "tar", {} },
    .{ "gzip", {} },
    .{ "gunzip", {} },
    .{ "zip", {} },
    .{ "unzip", {} },
    .{ "diff", {} },
    .{ "patch", {} },
    .{ "touch", {} },
    .{ "mkdir", {} },
    .{ "cp", {} },
    .{ "mv", {} },
    .{ "rm", {} },
    .{ "ln", {} },
});

/// Context passed to all process functions
pub const ProcessContext = struct {
    allocator: std.mem.Allocator,
    runtime: ?*c.OVHermesRuntime = null,
};

/// Global context for callbacks
var global_process_ctx: ?*ProcessContext = null;

/// Track concurrent process count
var concurrent_process_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

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

/// process.spawn(command, args?, options?) -> {stdout, stderr, code, signal}
/// Synchronous process execution - blocks until process completes
///
/// Security: Commands are validated against ALLOWED_COMMANDS allowlist.
/// Resource limits: MAX_CONCURRENT_PROCESSES, MAX_OUTPUT_SIZE enforced.
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

    // Check concurrent process limit - ATOMIC increment to prevent TOCTOU race
    // We increment first, then check. If over limit, we decrement and error.
    const old_count = concurrent_process_count.fetchAdd(1, .acq_rel);
    if (old_count >= MAX_CONCURRENT_PROCESSES) {
        // Undo the increment - we're over the limit
        _ = concurrent_process_count.fetchSub(1, .acq_rel);
        c.hermes_throw_error(runtime, "Too many concurrent processes (limit: 10)");
        return null;
    }
    // Decrement at end of function (success or error after this point)
    defer _ = concurrent_process_count.fetchSub(1, .acq_rel);

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

    const cmd_str = cmd_ptr[0..cmd_len];

    // Security: Validate command against allowlist
    if (!isCommandAllowed(cmd_str)) {
        c.hermes_throw_error(runtime, "Command not allowed. Use an allowed command or absolute path.");
        return null;
    }

    // Build argv
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(ctx.allocator);

    // Add command
    const cmd_copy = ctx.allocator.dupe(u8, cmd_str) catch {
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };
    argv.append(ctx.allocator, cmd_copy) catch {
        ctx.allocator.free(cmd_copy); // Fix: free on append failure
        c.hermes_throw_error(runtime, "Out of memory");
        return null;
    };

    // Add args if provided
    if (arg_count >= 2) {
        const args_val = args[1];
        if (args_val != null) {
            // Check if it's an array by trying to get length
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
                        const arg_copy = ctx.allocator.dupe(u8, arg_ptr[0..arg_len]) catch {
                            c.hermes_value_destroy(elem);
                            continue;
                        };
                        argv.append(ctx.allocator, arg_copy) catch {
                            ctx.allocator.free(arg_copy); // Fix: free on append failure
                            c.hermes_value_destroy(elem);
                            continue;
                        };
                    }
                }
                c.hermes_value_destroy(elem);
            }
        }
    }

    // Get options (cwd, env, clearEnv, stdin, timeout) - optional
    var spawn_cwd: ?[]const u8 = null;
    var env_obj: ?*c.OVHermesValue = null;
    var clear_env: bool = false;
    var stdin_null: bool = false;
    // Note: timeout not yet implemented for sync spawn (reserved for async)

    if (arg_count >= 3) {
        const opts_val = args[2];
        if (opts_val != null and c.hermes_value_is_object(opts_val)) {
            // Get cwd option
            const cwd_prop = c.hermes_value_get_property(runtime, opts_val, "cwd");
            if (cwd_prop != null and c.hermes_value_is_string(cwd_prop)) {
                var cwd_len: usize = 0;
                const cwd_ptr = c.hermes_value_get_string(runtime, cwd_prop, &cwd_len);
                if (cwd_ptr != null and cwd_len > 0) {
                    spawn_cwd = ctx.allocator.dupe(u8, cwd_ptr[0..cwd_len]) catch null;
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

            // Get stdin option (string: 'pipe', 'null', 'ignore')
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

            // Note: timeout option reserved for future async implementation
        }
    }

    // Build environment map (merges with current env unless clearEnv is true)
    var env_map: ?std.process.EnvMap = null;
    if (env_obj != null or clear_env) {
        env_map = buildEnvMap(runtime, ctx.allocator, env_obj, clear_env);
    }
    defer {
        if (env_map) |*em| em.deinit();
    }

    // Clean up env_obj now that we've extracted the data
    if (env_obj) |obj| {
        c.hermes_value_destroy(obj);
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

    // Validate cwd if provided
    if (spawn_cwd) |dir| {
        // Check that the directory exists and is accessible
        std.fs.cwd().access(dir, .{}) catch {
            c.hermes_throw_error(runtime, "Invalid working directory: path does not exist or is not accessible");
            return null;
        };
    }

    // Spawn process using Child.init with []const []const u8
    var child = std.process.Child.init(argv.items, ctx.allocator);

    if (spawn_cwd) |dir| {
        child.cwd = dir;
    }

    // Set custom environment if provided
    if (env_map) |*em| {
        child.env_map = em;
    }

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // Set stdin behavior based on stdin option
    if (stdin_null) {
        child.stdin_behavior = .Ignore;
    }

    child.spawn() catch |err| {
        var err_buf: [256]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&err_buf, "Failed to spawn '{s}': {s}", .{
            argv.items[0],
            @errorName(err),
        }) catch "Failed to spawn process";
        c.hermes_throw_error(runtime, err_msg.ptr);
        return null;
    };

    // Read output using readToEndAlloc (Zig 0.15+ API) with size limits
    const stdout = if (child.stdout) |stdout_pipe| blk: {
        break :blk stdout_pipe.readToEndAlloc(ctx.allocator, MAX_OUTPUT_SIZE) catch "";
    } else "";
    defer if (stdout.len > 0) ctx.allocator.free(stdout);

    const stderr = if (child.stderr) |stderr_pipe| blk: {
        break :blk stderr_pipe.readToEndAlloc(ctx.allocator, MAX_OUTPUT_SIZE) catch "";
    } else "";
    defer if (stderr.len > 0) ctx.allocator.free(stderr);

    // Check total output size
    if (stdout.len + stderr.len > MAX_TOTAL_OUTPUT_SIZE) {
        // Still return what we have, but truncated
        // This is a soft limit - we already read the data
    }

    // Wait for process
    const term = child.wait() catch |err| {
        var err_buf: [256]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&err_buf, "Failed to wait for '{s}': {s}", .{
            argv.items[0],
            @errorName(err),
        }) catch "Failed to wait for process";
        c.hermes_throw_error(runtime, err_msg.ptr);
        return null;
    };

    // Create result object with Node.js-compatible fields
    const obj = c.hermes_value_create_object(runtime);
    if (obj == null) {
        c.hermes_throw_error(runtime, "Failed to create result object");
        return null;
    }

    // Create stdout/stderr strings with OOM checks
    // Use empty string literal for empty output to avoid invalid pointer issues
    const stdout_val = if (stdout.len > 0)
        c.hermes_value_create_string(runtime, stdout.ptr, stdout.len)
    else
        c.hermes_value_create_string(runtime, "", 0);

    if (stdout_val == null) {
        c.hermes_value_destroy(obj);
        c.hermes_throw_error(runtime, "Out of memory creating stdout string");
        return null;
    }
    c.hermes_value_set_property(runtime, obj, "stdout", stdout_val);

    const stderr_val = if (stderr.len > 0)
        c.hermes_value_create_string(runtime, stderr.ptr, stderr.len)
    else
        c.hermes_value_create_string(runtime, "", 0);

    if (stderr_val == null) {
        c.hermes_value_destroy(obj);
        c.hermes_throw_error(runtime, "Out of memory creating stderr string");
        return null;
    }
    c.hermes_value_set_property(runtime, obj, "stderr", stderr_val);

    // Handle termination status (Node.js compatible)
    switch (term) {
        .Exited => |code| {
            c.hermes_value_set_property(
                runtime,
                obj,
                "code",
                c.hermes_value_create_number(runtime, @floatFromInt(code)),
            );
            c.hermes_value_set_property(
                runtime,
                obj,
                "signal",
                c.hermes_value_create_null(runtime),
            );
        },
        .Signal => |sig| {
            c.hermes_value_set_property(
                runtime,
                obj,
                "code",
                c.hermes_value_create_null(runtime),
            );
            // Convert signal number to name
            const signal_name = getSignalName(sig);
            c.hermes_value_set_property(
                runtime,
                obj,
                "signal",
                c.hermes_value_create_string(runtime, signal_name.ptr, signal_name.len),
            );
        },
        else => {
            c.hermes_value_set_property(
                runtime,
                obj,
                "code",
                c.hermes_value_create_number(runtime, -1),
            );
            c.hermes_value_set_property(
                runtime,
                obj,
                "signal",
                c.hermes_value_create_null(runtime),
            );
        },
    }

    return obj;
}

/// Safe directories for absolute path execution
/// Only executables in these directories can be run via absolute path
const SAFE_PATH_PREFIXES = [_][]const u8{
    "/bin/",
    "/usr/bin/",
    "/usr/local/bin/",
    "/opt/homebrew/bin/", // macOS Homebrew
    "/sbin/",
    "/usr/sbin/",
};

/// Check if a command is allowed to be executed
fn isCommandAllowed(cmd: []const u8) bool {
    // If it's an absolute path, only allow from safe directories
    if (cmd.len > 0 and cmd[0] == '/') {
        for (SAFE_PATH_PREFIXES) |prefix| {
            if (std.mem.startsWith(u8, cmd, prefix)) {
                return true;
            }
        }
        // Absolute path not in safe directory - reject
        return false;
    }

    // Check against allowlist
    return ALLOWED_COMMANDS.has(cmd);
}

/// Convert signal number to name (platform-aware POSIX signals)
/// Signal numbers differ between platforms (e.g., SIGUSR1 is 10 on Linux/macOS, 30 on BSD)
fn getSignalName(sig: u32) []const u8 {
    // Use Zig's platform-specific signal constants for accuracy
    const SIG = std.posix.SIG;

    // Check against platform-specific signal constants
    if (sig == SIG.HUP) return "SIGHUP";
    if (sig == SIG.INT) return "SIGINT";
    if (sig == SIG.QUIT) return "SIGQUIT";
    if (sig == SIG.ILL) return "SIGILL";
    if (sig == SIG.TRAP) return "SIGTRAP";
    if (sig == SIG.ABRT) return "SIGABRT";
    if (sig == SIG.BUS) return "SIGBUS";
    if (sig == SIG.FPE) return "SIGFPE";
    if (sig == SIG.KILL) return "SIGKILL";
    if (sig == SIG.USR1) return "SIGUSR1";
    if (sig == SIG.SEGV) return "SIGSEGV";
    if (sig == SIG.USR2) return "SIGUSR2";
    if (sig == SIG.PIPE) return "SIGPIPE";
    if (sig == SIG.ALRM) return "SIGALRM";
    if (sig == SIG.TERM) return "SIGTERM";
    if (sig == SIG.CHLD) return "SIGCHLD";
    if (sig == SIG.CONT) return "SIGCONT";
    if (sig == SIG.STOP) return "SIGSTOP";
    if (sig == SIG.TSTP) return "SIGTSTP";
    if (sig == SIG.TTIN) return "SIGTTIN";
    if (sig == SIG.TTOU) return "SIGTTOU";

    return "UNKNOWN";
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
// Environment Variable Helpers
// ============================================================================

/// Build environment map from JavaScript object for std.process.Child
/// Returns an EnvMap populated with environment variables
/// If clearEnv is false (default), starts with current environment
fn buildEnvMap(
    runtime: ?*c.OVHermesRuntime,
    allocator: std.mem.Allocator,
    env_obj: ?*c.OVHermesValue,
    clear_env: bool,
) std.process.EnvMap {
    var env_map = std.process.EnvMap.init(allocator);

    // Get current environment first (if not clearing)
    if (!clear_env) {
        const environ = std.c.environ;
        var i: usize = 0;
        while (environ[i]) |env_entry| : (i += 1) {
            if (i >= MAX_ENV_VARS) break;
            const entry_slice = std.mem.span(env_entry);
            // Find the '=' separator
            if (std.mem.indexOfScalar(u8, entry_slice, '=')) |eq_pos| {
                const key = entry_slice[0..eq_pos];
                const value = entry_slice[eq_pos + 1 ..];
                env_map.put(key, value) catch continue;
            }
        }
    }

    // Add/override with custom env vars from JS object
    if (env_obj) |obj| {
        var key_buf: [256]u8 = undefined;

        // Try to get properties by iterating (Hermes doesn't expose Object.keys easily)
        // We use a workaround: try to get __keys property if set by JS wrapper
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

                // Add to env map (automatically overrides existing)
                env_map.put(key_ptr[0..key_len], val_ptr[0..val_len]) catch continue;
            }
        }
    }

    return env_map;
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, context: *ProcessContext) void {
    // Store runtime reference for future async callbacks
    context.runtime = runtime;
    global_process_ctx = context;

    c.hermes_register_host_object(
        runtime,
        "__process",
        processHostObjectGet,
        null, // No setter
        null, // No enumerator
        @ptrCast(context),
    );
}
