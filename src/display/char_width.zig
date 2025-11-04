const std = @import("std");
const uucode = @import("uucode");

/// Get the display width of a Unicode codepoint using Ghostty's uucode library
/// Returns:
///   1 for normal characters (ASCII, most Unicode)
///   2 for wide characters (CJK, emoji, etc.)
///   0 for zero-width characters (combining marks, variation selectors)
///
/// Uses Unicode East Asian Width property (UAX #11) via Ghostty's battle-tested uucode implementation
pub fn codepointWidth(codepoint: u21) u8 {
    // Check if codepoint is beyond Unicode range
    if (codepoint > uucode.config.max_code_point) return 1;

    // Special handling for zero-width characters
    // These don't have reliable east_asian_width properties, so we check explicitly

    // Variation Selectors (VS1-VS16): U+FE00..U+FE0F
    if (codepoint >= 0xFE00 and codepoint <= 0xFE0F) return 0;

    // Variation Selectors Supplement (VS17-VS256): U+E0100..U+E01EF
    if (codepoint >= 0xE0100 and codepoint <= 0xE01EF) return 0;

    // Zero-width characters
    if (codepoint == 0x200B or // Zero Width Space
        codepoint == 0x200C or // Zero Width Non-Joiner
        codepoint == 0x200D or // Zero Width Joiner
        codepoint == 0xFEFF) // Zero Width No-Break Space (BOM)
        return 0;

    // Combining Diacritical Marks: U+0300..U+036F
    if (codepoint >= 0x0300 and codepoint <= 0x036F) return 0;

    // Combining Diacritical Marks Extended: U+1AB0..U+1AFF
    if (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) return 0;

    // Combining Diacritical Marks Supplement: U+1DC0..U+1DFF
    if (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) return 0;

    // Combining Half Marks: U+FE20..U+FE2F
    if (codepoint >= 0xFE20 and codepoint <= 0xFE2F) return 0;

    // Get East Asian Width property from uucode
    const east_asian_width = uucode.get(.east_asian_width, codepoint);

    // Map East Asian Width to terminal display width
    // Based on: https://www.unicode.org/reports/tr11/
    return switch (east_asian_width) {
        .fullwidth, .wide => 2,       // CJK, emoji, fullwidth forms
        .neutral, .narrow, .halfwidth => 1, // Most characters
        .ambiguous => 1,              // Context-dependent, default to 1
    };
}

/// Calculate the display width of a UTF-8 string
/// This is NOT the same as byte length or character count
pub fn stringWidth(str: []const u8) usize {
    var total_width: usize = 0;
    var i: usize = 0;

    while (i < str.len) {
        const char_len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + char_len > str.len) break;

        const codepoint = std.unicode.utf8Decode(str[i..][0..char_len]) catch ' ';
        total_width += codepointWidth(codepoint);

        i += char_len;
    }

    return total_width;
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

// Tests - verifying uucode integration works correctly
test "char_width: ASCII characters" {
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('a'));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('Z'));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth(' '));
    try std.testing.expectEqual(@as(u8, 1), codepointWidth('0'));
}

test "char_width: emoji (double-width)" {
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F3AF)); // 🎯
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F680)); // 🚀
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F4DD)); // 📝
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F3A8)); // 🎨
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x1F5A5)); // 🖥 (desktop computer)
}

test "char_width: CJK (double-width)" {
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x4E2D)); // 中
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0x6587)); // 文
}

test "char_width: Hangul (double-width)" {
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0xAC00)); // 가
    try std.testing.expectEqual(@as(u8, 2), codepointWidth(0xD7A3)); // 힣
}

test "char_width: variation selectors (zero-width)" {
    // Variation selectors should always return width 0
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0xFE0F)); // VS-16
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0xFE00)); // VS-1
    try std.testing.expectEqual(@as(u8, 0), codepointWidth(0xE0100)); // VS-17
}

test "char_width: string width calculation" {
    try std.testing.expectEqual(@as(usize, 5), stringWidth("hello"));
    // Emoji without variation selector = width 2
    try std.testing.expectEqual(@as(usize, 2), stringWidth("🎯"));
    // Emoji with variation selector = 2+0 = width 2 (VS is zero-width)
    try std.testing.expectEqual(@as(usize, 2), stringWidth("🖥️")); // Desktop with VS-16
}

test "char_width: byte to display conversion" {
    const text = "🎯 hi"; // byte 0-3: 🎯, byte 4: space, byte 5: h, byte 6: i
    try std.testing.expectEqual(@as(usize, 0), byteToDisplayColumn(text, 0));
    // After emoji (width 2)
    try std.testing.expectEqual(@as(usize, 2), byteToDisplayColumn(text, 4));

    // Test with variation selector
    const text_vs = "🖥️ hi"; // Desktop emoji + VS-16 + space
    // After emoji+VS (2+0 = width 2)
    const after_vs = byteToDisplayColumn(text_vs, 7); // After both codepoints
    try std.testing.expectEqual(@as(usize, 2), after_vs);
}
