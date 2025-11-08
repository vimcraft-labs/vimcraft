const std = @import("std");
const protocol = @import("protocol.zig");

/// Serialize EditorState to JSON
pub fn serializeEditorState(state: protocol.EditorState, writer: anytype) !void {
    try writer.writeAll("{");

    // Mode
    try writer.print("\"mode\":\"{s}\",", .{state.mode});

    // Cursor
    try writer.writeAll("\"cursor\":");
    try serializeCursor(state.cursor, writer);
    try writer.writeAll(",");

    // Buffer
    try writer.writeAll("\"buffer\":");
    try serializeBufferState(state.buffer, writer);
    try writer.writeAll(",");

    // Visual (optional)
    try writer.writeAll("\"visual\":");
    if (state.visual) |vis| {
        try serializeVisualState(vis, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",");

    // Registers
    try writer.writeAll("\"registers\":");
    try serializeRegistersState(state.registers, writer);

    try writer.writeAll("}");
}

/// Serialize cursor position
pub fn serializeCursor(pos: protocol.Position, writer: anytype) !void {
    try writer.print("{{\"line\":{d},\"col\":{d}}}", .{ pos.line, pos.col });
}

/// Serialize visual selection state
pub fn serializeVisualState(visual: protocol.VisualState, writer: anytype) !void {
    try writer.writeAll("{");

    // Active
    try writer.print("\"active\":{},", .{visual.active});

    // Mode
    try writer.print("\"mode\":\"{s}\",", .{visual.mode});

    // Anchor
    try writer.writeAll("\"anchor\":");
    try serializeCursor(visual.anchor, writer);
    try writer.writeAll(",");

    // Head
    try writer.writeAll("\"head\":");
    try serializeCursor(visual.head, writer);
    try writer.writeAll(",");

    // Text (selected lines)
    try writer.writeAll("\"text\":[");
    for (visual.text, 0..) |line, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{line});
    }
    try writer.writeAll("]");

    try writer.writeAll("}");
}

/// Serialize buffer state
pub fn serializeBufferState(buffer: protocol.BufferState, writer: anytype) !void {
    try writer.writeAll("{");

    // Path (optional)
    try writer.writeAll("\"path\":");
    if (buffer.path) |path| {
        try writer.print("\"{s}\"", .{path});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",");

    // Lines
    try writer.writeAll("\"lines\":[");
    for (buffer.lines, 0..) |line, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{line});
    }
    try writer.writeAll("],");

    // Modified
    try writer.print("\"modified\":{},", .{buffer.modified});

    // Line count
    try writer.print("\"line_count\":{d}", .{buffer.line_count});

    try writer.writeAll("}");
}

/// Serialize single register state
pub fn serializeRegisterState(reg: protocol.RegisterState, writer: anytype) !void {
    try writer.writeAll("{");

    // Name (escape double quote character)
    try writer.writeAll("\"name\":\"");
    if (reg.name == '"') {
        try writer.writeAll("\\\"");
    } else {
        try writer.print("{c}", .{reg.name});
    }
    try writer.writeAll("\",");

    // Lines
    try writer.writeAll("\"lines\":[");
    for (reg.lines, 0..) |line, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{line});
    }
    try writer.writeAll("],");

    // Type
    try writer.print("\"type\":\"{s}\",", .{reg.type});

    // Width (for block-wise)
    try writer.print("\"width\":{d},", .{reg.width});

    // Timestamp
    try writer.print("\"timestamp\":{d}", .{reg.timestamp});

    try writer.writeAll("}");
}

/// Serialize all registers state
pub fn serializeRegistersState(registers: protocol.RegistersState, writer: anytype) !void {
    try writer.writeAll("{");
    try writer.print("\"count\":{d},", .{registers.count});
    try writer.writeAll("\"registers\":[");

    for (registers.registers, 0..) |reg, i| {
        if (i > 0) try writer.writeAll(",");
        try serializeRegisterState(reg, writer);
    }

    try writer.writeAll("]}");
}

