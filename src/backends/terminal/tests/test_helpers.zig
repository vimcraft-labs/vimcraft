const std = @import("std");

/// Strip ANSI escape sequences from output
/// Returns a new allocated string with ANSI codes removed
/// Handles both CSI (ESC[) and OSC (ESC]) sequences
pub fn stripAnsi(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, input.len);
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len) {
            if (input[i + 1] == '[') {
                // Found ESC[ (CSI), skip until we find a letter (SGR terminator)
                i += 2;
                while (i < input.len) : (i += 1) {
                    const c = input[i];
                    if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        i += 1;
                        break;
                    }
                }
            } else if (input[i + 1] == ']') {
                // Found ESC] (OSC), skip until we find BEL (0x07) or ESC\
                i += 2;
                while (i < input.len) : (i += 1) {
                    if (input[i] == 0x07) { // BEL
                        i += 1;
                        break;
                    } else if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '\\') { // ESC\
                        i += 2;
                        break;
                    }
                }
            } else {
                // Other ESC sequence, just skip ESC
                try result.append(allocator, input[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Parse cursor position from ANSI output
/// Looks for CSI sequences like ESC[row;colH or ESC[row;colf
pub fn parseAnsiCursor(input: []const u8) ?struct { row: usize, col: usize } {
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '[') {
            // Found ESC[, try to parse row;colH
            i += 2;
            const start = i;

            // Parse row
            var row: usize = 0;
            while (i < input.len and input[i] >= '0' and input[i] <= '9') : (i += 1) {
                row = row * 10 + (input[i] - '0');
            }

            if (i >= input.len or input[i] != ';') {
                i = start;
                continue;
            }
            i += 1; // Skip ';'

            // Parse col
            var col: usize = 0;
            while (i < input.len and input[i] >= '0' and input[i] <= '9') : (i += 1) {
                col = col * 10 + (input[i] - '0');
            }

            if (i < input.len and (input[i] == 'H' or input[i] == 'f')) {
                return .{ .row = row, .col = col };
            }
        }
        i += 1;
    }

    return null;
}

/// Wait for a pattern to appear in PTY output
/// Polls the PTY and accumulates output until pattern found or timeout
pub fn waitForPattern(
    pty: anytype, // *Pty
    allocator: std.mem.Allocator,
    pattern: []const u8,
    timeout_ms: i32,
) !bool {
    var output = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer output.deinit(allocator);

    const start_time = std.time.milliTimestamp();
    var buf: [4096]u8 = undefined;

    while (std.time.milliTimestamp() - start_time < timeout_ms) {
        const data = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) continue;
            return err;
        };

        if (data.len > 0) {
            try output.appendSlice(allocator, data);

            // Check if pattern found
            if (std.mem.indexOf(u8, output.items, pattern) != null) {
                return true;
            }
        }
    }

    return false;
}

// Tests for helper functions
test "stripAnsi: removes escape codes" {
    const allocator = std.testing.allocator;

    const input = "\x1b[31mHello\x1b[0m World";
    const result = try stripAnsi(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World", result);
}

test "stripAnsi: handles multiple codes" {
    const allocator = std.testing.allocator;

    const input = "\x1b[1m\x1b[32mBold Green\x1b[0m\x1b[0m";
    const result = try stripAnsi(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Bold Green", result);
}

test "stripAnsi: preserves text without codes" {
    const allocator = std.testing.allocator;

    const input = "Plain text";
    const result = try stripAnsi(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Plain text", result);
}

test "parseAnsiCursor: parses cursor position" {
    const input = "\x1b[5;10H";
    const pos = parseAnsiCursor(input);

    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(usize, 5), pos.?.row);
    try std.testing.expectEqual(@as(usize, 10), pos.?.col);
}

test "parseAnsiCursor: handles f terminator" {
    const input = "\x1b[12;34f";
    const pos = parseAnsiCursor(input);

    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(usize, 12), pos.?.row);
    try std.testing.expectEqual(@as(usize, 34), pos.?.col);
}

test "parseAnsiCursor: returns null for invalid input" {
    const input = "No cursor here";
    const pos = parseAnsiCursor(input);

    try std.testing.expect(pos == null);
}

test "parseAnsiCursor: finds cursor in mixed output" {
    const input = "Some text\x1b[2;3H more text";
    const pos = parseAnsiCursor(input);

    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(usize, 2), pos.?.row);
    try std.testing.expectEqual(@as(usize, 3), pos.?.col);
}
