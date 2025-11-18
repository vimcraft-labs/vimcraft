const std = @import("std");
const filetype_data = @import("filetype_data");

/// Language configuration metadata
pub const LanguageConfig = struct {
    name: []const u8, // "rust"
    scope: []const u8, // "source.rust" (for tree-sitter)
    extensions: []const []const u8, // [".rs"]
    globs: []const []const u8, // ["Makefile", "*.config.js"]
    shebangs: []const []const u8, // ["node", "python3"]
    comment_token: []const u8, // "//"
};

/// Glob pattern matcher
pub const GlobPattern = struct {
    pattern: []const u8, // "Makefile" or "*.config.js"
    language: []const u8, // "make" or "javascript"

    /// Check if path matches this glob pattern
    pub fn matches(self: GlobPattern, path: []const u8) bool {
        // Extract basename for matching
        const basename = std.fs.path.basename(path);

        // Exact match (e.g., "Makefile")
        if (std.mem.eql(u8, self.pattern, basename)) {
            return true;
        }

        // Wildcard match (e.g., "*.config.js")
        if (std.mem.indexOf(u8, self.pattern, "*")) |star_pos| {
            const suffix = self.pattern[star_pos + 1 ..];
            if (std.mem.endsWith(u8, basename, suffix)) {
                return true;
            }
        }

        return false;
    }
};

