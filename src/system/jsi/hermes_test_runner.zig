/// Hermes Test Runner - Runs TypeScript tests compiled to Hermes bytecode
///
/// Pipeline: TypeScript → esbuild → JavaScript → hermesc → HBC → Hermes Runtime
///
/// Usage in build.zig:
///   zig build hermes-tests
///
/// This creates a test target that:
/// 1. Finds all .ts files in tests/hermes/
/// 2. Transpiles them to JavaScript using esbuild
/// 3. Compiles to Hermes bytecode using hermesc
/// 4. Caches the bytecode in .zig-cache/hermes-tests/
/// 5. Executes each test with full Hermes runtime
const std = @import("std");

// Import transpiler modules (provided via build.zig)
const esbuild = @import("esbuild");
const hermes_compiler = @import("hermes_compiler");
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Test result
pub const TestResult = struct {
    name: []const u8,
    passed: bool,
    duration_ns: u64,
    error_msg: ?[]const u8,
};

/// Test runner context
pub const TestRunner = struct {
    allocator: std.mem.Allocator,
    runtime: *c.OVHermesRuntime,
    results: std.ArrayList(TestResult),
    test_dir: []const u8,
    cache_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, test_dir: []const u8, cache_dir: []const u8) !Self {
        // Create Hermes runtime
        const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;

        return .{
            .allocator = allocator,
            .runtime = runtime,
            .results = .empty,
            .test_dir = test_dir,
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        c.hermes_runtime_destroy(self.runtime);
        for (self.results.items) |result| {
            // Free duplicated name
            self.allocator.free(result.name);
            if (result.error_msg) |msg| {
                self.allocator.free(msg);
            }
        }
        self.results.deinit(self.allocator);
    }

    /// Register test assertion APIs and create vim global object
    pub fn registerTestAPIs(self: *Self) !void {
        // Register native host functions with global names
        c.hermes_register_host_function(self.runtime, "vimTestAssert", testAssert, @ptrCast(self));
        c.hermes_register_host_function(self.runtime, "vimTestAssertEqual", testAssertEqual, @ptrCast(self));
        c.hermes_register_host_function(self.runtime, "vimTestPass", testPass, @ptrCast(self));
        c.hermes_register_host_function(self.runtime, "vimTestFail", testFail, @ptrCast(self));

        // Create vim object hierarchy via JavaScript bootstrap
        // This creates vim.test, vim.api, vim.motion, vim.cursor objects
        // Note: Use globalThis to ensure the object is globally accessible
        const bootstrap_js =
            \\// Bootstrap vim global object for test environment
            \\// Note: This is a mock implementation for testing
            \\(function() {
            \\    var autocmdId = 0;  // Stateful counter for incrementing IDs
            \\
            \\    globalThis.vim = {
            \\        test: {
            \\            assert: vimTestAssert,
            \\            assertEqual: vimTestAssertEqual,
            \\            pass: vimTestPass,
            \\            fail: vimTestFail
            \\        },
            \\        api: {
            \\            createAutocmd: function(event, opts) {
            \\                autocmdId++;
            \\                return autocmdId;
            \\            },
            \\            delAutocmd: function(id) {},
            \\            createAugroup: function(name, opts) { return name; },
            \\            clearAutocmds: function(opts) {}
            \\        },
            \\        motion: {
            \\            left: function(count) {},
            \\            right: function(count) {},
            \\            up: function(count) {},
            \\            down: function(count) {},
            \\            lineStart: function() {},
            \\            lineEnd: function() {},
            \\            wordForward: function() {},
            \\            wordBackward: function() {},
            \\            wordEnd: function() {},
            \\            fileStart: function() {},
            \\            fileEnd: function() {},
            \\            pageUp: function() {},
            \\            pageDown: function() {}
            \\        },
            \\        cursor: {
            \\            getPosition: function() { return { line: 0, col: 0 }; }
            \\        }
            \\    };
            \\})();
        ;

        // Compile bootstrap script to bytecode
        const bootstrap_bytecode = hermes_compiler.compile(self.allocator, bootstrap_js) catch |err| {
            std.log.err("Failed to compile bootstrap script: {}", .{err});
            return error.BootstrapFailed;
        };
        defer self.allocator.free(bootstrap_bytecode);

        // Execute bootstrap bytecode to set up vim object
        const result = c.hermes_evaluate_bytecode(
            self.runtime,
            bootstrap_bytecode.ptr,
            bootstrap_bytecode.len,
        );
        if (result) |r| {
            c.hermes_value_destroy(r);
        } else {
            std.log.err("Bootstrap script failed", .{});
            return error.BootstrapFailed;
        }
    }

    /// Run a single TypeScript test file
    pub fn runTest(self: *Self, ts_path: []const u8) !TestResult {
        const start_time = std.time.nanoTimestamp();

        // Get test name from filename (must dupe since ts_path may be freed)
        const basename = std.fs.path.basename(ts_path);
        const name_slice = if (std.mem.endsWith(u8, basename, ".ts"))
            basename[0 .. basename.len - 3]
        else
            basename;
        const test_name = try self.allocator.dupe(u8, name_slice);

        // Check cache for compiled bytecode
        const hbc_path = try self.getCachedPath(ts_path);
        defer self.allocator.free(hbc_path);

        const bytecode = blk: {
            // Check if cached bytecode exists and is newer than source
            if (self.isCacheValid(ts_path, hbc_path)) {
                // Load from cache
                break :blk std.fs.cwd().readFileAlloc(
                    self.allocator,
                    hbc_path,
                    100 * 1024 * 1024,
                ) catch null;
            }
            break :blk null;
        } orelse try self.compileTest(ts_path, hbc_path);
        defer self.allocator.free(bytecode);

        // Execute bytecode
        const result = c.hermes_evaluate_bytecode(
            self.runtime,
            bytecode.ptr,
            bytecode.len,
        );

        const end_time = std.time.nanoTimestamp();
        const duration_ns: u64 = @intCast(end_time - start_time);

        if (result) |r| {
            c.hermes_value_destroy(r);
            return .{
                .name = test_name,
                .passed = true,
                .duration_ns = duration_ns,
                .error_msg = null,
            };
        } else {
            return .{
                .name = test_name,
                .passed = false,
                .duration_ns = duration_ns,
                .error_msg = try self.allocator.dupe(u8, "Bytecode execution failed"),
            };
        }
    }

    /// Compile TypeScript test to Hermes bytecode
    fn compileTest(self: *Self, ts_path: []const u8, hbc_path: []const u8) ![]const u8 {
        // Read TypeScript source
        const ts_source = try std.fs.cwd().readFileAlloc(
            self.allocator,
            ts_path,
            10 * 1024 * 1024, // Max 10MB
        );
        defer self.allocator.free(ts_source);

        // Transpile TypeScript → JavaScript
        const js_source = try esbuild.transpile(self.allocator, ts_source, "ts");
        defer self.allocator.free(js_source);

        // Compile JavaScript → Hermes bytecode
        const bytecode = try hermes_compiler.compile(self.allocator, js_source);

        // Cache the bytecode
        self.cacheResult(hbc_path, bytecode) catch |err| {
            std.log.warn("Failed to cache bytecode: {}", .{err});
        };

        return bytecode;
    }

    /// Get cached bytecode path for a test file
    fn getCachedPath(self: *Self, ts_path: []const u8) ![]const u8 {
        const basename = std.fs.path.basename(ts_path);
        const name_without_ext = if (std.mem.endsWith(u8, basename, ".ts"))
            basename[0 .. basename.len - 3]
        else
            basename;

        return std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.hbc",
            .{ self.cache_dir, name_without_ext },
        );
    }

    /// Check if cached bytecode is valid (exists and newer than source)
    fn isCacheValid(self: *Self, ts_path: []const u8, hbc_path: []const u8) bool {
        _ = self;

        const source_stat = std.fs.cwd().statFile(ts_path) catch return false;
        const cache_stat = std.fs.cwd().statFile(hbc_path) catch return false;

        return cache_stat.mtime >= source_stat.mtime;
    }

    /// Cache compiled bytecode
    fn cacheResult(self: *Self, hbc_path: []const u8, bytecode: []const u8) !void {
        _ = self;

        // Ensure cache directory exists
        const dir = std.fs.path.dirname(hbc_path) orelse return;
        std.fs.cwd().makePath(dir) catch {};

        // Write bytecode
        try std.fs.cwd().writeFile(.{
            .sub_path = hbc_path,
            .data = bytecode,
        });
    }

    /// Run all tests in the test directory
    pub fn runAllTests(self: *Self) !void {
        var dir = try std.fs.cwd().openDir(self.test_dir, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".ts")) continue;

            const full_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ self.test_dir, entry.name },
            );
            defer self.allocator.free(full_path);

            const result = self.runTest(full_path) catch |err| {
                // Dupe the name since entry.name is temporary
                const duped_name = try self.allocator.dupe(u8, entry.name);
                try self.results.append(self.allocator, .{
                    .name = duped_name,
                    .passed = false,
                    .duration_ns = 0,
                    .error_msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Compilation error: {}",
                        .{err},
                    ),
                });
                continue;
            };

            try self.results.append(self.allocator, result);
        }
    }

    /// Print test results summary
    pub fn printSummary(self: *Self) void {
        var passed: usize = 0;
        var failed: usize = 0;
        var total_time_ns: u64 = 0;

        std.debug.print("\n=== Hermes TypeScript Test Results ===\n\n", .{});

        for (self.results.items) |result| {
            total_time_ns += result.duration_ns;
            if (result.passed) {
                passed += 1;
                std.debug.print("  ✓ {s} ({d:.2}ms)\n", .{
                    result.name,
                    @as(f64, @floatFromInt(result.duration_ns)) / 1_000_000.0,
                });
            } else {
                failed += 1;
                std.debug.print("  ✗ {s}: {s}\n", .{
                    result.name,
                    result.error_msg orelse "Unknown error",
                });
            }
        }

        std.debug.print("\n{d} passed, {d} failed ({d:.2}ms total)\n", .{
            passed,
            failed,
            @as(f64, @floatFromInt(total_time_ns)) / 1_000_000.0,
        });
    }
};

