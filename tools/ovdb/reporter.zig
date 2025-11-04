const std = @import("std");
const script = @import("script.zig");

/// Report test results in LLM-optimized compact format
pub fn report(results: script.ScriptResults, writer: anytype) !void {
    // Summary header
    try writer.print("TEST_SCRIPT: {s}\n", .{results.script_path});
    try writer.print("SUMMARY: {d} tests, {d} passed, {d} failed, {d} errors, {d:.1}ms\n\n", .{
        results.total,
        results.passed,
        results.failed,
        results.errors,
        results.total_duration_ms,
    });

    // Individual test results
    for (results.results.items, 0..) |result, i| {
        const status_str = switch (result.status) {
            .pass => "PASS",
            .fail => "FAIL",
            .@"error" => "ERROR",
        };

        try writer.print("[{s}] {s} ({d:.1}ms)\n", .{ status_str, result.command, result.duration_ms });

        // Show details for failures and errors
        if (result.status == .fail) {
            if (result.expected) |exp| {
                try writer.print("       Expected: {s}\n", .{exp});
            }
            if (result.actual) |act| {
                try writer.print("       Actual: {s}\n", .{act});
            }
        } else if (result.status == .@"error") {
            if (result.error_message) |err| {
                try writer.print("       Error: {s}\n", .{err});
            }
        }

        // Add spacing between tests except after last one
        if (i < results.results.items.len - 1) {
            try writer.print("\n", .{});
        }
    }

    // Final status
    try writer.print("\n", .{});
    const final_status = if (results.failed == 0 and results.errors == 0) "ALL_PASSED" else "FAILED";
    try writer.print("FINAL: {s}\n", .{final_status});
}

// Tests
test "Reporter: compact format" {
    const allocator = std.testing.allocator;

    var results = try script.ScriptResults.init(allocator, "test.ovdb");
    defer results.deinit(allocator);

    try results.addResult(.{
        .command = try allocator.dupe(u8, "ping"),
        .status = .pass,
        .duration_ms = 1.5,
        .error_message = null,
        .expected = null,
        .actual = null,
    });

    try results.addResult(.{
        .command = try allocator.dupe(u8, "assert_cursor 0 5"),
        .status = .fail,
        .duration_ms = 0.8,
        .error_message = null,
        .expected = try allocator.dupe(u8, "(0, 5)"),
        .actual = try allocator.dupe(u8, "(0, 3)"),
    });

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try report(results, buffer.writer());

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "TEST_SCRIPT: test.ovdb") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[PASS] ping") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[FAIL] assert_cursor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Expected: (0, 5)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Actual: (0, 3)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FINAL:") != null);
}
