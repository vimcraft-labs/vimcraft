const std = @import("std");
const protocol = @import("protocol.zig");
const json = @import("json.zig");
const state = @import("state.zig");
const Editor = @import("../core/editor.zig").Editor;

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
    editor: *Editor, // Reference to editor core

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig, editor: *Editor) Server {
        return .{
            .allocator = allocator,
            .config = config,
            .running = false,
            .editor = editor,
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
        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();

        var line_buffer: [8192]u8 = undefined;
        var line_pos: usize = 0;

        while (self.running) {
            // Read one byte at a time
            var char_buf: [1]u8 = undefined;
            const bytes_read = stdin.read(&char_buf) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (bytes_read == 0) break; // EOF

            const ch = char_buf[0];

            if (ch == '\n') {
                // End of line - process the command
                const line_str = line_buffer[0..line_pos];

                // Skip empty lines and whitespace-only lines
                const trimmed = std.mem.trim(u8, line_str, " \t\r");
                if (trimmed.len == 0) {
                    line_pos = 0;
                    continue;
                }

                // Parse command (use trimmed line)
                var cmd = json.parseCommand(trimmed, self.allocator) catch |err| {
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

                try stdout.writeAll(response_json);
                try stdout.writeAll("\n");
                line_pos = 0; // Reset for next line
                continue;
            };
            defer cmd.deinit(self.allocator);

            // Handle command and get response
            var response = try self.handleCommand(cmd);
            defer response.deinit(self.allocator);

            // Serialize and send response
            const response_json = try json.serializeResponse(response, self.allocator);
            defer self.allocator.free(response_json);

            try stdout.writeAll(response_json);
            try stdout.writeAll("\n");

            // Reset line buffer for next line
            line_pos = 0;
            } else {
                // Accumulate character into line buffer
                if (line_pos < line_buffer.len) {
                    line_buffer[line_pos] = ch;
                    line_pos += 1;
                } else {
                    // Line too long - send error and reset
                    const err_str = "Line too long (max 8192 bytes)";
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

                    try stdout.writeAll(response_json);
                    try stdout.writeAll("\n");

                    line_pos = 0; // Reset for next line
                }
            }
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
                return .{ .cursor = .{
                    .line = self.editor.buffer.cursor.row,
                    .col = self.editor.buffer.cursor.col,
                } };
            },

            .get_mode => {
                const mode_str = try self.allocator.dupe(u8, self.editor.mode_manager.getModeString());
                return .{ .mode = .{ .mode = mode_str } };
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

            .get_layers => {
                // TODO: Get layer system state from Display
                return error.NotImplemented;
            },

            .get_layer => {
                // TODO: Get specific layer state from Display
                return error.NotImplemented;
            },

            // Commands - execute keys in the editor
            .execute_keys => {
                const keys = cmd.args.execute_keys.keys;
                try self.editor.executeKeys(keys);
                return .{ .execute_keys = .{ .keys_processed = keys.len } };
            },

            .load_file => {
                const path = cmd.args.load_file.path;
                try self.editor.buffer.loadFile(path);
                return .{ .none = {} };
            },

            // Assertions - verify editor state matches expectations
            .assert_cursor => {
                const expected_line = cmd.args.assert_cursor.line;
                const expected_col = cmd.args.assert_cursor.col;
                const actual_line = self.editor.buffer.cursor.row;
                const actual_col = self.editor.buffer.cursor.col;

                const match = (expected_line == actual_line and expected_col == actual_col);

                if (!match) {
                    const expected = try std.fmt.allocPrint(self.allocator, "({d},{d})", .{ expected_line, expected_col });
                    const actual = try std.fmt.allocPrint(self.allocator, "({d},{d})", .{ actual_line, actual_col });
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected ({d},{d}), got ({d},{d})", .{ expected_line, expected_col, actual_line, actual_col });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },

            .assert_mode => {
                const expected_mode = cmd.args.assert_mode.mode;
                const actual_mode = self.editor.mode_manager.getModeString();

                const match = std.mem.eql(u8, expected_mode, actual_mode);

                if (!match) {
                    const expected = try self.allocator.dupe(u8, expected_mode);
                    const actual = try self.allocator.dupe(u8, actual_mode);
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected '{s}', got '{s}'", .{ expected_mode, actual_mode });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
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
                const line_num = cmd.args.assert_line.line;
                const expected_text = cmd.args.assert_line.text;

                const line = self.editor.buffer.getLine(line_num) orelse {
                    const diff = try std.fmt.allocPrint(self.allocator, "Line {d} does not exist", .{line_num});
                    return .{ .assertion = .{
                        .match = false,
                        .expected = try self.allocator.dupe(u8, expected_text),
                        .actual = try self.allocator.dupe(u8, "(line does not exist)"),
                        .diff = diff,
                    } };
                };

                // Remove trailing newline if present
                const actual_text = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                const match = std.mem.eql(u8, expected_text, actual_text);

                if (!match) {
                    const expected = try self.allocator.dupe(u8, expected_text);
                    const actual = try self.allocator.dupe(u8, actual_text);
                    const diff = try std.fmt.allocPrint(self.allocator, "Line {d}: Expected [{s}], got [{s}]", .{ line_num, expected_text, actual_text });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
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
