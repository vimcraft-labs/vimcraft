/// TypeScript Module Cache Management
/// Provides unified caching for all TypeScript modules (single files + multi-file plugins)
const std = @import("std");
const esbuild = @import("esbuild.zig");

/// Cache error set
pub const CacheError = error{
    CacheDirectoryCreationFailed,
    CacheKeyComputationFailed,
    CacheReadFailed,
    CacheWriteFailed,
    OutOfMemory,
};

/// Cache configuration
pub const CacheConfig = struct {
    /// Cache directory (default: ~/.cache/vimcraft/bytecode)
    cache_dir: []const u8,

    /// Enable cache (can be disabled for debugging)
    enabled: bool = true,
};

/// Compute cache key from file path using fast WyHash
/// Returns 16-char hex string (64-bit hash)
///
/// Note: We hash ONLY the path, not mtime. Cache invalidation is handled
/// separately by isCacheFresh() which compares mtimes.
pub fn computeCacheKey(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]const u8 {
    // Fast hash using WyHash (100x faster than SHA256)
    const hash = std.hash.Wyhash.hash(0, path);

    // Convert to 16-char hex string
    return try std.fmt.allocPrint(allocator, "{x:0>16}", .{hash});
}

/// Compute cache key from in-memory source content + path
/// Used for wrapped config files (runtime.js + user config)
/// This ensures cache invalidates when EITHER source OR wrapper changes
pub fn computeCacheKeyFromContent(
    allocator: std.mem.Allocator,
    content: []const u8,
    path: []const u8,
) ![]const u8 {
    // Hash both content AND path (ensures unique cache per file)
    const content_hash = std.hash.Wyhash.hash(0, content);
    const path_hash = std.hash.Wyhash.hash(0, path);

    // Combine hashes (simple XOR is sufficient for cache key)
    const combined_hash = content_hash ^ path_hash;

    // Convert to 16-char hex string
    return try std.fmt.allocPrint(allocator, "{x:0>16}", .{combined_hash});
}

/// Get cache file path for given source file
pub fn getCachePath(
    allocator: std.mem.Allocator,
    config: CacheConfig,
    source_path: []const u8,
) ![]const u8 {
    const cache_key = try computeCacheKey(allocator, source_path);
    defer allocator.free(cache_key);

    return try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.hbc",
        .{ config.cache_dir, cache_key },
    );
}

/// Check if cache is fresh (cache mtime >= source mtime)
pub fn isCacheFresh(
    source_path: []const u8,
    cache_path: []const u8,
) bool {
    const source_stat = std.fs.cwd().statFile(source_path) catch return false;
    const cache_stat = std.fs.cwd().statFile(cache_path) catch return false;

    // Cache is fresh if it's newer than or equal to source
    return cache_stat.mtime >= source_stat.mtime;
}

/// Load bytecode from cache
pub fn loadFromCache(
    allocator: std.mem.Allocator,
    cache_path: []const u8,
) ![]const u8 {
    return std.fs.cwd().readFileAlloc(
        allocator,
        cache_path,
        100 * 1024 * 1024, // Max 100MB
    ) catch |err| {
        std.log.debug("Cache read failed for {s}: {}", .{ cache_path, err });
        return CacheError.CacheReadFailed;
    };
}

/// Save bytecode to cache
pub fn saveToCache(
    cache_path: []const u8,
    bytecode: []const u8,
) !void {
    // Ensure cache directory exists
    const cache_dir = std.fs.path.dirname(cache_path) orelse return CacheError.CacheDirectoryCreationFailed;
    std.fs.cwd().makePath(cache_dir) catch |err| {
        std.log.err("Failed to create cache directory {s}: {}", .{ cache_dir, err });
        return CacheError.CacheDirectoryCreationFailed;
    };

    // Write bytecode to cache
    std.fs.cwd().writeFile(.{
        .sub_path = cache_path,
        .data = bytecode,
    }) catch |err| {
        std.log.err("Failed to write cache {s}: {}", .{ cache_path, err });
        return CacheError.CacheWriteFailed;
    };

    std.log.info("Cached bytecode: {s} ({d} bytes)", .{ cache_path, bytecode.len });
}

