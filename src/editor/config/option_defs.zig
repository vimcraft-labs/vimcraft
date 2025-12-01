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
        .js_name = "number",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "relativenumber",
        .short_name = "rnu",
        .js_name = "relativeNumber",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "numberwidth",
        .short_name = "nuw",
        .js_name = "numberWidth",
        .type = .number,
        .default = .{ .number = 4 }, // Neovim default: minimum 4 digits
        .scope = .window,
    },

    .{
        .name = "cursorline",
        .short_name = "cul",
        .js_name = "cursorLine",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "cursorcolumn",
        .short_name = "cuc",
        .js_name = "cursorColumn",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "signcolumn",
        .short_name = "scl",
        .js_name = "signColumn",
        .type = .string,
        .default = .{ .string = "auto" }, // "yes", "no", "auto", "auto:[1-9]"
        .scope = .window,
    },

    .{
        .name = "colorcolumn",
        .short_name = "cc",
        .js_name = "colorColumn",
        .type = .string,
        .default = .{ .string = "" }, // "80" or "+1" or "80,120"
        .scope = .window,
    },

    .{
        .name = "wrap",
        .short_name = null,
        .js_name = "wrap",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .window,
    },

    .{
        .name = "linebreak",
        .short_name = "lbr",
        .js_name = "lineBreak",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "list",
        .short_name = null,
        .js_name = "list",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "listchars",
        .short_name = "lcs",
        .js_name = "listChars",
        .type = .string,
        .default = .{ .string = "tab:> ,trail:-,nbsp:+" }, // Neovim default
        .scope = .global,
    },

    .{
        .name = "scrolloff",
        .short_name = "so",
        .js_name = "scrollOff",
        .type = .number,
        .default = .{ .number = 0 },
        .scope = .global,
    },

    .{
        .name = "sidescrolloff",
        .short_name = "siso",
        .js_name = "sideScrollOff",
        .type = .number,
        .default = .{ .number = 0 },
        .scope = .global,
    },

    .{
        .name = "conceallevel",
        .short_name = "cole",
        .js_name = "concealLevel",
        .type = .number,
        .default = .{ .number = 0 }, // 0=show, 1=replace, 2=hide, 3=completely hide
        .scope = .window,
    },

    .{
        .name = "spell",
        .short_name = null,
        .js_name = "spell",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .window,
    },

    .{
        .name = "foldcolumn",
        .short_name = "fdc",
        .js_name = "foldColumn",
        .type = .string,
        .default = .{ .string = "0" }, // "0" to "12" or "auto"
        .scope = .window,
    },

    .{
        .name = "termguicolors",
        .short_name = "tgc",
        .js_name = "termGuiColors",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "background",
        .short_name = "bg",
        .js_name = "background",
        .type = .string,
        .default = .{ .string = "dark" }, // "light" or "dark"
        .scope = .global,
    },

    .{
        .name = "showmatch",
        .short_name = "sm",
        .js_name = "showMatch",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    // ========== Editing Options ==========

    .{
        .name = "tabstop",
        .short_name = "ts",
        .js_name = "tabStop",
        .type = .number,
        .default = .{ .number = 8 },
        .scope = .buffer,
    },

    .{
        .name = "shiftwidth",
        .short_name = "sw",
        .js_name = "shiftWidth",
        .type = .number,
        .default = .{ .number = 8 },
        .scope = .buffer,
    },

    .{
        .name = "expandtab",
        .short_name = "et",
        .js_name = "expandTab",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "autoindent",
        .short_name = "ai",
        .js_name = "autoIndent",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "smartindent",
        .short_name = "si",
        .js_name = "smartIndent",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "textwidth",
        .short_name = "tw",
        .js_name = "textWidth",
        .type = .number,
        .default = .{ .number = 0 },
        .scope = .buffer,
    },

    .{
        .name = "softtabstop",
        .short_name = "sts",
        .js_name = "softTabStop",
        .type = .number,
        .default = .{ .number = 0 }, // 0=off, negative=use shiftwidth
        .scope = .buffer,
    },

    .{
        .name = "smarttab",
        .short_name = "sta",
        .js_name = "smartTab",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "backspace",
        .short_name = "bs",
        .js_name = "backspace",
        .type = .string,
        .default = .{ .string = "indent,eol,start" }, // Neovim default
        .scope = .global,
    },

    .{
        .name = "formatoptions",
        .short_name = "fo",
        .js_name = "formatOptions",
        .type = .string,
        .default = .{ .string = "tcqj" }, // Neovim default
        .scope = .buffer,
    },

    .{
        .name = "completeopt",
        .short_name = "cot",
        .js_name = "completeOpt",
        .type = .string,
        .default = .{ .string = "menu,preview" }, // Neovim default: "menu,preview"
        .scope = .global,
    },

    .{
        .name = "virtualedit",
        .short_name = "ve",
        .js_name = "virtualEdit",
        .type = .string,
        .default = .{ .string = "" }, // "", "block", "insert", "all", "onemore"
        .scope = .global,
    },

    .{
        .name = "modifiable",
        .short_name = "ma",
        .js_name = "modifiable",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .buffer,
    },

    .{
        .name = "readonly",
        .short_name = "ro",
        .js_name = "readOnly",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    // ========== Behavior Options ==========

    .{
        .name = "mouse",
        .short_name = null,
        .js_name = "mouse",
        .type = .string,
        .default = .{ .string = "" }, // "a" for all modes, "n" for normal, etc.
        .scope = .global,
    },

    .{
        .name = "clipboard",
        .short_name = "cb",
        .js_name = "clipboard",
        .type = .string,
        .default = .{ .string = "" }, // "unnamed", "unnamedplus", "unnamed,unnamedplus"
        .scope = .global,
    },

    .{
        .name = "undolevels",
        .short_name = "ul",
        .js_name = "undoLevels",
        .type = .number,
        .default = .{ .number = 1000 },
        .scope = .global,
    },

    .{
        .name = "timeout",
        .short_name = "to",
        .js_name = "timeout",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "timeoutlen",
        .short_name = "tm",
        .js_name = "timeoutLen",
        .type = .number,
        .default = .{ .number = 1000 }, // milliseconds
        .scope = .global,
    },

    .{
        .name = "updatetime",
        .short_name = null,
        .js_name = "updateTime",
        .type = .number,
        .default = .{ .number = 4000 }, // milliseconds
        .scope = .global,
    },

    .{
        .name = "hidden",
        .short_name = "hid",
        .js_name = "hidden",
        .type = .boolean,
        .default = .{ .boolean = true }, // Neovim default (Vim: false)
        .scope = .global,
    },

    .{
        .name = "backup",
        .short_name = "bk",
        .js_name = "backup",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "writebackup",
        .short_name = "wb",
        .js_name = "writeBackup",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "swapfile",
        .short_name = "swf",
        .js_name = "swapFile",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .buffer,
    },

    .{
        .name = "undofile",
        .short_name = "udf",
        .js_name = "undoFile",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .buffer,
    },

    .{
        .name = "undodir",
        .short_name = "udir",
        .js_name = "undoDir",
        .type = .string,
        .default = .{ .string = "." }, // Vim default: ".", Neovim uses XDG_DATA_HOME
        .scope = .global,
    },

    .{
        .name = "splitright",
        .short_name = "spr",
        .js_name = "splitRight",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "splitbelow",
        .short_name = "sb",
        .js_name = "splitBelow",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "autoread",
        .short_name = "ar",
        .js_name = "autoRead",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "autowrite",
        .short_name = "aw",
        .js_name = "autoWrite",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "confirm",
        .short_name = "cf",
        .js_name = "confirm",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "startofline",
        .short_name = "sol",
        .js_name = "startOfLine",
        .type = .boolean,
        .default = .{ .boolean = false }, // Neovim default is off (preserves column)
        .scope = .global,
    },

    // ========== Search Options ==========

    .{
        .name = "ignorecase",
        .short_name = "ic",
        .js_name = "ignoreCase",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "smartcase",
        .short_name = "scs",
        .js_name = "smartCase",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "hlsearch",
        .short_name = "hls",
        .js_name = "hlSearch",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "incsearch",
        .short_name = "is",
        .js_name = "incSearch",
        .type = .boolean,
        .default = .{ .boolean = false },
        .scope = .global,
    },

    .{
        .name = "wrapscan",
        .short_name = "ws",
        .js_name = "wrapScan",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    // ========== UI Options ==========

    .{
        .name = "laststatus",
        .short_name = null,
        .js_name = "lastStatus",
        .type = .number,
        .default = .{ .number = 2 }, // 0=never, 1=only if multiple windows, 2=always, 3=global statusline
        .scope = .global,
    },

    .{
        .name = "showcmd",
        .short_name = "sc",
        .js_name = "showCmd",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "showmode",
        .short_name = "smd",
        .js_name = "showMode",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "ruler",
        .short_name = "ru",
        .js_name = "ruler",
        .type = .boolean,
        .default = .{ .boolean = true },
        .scope = .global,
    },

    .{
        .name = "cmdheight",
        .short_name = "ch",
        .js_name = "cmdHeight",
        .type = .number,
        .default = .{ .number = 1 },
        .scope = .global,
    },

    .{
        .name = "pumheight",
        .short_name = "ph",
        .js_name = "pumHeight",
        .type = .number,
        .default = .{ .number = 0 }, // 0=use available space
        .scope = .global,
    },

    .{
        .name = "winblend",
        .short_name = "winbl",
        .js_name = "winBlend",
        .type = .number,
        .default = .{ .number = 0 }, // 0-100 (0=opaque, 100=transparent)
        .scope = .window,
    },

    .{
        .name = "pumblend",
        .short_name = "pb",
        .js_name = "pumBlend",
        .type = .number,
        .default = .{ .number = 0 }, // 0-100 (0=opaque, 100=transparent)
        .scope = .global,
    },

    .{
        .name = "showtabline",
        .short_name = "stal",
        .js_name = "showTabLine",
        .type = .number,
        .default = .{ .number = 1 }, // 0=never, 1=only if 2+ tabs, 2=always
        .scope = .global,
    },

    .{
        .name = "wildmenu",
        .short_name = "wmnu",
        .js_name = "wildMenu",
        .type = .boolean,
        .default = .{ .boolean = true }, // Neovim default
        .scope = .global,
    },

    .{
        .name = "wildmode",
        .short_name = "wim",
        .js_name = "wildMode",
        .type = .string,
        .default = .{ .string = "full" }, // Neovim default
        .scope = .global,
    },
};

/// Get option metadata by name (returns null if not found)
/// Searches by: Vim name, short name, or JavaScript camelCase name
pub fn getOptionMeta(name: []const u8) ?OptionMeta {
    for (OPTIONS) |opt| {
        // Check Vim name (e.g., "tabstop")
        if (std.mem.eql(u8, opt.name, name)) {
            return opt;
        }
        // Check Vim short name (e.g., "ts")
        if (opt.short_name) |short| {
            if (std.mem.eql(u8, short, name)) {
                return opt;
            }
        }
        // Check JavaScript camelCase name (e.g., "tabStop")
        if (std.mem.eql(u8, opt.js_name, name)) {
            return opt;
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
            if (std.mem.eql(u8, meta.name, "foldcolumn")) {
                // Valid values: "0" through "12" or "auto"
                if (std.mem.eql(u8, s, "auto")) return true;
                if (s.len == 1) {
                    const digit = s[0];
                    return digit >= '0' and digit <= '9';
                }
                if (s.len == 2) {
                    return std.mem.eql(u8, s, "10") or
                        std.mem.eql(u8, s, "11") or
                        std.mem.eql(u8, s, "12");
                }
                return false;
            }
            if (std.mem.eql(u8, meta.name, "background")) {
                // Valid values: "light" or "dark"
                return std.mem.eql(u8, s, "light") or std.mem.eql(u8, s, "dark");
            }
            // Other string options are generally free-form
            return true;
        },
        .number => |n| {
            // Range validation for specific options
            if (std.mem.eql(u8, meta.name, "tabstop") or
                std.mem.eql(u8, meta.name, "shiftwidth"))
            {
                return n > 0 and n <= 20; // Reasonable tab width range (must be positive)
            }
            if (std.mem.eql(u8, meta.name, "softtabstop")) {
                return n >= 0 and n <= 20; // 0=off, negative would use shiftwidth (but we don't allow negative)
            }
            if (std.mem.eql(u8, meta.name, "laststatus")) {
                return n >= 0 and n <= 3;
            }
            if (std.mem.eql(u8, meta.name, "conceallevel")) {
                return n >= 0 and n <= 3; // 0=show, 1=replace, 2=hide, 3=completely hide
            }
            if (std.mem.eql(u8, meta.name, "cmdheight")) {
                return n >= 0 and n <= 10; // Reasonable command line height
            }
            if (std.mem.eql(u8, meta.name, "winblend") or
                std.mem.eql(u8, meta.name, "pumblend"))
            {
                return n >= 0 and n <= 100; // 0=opaque, 100=transparent
            }
            if (std.mem.eql(u8, meta.name, "showtabline")) {
                return n >= 0 and n <= 2; // 0=never, 1=auto, 2=always
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

test "getOptionMeta: find by JavaScript camelCase name" {
    const meta = getOptionMeta("tabStop"); // JavaScript name instead of "tabstop"
    try std.testing.expect(meta != null);
    try std.testing.expectEqualStrings("tabstop", meta.?.name); // Internal name is still Vim-style
    try std.testing.expectEqualStrings("tabStop", meta.?.js_name);
}

test "getOptionMeta: camelCase for multi-word options" {
    // Test relativeNumber (camelCase) instead of relativenumber (Vim style)
    const meta1 = getOptionMeta("relativeNumber");
    try std.testing.expect(meta1 != null);
    try std.testing.expectEqualStrings("relativenumber", meta1.?.name);

    // Test termGuiColors (camelCase) instead of termguicolors (Vim style)
    const meta2 = getOptionMeta("termGuiColors");
    try std.testing.expect(meta2 != null);
    try std.testing.expectEqualStrings("termguicolors", meta2.?.name);

    // Test splitRight (camelCase) instead of splitright (Vim style)
    const meta3 = getOptionMeta("splitRight");
    try std.testing.expect(meta3 != null);
    try std.testing.expectEqualStrings("splitright", meta3.?.name);
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
