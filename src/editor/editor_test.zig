/// Tests for Editor buffer management and state
/// Comprehensive regression tests for multi-buffer architecture (Phase 3)
const std = @import("std");
const testing = std.testing;
const Editor = @import("editor.zig").Editor;
const BufferId = @import("editor.zig").BufferId;

// ============================================================================
// js_state_dirty Flag Tests
// ============================================================================

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

    // Perform buffer operation (flag should remain true)
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator, "test");
    try testing.expect(editor.js_state_dirty);

    // Reset flag
    editor.js_state_dirty = false;
    try testing.expect(!editor.js_state_dirty);
}

// ============================================================================
// Buffer Management Core Tests
// ============================================================================

test "Editor: initial buffer is created on init" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Should have exactly 1 buffer (unnamed initial buffer)
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());

    // Should have current buffer set
    try testing.expect(editor.current_buffer_id != null);

    // getCurrentBuffer should return non-null
    const buf = editor.getCurrentBuffer();
    try testing.expect(buf != null);
}

test "Editor: getCurrentBuffer returns active buffer" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;

    // Should be the initial buffer (ID 1)
    try testing.expect(editor.current_buffer_id.?.id == 1);

    // Buffer content should be accessible
    try testing.expectEqual(@as(usize, 0), buf.content.len());
}

test "Editor: createBuffer generates unique IDs" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();
    const id3 = try editor.createBuffer();

    // IDs should be unique and auto-incrementing
    try testing.expectEqual(@as(u64, 1), id1.id);
    try testing.expectEqual(@as(u64, 2), id2.id);
    try testing.expectEqual(@as(u64, 3), id3.id);

    // Should have 3 buffers total
    try testing.expectEqual(@as(usize, 3), editor.buffers.count());
}

test "Editor: switchBuffer changes current buffer" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();

    // Initially on buffer 1
    try testing.expect(editor.current_buffer_id.?.eql(id1));

    // Switch to buffer 2
    try editor.switchBuffer(id2);
    try testing.expect(editor.current_buffer_id.?.eql(id2));

    // getCurrentBuffer should return buffer 2
    _ = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
}

test "Editor: switchBuffer to invalid ID returns error" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const invalid_id = BufferId{ .id = 999 };

    // Should return error
    try testing.expectError(error.BufferNotFound, editor.switchBuffer(invalid_id));

    // Current buffer should remain unchanged
    try testing.expectEqual(@as(u64, 1), editor.current_buffer_id.?.id);
}

test "Editor: deleteBuffer removes buffer from HashMap" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id2 = try editor.createBuffer();
    try testing.expectEqual(@as(usize, 2), editor.buffers.count());

    // Delete buffer 2 (not current)
    try editor.deleteBuffer(id2, false);

    // Should have 1 buffer left
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());

    // Should still be on buffer 1
    try testing.expectEqual(@as(u64, 1), editor.current_buffer_id.?.id);
}

test "Editor: deleteBuffer on current buffer switches to another" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();

    // Switch to buffer 2
    try editor.switchBuffer(id2);
    try testing.expect(editor.current_buffer_id.?.eql(id2));

    // Delete current buffer (2)
    try editor.deleteBuffer(id2, false);

    // Should auto-switch to buffer 1
    try testing.expect(editor.current_buffer_id.?.eql(id1));
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());
}

test "Editor: deleteBuffer on modified buffer without force fails" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.modified = true;

    // Should fail without force
    try testing.expectError(error.BufferModified, editor.deleteBuffer(editor.current_buffer_id.?, false));

    // Buffer should still exist
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());
}

test "Editor: deleteBuffer on modified buffer with force succeeds" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id2 = try editor.createBuffer();
    try editor.switchBuffer(id2);

    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.modified = true;

    // Should succeed with force
    try editor.deleteBuffer(id2, true);

    // Should have 1 buffer left
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());
}

