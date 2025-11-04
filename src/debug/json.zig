const std = @import("std");
const protocol = @import("protocol.zig");
const state = @import("state.zig");

/// JSON serialization for debug protocol
/// All protocol types can be serialized to/from JSON for LLM-friendly communication

/// Serialize Command to JSON
pub fn serializeCommand(command: protocol.Command, allocator: std.mem.Allocator) ![]const u8 {
    var string = std.ArrayList(u8).init(allocator);
    errdefer string.deinit();

    var writer = string.writer();
    try writer.writeAll("{");

    // ID
    try writer.print("\"id\":\"{s}\",", .{command.id});

    // Command type
    try writer.print("\"cmd\":\"{s}\",", .{command.cmd.toString()});

    // Args (based on command type)
    try writer.writeAll("\"args\":");
    try serializeCommandArgs(command.args, writer);
    try writer.writeAll(",");

    // Timestamp
    try writer.print("\"timestamp\":{d}", .{command.timestamp});

    try writer.writeAll("}");

    return string.toOwnedSlice();
}

fn serializeCommandArgs(args: protocol.CommandArgs, writer: anytype) !void {
    switch (args) {
        .none => try writer.writeAll("{}"),
        .get_register => |a| {
            try writer.print("{{\"name\":\"{c}\"}}", .{a.name});
        },
        .execute_keys => |a| {
            try writer.print("{{\"keys\":\"{s}\"}}", .{a.keys});
        },
        .load_file => |a| {
            try writer.print("{{\"path\":\"{s}\"}}", .{a.path});
        },
        .assert_cursor => |pos| {
            try writer.print("{{\"line\":{d},\"col\":{d}}}", .{ pos.line, pos.col });
        },
        .assert_mode => |a| {
            try writer.print("{{\"mode\":\"{s}\"}}", .{a.mode});
        },
        .assert_visual_active => |a| {
            try writer.print("{{\"active\":{}}}", .{a.active});
        },
        .assert_visual_mode => |a| {
            try writer.print("{{\"mode\":\"{s}\"}}", .{a.mode});
        },
        .assert_register => |a| {
            try writer.print("{{\"name\":\"{c}\",\"text\":\"{s}\"}}", .{ a.name, a.text });
        },
        .assert_line => |a| {
            try writer.print("{{\"line\":{d},\"text\":\"{s}\"}}", .{ a.line, a.text });
        },
        .benchmark => |a| {
            try writer.print("{{\"operation\":\"{s}\",\"iterations\":{d}}}", .{ a.operation, a.iterations });
        },
    }
}

/// Serialize Response to JSON
pub fn serializeResponse(response: protocol.Response, allocator: std.mem.Allocator) ![]const u8 {
    var string = std.ArrayList(u8).init(allocator);
    errdefer string.deinit();

    var writer = string.writer();
    try writer.writeAll("{");

    // ID
    try writer.print("\"id\":\"{s}\",", .{response.id});

    // Status
    try writer.print("\"status\":\"{s}\",", .{response.status.toString()});

    // Result (if status is ok)
    if (response.result) |result| {
        try writer.writeAll("\"result\":");
        try serializeResponseResult(result, writer);
        try writer.writeAll(",");
    }

    // Error (if status is error)
    if (response.@"error") |err| {
        try writer.print("\"error\":\"{s}\",", .{err});
    }

    // Timestamp
    try writer.print("\"timestamp\":{d},", .{response.timestamp});

    // Duration
    try writer.print("\"duration_ns\":{d}", .{response.duration_ns});

    try writer.writeAll("}");

    return string.toOwnedSlice();
}

