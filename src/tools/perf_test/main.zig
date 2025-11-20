const std = @import("std");

// Import the PTY infrastructure from the vimcraft codebase
const Pty = @import("pty").Pty;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Vimcraft Performance Measurement ===\n\n", .{});

    // Create test file (large file with syntax highlighting potential)
    {
        const file = try std.fs.cwd().createFile("/tmp/perf_test.txt", .{});
        defer file.close();
        var i: usize = 1;
        while (i <= 200) : (i += 1) {
            var line_buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(&line_buf, "const value{d} = computeExpensiveOperation({d}, \"{s}\", true);\n", .{ i, i * 2, "test" });
            try file.writeAll(line);
        }
    }

    std.debug.print("1. Starting vimc with PTY...\n", .{});

    // Spawn vimc in a real PTY
    const argv = [_][]const u8{
        "./zig-out/bin/vimc",
        "/tmp/perf_test.txt",
    };
    var pty = try Pty.spawn(allocator, &argv);
    defer pty.kill();

    // Wait for initial render
    std.Thread.sleep(500 * std.time.ns_per_ms);
    std.debug.print("2. Vimc started, waiting for initial render...\n", .{});

    // Drain initial output
    var drain_buf: [1024 * 1024]u8 = undefined;
    _ = try pty.readAll(&drain_buf);

    std.Thread.sleep(200 * std.time.ns_per_ms);

    std.debug.print("3. Sending 20 rapid 'j' movements...\n\n", .{});

    // Measure: Send 20 rapid 'j' movements
    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        // Send 'j'
        try pty.write("j");

        // Give 20ms for processing and rendering (allows one 60 FPS frame)
        std.Thread.sleep(20 * std.time.ns_per_ms);

        if ((i + 1) % 5 == 0) {
            std.debug.print("   Sent movements 1-{d}\n", .{i + 1});
        }
    }

    const keys_sent_time = std.time.milliTimestamp();
    const keys_duration = keys_sent_time - start_time;

    // Collect terminal output after all movements
    var output_buf: [1024 * 1024]u8 = undefined;
    std.Thread.sleep(200 * std.time.ns_per_ms); // Wait for final render
    const output = try pty.readAll(&output_buf);

    const end_time = std.time.milliTimestamp();
    const total_duration = end_time - start_time;
    const render_completion_time = end_time - keys_sent_time;

    std.debug.print("\n4. Analyzing terminal output...\n\n", .{});

    // Count various escape sequences
    const cursor_position_codes = std.mem.count(u8, output, "\x1b[");
    const cursor_shows = std.mem.count(u8, output, "\x1b[?25h");
    const cursor_hides = std.mem.count(u8, output, "\x1b[?25l");
    const cursor_shapes = std.mem.count(u8, output, "\x1b[2 q") + std.mem.count(u8, output, "\x1b[6 q");
    const sync_begin = std.mem.count(u8, output, "\x1bP=1s");
    const sync_end = std.mem.count(u8, output, "\x1bP=2s");

    // Send 'q' to quit
    try pty.write("q");
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // ===================================================================
    // Results
    // ===================================================================
    std.debug.print("═══════════════════════════════════════════════════════\n", .{});
    std.debug.print("PERFORMANCE RESULTS\n", .{});
    std.debug.print("═══════════════════════════════════════════════════════\n\n", .{});

    std.debug.print("Timing:\n", .{});
    std.debug.print("   Keys sent in: {}ms\n", .{keys_duration});
    std.debug.print("   Render completion wait: {}ms\n", .{render_completion_time});
    std.debug.print("   Total duration: {}ms\n", .{total_duration});
    std.debug.print("   Movements: 20\n", .{});
    std.debug.print("   Avg per movement: {d:.1}ms\n", .{
        @as(f64, @floatFromInt(total_duration)) / 20.0,
    });
    std.debug.print("   Actual processing per movement: {d:.1}ms\n\n", .{
        @as(f64, @floatFromInt(keys_duration)) / 20.0,
    });

    const avg_ms = @as(f64, @floatFromInt(total_duration)) / 20.0;
    std.debug.print("Assessment:\n", .{});
    if (avg_ms > 100) {
        std.debug.print("   CRITICAL: >100ms per movement (VERY SLOW)\n", .{});
        std.debug.print("   User will perceive significant lag\n\n", .{});
    } else if (avg_ms > 50) {
        std.debug.print("   SLUGGISH: 50-100ms per movement\n", .{});
        std.debug.print("   Noticeable delay during rapid input\n\n", .{});
    } else if (avg_ms > 20) {
        std.debug.print("   ACCEPTABLE: 20-50ms per movement\n", .{});
        std.debug.print("   Responsive for most users\n\n", .{});
    } else {
        std.debug.print("   EXCELLENT: <20ms per movement\n", .{});
        std.debug.print("   Instant response, no perceived lag\n\n", .{});
    }

    std.debug.print("Terminal Output Analysis:\n", .{});
    std.debug.print("   Total output: {} bytes\n", .{output.len});
    std.debug.print("   Escape sequences: {}\n", .{cursor_position_codes});
    std.debug.print("   Cursor show codes: {}\n", .{cursor_shows});
    std.debug.print("   Cursor hide codes: {}\n", .{cursor_hides});
    std.debug.print("   Cursor shape codes: {}\n", .{cursor_shapes});
    std.debug.print("   Sync begin/end: {} / {}\n\n", .{ sync_begin, sync_end });

    // Diagnose potential issues
    std.debug.print("Diagnostic:\n", .{});
    if (cursor_shows > 10 or cursor_hides > 10) {
        std.debug.print("   Excessive cursor visibility toggling!\n", .{});
        std.debug.print("      {} show + {} hide codes\n", .{ cursor_shows, cursor_hides });
        std.debug.print("      This causes cursor flickering\n", .{});
    } else {
        std.debug.print("   Cursor visibility codes look good\n", .{});
    }

    if (sync_begin != sync_end or sync_begin == 0) {
        std.debug.print("   Synchronized updates: {} begin / {} end\n", .{ sync_begin, sync_end });
        if (sync_begin == 0) {
            std.debug.print("      Terminal may not support synchronized updates\n", .{});
        }
    } else {
        std.debug.print("   Synchronized updates working ({} frames)\n", .{sync_begin});
    }

    const escape_per_movement = cursor_position_codes / 20;
    if (escape_per_movement > 50) {
        std.debug.print("   Many escape codes per movement: ~{}\n", .{escape_per_movement});
        std.debug.print("      This may impact performance\n", .{});
    } else {
        std.debug.print("   Reasonable escape code count (~{} per movement)\n", .{escape_per_movement});
    }

    std.debug.print("\n═══════════════════════════════════════════════════════\n\n", .{});
}
