const std = @import("std");

// Import Hermes C API
const c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

pub fn main() !void {
    std.debug.print("\n=== Zig Calling Hermes JavaScript Engine ===\n\n", .{});
    
    // Create Hermes runtime
    std.debug.print("[Zig] Creating Hermes runtime...\n", .{});
    const runtime = c.hermes_runtime_create();
    if (runtime == null) {
        std.debug.print("[Zig] FAIL: Could not create runtime\n", .{});
        return error.HermesInitFailed;
    }
    defer c.hermes_runtime_destroy(runtime);
    
    std.debug.print("[Zig] ✅ Hermes runtime created!\n\n", .{});
    
    // Load bytecode file
    std.debug.print("[Zig] Loading bytecode from /tmp/test.hbc...\n", .{});
    const file = try std.fs.cwd().openFile("/tmp/test.hbc", .{});
    defer file.close();
    
    const bytecode = try file.readToEndAlloc(std.heap.page_allocator, 10_000);
    defer std.heap.page_allocator.free(bytecode);
    
    std.debug.print("[Zig] Loaded {} bytes of bytecode\n\n", .{bytecode.len});
    
    // Execute JavaScript
    std.debug.print("[Zig] Executing JavaScript: 2 + 2\n", .{});
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);
    
    if (result == null) {
        const err_msg = c.hermes_get_exception_message(runtime);
        std.debug.print("[Zig] FAIL: {s}\n", .{err_msg});
        return error.JavaScriptError;
    }
    defer c.hermes_value_destroy(result);
    
    std.debug.print("[Zig] ✅ JavaScript executed successfully!\n\n", .{});
    
    // Get result
    if (c.hermes_value_is_number(result)) {
        const num = c.hermes_value_get_number(result);
        std.debug.print("[Zig] Result: {d}\n\n", .{num});
    }
    
    std.debug.print("=== SUCCESS: ZIG IS RUNNING JAVASCRIPT! ===\n", .{});
    std.debug.print("Hermes version: {s}\n\n", .{c.hermes_get_version()});
}
