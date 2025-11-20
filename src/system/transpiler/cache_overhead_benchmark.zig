/// Benchmark: Cache Overhead for Small Files
/// Verify that caching EVERYTHING is faster than in-memory transpilation
const std = @import("std");
const esbuild = @import("esbuild.zig");

const small_config =
    \\interface Config {
    \\    tabstop: number;
    \\    expandtab: boolean;
    \\}
    \\const config: Config = { tabstop: 4, expandtab: true };
    \\vim.opt.tabstop = config.tabstop;
;

test "Benchmark: Cache Overhead vs In-Memory" {
    const allocator = std.testing.allocator;

    std.debug.print("\n\n{s}\n", .{"=" ** 80});
    std.debug.print("  CACHE OVERHEAD BENCHMARK\n", .{});
    std.debug.print("  (Verify caching small files is worth it)\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    // Create temp directory for cache
    const cache_dir = "/tmp/vimcraft-cache-test";
    std.fs.cwd().makePath(cache_dir) catch {};
    defer std.fs.cwd().deleteTree(cache_dir) catch {};

    const cache_file = "/tmp/vimcraft-cache-test/test.hbc";

    // Benchmark 1: In-memory transpilation (no cache)
    var in_memory_total: u64 = 0;
    const iterations = 100;

    std.debug.print("Running {d} iterations...\n\n", .{iterations});

    for (0..iterations) |_| {
        const start = std.time.nanoTimestamp();
        const result = try esbuild.transpile(allocator, small_config, "ts");
        allocator.free(result);
        const end = std.time.nanoTimestamp();
        in_memory_total += @as(u64, @intCast(end - start));
    }

    const in_memory_avg_ns = in_memory_total / iterations;
    const in_memory_avg_ms = @as(f64, @floatFromInt(in_memory_avg_ns)) / 1_000_000.0;

    // Benchmark 2: Cache write (first run)
    const start_write = std.time.nanoTimestamp();
    const transpiled = try esbuild.transpile(allocator, small_config, "ts");
    try std.fs.cwd().writeFile(.{ .sub_path = cache_file, .data = transpiled });
    const end_write = std.time.nanoTimestamp();
    allocator.free(transpiled);

    const cache_write_ns = @as(u64, @intCast(end_write - start_write));
    const cache_write_ms = @as(f64, @floatFromInt(cache_write_ns)) / 1_000_000.0;

    // Benchmark 3: Cache read (subsequent runs)
    var cache_read_total: u64 = 0;
    for (0..iterations) |_| {
        const start = std.time.nanoTimestamp();
        const cached = try std.fs.cwd().readFileAlloc(allocator, cache_file, 10 * 1024 * 1024);
        allocator.free(cached);
        const end = std.time.nanoTimestamp();
        cache_read_total += @as(u64, @intCast(end - start));
    }

    const cache_read_avg_ns = cache_read_total / iterations;
    const cache_read_avg_ms = @as(f64, @floatFromInt(cache_read_avg_ns)) / 1_000_000.0;

    // Results
    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  RESULTS ({d} iterations average)\n", .{iterations});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print("In-Memory Transpilation:  {d:8.3}ms\n", .{in_memory_avg_ms});
    std.debug.print("Cache Write (first run):  {d:8.3}ms\n", .{cache_write_ms});
    std.debug.print("Cache Read (cached):      {d:8.3}ms\n", .{cache_read_avg_ms});

    const speedup = in_memory_avg_ms / cache_read_avg_ms;

    std.debug.print("\n{s}\n", .{"=" ** 80});
    std.debug.print("  ANALYSIS\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    if (cache_read_avg_ms < in_memory_avg_ms) {
        std.debug.print("✅ CACHE IS FASTER by {d:.1}x\n\n", .{speedup});
        std.debug.print("Recommendation: ALWAYS cache (even small files)\n", .{});
        std.debug.print("   - First run: {d:.2}ms (transpile + write)\n", .{cache_write_ms});
        std.debug.print("   - Cached runs: {d:.2}ms (just read)\n", .{cache_read_avg_ms});
        std.debug.print("   - Speedup: {d:.1}x faster than re-transpiling\n\n", .{speedup});
    } else {
        std.debug.print("⚠️  IN-MEMORY IS FASTER\n\n", .{});
        std.debug.print("Recommendation: Skip cache for files this small\n", .{});
    }

    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  CONSISTENT ARCHITECTURE\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print(
        \\fn loadModule(path: []const u8) ![]const u8 {{
        \\    // 1. Compute cache key (path + mtime)
        \\    const cache_key = try computeCacheKey(path);
        \\    const cache_path = try getCachePath(cache_key);
        \\
        \\    // 2. Check cache
        \\    if (try isCacheFresh(path, cache_path)) {{
        \\        // Cache hit: Just load it (~0.1ms)
        \\        return try loadFromCache(cache_path);
        \\    }}
        \\
        \\    // 3. Cache miss: Build + compile + save
        \\    const bundled = try esbuildBuild(path);      // ~10-50ms
        \\    const hbc = try hermesCompile(bundled);      // ~10-30ms
        \\    try saveToCache(cache_path, hbc);            // ~1ms
        \\    return hbc;
        \\}}
        \\
        \\// Benefits:
        \\// ✅ One code path (simple!)
        \\// ✅ Always fast after first run
        \\// ✅ No complex conditionals
        \\// ✅ Cache invalidation built-in
        \\// ✅ Works for files AND directories
        \\
        \\
    , .{});

    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  CACHE INVALIDATION\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print(
        \\fn isCacheFresh(source: []const u8, cache: []const u8) !bool {{
        \\    const source_stat = try std.fs.cwd().statFile(source);
        \\    const cache_stat = try std.fs.cwd().statFile(cache) catch return false;
        \\
        \\    // Cache valid if cache is newer than source
        \\    return cache_stat.mtime >= source_stat.mtime;
        \\}}
        \\
        \\// For directories (multi-file plugins):
        \\// - Hash all file mtimes in dependency tree
        \\// - If ANY file changed → invalidate cache
        \\// - esbuild handles dependency tracking!
        \\
        \\
    , .{});

    std.debug.print("{s}\n\n", .{"=" ** 80});
}