/// Create EditorState from current runtime state
/// This will be called by the debug server to capture a snapshot
pub fn captureEditorState(
    _: std.mem.Allocator,
    mode: []const u8,
    cursor: protocol.Position,
    buffer_lines: []const []const u8,
    buffer_path: ?[]const u8,
    buffer_modified: bool,
    visual_active: bool,
    visual_mode: ?[]const u8,
    visual_anchor: ?protocol.Position,
    visual_head: ?protocol.Position,
    visual_text: ?[]const []const u8,
) !protocol.EditorState {
    // Create buffer state
    const buffer = protocol.BufferState{
        .path = buffer_path,
        .lines = buffer_lines,
        .modified = buffer_modified,
        .line_count = buffer_lines.len,
    };

    // Create visual state (if active)
    var visual: ?protocol.VisualState = null;
    if (visual_active and visual_mode != null and visual_anchor != null and visual_head != null and visual_text != null) {
        visual = protocol.VisualState{
            .active = true,
            .mode = visual_mode.?,
            .anchor = visual_anchor.?,
            .head = visual_head.?,
            .text = visual_text.?,
        };
    }

    // Create registers state (empty for now - will be filled by caller)
    const registers = protocol.RegistersState{
        .registers = &[_]protocol.RegisterState{},
        .count = 0,
    };

    return protocol.EditorState{
        .mode = mode,
        .cursor = cursor,
        .buffer = buffer,
        .visual = visual,
        .registers = registers,
    };
}

// Tests
test "State: serialize cursor position" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const pos = protocol.Position{ .line = 5, .col = 10 };
    try serializeCursor(pos, buffer.writer());

    const json = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"line\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"col\":10") != null);
}

test "State: serialize buffer state" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const lines = [_][]const u8{ "Line 1", "Line 2", "Line 3" };
    const buf_state = protocol.BufferState{
        .path = "/tmp/test.txt",
        .lines = &lines,
        .modified = false,
        .line_count = 3,
    };

    try serializeBufferState(buf_state, buffer.writer());

    const json = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path\":\"/tmp/test.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"Line 1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"modified\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"line_count\":3") != null);
}

test "State: serialize visual state" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const text = [_][]const u8{"Hello"};
    const vis_state = protocol.VisualState{
        .active = true,
        .mode = "char",
        .anchor = .{ .line = 0, .col = 0 },
        .head = .{ .line = 0, .col = 5 },
        .text = &text,
    };

    try serializeVisualState(vis_state, buffer.writer());

    const json = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"active\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mode\":\"char\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"Hello\"") != null);
}

test "State: serialize register state" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const lines = [_][]const u8{"yanked text"};
    const reg_state = protocol.RegisterState{
        .name = 'a',
        .lines = &lines,
        .type = "char",
        .width = 0,
        .timestamp = 1234567890,
    };

    try serializeRegisterState(reg_state, buffer.writer());

    const json = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"yanked text\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"char\"") != null);
}

test "State: serialize editor state" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const lines = [_][]const u8{ "Line 1", "Line 2" };
    const buf_state = protocol.BufferState{
        .path = "/tmp/test.txt",
        .lines = &lines,
        .modified = false,
        .line_count = 2,
    };

    const registers = protocol.RegistersState{
        .registers = &[_]protocol.RegisterState{},
        .count = 0,
    };

    const editor_state = protocol.EditorState{
        .mode = "NORMAL",
        .cursor = .{ .line = 0, .col = 0 },
        .buffer = buf_state,
        .visual = null,
        .registers = registers,
    };

    try serializeEditorState(editor_state, buffer.writer());

    const json = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mode\":\"NORMAL\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor\":{\"line\":0,\"col\":0}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"buffer\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"visual\":null") != null);
}

test "State: capture editor state" {
    const allocator = std.testing.allocator;

    const lines = [_][]const u8{ "Line 1", "Line 2" };
    const state = try captureEditorState(
        allocator,
        "NORMAL",
        .{ .line = 0, .col = 0 },
        &lines,
        "/tmp/test.txt",
        false,
        false,
        null,
        null,
        null,
        null,
    );

    try std.testing.expectEqualStrings("NORMAL", state.mode);
    try std.testing.expectEqual(@as(usize, 0), state.cursor.line);
    try std.testing.expectEqual(@as(usize, 2), state.buffer.line_count);
    try std.testing.expect(state.visual == null);
    try std.testing.expectEqual(@as(usize, 0), state.registers.count);
}
