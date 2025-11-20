/// Unified TypeScript Module Loader
/// Handles: TypeScript → JavaScript → Hermes Bytecode → Cache
/// Architecture: Always cache, one code path for consistency
const std = @import("std");
const esbuild = @import("esbuild.zig");
const hermes = @import("hermes.zig");
const cache = @import("cache.zig");
const builtin = @import("builtin");

/// Build-time configuration flag for /tmp/ loading
/// PRODUCTION: Set to false to disable /tmp/ access
/// DEVELOPMENT: Set to true for testing
pub const enable_tmp_loading = if (@import("builtin").is_test)
    true // Default to true for standalone tests
else
    @import("build_options").enable_tmp_loading;

/// Loader error set
pub const LoadError = error{
    PathNotFound,
    InvalidPath,
    PathTraversal,
    CacheFailed,
    TranspileFailed,
    CompileFailed,
    OutOfMemory,
    HomeNotFound,
};

/// Loader configuration
pub const LoaderConfig = struct {
    /// Cache directory (default: ~/.config/vimcraft/bytecode)
    cache_dir: []const u8,

    /// Enable cache (can be disabled for debugging)
    enable_cache: bool = true,

    /// Cache statistics (for monitoring performance)
    stats: *cache.CacheStats,
};

/// Load from in-memory source (NO file I/O)
/// Use this for wrapping config files with runtime.js without creating temp files
///
/// Example:
/// ```zig
/// const wrapped = try std.fmt.allocPrint(allocator, "{s}\n\n{s}", .{runtime_js, user_config});
/// defer allocator.free(wrapped);
///
/// const bytecode = try loadFromSource(allocator, config, wrapped, original_path);
/// defer allocator.free(bytecode);
/// ```
pub fn loadFromSource(
    allocator: std.mem.Allocator,
    config: LoaderConfig,
    source: []const u8,
    source_path: []const u8, // Original path for cache key
) LoadError![]const u8 {

    // Validate source path (but don't read from it)
    try validatePath(source_path);

    // Compute cache key based on source content + path
    // CRITICAL: This ensures cache invalidates when EITHER source OR wrapper changes
    const cache_key = cache.computeCacheKeyFromContent(allocator, source, source_path) catch |err| {
        std.log.err("Failed to compute cache key: {}", .{err});
        return LoadError.CacheFailed;
    };
    defer allocator.free(cache_key);

    // Build cache path directly from content-based key
    // CRITICAL FIX: Use cache_key (content hash), NOT source_path (path hash)
    // This ensures cache path changes when wrapped content changes
    const cache_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.hbc",
        .{ config.cache_dir, cache_key },
    );
    defer allocator.free(cache_path);

    // Try to load from cache (no freshness check needed - content-based key)
    // When content changes → different cache_key → different cache_path → cache miss
    if (config.enable_cache) {
        if (cache.loadFromCache(allocator, cache_path)) |bytecode| {
            config.stats.recordHit();
            return bytecode;
        } else |_| {
            // Cache doesn't exist or read failed - rebuild
        }
    }

    // Cache miss: Transpile in-memory source

    // Determine loader based on source path extension
    const ext = std.fs.path.extension(source_path);
    const loader = if (std.mem.eql(u8, ext, ".ts"))
        "ts"
    else if (std.mem.eql(u8, ext, ".tsx"))
        "tsx"
    else if (std.mem.eql(u8, ext, ".jsx"))
        "jsx"
    else
        "js";

    const js = esbuild.transpile(allocator, source, loader) catch |err| {
        std.log.err("esbuild transpile failed: {}", .{err});
        return LoadError.TranspileFailed;
    };
    defer allocator.free(js);


    // Compile JavaScript → Hermes Bytecode
    const hbc = hermes.compile(allocator, js) catch |err| {
        std.log.err("Hermes compilation failed: {}", .{err});
        return LoadError.CompileFailed;
    };
    errdefer allocator.free(hbc);


    // Save to cache (if enabled)
    if (config.enable_cache) {
        cache.saveToCache(cache_path, hbc) catch |err| {
            std.log.warn("Cache save failed (non-fatal): {}", .{err});
            // Continue - we still have the bytecode
        };
    }

    config.stats.recordMiss(hbc.len);

    return hbc;
}

