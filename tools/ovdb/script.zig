const std = @import("std");
const client = @import("client.zig");

/// Script command - parsed from .ovdb file
pub const ScriptCommand = struct {
    line_number: usize,
    raw_line: []const u8,
    cmd_type: client.protocol.CommandType,
    args: client.protocol.CommandArgs,

    pub fn deinit(self: *ScriptCommand, allocator: std.mem.Allocator) void {
        // Free args based on type
        switch (self.args) {
            .execute_keys => |a| allocator.free(a.keys),
            .load_file => |a| allocator.free(a.path),
            .assert_mode => |a| allocator.free(a.mode),
            .assert_visual_mode => |a| allocator.free(a.mode),
            .assert_register => |a| allocator.free(a.text),
            .assert_line => |a| allocator.free(a.text),
            else => {},
        }
        allocator.free(self.raw_line);
    }
};

/// Test status
pub const TestStatus = enum {
    pass,
    fail,
    @"error",
};

/// Test result for a single command
pub const TestResult = struct {
    command: []const u8,
    status: TestStatus,
    duration_ms: f64,
    error_message: ?[]const u8,
    expected: ?[]const u8,
    actual: ?[]const u8,

    pub fn deinit(self: *TestResult, allocator: std.mem.Allocator) void {
        allocator.free(self.command);
        if (self.error_message) |msg| allocator.free(msg);
        if (self.expected) |exp| allocator.free(exp);
        if (self.actual) |act| allocator.free(act);
    }
};

/// Script execution results
pub const ScriptResults = struct {
    script_path: []const u8,
    total: usize,
    passed: usize,
    failed: usize,
    errors: usize,
    results: std.ArrayList(TestResult),
    total_duration_ms: f64,

    pub fn init(allocator: std.mem.Allocator, script_path: []const u8) !ScriptResults {
        return .{
            .script_path = try allocator.dupe(u8, script_path),
            .total = 0,
            .passed = 0,
            .failed = 0,
            .errors = 0,
            .results = .empty,
            .total_duration_ms = 0,
        };
    }

    pub fn deinit(self: *ScriptResults, allocator: std.mem.Allocator) void {
        for (self.results.items) |*result| {
            result.deinit(allocator);
        }
        self.results.deinit(allocator);
        allocator.free(self.script_path);
    }

    pub fn addResult(self: *ScriptResults, allocator: std.mem.Allocator, result: TestResult) !void {
        try self.results.append(allocator, result);
        self.total += 1;
        self.total_duration_ms += result.duration_ms;

        switch (result.status) {
            .pass => self.passed += 1,
            .fail => self.failed += 1,
            .@"error" => self.errors += 1,
        }
    }
};

/// Parse a .ovdb script file
pub fn parseScript(allocator: std.mem.Allocator, script_path: []const u8) !std.ArrayList(ScriptCommand) {
    var commands: std.ArrayList(ScriptCommand) = .empty;
    errdefer {
        for (commands.items) |*cmd| {
            cmd.deinit(allocator);
        }
        commands.deinit(allocator);
    }

    // Read file
    const file = try std.fs.cwd().openFile(script_path, .{});
    defer file.close();

    var file_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&file_buf);
    const reader = &file_reader.interface;

    var line_number: usize = 0;

    while (true) {
        const line = reader.*.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        line_number += 1;
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Parse command
        const cmd = try parseScriptLine(allocator, trimmed, line_number);
        try commands.append(allocator, cmd);
    }

    return commands;
}

/// Parse a single script line into a command
fn parseScriptLine(allocator: std.mem.Allocator, line: []const u8, line_number: usize) !ScriptCommand {
    var iter = std.mem.splitScalar(u8, line, ' ');
    const cmd_str = iter.next() orelse return error.EmptyCommand;

    // Determine command type and parse arguments
    if (std.mem.eql(u8, cmd_str, "ping")) {
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .ping,
            .args = .{ .none = {} },
        };
    } else if (std.mem.eql(u8, cmd_str, "get_state")) {
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .get_state,
            .args = .{ .none = {} },
        };
    } else if (std.mem.eql(u8, cmd_str, "get_cursor")) {
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .get_cursor,
            .args = .{ .none = {} },
        };
    } else if (std.mem.eql(u8, cmd_str, "get_mode")) {
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .get_mode,
            .args = .{ .none = {} },
        };
    } else if (std.mem.eql(u8, cmd_str, "execute_keys")) {
        const keys = iter.rest();
        if (keys.len == 0) return error.MissingArgument;
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .execute_keys,
            .args = .{ .execute_keys = .{ .keys = try allocator.dupe(u8, keys) } },
        };
    } else if (std.mem.eql(u8, cmd_str, "load_file")) {
        const path = iter.rest();
        if (path.len == 0) return error.MissingArgument;
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .load_file,
            .args = .{ .load_file = .{ .path = try allocator.dupe(u8, path) } },
        };
    } else if (std.mem.eql(u8, cmd_str, "assert_cursor")) {
        const line_arg = iter.next() orelse return error.MissingArgument;
        const col_arg = iter.next() orelse return error.MissingArgument;
        const line_num = try std.fmt.parseInt(usize, line_arg, 10);
        const col_num = try std.fmt.parseInt(usize, col_arg, 10);
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .assert_cursor,
            .args = .{ .assert_cursor = .{ .line = line_num, .col = col_num } },
        };
    } else if (std.mem.eql(u8, cmd_str, "assert_mode")) {
        const mode = iter.rest();
        if (mode.len == 0) return error.MissingArgument;
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .assert_mode,
            .args = .{ .assert_mode = .{ .mode = try allocator.dupe(u8, mode) } },
        };
    } else if (std.mem.eql(u8, cmd_str, "assert_visual_active")) {
        const active_str = iter.next() orelse return error.MissingArgument;
        const active = std.mem.eql(u8, active_str, "true");
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .assert_visual_active,
            .args = .{ .assert_visual_active = .{ .active = active } },
        };
    } else if (std.mem.eql(u8, cmd_str, "assert_register")) {
        const name_str = iter.next() orelse return error.MissingArgument;
        const text = iter.rest();
        if (name_str.len != 1) return error.InvalidRegisterName;
        if (text.len == 0) return error.MissingArgument;
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .assert_register,
            .args = .{ .assert_register = .{ .name = name_str[0], .text = try allocator.dupe(u8, text) } },
        };
    } else if (std.mem.eql(u8, cmd_str, "shutdown")) {
        return ScriptCommand{
            .line_number = line_number,
            .raw_line = try allocator.dupe(u8, line),
            .cmd_type = .shutdown,
            .args = .{ .none = {} },
        };
    } else {
        return error.UnknownCommand;
    }
}

