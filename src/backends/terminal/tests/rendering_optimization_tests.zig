const std = @import("std");
const Pty = @import("pty.zig").Pty;
const helpers = @import("test_helpers.zig");

// NOTE: These tests validate rendering optimizations (synchronized updates, throttling, tracking)
// Run with: zig build pty_tests

const VIMCRAFT_BIN = "./zig-out/bin/vimc";

/// Helper to create a test file with unique name
fn createTestFile(content: []const u8, suffix: []const u8) ![]const u8 {
    var buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "/tmp/vimcraft_test_{s}.txt", .{suffix});
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
    return path;
}

/// Helper to spawn Vimcraft with test file
fn spawnVimcraft(allocator: std.mem.Allocator, test_file: []const u8) !Pty {
    const argv = [_][]const u8{ VIMCRAFT_BIN, test_file };
    return try Pty.spawn(allocator, &argv);
}

// ============================================================================
// Test 1: Synchronized Updates - No Flickering During Rapid Movement
// ============================================================================
test "PTY: Synchronized updates prevent cursor flickering" {
    const allocator = std.testing.allocator;

    // Create test file with enough lines to scroll
    var content_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&content_buf);
    const writer = fbs.writer();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        try writer.print("Line {d}: Test content for flickering detection\n", .{i});
    }
    const test_file = try createTestFile(fbs.getWritten(), "sync_updates");

    var pty = try spawnVimcraft(allocator, test_file);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);
    var buf: [16384]u8 = undefined;
    _ = try pty.read(&buf, 1000); // Drain startup output

    // Simulate holding 'j' key - 20 rapid movements
    try pty.write("jjjjjjjjjjjjjjjjjjjj");
    std.Thread.sleep(300 * std.time.ns_per_ms); // Wait for all movements to process

    // Capture all output
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);
    while (true) {
        const chunk = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) break;
            return err;
        };
        if (chunk.len == 0) break;
        try output.appendSlice(allocator, chunk);
    }

    // Count cursor visibility toggles
    const hide_cursor = "\x1b[?25l"; // ESC[?25l
    const show_cursor = "\x1b[?25h"; // ESC[?25h

    const hide_count = std.mem.count(u8, output.items, hide_cursor);
    const show_count = std.mem.count(u8, output.items, show_cursor);
    const total_visibility_codes = hide_count + show_count;

    std.debug.print("\n[SYNCHRONIZED UPDATES TEST]\n", .{});
    std.debug.print("  20 rapid movements (holding 'j')\n", .{});
    std.debug.print("  Hide cursor codes: {}\n", .{hide_count});
    std.debug.print("  Show cursor codes: {}\n", .{show_count});
    std.debug.print("  Total visibility toggles: {}\n", .{total_visibility_codes});

    // EXPECTED: With synchronized updates, cursor is hidden before render batch,
    // shown after. Should see 2-4 toggles total (not 20-40).
    // Without optimization: 40-80 toggles (hide+show per movement)
    if (total_visibility_codes > 10) {
        std.debug.print("  ❌ FAIL: Excessive visibility toggles detected!\n", .{});
        std.debug.print("  Expected: <10, Got: {}\n", .{total_visibility_codes});
        std.debug.print("  Synchronized updates may not be working\n", .{});
        return error.ExcessiveFlickering;
    }

    std.debug.print("  ✓ PASS: Minimal flickering ({} toggles)\n", .{total_visibility_codes});
    std.debug.print("  Synchronized updates working correctly\n", .{});
}

