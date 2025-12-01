const std = @import("std");

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Convert from highlight_api.Color to this Color type
    /// This is the ONE place for this conversion (DRY principle)
    /// Used by: layer_renderer, window_renderer, separator_renderer, text_renderer
    pub fn fromApiColor(api_color: anytype) Color {
        // Handle both .rgb and .indexed variants
        return switch (api_color) {
            .rgb => |rgb| Color{ .r = rgb.r, .g = rgb.g, .b = rgb.b },
            .indexed => |idx| Color{ .r = idx, .g = idx, .b = idx }, // TODO: proper 256-color palette
        };
    }

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

    // Invisible character highlighting (listchars)
    whitespace: ?Highlight = null, // Whitespace characters (space, tab, nbsp) - Neovim uses this
    special_key: ?Highlight = null, // Special keys and characters (eol, trail) - Vim tradition
    non_text: ?Highlight = null, // Non-text characters (eol, extends, precedes) - fallback

    // Status line highlighting
    statusline: ?Highlight = null, // Active window status line (StatusLine)
    statusline_nc: ?Highlight = null, // Inactive window status line (StatusLineNC)

    // Floating window highlighting
    float_border: ?Highlight = null, // Floating window border (FloatBorder)
    normal_float: ?Highlight = null, // Floating window background (NormalFloat)

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
        } else if (std.mem.eql(u8, name, "Whitespace")) {
            self.whitespace = hl;
        } else if (std.mem.eql(u8, name, "SpecialKey")) {
            self.special_key = hl;
        } else if (std.mem.eql(u8, name, "NonText")) {
            self.non_text = hl;
        } else if (std.mem.eql(u8, name, "StatusLine")) {
            self.statusline = hl;
        } else if (std.mem.eql(u8, name, "StatusLineNC")) {
            self.statusline_nc = hl;
        } else if (std.mem.eql(u8, name, "FloatBorder")) {
            self.float_border = hl;
        } else if (std.mem.eql(u8, name, "NormalFloat")) {
            self.normal_float = hl;
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
        } else if (std.mem.eql(u8, name, "Whitespace")) {
            return self.whitespace;
        } else if (std.mem.eql(u8, name, "SpecialKey")) {
            return self.special_key;
        } else if (std.mem.eql(u8, name, "NonText")) {
            return self.non_text;
        } else if (std.mem.eql(u8, name, "StatusLine")) {
            return self.statusline;
        } else if (std.mem.eql(u8, name, "StatusLineNC")) {
            return self.statusline_nc;
        } else if (std.mem.eql(u8, name, "FloatBorder")) {
            return self.float_border;
        } else if (std.mem.eql(u8, name, "NormalFloat")) {
            return self.normal_float;
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

test "HighlightConfig: set and get Whitespace" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    const hl = Highlight{
        .fg = Color{ .r = 80, .g = 80, .b = 80 },
        .bg = Color{ .r = 30, .g = 30, .b = 30 },
    };
    config.setHighlight("Whitespace", hl);

    const retrieved = config.getHighlight("Whitespace");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(u8, 80), retrieved.?.fg.?.r);
    try std.testing.expectEqual(@as(u8, 80), retrieved.?.fg.?.g);
    try std.testing.expectEqual(@as(u8, 80), retrieved.?.fg.?.b);
    try std.testing.expectEqual(@as(u8, 30), retrieved.?.bg.?.r);
}

test "HighlightConfig: set and get SpecialKey" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    const hl = Highlight{
        .fg = Color{ .r = 128, .g = 128, .b = 128 },
    };
    config.setHighlight("SpecialKey", hl);

    const retrieved = config.getHighlight("SpecialKey");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(u8, 128), retrieved.?.fg.?.r);
    try std.testing.expect(retrieved.?.bg == null); // Background not set
}

test "HighlightConfig: set and get NonText" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    const hl = Highlight{
        .fg = Color{ .r = 64, .g = 64, .b = 64 },
    };
    config.setHighlight("NonText", hl);

    const retrieved = config.getHighlight("NonText");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(u8, 64), retrieved.?.fg.?.r);
}

test "HighlightConfig: get non-existent highlight returns null" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    const retrieved = config.getHighlight("Whitespace");
    try std.testing.expect(retrieved == null);
}

test "HighlightConfig: all three invisible char highlights" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    // Set all three highlight groups
    config.setHighlight("Whitespace", Highlight{
        .fg = Color{ .r = 50, .g = 50, .b = 50 },
    });
    config.setHighlight("SpecialKey", Highlight{
        .fg = Color{ .r = 80, .g = 80, .b = 80 },
    });
    config.setHighlight("NonText", Highlight{
        .fg = Color{ .r = 40, .g = 40, .b = 40 },
    });

    // Verify all are set correctly
    const ws = config.getHighlight("Whitespace");
    const sk = config.getHighlight("SpecialKey");
    const nt = config.getHighlight("NonText");

    try std.testing.expect(ws != null);
    try std.testing.expect(sk != null);
    try std.testing.expect(nt != null);

    try std.testing.expectEqual(@as(u8, 50), ws.?.fg.?.r);
    try std.testing.expectEqual(@as(u8, 80), sk.?.fg.?.r);
    try std.testing.expectEqual(@as(u8, 40), nt.?.fg.?.r);
}

test "HighlightConfig: overwrite existing highlight" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    // Set initial value
    config.setHighlight("Whitespace", Highlight{
        .fg = Color{ .r = 50, .g = 50, .b = 50 },
    });

    // Overwrite with new value
    config.setHighlight("Whitespace", Highlight{
        .fg = Color{ .r = 100, .g = 100, .b = 100 },
    });

    // Verify new value
    const retrieved = config.getHighlight("Whitespace");
    try std.testing.expectEqual(@as(u8, 100), retrieved.?.fg.?.r);
}

test "HighlightConfig: partial highlight (only fg)" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    const hl = Highlight{
        .fg = Color{ .r = 128, .g = 0, .b = 0 },
        // bg intentionally not set
    };
    config.setHighlight("SpecialKey", hl);

    const retrieved = config.getHighlight("SpecialKey");
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.fg != null);
    try std.testing.expect(retrieved.?.bg == null);
}

test "HighlightConfig: partial highlight (only bg)" {
    var config = HighlightConfig.init(std.testing.allocator);
    defer config.deinit();

    const hl = Highlight{
        // fg intentionally not set
        .bg = Color{ .r = 0, .g = 0, .b = 128 },
    };
    config.setHighlight("NonText", hl);

    const retrieved = config.getHighlight("NonText");
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.fg == null);
    try std.testing.expect(retrieved.?.bg != null);
}
