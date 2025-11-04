const std = @import("std");
const protocol = @import("protocol.zig");
const json = @import("json.zig");
const state = @import("state.zig");

/// Debug server configuration
pub const ServerConfig = struct {
    socket_path: ?[]const u8 = null, // Unix socket path (e.g., "/tmp/openvim-debug.sock")
    use_stdio: bool = true, // Use stdin/stdout for communication
};

/// Debug server instance
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    running: bool,

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) Server {
        return .{
            .allocator = allocator,
            .config = config,
            .running = false,
        };
    }

    pub fn deinit(self: *Server) void {
        _ = self;
        // Cleanup resources if needed
    }

    /// Start the debug server
    pub fn start(self: *Server) !void {
        self.running = true;

        if (self.config.use_stdio) {
            try self.runStdio();
        } else if (self.config.socket_path) |_| {
            // TODO: Implement Unix socket server
            return error.NotImplemented;
        } else {
            return error.InvalidConfiguration;
        }
    }

    /// Stop the debug server
    pub fn stop(self: *Server) void {
        self.running = false;
    }

    /// Run server using stdin/stdout
    fn runStdio(self: *Server) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

        var buf_reader = std.io.bufferedReader(stdin);
        var in_stream = buf_reader.reader();

        while (self.running) {
            // Read line from stdin
            var line_buffer: [4096]u8 = undefined;
            const line = in_stream.readUntilDelimiterOrEof(&line_buffer, '\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            } orelse break;

            // Parse command
            var cmd = json.parseCommand(line, self.allocator) catch |err| {
                // Send error response for parse failure
                const err_str = try std.fmt.allocPrint(self.allocator, "Failed to parse command: {}", .{err});
                defer self.allocator.free(err_str);

                const response = try json.createErrorResponse(
                    self.allocator,
                    "unknown",
                    err_str,
                    0,
                );
                defer {
                    var mut_response = response;
                    mut_response.deinit(self.allocator);
                }

                const response_json = try json.serializeResponse(response, self.allocator);
                defer self.allocator.free(response_json);

                try stdout.print("{s}\n", .{response_json});
                continue;
            };
            defer cmd.deinit(self.allocator);

            // Handle command and get response
            var response = try self.handleCommand(cmd);
            defer response.deinit(self.allocator);

            // Serialize and send response
            const response_json = try json.serializeResponse(response, self.allocator);
            defer self.allocator.free(response_json);

            try stdout.print("{s}\n", .{response_json});
        }
    }

    /// Handle a command and return a response
    fn handleCommand(self: *Server, cmd: protocol.Command) !protocol.Response {
        const start_time = std.time.nanoTimestamp();

        const result = self.executeCommand(cmd) catch |err| {
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
            const err_str = try std.fmt.allocPrint(self.allocator, "Command failed: {}", .{err});
            defer self.allocator.free(err_str);
            return json.createErrorResponse(self.allocator, cmd.id, err_str, duration);
        };

        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
        return json.createSuccessResponse(self.allocator, cmd.id, result, duration);
    }

    /// Execute a command and return the result
    /// This is where the actual command logic is implemented
    fn executeCommand(self: *Server, cmd: protocol.Command) !protocol.ResponseResult {
        return switch (cmd.cmd) {
            .ping => .{ .pong = .{ .version = protocol.PROTOCOL_VERSION } },

            .shutdown => {
                self.stop();
                return .{ .none = {} };
            },

            // State queries - these need to be hooked up to actual editor state
            .get_state => {
                // TODO: Get actual editor state from editor core
                return error.NotImplemented;
            },

            .get_cursor => {
                // TODO: Get actual cursor position from editor
                return error.NotImplemented;
            },

            .get_mode => {
                // TODO: Get actual mode from editor
                return error.NotImplemented;
            },

            .get_visual => {
                // TODO: Get actual visual state from editor
                return error.NotImplemented;
            },

            .get_registers => {
                // TODO: Get actual registers from editor
                return error.NotImplemented;
            },

            .get_register => {
                // TODO: Get specific register from editor
                return error.NotImplemented;
            },

            .get_buffer => {
                // TODO: Get buffer state from editor
                return error.NotImplemented;
            },

            // Commands - these need to be hooked up to actual editor operations
            .execute_keys => {
                // TODO: Execute keys in editor
                return error.NotImplemented;
            },

            .load_file => {
                // TODO: Load file in editor
                return error.NotImplemented;
            },

            // Assertions - these need to query editor state and compare
            .assert_cursor => {
                // TODO: Verify cursor position
                return error.NotImplemented;
            },

            .assert_mode => {
                // TODO: Verify mode
                return error.NotImplemented;
            },

            .assert_visual_active => {
                // TODO: Verify visual mode active
                return error.NotImplemented;
            },

            .assert_visual_mode => {
                // TODO: Verify visual mode type
                return error.NotImplemented;
            },

            .assert_register => {
                // TODO: Verify register content
                return error.NotImplemented;
            },

            .assert_line => {
                // TODO: Verify line content
                return error.NotImplemented;
            },

            // Performance
            .benchmark => {
                // TODO: Run benchmark
                return error.NotImplemented;
            },
        };
    }
};

// Tests
test "Server: init and deinit" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    try std.testing.expect(!server.running);
}

test "Server: handle ping command" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    var cmd = try protocol.Command.init(
        allocator,
        "test-1",
        .ping,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    var response = try server.handleCommand(cmd);
    defer response.deinit(allocator);

    try std.testing.expectEqual(protocol.ResponseStatus.ok, response.status);
    try std.testing.expect(response.result != null);
    try std.testing.expect(response.result.?.pong.version.len > 0);
}

test "Server: handle shutdown command" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    server.running = true;

    var cmd = try protocol.Command.init(
        allocator,
        "test-2",
        .shutdown,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    var response = try server.handleCommand(cmd);
    defer response.deinit(allocator);

    try std.testing.expectEqual(protocol.ResponseStatus.ok, response.status);
    try std.testing.expect(!server.running); // Should be stopped
}

test "Server: handle unimplemented command" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    var cmd = try protocol.Command.init(
        allocator,
        "test-3",
        .get_state,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    var response = try server.handleCommand(cmd);
    defer response.deinit(allocator);

    // Should return error since get_state is not yet implemented
    try std.testing.expectEqual(protocol.ResponseStatus.@"error", response.status);
    try std.testing.expect(response.@"error" != null);
}
