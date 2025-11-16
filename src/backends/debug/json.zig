const std = @import("std");
const protocol = @import("protocol.zig");
const state = @import("state.zig");

/// JSON serialization for debug protocol
/// All protocol types can be serialized to/from JSON for LLM-friendly communication
/// Serialize Command to JSON
pub fn serializeCommand(command: protocol.Command, allocator: std.mem.Allocator) ![]const u8 {
    var string: std.ArrayList(u8) = .empty;
    errdefer string.deinit(allocator);

    var writer = string.writer(allocator);
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

    return string.toOwnedSlice(allocator);
}

fn serializeCommandArgs(args: protocol.CommandArgs, writer: anytype) !void {
    switch (args) {
        .none => try writer.writeAll("{}"),
        .get_register => |a| {
            try writer.print("{{\"name\":\"{c}\"}}", .{a.name});
        },
        .get_layer => |a| {
            try writer.print("{{\"name\":\"{s}\"}}", .{a.name});
        },
        .get_layer_cells => |a| {
            try writer.print("{{\"name\":\"{s}\"", .{a.name});
            if (a.region) |r| {
                try writer.print(",\"region\":{{\"row\":{d},\"col\":{d},\"height\":{d},\"width\":{d}}}", .{ r.row, r.col, r.height, r.width });
            }
            try writer.writeAll("}");
        },
        .get_output_grid => |a| {
            if (a.region) |r| {
                try writer.print("{{\"region\":{{\"row\":{d},\"col\":{d},\"height\":{d},\"width\":{d}}}}}", .{ r.row, r.col, r.height, r.width });
            } else {
                try writer.writeAll("{}");
            }
        },
        .get_logs => |a| {
            try writer.writeAll("{");
            var needs_comma = false;
            if (a.count) |count| {
                try writer.print("\"count\":{d}", .{count});
                needs_comma = true;
            }
            if (a.level) |level| {
                if (needs_comma) try writer.writeAll(",");
                try writer.print("\"level\":\"{s}\"", .{level});
                needs_comma = true;
            }
            if (a.max_bytes) |max_bytes| {
                if (needs_comma) try writer.writeAll(",");
                try writer.print("\"max_bytes\":{d}", .{max_bytes});
            }
            try writer.writeAll("}");
        },
        .execute_keys => |a| {
            try writer.print("{{\"keys\":\"{s}\"}}", .{a.keys});
        },
        .load_file => |a| {
            try writer.print("{{\"path\":\"{s}\"}}", .{a.path});
        },
        .save_file => |a| {
            if (a.path) |p| {
                try writer.print("{{\"path\":\"{s}\"}}", .{p});
            } else {
                try writer.writeAll("{}");
            }
        },
        .set_buffer => |a| {
            try writer.writeAll("{\"lines\":[");
            for (a.lines, 0..) |line, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("\"{s}\"", .{line});
            }
            try writer.writeAll("]");
            if (a.cursor) |c| {
                try writer.print(",\"cursor\":{{\"line\":{d},\"col\":{d}}}", .{ c.line, c.col });
            }
            try writer.writeAll("}");
        },
        .set_cursor => |pos| {
            try writer.print("{{\"line\":{d},\"col\":{d}}}", .{ pos.line, pos.col });
        },
        .set_mode => |a| {
            try writer.print("{{\"mode\":\"{s}\"}}", .{a.mode});
        },
        .set_option => |a| {
            try writer.print("{{\"name\":\"{s}\",\"value\":", .{a.name});
            switch (a.value) {
                .boolean => |b| try writer.print("{}", .{b}),
                .number => |n| try writer.print("{d}", .{n}),
                .string => |s| try writer.print("\"{s}\"", .{s}),
            }
            try writer.writeAll("}");
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
    }
}

/// Serialize Response to JSON
pub fn serializeResponse(response: protocol.Response, allocator: std.mem.Allocator) ![]const u8 {
    var string: std.ArrayList(u8) = .empty;
    errdefer string.deinit(allocator);

    var writer = string.writer(allocator);
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

    return string.toOwnedSlice(allocator);
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
        .layers => |l| {
            try serializeLayersState(l, writer);
        },
        .layer => |l| {
            try serializeLayerState(l, writer);
        },
        .layer_cells => |lc| {
            try serializeLayerCells(lc, writer);
        },
        .output_grid => |og| {
            try serializeOutputGrid(og, writer);
        },
        .logs => |logs| {
            try serializeLogsState(logs, writer);
        },
        .undo_stack => |us| {
            try serializeUndoStackState(us, writer);
        },
        .redo_stack => |rs| {
            try serializeRedoStackState(rs, writer);
        },
        .transaction => |t| {
            try serializeTransactionState(t, writer);
        },
        .buffer_info => |bi| {
            try serializeBufferInfo(bi, writer);
        },
        .file_saved => |fs| {
            try writer.print("{{\"bytes_written\":{d}}}", .{fs.bytes_written});
        },
    }
}

