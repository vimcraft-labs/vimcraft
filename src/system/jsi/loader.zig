/// Loader Module
/// Handles JavaScript plugin and config file loading
/// Compiles JS to Hermes bytecode for performance
const std = @import("std");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Compile JavaScript to Hermes bytecode using hermesc
fn compileJsToBytecode(js_path: []const u8, hbc_path: []const u8) !void {
    // Run hermesc to compile JS to bytecode
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{
            "vendor/hermes/build/bin/hermesc",
            "-emit-binary",
            "-out",
            hbc_path,
            js_path,
        },
    }) catch |err| {
        std.debug.print("[JSI] Failed to run hermesc: {}\n", .{err});
        return err;
    };
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        // Keep stderr errors for hermesc failures (critical)
        std.debug.print("[JSI] hermesc failed:\n{s}\n", .{result.stderr});
        return error.CompilationFailed;
    }

    // Compilation successful (silent mode)
}

/// Check if file needs recompilation (returns true if hbc is missing or older than js)
fn needsRecompilation(js_path: []const u8, hbc_path: []const u8) bool {
    const js_file = std.fs.openFileAbsolute(js_path, .{}) catch return true;
    defer js_file.close();

    const hbc_file = std.fs.openFileAbsolute(hbc_path, .{}) catch return true;
    defer hbc_file.close();

    const js_stat = js_file.stat() catch return true;
    const hbc_stat = hbc_file.stat() catch return true;

    // Compare modification times (need recompile if js is newer)
    return js_stat.mtime > hbc_stat.mtime;
}

/// Load and execute JavaScript plugin file (NO wrapper - uses existing globals)
pub fn loadPlugin(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Read plugin source
    const file = std.fs.openFileAbsolute(filepath, .{}) catch |err| {
        std.debug.print("[JSI] Could not open plugin file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1_000_000);
    defer allocator.free(source);

    // Bytecode path (no .wrapped.js for plugins!)
    const hbc_path = try std.fmt.allocPrint(allocator, "{s}.hbc", .{filepath});
    defer allocator.free(hbc_path);

    // Compile if needed
    if (needsRecompilation(filepath, hbc_path)) {
        try compileJsToBytecode(filepath, hbc_path);
    }

    // Load and execute bytecode
    const hbc_file = try std.fs.openFileAbsolute(hbc_path, .{});
    defer hbc_file.close();

    const bytecode = try hbc_file.readToEndAlloc(allocator, 10_000_000);
    defer allocator.free(bytecode);

    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[JSI] Plugin error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
}

/// Load and execute JavaScript configuration file (via bytecode)
pub fn loadConfig(runtime: *c.OVHermesRuntime, filepath: []const u8, allocator: std.mem.Allocator) !void {
    // Loading config (silent mode)

    // Read source to wrap it with vim API
    const file = std.fs.openFileAbsolute(filepath, .{}) catch |err| {
        // Keep critical errors
        std.debug.print("[JSI] Could not open config file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1_000_000);
    defer allocator.free(source);

    // Load runtime wrapper at compile time
    const runtime_wrapper = @embedFile("runtime.js");

    // Wrap user config with runtime wrapper
    const wrapped_source = try std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\// User config
        \\{s}
    , .{ runtime_wrapper, source });
    defer allocator.free(wrapped_source);

    // Write wrapped source to temp file for compilation
    const temp_js_path = try std.fmt.allocPrint(allocator, "{s}.wrapped.js", .{filepath});
    defer allocator.free(temp_js_path);

    const temp_js_file = try std.fs.createFileAbsolute(temp_js_path, .{});
    defer temp_js_file.close();
    try temp_js_file.writeAll(wrapped_source);

    // Bytecode path
    const hbc_path = try std.fmt.allocPrint(allocator, "{s}.hbc", .{filepath});
    defer allocator.free(hbc_path);

    // Compile if needed (check if wrapped.js is newer than hbc)
    if (needsRecompilation(temp_js_path, hbc_path)) {
        // Compiling to bytecode (silent mode)
        try compileJsToBytecode(temp_js_path, hbc_path);
    }

    // Load bytecode
    const hbc_file = try std.fs.openFileAbsolute(hbc_path, .{});
    defer hbc_file.close();

    const bytecode = try hbc_file.readToEndAlloc(allocator, 10_000_000);
    defer allocator.free(bytecode);

    // Execute bytecode
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);

    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        // Keep critical errors
        std.debug.print("[JSI] JavaScript error: {s}\n", .{err_msg});
        return error.JSError;
    }

    defer c.hermes_value_destroy(result);
    // Config loaded successfully (silent mode)
}