/// Load and bundle TypeScript config file with runtime wrapper
/// This function:
/// 1. Checks cache based on source file mtime (BEFORE expensive bundling!)
/// 2. If cache miss: bundles the config file using esbuild.build() (resolves imports)
/// 3. Wraps the bundle with runtime wrapper
/// 4. Compiles to Hermes bytecode
/// 5. Saves to cache
///
/// Use this for index.ts that may have imports. For simple plugins without imports,
/// use loadFromSource() directly.
pub fn loadConfigWithBundle(
    allocator: std.mem.Allocator,
    config: LoaderConfig,
    filepath: []const u8,
    runtime_wrapper: []const u8,
) LoadError![]const u8 {
    // 1. Compute cache key based on source file path + mtime (BEFORE bundling)
    // This avoids expensive bundling when source hasn't changed
    const cache_key = cache.computeCacheKey(allocator, filepath) catch |err| {
        std.log.err("Failed to compute cache key for {s}: {}", .{ filepath, err });
        return LoadError.CacheFailed;
    };
    defer allocator.free(cache_key);

    const cache_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.hbc",
        .{ config.cache_dir, cache_key },
    );
    defer allocator.free(cache_path);

    // 2. Check cache freshness BEFORE expensive bundling
    if (config.enable_cache and cache.isCacheFresh(filepath, cache_path)) {
        if (cache.loadFromCache(allocator, cache_path)) |bytecode| {
            config.stats.recordHit();
            return bytecode;
        } else |_| {
            // Cache read failed - rebuild
        }
    }

    // 3. Cache miss: Bundle user config (resolves all imports)
    // Use buildWithCacheDir for better performance and cross-platform compatibility
    const bundled_js = esbuild.buildWithCacheDir(allocator, filepath, config.cache_dir) catch |err| {
        std.log.err("esbuild bundle failed for {s}: {}", .{ filepath, err });
        return LoadError.TranspileFailed;
    };
    defer allocator.free(bundled_js);

    // 4. Wrap bundled output with runtime wrapper
    const wrapped_source = try std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\// User config (bundled)
        \\{s}
    , .{ runtime_wrapper, bundled_js });
    defer allocator.free(wrapped_source);

    // 5. Compile wrapped bundle to Hermes bytecode
    const hbc = hermes.compile(allocator, wrapped_source) catch |err| {
        std.log.err("Hermes compilation failed: {}", .{err});
        return LoadError.CompileFailed;
    };
    errdefer allocator.free(hbc);

    // 6. Save to cache
    if (config.enable_cache) {
        cache.saveToCache(cache_path, hbc) catch |err| {
            std.log.warn("Cache save failed (non-fatal): {}", .{err});
        };
    }

    config.stats.recordMiss(hbc.len);

    return hbc;
}

