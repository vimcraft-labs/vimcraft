const std = @import("std");
const uucode = @import("uucode");

/// Width override entry for a character or range (like Neovim's setcellwidths())
pub const CellWidthEntry = struct {
    start: u21,
    end: u21,
    width: u8,
};

/// Ambiguous width mode (like Neovim's 'ambiwidth' option)
pub const AmbiWidthMode = enum {
    single, // Ambiguous width chars are single-width (default)
    double, // Ambiguous width chars are double-width
};

/// Configuration for character width handling
/// Follows Neovim's approach: Unicode standard + user configuration
pub const CellWidthConfig = struct {
    /// User-defined character width overrides (via vim.fn.setcellwidths())
    overrides: std.ArrayList(CellWidthEntry),

    /// How to handle ambiguous width characters (like Neovim's 'ambiwidth')
    ambiwidth: AmbiWidthMode = .single,

    /// Whether emoji characters >= 0x1F000 should be width 2 (like Neovim's 'emoji')
    emoji: bool = true,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !CellWidthConfig {
        return .{
            .overrides = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CellWidthConfig) void {
        self.overrides.deinit(self.allocator);
    }

    /// Add a character width override
    pub fn addOverride(self: *CellWidthConfig, start: u21, end: u21, width: u8) !void {
        try self.overrides.append(self.allocator, .{
            .start = start,
            .end = end,
            .width = width,
        });
        // Keep sorted for binary search
        std.mem.sort(CellWidthEntry, self.overrides.items, {}, compareEntries);
    }

    /// Get the width override for a character (if any)
    pub fn getOverride(self: *const CellWidthConfig, codepoint: u21) ?u8 {
        // Linear search (overrides are typically small)
        for (self.overrides.items) |entry| {
            if (codepoint >= entry.start and codepoint <= entry.end) {
                return entry.width;
            }
        }
        return null;
    }

    fn compareEntries(_: void, a: CellWidthEntry, b: CellWidthEntry) bool {
        return a.start < b.start;
    }
};

/// Global cellwidth configuration
var global_config: ?*CellWidthConfig = null;

/// Initialize the global cellwidth configuration
pub fn initGlobal(allocator: std.mem.Allocator) !void {
    if (global_config != null) return;

    global_config = try allocator.create(CellWidthConfig);
    global_config.?.* = try CellWidthConfig.init(allocator);
}

/// Deinitialize the global configuration
pub fn deinitGlobal(allocator: std.mem.Allocator) void {
    if (global_config) |config| {
        config.deinit();
        allocator.destroy(config);
        global_config = null;
    }
}

/// Get the display width of a Unicode codepoint
/// Follows Neovim's utf_char2cells() logic:
/// 1. Check user overrides (setcellwidths)
/// 2. Use Unicode standard (uucode/utf8proc)
/// 3. Check 'ambiwidth' option
/// 4. Check 'emoji' option for emoji >= 0x1F000
pub fn getWidth(codepoint: u21) u8 {
    // Check if codepoint is beyond Unicode range
    if (codepoint > uucode.config.max_code_point) return 1;

    // 1. Check for user overrides first (like Neovim's cw_value())
    if (global_config) |config| {
        if (config.getOverride(codepoint)) |override| {
            return override;
        }
    }

    // Handle zero-width characters explicitly
    if (isZeroWidth(codepoint)) return 0;

    // 2. Get base width from uucode (Unicode standard, like Neovim's utf8proc)
    const base_width = uucode.get(.width, codepoint);

    // 3. Apply ambiguous width configuration (like Neovim's 'ambiwidth')
    if (global_config) |config| {
        if (config.ambiwidth == .double and isAmbiguousWidth(codepoint)) {
            return 2;
        }
    }

    // 4. Apply emoji configuration (like Neovim's 'emoji' option)
    // Characters >= 0x1F000 may be considered width 2 when emoji is enabled
    if (global_config) |config| {
        if (config.emoji and codepoint >= 0x1F000 and codepoint <= 0x1FFFF) {
            // Modern emoji are width 2 when emoji mode is enabled
            return 2;
        }
    }

    return base_width;
}

/// Check if a character is zero-width (combining marks, variation selectors, etc.)
fn isZeroWidth(codepoint: u21) bool {
    // Variation Selectors (VS1-VS16)
    if (codepoint >= 0xFE00 and codepoint <= 0xFE0F) return true;
    // Variation Selectors Supplement
    if (codepoint >= 0xE0100 and codepoint <= 0xE01EF) return true;

    // Zero-width characters
    if (codepoint == 0x200B or // Zero Width Space
        codepoint == 0x200C or // Zero Width Non-Joiner
        codepoint == 0x200D or // Zero Width Joiner
        codepoint == 0xFEFF) // Zero Width No-Break Space (BOM)
        return true;

    // Combining Diacritical Marks
    if (codepoint >= 0x0300 and codepoint <= 0x036F) return true;
    // Combining Diacritical Marks Extended
    if (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) return true;
    // Combining Diacritical Marks Supplement
    if (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) return true;
    // Combining Half Marks
    if (codepoint >= 0xFE20 and codepoint <= 0xFE2F) return true;

    return false;
}

/// Check if a character has ambiguous East Asian width
/// TODO: Implement proper East Asian Width property lookup from Unicode data
fn isAmbiguousWidth(codepoint: u21) bool {
    // Common ambiguous width characters
    // These are characters that may be rendered as either single or double width
    // depending on the context (CJK vs Western)

    // Greek letters (often ambiguous)
    if (codepoint >= 0x0391 and codepoint <= 0x03C9) return true;

    // Cyrillic letters (often ambiguous)
    if (codepoint >= 0x0410 and codepoint <= 0x044F) return true;

    // Box drawing characters
    if (codepoint >= 0x2500 and codepoint <= 0x257F) return true;

    // For a complete implementation, we'd need the full East Asian Width
    // property from Unicode data. For now, return false for most characters.
    return false;
}

/// Set cell widths for a list of characters (like Neovim's setcellwidths())
/// This is the user-facing API for configuring character widths
pub fn setCellWidths(entries: []const CellWidthEntry) !void {
    if (global_config) |config| {
        // Clear existing user overrides
        config.overrides.clearRetainingCapacity();

        // Add new entries
        for (entries) |entry| {
            try config.addOverride(entry.start, entry.end, entry.width);
        }
    }
}

/// Set the ambiguous width mode (like Neovim's 'ambiwidth' option)
pub fn setAmbiWidth(mode: AmbiWidthMode) void {
    if (global_config) |config| {
        config.ambiwidth = mode;
    }
}

/// Set the emoji mode (like Neovim's 'emoji' option)
pub fn setEmoji(enabled: bool) void {
    if (global_config) |config| {
        config.emoji = enabled;
    }
}

/// Get string display width
pub fn getStringWidth(str: []const u8) usize {
    var total_width: usize = 0;
    var i: usize = 0;

    while (i < str.len) {
        const char_len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + char_len > str.len) break;

        const codepoint = std.unicode.utf8Decode(str[i..][0..char_len]) catch ' ';
        total_width += getWidth(codepoint);

        i += char_len;
    }

    return total_width;
}

