const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const VisualState = @import("../visual/visual.zig").VisualState;
const VisualMode = @import("../visual/visual.zig").VisualMode;
const Position = @import("../visual/visual.zig").Position;
const RegisterManager = @import("../register/register.zig").RegisterManager;
const MotionType = @import("../register/register.zig").MotionType;

/// Extract text from visual selection
/// Returns array of lines (owned, caller must free)
pub fn extractVisualSelection(
    buffer: *const Buffer,
    visual: VisualState,
    cursor_pos: Position,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    const range = visual.getRange(cursor_pos);

    return switch (visual.mode) {
        .char => try extractCharWise(buffer, range.start, range.end, allocator),
        .line => try extractLineWise(buffer, range.start, range.end, allocator),
        .block => try extractBlockWise(buffer, range.start, range.end, allocator),
    };
}

/// Extract character-wise selection
/// Returns array of lines (owned, caller must free each line and the array)
fn extractCharWise(
    buffer: *const Buffer,
    start: Position,
    end: Position,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    // Single line selection
    if (start.line == end.line) {
        const line = buffer.getLine(start.line) orelse return allocator.alloc([]const u8, 0);
        defer allocator.free(line); // ✅ FIX: Free owned memory from getLine()

        // Extract substring from start.col to end.col (inclusive)
        const start_col = @min(start.col, line.len);
        const end_col = @min(end.col + 1, line.len); // +1 for inclusive

        if (start_col >= end_col) {
            return allocator.alloc([]const u8, 0);
        }

        const text = line[start_col..end_col];
        var result = try allocator.alloc([]const u8, 1);
        result[0] = try allocator.dupe(u8, text);
        return result;
    }

    // Multi-line selection
    const num_lines = end.line - start.line + 1;
    var lines = try allocator.alloc([]const u8, num_lines);
    errdefer {
        for (lines[0..num_lines]) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }

    var line_idx: usize = 0;

    // First line: from start.col to end of line
    const first_line = buffer.getLine(start.line) orelse return error.InvalidLine;
    defer allocator.free(first_line); // ✅ FIX: Free owned memory from getLine()
    const first_start = @min(start.col, first_line.len);
    const first_end = first_line.len;

    // Remove trailing newline if present
    const first_text = if (first_end > 0 and first_line[first_end - 1] == '\n')
        first_line[first_start .. first_end - 1]
    else
        first_line[first_start..first_end];

    lines[line_idx] = try allocator.dupe(u8, first_text);
    line_idx += 1;

    // Middle lines: entire lines
    var i = start.line + 1;
    while (i < end.line) : (i += 1) {
        const middle_line = buffer.getLine(i) orelse continue;
        defer allocator.free(middle_line); // ✅ FIX: Free owned memory from getLine()

        // Remove trailing newline
        const middle_text = if (middle_line.len > 0 and middle_line[middle_line.len - 1] == '\n')
            middle_line[0 .. middle_line.len - 1]
        else
            middle_line;

        lines[line_idx] = try allocator.dupe(u8, middle_text);
        line_idx += 1;
    }

    // Last line: from start to end.col
    const last_line = buffer.getLine(end.line) orelse return error.InvalidLine;
    defer allocator.free(last_line); // ✅ FIX: Free owned memory from getLine()
    const last_end = @min(end.col + 1, last_line.len); // +1 for inclusive

    // Remove trailing newline if present
    const last_text = if (last_end > 0 and last_line[last_end - 1] == '\n')
        last_line[0..@min(last_end, last_line.len - 1)]
    else
        last_line[0..last_end];

    lines[line_idx] = try allocator.dupe(u8, last_text);

    return lines;
}

/// Extract line-wise selection
/// Returns array of complete lines (owned, caller must free)
fn extractLineWise(
    buffer: *const Buffer,
    start: Position,
    end: Position,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    const num_lines = end.line - start.line + 1;
    var lines = try allocator.alloc([]const u8, num_lines);
    errdefer {
        for (lines[0..num_lines]) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }

    var line_idx: usize = 0;
    var i = start.line;
    while (i <= end.line) : (i += 1) {
        const line = buffer.getLine(i) orelse continue;
        defer allocator.free(line); // ✅ FIX: Free owned memory from getLine()

        // Remove trailing newline for storage (register adds it back during paste)
        const text = if (line.len > 0 and line[line.len - 1] == '\n')
            line[0 .. line.len - 1]
        else
            line;

        lines[line_idx] = try allocator.dupe(u8, text);
        line_idx += 1;
    }

    return lines;
}

/// Extract block-wise (rectangular) selection
/// Returns array of line segments (owned, caller must free)
fn extractBlockWise(
    buffer: *const Buffer,
    start: Position,
    end: Position,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    const num_lines = end.line - start.line + 1;
    var lines = try allocator.alloc([]const u8, num_lines);
    errdefer {
        for (lines[0..num_lines]) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }

    const start_col = @min(start.col, end.col);
    const end_col = @max(start.col, end.col);

    var line_idx: usize = 0;
    var i = start.line;
    while (i <= end.line) : (i += 1) {
        const line = buffer.getLine(i) orelse {
            // Empty line - add empty string
            lines[line_idx] = try allocator.alloc(u8, 0);
            line_idx += 1;
            continue;
        };
        defer allocator.free(line); // ✅ FIX: Free owned memory from getLine()

        // Extract rectangle segment from this line
        const actual_start = @min(start_col, line.len);
        const actual_end = @min(end_col + 1, line.len); // +1 for inclusive

        if (actual_start >= actual_end) {
            lines[line_idx] = try allocator.alloc(u8, 0);
        } else {
            const segment = line[actual_start..actual_end];
            // Remove trailing newline if present
            const text = if (segment.len > 0 and segment[segment.len - 1] == '\n')
                segment[0 .. segment.len - 1]
            else
                segment;
            lines[line_idx] = try allocator.dupe(u8, text);
        }
        line_idx += 1;
    }

    return lines;
}