fn serializeResponseResult(result: protocol.ResponseResult, writer: anytype) !void {
    switch (result) {
        .none => try writer.writeAll("null"),
        .cursor => |pos| {
            try writer.print("{{\"line\":{d},\"col\":{d}}}", .{ pos.line, pos.col });
        },
        .mode => |m| {
            try writer.print("{{\"mode\":\"{s}\"}}", .{m.mode});
        },
        .execute_keys => |e| {
            try writer.print("{{\"keys_processed\":{d}}}", .{e.keys_processed});
        },
        .assertion => |a| {
            try writer.print("{{\"match\":{},", .{a.match});
            if (a.expected) |exp| {
                try writer.print("\"expected\":\"{s}\",", .{exp});
            }
            if (a.actual) |act| {
                try writer.print("\"actual\":\"{s}\",", .{act});
            }
            if (a.diff) |d| {
                try writer.print("\"diff\":\"{s}\"", .{d});
            }
            try writer.writeAll("}");
        },
        .benchmark => |b| {
            try writer.print("{{\"iterations\":{d},\"total_ns\":{d},\"avg_ns\":{d},\"avg_ms\":{d:.3},\"min_ns\":{d},\"max_ns\":{d},\"within_target\":{},\"target_ms\":{d:.1}}}", .{
                b.iterations,
                b.total_ns,
                b.avg_ns,
                b.avg_ms,
                b.min_ns,
                b.max_ns,
                b.within_target,
                b.target_ms,
            });
        },
        .pong => |p| {
            try writer.print("{{\"version\":\"{s}\"}}", .{p.version});
        },
        .state => |s| {
            try state.serializeEditorState(s, writer);
        },
        .visual => |v| {
            try state.serializeVisualState(v, writer);
        },
        .buffer => |b| {
            try state.serializeBufferState(b, writer);
        },
        .register => |r| {
            try state.serializeRegisterState(r, writer);
        },
        .registers => |r| {
            try state.serializeRegistersState(r, writer);
        },
    }
}

/// Parse Command from JSON
pub fn parseCommand(json_str: []const u8, allocator: std.mem.Allocator) !protocol.Command {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Extract ID
    const id = root.object.get("id").?.string;

    // Extract command type
    const cmd_str = root.object.get("cmd").?.string;
    const cmd = protocol.CommandType.fromString(cmd_str) orelse return error.InvalidCommand;

    // Extract args based on command type
    const args_obj = root.object.get("args").?;
    const args = try parseCommandArgs(cmd, args_obj, allocator);

    // Create command
    return protocol.Command.init(allocator, id, cmd, args);
}

fn parseCommandArgs(cmd: protocol.CommandType, args_obj: std.json.Value, allocator: std.mem.Allocator) !protocol.CommandArgs {
    return switch (cmd) {
        .ping, .shutdown, .get_state, .get_cursor, .get_mode, .get_visual, .get_registers, .get_buffer => .{ .none = {} },

        .get_register => blk: {
            const name = args_obj.object.get("name").?.string[0];
            break :blk .{ .get_register = .{ .name = name } };
        },

        .execute_keys => blk: {
            const keys = args_obj.object.get("keys").?.string;
            const owned = try allocator.dupe(u8, keys);
            break :blk .{ .execute_keys = .{ .keys = owned } };
        },

        .load_file => blk: {
            const path = args_obj.object.get("path").?.string;
            const owned = try allocator.dupe(u8, path);
            break :blk .{ .load_file = .{ .path = owned } };
        },

        .assert_cursor => blk: {
            const line = @as(usize, @intCast(args_obj.object.get("line").?.integer));
            const col = @as(usize, @intCast(args_obj.object.get("col").?.integer));
            break :blk .{ .assert_cursor = .{ .line = line, .col = col } };
        },

        .assert_mode => blk: {
            const mode = args_obj.object.get("mode").?.string;
            const owned = try allocator.dupe(u8, mode);
            break :blk .{ .assert_mode = .{ .mode = owned } };
        },

        .assert_visual_active => blk: {
            const active = args_obj.object.get("active").?.bool;
            break :blk .{ .assert_visual_active = .{ .active = active } };
        },

        .assert_visual_mode => blk: {
            const mode = args_obj.object.get("mode").?.string;
            const owned = try allocator.dupe(u8, mode);
            break :blk .{ .assert_visual_mode = .{ .mode = owned } };
        },

        .assert_register => blk: {
            const name = args_obj.object.get("name").?.string[0];
            const text = args_obj.object.get("text").?.string;
            const owned = try allocator.dupe(u8, text);
            break :blk .{ .assert_register = .{ .name = name, .text = owned } };
        },

        .assert_line => blk: {
            const line = @as(usize, @intCast(args_obj.object.get("line").?.integer));
            const text = args_obj.object.get("text").?.string;
            const owned = try allocator.dupe(u8, text);
            break :blk .{ .assert_line = .{ .line = line, .text = owned } };
        },

        .benchmark => blk: {
            const operation = args_obj.object.get("operation").?.string;
            const iterations = @as(usize, @intCast(args_obj.object.get("iterations").?.integer));
            const owned = try allocator.dupe(u8, operation);
            break :blk .{ .benchmark = .{ .operation = owned, .iterations = iterations } };
        },
    };
}