// Tests
test "cellwidth: basic ASCII" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 1), getWidth('a'));
    try std.testing.expectEqual(@as(u8, 1), getWidth('Z'));
    try std.testing.expectEqual(@as(u8, 1), getWidth(' '));
}

test "cellwidth: CJK double-width" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 2), getWidth(0x4E2D)); // 中
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x6587)); // 文
}

test "cellwidth: zero-width marks" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 0), getWidth(0xFE0F)); // VS-16
    try std.testing.expectEqual(@as(u8, 0), getWidth(0x0300)); // Combining grave
}

test "cellwidth: user overrides" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    // Add custom override for a specific character
    if (global_config) |config| {
        try config.addOverride(0x2702, 0x2702, 2); // ✂ scissors

        // Now it should return 2 instead of default
        try std.testing.expectEqual(@as(u8, 2), getWidth(0x2702));
    }
}

test "cellwidth: modern emoji with emoji option" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    // Modern emoji (>= 0x1F000) should be width 2 when emoji=true (default)
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x1F3AF)); // 🎯
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x1F680)); // 🚀

    // Disable emoji mode
    setEmoji(false);

    // Now they use uucode's base width (which may be 1 or 2)
    // The exact value depends on uucode's Unicode data
    const width = getWidth(0x1F680);
    try std.testing.expect(width == 1 or width == 2);
}

test "cellwidth: symbols use Unicode standard" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    // Symbols like ⚠ (U+26A0) use uucode's standard width
    // No terminal-specific hacks - users can override with setcellwidths()
    const warning_width = getWidth(0x26A0); // ⚠
    try std.testing.expect(warning_width == 1 or warning_width == 2);

    // Arrows use uucode's standard width
    const arrow_width = getWidth(0x2192); // →
    try std.testing.expect(arrow_width == 1 or arrow_width == 2);
}
