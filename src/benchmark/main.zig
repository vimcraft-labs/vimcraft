const std = @import("std");
const buffer_bench = @import("buffer_bench.zig");
const display_bench = @import("display_bench.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║         OpenVim Performance Benchmark Suite                ║\n", .{});
    std.debug.print("║         Target: <16ms per operation (60fps)                ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Run buffer benchmarks
    try buffer_bench.runBufferBenchmarks(allocator);

    // Run display benchmarks
    try display_bench.runDisplayBenchmarks(allocator);

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║              Benchmark Suite Complete                      ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}