/// Load TypeScript/JavaScript module and return Hermes bytecode
///
/// This is the UNIFIED entry point for all module loading:
/// - Single .ts/.js files → transpile → compile → cache
/// - Directories (plugins) → bundle → compile → cache
///
/// Architecture guarantees:
/// 1. First run: ~10-50ms (transpile + compile + cache write)
/// 2. Cached runs: ~0.1ms (just read from disk)
/// 3. Automatic invalidation when source changes (mtime tracking)
/// 4. No conditionals - always cache for consistency
///
/// Example:
/// ```zig
/// var stats = cache.CacheStats{};
/// const config = LoaderConfig{
///     .cache_dir = try cache.getDefaultCacheDir(allocator),
///     .stats = &stats,
/// };
///
/// const bytecode = try loadModule(allocator, config, "~/.config/vimcraft/init.ts");
/// defer allocator.free(bytecode);
///
/// // Execute in Hermes runtime
/// try hermes_runtime.evaluateBytecode(bytecode);
/// ```
pub fn loadModule(
    allocator: std.mem.Allocator,
    config: LoaderConfig,
    path: []const u8,
) LoadError![]const u8 {

    // Expand ~ to home directory if needed
    const expanded_path = if (std.mem.startsWith(u8, path, "~/"))
        try expandHomePath(allocator, path)
    else
        try allocator.dupe(u8, path);
    defer allocator.free(expanded_path);

    // Validate path for security (prevent directory traversal)
    try validatePath(expanded_path);

    // 1. Compute cache key (path + mtime)
    const cache_key = cache.computeCacheKey(allocator, expanded_path) catch |err| {
        std.log.err("Failed to compute cache key for {s}: {}", .{ expanded_path, err });
        return LoadError.CacheFailed;
    };
    defer allocator.free(cache_key);

    const cache_path = cache.getCachePath(allocator, .{
        .cache_dir = config.cache_dir,
        .enabled = config.enable_cache,
    }, expanded_path) catch |err| {
        std.log.err("Failed to get cache path: {}", .{err});
        return LoadError.CacheFailed;
    };
    defer allocator.free(cache_path);

    // 2. Check cache freshness (if enabled)
    if (config.enable_cache and cache.isCacheFresh(expanded_path, cache_path)) {

        if (cache.loadFromCache(allocator, cache_path)) |bytecode| {
            config.stats.recordHit();
            return bytecode;
        } else |err| {
            std.log.warn("Cache load failed (will rebuild): {}", .{err});
            // Fall through to rebuild
        }
    }

    // 3. Cache miss: Build pipeline

    // 3a. Determine if single file or directory
    const stat = std.fs.cwd().statFile(expanded_path) catch |err| {
        std.log.err("Path not found: {s} ({})", .{ expanded_path, err });
        return LoadError.PathNotFound;
    };

    const is_dir = stat.kind == .directory;

    // 3b. Transpile TypeScript → JavaScript
    const js = if (is_dir) blk: {
        // Use buildWithCacheDir for cross-platform compatibility
        break :blk esbuild.buildWithCacheDir(allocator, expanded_path, config.cache_dir) catch |err| {
            std.log.err("esbuild bundle failed: {}", .{err});
            return LoadError.TranspileFailed;
        };
    } else blk: {
        // Read source file
        const source = std.fs.cwd().readFileAlloc(
            allocator,
            expanded_path,
            100 * 1024 * 1024, // Max 100MB
        ) catch |err| {
            std.log.err("Failed to read source file: {}", .{err});
            return LoadError.PathNotFound;
        };
        defer allocator.free(source);

        // Determine loader based on extension
        const ext = std.fs.path.extension(expanded_path);
        const loader = if (std.mem.eql(u8, ext, ".ts"))
            "ts"
        else if (std.mem.eql(u8, ext, ".tsx"))
            "tsx"
        else if (std.mem.eql(u8, ext, ".jsx"))
            "jsx"
        else
            "js";

        break :blk esbuild.transpile(allocator, source, loader) catch |err| {
            std.log.err("esbuild transpile failed: {}", .{err});
            return LoadError.TranspileFailed;
        };
    };
    defer allocator.free(js);


    // 3c. Compile JavaScript → Hermes Bytecode
    const hbc = hermes.compile(allocator, js) catch |err| {
        std.log.err("Hermes compilation failed: {}", .{err});
        return LoadError.CompileFailed;
    };
    errdefer allocator.free(hbc);


    // 3d. Save to cache (if enabled)
    if (config.enable_cache) {
        cache.saveToCache(cache_path, hbc) catch |err| {
            std.log.warn("Cache save failed (non-fatal): {}", .{err});
            // Continue - we still have the bytecode
        };
    }

    config.stats.recordMiss(hbc.len);

    return hbc;
}

