const std = @import("std");

// Import unified debug module (provided by build system)
const debug = @import("debug");
pub const protocol = debug.protocol;
pub const json = debug.json;

/// Client configuration
pub const ClientConfig = struct {
    socket_path: ?[]const u8 = null,
    use_stdio: bool = true,
    timeout_ms: u64 = 5000,
};

/// Debug client for connecting to OpenVim debug server
pub const Client = struct {
    allocator: std.mem.Allocator,
    config: ClientConfig,
    process: ?std.process.Child = null,
    connected: bool = false,
    request_id_counter: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, config: ClientConfig) Client {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Client) void {
        self.disconnect();
    }

    /// Connect to the debug server
    pub fn connect(self: *Client, openvim_path: []const u8) !void {
        if (self.connected) return;

        if (self.config.use_stdio) {
            // Spawn OpenVim process with --debug-protocol flag
            var child = std.process.Child.init(
                &[_][]const u8{ openvim_path, "--debug-protocol" },
                self.allocator,
            );

            child.stdin_behavior = .Pipe;
            child.stdout_behavior = .Pipe;
            child.stderr_behavior = .Inherit;

            try child.spawn();

            self.process = child;
            self.connected = true;
        } else if (self.config.socket_path) |_| {
            // TODO: Implement Unix socket connection
            return error.NotImplemented;
        } else {
            return error.InvalidConfiguration;
        }
    }

    /// Disconnect from the debug server
    pub fn disconnect(self: *Client) void {
        if (!self.connected) return;

        if (self.process) |*proc| {
            // Try to send shutdown command (ignore errors, best effort)
            if (self.sendCommand(.shutdown, .{ .none = {} })) |response| {
                var mut_response = response;
                mut_response.deinit(self.allocator);
            } else |_| {}

            // Wait for process to exit
            _ = proc.wait() catch {};
        }

        self.connected = false;
        self.process = null;
    }

    /// Generate a unique request ID
    fn nextRequestId(self: *Client) ![]const u8 {
        self.request_id_counter += 1;
        return try std.fmt.allocPrint(self.allocator, "req-{d}", .{self.request_id_counter});
    }

    /// Send a command and wait for response
    pub fn sendCommand(
        self: *Client,
        cmd_type: protocol.CommandType,
        args: protocol.CommandArgs,
    ) !protocol.Response {
        if (!self.connected) return error.NotConnected;

        const request_id = try self.nextRequestId();
        defer self.allocator.free(request_id);

        // Create command
        var cmd = try protocol.Command.init(
            self.allocator,
            request_id,
            cmd_type,
            args,
        );
        defer cmd.deinit(self.allocator);

        // Serialize command to JSON
        const cmd_json = try json.serializeCommand(cmd, self.allocator);
        defer self.allocator.free(cmd_json);

        // Send to server
        const stdin = self.process.?.stdin.?.writer();
        try stdin.print("{s}\n", .{cmd_json});

        // Read response
        const stdout = self.process.?.stdout.?.reader();
        var buf_reader = std.io.bufferedReader(stdout);
        var in_stream = buf_reader.reader();

        var line_buffer: [8192]u8 = undefined;
        const response_line = try in_stream.readUntilDelimiterOrEof(&line_buffer, '\n') orelse
            return error.UnexpectedEOF;

        // Parse response JSON
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_line, .{});
        defer parsed.deinit();

        // Extract response fields
        const root = parsed.value;
        const id = root.object.get("id").?.string;
        const status_str = root.object.get("status").?.string;
        const timestamp = @as(i64, @intCast(root.object.get("timestamp").?.integer));
        const duration_ns = @as(u64, @intCast(root.object.get("duration_ns").?.integer));

        const status: protocol.ResponseStatus = if (std.mem.eql(u8, status_str, "ok"))
            .ok
        else
            .@"error";

        // Extract result or error
        var result: ?protocol.ResponseResult = null;
        var err_msg: ?[]const u8 = null;

        if (status == .ok) {
            if (root.object.get("result")) |result_json| {
                result = try parseResponseResult(self.allocator, cmd_type, result_json);
            }
        } else {
            if (root.object.get("error")) |err_json| {
                err_msg = try self.allocator.dupe(u8, err_json.string);
            }
        }

        const owned_id = try self.allocator.dupe(u8, id);
        return protocol.Response{
            .id = owned_id,
            .status = status,
            .result = result,
            .@"error" = err_msg,
            .timestamp = timestamp,
            .duration_ns = duration_ns,
        };
    }

    /// Parse response result based on command type
    fn parseResponseResult(
        allocator: std.mem.Allocator,
        cmd_type: protocol.CommandType,
        result_json: std.json.Value,
    ) !protocol.ResponseResult {
        return switch (cmd_type) {
            .ping => .{
                .pong = .{
                    .version = try allocator.dupe(u8, result_json.object.get("version").?.string),
                },
            },

            .get_cursor => .{
                .cursor = .{
                    .line = @as(usize, @intCast(result_json.object.get("line").?.integer)),
                    .col = @as(usize, @intCast(result_json.object.get("col").?.integer)),
                },
            },

            .get_mode => .{
                .mode = .{
                    .mode = try allocator.dupe(u8, result_json.object.get("mode").?.string),
                },
            },

            .execute_keys => .{
                .execute_keys = .{
                    .keys_processed = @as(usize, @intCast(result_json.object.get("keys_processed").?.integer)),
                },
            },

            .assert_cursor, .assert_mode, .assert_visual_active, .assert_visual_mode, .assert_register, .assert_line => .{
                .assertion = .{
                    .match = result_json.object.get("match").?.bool,
                    .expected = if (result_json.object.get("expected")) |e|
                        try allocator.dupe(u8, e.string)
                    else
                        null,
                    .actual = if (result_json.object.get("actual")) |a|
                        try allocator.dupe(u8, a.string)
                    else
                        null,
                    .diff = if (result_json.object.get("diff")) |d|
                        try allocator.dupe(u8, d.string)
                    else
                        null,
                },
            },

            .shutdown => .{ .none = {} },

            // TODO: Implement parsing for complex result types
            else => .{ .none = {} },
        };
    }

    /// Ping the server to check if it's alive
    pub fn ping(self: *Client) !bool {
        var response = try self.sendCommand(.ping, .{ .none = {} });
        defer response.deinit(self.allocator);

        return response.status == .ok;
    }
};

// Tests
test "Client: init and deinit" {
    const allocator = std.testing.allocator;

    var client = Client.init(allocator, .{});
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "Client: generate request IDs" {
    const allocator = std.testing.allocator;

    var client = Client.init(allocator, .{});
    defer client.deinit();

    const id1 = try client.nextRequestId();
    defer allocator.free(id1);

    const id2 = try client.nextRequestId();
    defer allocator.free(id2);

    // IDs should be unique
    try std.testing.expect(!std.mem.eql(u8, id1, id2));
    try std.testing.expectEqualStrings("req-1", id1);
    try std.testing.expectEqualStrings("req-2", id2);
}