/// Execute a script and return results
pub fn executeScript(
    allocator: std.mem.Allocator,
    ovdb_client: *client.Client,
    commands: []const ScriptCommand,
    script_path: []const u8,
) !ScriptResults {
    var results = try ScriptResults.init(allocator, script_path);
    errdefer results.deinit(allocator);

    for (commands) |cmd| {
        const start = std.time.milliTimestamp();

        // Execute command
        var response = ovdb_client.sendCommand(cmd.cmd_type, cmd.args) catch |err| {
            // Network/communication error
            const duration_ms = @as(f64, @floatFromInt(std.time.milliTimestamp() - start));
            const err_msg = try std.fmt.allocPrint(allocator, "Communication error: {}", .{err});
            try results.addResult(allocator, .{
                .command = try allocator.dupe(u8, cmd.raw_line),
                .status = .@"error",
                .duration_ms = duration_ms,
                .error_message = err_msg,
                .expected = null,
                .actual = null,
            });
            continue;
        };
        defer response.deinit(allocator);

        const duration_ms = @as(f64, @floatFromInt(std.time.milliTimestamp() - start));

        // Check response status
        if (response.status == .@"error") {
            // Server returned error
            const err_msg = if (response.@"error") |e|
                try allocator.dupe(u8, e)
            else
                try allocator.dupe(u8, "Unknown error");

            try results.addResult(allocator, .{
                .command = try allocator.dupe(u8, cmd.raw_line),
                .status = .@"error",
                .duration_ms = duration_ms,
                .error_message = err_msg,
                .expected = null,
                .actual = null,
            });
            continue;
        }

        // Check if this is an assertion
        const is_assertion = switch (cmd.cmd_type) {
            .assert_cursor, .assert_mode, .assert_visual_active, .assert_visual_mode, .assert_register, .assert_line => true,
            else => false,
        };

        if (is_assertion and response.result != null) {
            const assertion = response.result.?.assertion;
            const status: TestStatus = if (assertion.match) .pass else .fail;

            try results.addResult(allocator, .{
                .command = try allocator.dupe(u8, cmd.raw_line),
                .status = status,
                .duration_ms = duration_ms,
                .error_message = null,
                .expected = if (assertion.expected) |e| try allocator.dupe(u8, e) else null,
                .actual = if (assertion.actual) |a| try allocator.dupe(u8, a) else null,
            });
        } else {
            // Non-assertion command - just mark as passed
            try results.addResult(allocator, .{
                .command = try allocator.dupe(u8, cmd.raw_line),
                .status = .pass,
                .duration_ms = duration_ms,
                .error_message = null,
                .expected = null,
                .actual = null,
            });
        }
    }

    return results;
}

// Tests
test "Script: parse simple commands" {
    const allocator = std.testing.allocator;

    const script =
        \\# Test script
        \\ping
        \\get_state
        \\execute_keys viw
    ;

    // Write to temp file
    const tmp_file = try std.fs.cwd().createFile("test_script.ovdb", .{});
    defer std.fs.cwd().deleteFile("test_script.ovdb") catch {};
    defer tmp_file.close();

    try tmp_file.writeAll(script);
    try tmp_file.sync();

    // Parse
    var commands = try parseScript(allocator, "test_script.ovdb");
    defer {
        for (commands.items) |*cmd| {
            cmd.deinit(allocator);
        }
        commands.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), commands.items.len);
    try std.testing.expectEqual(client.protocol.CommandType.ping, commands.items[0].cmd_type);
    try std.testing.expectEqual(client.protocol.CommandType.get_state, commands.items[1].cmd_type);
    try std.testing.expectEqual(client.protocol.CommandType.execute_keys, commands.items[2].cmd_type);
}

test "Script: parse assertion commands" {
    const allocator = std.testing.allocator;

    const script =
        \\assert_cursor 5 10
        \\assert_mode VISUAL
        \\assert_visual_active true
    ;

    const tmp_file = try std.fs.cwd().createFile("test_assertions.ovdb", .{});
    defer std.fs.cwd().deleteFile("test_assertions.ovdb") catch {};
    defer tmp_file.close();

    try tmp_file.writeAll(script);
    try tmp_file.sync();

    var commands = try parseScript(allocator, "test_assertions.ovdb");
    defer {
        for (commands.items) |*cmd| {
            cmd.deinit(allocator);
        }
        commands.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), commands.items.len);
    try std.testing.expectEqual(client.protocol.CommandType.assert_cursor, commands.items[0].cmd_type);
    try std.testing.expectEqual(@as(usize, 5), commands.items[0].args.assert_cursor.line);
    try std.testing.expectEqual(@as(usize, 10), commands.items[0].args.assert_cursor.col);
}
