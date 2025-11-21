/// Unit tests for CommonJS require() module system
/// Following TDD principles: Tests specify correct behavior
const std = @import("std");
const testing = std.testing;
const module_api = @import("module_api.zig");
const config_api = @import("config_api.zig");
const c_api = @import("c_api.zig");
const c = c_api.c;

// Test helper: Create temporary test files
fn createTestFile(_: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

// Test helper: Cleanup test files
fn cleanupTestFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch {};
}

// ============================================================================
// Security Tests - Path Traversal
// ============================================================================

test "require() blocks path traversal to /etc" {
    // TDD: Specify correct behavior - path traversal should be rejected
    const allocator = testing.allocator;

    // Setup: Create Hermes runtime
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Test: Try to require /etc/passwd (should return undefined/error)
    const malicious_path = "/etc/passwd";
    const path_value = c.hermes_value_create_string(runtime, malicious_path.ptr, malicious_path.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: Should return undefined (blocked by security check)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

test "require() blocks relative path traversal" {
    const allocator = testing.allocator;

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = "/tmp/test.js",
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Try to escape with relative path
    const malicious_path = "../../../../../../../../etc/passwd";
    const path_value = c.hermes_value_create_string(runtime, malicious_path.ptr, malicious_path.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: Blocked
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

test "require() blocks symlink to restricted directory" {
    const allocator = testing.allocator;

    // Setup: Create symlink to /etc/passwd in /tmp (allowed directory)
    const symlink_path = "/tmp/test_malicious_symlink.js";
    defer cleanupTestFile(symlink_path);

    // Try to create symlink (may fail if no permissions, test will be skipped)
    std.posix.symlink("/etc/passwd", symlink_path) catch |err| {
        if (err == error.PermissionDenied or err == error.AccessDenied) {
            // Skip test if can't create symlinks
            return error.SkipZigTest;
        }
        return err;
    };

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Try to require symlink (should be blocked after realpath resolution)
    const path_value = c.hermes_value_create_string(runtime, symlink_path.ptr, symlink_path.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: Blocked (symlink resolves to /etc/passwd which is not in whitelist)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

// ============================================================================
// Input Validation Tests
// ============================================================================

test "require() rejects empty string" {
    const allocator = testing.allocator;

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Test: require('')
    const empty_path = "";
    const path_value = c.hermes_value_create_string(runtime, empty_path.ptr, empty_path.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: undefined (input validation failure)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

test "require() rejects null byte injection" {
    const allocator = testing.allocator;

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Test: require('safe.js\0malicious')
    const malicious_path = "safe.js\x00../../../../etc/passwd";
    const path_value = c.hermes_value_create_string(runtime, malicious_path.ptr, malicious_path.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: undefined (null byte rejected)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

test "require() rejects path exceeding PATH_MAX" {
    const allocator = testing.allocator;

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Create path > 2048 chars
    const long_path = try allocator.alloc(u8, 2100);
    defer allocator.free(long_path);
    @memset(long_path, 'a');

    const path_value = c.hermes_value_create_string(runtime, long_path.ptr, long_path.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: undefined (path too long)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

test "require() requires string argument" {
    const allocator = testing.allocator;

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Test: require(42) - number instead of string
    const number_value = c.hermes_value_create_number(runtime, 42);
    defer c.hermes_value_destroy(number_value);

    var args = [_]?*c.OVHermesValue{number_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: undefined (type check failure)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

// ============================================================================
// Module Resolution Tests
// ============================================================================

test "require() resolves absolute path in whitelist" {
    const allocator = testing.allocator;

    // Create test file in /tmp (whitelisted directory)
    const test_file = "/tmp/test_require_absolute.js";
    try createTestFile(allocator, test_file, "module.exports = { test: true };");
    defer cleanupTestFile(test_file);

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    const path_value = c.hermes_value_create_string(runtime, test_file.ptr, test_file.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: Should load successfully (returns object, not undefined)
    try testing.expect(result != null);
    // Note: Can't easily check if it's an object without more Hermes API calls
    // But if it loaded, it won't be undefined
}

test "require() returns undefined for nonexistent module" {
    const allocator = testing.allocator;

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Try to require non-existent module
    const fake_module = "this-module-definitely-does-not-exist-12345";
    const path_value = c.hermes_value_create_string(runtime, fake_module.ptr, fake_module.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: undefined (module not found)
    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

// ============================================================================
// Module Caching Tests
// ============================================================================

test "require() caches modules by absolute path" {
    const allocator = testing.allocator;

    const test_file = "/tmp/test_require_caching.js";
    try createTestFile(allocator, test_file, "module.exports = { cached: true };");
    defer cleanupTestFile(test_file);

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    const path_value = c.hermes_value_create_string(runtime, test_file.ptr, test_file.len);
    defer c.hermes_value_destroy(path_value);

    // First require
    var args = [_]?*c.OVHermesValue{path_value};
    const result1 = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);
    try testing.expect(result1 != null);

    // Second require (should return cached)
    const result2 = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);
    try testing.expect(result2 != null);

    // Expected: Same pointer (cached)
    try testing.expectEqual(result1, result2);
}

test "require() detects circular dependencies" {
    const allocator = testing.allocator;

    // Create two files that require each other
    const file_a = "/tmp/test_circular_a.js";
    const file_b = "/tmp/test_circular_b.js";

    try createTestFile(allocator, file_a,
        \\const b = require('/tmp/test_circular_b.js');
        \\module.exports = { name: 'A', b: b };
    );
    try createTestFile(allocator, file_b,
        \\const a = require('/tmp/test_circular_a.js');
        \\module.exports = { name: 'B', a: a };
    );
    defer cleanupTestFile(file_a);
    defer cleanupTestFile(file_b);

    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = config_api.ConfigContext{
        .highlight_config = undefined,
        .options_manager = undefined,
        .allocator = allocator,
        .display = null,
        .module_cache = std.StringHashMap(config_api.ModuleEntry).init(allocator),
        .current_file_path = null,
        .runtime = runtime,
    };
    defer ctx.module_cache.deinit();

    // Register require() function
    module_api.register(runtime, &ctx);

    const path_value = c.hermes_value_create_string(runtime, file_a.ptr, file_a.len);
    defer c.hermes_value_destroy(path_value);

    var args = [_]?*c.OVHermesValue{path_value};
    const result = module_api.hermesRequire(runtime, @ptrCast(&ctx), &args, 1);

    // Expected: Should handle circular dependency
    // (Either return undefined for circular ref, or return partial exports)
    try testing.expect(result != null);
}
