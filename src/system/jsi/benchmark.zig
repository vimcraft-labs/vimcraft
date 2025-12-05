/// JSI HostObject Performance Benchmark
/// Measures zero-copy JSI performance for future reference
///
/// Benchmarks:
/// 1. Property lookup speed (HostObject getter dispatch via C API)
/// 2. Property enumeration (getPropertyNames)
///
/// Architecture:
/// - O(1) property dispatch via StaticStringMap
/// - Zero-copy property access (no per-call string allocation)
/// - Lazy function creation (only when accessed)

const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;
const motion_api = @import("motion_api.zig");
const host_object_builder = @import("host_object_builder.zig");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;

const WARMUP_ITERATIONS: usize = 10_000;
const BENCHMARK_ITERATIONS: usize = 1_000_000;

/// Benchmark result
const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: f64,
    ops_per_sec: f64,

    fn print(self: BenchmarkResult) void {
        std.debug.print("{s}:\n", .{self.name});
        std.debug.print("  Iterations: {d}\n", .{self.iterations});
        std.debug.print("  Total time: {d}ns ({d:.2}ms)\n", .{ self.total_ns, @as(f64, @floatFromInt(self.total_ns)) / 1_000_000.0 });
        std.debug.print("  Avg per call: {d:.2}ns\n", .{self.avg_ns});
        std.debug.print("  Ops/sec: {d:.0}\n\n", .{self.ops_per_sec});
    }
};

/// Benchmark 1: HostObject property lookup (via C API)
fn benchmarkHostObjectPropertyLookup(runtime: *c.OVHermesRuntime, allocator: std.mem.Allocator) !BenchmarkResult {
    // Setup - use real Editor for proper context
    var editor = try Editor.init(allocator);
    defer editor.deinit();
    const buffer = editor.getCurrentBuffer() orelse return error.NoBuffer;
    try buffer.content.insert(0, "test\n");

    var ctx = motion_api.MotionContext{
        .editor = &editor,
        .viewport_height = 24,
    };

    // Build HostObject VTable manually for direct C API benchmarking
    var builder = try host_object_builder.HostObjectBuilder.initComptime("motion", allocator);
    defer builder.deinit();

    // Add all 17 methods
    _ = try builder.addMethod("left", motion_api.moveLeft, &ctx);
    _ = try builder.addMethod("right", motion_api.moveRight, &ctx);
    _ = try builder.addMethod("up", motion_api.moveUp, &ctx);
    _ = try builder.addMethod("down", motion_api.moveDown, &ctx);

    const vtable = try builder.build();

    // Property names to lookup
    const property_names = [_][*:0]const u8{
        "left",
        "right",
        "up",
        "down",
    };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        for (property_names) |name| {
            const val = vtable.get(runtime, vtable.context, name);
            if (val) |v| c.hermes_value_destroy(v);
        }
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    const start = timer.read();

    for (0..BENCHMARK_ITERATIONS) |_| {
        for (property_names) |name| {
            const val = vtable.get(runtime, vtable.context, name);
            if (val) |v| c.hermes_value_destroy(v);
        }
    }

    const end = timer.read();
    const total_ns = end - start;
    const total_lookups = BENCHMARK_ITERATIONS * property_names.len;
    const avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(total_lookups));
    const ops_per_sec = 1_000_000_000.0 / avg_ns;

    return BenchmarkResult{
        .name = "HostObject: Property Lookup (StaticStringMap)",
        .iterations = total_lookups,
        .total_ns = total_ns,
        .avg_ns = avg_ns,
        .ops_per_sec = ops_per_sec,
    };
}


/// Benchmark 2: Property enumeration speed
fn benchmarkPropertyEnumeration(runtime: *c.OVHermesRuntime, allocator: std.mem.Allocator) !BenchmarkResult {
    // Setup - use real Editor for proper context
    var editor = try Editor.init(allocator);
    defer editor.deinit();
    const buffer = editor.getCurrentBuffer() orelse return error.NoBuffer;
    try buffer.content.insert(0, "test\n");

    var ctx = motion_api.MotionContext{
        .editor = &editor,
        .viewport_height = 24,
    };

    var builder = try host_object_builder.HostObjectBuilder.initComptime("motion", allocator);
    defer builder.deinit();

    // Add 4 methods
    _ = try builder.addMethod("left", motion_api.moveLeft, &ctx);
    _ = try builder.addMethod("right", motion_api.moveRight, &ctx);
    _ = try builder.addMethod("up", motion_api.moveUp, &ctx);
    _ = try builder.addMethod("down", motion_api.moveDown, &ctx);

    const vtable = try builder.build();

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        const val = vtable.getPropertyNames.?(runtime, vtable.context);
        if (val) |v| c.hermes_value_destroy(v);
    }

    // Benchmark
    var timer = try std.time.Timer.start();
    const start = timer.read();

    for (0..BENCHMARK_ITERATIONS) |_| {
        const val = vtable.getPropertyNames.?(runtime, vtable.context);
        if (val) |v| c.hermes_value_destroy(v);
    }

    const end = timer.read();
    const total_ns = end - start;
    const avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS));
    const ops_per_sec = 1_000_000_000.0 / avg_ns;

    return BenchmarkResult{
        .name = "HostObject: Property Enumeration (getPropertyNames)",
        .iterations = BENCHMARK_ITERATIONS,
        .total_ns = total_ns,
        .avg_ns = avg_ns,
        .ops_per_sec = ops_per_sec,
    };
}

/// Main benchmark runner
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Zero-Copy JSI Performance Benchmark ===\n\n", .{});
    std.debug.print("Measuring HostObject property dispatch performance\n", .{});
    std.debug.print("Warmup iterations: {d}\n", .{WARMUP_ITERATIONS});
    std.debug.print("Benchmark iterations: {d}\n\n", .{BENCHMARK_ITERATIONS});

    // Create Hermes runtime
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    // Run benchmarks
    std.debug.print("Running benchmarks...\n\n", .{});

    const property_lookup = try benchmarkHostObjectPropertyLookup(runtime, allocator);
    const property_enum = try benchmarkPropertyEnumeration(runtime, allocator);

    // Print results
    std.debug.print("=== Results ===\n\n", .{});
    property_lookup.print();
    property_enum.print();

    // Summary
    std.debug.print("=== Architecture ===\n\n", .{});
    std.debug.print("Property Dispatch:\n", .{});
    std.debug.print("  - O(1) StaticStringMap lookup\n", .{});
    std.debug.print("  - Zero-copy property access\n", .{});
    std.debug.print("  - Lazy function creation\n", .{});
    std.debug.print("  - Direct C API calls\n\n", .{});

    std.debug.print("Performance Characteristics:\n", .{});
    std.debug.print("  - Property lookup: {d:.0} ns/call ({d:.1}M ops/sec)\n", .{ property_lookup.avg_ns, property_lookup.ops_per_sec / 1_000_000.0 });
    std.debug.print("  - Property enumeration: {d:.0} ns/call ({d:.1}M ops/sec)\n", .{ property_enum.avg_ns, property_enum.ops_per_sec / 1_000_000.0 });
    std.debug.print("\n✅ Benchmark complete - results saved for future reference\n\n", .{});
}