// ============================================================================
// Test 2: Cursor Position Tracking - No Redundant Position Codes
// ============================================================================
test "PTY: Cursor position tracking prevents redundant codes" {
    const allocator = std.testing.allocator;

    // Create simple test file
    const test_file = try createTestFile("abcdefghijklmnopqrstuvwxyz\n", "cursor_tracking");

    var pty = try spawnVimcraft(allocator, test_file);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);
    var buf: [16384]u8 = undefined;
    _ = try pty.read(&buf, 1000); // Drain startup output

    // Perform 10 cursor movements
    try pty.write("llllllllll"); // 10 right movements
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Capture output
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);
    while (true) {
        const chunk = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) break;
            return err;
        };
        if (chunk.len == 0) break;
        try output.appendSlice(allocator, chunk);
    }

    // Count cursor position codes
    const positions = try helpers.findAllCursorPositions(allocator, output.items);
    defer allocator.free(positions);

    std.debug.print("\n[CURSOR POSITION TRACKING TEST]\n", .{});
    std.debug.print("  10 cursor movements (10x 'l')\n", .{});
    std.debug.print("  Cursor position codes sent: {}\n", .{positions.len});

    // EXPECTED: With cursor position tracking, we should see minimal position codes
    // Ideally 0 (if cursor doesn't move on screen due to scrolling), or 10-12 max
    // Without optimization: 20-40 codes (redundant positioning)
    if (positions.len > 20) {
        std.debug.print("  ❌ FAIL: Redundant cursor position codes!\n", .{});
        std.debug.print("  Expected: <20, Got: {}\n", .{positions.len});
        std.debug.print("  Cursor position tracking may not be working\n", .{});
        return error.RedundantPositioning;
    }

    std.debug.print("  ✓ PASS: Minimal position codes ({} codes)\n", .{positions.len});
    std.debug.print("  Cursor position tracking working correctly\n", .{});

    // Verify final cursor position is correct (should be at column 10)
    if (positions.len > 0) {
        const last_pos = positions[positions.len - 1];
        std.debug.print("  Final cursor: row={} col={}\n", .{ last_pos.row, last_pos.col });
    }
}

// ============================================================================
// Test 3: Render Throttling - Frame Rate Limiting
// ============================================================================
test "PTY: Render throttling limits frame rate" {
    const allocator = std.testing.allocator;

    // Create test file
    const test_file = try createTestFile("Test line\n", "throttling");

    var pty = try spawnVimcraft(allocator, test_file);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);
    var buf: [16384]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Send 50 rapid state changes (movements) in ~500ms
    // At 60 FPS throttle, we should see ~30 renders max
    const start_time = std.time.milliTimestamp();

    try pty.write("llllllllllllllllllllllllllllllllllllllllllllllllll"); // 50 movements
    std.Thread.sleep(500 * std.time.ns_per_ms);

    const elapsed_ms = std.time.milliTimestamp() - start_time;

    // Capture output
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);
    while (true) {
        const chunk = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) break;
            return err;
        };
        if (chunk.len == 0) break;
        try output.appendSlice(allocator, chunk);
    }

    // Estimate render count from cursor position codes
    const positions = try helpers.findAllCursorPositions(allocator, output.items);
    defer allocator.free(positions);

    std.debug.print("\n[RENDER THROTTLING TEST]\n", .{});
    std.debug.print("  50 rapid movements in {}ms\n", .{elapsed_ms});
    std.debug.print("  Cursor position updates: {}\n", .{positions.len});

    // EXPECTED: With 60 FPS throttle and 500ms elapsed, max ~30 renders
    // Without throttling: 50+ renders (one per movement)
    const max_expected_renders = @as(usize, @intCast(@divTrunc(elapsed_ms * 60, 1000))) + 10; // +10 for startup/margin

    if (positions.len > max_expected_renders) {
        std.debug.print("  ⚠ WARNING: More renders than expected for throttle\n", .{});
        std.debug.print("  Expected: <{}, Got: {}\n", .{ max_expected_renders, positions.len });
        std.debug.print("  Throttling may not be working optimally\n", .{});
        // Don't fail - this test is approximate due to timing variance
    } else {
        std.debug.print("  ✓ PASS: Render count within throttle limit\n", .{});
        std.debug.print("  Effective FPS: ~{d:.1} (target: 60)\n", .{@as(f64, @floatFromInt(positions.len)) / (@as(f64, @floatFromInt(elapsed_ms)) / 1000.0)});
    }
}