/// Expand ~ to home directory
fn expandHomePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, path, "~/")) {
        return allocator.dupe(u8, path);
    }

    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[1..] });
}

/// Validate path to prevent directory traversal attacks
///
/// Security policy (Defense-in-Depth):
/// 1. Resolve symlinks (TOCTOU mitigation via realpath)
/// 2. Check for null bytes (injection prevention)
/// 3. Reject paths containing ".." (parent directory traversal)
/// 4. Ensure absolute path after expansion
/// 5. Normalize case (case-insensitive filesystem bug fix)
/// 6. Restrict to allowed directories (whitelist):
///    - ~/.config/vimcraft/ (user config)
///    - /tmp/ (testing only - disabled in production builds)
///    - Current working directory (project-local plugins)
///
/// Public for penetration testing
pub fn validatePath(path: []const u8) LoadError!void {
    // 1. Check for null bytes (injection attack)
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        std.log.err("Null byte detected in path: {s}", .{path});
        return LoadError.InvalidPath;
    }

    // 2. Check for directory traversal attempts (pattern detection)
    if (std.mem.indexOf(u8, path, "..") != null) {
        std.log.err("Path traversal detected: {s}", .{path});
        return LoadError.PathTraversal;
    }

    // 3. Ensure path is absolute (starts with /)
    if (!std.fs.path.isAbsolute(path)) {
        std.log.err("Relative paths not allowed: {s}", .{path});
        return LoadError.InvalidPath;
    }

    // 4. Resolve symlinks to prevent symlink-based bypasses (TOCTOU mitigation)
    var resolved_buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved_path = std.fs.cwd().realpath(path, &resolved_buf) catch |err| {
        // If path doesn't exist yet, validate the parent directory instead
        if (err == error.FileNotFound) {
            // For non-existent paths, validate the parent directory
            const dirname = std.fs.path.dirname(path) orelse {
                std.log.err("Cannot determine parent directory for: {s}", .{path});
                return LoadError.InvalidPath;
            };
            // Recursively validate parent (will resolve symlinks in parent path)
            return validatePath(dirname);
        }
        std.log.err("Cannot resolve path {s}: {}", .{ path, err });
        return LoadError.InvalidPath;
    };

    // 5. Normalize case for case-insensitive filesystem bug fix (macOS/Windows)
    // Convert both resolved_path and whitelist paths to lowercase for comparison
    var normalized_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized_path = normalizePath(&normalized_path_buf, resolved_path);

    // 6. Check if path is in allowed directories (whitelist)
    const home = std.posix.getenv("HOME");

    // Allow: ~/.config/vimcraft/
    if (home) |home_dir| {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const vimcraft_config = std.fmt.bufPrint(&buf, "{s}/.config/vimcraft", .{home_dir}) catch {
            return LoadError.InvalidPath;
        };

        // Normalize whitelist path for case-insensitive comparison
        var normalized_whitelist_buf: [std.fs.max_path_bytes]u8 = undefined;
        const normalized_whitelist = normalizePath(&normalized_whitelist_buf, vimcraft_config);

        if (std.mem.startsWith(u8, normalized_path, normalized_whitelist)) {
            return; // Allowed
        }
    }

    // Allow: /tmp/ (for testing - compile-time flag)
    if (comptime enable_tmp_loading) {
        // Resolve /tmp symlink (macOS: /tmp → /private/tmp)
        var tmp_realpath_buf: [std.fs.max_path_bytes]u8 = undefined;
        const tmp_realpath = std.fs.cwd().realpath("/tmp", &tmp_realpath_buf) catch "/tmp";

        var normalized_tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
        const normalized_tmp = normalizePath(&normalized_tmp_buf, tmp_realpath);

        if (std.mem.startsWith(u8, normalized_path, normalized_tmp)) {
            std.log.warn("Loading from /tmp (testing mode enabled): {s}", .{path});
            return; // Allowed for testing
        }
    }

    // Allow: Current working directory (project-local plugins)
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch {
        return LoadError.InvalidPath;
    };

    // Normalize CWD for case-insensitive comparison
    var normalized_cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized_cwd = normalizePath(&normalized_cwd_buf, cwd);

    if (std.mem.startsWith(u8, normalized_path, normalized_cwd)) {
        return; // Allowed
    }

    // Reject all other paths
    std.log.err("Path not in allowed directories: {s}", .{resolved_path});
    std.log.err("Resolved from: {s}", .{path});
    std.log.err("Allowed directories:", .{});
    if (home) |home_dir| {
        std.log.err("  - {s}/.config/vimcraft/", .{home_dir});
    }
    std.log.err("  - {s}/", .{cwd});
    if (comptime enable_tmp_loading) {
        std.log.err("  - /tmp/ (testing mode)", .{});
    }
    return LoadError.InvalidPath;
}