fn serializeLogsState(logs: protocol.LogsState, writer: anytype) !void {
    try writer.writeAll("{\"logs\":[");
    for (logs.logs, 0..) |log_entry, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"message\":\"{s}\",", .{log_entry.message});
        try writer.print("\"level\":\"{s}\",", .{log_entry.level});
        try writer.print("\"timestamp_ms\":{d}}}", .{log_entry.timestamp_ms});
    }
    try writer.writeAll("],");
    try writer.print("\"count\":{d},", .{logs.count});
    try writer.print("\"total_in_buffer\":{d},", .{logs.total_in_buffer});
    try writer.print("\"truncated\":{},", .{logs.truncated});
    try writer.print("\"bytes_used\":{d}}}", .{logs.bytes_used});
}

fn serializeUndoEntry(entry: protocol.UndoEntry, writer: anytype) !void {
    try writer.print("{{\"offset\":{d},", .{entry.offset});
    try writer.print("\"deleted_text\":\"{s}\",", .{entry.deleted_text});
    try writer.print("\"inserted_text\":\"{s}\",", .{entry.inserted_text});
    try writer.print("\"cursor_before\":{{\"line\":{d},\"col\":{d}}},", .{ entry.cursor_before.line, entry.cursor_before.col });
    try writer.print("\"cursor_after\":{{\"line\":{d},\"col\":{d}}}}}", .{ entry.cursor_after.line, entry.cursor_after.col });
}

fn serializeUndoStackState(undo_stack: protocol.UndoStackState, writer: anytype) !void {
    try writer.writeAll("{\"entries\":[");
    for (undo_stack.entries, 0..) |entry, i| {
        if (i > 0) try writer.writeAll(",");
        try serializeUndoEntry(entry, writer);
    }
    try writer.writeAll("],");
    try writer.print("\"count\":{d},", .{undo_stack.count});
    try writer.print("\"position\":{d}}}", .{undo_stack.position});
}

fn serializeRedoStackState(redo_stack: protocol.RedoStackState, writer: anytype) !void {
    try writer.writeAll("{\"entries\":[");
    for (redo_stack.entries, 0..) |entry, i| {
        if (i > 0) try writer.writeAll(",");
        try serializeUndoEntry(entry, writer);
    }
    try writer.writeAll("],");
    try writer.print("\"count\":{d}}}", .{redo_stack.count});
}

fn serializeTransactionState(transaction: protocol.TransactionState, writer: anytype) !void {
    try writer.print("{{\"active\":{},", .{transaction.active});
    try writer.print("\"text_buffer\":\"{s}\",", .{transaction.text_buffer});
    try writer.print("\"cursor_start\":{{\"line\":{d},\"col\":{d}}},", .{ transaction.cursor_start.line, transaction.cursor_start.col });
    try writer.print("\"cursor_end\":{{\"line\":{d},\"col\":{d}}}}}", .{ transaction.cursor_end.line, transaction.cursor_end.col });
}

fn serializeBufferInfo(buffer_info: protocol.BufferInfo, writer: anytype) !void {
    try writer.print("{{\"modified\":{},", .{buffer_info.modified});
    if (buffer_info.filepath) |fp| {
        try writer.print("\"filepath\":\"{s}\",", .{fp});
    } else {
        try writer.writeAll("\"filepath\":null,");
    }
    try writer.print("\"size\":{d},", .{buffer_info.size});
    try writer.print("\"line_count\":{d}}}", .{buffer_info.line_count});
}

fn serializeLayerState(layer: protocol.LayerState, writer: anytype) !void {
    try writer.print("{{\"id\":{d},", .{layer.id});
    try writer.print("\"name\":\"{s}\",", .{layer.name});
    try writer.print("\"z_index\":{d},", .{layer.z_index});
    try writer.print("\"enabled\":{},", .{layer.enabled});
    try writer.print("\"opacity\":{d:.2},", .{layer.opacity});
    try writer.print("\"dirty\":{},", .{layer.dirty});
    try writer.print("\"width\":{d},", .{layer.width});
    try writer.print("\"height\":{d}}}", .{layer.height});
}

