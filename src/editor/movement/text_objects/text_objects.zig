const std = @import("std");
const Buffer = @import("../../buffer/buffer.zig").Buffer;
const Cursor = @import("../../buffer/buffer.zig").Cursor;
const Range = @import("../../buffer/edit.zig").Range;

/// Text object types (the thing after i/a)
pub const TextObjectType = enum {
    word, // w
    WORD, // W (includes punctuation)
    bracket, // [ ]
    brace, // { }
    paren, // ( )
    angle, // < >
    quote_double, // "
    quote_single, // '
    quote_back, // `
    tag, // t (HTML/XML tags)

    pub fn fromChar(c: u8) ?TextObjectType {
        return switch (c) {
            'w' => .word,
            'W' => .WORD,
            '[', ']' => .bracket,
            '{', '}' => .brace,
            '(', ')' => .paren,
            '<', '>' => .angle,
            '"' => .quote_double,
            '\'' => .quote_single,
            '`' => .quote_back,
            't' => .tag,
            else => null,
        };
    }
};

/// Modifier for text objects (i = inner, a = around/all)
pub const TextObjectModifier = enum {
    inner, // i - excludes delimiters/whitespace
    around, // a - includes delimiters/whitespace

    pub fn fromChar(c: u8) ?TextObjectModifier {
        return switch (c) {
            'i' => .inner,
            'a' => .around,
            else => null,
        };
    }
};

/// Find the range for a text object at the cursor position
pub fn findTextObject(
    buffer: *const Buffer,
    object_type: TextObjectType,
    modifier: TextObjectModifier,
) ?Range {
    return switch (object_type) {
        .word => findWord(buffer, modifier),
        .WORD => findWORD(buffer, modifier),
        .bracket => findPair(buffer, '[', ']', modifier),
        .brace => findPair(buffer, '{', '}', modifier),
        .paren => findPair(buffer, '(', ')', modifier),
        .angle => findPair(buffer, '<', '>', modifier),
        .quote_double => findQuote(buffer, '"', modifier),
        .quote_single => findQuote(buffer, '\'', modifier),
        .quote_back => findQuote(buffer, '`', modifier),
        .tag => findTag(buffer, modifier),
    };
}

/// Find word boundaries (vim 'word': letters, digits, underscore)
fn findWord(buffer: *const Buffer, modifier: TextObjectModifier) ?Range {
    const line = buffer.getLine(buffer.cursor.row) orelse return null;
    // getLine returns cached/borrowed memory - do NOT free
    const cursor_col = buffer.cursor.col;

    if (cursor_col >= line.len) return null;

    // Check if we're on a word character
    const is_on_word = isWordChar(line[cursor_col]);

    var start = cursor_col;
    var end = cursor_col;

    if (is_on_word) {
        // Find word boundaries
        // Move start backward to beginning of word
        while (start > 0 and isWordChar(line[start - 1])) {
            start -= 1;
        }

        // Move end forward to end of word
        while (end < line.len and isWordChar(line[end])) {
            end += 1;
        }

        // For 'aw', include trailing whitespace
        if (modifier == .around) {
            while (end < line.len and isWhitespace(line[end]) and line[end] != '\n') {
                end += 1;
            }
            // If no trailing whitespace, try leading whitespace
            if (end == cursor_col + 1 or !isWhitespace(line[end - 1])) {
                const orig_start = start;
                while (start > 0 and isWhitespace(line[start - 1])) {
                    start -= 1;
                }
                // If we didn't find leading whitespace, restore original start
                if (start == orig_start and start > 0) {
                    start = orig_start;
                }
            }
        }
    } else if (isWhitespace(line[cursor_col])) {
        // On whitespace - select whitespace block
        while (start > 0 and isWhitespace(line[start - 1]) and line[start - 1] != '\n') {
            start -= 1;
        }
        while (end < line.len and isWhitespace(line[end]) and line[end] != '\n') {
            end += 1;
        }
    } else {
        // On non-word, non-whitespace (punctuation)
        return null;
    }

    const line_start = buffer.content.byteOfLine(buffer.cursor.row);
    return Range{
        .start = line_start + start,
        .end = line_start + end,
    };
}

