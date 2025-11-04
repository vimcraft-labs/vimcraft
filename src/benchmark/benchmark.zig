const std = @import("std");

/// Benchmark result for a single operation
pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
    min_ns: u64,
    max_ns: u64,
    avg_ms: f64,

    pub fn format(
        self: BenchmarkResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}: {d} iterations, avg {d:.3}ms (min {d:.3}ms, max {d:.3}ms)\n", .{
            self.name,
            self.iterations,
            self.avg_ms,
            @as(f64, @floatFromInt(self.min_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(self.max_ns)) / 1_000_000.0,
        });
    }
};

/// Benchmark a function N times and return statistics
pub fn benchmark(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    iterations: usize,
    comptime func: anytype,
    args: anytype,
) !BenchmarkResult {
    var times = try allocator.alloc(u64, iterations);
    defer allocator.free(times);

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = std.time.nanoTimestamp();

        // Call the function with provided arguments
        // Handle both void and error union returns
        const ReturnType = @TypeOf(@call(.auto, func, args));
        if (@typeInfo(ReturnType) == .error_union or @typeInfo(ReturnType) == .error_set) {
            _ = @call(.auto, func, args) catch {};
        } else {
            _ = @call(.auto, func, args);
        }

        const end = std.time.nanoTimestamp();
        times[i] = @intCast(end - start);
    }

    // Calculate statistics
    var total: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;

    for (times) |t| {
        total += t;
        if (t < min_time) min_time = t;
        if (t > max_time) max_time = t;
    }

    const avg = total / iterations;
    const avg_ms = @as(f64, @floatFromInt(avg)) / 1_000_000.0;

    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_ns = total,
        .avg_ns = avg,
        .min_ns = min_time,
        .max_ns = max_time,
        .avg_ms = avg_ms,
    };
}

/// Benchmark suite for collecting multiple benchmark results
pub const BenchmarkSuite = struct {
    results: std.ArrayList(BenchmarkResult),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BenchmarkSuite {
        return .{
            .results = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BenchmarkSuite) void {
        self.results.deinit(self.allocator);
    }

    pub fn add(self: *BenchmarkSuite, result: BenchmarkResult) !void {
        try self.results.append(self.allocator, result);
    }

    pub fn printSummary(self: *const BenchmarkSuite) void {
        std.debug.print("\n=== Performance Benchmark Results ===\n\n", .{});

        for (self.results.items) |result| {
            std.debug.print("{any}\n", .{result});

            // Check if operation meets <16ms target
            if (result.avg_ms > 16.0) {
                std.debug.print("  ⚠️  EXCEEDS 16ms TARGET\n", .{});
            } else {
                std.debug.print("  ✅ Within 16ms target\n", .{});
            }
        }

        std.debug.print("\n=== Summary ===\n", .{});
        var passed: usize = 0;
        var failed: usize = 0;

        for (self.results.items) |result| {
            if (result.avg_ms <= 16.0) {
                passed += 1;
            } else {
                failed += 1;
            }
        }

        std.debug.print("Passed: {d}/{d}\n", .{ passed, self.results.items.len });
        if (failed > 0) {
            std.debug.print("Failed: {d}/{d}\n", .{ failed, self.results.items.len });
        }
    }
};

// Simple warmup function to stabilize timing
pub fn warmup() void {
    var i: usize = 0;
    var sum: usize = 0;
    while (i < 1000) : (i += 1) {
        sum +%= i;
    }
    std.mem.doNotOptimizeAway(&sum);
}
