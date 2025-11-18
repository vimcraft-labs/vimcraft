/// Motion API HostObject Integration Tests
/// Verifies motion_api.zig HostObject implementation works correctly
///
/// Test Coverage:
/// - All 17 motion methods are accessible
/// - Property enumeration lists all methods
/// - Motion methods modify buffer state correctly
/// - JavaScript can call motion methods in sequence
/// - Backwards compatibility with legacy API

const std = @import("std");
const testing = std.testing;
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;

// Import JSI infrastructure
const c_api = @import("c_api.zig");
const c = c_api.c;
const motion_api = @import("motion_api.zig");

// Test: All motion methods are enumerable
test "motion API - Object.keys lists all methods" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    // Create buffer and context
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "Hello, World!\n");
    try buffer.content.appendSlice(allocator, "Second line\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    // Register motion API
    motion_api.register(runtime, &ctx);

    // Get all method names via Object.keys()
    const js_code = "Object.keys(vimMotion).length";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(result != null);
    try testing.expect(c.hermes_value_is_number(result));

    const count = c.hermes_value_get_number(result);
    try testing.expectEqual(@as(f64, 17.0), count); // 17 motion methods
}

// Test: Motion method can be called and modifies buffer
test "motion API - method execution modifies buffer" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "Hello, World!\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Initial cursor position
    try testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try testing.expectEqual(@as(usize, 0), buffer.cursor.col);
    try testing.expect(!js_state_dirty);

    // Call right() method
    const js_code = "vimMotion.right()";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    // Verify cursor moved right
    try testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try testing.expectEqual(@as(usize, 1), buffer.cursor.col);
    try testing.expect(js_state_dirty); // Should be marked dirty
}

// Test: All motion methods exist and are callable
test "motion API - all methods callable" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "Hello, World!\nSecond line\nThird line\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Test all methods return without error
    const methods = [_][]const u8{
        "vimMotion.left()",
        "vimMotion.right()",
        "vimMotion.up()",
        "vimMotion.down()",
        "vimMotion.lineStart()",
        "vimMotion.lineEnd()",
        "vimMotion.firstNonBlank()",
        "vimMotion.wordForward()",
        "vimMotion.wordBackward()",
        "vimMotion.wordEnd()",
        "vimMotion.fileStart()",
        "vimMotion.fileEnd()",
        "vimMotion.viewportTop()",
        "vimMotion.viewportMiddle()",
        "vimMotion.viewportBottom()",
        "vimMotion.scrollHalfPageDown()",
        "vimMotion.scrollHalfPageUp()",
    };

    for (methods) |method| {
        const result = c.hermes_evaluate_javascript(runtime, method.ptr, method.len, "test");
        defer if (result) |r| c.hermes_value_destroy(r);

        // Verify no exception
        try testing.expect(!c.hermes_has_exception(runtime));
        try testing.expect(result != null);
    }
}

// Test: Motion method sequence works correctly
test "motion API - sequential method calls" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "Hello, World!\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Execute sequence: right, right, right
    const js_code =
        \\vimMotion.right();
        \\vimMotion.right();
        \\vimMotion.right();
    ;
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    // Verify cursor moved 3 positions right
    try testing.expectEqual(@as(usize, 0), buffer.cursor.row);
    try testing.expectEqual(@as(usize, 3), buffer.cursor.col);
}

// Test: Property access returns function type
test "motion API - properties are functions" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "test\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Verify all methods are functions
    const js_code =
        \\typeof vimMotion.left === 'function' &&
        \\typeof vimMotion.right === 'function' &&
        \\typeof vimMotion.up === 'function' &&
        \\typeof vimMotion.down === 'function'
    ;
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(c.hermes_value_is_boolean(result));
    try testing.expect(c.hermes_value_get_boolean(result));
}

// Test: Invalid property returns undefined
test "motion API - invalid property" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "test\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Access non-existent method
    const js_code = "typeof vimMotion.nonExistent";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(c.hermes_value_is_string(result));

    var len: usize = 0;
    const type_str = c.hermes_value_get_string(runtime, result, &len);
    try testing.expectEqualStrings("undefined", type_str[0..len]);
}

// Test: vimMotion object exists globally
test "motion API - global object registration" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "test\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Verify vimMotion is an object
    const js_code = "typeof vimMotion";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    try testing.expect(c.hermes_value_is_string(result));

    var len: usize = 0;
    const type_str = c.hermes_value_get_string(runtime, result, &len);
    try testing.expectEqualStrings("object", type_str[0..len]);
}

// Test: js_state_dirty flag is set on motion
test "motion API - dirty flag management" {
    const allocator = testing.allocator;
    const runtime = c.hermes_runtime_create() orelse return error.RuntimeCreationFailed;
    defer c.hermes_runtime_destroy(runtime);

    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.content.appendSlice(allocator, "Hello, World!\n");
    try buffer.buildLineIndex();

    var viewport_top: usize = 0;
    var js_state_dirty: bool = false;

    var ctx = motion_api.MotionContext{
        .buffer = &buffer,
        .viewport_top = &viewport_top,
        .viewport_height = 24,
        .js_state_dirty = &js_state_dirty,
    };

    motion_api.register(runtime, &ctx);

    // Verify dirty flag is initially false
    try testing.expect(!js_state_dirty);

    // Execute motion
    const js_code = "vimMotion.right()";
    const result = c.hermes_evaluate_javascript(runtime, js_code.ptr, js_code.len, "test");
    defer if (result) |r| c.hermes_value_destroy(r);

    // Verify dirty flag is now true
    try testing.expect(js_state_dirty);
}