/// Find WORD boundaries (vim 'WORD': everything except whitespace)
fn findWORD(buffer: *const Buffer, modifier: TextObjectModifier) ?Range {
    const line = buffer.getLine(buffer.cursor.row) orelse return null;
    // getLine returns cached/borrowed memory - do NOT free
    const cursor_col = buffer.cursor.col;

    if (cursor_col >= line.len) return null;

    var start = cursor_col;
    var end = cursor_col;

    if (!isWhitespace(line[cursor_col])) {
        // Move start backward
        while (start > 0 and !isWhitespace(line[start - 1])) {
            start -= 1;
        }

        // Move end forward
        while (end < line.len and !isWhitespace(line[end])) {
            end += 1;
        }

        // For 'aw', include trailing whitespace
        if (modifier == .around) {
            while (end < line.len and isWhitespace(line[end]) and line[end] != '\n') {
                end += 1;
            }
        }
    } else {
        // On whitespace
        while (start > 0 and isWhitespace(line[start - 1]) and line[start - 1] != '\n') {
            start -= 1;
        }
        while (end < line.len and isWhitespace(line[end]) and line[end] != '\n') {
            end += 1;
        }
    }

    const line_start = buffer.content.byteOfLine(buffer.cursor.row);
    return Range{
        .start = line_start + start,
        .end = line_start + end,
    };
}

/// Find matching pair of delimiters (brackets, braces, parens, etc.)
fn findPair(buffer: *const Buffer, open: u8, close: u8, modifier: TextObjectModifier) ?Range {
    // Search for the opening and closing delimiter
    // This is a simplified implementation - Vim's actual behavior is more complex

    var start_offset: ?usize = null;
    var end_offset: ?usize = null;

    // First, try to find the pair on the current line
    const row = buffer.cursor.row;
    const line = buffer.getLine(row) orelse return null;
    // getLine returns cached/borrowed memory - do NOT free
    const line_start = buffer.content.byteOfLine(row);

    // Search backward from cursor for open delimiter
    var col: isize = @intCast(buffer.cursor.col);
    var open_col: usize = 0;
    while (col >= 0) : (col -= 1) {
        const c = line[@intCast(col)];
        if (c == open) {
            open_col = @intCast(col);
            start_offset = line_start + open_col;
            break;
        }
    }

    if (start_offset == null) return null;

    // Now search forward from the opening delimiter for matching close delimiter
    var depth: i32 = 1;
    col = @as(isize, @intCast(open_col)) + 1;
    while (col < line.len) : (col += 1) {
        const c = line[@intCast(col)];
        if (c == open) {
            depth += 1;
        } else if (c == close) {
            depth -= 1;
            if (depth == 0) {
                end_offset = line_start + @as(usize, @intCast(col));
                break;
            }
        }
    }

    if (end_offset == null) return null;

    const start = start_offset.?;
    const end = end_offset.?;

    // For 'i' (inner), exclude the delimiters
    // For 'a' (around), include the delimiters
    if (modifier == .inner) {
        return Range{
            .start = start + 1,
            .end = end,
        };
    } else {
        return Range{
            .start = start,
            .end = end + 1,
        };
    }
}

/// Find matching quotes
fn findQuote(buffer: *const Buffer, quote: u8, modifier: TextObjectModifier) ?Range {
    const line = buffer.getLine(buffer.cursor.row) orelse return null;
    // getLine returns cached/borrowed memory - do NOT free
    const line_start = buffer.content.byteOfLine(buffer.cursor.row);

    var start_offset: ?usize = null;
    var end_offset: ?usize = null;

    // Search backward from cursor for opening quote
    var col: isize = @intCast(buffer.cursor.col);
    while (col >= 0) : (col -= 1) {
        if (line[@intCast(col)] == quote) {
            start_offset = line_start + @as(usize, @intCast(col));
            break;
        }
    }

    if (start_offset == null) return null;

    // Search forward for closing quote
    col = @as(isize, @intCast(buffer.cursor.col)) + 1;
    while (col < line.len) : (col += 1) {
        const c = line[@intCast(col)];
        // Skip escaped quotes
        if (col > 0 and line[@intCast(col - 1)] == '\\') continue;

        if (c == quote) {
            end_offset = line_start + @as(usize, @intCast(col));
            break;
        }
    }

    if (end_offset == null) return null;

    const start = start_offset.?;
    const end = end_offset.?;

    if (modifier == .inner) {
        return Range{
            .start = start + 1,
            .end = end,
        };
    } else {
        return Range{
            .start = start,
            .end = end + 1,
        };
    }
}