fn serializeLayersState(layers: protocol.LayersState, writer: anytype) !void {
    try writer.writeAll("{\"layers\":[");
    for (layers.layers, 0..) |layer, i| {
        if (i > 0) try writer.writeAll(",");
        try serializeLayerState(layer, writer);
    }
    try writer.writeAll("],\"compositor_stats\":");
    try serializeCompositorStats(layers.compositor_stats, writer);
    try writer.writeAll("}");
}

fn serializeCompositorStats(stats: protocol.CompositorStats, writer: anytype) !void {
    try writer.print("{{\"layers_composited\":{d},", .{stats.layers_composited});
    try writer.print("\"layers_skipped\":{d},", .{stats.layers_skipped});
    try writer.print("\"layers_cached\":{d},", .{stats.layers_cached});
    try writer.print("\"cells_blended\":{d},", .{stats.cells_blended});
    try writer.print("\"cells_skipped\":{d},", .{stats.cells_skipped});
    try writer.print("\"cells_from_cache\":{d},", .{stats.cells_from_cache});
    try writer.print("\"composite_time_ns\":{d}}}", .{stats.composite_time_ns});
}

fn serializeOutputCell(cell: protocol.OutputCell, writer: anytype) !void {
    try writer.print("{{\"row\":{d},\"col\":{d},\"char\":{d}", .{ cell.row, cell.col, cell.char });
    if (cell.fg) |fg| {
        try writer.print(",\"fg\":{{\"r\":{d},\"g\":{d},\"b\":{d}}}", .{ fg.r, fg.g, fg.b });
    }
    if (cell.bg) |bg| {
        try writer.print(",\"bg\":{{\"r\":{d},\"g\":{d},\"b\":{d}}}", .{ bg.r, bg.g, bg.b });
    }
    try writer.writeAll("}");
}

fn serializeLayerCells(lc: protocol.LayerCells, writer: anytype) !void {
    try writer.print("{{\"layer_name\":\"{s}\",", .{lc.layer_name});
    try writer.print("\"layer_id\":{d},", .{lc.layer_id});
    try writer.print("\"dirty_count\":{d},", .{lc.dirty_count});
    try writer.writeAll("\"cells\":[");
    for (lc.cells, 0..) |cell, i| {
        if (i > 0) try writer.writeAll(",");
        try serializeOutputCell(cell, writer);
    }
    try writer.writeAll("]}");
}

fn serializeOutputGrid(og: protocol.OutputGrid, writer: anytype) !void {
    try writer.print("{{\"width\":{d},", .{og.width});
    try writer.print("\"height\":{d},", .{og.height});
    try writer.print("\"cell_count\":{d},", .{og.cell_count});
    try writer.writeAll("\"cells\":[");
    for (og.cells, 0..) |cell, i| {
        if (i > 0) try writer.writeAll(",");
        try serializeOutputCell(cell, writer);
    }
    try writer.writeAll("]}");
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

    // Extract args based on command type (optional - some commands don't need args)
    const args: protocol.CommandArgs = if (root.object.get("args")) |args_obj|
        try parseCommandArgs(cmd, args_obj, allocator)
    else
        protocol.CommandArgs{ .none = {} };

    // Create command
    return protocol.Command.init(allocator, id, cmd, args);
}