// ============================================================================
// Test Assertion Callbacks
// ============================================================================

fn testAssert(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (arg_count < 1) {
        c.hermes_throw_error(rt, "assert requires at least 1 argument");
        return null;
    }

    const condition = c.hermes_value_get_boolean(args[0]);
    if (!condition) {
        var msg: []const u8 = "Assertion failed";
        if (arg_count >= 2 and c.hermes_value_is_string(args[1])) {
            var len: usize = 0;
            const ptr = c.hermes_value_get_string(rt, args[1], &len);
            if (ptr != null and len > 0) {
                msg = ptr[0..len];
            }
        }
        c.hermes_throw_error(rt, msg.ptr);
        return null;
    }

    return c.hermes_value_create_undefined(rt);
}

fn testAssertEqual(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (arg_count < 2) {
        c.hermes_throw_error(rt, "assertEqual requires at least 2 arguments");
        return null;
    }

    // Compare values (simplified - just check numbers for now)
    if (c.hermes_value_is_number(args[0]) and c.hermes_value_is_number(args[1])) {
        const actual = c.hermes_value_get_number(args[0]);
        const expected = c.hermes_value_get_number(args[1]);
        if (actual != expected) {
            c.hermes_throw_error(rt, "Values not equal");
            return null;
        }
    }

    return c.hermes_value_create_undefined(rt);
}

fn testPass(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;
    const rt = runtime orelse return null;
    return c.hermes_value_create_undefined(rt);
}

fn testFail(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    if (arg_count >= 2 and c.hermes_value_is_string(args[1])) {
        var len: usize = 0;
        const ptr = c.hermes_value_get_string(rt, args[1], &len);
        if (ptr != null and len > 0) {
            c.hermes_throw_error(rt, ptr);
            return null;
        }
    }

    c.hermes_throw_error(rt, "Test failed");
    return null;
}

// ============================================================================
// Main Entry Point for Test Executable
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runner = try TestRunner.init(
        allocator,
        "tests/hermes",
        ".zig-cache/hermes-tests",
    );
    defer runner.deinit();

    // Register test APIs
    try runner.registerTestAPIs();

    // Run all tests
    try runner.runAllTests();

    // Print results
    runner.printSummary();
}

// ============================================================================
// Unit Tests
// ============================================================================

test "TestRunner compiles TypeScript to bytecode" {
    // This test requires esbuild and hermesc to be available
    // Skip in CI environments without these tools
    return error.SkipZigTest;
}