/// Yank visual selection to register
pub fn yankVisualSelection(
    buffer: *const Buffer,
    visual: VisualState,
    cursor_pos: Position,
    register_mgr: *RegisterManager,
    regname: u8,
    allocator: std.mem.Allocator,
) !void {
    // Extract text from selection
    const lines = try extractVisualSelection(buffer, visual, cursor_pos, allocator);
    defer {
        for (lines) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }

    // Determine motion type from visual mode
    const motion_type: MotionType = switch (visual.mode) {
        .char => .char_wise,
        .line => .line_wise,
        .block => .block_wise,
    };

    // Yank to register
    try register_mgr.yank(regname, lines, motion_type);
}

/// Free lines array returned by extract functions
pub fn freeLines(lines: [][]const u8, allocator: std.mem.Allocator) void {
    for (lines) |line| {
        allocator.free(line);
    }
    allocator.free(lines);
}

// Tests
test "yank: extract single line character-wise" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Create temp file with test content
    const tmp_path = "/tmp/vimcraft_yank_test.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Hello World\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual select "World" (positions 6-10)
    const visual = VisualState.init(.{ .line = 0, .col = 6 }, .char);
    const cursor_pos = Position{ .line = 0, .col = 10 };

    const lines = try extractVisualSelection(&buffer, visual, cursor_pos, allocator);
    defer freeLines(lines, allocator);

    try std.testing.expectEqual(@as(usize, 1), lines.len);
    try std.testing.expectEqualStrings("World", lines[0]);
}

test "yank: extract multi-line character-wise" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_yank_multi.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Line 1\nLine 2\nLine 3\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual select from "e 1" to "e 2" (cross two lines)
    const visual = VisualState.init(.{ .line = 0, .col = 3 }, .char);
    const cursor_pos = Position{ .line = 1, .col = 3 };

    const lines = try extractVisualSelection(&buffer, visual, cursor_pos, allocator);
    defer freeLines(lines, allocator);

    try std.testing.expectEqual(@as(usize, 2), lines.len);
    try std.testing.expectEqualStrings("e 1", lines[0]);
    try std.testing.expectEqualStrings("Line", lines[1]);
}

test "yank: extract line-wise" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_yank_line.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Line 1\nLine 2\nLine 3\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual line select lines 0-1
    const visual = VisualState.init(.{ .line = 0, .col = 0 }, .line);
    const cursor_pos = Position{ .line = 1, .col = 0 };

    const lines = try extractVisualSelection(&buffer, visual, cursor_pos, allocator);
    defer freeLines(lines, allocator);

    try std.testing.expectEqual(@as(usize, 2), lines.len);
    try std.testing.expectEqualStrings("Line 1", lines[0]);
    try std.testing.expectEqualStrings("Line 2", lines[1]);
}

test "yank: extract block-wise" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    const tmp_path = "/tmp/vimcraft_yank_block.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("abcdef\nghijkl\nmnopqr\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Block select columns 2-4 across lines 0-2
    const visual = VisualState.init(.{ .line = 0, .col = 2 }, .block);
    const cursor_pos = Position{ .line = 2, .col = 4 };

    const lines = try extractVisualSelection(&buffer, visual, cursor_pos, allocator);
    defer freeLines(lines, allocator);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("cde", lines[0]);
    try std.testing.expectEqualStrings("ijk", lines[1]);
    try std.testing.expectEqualStrings("opq", lines[2]);
}

test "yank: integration with RegisterManager" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    var register_mgr = RegisterManager.init(allocator);
    defer register_mgr.deinit();

    const tmp_path = "/tmp/vimcraft_yank_reg.txt";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("Test text\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try buffer.loadFile(tmp_path);

    // Visual select "Test"
    const visual = VisualState.init(.{ .line = 0, .col = 0 }, .char);
    const cursor_pos = Position{ .line = 0, .col = 3 };

    // Yank to register "a"
    try yankVisualSelection(&buffer, visual, cursor_pos, &register_mgr, 'a', allocator);

    // Verify register contains the text
    const reg = register_mgr.get('a').?;
    try std.testing.expectEqual(@as(usize, 1), reg.lines.items.len);
    try std.testing.expectEqualStrings("Test", reg.lines.items[0]);
    try std.testing.expectEqual(MotionType.char_wise, reg.motion_type);

    // Verify unnamed register also has it
    const reg_unnamed = register_mgr.get('"').?;
    try std.testing.expectEqual(@as(usize, 1), reg_unnamed.lines.items.len);
    try std.testing.expectEqualStrings("Test", reg_unnamed.lines.items[0]);
}
