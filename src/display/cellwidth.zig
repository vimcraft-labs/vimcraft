const std = @import("std");
const uucode = @import("uucode");

/// Width override entry for a character or range
pub const CellWidthEntry = struct {
    start: u21,
    end: u21,
    width: u8,
};

/// Ambiguous width mode (similar to Neovim's 'ambiwidth' option)
pub const AmbiWidthMode = enum {
    single,  // Ambiguous width chars are single-width
    double,  // Ambiguous width chars are double-width
    auto,    // Auto-detect based on terminal
};

/// Configuration for character width handling
pub const CellWidthConfig = struct {
    /// User-defined character width overrides
    overrides: std.ArrayList(CellWidthEntry),

    /// How to handle ambiguous width characters
    ambiwidth: AmbiWidthMode = .single,

    /// Whether to use emoji presentation for emoji characters
    emoji_mode: bool = true,

    /// Terminal-specific adjustments detected at startup
    terminal_quirks: TerminalQuirks = .{},

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
        // Binary search for efficiency
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

/// Terminal-specific quirks detected at startup
pub const TerminalQuirks = struct {
    /// Some terminals render emoji with wcwidth=1 as 2-wide
    emoji_wcwidth_mismatch: bool = false,

    /// Terminal name (for debugging)
    name: []const u8 = "unknown",

    /// Terminal program (TERM_PROGRAM env var)
    program: []const u8 = "unknown",

    /// Is this WezTerm?
    is_wezterm: bool = false,
};

/// Global cellwidth configuration (similar to Neovim's global state)
var global_config: ?*CellWidthConfig = null;

/// Initialize the global cellwidth configuration
pub fn initGlobal(allocator: std.mem.Allocator) !void {
    if (global_config != null) return;

    global_config = try allocator.create(CellWidthConfig);
    global_config.?.* = try CellWidthConfig.init(allocator);

    // Detect terminal and apply default configuration
    try detectTerminalAndConfigure(global_config.?);
}

/// Deinitialize the global configuration
pub fn deinitGlobal(allocator: std.mem.Allocator) void {
    if (global_config) |config| {
        config.deinit();
        allocator.destroy(config);
        global_config = null;
    }
}

/// Detect terminal and apply appropriate configuration
fn detectTerminalAndConfigure(config: *CellWidthConfig) !void {
    // Get TERM environment variable
    const term = std.posix.getenv("TERM") orelse "unknown";
    const term_program = std.posix.getenv("TERM_PROGRAM");

    // Set terminal name for debugging
    config.terminal_quirks.name = term;

    // Terminal-specific detection
    if (term_program) |tp| {
        config.terminal_quirks.program = tp;

        if (std.mem.eql(u8, tp, "WezTerm")) {
            config.terminal_quirks.emoji_wcwidth_mismatch = true;
            config.terminal_quirks.is_wezterm = true;


            // WezTerm-specific: Force ALL emoji/symbol ranges to width 2
            // WezTerm renders these as 2-wide regardless of what wcwidth says

            // ALL emoji and symbol blocks that might render wide in WezTerm
            try config.addOverride(0x2190, 0x21FF, 2);    // Arrows
            try config.addOverride(0x2300, 0x23FF, 2);    // Misc Technical
            try config.addOverride(0x2460, 0x24FF, 2);    // Enclosed Alphanumerics
            try config.addOverride(0x25A0, 0x25FF, 2);    // Geometric Shapes
            try config.addOverride(0x2600, 0x27BF, 2);    // Misc Symbols & Dingbats
            try config.addOverride(0x2900, 0x297F, 2);    // Supplemental Arrows-B
            try config.addOverride(0x2B00, 0x2BFF, 2);    // Misc Symbols and Arrows

            // All emoji blocks
            try config.addOverride(0x1F000, 0x1FFFF, 2);  // ALL emoji ranges

            // Even more specific problem characters in WezTerm
            try config.addOverride(0x203C, 0x203C, 2);    // ‼
            try config.addOverride(0x2049, 0x2049, 2);    // ⁉
            try config.addOverride(0x2122, 0x2122, 2);    // ™
            try config.addOverride(0x2139, 0x2139, 2);    // ℹ
            try config.addOverride(0x2194, 0x2199, 2);    // ↔ ↕ etc
            try config.addOverride(0x21A9, 0x21AA, 2);    // ↩ ↪
            try config.addOverride(0x231A, 0x231B, 2);    // ⌚ ⌛
            try config.addOverride(0x2328, 0x2328, 2);    // ⌨
            try config.addOverride(0x23E9, 0x23F3, 2);    // ⏩ ⏪ etc
            try config.addOverride(0x23F8, 0x23FA, 2);    // ⏸ ⏹ ⏺
            try config.addOverride(0x24C2, 0x24C2, 2);    // Ⓜ

        } else if (std.mem.eql(u8, tp, "ghostty")) {
            config.terminal_quirks.emoji_wcwidth_mismatch = false;
            // Ghostty is more consistent, but still apply modern emoji
            try config.addOverride(0x1F000, 0x1FFFF, 2);  // Modern emoji
        }
    } else {
        // Default: assume emoji should be width 2
        if (config.emoji_mode) {
            try config.addOverride(0x1F000, 0x1FFFF, 2);  // Modern emoji
            try config.addOverride(0x2600, 0x27BF, 2);    // Common symbols
        }
    }
}

/// Get the display width of a Unicode codepoint
/// This is the main API that respects configuration and overrides
pub fn getWidth(codepoint: u21) u8 {
    // Check if codepoint is beyond Unicode range
    if (codepoint > uucode.config.max_code_point) return 1;

    // Check for user/terminal overrides first
    if (global_config) |config| {
        if (config.getOverride(codepoint)) |override| {
            return override;
        }
    }

    // Handle zero-width characters explicitly
    if (isZeroWidth(codepoint)) return 0;

    // Get base width from uucode
    const base_width = uucode.get(.width, codepoint);

    // SPECIAL WEZTERM HANDLING: Force ALL emoji-like characters to width 2
    // WezTerm renders many characters as 2-wide even when wcwidth says 1
    if (global_config) |config| {
        if (config.terminal_quirks.is_wezterm) {
            // We detected WezTerm - be aggressive with width 2
            // WezTerm renders many characters wider than expected

            // Check for emoji and symbol ranges that WezTerm renders as double-width
            // Note: Box drawing (0x2500-0x257F) are typically single-width
            if ((codepoint >= 0x203C and codepoint <= 0x203C) or    // ‼
                (codepoint >= 0x2049 and codepoint <= 0x2049) or    // ⁉
                (codepoint >= 0x2122 and codepoint <= 0x2122) or    // ™
                (codepoint >= 0x2139 and codepoint <= 0x2139) or    // ℹ
                (codepoint >= 0x2190 and codepoint <= 0x21FF) or    // Arrows
                (codepoint >= 0x2300 and codepoint <= 0x23FF) or    // Misc Technical
                (codepoint >= 0x2460 and codepoint <= 0x24FF) or    // Enclosed Alphanumerics
                (codepoint >= 0x25A0 and codepoint <= 0x25FF) or    // Geometric Shapes
                (codepoint >= 0x2600 and codepoint <= 0x27BF) or    // Misc Symbols & Dingbats
                (codepoint >= 0x2900 and codepoint <= 0x297F) or    // Supplemental Arrows-B
                (codepoint >= 0x2B00 and codepoint <= 0x2BFF) or    // Misc Symbols and Arrows
                (codepoint >= 0x1F000 and codepoint <= 0x1FFFF))    // All modern emoji
            {
                // For WezTerm, ALWAYS force these chars to width 2 regardless of base width
                // This ensures consistent rendering in WezTerm
                return 2;
            }
        }
    }

    // Apply ambiguous width configuration
    if (global_config) |config| {
        if (config.ambiwidth == .double and isAmbiguousWidth(codepoint)) {
            return 2;
        }
    }

    return base_width;
}

/// Check if a character is zero-width (combining marks, etc.)
fn isZeroWidth(codepoint: u21) bool {
    // Variation Selectors
    if (codepoint >= 0xFE00 and codepoint <= 0xFE0F) return true;
    if (codepoint >= 0xE0100 and codepoint <= 0xE01EF) return true;

    // Zero-width characters
    if (codepoint == 0x200B or // Zero Width Space
        codepoint == 0x200C or // Zero Width Non-Joiner
        codepoint == 0x200D or // Zero Width Joiner
        codepoint == 0xFEFF)   // Zero Width No-Break Space
        return true;

    // Combining marks
    if (codepoint >= 0x0300 and codepoint <= 0x036F) return true;
    if (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) return true;
    if (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) return true;
    if (codepoint >= 0xFE20 and codepoint <= 0xFE2F) return true;

    return false;
}

/// Check if a character has ambiguous East Asian width
fn isAmbiguousWidth(codepoint: u21) bool {
    // For now, return false as we don't have easy access to East Asian Width property
    // This could be improved later with a proper Unicode database
    _ = codepoint;
    return false;
}

/// Set cell widths for a list of characters (like Neovim's setcellwidths())
pub fn setCellWidths(entries: []const CellWidthEntry) !void {
    if (global_config) |config| {
        // Clear existing overrides
        config.overrides.clearRetainingCapacity();

        // Add new entries
        for (entries) |entry| {
            try config.addOverride(entry.start, entry.end, entry.width);
        }
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

// Test support
test "cellwidth: basic ASCII" {
    // Initialize for testing
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

test "cellwidth: custom overrides" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    // Add custom override for a specific character
    if (global_config) |config| {
        try config.addOverride(0x2702, 0x2702, 2); // ✂ scissors

        // Now it should return 2 instead of default
        try std.testing.expectEqual(@as(u8, 2), getWidth(0x2702));
    }
}

test "cellwidth: emoji widths" {
    try initGlobal(std.testing.allocator);
    defer deinitGlobal(std.testing.allocator);

    // Test that common emoji return width 2
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x1F3AF)); // 🎯
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x1F680)); // 🚀
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x1F5A5)); // 🖥️
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x2699));  // ⚙️
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x26A1));  // ⚡
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x21A9));  // ↩️
    try std.testing.expectEqual(@as(u8, 2), getWidth(0x2702));  // ✂️

    // ASCII should still be width 1
    try std.testing.expectEqual(@as(u8, 1), getWidth('A'));
    try std.testing.expectEqual(@as(u8, 1), getWidth('1'));
}