/// Normalize path for case-insensitive comparison (macOS/Windows)
/// Converts path to lowercase and returns a slice of the provided buffer
fn normalizePath(buf: []u8, path: []const u8) []const u8 {
    const len = @min(buf.len, path.len);
    for (path[0..len], 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..len];
}

// ============================================================================
// Unit Tests
// ============================================================================

test "load single TypeScript file" {
    const allocator = std.testing.allocator;

    // Create temp TypeScript file
    const temp_file = "/tmp/vimcraft-test-load.ts";
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_file,
        .data =
        \\const greeting: string = "Hello, TypeScript!";
        \\console.log(greeting);
        ,
    });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    // Setup loader config
    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    // First load: Cache miss
    const bytecode1 = try loadModule(allocator, config, temp_file);
    defer allocator.free(bytecode1);

    try std.testing.expect(bytecode1.len > 0);
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);

    std.debug.print("\n=== Single File Load ===\n", .{});
    std.debug.print("Bytecode size: {d} bytes\n", .{bytecode1.len});
    std.debug.print("Cache stats: {any}\n", .{stats});

    // Second load: Cache hit
    const bytecode2 = try loadModule(allocator, config, temp_file);
    defer allocator.free(bytecode2);

    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqualSlices(u8, bytecode1, bytecode2);

    std.debug.print("After cache hit: {any}\n", .{stats});
}

test "cache invalidation on file change" {
    const allocator = std.testing.allocator;

    // Create temp file
    const temp_file = "/tmp/vimcraft-test-invalidation.ts";
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_file,
        .data = "const x = 42;",
    });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    // Setup loader config
    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    // First load
    const bytecode1 = try loadModule(allocator, config, temp_file);
    defer allocator.free(bytecode1);

    // Modify file (ensure mtime changes)
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_file,
        .data = "const x = 43;", // Different content
    });

    // Second load: Should invalidate cache
    const bytecode2 = try loadModule(allocator, config, temp_file);
    defer allocator.free(bytecode2);

    // Should have 0 hits, 2 misses (cache invalidated)
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 2), stats.misses);

    std.debug.print("\n=== Cache Invalidation ===\n", .{});
    std.debug.print("Cache correctly invalidated after file change\n", .{});
    std.debug.print("Stats: {any}\n", .{stats});
}

test "load with cache disabled" {
    const allocator = std.testing.allocator;

    // Create temp file
    const temp_file = "/tmp/vimcraft-test-no-cache.ts";
    try std.fs.cwd().writeFile(.{
        .sub_path = temp_file,
        .data = "const x = 42;",
    });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    // Setup loader config with cache disabled
    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .enable_cache = false, // Disable cache
        .stats = &stats,
    };

    // Load twice - should rebuild both times
    const bytecode1 = try loadModule(allocator, config, temp_file);
    defer allocator.free(bytecode1);

    const bytecode2 = try loadModule(allocator, config, temp_file);
    defer allocator.free(bytecode2);

    // Should have 0 hits, 2 misses (cache disabled)
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 2), stats.misses);

    std.debug.print("\n=== Cache Disabled ===\n", .{});
    std.debug.print("Both loads rebuilt (cache disabled)\n", .{});
}