fn parseCommandArgs(cmd: protocol.CommandType, args_obj: std.json.Value, allocator: std.mem.Allocator) !protocol.CommandArgs {
    return switch (cmd) {
        .ping, .shutdown, .get_state, .get_cursor, .get_mode, .get_visual, .get_registers, .get_buffer, .get_layers, .get_undo_stack, .get_redo_stack, .get_transaction, .get_buffer_info => .{ .none = {} },

        .get_logs => blk: {
            const count = if (args_obj.object.get("count")) |c| @as(usize, @intCast(c.integer)) else null;
            const level = if (args_obj.object.get("level")) |l| try allocator.dupe(u8, l.string) else null;
            const max_bytes = if (args_obj.object.get("max_bytes")) |mb| @as(usize, @intCast(mb.integer)) else null;
            break :blk .{ .get_logs = .{
                .count = count,
                .level = level,
                .max_bytes = max_bytes,
            } };
        },

        .get_register => blk: {
            const name = args_obj.object.get("name").?.string[0];
            break :blk .{ .get_register = .{ .name = name } };
        },

        .get_layer => blk: {
            const name = args_obj.object.get("name").?.string;
            const owned = try allocator.dupe(u8, name);
            break :blk .{ .get_layer = .{ .name = owned } };
        },

        .get_layer_cells => blk: {
            const name = args_obj.object.get("name").?.string;
            const owned = try allocator.dupe(u8, name);
            const region = if (args_obj.object.get("region")) |r| protocol.GridRegion{
                .row = @as(usize, @intCast(r.object.get("row").?.integer)),
                .col = @as(usize, @intCast(r.object.get("col").?.integer)),
                .height = @as(usize, @intCast(r.object.get("height").?.integer)),
                .width = @as(usize, @intCast(r.object.get("width").?.integer)),
            } else null;
            break :blk .{ .get_layer_cells = .{ .name = owned, .region = region } };
        },

        .get_output_grid => blk: {
            const region = if (args_obj.object.get("region")) |r| protocol.GridRegion{
                .row = @as(usize, @intCast(r.object.get("row").?.integer)),
                .col = @as(usize, @intCast(r.object.get("col").?.integer)),
                .height = @as(usize, @intCast(r.object.get("height").?.integer)),
                .width = @as(usize, @intCast(r.object.get("width").?.integer)),
            } else null;
            break :blk .{ .get_output_grid = .{ .region = region } };
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

        .save_file => blk: {
            const path = if (args_obj.object.get("path")) |p| blk2: {
                if (p == .null) break :blk2 null;
                break :blk2 try allocator.dupe(u8, p.string);
            } else null;
            break :blk .{ .save_file = .{ .path = path } };
        },

        .set_buffer => blk: {
            const lines_array = args_obj.object.get("lines").?.array;
            const lines = try allocator.alloc([]const u8, lines_array.items.len);
            errdefer {
                for (lines[0..lines_array.items.len]) |line| allocator.free(line);
                allocator.free(lines);
            }
            for (lines_array.items, 0..) |line_val, i| {
                lines[i] = try allocator.dupe(u8, line_val.string);
            }
            const cursor = if (args_obj.object.get("cursor")) |c| protocol.Position{
                .line = @as(usize, @intCast(c.object.get("line").?.integer)),
                .col = @as(usize, @intCast(c.object.get("col").?.integer)),
            } else null;
            break :blk .{ .set_buffer = .{ .lines = lines, .cursor = cursor } };
        },

        .set_cursor => blk: {
            const line = @as(usize, @intCast(args_obj.object.get("line").?.integer));
            const col = @as(usize, @intCast(args_obj.object.get("col").?.integer));
            break :blk .{ .set_cursor = .{ .line = line, .col = col } };
        },

        .set_mode => blk: {
            const mode = args_obj.object.get("mode").?.string;
            const owned = try allocator.dupe(u8, mode);
            break :blk .{ .set_mode = .{ .mode = owned } };
        },

        .set_option => blk: {
            const name = args_obj.object.get("name").?.string;
            const owned_name = try allocator.dupe(u8, name);

            const value_json = args_obj.object.get("value").?;
            const value = switch (value_json) {
                .bool => |b| protocol.OptionValue{ .boolean = b },
                .integer => |i| protocol.OptionValue{ .number = i },
                .string => |s| protocol.OptionValue{ .string = try allocator.dupe(u8, s) },
                .object => |obj| blk2: {
                    // Special handling for listchars: convert object to string format
                    // {"tab":"→·","space":"·"} -> "tab:→·,space:·"
                    if (std.mem.eql(u8, name, "listchars") or std.mem.eql(u8, name, "lcs")) {
                        // Build comma-separated key:value pairs
                        var result: std.ArrayList(u8) = .empty;
                        errdefer result.deinit(allocator);

                        var first = true;
                        var iter = obj.iterator();
                        while (iter.next()) |entry| {
                            if (!first) {
                                try result.append(allocator, ',');
                            }
                            first = false;

                            try result.appendSlice(allocator, entry.key_ptr.*);
                            try result.append(allocator, ':');

                            if (entry.value_ptr.* == .string) {
                                try result.appendSlice(allocator, entry.value_ptr.string);
                            }
                        }

                        break :blk2 protocol.OptionValue{ .string = try result.toOwnedSlice(allocator) };
                    }
                    return error.InvalidOptionValue;
                },
                else => return error.InvalidOptionValue,
            };

            break :blk .{ .set_option = .{ .name = owned_name, .value = value } };
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
