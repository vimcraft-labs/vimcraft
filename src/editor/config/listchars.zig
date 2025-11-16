const std = @import("std");

/// Parsed listchars configuration
/// Stores the characters to display for invisible characters
pub const ListChars = struct {
    /// Character to show at end of line (0 = don't show)
    eol: u21 = 0,

    /// Characters for tab display (up to 3 chars: start, middle, end)
    tab: [3]u21 = .{ '>', ' ', 0 }, // Default: "> "

    /// Character for spaces (0 = don't show)
    space: u21 = 0,

    /// Character for trailing spaces (0 = don't show)
    trail: u21 = '-',

    /// Character for non-breaking space
    nbsp: u21 = '+',

    /// Parse listchars string (e.g., "tab:>-,space:·,trail:~,eol:↵")
    pub fn parse(allocator: std.mem.Allocator, listchars_str: []const u8) !ListChars {
        _ = allocator;
        var result = ListChars{};

        var iter = std.mem.splitScalar(u8, listchars_str, ',');
        while (iter.next()) |item| {
            const trimmed = std.mem.trim(u8, item, " \t");
            if (trimmed.len == 0) continue;

            // Find the colon separator
            const colon_pos = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
            const key = trimmed[0..colon_pos];
            const value = trimmed[colon_pos + 1 ..];

            if (value.len == 0) continue;

            if (std.mem.eql(u8, key, "eol")) {
                result.eol = try getFirstChar(value);
            } else if (std.mem.eql(u8, key, "tab")) {
                try parseTab(&result, value);
            } else if (std.mem.eql(u8, key, "space")) {
                result.space = try getFirstChar(value);
            } else if (std.mem.eql(u8, key, "trail")) {
                result.trail = try getFirstChar(value);
            } else if (std.mem.eql(u8, key, "nbsp")) {
                result.nbsp = try getFirstChar(value);
            }
        }

        return result;
    }

    /// Get first UTF-8 character from string
    fn getFirstChar(s: []const u8) !u21 {
        if (s.len == 0) return 0;
        const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return s[0];
        if (len > s.len) return s[0];
        return std.unicode.utf8Decode(s[0..len]) catch s[0];
    }

    /// Parse tab display string (e.g., ">-" or "<->" for 3-char mode)
    fn parseTab(self: *ListChars, value: []const u8) !void {
        if (value.len == 0) return;

        // Get characters from the string
        var chars: [3]u21 = .{ 0, 0, 0 };
        var char_count: usize = 0;
        var i: usize = 0;

        while (i < value.len and char_count < 3) {
            const len = std.unicode.utf8ByteSequenceLength(value[i]) catch 1;
            if (len > value.len - i) break;

            chars[char_count] = std.unicode.utf8Decode(value[i .. i + len]) catch value[i];
            char_count += 1;
            i += len;
        }

        if (char_count >= 2) {
            // Two or three char mode
            self.tab[0] = chars[0]; // First char (always shown)
            self.tab[1] = chars[1]; // Middle char (repeated)
            self.tab[2] = if (char_count == 3) chars[2] else 0; // End char (optional)
        } else if (char_count == 1) {
            // Single char - just repeat it
            self.tab[0] = chars[0];
            self.tab[1] = chars[0];
            self.tab[2] = 0;
        }
    }
};

// ========== Tests ==========

test "ListChars: default values" {
    const lc = ListChars{};
    try std.testing.expectEqual(@as(u21, 0), lc.eol);
    try std.testing.expectEqual(@as(u21, '>'), lc.tab[0]);
    try std.testing.expectEqual(@as(u21, ' '), lc.tab[1]);
    try std.testing.expectEqual(@as(u21, 0), lc.tab[2]);
    try std.testing.expectEqual(@as(u21, '-'), lc.trail);
    try std.testing.expectEqual(@as(u21, '+'), lc.nbsp);
}

test "ListChars: parse simple" {
    const lc = try ListChars.parse(std.testing.allocator, "tab:>-,trail:~,eol:$");
    try std.testing.expectEqual(@as(u21, '$'), lc.eol);
    try std.testing.expectEqual(@as(u21, '>'), lc.tab[0]);
    try std.testing.expectEqual(@as(u21, '-'), lc.tab[1]);
    try std.testing.expectEqual(@as(u21, '~'), lc.trail);
}

test "ListChars: parse with unicode" {
    const lc = try ListChars.parse(std.testing.allocator, "tab:→·,space:·,eol:↵");
    try std.testing.expectEqual(@as(u21, '↵'), lc.eol);
    try std.testing.expectEqual(@as(u21, '→'), lc.tab[0]);
    try std.testing.expectEqual(@as(u21, '·'), lc.tab[1]);
    try std.testing.expectEqual(@as(u21, '·'), lc.space);
}

test "ListChars: parse tab with 3 chars" {
    const lc = try ListChars.parse(std.testing.allocator, "tab:<->");
    try std.testing.expectEqual(@as(u21, '<'), lc.tab[0]);
    try std.testing.expectEqual(@as(u21, '-'), lc.tab[1]);
    try std.testing.expectEqual(@as(u21, '>'), lc.tab[2]);
}

test "ListChars: Neovim default" {
    const lc = try ListChars.parse(std.testing.allocator, "tab:> ,trail:-,nbsp:+");
    try std.testing.expectEqual(@as(u21, 0), lc.eol);
    try std.testing.expectEqual(@as(u21, '>'), lc.tab[0]);
    try std.testing.expectEqual(@as(u21, ' '), lc.tab[1]);
    try std.testing.expectEqual(@as(u21, 0), lc.tab[2]);
    try std.testing.expectEqual(@as(u21, '-'), lc.trail);
    try std.testing.expectEqual(@as(u21, '+'), lc.nbsp);
}