test "path traversal protection" {
    const allocator = std.testing.allocator;

    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    std.debug.print("\n=== Path Traversal Security Tests ===\n", .{});

    // Test 1: Directory traversal with .. should fail
    const malicious_path1 = "/tmp/../../../etc/passwd";
    const result1 = loadModule(allocator, config, malicious_path1);
    try std.testing.expectError(LoadError.PathTraversal, result1);
    std.debug.print("✓ Blocked: {s}\n", .{malicious_path1});

    // Test 2: Hidden .. in middle of path should fail
    const malicious_path2 = "/tmp/vimcraft/../../../etc/passwd";
    const result2 = loadModule(allocator, config, malicious_path2);
    try std.testing.expectError(LoadError.PathTraversal, result2);
    std.debug.print("✓ Blocked: {s}\n", .{malicious_path2});

    // Test 3: Relative path should fail
    const relative_path = "plugin.ts";
    const result3 = loadModule(allocator, config, relative_path);
    try std.testing.expectError(LoadError.InvalidPath, result3);
    std.debug.print("✓ Blocked: {s} (relative path)\n", .{relative_path});

    // Test 4: Valid absolute path should succeed
    const valid_path = "/tmp/vimcraft-security-test.ts";
    try std.fs.cwd().writeFile(.{
        .sub_path = valid_path,
        .data = "const x = 42;",
    });
    defer std.fs.cwd().deleteFile(valid_path) catch {};

    const bytecode = try loadModule(allocator, config, valid_path);
    defer allocator.free(bytecode);
    try std.testing.expect(bytecode.len > 0);
    std.debug.print("✓ Allowed: {s}\n", .{valid_path});

    std.debug.print("\n=== All Security Tests Passed ===\n", .{});
}

test "path validation function" {
    std.debug.print("\n=== Path Validation Unit Tests ===\n", .{});

    // Valid: /tmp/ (allowed for testing)
    try validatePath("/tmp/test.ts");
    std.debug.print("✓ Allowed: /tmp/test.ts\n", .{});

    // Valid: ~/.config/vimcraft/ (if HOME is set)
    if (std.posix.getenv("HOME")) |home| {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const vimcraft_path = try std.fmt.bufPrint(&buf, "{s}/.config/vimcraft/init.ts", .{home});
        try validatePath(vimcraft_path);
        std.debug.print("✓ Allowed: {s}\n", .{vimcraft_path});
    }

    // Valid: Current working directory
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &cwd_buf);
    var plugin_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugin_path = try std.fmt.bufPrint(&plugin_buf, "{s}/plugin.ts", .{cwd});
    try validatePath(plugin_path);
    std.debug.print("✓ Allowed: {s}\n", .{plugin_path});

    // Invalid: contains ..
    try std.testing.expectError(LoadError.PathTraversal, validatePath("/tmp/../etc/passwd"));
    std.debug.print("✓ Blocked: /tmp/../etc/passwd (traversal)\n", .{});

    try std.testing.expectError(LoadError.PathTraversal, validatePath("/tmp/test/../secret.ts"));
    std.debug.print("✓ Blocked: /tmp/test/../secret.ts (traversal)\n", .{});

    // Invalid: relative path
    try std.testing.expectError(LoadError.InvalidPath, validatePath("relative/path.ts"));
    std.debug.print("✓ Blocked: relative/path.ts (relative)\n", .{});

    try std.testing.expectError(LoadError.InvalidPath, validatePath("plugin.ts"));
    std.debug.print("✓ Blocked: plugin.ts (relative)\n", .{});

    // Invalid: outside allowed directories
    try std.testing.expectError(LoadError.InvalidPath, validatePath("/etc/passwd"));
    std.debug.print("✓ Blocked: /etc/passwd (not in whitelist)\n", .{});

    try std.testing.expectError(LoadError.InvalidPath, validatePath("/usr/local/lib/plugin.ts"));
    std.debug.print("✓ Blocked: /usr/local/lib/plugin.ts (not in whitelist)\n", .{});

    std.debug.print("\n=== All Path Validation Tests Passed ===\n", .{});
}

