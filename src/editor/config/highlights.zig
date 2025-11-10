const std = @import("std");

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Parse hex color string like "#2b2b2b" or "2b2b2b"
    pub fn fromHex(hex: []const u8) !Color {
        var start: usize = 0;
        if (hex.len > 0 and hex[0] == '#') {
            start = 1;
        }
        const hex_digits = hex[start..];

        if (hex_digits.len != 6) {
            return error.InvalidHexColor;
        }

        const r = try std.fmt.parseInt(u8, hex_digits[0..2], 16);
        const g = try std.fmt.parseInt(u8, hex_digits[2..4], 16);
        const b = try std.fmt.parseInt(u8, hex_digits[4..6], 16);

        return Color{ .r = r, .g = g, .b = b };
    }

    /// Convert to ANSI 24-bit true color escape sequence (background)
    pub fn toAnsiBg(self: Color, buf: []u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "\x1b[48;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
    }

    /// Convert to ANSI 24-bit true color escape sequence (foreground)
    pub fn toAnsiFg(self: Color, buf: []u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "\x1b[38;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
    }
};

/// Highlight definition (foreground, background, attributes)
pub const Highlight = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
};

/// Global highlight configuration
pub const HighlightConfig = struct {
    normal: ?Highlight = null, // Normal text (background/foreground)
    cursor: ?Highlight = null, // Cursor highlight
    cursorline: ?Highlight = null,
    visual: ?Highlight = null,
    yank_flash: ?Highlight = null, // Brief flash after yank
    line_nr: ?Highlight = null,
    cursorline_nr: ?Highlight = null, // Line number on cursor line (CursorLineNr)

    // Options
    cursorline_enabled: bool = true, // Enabled by default (standard Vim/Neovim behavior)

    // Sign column config (stored here temporarily for JSI access)
    signcolumn_mode: []const u8 = "no", // "yes", "no", "auto"

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HighlightConfig {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HighlightConfig) void {
        _ = self;
        // Future: clean up if we allocate dynamic highlights
    }

    /// Set a highlight by name
    pub fn setHighlight(self: *HighlightConfig, name: []const u8, hl: Highlight) void {
        if (std.mem.eql(u8, name, "Normal")) {
            self.normal = hl;
        } else if (std.mem.eql(u8, name, "Cursor")) {
            self.cursor = hl;
        } else if (std.mem.eql(u8, name, "CursorLine")) {
            self.cursorline = hl;
        } else if (std.mem.eql(u8, name, "Visual")) {
            self.visual = hl;
        } else if (std.mem.eql(u8, name, "YankFlash")) {
            self.yank_flash = hl;
        } else if (std.mem.eql(u8, name, "LineNr")) {
            self.line_nr = hl;
        } else if (std.mem.eql(u8, name, "CursorLineNr")) {
            self.cursorline_nr = hl;
        }
        // Add more highlight groups as needed
    }

    /// Get highlight for a specific group
    pub fn getHighlight(self: *const HighlightConfig, name: []const u8) ?Highlight {
        if (std.mem.eql(u8, name, "Normal")) {
            return self.normal;
        } else if (std.mem.eql(u8, name, "Cursor")) {
            return self.cursor;
        } else if (std.mem.eql(u8, name, "CursorLine")) {
            return self.cursorline;
        } else if (std.mem.eql(u8, name, "Visual")) {
            return self.visual;
        } else if (std.mem.eql(u8, name, "YankFlash")) {
            return self.yank_flash;
        } else if (std.mem.eql(u8, name, "LineNr")) {
            return self.line_nr;
        } else if (std.mem.eql(u8, name, "CursorLineNr")) {
            return self.cursorline_nr;
        }
        return null;
    }
};

// Tests
test "Color: parse hex" {
    const color = try Color.fromHex("#2b2b2b");
    try std.testing.expectEqual(@as(u8, 0x2b), color.r);
    try std.testing.expectEqual(@as(u8, 0x2b), color.g);
    try std.testing.expectEqual(@as(u8, 0x2b), color.b);

    const color2 = try Color.fromHex("ff00aa");
    try std.testing.expectEqual(@as(u8, 0xff), color2.r);
    try std.testing.expectEqual(@as(u8, 0x00), color2.g);
    try std.testing.expectEqual(@as(u8, 0xaa), color2.b);
}

test "Color: ANSI escape codes" {
    const color = Color{ .r = 43, .g = 43, .b = 43 };
    var buf: [32]u8 = undefined;

    const bg = try color.toAnsiBg(&buf);
    try std.testing.expectEqualStrings("\x1b[48;2;43;43;43m", bg);

    const fg = try color.toAnsiFg(&buf);
    try std.testing.expectEqualStrings("\x1b[38;2;43;43;43m", fg);
}
