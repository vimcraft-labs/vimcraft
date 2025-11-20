const std = @import("std");
const posix = std.posix;

/// Pseudoterminal wrapper for testing terminal applications
/// Uses POSIX openpty() to create master/slave pty pair
pub const Pty = struct {
    master: std.fs.File,
    slave_fd: posix.fd_t,
    pid: ?posix.pid_t,
    allocator: std.mem.Allocator,

    /// Spawn a process in a pseudoterminal
    /// The process's stdin/stdout/stderr will be connected to the pty
    /// If env is provided, it will be used instead of inheriting parent's environment
    pub fn spawn(
        allocator: std.mem.Allocator,
        argv: []const []const u8,
    ) !Pty {
        return spawnWithEnv(allocator, argv, null);
    }

    /// Spawn with custom environment variables
    /// env_map: HashMap where keys and values are environment variable names and values
    pub fn spawnWithEnv(
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        env_map: ?*const std.process.EnvMap,
    ) !Pty {
        if (argv.len == 0) return error.EmptyArgv;

        // Call C openpty() function
        // Note: Zig doesn't have openpty in std, so we use C FFI
        const c = @cImport({
            @cInclude("util.h"); // macOS: openpty is in util.h
            @cInclude("termios.h");
            @cInclude("unistd.h"); // setsid
            @cInclude("sys/ioctl.h"); // ioctl, TIOCSCTTY
        });

        var master: c_int = undefined;
        var slave: c_int = undefined;

        // openpty(master, slave, name, termp, winp)
        if (c.openpty(&master, &slave, null, null, null) != 0) {
            return error.OpenPtyFailed;
        }
        errdefer posix.close(master);

        // Fork child process
        const pid = try posix.fork();

        if (pid == 0) {
            // Child process
            posix.close(master);

            // Become session leader (detach from parent's terminal)
            if (c.setsid() == -1) {
                posix.exit(1); // setsid failed
            }

            // Make the slave PTY the controlling terminal for this session
            // TIOCSCTTY = 0x20007461 on macOS, 0x540E on Linux
            const TIOCSCTTY: c_ulong = if (@import("builtin").os.tag == .macos) 0x20007461 else 0x540E;
            if (c.ioctl(slave, TIOCSCTTY, @as(c_int, 0)) == -1) {
                posix.exit(1); // ioctl failed
            }

            // Redirect stdin/stdout/stderr to pty slave
            posix.dup2(slave, posix.STDIN_FILENO) catch posix.exit(1);
            posix.dup2(slave, posix.STDOUT_FILENO) catch posix.exit(1);
            posix.dup2(slave, posix.STDERR_FILENO) catch posix.exit(1);

            // Close slave fd (already duped to 0/1/2)
            if (slave > 2) posix.close(slave);

            // Convert argv to C strings in child process
            // Use stack allocation (safer than heap after fork)
            var argv_storage: [256][256:0]u8 = undefined;
            var argv_ptrs: [257:null]?[*:0]const u8 = undefined;

            for (argv, 0..) |arg, i| {
                if (arg.len >= 256) posix.exit(1); // Arg too long
                @memcpy(argv_storage[i][0..arg.len], arg);
                argv_storage[i][arg.len] = 0;
                argv_ptrs[i] = @ptrCast(&argv_storage[i]);
            }
            argv_ptrs[argv.len] = null;

            // Build environment (custom or inherited)
            var env_storage: [256][512:0]u8 = undefined;
            var env_ptrs: [257:null]?[*:0]const u8 = undefined;
            var env_count: usize = 0;

            if (env_map) |map| {
                // Use custom environment
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    if (env_count >= 256) break; // Too many vars

                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;

                    // Format as KEY=VALUE
                    var buf_len: usize = 0;
                    for (key) |ch| {
                        if (buf_len >= 511) break;
                        env_storage[env_count][buf_len] = ch;
                        buf_len += 1;
                    }
                    if (buf_len < 511) {
                        env_storage[env_count][buf_len] = '=';
                        buf_len += 1;
                    }
                    for (value) |ch| {
                        if (buf_len >= 511) break;
                        env_storage[env_count][buf_len] = ch;
                        buf_len += 1;
                    }
                    env_storage[env_count][buf_len] = 0;

                    env_ptrs[env_count] = @ptrCast(&env_storage[env_count]);
                    env_count += 1;
                }
                env_ptrs[env_count] = null;
            }

            // Use Zig's posix.execveZ - replaces current process with new program
            // execveZ never returns on success, only returns ExecveError on failure
            const environ_ptr: [*:null]const ?[*:0]const u8 = if (env_map != null)
                @ptrCast(@alignCast(&env_ptrs))
            else
                @ptrCast(@alignCast(std.os.environ.ptr));

            const err = posix.execveZ(
                argv_ptrs[0].?,
                &argv_ptrs,
                environ_ptr,
            );

            // If execveZ returns (which means it failed), just exit
            std.debug.print("execveZ failed: {}\n", .{err});
            posix.exit(1);
        }

        // Parent process
        // CRITICAL: Close slave in parent!
        // Child has its own copy via dup2, and keeping slave open in parent
        // prevents EOF signaling when child exits
        posix.close(slave);

        return Pty{
            .master = std.fs.File{ .handle = master },
            .slave_fd = -1, // Already closed
            .pid = pid,
            .allocator = allocator,
        };
    }

    /// Write data to pty (simulates user typing)
    pub fn write(self: *Pty, data: []const u8) !void {
        try self.master.writeAll(data);
    }

    /// Read data from pty with timeout
    /// Returns slice of buf that was filled
    /// Blocks up to timeout_ms milliseconds
    pub fn read(self: *Pty, buf: []u8, timeout_ms: i32) ![]const u8 {
        // Use poll() to wait for data with timeout
        var fds = [_]posix.pollfd{.{
            .fd = self.master.handle,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        const result = try posix.poll(&fds, timeout_ms);

        if (result == 0) {
            // Timeout - no data available
            return buf[0..0];
        }

        if (fds[0].revents & posix.POLL.IN != 0) {
            // Data available
            const n = try self.master.read(buf);
            return buf[0..n];
        }

        // Poll returned but no IN event (probably error/HUP)
        return buf[0..0];
    }

    /// Read all available data (non-blocking)
    /// Continues reading until no more data is immediately available
    pub fn readAll(self: *Pty, buf: []u8) ![]const u8 {
        var total: usize = 0;

        while (total < buf.len) {
            // Non-blocking poll (0ms timeout)
            var fds = [_]posix.pollfd{.{
                .fd = self.master.handle,
                .events = posix.POLL.IN,
                .revents = 0,
            }};

            const result = try posix.poll(&fds, 0);
            if (result == 0) break; // No more data

            if (fds[0].revents & posix.POLL.IN != 0) {
                const n = try self.master.read(buf[total..]);
                if (n == 0) break; // EOF
                total += n;
            } else {
                break;
            }
        }

        return buf[0..total];
    }

    /// Wait for process to complete
    pub fn wait(self: *Pty) !void {
        if (self.pid) |pid| {
            _ = posix.waitpid(pid, 0);
            self.pid = null;
        }
    }

    /// Kill the child process and clean up resources
    pub fn kill(self: *Pty) void {
        if (self.pid) |pid| {
            // Send SIGTERM
            posix.kill(pid, posix.SIG.TERM) catch {};

            // Wait up to 1 second for clean exit
            var process_exited = false;
            var waited: usize = 0;
            while (waited < 10) : (waited += 1) {
                const result = posix.waitpid(pid, posix.W.NOHANG);
                if (result.pid != 0) {
                    process_exited = true;
                    break;
                }
                std.Thread.sleep(100 * std.time.ns_per_ms);
            }

            // If still running, force kill
            if (!process_exited) {
                posix.kill(pid, posix.SIG.KILL) catch {};
                _ = posix.waitpid(pid, 0);
            }

            self.pid = null;
        }

        // Close master (slave was already closed in spawn)
        self.master.close();
    }

    /// Convenience: wait for specific text to appear in output
    /// Polls pty output and searches for pattern
    /// Returns true if found within timeout, false otherwise
    pub fn waitForText(
        self: *Pty,
        allocator: std.mem.Allocator,
        pattern: []const u8,
        timeout_ms: i32,
    ) !bool {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        const start_time = std.time.milliTimestamp();
        var buf: [4096]u8 = undefined;

        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            const data = try self.read(&buf, 100); // Poll every 100ms
            if (data.len > 0) {
                try output.appendSlice(data);

                // Check if pattern found
                if (std.mem.indexOf(u8, output.items, pattern) != null) {
                    return true;
                }
            }
        }

        return false;
    }
};

// Tests for Pty infrastructure
test "Pty: spawn and read from process" {
    const allocator = std.testing.allocator;

    // Spawn cat and send data
    const argv = [_][]const u8{"/bin/cat"};
    var pty = try Pty.spawn(allocator, &argv);
    defer pty.kill();

    // Write data
    try pty.write("Hello from PTY\n");

    // Read output
    var buf: [1024]u8 = undefined;
    const output = try pty.read(&buf, 1000);

    // Should echo back
    try std.testing.expect(std.mem.indexOf(u8, output, "Hello from PTY") != null);
}

test "Pty: write and read" {
    const allocator = std.testing.allocator;

    // Spawn cat (echoes input)
    const argv = [_][]const u8{"/bin/cat"};
    var pty = try Pty.spawn(allocator, &argv);
    defer pty.kill();

    // Write some data
    try pty.write("test data\n");

    // Read it back
    var buf: [1024]u8 = undefined;
    const output = try pty.read(&buf, 1000);

    // Should echo back what we sent
    try std.testing.expect(std.mem.indexOf(u8, output, "test data") != null);
}