/// Initialize cache directory
pub fn initCacheDir(cache_dir: []const u8) !void {
    std.fs.cwd().makePath(cache_dir) catch |err| {
        std.log.err("Failed to create cache directory {s}: {}", .{ cache_dir, err });
        return CacheError.CacheDirectoryCreationFailed;
    };

    std.log.info("Cache directory initialized: {s}", .{cache_dir});
}

/// Get default cache directory (~/.cache/vimcraft/bytecode)
pub fn getDefaultCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.cache/vimcraft/bytecode", .{home});
}

/// Cache statistics for debugging
pub const CacheStats = struct {
    hits: usize = 0,
    misses: usize = 0,
    total_bytes_cached: usize = 0,

    pub fn recordHit(self: *CacheStats) void {
        self.hits += 1;
    }

    pub fn recordMiss(self: *CacheStats, bytes: usize) void {
        self.misses += 1;
        self.total_bytes_cached += bytes;
    }

    pub fn hitRate(self: CacheStats) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }

    pub fn format(
        self: CacheStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Cache Stats: {d} hits, {d} misses, {d:.1}% hit rate, {d} bytes cached", .{
            self.hits,
            self.misses,
            self.hitRate() * 100.0,
            self.total_bytes_cached,
        });
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "cache key computation" {
    const allocator = std.testing.allocator;

    // Test 1: Key is deterministic for same path
    const path1 = "/tmp/vimcraft-test-cache-key.ts";
    const key1 = try computeCacheKey(allocator, path1);
    defer allocator.free(key1);

    // Key should be 16 hex chars (64-bit hash)
    try std.testing.expectEqual(@as(usize, 16), key1.len);

    // Compute again - should be same (deterministic)
    const key2 = try computeCacheKey(allocator, path1);
    defer allocator.free(key2);

    try std.testing.expectEqualStrings(key1, key2);

    // Test 2: Different paths produce different keys
    const path2 = "/tmp/vimcraft-test-different.ts";
    const key3 = try computeCacheKey(allocator, path2);
    defer allocator.free(key3);

    // Keys should be different for different paths
    try std.testing.expect(!std.mem.eql(u8, key1, key3));

    std.debug.print("\n=== Cache Key Tests ===\n", .{});
    std.debug.print("Path 1: {s}\n", .{path1});
    std.debug.print("  Key: {s}\n", .{key1});
    std.debug.print("Path 2: {s}\n", .{path2});
    std.debug.print("  Key: {s}\n\n", .{key3});
}

test "cache freshness check" {
    const temp_source = "/tmp/vimcraft-test-source.ts";
    const temp_cache = "/tmp/vimcraft-test-cache.hbc";

    // Create source file
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_source,
        .data = "const x = 42;",
    });
    defer std.fs.cwd().deleteFile(temp_source) catch {};

    // No cache yet - should be stale
    try std.testing.expect(!isCacheFresh(temp_source, temp_cache));

    // Create cache file
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_cache,
        .data = "cached_bytecode",
    });
    defer std.fs.cwd().deleteFile(temp_cache) catch {};

    // Cache should be fresh (just created)
    try std.testing.expect(isCacheFresh(temp_source, temp_cache));

    // Modify source - cache should be stale
    std.Thread.sleep(10 * std.time.ns_per_ms); // Ensure mtime changes
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_source,
        .data = "const x = 43;",
    });

    try std.testing.expect(!isCacheFresh(temp_source, temp_cache));
}

test "cache save and load" {
    const allocator = std.testing.allocator;

    const cache_path = "/tmp/vimcraft-test-save-load.hbc";
    defer std.fs.cwd().deleteFile(cache_path) catch {};

    const test_data = "test_bytecode_data_12345";

    // Save to cache
    try saveToCache(cache_path, test_data);

    // Load from cache
    const loaded = try loadFromCache(allocator, cache_path);
    defer allocator.free(loaded);

    try std.testing.expectEqualStrings(test_data, loaded);
}

test "cache stats tracking" {
    var stats = CacheStats{};

    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 0), stats.misses);
    try std.testing.expectEqual(@as(f64, 0.0), stats.hitRate());

    stats.recordHit();
    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectEqual(@as(f64, 1.0), stats.hitRate());

    stats.recordMiss(1024);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqual(@as(f64, 0.5), stats.hitRate());
    try std.testing.expectEqual(@as(usize, 1024), stats.total_bytes_cached);
}
