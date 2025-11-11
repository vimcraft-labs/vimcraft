const std = @import("std");
const options = @import("options.zig");
const OptionMeta = options.OptionMeta;
const OptionValue = options.OptionValue;

/// All supported editor options
/// Organized by category: Display, Editing, Behavior, Search, UI
pub const OPTIONS = [_]OptionMeta{
    // ========== Display Options ==========

    .{
        .name = "number",
        .short_name = "nu",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "relativenumber",
        .short_name = "rnu",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "cursorline",
        .short_name = "cul",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "cursorcolumn",
        .short_name = "cuc",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "signcolumn",
        .short_name = "scl",
        .type = .string,
        .default = .{ .string = "auto" }, // "yes", "no", "auto", "auto:[1-9]"
        .scope = .window,
    },

    .{
        .name = "colorcolumn",
        .short_name = "cc",
        .type = .string,
        .default = .{ .string = "" }, // "80" or "+1" or "80,120"
        .scope = .window,
    },

    .{
        .name = "wrap",
        .short_name = null,
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .window,
    },

    .{
        .name = "linebreak",
        .short_name = "lbr",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "scrolloff",
        .short_name = "so",
        .type = .number,
        .default = .{ .number = 0 },
        .scope = .global,
    },

    .{
        .name = "sidescrolloff",
        .short_name = "siso",
        .type = .number,
        .default = .{ .number = 0 },
        .scope = .global,
    },

    // ========== Editing Options ==========

    .{
        .name = "tabstop",
        .short_name = "ts",
        .type = .number,
        .default = .{ .number = 8 },
        .scope = .buffer,
    },

    .{
        .name = "shiftwidth",
        .short_name = "sw",
        .type = .number,
        .default = .{ .number = 8 },
        .scope = .buffer,
    },

    .{
        .name = "expandtab",
        .short_name = "et",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "autoindent",
        .short_name = "ai",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "smartindent",
        .short_name = "si",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "textwidth",
        .short_name = "tw",
        .type = .number,
        .default = .{ .number = 0 },
        .scope = .buffer,
    },

    // ========== Behavior Options ==========

    .{
        .name = "mouse",
        .short_name = null,
        .type = .string,
        .default = .{ .string = "" }, // "a" for all modes, "n" for normal, etc.
        .scope = .global,
    },

    .{
        .name = "clipboard",
        .short_name = "cb",
        .type = .string,
        .default = .{ .string = "" }, // "unnamed", "unnamedplus", "unnamed,unnamedplus"
        .scope = .global,
    },

    .{
        .name = "undolevels",
        .short_name = "ul",
        .type = .number,
        .default = .{ .number = 1000 },
        .scope = .global,
    },

    .{
        .name = "timeout",
        .short_name = "to",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "timeoutlen",
        .short_name = "tm",
        .type = .number,
        .default = .{ .number = 1000 }, // milliseconds
        .scope = .global,
    },

    .{
        .name = "updatetime",
        .short_name = null,
        .type = .number,
        .default = .{ .number = 4000 }, // milliseconds
        .scope = .global,
    },

    // ========== Search Options ==========

    .{
        .name = "ignorecase",
        .short_name = "ic",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "smartcase",
        .short_name = "scs",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "hlsearch",
        .short_name = "hls",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "incsearch",
        .short_name = "is",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    // ========== UI Options ==========

    .{
        .name = "laststatus",
        .short_name = null,
        .type = .number,
        .default = .{ .number = 2 }, // 0=never, 1=only if multiple windows, 2=always, 3=global statusline
        .scope = .global,
    },

    .{
        .name = "showcmd",
        .short_name = "sc",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "showmode",
        .short_name = "smd",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "ruler",
        .short_name = "ru",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },
};

/// Get option metadata by name (returns null if not found)
pub fn getOptionMeta(name: []const u8) ?OptionMeta {
    for (OPTIONS) |opt| {
        if (std.mem.eql(u8, opt.name, name)) {
            return opt;
        }
        if (opt.short_name) |short| {
            if (std.mem.eql(u8, short, name)) {
                return opt;
            }
        }
    }
    return null;
}

/// Validate an option value against its metadata
pub fn validateOption(meta: OptionMeta, value: OptionValue) bool {
    // Check type matches
    if (@intFromEnum(meta.type) != @intFromEnum(value)) {
        return false;
    }

    // Type-specific validation
    switch (value) {
        .string => |s| {
            // Special validation for specific options
            if (std.mem.eql(u8, meta.name, "signcolumn")) {
                // Valid values: "yes", "no", "auto", "auto:1" through "auto:9"
                if (std.mem.eql(u8, s, "yes") or
                    std.mem.eql(u8, s, "no") or
                    std.mem.eql(u8, s, "auto"))
                {
                    return true;
                }
                if (std.mem.startsWith(u8, s, "auto:") and s.len == 6) {
                    const digit = s[5];
                    return digit >= '1' and digit <= '9';
                }
                return false;
            }
            // Other string options are generally free-form
            return true;
        },
        .number => |n| {
            // Range validation for specific options
            if (std.mem.eql(u8, meta.name, "tabstop") or
                std.mem.eql(u8, meta.name, "shiftwidth"))
            {
                return n > 0 and n <= 20; // Reasonable tab width range
            }
            if (std.mem.eql(u8, meta.name, "laststatus")) {
                return n >= 0 and n <= 3;
            }
            // Most number options allow any non-negative value
            return n >= 0;
        },
        .boolean => return true,
    }
}

// ========== Tests ==========

test "getOptionMeta: find by full name" {
    const meta = getOptionMeta("number");
    try std.testing.expect(meta != null);
    try std.testing.expectEqualStrings("number", meta.?.name);
    try std.testing.expect(meta.?.type == .boolean);
}

test "getOptionMeta: find by short name" {
    const meta = getOptionMeta("nu");
    try std.testing.expect(meta != null);
    try std.testing.expectEqualStrings("number", meta.?.name);
}

test "getOptionMeta: not found" {
    const meta = getOptionMeta("nonexistent");
    try std.testing.expect(meta == null);
}

test "validateOption: correct type" {
    const meta = getOptionMeta("number").?;
    const value = OptionValue{ .boolean = true };
    try std.testing.expect(validateOption(meta, value));
}

test "validateOption: wrong type" {
    const meta = getOptionMeta("number").?;
    const value = OptionValue{ .number = 42 };
    try std.testing.expect(!validateOption(meta, value));
}

test "validateOption: signcolumn valid values" {
    const meta = getOptionMeta("signcolumn").?;

    try std.testing.expect(validateOption(meta, .{ .string = "yes" }));
    try std.testing.expect(validateOption(meta, .{ .string = "no" }));
    try std.testing.expect(validateOption(meta, .{ .string = "auto" }));
    try std.testing.expect(validateOption(meta, .{ .string = "auto:1" }));
    try std.testing.expect(validateOption(meta, .{ .string = "auto:9" }));

    // Invalid values
    try std.testing.expect(!validateOption(meta, .{ .string = "maybe" }));
    try std.testing.expect(!validateOption(meta, .{ .string = "auto:0" }));
    try std.testing.expect(!validateOption(meta, .{ .string = "auto:10" }));
}

test "validateOption: tabstop range" {
    const meta = getOptionMeta("tabstop").?;

    try std.testing.expect(validateOption(meta, .{ .number = 1 }));
    try std.testing.expect(validateOption(meta, .{ .number = 4 }));
    try std.testing.expect(validateOption(meta, .{ .number = 8 }));
    try std.testing.expect(validateOption(meta, .{ .number = 20 }));

    // Out of range
    try std.testing.expect(!validateOption(meta, .{ .number = 0 }));
    try std.testing.expect(!validateOption(meta, .{ .number = 21 }));
    try std.testing.expect(!validateOption(meta, .{ .number = -1 }));
}
