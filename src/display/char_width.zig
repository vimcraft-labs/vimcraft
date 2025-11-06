const std = @import("std");
const cellwidth = @import("cellwidth.zig");

/// Get the display width of a Unicode codepoint for GRID RENDERING
/// Returns:
///   1 for normal characters (ASCII, most Unicode)
///   2 for wide characters (CJK, emoji)
///   0 for zero-width characters (combining marks, variation selectors)
///
/// This uses the configurable cellwidth system which respects terminal-specific
/// overrides and user configuration
pub fn codepointWidth(codepoint: u21) u8 {
    return cellwidth.getWidth(codepoint);
}

/// Calculate the display width of a UTF-8 string
/// This is NOT the same as byte length or character count
pub fn stringWidth(str: []const u8) usize {
    return cellwidth.getStringWidth(str);
}

/// Convert byte position to display column position
/// This is needed for cursor positioning with emoji/CJK
pub fn byteToDisplayColumn(str: []const u8, byte_pos: usize) usize {
    var display_col: usize = 0;
    var i: usize = 0;

    while (i < byte_pos and i < str.len) {
        const char_len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + char_len > str.len) break;

        const codepoint = std.unicode.utf8Decode(str[i..][0..char_len]) catch ' ';
        display_col += codepointWidth(codepoint);

        i += char_len;
    }

    return display_col;
}

/// Convert display column to byte position
/// Returns the byte position of the character at the given display column
pub fn displayColumnToByte(str: []const u8, target_col: usize) usize {
    var display_col: usize = 0;
    var i: usize = 0;

    while (i < str.len) {
        if (display_col >= target_col) return i;

        const char_len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + char_len > str.len) break;

        const codepoint = std.unicode.utf8Decode(str[i..][0..char_len]) catch ' ';
        display_col += codepointWidth(codepoint);

        i += char_len;
    }

    return i;
}

// Tests
test "char_width: ASCII characters" {
    // Initialize cellwidth system for tests
    try cellwidth.initGlobal(std.testing.allocator);
    defer cellwidth.deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 1), codepointWidth('a'));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('Z'));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth(' '));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('0'));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('#'));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('@'));
}

test "char_width: emoji" {
    try cellwidth.initGlobal(std.testing.allocator);
    defer cellwidth.deinitGlobal(std.testing.allocator);

    // Modern emoji should be width 2 (configured by cellwidth)
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F3AF)); // 🎯
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F680)); // 🚀
}

test "char_width: CJK (double-width)" {
    try cellwidth.initGlobal(std.testing.allocator);
    defer cellwidth.deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x4E2D)); // 中
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x6587)); // 文
}

test "char_width: variation selectors (zero-width)" {
    try cellwidth.initGlobal(std.testing.allocator);
    defer cellwidth.deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0xFE0F)); // VS-16
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0xFE00)); // VS-1
}

test "char_width: string width calculation" {
    try cellwidth.initGlobal(std.testing.allocator);
    defer cellwidth.deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), stringWidth("hello"));
    // Emoji with variation selector = 2+0 = width 2
    try std.testing.expectEqual(@as(usize, 2), stringWidth("🖥️")); // Desktop with VS-16
}

test "char_width: byte to display conversion" {
    try cellwidth.initGlobal(std.testing.allocator);
    defer cellwidth.deinitGlobal(std.testing.allocator);

    const text = "🎯 hi"; // byte 0-3: 🎯, byte 4: space, byte 5: h, byte 6: i
    try std.testing.expectEqual(@as(usize, 0), byteToDisplayColumn(text, 0));
    // After emoji (width 2)
    try std.testing.expectEqual(@as(usize, 2), byteToDisplayColumn(text, 4));
}