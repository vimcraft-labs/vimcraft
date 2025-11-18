/// HostObject Infrastructure Tests
/// Verifies zero-copy JSI HostObject implementation works correctly
///
/// Test Coverage:
/// - HostObject registration and property access
/// - Property enumeration (Object.keys support)
/// - Multiple HostObjects coexisting
/// - Error handling for invalid properties
/// - Memory management (no leaks)

const std = @import("std");
const testing = std.testing;

// Import JSI infrastructure
const c_api = @import("c_api.zig");
const c = c_api.c;
const host_object_builder = @import("host_object_builder.zig");

// Test fixtures
const TestContext = struct {
    call_count: usize = 0,
    last_value: i32 = 0,
};

// Dummy host functions for testing
fn testMethod1(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const ctx = @as(*TestContext, @ptrCast(@alignCast(context.?)));
    ctx.call_count += 1;
    return c.hermes_value_create_number(runtime, 42.0);
}

fn testMethod2(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = arg_count;
    const ctx = @as(*TestContext, @ptrCast(@alignCast(context.?)));
    ctx.call_count += 2;
    return c.hermes_value_create_string(runtime, "test", 4);
}

// HostObject getter for tests
export fn testHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(host_object_builder.HostFunction).initComptime(.{
        .{ "method1", testMethod1 },
        .{ "method2", testMethod2 },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(rt, prop_name, func, context);
}

// HostObject enumerator for tests
export fn testHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{ "method1", "method2" };
    const arr = c.hermes_array_create(rt, method_names.len) orelse return null;

    for (method_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// Test: HostObject can be registered and accessed
test "HostObject registration" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    // Register HostObject
    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null, // No setter
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Verify it's accessible in JavaScript
    const js_code = "typeof testObj";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_string(result));

    // Check it's an object type
    var len: usize = 0;
    const type_str = c.hermes_value_get_string(runtime, result, &len);
    try testing.expectEqualStrings("object", type_str[0..len]);
}

// Test: HostObject properties return functions
test "HostObject property access returns function" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Access property and verify it's a function
    const js_code = "typeof testObj.method1";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_string(result));

    var len: usize = 0;
    const type_str = c.hermes_value_get_string(runtime, result, &len);
    try testing.expectEqualStrings("function", type_str[0..len]);
}

// Test: HostObject methods can be called
test "HostObject method invocation" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Call method1 and verify return value
    const js_code = "testObj.method1()";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_number(result));

    const num = c.hermes_value_get_number(result);
    try testing.expectEqual(@as(f64, 42.0), num);

    // Verify context was updated
    try testing.expectEqual(@as(usize, 1), ctx.call_count);
}

// Test: Multiple HostObject methods work
test "HostObject multiple methods" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Call method1
    {
        const js_code = "testObj.method1()";
        const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
        defer if (result) |r| c.hermes_value_destroy(r);
        try testing.expectEqual(@as(usize, 1), ctx.call_count);
    }

    // Call method2
    {
        const js_code = "testObj.method2()";
        const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
        defer if (result) |r| c.hermes_value_destroy(r);

        try testing.expect(result != null);
        try testing.expect(c.hermes_value_is_string(result));

        var len: usize = 0;
        const str = c.hermes_value_get_string(runtime, result, &len);
        try testing.expectEqualStrings("test", str[0..len]);

        // Verify call_count incremented by 2
        try testing.expectEqual(@as(usize, 3), ctx.call_count); // 1 + 2
    }
}

// Test: Object.keys() works with HostObject
test "HostObject property enumeration" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Get property names via Object.keys()
    const js_code = "Object.keys(testObj).join(',')";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_string(result));

    var len: usize = 0;
    const str = c.hermes_value_get_string(runtime, result, &len);

    // Verify both methods are enumerated
    try testing.expect(std.mem.indexOf(u8, str[0..len], "method1") != null);
    try testing.expect(std.mem.indexOf(u8, str[0..len], "method2") != null);
}

// Test: Invalid property access returns undefined
test "HostObject invalid property" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Access non-existent property
    const js_code = "testObj.nonExistent";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_undefined(result));
}

// Test: Multiple HostObjects can coexist
test "Multiple HostObjects" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    // Register two HostObjects
    c.hermes_register_host_object(
        runtime,
        "obj1",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx1),
    );

    c.hermes_register_host_object(
        runtime,
        "obj2",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx2),
    );

    // Call methods on both objects
    {
        const js_code = "obj1.method1()";
        const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
        defer if (result) |r| c.hermes_value_destroy(r);
        try testing.expectEqual(@as(usize, 1), ctx1.call_count);
        try testing.expectEqual(@as(usize, 0), ctx2.call_count);
    }

    {
        const js_code = "obj2.method2()";
        const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
        defer if (result) |r| c.hermes_value_destroy(r);
        try testing.expectEqual(@as(usize, 1), ctx1.call_count);
        try testing.expectEqual(@as(usize, 2), ctx2.call_count);
    }

    // Verify both objects exist
    {
        const js_code = "typeof obj1 === 'object' && typeof obj2 === 'object'";
        const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
        defer if (result) |r| c.hermes_value_destroy(r);
        try testing.expect(c.hermes_value_is_boolean(result));
        try testing.expect(c.hermes_value_get_boolean(result));
    }
}

// Test: HostObject method chaining works
test "HostObject method chaining" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Call multiple methods in sequence
    const js_code =
        \\testObj.method1();
        \\testObj.method2();
        \\testObj.method1();
    ;
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    // Verify all calls executed: 1 + 2 + 1 = 4
    try testing.expectEqual(@as(usize, 4), ctx.call_count);
}

// Test: HostObject survives GC cycles
test "HostObject GC stability" {
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var ctx = TestContext{};

    c.hermes_register_host_object(
        runtime,
        "testObj",
        testHostObjectGet,
        null,
        testHostObjectEnumerator,
        @ptrCast(&ctx),
    );

    // Create many temporary objects to trigger GC
    const js_code =
        \\for (let i = 0; i < 1000; i++) {
        \\  const temp = { data: new Array(100).fill(i) };
        \\}
        \\testObj.method1();
    ;
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    // Verify HostObject still works after GC pressure
    try testing.expectEqual(@as(usize, 1), ctx.call_count);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_number(result));
    try testing.expectEqual(@as(f64, 42.0), c.hermes_value_get_number(result));
}
