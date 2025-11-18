/// JSI HostObject Performance Benchmark Entry Point
/// This wrapper allows benchmark.zig to access editor modules via relative imports

const benchmark = @import("system/jsi/benchmark.zig");

pub fn main() !void {
    try benchmark.main();
}