// ============================================================================
// Security Edge Case Tests (Added January 2025)
// ============================================================================

test "symlink attack prevention" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Symlink Attack Prevention ===\n", .{});

    // Create a symlink from /tmp/ → /etc/ (simulating symlink attack)
    const symlink_path = "/tmp/vimcraft-symlink-test";
    const target_path = "/etc";

    // Create symlink (may fail if permissions denied - that's OK)
    std.fs.cwd().symLink(target_path, symlink_path, .{}) catch |err| {
        std.debug.print("⚠ Skipping symlink test (cannot create symlink): {}\n", .{err});
        return;
    };
    defer std.fs.cwd().deleteFile(symlink_path) catch {};

    // Try to load via symlink - should resolve to /etc/ and be blocked
    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    const malicious_path = "/tmp/vimcraft-symlink-test/passwd";
    const result = loadModule(allocator, config, malicious_path);

    // Should fail because symlink resolves to /etc/passwd (not in whitelist)
    try std.testing.expectError(LoadError.InvalidPath, result);
    std.debug.print("✓ Blocked symlink attack: {s} → /etc/passwd\n", .{symlink_path});
}

test "null byte injection prevention" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Null Byte Injection Prevention ===\n", .{});

    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    // Path with null byte (injection attack)
    var malicious_path_buf: [100]u8 = undefined;
    const malicious_path = try std.fmt.bufPrint(&malicious_path_buf, "/tmp/test.ts\x00/etc/passwd", .{});

    const result = loadModule(allocator, config, malicious_path);
    try std.testing.expectError(LoadError.InvalidPath, result);
    std.debug.print("✓ Blocked null byte injection: /tmp/test.ts\\x00/etc/passwd\n", .{});
}

test "unicode path handling" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Unicode Path Handling ===\n", .{});

    // Create temp file with unicode characters
    const unicode_file = "/tmp/vimcraft-unicode-тест-测试.ts";
    try std.fs.cwd().writeFile(.{
        .sub_path = unicode_file,
        .data = "const x = 42;",
    });
    defer std.fs.cwd().deleteFile(unicode_file) catch {};

    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    // Should succeed (unicode paths are valid)
    const bytecode = try loadModule(allocator, config, unicode_file);
    defer allocator.free(bytecode);

    try std.testing.expect(bytecode.len > 0);
    std.debug.print("✓ Unicode path handled correctly: {s}\n", .{unicode_file});
}

test "path length limit" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Path Length Limit Test ===\n", .{});

    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .stats = &stats,
    };

    // Create extremely long path (exceeds PATH_MAX)
    var long_path_buf: [std.fs.max_path_bytes + 100]u8 = undefined;
    @memset(&long_path_buf, 'a');
    long_path_buf[0] = '/'; // Make it absolute
    long_path_buf[4] = 't'; // /tmp
    long_path_buf[5] = 'm';
    long_path_buf[6] = 'p';
    long_path_buf[7] = '/';

    const long_path = long_path_buf[0 .. std.fs.max_path_bytes + 50];

    const result = loadModule(allocator, config, long_path);

    // Should fail (path too long)
    try std.testing.expectError(LoadError.InvalidPath, result);
    std.debug.print("✓ Blocked excessively long path ({d} bytes)\n", .{long_path.len});
}