/// Create success response
/// NOTE: The result fields are assumed to be already allocated/owned by caller
/// or will be allocated here for string literals
pub fn createSuccessResponse(
    allocator: std.mem.Allocator,
    id: []const u8,
    result: protocol.ResponseResult,
    duration_ns: u64,
) !protocol.Response {
    const owned_id = try allocator.dupe(u8, id);

    // Ensure pong version is owned (not a string literal)
    var owned_result = result;
    if (result == .pong) {
        owned_result.pong.version = try allocator.dupe(u8, result.pong.version);
    }

    return protocol.Response{
        .id = owned_id,
        .status = .ok,
        .result = owned_result,
        .@"error" = null,
        .timestamp = std.time.milliTimestamp(),
        .duration_ns = duration_ns,
    };
}

/// Create error response
pub fn createErrorResponse(
    allocator: std.mem.Allocator,
    id: []const u8,
    error_msg: []const u8,
    duration_ns: u64,
) !protocol.Response {
    const owned_id = try allocator.dupe(u8, id);
    const owned_err = try allocator.dupe(u8, error_msg);
    return protocol.Response{
        .id = owned_id,
        .status = .@"error",
        .result = null,
        .@"error" = owned_err,
        .timestamp = std.time.milliTimestamp(),
        .duration_ns = duration_ns,
    };
}

// Tests
test "JSON: serialize/parse simple command" {
    const allocator = std.testing.allocator;

    // Create command
    var cmd = try protocol.Command.init(
        allocator,
        "test-1",
        .ping,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    // Serialize
    const json = try serializeCommand(cmd, allocator);
    defer allocator.free(json);

    // Should contain expected fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"test-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cmd\":\"ping\"") != null);
}

test "JSON: serialize/parse execute_keys command" {
    const allocator = std.testing.allocator;

    const keys = try allocator.dupe(u8, "viw");
    var cmd = try protocol.Command.init(
        allocator,
        "test-2",
        .execute_keys,
        .{ .execute_keys = .{ .keys = keys } },
    );
    defer cmd.deinit(allocator);

    // Serialize
    const json = try serializeCommand(cmd, allocator);
    defer allocator.free(json);

    // Should contain keys
    try std.testing.expect(std.mem.indexOf(u8, json, "\"keys\":\"viw\"") != null);

    // Parse back
    var parsed = try parseCommand(json, allocator);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(protocol.CommandType.execute_keys, parsed.cmd);
    try std.testing.expectEqualStrings("viw", parsed.args.execute_keys.keys);
}

test "JSON: serialize response with assertion result" {
    const allocator = std.testing.allocator;

    const response = protocol.Response{
        .id = try allocator.dupe(u8, "test-3"),
        .status = .ok,
        .result = .{
            .assertion = .{
                .match = true,
                .expected = try allocator.dupe(u8, "VISUAL"),
                .actual = try allocator.dupe(u8, "VISUAL"),
                .diff = null,
            },
        },
        .@"error" = null,
        .timestamp = 1234567890,
        .duration_ns = 1000,
    };

    // Serialize
    const json = try serializeResponse(response, allocator);
    defer allocator.free(json);

    // Cleanup
    allocator.free(response.id);
    allocator.free(response.result.?.assertion.expected.?);
    allocator.free(response.result.?.assertion.actual.?);

    // Should contain assertion result
    try std.testing.expect(std.mem.indexOf(u8, json, "\"match\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"expected\":\"VISUAL\"") != null);
}

test "JSON: serialize error response" {
    const allocator = std.testing.allocator;

    var response = try createErrorResponse(
        allocator,
        "test-4",
        "Command failed",
        5000,
    );
    defer response.deinit(allocator);

    const json = try serializeResponse(response, allocator);
    defer allocator.free(json);

    // Should be error status
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"error\":\"Command failed\"") != null);
}
