/// Tests for Editor state management
/// Verifies js_state_dirty flag mechanism used by JavaScript APIs
const std = @import("std");
const testing = std.testing;
const Editor = @import("editor.zig").Editor;

test "Editor: js_state_dirty flag initializes to false" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try testing.expect(!editor.js_state_dirty);
}

test "Editor: js_state_dirty flag can be set" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Initially false
    try testing.expect(!editor.js_state_dirty);

    // Set to true
    editor.js_state_dirty = true;
    try testing.expect(editor.js_state_dirty);

    // Reset to false
    editor.js_state_dirty = false;
    try testing.expect(!editor.js_state_dirty);
}

test "Editor: js_state_dirty flag persists across operations" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Set flag
    editor.js_state_dirty = true;

    // Perform some buffer operations (flag should remain true)
    try editor.buffer.content.appendSlice(allocator, "test");
    try testing.expect(editor.js_state_dirty);

    // Reset flag
    editor.js_state_dirty = false;
    try testing.expect(!editor.js_state_dirty);
}