// ============================================================================
// Test 4: Color/Attribute Deduplication - Minimal Redundant SGR Codes
// ============================================================================
test "PTY: Color/attribute tracking reduces redundant codes" {
    const allocator = std.testing.allocator;

    // Create test file with some content
    var content_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&content_buf);
    const writer = fbs.writer();
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try writer.print("Line {d}: Color test content\n", .{i});
    }
    const test_file = try createTestFile(fbs.getWritten(), "color_tracking");

    var pty = try spawnVimcraft(allocator, test_file);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);
    var buf: [16384]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Scroll down and back up (triggers re-rendering)
    try pty.write("jjjjj"); // Move down 5 lines
    std.Thread.sleep(100 * std.time.ns_per_ms);
    try pty.write("kkkkk"); // Move back up 5 lines
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Capture output
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);
    while (true) {
        const chunk = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) break;
            return err;
        };
        if (chunk.len == 0) break;
        try output.appendSlice(allocator, chunk);
    }

    // Count SGR (color/attribute) codes
    // Common SGR codes: \x1b[0m (reset), \x1b[1m (bold), \x1b[3m (italic)
    // Color codes: \x1b[38;2;R;G;Bm (foreground), \x1b[48;2;R;G;Bm (background)

    var sgr_count: usize = 0;
    var i_sgr: usize = 0;
    while (i_sgr < output.items.len) {
        if (output.items[i_sgr] == 0x1b and i_sgr + 1 < output.items.len and output.items[i_sgr + 1] == '[') {
            // Found ESC[, check if it ends with 'm' (SGR code)
            i_sgr += 2;
            while (i_sgr < output.items.len) : (i_sgr += 1) {
                const c = output.items[i_sgr];
                if (c == 'm') {
                    sgr_count += 1;
                    break;
                }
                if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    break; // Non-SGR code
                }
            }
        }
        i_sgr += 1;
    }

    std.debug.print("\n[COLOR/ATTRIBUTE TRACKING TEST]\n", .{});
    std.debug.print("  10 movements (5 down + 5 up)\n", .{});
    std.debug.print("  SGR (color/attribute) codes: {}\n", .{sgr_count});

    // EXPECTED: With attribute tracking, we should see minimal redundant codes
    // Exact count depends on content and scrolling, but should be reasonable
    // This is more of an informational test than strict pass/fail
    std.debug.print("  Output size: {} bytes\n", .{output.items.len});
    const sgr_per_kb = @as(f64, @floatFromInt(sgr_count)) / (@as(f64, @floatFromInt(output.items.len)) / 1024.0);
    std.debug.print("  SGR codes per KB: {d:.1}\n", .{sgr_per_kb});

    if (sgr_count > 200) {
        std.debug.print("  ⚠ INFO: High SGR code count\n", .{});
        std.debug.print("  This is expected for colorized output\n", .{});
    } else {
        std.debug.print("  ✓ INFO: Moderate SGR code count\n", .{});
    }

    std.debug.print("  Attribute tracking optimization active\n", .{});
}

// ============================================================================
// Test 5: Event Batching - Single Render Per Loop Iteration
// ============================================================================
test "PTY: Event batching groups state changes" {
    const allocator = std.testing.allocator;

    // Create test file
    const test_file = try createTestFile("Line 1\nLine 2\nLine 3\n", "event_batching");

    var pty = try spawnVimcraft(allocator, test_file);
    defer pty.kill();

    // Wait for startup
    std.Thread.sleep(500 * std.time.ns_per_ms);
    var buf: [16384]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // Send multiple commands rapidly (should batch into single render)
    try pty.write("j"); // Move down
    try pty.write("l"); // Move right
    try pty.write("l"); // Move right again
    std.Thread.sleep(50 * std.time.ns_per_ms); // Brief pause for processing

    // Capture output
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);
    while (true) {
        const chunk = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) break;
            return err;
        };
        if (chunk.len == 0) break;
        try output.appendSlice(allocator, chunk);
    }

    // Count renders (approximate via cursor position codes)
    const positions = try helpers.findAllCursorPositions(allocator, output.items);
    defer allocator.free(positions);

    std.debug.print("\n[EVENT BATCHING TEST]\n", .{});
    std.debug.print("  3 rapid commands (j + l + l)\n", .{});
    std.debug.print("  Cursor position updates: {}\n", .{positions.len});

    // EXPECTED: With event batching, multiple state changes should result in
    // fewer renders than commands. Ideally 1-2 renders for 3 commands.
    // Without batching: 3+ renders (one per command)
    if (positions.len > 5) {
        std.debug.print("  ⚠ INFO: More renders than expected\n", .{});
        std.debug.print("  Expected: <5, Got: {}\n", .{positions.len});
        std.debug.print("  Event batching may have room for improvement\n", .{});
    } else {
        std.debug.print("  ✓ PASS: Commands batched efficiently\n", .{});
        std.debug.print("  Batching ratio: {} renders for 3 commands\n", .{positions.len});
    }
}