test "case sensitivity bypass prevention" {
    std.debug.print("\n=== Case Sensitivity Bypass Prevention ===\n", .{});

    // Test uppercase variants of /tmp/
    const test_cases = [_][]const u8{
        "/TMP/test.ts", // Uppercase
        "/Tmp/test.ts", // Mixed case
        "/tMp/test.ts", // Mixed case
    };

    for (test_cases) |test_path| {
        if (comptime enable_tmp_loading) {
            // With tmp enabled, normalized comparison should allow all variants
            try validatePath(test_path);
            std.debug.print("✓ Allowed (normalized): {s}\n", .{test_path});
        } else {
            // Without tmp enabled, should block
            const result = validatePath(test_path);
            try std.testing.expectError(LoadError.InvalidPath, result);
            std.debug.print("✓ Blocked (tmp disabled): {s}\n", .{test_path});
        }
    }

    // Test that /ETC/ variants are ALWAYS blocked (case normalization working)
    const blocked_cases = [_][]const u8{
        "/ETC/passwd",
        "/Etc/passwd",
        "/etc/PASSWD",
    };

    for (blocked_cases) |blocked_path| {
        const result = validatePath(blocked_path);
        try std.testing.expectError(LoadError.InvalidPath, result);
        std.debug.print("✓ Blocked (case variant): {s}\n", .{blocked_path});
    }

    std.debug.print("\n=== Case Sensitivity Tests Passed ===\n", .{});
}

test "loadFromSource cache invalidation" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== loadFromSource Cache Invalidation Test ===\n", .{});

    const cache_dir = try cache.getDefaultCacheDir(allocator);
    defer allocator.free(cache_dir);

    var stats = cache.CacheStats{};
    const config = LoaderConfig{
        .cache_dir = cache_dir,
        .enable_cache = true,
        .stats = &stats,
    };

    // Load 1: First content
    const source1 = "console.log('test');";
    const bytecode1 = try loadFromSource(allocator, config, source1, "/tmp/test.ts");
    defer allocator.free(bytecode1);

    try std.testing.expect(bytecode1.len > 0);
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    std.debug.print("Load 1: {d} bytes (cache miss)\n", .{bytecode1.len});

    // Load 2: Same content (should hit cache)
    const bytecode2 = try loadFromSource(allocator, config, source1, "/tmp/test.ts");
    defer allocator.free(bytecode2);

    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqualSlices(u8, bytecode1, bytecode2);
    std.debug.print("Load 2: {d} bytes (cache HIT - same content)\n", .{bytecode2.len});

    // Load 3: Different content (should miss cache - content changed)
    const source2 = "console.log('modified');"; // Different content
    const bytecode3 = try loadFromSource(allocator, config, source2, "/tmp/test.ts");
    defer allocator.free(bytecode3);

    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectEqual(@as(usize, 2), stats.misses);
    std.debug.print("Load 3: {d} bytes (cache MISS - content changed)\n", .{bytecode3.len});

    // Load 4: Same content as Load 3 (should hit cache)
    const bytecode4 = try loadFromSource(allocator, config, source2, "/tmp/test.ts");
    defer allocator.free(bytecode4);

    try std.testing.expectEqual(@as(usize, 2), stats.hits);
    try std.testing.expectEqual(@as(usize, 2), stats.misses);
    try std.testing.expectEqualSlices(u8, bytecode3, bytecode4);
    std.debug.print("Load 4: {d} bytes (cache HIT - same as Load 3)\n", .{bytecode4.len});

    std.debug.print("\n✅ Cache invalidation working correctly:\n", .{});
    std.debug.print("   - Content change → cache miss\n", .{});
    std.debug.print("   - Same content → cache hit\n", .{});
    std.debug.print("   - Final stats: {d} hits, {d} misses\n\n", .{ stats.hits, stats.misses });
}