/// Tree-sitter language loader and filetype detector
/// Now using Neovim's comprehensive filetype database (1,405+ mappings)
pub const Loader = struct {
    allocator: std.mem.Allocator,
    // Note: extension_map and filename_map are now compile-time from filetype_data.zig
    glob_patterns: std.ArrayList(GlobPattern), // Makefile, *.config.js (custom patterns only)
    shebang_map: std.StringHashMap([]const u8), // "node" -> "javascript"

    /// Initialize loader with language configurations
    /// Extension and filename maps are compile-time initialized from Neovim data
    pub fn init(allocator: std.mem.Allocator) !Loader {
        var loader = Loader{
            .allocator = allocator,
            .glob_patterns = .{
                .items = &[_]GlobPattern{},
                .capacity = 0,
            },
            .shebang_map = std.StringHashMap([]const u8).init(allocator),
        };

        // Load additional language configurations (glob patterns, shebangs)
        try loader.loadLanguages();

        return loader;
    }

    /// Clean up resources
    pub fn deinit(self: *Loader) void {
        // Note: extension_map and filename_map are compile-time, no cleanup needed
        self.glob_patterns.deinit(self.allocator);
        self.shebang_map.deinit();
    }

    /// Load additional language configurations
    /// Note: Extensions and exact filenames come from Neovim's compile-time data
    /// This function only registers glob patterns and shebangs
    fn loadLanguages(self: *Loader) !void {
        // JavaScript shebangs
        try self.registerShebangs(&.{ "node", "nodejs" }, "javascript");

        // Python shebangs
        try self.registerShebangs(&.{ "python", "python3", "python2" }, "python");

        // Shell shebangs
        try self.registerShebangs(&.{ "sh", "bash", "dash", "zsh" }, "sh");

        // Perl shebangs
        try self.registerShebangs(&.{ "perl", "perl5" }, "perl");

        // Ruby shebangs
        try self.registerShebangs(&.{ "ruby" }, "ruby");

        // Custom glob patterns (for advanced matching)
        try self.registerGlob("*.config.js", "javascript");
        try self.registerGlob("*.test.js", "javascript");
        try self.registerGlob("*.spec.js", "javascript");
    }

    // Note: registerExtensions() removed - extensions come from Neovim's compile-time data

    /// Register glob pattern for a language
    fn registerGlob(self: *Loader, pattern: []const u8, language: []const u8) !void {
        try self.glob_patterns.append(self.allocator, .{
            .pattern = pattern,
            .language = language,
        });
    }

    /// Register shebang patterns for a language
    fn registerShebangs(self: *Loader, shebangs: []const []const u8, language: []const u8) !void {
        for (shebangs) |shebang| {
            try self.shebang_map.put(shebang, language);
        }
    }

    /// Detect filetype from path and optional first line
    /// Four-tier detection: extension -> exact filename -> glob -> shebang
    /// Uses Neovim's comprehensive database (1,405+ mappings)
    pub fn detectFiletype(self: *Loader, path: []const u8, first_line: ?[]const u8) ?[]const u8 {
        // Tier 1: Extension lookup (O(1), compile-time map, 1034 mappings)
        if (self.detectByExtension(path)) |lang| {
            return lang;
        }

        // Tier 2: Exact filename lookup (O(1), compile-time map, 371 mappings)
        if (self.detectByFilename(path)) |lang| {
            return lang;
        }

        // Tier 3: Glob pattern matching (custom patterns)
        if (self.detectByGlob(path)) |lang| {
            return lang;
        }

        // Tier 4: Shebang inspection (if first line available)
        if (first_line) |line| {
            if (self.detectByShebang(line)) |lang| {
                return lang;
            }
        }

        return null; // Unknown filetype
    }

    /// Detect filetype by file extension (uses Neovim's compile-time map)
    fn detectByExtension(_: *Loader, path: []const u8) ?[]const u8 {
        const ext = std.fs.path.extension(path);
        if (ext.len == 0) return null;

        return filetype_data.extension_map.get(ext);
    }

    /// Detect filetype by exact filename match (uses Neovim's compile-time map)
    fn detectByFilename(_: *Loader, path: []const u8) ?[]const u8 {
        const basename = std.fs.path.basename(path);

        // Try exact filename match first
        if (filetype_data.filename_map.get(basename)) |ft| {
            return ft;
        }

        // Try full path match (for paths like /etc/passwd)
        if (filetype_data.filename_map.get(path)) |ft| {
            return ft;
        }

        return null;
    }

    /// Detect filetype by glob pattern matching
    fn detectByGlob(self: *Loader, path: []const u8) ?[]const u8 {
        for (self.glob_patterns.items) |glob| {
            if (glob.matches(path)) {
                return glob.language;
            }
        }
        return null;
    }

    /// Detect filetype by shebang line (#!/usr/bin/env node)
    fn detectByShebang(self: *Loader, line: []const u8) ?[]const u8 {
        // Check if line starts with shebang
        if (!std.mem.startsWith(u8, line, "#!")) {
            return null;
        }

        // Extract shebang content (skip "#!")
        const shebang_content = std.mem.trim(u8, line[2..], " \t\r\n");

        // Common patterns:
        // #!/usr/bin/env node
        // #!/usr/bin/python3
        // #!/bin/bash

        // Check for /usr/bin/env pattern
        if (std.mem.indexOf(u8, shebang_content, "/env ")) |env_pos| {
            const interpreter = std.mem.trim(u8, shebang_content[env_pos + 5 ..], " \t\r\n");
            if (self.shebang_map.get(interpreter)) |lang| {
                return lang;
            }
        }

        // Check for direct path pattern (/usr/bin/python3)
        if (std.mem.lastIndexOf(u8, shebang_content, "/")) |slash_pos| {
            const interpreter = std.mem.trim(u8, shebang_content[slash_pos + 1 ..], " \t\r\n");
            if (self.shebang_map.get(interpreter)) |lang| {
                return lang;
            }
        }

        return null;
    }
};

// ========================================
// Tests
// ========================================

test "Loader: init and deinit" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Verify compile-time data is available
    try std.testing.expect(filetype_data.stats.total_mappings > 0);
    try std.testing.expect(loader.glob_patterns.items.len > 0);
}

test "Loader: detect Rust by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("test.rs", null);
    try std.testing.expect(filetype != null);
    try std.testing.expectEqualStrings("rust", filetype.?);
}

