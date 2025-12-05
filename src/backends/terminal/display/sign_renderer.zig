const std = @import("std");
const namespace_api = @import("../../../system/jsi/namespace_api.zig");

/// Sign characters decoded from UTF-8 sign text
/// Used by both layer_renderer and window_renderer for consistent sign rendering
pub const SignChars = struct {
    char_0: u21 = ' ',
    char_1: u21 = ' ',
};

/// Sign info with decoded characters and optional highlight group
pub const DecodedSign = struct {
    chars: SignChars = .{},
    hl_group: ?[]const u8 = null,
};

/// Decode UTF-8 sign text into up to 2 Unicode codepoints
/// Signs in Neovim/Vimcraft are 1-2 characters wide (e.g., "+", "▎", ">>")
pub fn decodeSignText(text: []const u8) SignChars {
    var result = SignChars{};
    var byte_idx: usize = 0;

    // First codepoint
    if (byte_idx < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + len <= text.len) {
            result.char_0 = std.unicode.utf8Decode(text[byte_idx..][0..len]) catch ' ';
            byte_idx += len;
        }
    }

    // Second codepoint (if any)
    if (byte_idx < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[byte_idx]) catch 1;
        if (byte_idx + len <= text.len) {
            result.char_1 = std.unicode.utf8Decode(text[byte_idx..][0..len]) catch ' ';
        }
    }

    return result;
}

/// Look up sign for a line and decode it
/// Returns DecodedSign with decoded characters and optional highlight group name
/// Caller is responsible for looking up the highlight group in their registry
pub fn lookupSign(
    buf_exts: ?*const namespace_api.BufferExtmarks,
    line_num: usize,
) DecodedSign {
    var result = DecodedSign{};

    if (buf_exts) |exts| {
        if (exts.getSignForLine(line_num)) |sign_info| {
            result.chars = decodeSignText(sign_info.text);
            result.hl_group = sign_info.hl_group;
        }
    }

    return result;
}

/// Look up sign using buffer handle (for window_renderer which doesn't have buf_exts directly)
pub fn lookupSignByHandle(
    buffer_handle: i64,
    line_num: usize,
) DecodedSign {
    const buf_exts = namespace_api.getBufferExtmarks(buffer_handle);
    return lookupSign(buf_exts, line_num);
}

// Tests
test "decodeSignText ASCII" {
    const result = decodeSignText("+");
    try std.testing.expectEqual(@as(u21, '+'), result.char_0);
    try std.testing.expectEqual(@as(u21, ' '), result.char_1);
}

test "decodeSignText two ASCII" {
    const result = decodeSignText(">>");
    try std.testing.expectEqual(@as(u21, '>'), result.char_0);
    try std.testing.expectEqual(@as(u21, '>'), result.char_1);
}

test "decodeSignText Unicode BoldLineLeft" {
    // ▎ = U+258E = 0xE2 0x96 0x8E in UTF-8
    const result = decodeSignText("▎");
    try std.testing.expectEqual(@as(u21, 0x258E), result.char_0);
    try std.testing.expectEqual(@as(u21, ' '), result.char_1);
}

test "decodeSignText empty" {
    const result = decodeSignText("");
    try std.testing.expectEqual(@as(u21, ' '), result.char_0);
    try std.testing.expectEqual(@as(u21, ' '), result.char_1);
}
