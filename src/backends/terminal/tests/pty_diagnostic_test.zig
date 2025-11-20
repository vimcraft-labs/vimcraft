const std = @import("std");
const Pty = @import("pty.zig").Pty;

// DIAGNOSTIC TEST: Verify PTY is actually capturing terminal output
// This test will show us the raw bytes being captured

test "PTY Diagnostic: Capture and print raw output" {
    const allocator = std.testing.allocator;

    // Create simple test file
    const test_content = "Hello Vimcraft\nLine 2\nLine 3\n";
    try std.fs.cwd().writeFile(.{ .sub_path = "/tmp/pty_diagnostic.txt", .data = test_content });
    defer std.fs.cwd().deleteFile("/tmp/pty_diagnostic.txt") catch {};

    // Spawn Vimcraft
    const argv = [_][]const u8{ "./zig-out/bin/vimc", "/tmp/pty_diagnostic.txt" };
    var pty = try Pty.spawn(allocator, &argv);
    defer pty.kill();

    std.debug.print("\n========================================\n", .{});
    std.debug.print("PTY DIAGNOSTIC TEST\n", .{});
    std.debug.print("========================================\n\n", .{});

    // Wait for startup
    std.debug.print("1. Waiting for startup (500ms)...\n", .{});
    std.Thread.sleep(500 * std.time.ns_per_ms);

    // Read startup output
    var buf: [16384]u8 = undefined;
    std.debug.print("2. Reading startup output...\n", .{});
    const startup_chunk = pty.read(&buf, 1000) catch |err| {
        std.debug.print("ERROR reading startup: {}\n", .{err});
        return err;
    };
    std.debug.print("   Startup output: {} bytes\n", .{startup_chunk.len});

    // Print first 200 bytes in hex for inspection
    if (startup_chunk.len > 0) {
        std.debug.print("\n   First 200 bytes (hex):\n   ", .{});
        for (startup_chunk[0..@min(200, startup_chunk.len)], 0..) |byte, i| {
            std.debug.print("{x:0>2} ", .{byte});
            if ((i + 1) % 16 == 0) std.debug.print("\n   ", .{});
        }
        std.debug.print("\n", .{});

        // Also print as ASCII (with escape sequences visible)
        std.debug.print("\n   As ASCII (first 200 bytes):\n   ", .{});
        for (startup_chunk[0..@min(200, startup_chunk.len)]) |byte| {
            if (byte >= 32 and byte <= 126) {
                std.debug.print("{c}", .{byte});
            } else if (byte == '\n') {
                std.debug.print("\\n", .{});
            } else if (byte == '\r') {
                std.debug.print("\\r", .{});
            } else if (byte == 0x1b) {
                std.debug.print("ESC", .{});
            } else {
                std.debug.print(".", .{});
            }
        }
        std.debug.print("\n", .{});
    }

    // Send a single movement
    std.debug.print("\n3. Sending single 'j' movement...\n", .{});
    try pty.write("j");
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Capture movement output
    std.debug.print("4. Reading movement output...\n", .{});
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    var read_count: usize = 0;
    while (true) {
        const chunk = pty.read(&buf, 100) catch |err| {
            if (err == error.Timeout) {
                std.debug.print("   Read timeout after {} chunks\n", .{read_count});
                break;
            }
            std.debug.print("   ERROR during read: {}\n", .{err});
            return err;
        };
        if (chunk.len == 0) {
            std.debug.print("   Zero-length read, stopping\n", .{});
            break;
        }
        read_count += 1;
        std.debug.print("   Chunk {}: {} bytes\n", .{ read_count, chunk.len });
        try output.appendSlice(allocator, chunk);
    }

    std.debug.print("\n5. Total movement output: {} bytes\n", .{output.items.len});

    if (output.items.len > 0) {
        std.debug.print("\n   Movement output (hex):\n   ", .{});
        for (output.items, 0..) |byte, i| {
            std.debug.print("{x:0>2} ", .{byte});
            if ((i + 1) % 16 == 0) std.debug.print("\n   ", .{});
        }
        std.debug.print("\n", .{});

        std.debug.print("\n   Movement output (ASCII):\n   ", .{});
        for (output.items) |byte| {
            if (byte >= 32 and byte <= 126) {
                std.debug.print("{c}", .{byte});
            } else if (byte == '\n') {
                std.debug.print("\\n", .{});
            } else if (byte == '\r') {
                std.debug.print("\\r", .{});
            } else if (byte == 0x1b) {
                std.debug.print("[ESC]", .{});
            } else {
                std.debug.print(".", .{});
            }
        }
        std.debug.print("\n", .{});
    }

    // Search for specific escape codes
    std.debug.print("\n6. Searching for escape codes in output...\n", .{});

    // Look for cursor hide/show
    const hide_cursor = "\x1b[?25l";
    const show_cursor = "\x1b[?25h";
    const hide_count = std.mem.count(u8, output.items, hide_cursor);
    const show_count = std.mem.count(u8, output.items, show_cursor);
    std.debug.print("   Hide cursor (ESC[?25l): {} occurrences\n", .{hide_count});
    std.debug.print("   Show cursor (ESC[?25h): {} occurrences\n", .{show_count});

    // Look for cursor position codes (ESC[{row};{col}H)
    var cursor_moves: usize = 0;
    var i: usize = 0;
    while (i < output.items.len) : (i += 1) {
        if (output.items[i] == 0x1b and i + 1 < output.items.len and output.items[i + 1] == '[') {
            var j = i + 2;
            while (j < output.items.len and j < i + 20) : (j += 1) {
                if (output.items[j] == 'H' or output.items[j] == 'f') {
                    cursor_moves += 1;
                    break;
                }
            }
        }
    }
    std.debug.print("   Cursor position codes (ESC[...H/f): {} occurrences\n", .{cursor_moves});

    // Look for SGR codes (ESC[...m)
    var sgr_count: usize = 0;
    i = 0;
    while (i < output.items.len) : (i += 1) {
        if (output.items[i] == 0x1b and i + 1 < output.items.len and output.items[i + 1] == '[') {
            var j = i + 2;
            while (j < output.items.len and j < i + 30) : (j += 1) {
                if (output.items[j] == 'm') {
                    sgr_count += 1;
                    break;
                }
                if ((output.items[j] >= 'A' and output.items[j] <= 'Z') or
                    (output.items[j] >= 'a' and output.items[j] <= 'z')) {
                    break;
                }
            }
        }
    }
    std.debug.print("   SGR codes (ESC[...m): {} occurrences\n", .{sgr_count});

    std.debug.print("\n========================================\n", .{});
    std.debug.print("DIAGNOSTIC COMPLETE\n", .{});
    std.debug.print("========================================\n\n", .{});

    // If we got zero bytes, that's a clear indicator the test is broken
    if (output.items.len == 0) {
        std.debug.print("❌ FAILURE: Zero bytes captured - PTY not working!\n", .{});
        return error.NoPtyOutput;
    }

    // If output is suspiciously small (< 50 bytes for a movement), that's also concerning
    if (output.items.len < 50) {
        std.debug.print("⚠ WARNING: Very small output ({} bytes) - may indicate PTY issue\n", .{output.items.len});
    }

    std.debug.print("✓ PTY captured {} bytes - seems to be working\n", .{output.items.len});
}