test "Editor: deleting last buffer creates new empty buffer" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;

    // Delete the only buffer (force to bypass modified check)
    try editor.deleteBuffer(id1, true);

    // Should create a new buffer automatically
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());

    // Should have a current buffer
    try testing.expect(editor.current_buffer_id != null);

    // New buffer should have new ID (2)
    try testing.expectEqual(@as(u64, 2), editor.current_buffer_id.?.id);
}

// ============================================================================
// Buffer Navigation Tests (:bn, :bp, :b N)
// ============================================================================

test "Editor: nextBuffer cycles through buffers" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();
    const id3 = try editor.createBuffer();

    // Start on buffer 1
    try testing.expect(editor.current_buffer_id.?.eql(id1));

    // :bn -> buffer 2
    editor.nextBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id2));

    // :bn -> buffer 3
    editor.nextBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id3));

    // :bn -> wraps to buffer 1
    editor.nextBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id1));
}

test "Editor: prevBuffer cycles backwards through buffers" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();
    const id3 = try editor.createBuffer();

    // Start on buffer 1
    try testing.expect(editor.current_buffer_id.?.eql(id1));

    // :bp -> wraps to buffer 3
    editor.prevBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id3));

    // :bp -> buffer 2
    editor.prevBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id2));

    // :bp -> buffer 1
    editor.prevBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id1));
}

test "Editor: nextBuffer with single buffer stays on same buffer" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;

    // :bn with only 1 buffer -> stays on buffer 1
    editor.nextBuffer();
    try testing.expect(editor.current_buffer_id.?.eql(id1));
}

// ============================================================================
// Buffer Operations Tests (delete others, load file)
// ============================================================================

test "Editor: deleteOtherBuffers removes all except current" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    _ = try editor.createBuffer(); // id2
    _ = try editor.createBuffer(); // id3

    // Switch to buffer 1
    try editor.switchBuffer(id1);

    try testing.expectEqual(@as(usize, 3), editor.buffers.count());

    // Delete all others (:bo)
    const deleted = try editor.deleteOtherBuffers(false);
    try testing.expectEqual(@as(usize, 2), deleted);

    // Should have only buffer 1 left
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());
    try testing.expect(editor.current_buffer_id.?.eql(id1));
}

test "Editor: deleteOtherBuffers with modified buffers without force fails" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();

    // Modify buffer 2
    try editor.switchBuffer(id2);
    const buf2 = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf2.modified = true;

    // Switch back to buffer 1
    try editor.switchBuffer(id1);

    // Should fail without force
    try testing.expectError(error.BufferModified, editor.deleteOtherBuffers(false));

    // All buffers should still exist
    try testing.expectEqual(@as(usize, 2), editor.buffers.count());
}

test "Editor: deleteOtherBuffers with modified buffers with force succeeds" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const id1 = editor.current_buffer_id.?;
    const id2 = try editor.createBuffer();

    // Modify buffer 2
    try editor.switchBuffer(id2);
    const buf2 = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf2.modified = true;

    // Switch back to buffer 1
    try editor.switchBuffer(id1);

    // Should succeed with force
    const deleted = try editor.deleteOtherBuffers(true);
    try testing.expectEqual(@as(usize, 1), deleted);

    // Only buffer 1 should remain
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());
}

test "Editor: deleteOtherBuffers on last buffer returns 0" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Only 1 buffer exists
    const deleted = try editor.deleteOtherBuffers(false);
    try testing.expectEqual(@as(usize, 0), deleted);

    // Buffer should still exist
    try testing.expectEqual(@as(usize, 1), editor.buffers.count());
}

// ============================================================================
// Edge Cases and Error Handling
// ============================================================================

test "Editor: getCurrentBuffer with no buffers returns null" {
    // This test verifies defensive programming
    // (In practice, Editor always has at least 1 buffer after init)
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Manually clear current_buffer_id to simulate edge case
    editor.current_buffer_id = null;

    const buf = editor.getCurrentBuffer();
    try testing.expect(buf == null);
}