test "Loader: detect JavaScript by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const ft_js = loader.detectFiletype("app.js", null);
    try std.testing.expectEqualStrings("javascript", ft_js.?);

    const ft_mjs = loader.detectFiletype("module.mjs", null);
    try std.testing.expectEqualStrings("javascript", ft_mjs.?);

    const ft_cjs = loader.detectFiletype("common.cjs", null);
    try std.testing.expectEqualStrings("javascript", ft_cjs.?);
}

test "Loader: detect Python by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("script.py", null);
    try std.testing.expectEqualStrings("python", filetype.?);
}

test "Loader: detect Zig by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("build.zig", null);
    try std.testing.expectEqualStrings("zig", filetype.?);
}

test "Loader: detect Go by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const ft_go = loader.detectFiletype("server.go", null);
    try std.testing.expectEqualStrings("go", ft_go.?);
}

test "Loader: comprehensive Neovim coverage" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Verify we have Neovim's comprehensive mappings (1,405+ total)
    try std.testing.expect(filetype_data.stats.extension_count == 1034);
    try std.testing.expect(filetype_data.stats.filename_count == 371);
    try std.testing.expect(filetype_data.stats.total_mappings == 1405);

    // Test a variety of extensions from Neovim's database
    try std.testing.expectEqualStrings("rust", loader.detectFiletype("main.rs", null).?);
    try std.testing.expectEqualStrings("go", loader.detectFiletype("server.go", null).?);
    try std.testing.expectEqualStrings("ruby", loader.detectFiletype("app.rb", null).?);
    try std.testing.expectEqualStrings("lua", loader.detectFiletype("init.lua", null).?);
    try std.testing.expectEqualStrings("toml", loader.detectFiletype("Cargo.toml", null).?);
}

test "Loader: detect exact filename matches" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Test Neovim's exact filename mappings (371 total, Tier 2 detection)
    // Note: Files with extensions may match extension first (like .am -> elf)
    const ft_rprofile = loader.detectFiletype(".Rprofile", null);
    try std.testing.expectEqualStrings("r", ft_rprofile.?);

    const ft_rhistory = loader.detectFiletype(".Rhistory", null);
    try std.testing.expectEqualStrings("r", ft_rhistory.?);
}

test "Loader: detect JavaScript by glob pattern" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("vite.config.js", null);
    try std.testing.expectEqualStrings("javascript", filetype.?);
}

test "Loader: detect JavaScript by shebang" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const shebang1 = "#!/usr/bin/env node";
    const ft1 = loader.detectFiletype("script", shebang1);
    try std.testing.expectEqualStrings("javascript", ft1.?);

    const shebang2 = "#!/usr/bin/nodejs";
    const ft2 = loader.detectFiletype("app", shebang2);
    try std.testing.expectEqualStrings("javascript", ft2.?);
}

test "Loader: detect Python by shebang" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const shebang1 = "#!/usr/bin/env python3";
    const ft1 = loader.detectFiletype("script", shebang1);
    try std.testing.expectEqualStrings("python", ft1.?);

    const shebang2 = "#!/usr/bin/python";
    const ft2 = loader.detectFiletype("tool", shebang2);
    try std.testing.expectEqualStrings("python", ft2.?);
}

test "Loader: unknown filetype returns null" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("unknown.xyz", null);
    try std.testing.expect(filetype == null);
}

test "Loader: path with directory" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("/path/to/file.rs", null);
    try std.testing.expectEqualStrings("rust", filetype.?);
}

test "GlobPattern: exact match" {
    const glob = GlobPattern{
        .pattern = "Makefile",
        .language = "make",
    };

    try std.testing.expect(glob.matches("Makefile"));
    try std.testing.expect(glob.matches("/path/to/Makefile"));
    try std.testing.expect(!glob.matches("Makefile.am"));
}

test "GlobPattern: wildcard match" {
    const glob = GlobPattern{
        .pattern = "*.config.js",
        .language = "javascript",
    };

    try std.testing.expect(glob.matches("vite.config.js"));
    try std.testing.expect(glob.matches("/path/to/webpack.config.js"));
    try std.testing.expect(!glob.matches("config.ts"));
}
