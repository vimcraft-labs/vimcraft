const std = @import("std");
const Pty = @import("pty").Pty;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Cursor Escape Code Monitor ===\n", .{});
    std.debug.print("This test monitors ALL cursor codes during rapid movement\n\n", .{});

    // Create test file
    {
        const file = try std.fs.cwd().createFile("/tmp/cursor_test.txt", .{});
        defer file.close();
        var i: usize = 1;
        while (i <= 50) : (i += 1) {
            var line_buf: [128]u8 = undefined;
            const line = try std.fmt.bufPrint(&line_buf, "Line {d}: This is test content\n", .{i});
            try file.writeAll(line);
        }
    }

    std.debug.print("Starting vimc...\n", .{});

    // Spawn vimc in PTY
    const argv = [_][]const u8{
        "./zig-out/bin/vimc",
        "/tmp/cursor_test.txt",
    };
    var pty = try Pty.spawn(allocator, &argv);
    defer pty.kill();

    // CRITICAL: Start reading output BEFORE sending movements
    // This captures escape codes DURING rapid movement (where flickering happens)
    var output_buf: [1024 * 1024]u8 = undefined;
    var total_read: usize = 0;

    // Wait for initial render
    std.Thread.sleep(300 * std.time.ns_per_ms);
    const initial = try pty.readAll(output_buf[total_read..]);
    total_read += initial.len;

    std.debug.print("\nSending 20 rapid 'j' movements (capturing output DURING movement)...\n", .{});

    // Send movements AND capture output after EACH movement
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try pty.write("j");

        // CRITICAL: Read output immediately after each movement
        // This captures the render triggered by THIS movement
        std.Thread.sleep(50 * std.time.ns_per_ms); // Give time for render

        const chunk = try pty.readAll(output_buf[total_read..]);
        if (chunk.len > 0) {
            total_read += chunk.len;
        }
    }

    // Give time for final renders
    std.Thread.sleep(200 * std.time.ns_per_ms);
    const final_renders = try pty.readAll(output_buf[total_read..]);
    total_read += final_renders.len;

    // Send 'q' to quit and capture exit output
    try pty.write("q");
    std.Thread.sleep(200 * std.time.ns_per_ms);
    const exit_output = try pty.readAll(output_buf[total_read..]);
    total_read += exit_output.len;

    const output = output_buf[0..total_read];

    std.debug.print("\n=== RAW OUTPUT DEBUG ===\n", .{});
    std.debug.print("Output length: {} bytes\n", .{output.len});

    // Dump first 500 bytes and LAST 200 bytes
    if (output.len > 0) {
        std.debug.print("\nFirst 500 bytes (hex):\n", .{});
        const first_dump_len = @min(output.len, 500);
        var idx: usize = 0;
        while (idx < first_dump_len) : (idx += 16) {
            const end = @min(idx + 16, first_dump_len);
            std.debug.print("{x:0>8}: ", .{idx});
            for (output[idx..end]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
            std.debug.print("\n", .{});
        }

        if (output.len > 200) {
            std.debug.print("\nLast 200 bytes (hex):\n", .{});
            const last_start = output.len - 200;
            idx = last_start;
            while (idx < output.len) : (idx += 16) {
                const end = @min(idx + 16, output.len);
                std.debug.print("{x:0>8}: ", .{idx});
                for (output[idx..end]) |byte| {
                    std.debug.print("{x:0>2} ", .{byte});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    std.debug.print("\n=== Escape Code Analysis ===\n\n", .{});

    // Count cursor escape codes
    const hide_cursor = std.mem.count(u8, output, "\x1b[?25l");
    const show_cursor = std.mem.count(u8, output, "\x1b[?25h");
    const block_cursor = std.mem.count(u8, output, "\x1b[2 q");
    const bar_cursor = std.mem.count(u8, output, "\x1b[6 q");

    // Count synchronized updates
    const sync_begin = std.mem.count(u8, output, "\x1bP=1s");
    const sync_end = std.mem.count(u8, output, "\x1bP=2s");

    // Count cursor position codes (rough count)
    var position_codes: usize = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, output, idx, "\x1b[")) |pos| {
        idx = pos + 2;
        // Look for pattern like "\x1b[{row};{col}H"
        var end = idx;
        while (end < output.len and (std.ascii.isDigit(output[end]) or output[end] == ';')) {
            end += 1;
        }
        if (end < output.len and output[end] == 'H') {
            position_codes += 1;
        }
    }

    std.debug.print("Cursor Visibility Codes:\n", .{});
    std.debug.print("  Hide (\\x1b[?25l): {} times\n", .{hide_cursor});
    std.debug.print("  Show (\\x1b[?25h): {} times\n", .{show_cursor});
    std.debug.print("  Total visibility toggles: {}\n\n", .{hide_cursor + show_cursor});

    std.debug.print("Cursor Shape Codes:\n", .{});
    std.debug.print("  Block (\\x1b[2 q): {} times\n", .{block_cursor});
    std.debug.print("  Bar (\\x1b[6 q): {} times\n", .{bar_cursor});
    std.debug.print("  Total shape changes: {}\n\n", .{block_cursor + bar_cursor});

    std.debug.print("Cursor Position Codes:\n", .{});
    std.debug.print("  Position (\\x1b[N;MH): {} times\n", .{position_codes});
    std.debug.print("  Per movement: {d:.1}\n\n", .{@as(f64, @floatFromInt(position_codes)) / 20.0});

    std.debug.print("Synchronized Updates:\n", .{});
    std.debug.print("  Begin (\\x1bP=1s): {}\n", .{sync_begin});
    std.debug.print("  End (\\x1bP=2s): {}\n\n", .{sync_end});

    std.debug.print("Output Size: {} bytes\n\n", .{output.len});

    // Diagnosis
    std.debug.print("=== DIAGNOSIS ===\n\n", .{});

    var has_issues = false;

    if (hide_cursor > 2 or show_cursor > 2) {
        std.debug.print("❌ CURSOR FLICKERING DETECTED!\n", .{});
        std.debug.print("   Hide/show codes should be <=2 (one hide, one show)\n", .{});
        std.debug.print("   Got: {} hide + {} show = {} total\n", .{ hide_cursor, show_cursor, hide_cursor + show_cursor });
        std.debug.print("   This causes the cursor to blink/flicker during movement\n\n", .{});
        has_issues = true;
    } else {
        std.debug.print("✅ Cursor visibility codes OK ({}  hide + {} show)\n\n", .{ hide_cursor, show_cursor });
    }

    if (block_cursor > 2 or bar_cursor > 2) {
        std.debug.print("⚠️  Excessive cursor shape changes\n", .{});
        std.debug.print("   Shape should only change on mode transitions\n", .{});
        std.debug.print("   Got: {} block + {} bar codes\n\n", .{ block_cursor, bar_cursor });
        has_issues = true;
    }

    if (position_codes > 40) {
        std.debug.print("⚠️  Many cursor position codes: {}\n", .{position_codes});
        std.debug.print("   Average per movement: {d:.1}\n", .{@as(f64, @floatFromInt(position_codes)) / 20.0});
        std.debug.print("   This may contribute to perceived lag\n\n", .{});
        has_issues = true;
    } else {
        std.debug.print("✅ Cursor position codes reasonable: {} (~{d:.1} per movement)\n\n", .{ position_codes, @as(f64, @floatFromInt(position_codes)) / 20.0 });
    }

    if (sync_begin == 0) {
        std.debug.print("⚠️  Synchronized updates not working\n", .{});
        std.debug.print("   Terminal may not support DCS sequences\n\n", .{});
    } else if (sync_begin != sync_end) {
        std.debug.print("⚠️  Mismatched synchronized updates: {} begin / {} end\n\n", .{ sync_begin, sync_end });
    }

    if (!has_issues) {
        std.debug.print("✅ All cursor codes look good!\n", .{});
        std.debug.print("   If you're still experiencing lag/flickering:\n", .{});
        std.debug.print("   1. Try different terminal (iTerm2, Alacritty, WezTerm)\n", .{});
        std.debug.print("   2. Check terminal FPS settings\n", .{});
        std.debug.print("   3. Verify no background CPU load\n\n", .{});
    }

    std.debug.print("=== Test Complete ===\n\n", .{});

    // Kill vimc (it's in defer so it will be killed automatically)
}