test "Editor: BufferId equality works correctly" {
    const id1 = BufferId{ .id = 1 };
    const id2 = BufferId{ .id = 1 };
    const id3 = BufferId{ .id = 2 };

    try testing.expect(id1.eql(id2));
    try testing.expect(!id1.eql(id3));
    try testing.expect(!id2.eql(id3));
}

test "Editor: buffer content is isolated between buffers" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Write to buffer 1
    const buf1 = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf1.content.deinit();
    buf1.content = try @import("buffer/rope.zig").Rope.fromString(allocator, "buffer 1");

    // Create and switch to buffer 2
    const id2 = try editor.createBuffer();
    try editor.switchBuffer(id2);

    const buf2 = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf2.content.deinit();
    buf2.content = try @import("buffer/rope.zig").Rope.fromString(allocator, "buffer 2");

    // Verify buffer 2 has its content
    const content2 = try buf2.content.toString();
    defer allocator.free(content2);
    try testing.expectEqualStrings("buffer 2", content2);

    // Switch back to buffer 1
    const id1 = BufferId{ .id = 1 };
    try editor.switchBuffer(id1);

    const buf1_again = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    const content1 = try buf1_again.content.toString();
    defer allocator.free(content1);

    // Buffer 1 should still have its original content
    try testing.expectEqualStrings("buffer 1", content1);
}

test "Editor: next_buffer_id increments correctly after deletions" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Create buffers 1, 2, 3
    _ = try editor.createBuffer(); // 2
    const id3 = try editor.createBuffer(); // 3

    try testing.expectEqual(@as(u64, 4), editor.next_buffer_id);

    // Delete buffer 3
    try editor.deleteBuffer(id3, false);

    // Next buffer should still be 4 (IDs don't reuse)
    try testing.expectEqual(@as(u64, 4), editor.next_buffer_id);

    const id4 = try editor.createBuffer();
    try testing.expectEqual(@as(u64, 4), id4.id);
    try testing.expectEqual(@as(u64, 5), editor.next_buffer_id);
}

// ============================================================================
// Working Directory Tests (:cd, :pwd)
// ============================================================================

test "Editor: cwd is initialized on init" {
    const allocator = testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Should have valid cwd
    try testing.expect(editor.cwd.len > 0);
}

// ============================================================================
// Substitute Command Parser Tests
// ============================================================================

test "parseSubstituteCommand: basic pattern and replacement" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s/foo/bar/");
    try testing.expect(result != null);
    try testing.expectEqualStrings("foo", result.?.pattern);
    try testing.expectEqualStrings("bar", result.?.replacement);
    try testing.expect(!result.?.flags.global);
    try testing.expect(!result.?.flags.ignore_case);
}

test "parseSubstituteCommand: with g flag" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s/foo/bar/g");
    try testing.expect(result != null);
    try testing.expect(result.?.flags.global);
}

test "parseSubstituteCommand: with multiple flags" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s/foo/bar/gi");
    try testing.expect(result != null);
    try testing.expect(result.?.flags.global);
    try testing.expect(result.?.flags.ignore_case);
}

test "parseSubstituteCommand: empty replacement" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s/foo//");
    try testing.expect(result != null);
    try testing.expectEqualStrings("foo", result.?.pattern);
    try testing.expectEqualStrings("", result.?.replacement);
}

test "parseSubstituteCommand: empty pattern" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s//bar/");
    try testing.expect(result != null);
    try testing.expectEqualStrings("", result.?.pattern);
    try testing.expectEqualStrings("bar", result.?.replacement);
}

test "parseSubstituteCommand: alternate delimiter pipe" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s|foo|bar|g");
    try testing.expect(result != null);
    try testing.expectEqualStrings("foo", result.?.pattern);
    try testing.expectEqualStrings("bar", result.?.replacement);
    try testing.expect(result.?.flags.global);
}

test "parseSubstituteCommand: alternate delimiter hash" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s#path#replacement#");
    try testing.expect(result != null);
    try testing.expectEqualStrings("path", result.?.pattern);
    try testing.expectEqualStrings("replacement", result.?.replacement);
}