/// Find HTML/XML tag (simplified implementation)
fn findTag(buffer: *const Buffer, modifier: TextObjectModifier) ?Range {
    _ = buffer;
    _ = modifier;
    // TODO: Implement tag matching
    // This is complex and would require parsing HTML/XML
    return null;
}

/// Helper: Check if character is a word constituent
fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '_';
}

/// Helper: Check if character is whitespace
fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t';
}

// Tests
test "TextObject: inner word" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "hello world\n");
    buffer.cursor = .{ .row = 0, .col = 2 }; // Cursor on 'l' in "hello"

    const range = findWord(&buffer, .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("hello", text);
}

test "TextObject: around word with trailing space" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "hello world\n");
    buffer.cursor = .{ .row = 0, .col = 2 }; // Cursor on 'l' in "hello"

    const range = findWord(&buffer, .around).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("hello ", text);
}

test "TextObject: inner bracket" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "foo[bar]baz\n");
    buffer.cursor = .{ .row = 0, .col = 5 }; // Cursor on 'a' in "bar"

    const range = findPair(&buffer, '[', ']', .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("bar", text);
}

test "TextObject: around bracket" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "foo[bar]baz\n");
    buffer.cursor = .{ .row = 0, .col = 5 }; // Cursor on 'a' in "bar"

    const range = findPair(&buffer, '[', ']', .around).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("[bar]", text);
}

test "TextObject: inner paren with cursor at colon - bug fix" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    // Test case from bug: (line 293: src/core/editor.zig:293)
    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "(line 293: src/core/editor.zig:293)\n");
    buffer.cursor = .{ .row = 0, .col = 10 }; // Cursor on first ':'

    const range = findPair(&buffer, '(', ')', .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("line 293: src/core/editor.zig:293", text);
}

test "TextObject: inner paren at different cursor positions" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "simple (content) test\n");

    // Test at start of content
    buffer.cursor = .{ .row = 0, .col = 8 }; // 'c' in content
    {
        const range = findPair(&buffer, '(', ')', .inner).?;
        const text = try range.getText(&buffer);
        defer allocator.free(text);
        try std.testing.expectEqualStrings("content", text);
    }

    // Test at middle of content
    buffer.cursor = .{ .row = 0, .col = 11 }; // 't' in content
    {
        const range = findPair(&buffer, '(', ')', .inner).?;
        const text = try range.getText(&buffer);
        defer allocator.free(text);
        try std.testing.expectEqualStrings("content", text);
    }

    // Test at end of content
    buffer.cursor = .{ .row = 0, .col = 14 }; // 't' at end of content
    {
        const range = findPair(&buffer, '(', ')', .inner).?;
        const text = try range.getText(&buffer);
        defer allocator.free(text);
        try std.testing.expectEqualStrings("content", text);
    }
}

test "TextObject: nested parens - innermost pair" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "nested (outer (inner) outer) test\n");

    // Cursor inside 'inner' should find innermost pair
    buffer.cursor = .{ .row = 0, .col = 17 }; // 'i' in "inner"
    const range = findPair(&buffer, '(', ')', .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("inner", text);
}

test "TextObject: nested parens - outer pair" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "nested (outer (inner) outer) test\n");

    // Cursor in first 'outer' should find outer pair
    buffer.cursor = .{ .row = 0, .col = 9 }; // 'o' in first "outer"
    const range = findPair(&buffer, '(', ')', .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("outer (inner) outer", text);
}

test "TextObject: around paren includes delimiters" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "test (content) here\n");
    buffer.cursor = .{ .row = 0, .col = 8 }; // inside parens

    const range = findPair(&buffer, '(', ')', .around).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("(content)", text);
}

test "TextObject: braces work correctly" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "test {inside} end\n");
    buffer.cursor = .{ .row = 0, .col = 7 }; // 'i' in "inside"

    const range = findPair(&buffer, '{', '}', .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("inside", text);
}

test "TextObject: quotes work correctly" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    buffer.content.deinit();
    buffer.content = try @import("../../buffer/rope.zig").Rope.fromString(allocator, "quote \"text\" more\n");
    buffer.cursor = .{ .row = 0, .col = 9 }; // 't' in "text"

    const range = findQuote(&buffer, '"', .inner).?;
    const text = try range.getText(&buffer);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("text", text);
}
