/// Hermes Bytecode Compiler - Zig Wrapper
/// Compiles JavaScript to Hermes Bytecode (HBC) format
/// Performance: Direct execution of hermesc binary (~10-30ms per file)
const std = @import("std");

/// Compilation error set
pub const CompileError = error{
    CompilationFailed,
    HermescNotFound,
    OutputReadFailed,
    OutOfMemory,
};

/// Compile JavaScript source to Hermes bytecode (HBC)
///
/// This function invokes the hermesc compiler to produce optimized bytecode.
/// The caller owns the returned memory and must free it.
///
/// Example:
/// ```zig
/// const js_code = "const x = 42; console.log(x);";
/// const bytecode = try compile(allocator, js_code);
/// defer allocator.free(bytecode);
/// // Now execute: hermes_runtime.evaluateBytecode(bytecode)
/// ```
pub fn compile(
    allocator: std.mem.Allocator,
    source: []const u8,
) CompileError![]const u8 {
    // Create temp files for input and output
    const timestamp = std.time.milliTimestamp();
    const temp_in = try std.fmt.allocPrint(
        allocator,
        "/tmp/vimcraft-compile-{d}.js",
        .{timestamp},
    );
    defer allocator.free(temp_in);

    const temp_out = try std.fmt.allocPrint(
        allocator,
        "/tmp/vimcraft-compile-{d}.hbc",
        .{timestamp},
    );
    defer allocator.free(temp_out);

    // Write JavaScript source to temp file
    std.fs.cwd().writeFile(.{
        .sub_path = temp_in,
        .data = source,
    }) catch |err| {
        std.log.err("Failed to write temp input file: {}", .{err});
        return CompileError.CompilationFailed;
    };
    defer std.fs.cwd().deleteFile(temp_in) catch {};

    // Invoke hermesc compiler
    // hermesc -emit-binary -out output.hbc -commonjs input.js
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "vendor/hermes/build/bin/hermesc",
            "-emit-binary",
            "-out",
            temp_out,
            "-commonjs", // Enable CommonJS require()
            "-O", // Optimize
            temp_in,
        },
    }) catch |err| {
        std.log.err("Failed to execute hermesc: {}", .{err});
        return CompileError.HermescNotFound;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Check if compilation succeeded
    if (result.term.Exited != 0) {
        std.log.err("hermesc compilation failed:\n{s}", .{result.stderr});
        std.fs.cwd().deleteFile(temp_out) catch {};
        return CompileError.CompilationFailed;
    }

    // Read compiled bytecode
    const bytecode = std.fs.cwd().readFileAlloc(
        allocator,
        temp_out,
        100 * 1024 * 1024, // Max 100MB
    ) catch |err| {
        std.log.err("Failed to read compiled bytecode: {}", .{err});
        std.fs.cwd().deleteFile(temp_out) catch {};
        return CompileError.OutputReadFailed;
    };

    // Clean up temp output file
    std.fs.cwd().deleteFile(temp_out) catch {};

    return bytecode;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "compile simple JavaScript" {
    const allocator = std.testing.allocator;

    const source =
        \\const greeting = "Hello, Hermes!";
        \\console.log(greeting);
    ;

    const bytecode = try compile(allocator, source);
    defer allocator.free(bytecode);

    // Verify bytecode was generated
    try std.testing.expect(bytecode.len > 0);

    // Hermes bytecode starts with magic number (first 8 bytes)
    // HBC magic: 0xC61F5DC0 1BBC0C51 (little-endian)
    try std.testing.expect(bytecode.len >= 8);

    std.debug.print("\n=== Compiled JavaScript ===\n", .{});
    std.debug.print("Input:  {d} bytes\n", .{source.len});
    std.debug.print("Output: {d} bytes (HBC bytecode)\n", .{bytecode.len});
    std.debug.print("Compression: {d:.1}%\n", .{
        100.0 * @as(f64, @floatFromInt(bytecode.len)) / @as(f64, @floatFromInt(source.len)),
    });
}

test "compile CommonJS module" {
    const allocator = std.testing.allocator;

    const source =
        \\const fs = require('fs');
        \\module.exports = { version: '1.0.0' };
    ;

    const bytecode = try compile(allocator, source);
    defer allocator.free(bytecode);

    // Verify compilation succeeded
    try std.testing.expect(bytecode.len > 0);

    std.debug.print("\n=== Compiled CommonJS Module ===\n", .{});
    std.debug.print("Bytecode size: {d} bytes\n", .{bytecode.len});
}

test "compile with ES2020 features" {
    const allocator = std.testing.allocator;

    const source =
        \\const optional = obj?.property;
        \\const nullish = value ?? "default";
        \\const arr = [1, 2, 3];
        \\console.log(...arr);
    ;

    const bytecode = try compile(allocator, source);
    defer allocator.free(bytecode);

    // Verify compilation succeeded
    try std.testing.expect(bytecode.len > 0);

    std.debug.print("\n=== Compiled ES2020 Features ===\n", .{});
    std.debug.print("Bytecode size: {d} bytes\n", .{bytecode.len});
}