test "parseSubstituteCommand: escaped delimiter in pattern" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s/foo\\/bar/baz/");
    try testing.expect(result != null);
    try testing.expectEqualStrings("foo\\/bar", result.?.pattern);
}

test "parseSubstituteCommand: invalid - not starting with s" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("x/foo/bar/");
    try testing.expect(result == null);
}

test "parseSubstituteCommand: all flags" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = editor.parseSubstituteCommand("s/foo/bar/gien");
    try testing.expect(result != null);
    try testing.expect(result.?.flags.global);
    try testing.expect(result.?.flags.ignore_case);
    try testing.expect(result.?.flags.no_error);
    try testing.expect(result.?.flags.count_only);
}

// ============================================================================
// findMatchesOnLine Tests
// ============================================================================

test "findMatchesOnLine: single match" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("hello world", "world", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), matches.items.len);
    try testing.expectEqual(@as(usize, 6), matches.items[0].start);
    try testing.expectEqual(@as(usize, 11), matches.items[0].end);
}

test "findMatchesOnLine: multiple matches" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("foo bar foo baz foo", "foo", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), matches.items.len);
    try testing.expectEqual(@as(usize, 0), matches.items[0].start);
    try testing.expectEqual(@as(usize, 8), matches.items[1].start);
    try testing.expectEqual(@as(usize, 16), matches.items[2].start);
}

test "findMatchesOnLine: no match" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("hello world", "xyz", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), matches.items.len);
}

test "findMatchesOnLine: case sensitive" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("Hello HELLO hello", "Hello", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), matches.items.len);
    try testing.expectEqual(@as(usize, 0), matches.items[0].start);
}

test "findMatchesOnLine: case insensitive" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("Hello HELLO hello", "hello", true);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), matches.items.len);
}

test "findMatchesOnLine: overlapping patterns (non-overlapping result)" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // "aaa" contains "aa" at positions 0 and 1, but non-overlapping gives only 1
    var matches = try editor.findMatchesOnLine("aaa", "aa", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), matches.items.len);
    try testing.expectEqual(@as(usize, 0), matches.items[0].start);
}

test "findMatchesOnLine: pattern at end of line" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("hello world", "world", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), matches.items.len);
    try testing.expectEqual(@as(usize, 6), matches.items[0].start);
    try testing.expectEqual(@as(usize, 11), matches.items[0].end);
}

test "findMatchesOnLine: empty line" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    var matches = try editor.findMatchesOnLine("", "foo", false);
    defer matches.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), matches.items.len);
}

// ============================================================================
// unescapeSubstitute Tests
// ============================================================================

test "unescapeSubstitute: no escapes" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("hello", '/');
    defer allocator.free(result);

    try testing.expectEqualStrings("hello", result);
}

test "unescapeSubstitute: escaped delimiter" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("foo\\/bar", '/');
    defer allocator.free(result);

    try testing.expectEqualStrings("foo/bar", result);
}

test "unescapeSubstitute: escaped backslash" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("foo\\\\bar", '/');
    defer allocator.free(result);

    try testing.expectEqualStrings("foo\\bar", result);
}

test "unescapeSubstitute: newline escape" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("foo\\nbar", '/');
    defer allocator.free(result);

    try testing.expectEqualStrings("foo\nbar", result);
}

test "unescapeSubstitute: tab escape" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("foo\\tbar", '/');
    defer allocator.free(result);

    try testing.expectEqualStrings("foo\tbar", result);
}

test "unescapeSubstitute: multiple escapes" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("a\\/b\\nc\\\\d", '/');
    defer allocator.free(result);

    try testing.expectEqualStrings("a/b\nc\\d", result);
}

test "unescapeSubstitute: alternate delimiter" {
    const allocator = testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    const result = try editor.unescapeSubstitute("foo\\|bar", '|');
    defer allocator.free(result);

    try testing.expectEqualStrings("foo|bar", result);
}
