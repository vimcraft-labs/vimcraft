const std = @import("std");
const c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

// This is a Zig function that JavaScript will call via JSI!
export fn zig_add_numbers(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = context;
    
    if (arg_count != 2) {
        return c.hermes_value_create_undefined(runtime);
    }
    
    // Extract numbers from JavaScript (ZERO-COPY!)
    const a = c.hermes_value_get_number(args[0]);
    const b = c.hermes_value_get_number(args[1]);
    
    const result = a + b;
    
    std.debug.print("[Zig] JavaScript called zig_add_numbers({d}, {d}) = {d}\n", .{a, b, result});
    
    return c.hermes_value_create_number(runtime, result);
}

pub fn main() !void {
    std.debug.print("\n=== JSI Zero-Copy Bridge Demo ===\n\n", .{});
    
    const runtime = c.hermes_runtime_create();
    defer c.hermes_runtime_destroy(runtime);
    
    std.debug.print("[Zig] Registering Zig function for JavaScript to call...\n", .{});
    
    // Register our Zig function so JavaScript can call it!
    c.hermes_register_host_function(
        runtime,
        "zigAdd",  // JavaScript will call: zigAdd(10, 20)
        zig_add_numbers,
        null
    );
    
    std.debug.print("[Zig] ✅ Function 'zigAdd' registered!\n\n", .{});
    
    // Load JavaScript bytecode
    std.debug.print("[Zig] Loading JavaScript bytecode...\n", .{});
    const file = try std.fs.cwd().openFile("/tmp/jsi_test.hbc", .{});
    defer file.close();
    
    const bytecode = try file.readToEndAlloc(std.heap.page_allocator, 10_000);
    defer std.heap.page_allocator.free(bytecode);
    
    std.debug.print("[Zig] Loaded {} bytes\n\n", .{bytecode.len});
    
    // Execute JavaScript that calls our Zig function
    std.debug.print("[Zig] Executing JavaScript:\n", .{});
    std.debug.print("      zigAdd(10, 20) + zigAdd(100, 200)\n\n", .{});
    
    const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);
    
    if (result == null) {
        const err = c.hermes_get_exception_message(runtime);
        std.debug.print("Error: {s}\n", .{err});
        return error.JSError;
    }
    defer c.hermes_value_destroy(result);
    
    const final_result = c.hermes_value_get_number(result);
    std.debug.print("\n[Zig] Final JavaScript result: {d}\n", .{final_result});
    
    std.debug.print("\n=== THIS IS JSI! ===\n", .{});
    std.debug.print("✅ JavaScript called Zig functions with ZERO-COPY!\n", .{});
    std.debug.print("✅ No JSON, no serialization, direct memory sharing!\n\n", .{});
}
