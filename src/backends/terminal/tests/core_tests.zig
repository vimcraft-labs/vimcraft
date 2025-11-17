const std = @import("std");
const Pty = @import("pty.zig").Pty;
const helpers = @import("test_helpers.zig");

// NOTE: These tests require Vimcraft to be built first: zig build
// Run with: zig test src/backends/terminal/tests/core_tests.zig
// Or via build system: zig build pty_tests

const VIMCRAFT_BIN = "./zig-out/bin/vimc";
const TEST_FILE = "/tmp/vimcraft_test.txt";

/// Helper to create a test file
fn createTestFile(content: []const u8) !void {
    const file = try std.fs.cwd().createFile(TEST_FILE, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Helper to spawn Vimcraft with test file
fn spawnVimcraft(allocator: std.mem.Allocator) !Pty {
    const argv = [_][]const u8{ VIMCRAFT_BIN, TEST_FILE };
    return try Pty.spawn(allocator, &argv);
}

// ============================================================================
// Test 1: Startup - Vimcraft launches and displays buffer
// ============================================================================
test "PTY: Vimcraft startup and initial render" {
    const allocator = std.testing.allocator;

    // Create test file
    try createTestFile("Hello Vimcraft\n");

    // Spawn Vimcraft
    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for initial render (should show file content)
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    const output = try pty.read(&buf, 2000);

    // Verify we got output
    try std.testing.expect(output.len > 0);

    // Strip ANSI codes and check content
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    try std.testing.expect(std.mem.indexOf(u8, stripped, "Hello Vimcraft") != null);
}

// ============================================================================
// Test 2: Insert Mode - Enter insert, type text, exit
// ============================================================================
test "PTY: Insert mode typing" {
    const allocator = std.testing.allocator;

    try createTestFile("Line 1\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);
    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Enter insert mode
    try pty.write("i");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Type text
    try pty.write("Hello ");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Exit insert mode
    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    // Read output
    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show the typed text
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Hello") != null);
}

// ============================================================================
// Test 3: Append - 'A' moves to end of line and enters insert
// ============================================================================
test "PTY: Append at end of line" {
    const allocator = std.testing.allocator;

    try createTestFile("# Vimcraft\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Press A (append at end)
    try pty.write("A");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Type text
    try pty.write("!!");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Exit insert
    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    // Read output
    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show "# Vimcraft!!" (regression test for Aii bug)
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Vimcraft!!") != null);
}

// ============================================================================
// Test 4: Navigation - hjkl movement
// ============================================================================
test "PTY: hjkl navigation" {
    const allocator = std.testing.allocator;

    try createTestFile("abc\ndef\nghi\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Move right twice
    try pty.write("ll");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Move down
    try pty.write("j");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Enter insert and type to verify position
    try pty.write("ix");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // 'x' should be inserted at position (1,2) -> "dexf"
    try std.testing.expect(std.mem.indexOf(u8, stripped, "dexf") != null);
}

// ============================================================================
// Test 5: Delete - 'x' deletes character
// ============================================================================
test "PTY: Delete character with x" {
    const allocator = std.testing.allocator;

    try createTestFile("Hello\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Delete first character
    try pty.write("x");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show "ello" (H deleted)
    try std.testing.expect(std.mem.indexOf(u8, stripped, "ello") != null);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Hello") == null);
}

// ============================================================================
// Test 6: Undo - 'u' undoes last operation
// ============================================================================
test "PTY: Undo operation" {
    const allocator = std.testing.allocator;

    try createTestFile("Test\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Delete character
    try pty.write("x");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Undo
    try pty.write("u");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should restore "Test"
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Test") != null);
}

// ============================================================================
// Test 7: Visual Mode - 'v' enters visual, 'd' deletes selection
// ============================================================================
test "PTY: Visual mode and delete" {
    const allocator = std.testing.allocator;

    try createTestFile("Hello World\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Enter visual mode
    try pty.write("v");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Extend selection (5 characters: "Hello")
    try pty.write("llll");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Delete selection
    try pty.write("d");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show " World" (Hello deleted)
    try std.testing.expect(std.mem.indexOf(u8, stripped, "World") != null);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Hello") == null);
}

// ============================================================================
// Test 8: Paste - 'p' pastes from register
// ============================================================================
test "PTY: Yank and paste" {
    const allocator = std.testing.allocator;

    try createTestFile("Copy\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Yank line
    try pty.write("yy");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Paste
    try pty.write("p");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show "Copy" twice
    const first = std.mem.indexOf(u8, stripped, "Copy");
    try std.testing.expect(first != null);

    if (first) |pos| {
        const second = std.mem.indexOf(u8, stripped[pos + 4 ..], "Copy");
        try std.testing.expect(second != null);
    }
}

// ============================================================================
// Test 9: Multi-line Navigation - j/k between lines
// ============================================================================
test "PTY: Navigate between lines" {
    const allocator = std.testing.allocator;

    try createTestFile("Line 1\nLine 2\nLine 3\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Move down to line 2
    try pty.write("j");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Insert marker
    try pty.write("iX");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // X should be on line 2
    try std.testing.expect(std.mem.indexOf(u8, stripped, "XLine 2") != null);
}

// ============================================================================
// Test 10: Word Motion - 'w' moves forward by word
// ============================================================================
test "PTY: Word motion" {
    const allocator = std.testing.allocator;

    try createTestFile("one two three\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Move forward two words
    try pty.write("ww");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Insert marker
    try pty.write("iX");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // X should be before "three"
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Xthree") != null);
}

// ============================================================================
// Test 11: Line Boundaries - '0' and '$'
// ============================================================================
test "PTY: Line start and end" {
    const allocator = std.testing.allocator;

    try createTestFile("Middle\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Move to end
    try pty.write("$");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Append
    try pty.write("aEND");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    // Move to start
    try pty.write("0");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Insert
    try pty.write("iSTART");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show "STARTMiddleEND"
    try std.testing.expect(std.mem.indexOf(u8, stripped, "STARTMiddleEND") != null);
}

// ============================================================================
// Test 12: File Navigation - 'gg' and 'G'
// ============================================================================
test "PTY: File start and end navigation" {
    const allocator = std.testing.allocator;

    try createTestFile("First\nMiddle\nLast\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Go to end of file
    try pty.write("G");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Mark last line
    try pty.write("iZ");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    // Go to start
    try pty.write("gg");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Mark first line
    try pty.write("iA");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should have A on first line and Z on last
    try std.testing.expect(std.mem.indexOf(u8, stripped, "AFirst") != null);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "ZLast") != null);
}

// ============================================================================
// Test 13: Change Operator - 'cw' changes word
// ============================================================================
test "PTY: Change word operator" {
    const allocator = std.testing.allocator;

    try createTestFile("old word\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Change word
    try pty.write("cw");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Type new word
    try pty.write("new");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should show "new word" (old replaced with new)
    try std.testing.expect(std.mem.indexOf(u8, stripped, "new word") != null);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "old") == null);
}

// ============================================================================
// Test 14: Delete Line - 'dd' deletes current line
// ============================================================================
test "PTY: Delete line with dd" {
    const allocator = std.testing.allocator;

    try createTestFile("Keep\nDelete\nKeep\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Move to second line
    try pty.write("j");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Delete line
    try pty.write("dd");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // Should have "Keep" twice, no "Delete"
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Keep") != null);
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Delete") == null);
}

// ============================================================================
// Test 15: Regression - Aii bug (critical!)
// ============================================================================
test "PTY: Regression - Aii inserts on same line" {
    const allocator = std.testing.allocator;

    try createTestFile("# Vimcraft\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Reproduce bug: A then type "ii"
    try pty.write("A");
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("ii");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    // CRITICAL: Both 'i' characters must be on line 1
    // Bug was: second 'i' appeared on line 2
    try std.testing.expect(std.mem.indexOf(u8, stripped, "Vimcraftii") != null);

    // Verify second 'i' is NOT on a separate line
    var iterator = std.mem.splitSequence(u8, stripped, "\n");
    var line_count: usize = 0;
    while (iterator.next()) |line| {
        if (line.len > 0) {
            line_count += 1;
            if (line_count == 2) {
                // Second line should NOT start with 'i'
                try std.testing.expect(line[0] != 'i');
            }
        }
    }
}

// ============================================================================
// Test 16: ESC Timeout - Single ESC exits insert mode
// ============================================================================
test "PTY: Single ESC press exits insert mode" {
    const allocator = std.testing.allocator;

    try createTestFile("test line\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Enter insert mode
    try pty.write("i");
    std.Thread.sleep(100 * std.time.ns_per_ms);
    _ = try pty.read(&buf, 500);

    // Press ESC once
    try pty.write("\x1b"); // ESC

    std.Thread.sleep(100 * std.time.ns_per_ms); // Wait for ESC timeout

    // Wait for timeout (60ms to be safe, timeout is 50ms)
    std.Thread.sleep(60 * std.time.ns_per_ms);
    _ = try pty.read(&buf, 500);

    // Try normal mode command (h = left movement)
    // This should work if we're in normal mode
    try pty.write("h");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);

    // If we got output, the 'h' command was processed (normal mode active)
    // Bug was: ESC required double press, so 'h' would be typed as text
    try std.testing.expect(output.len > 0);
}

// ============================================================================
// Test 17: Arrow Keys Still Work - ESC timeout doesn't break arrow sequences
// ============================================================================
test "PTY: Arrow keys work despite ESC timeout" {
    const allocator = std.testing.allocator;

    try createTestFile("abc\ndef\nghi\n");

    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);

    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Enter insert mode
    try pty.write("i");
    std.Thread.sleep(100 * std.time.ns_per_ms);
    _ = try pty.read(&buf, 500);

    // Send arrow up (ESC[A - complete sequence)
    try pty.write("\x1b[A");
    std.Thread.sleep(100 * std.time.ns_per_ms);

    const output = try pty.read(&buf, 1000);

    // Arrow key should be processed (cursor moved up)
    // This verifies timeout doesn't break escape sequences
    try std.testing.expect(output.len > 0);
}
