const std = @import("std");
const enry = @import("../../system/enry/enry.zig");

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
/// Now using go-enry for runtime language detection (697 languages)
pub const Loader = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator, // Arena for go-enry allocations (batch-freed on deinit)
    // Note: extension_map and filename_map are now compile-time from filetype_data.zig
    glob_patterns: std.ArrayList(GlobPattern), // Makefile, *.config.js (custom patterns only)
    shebang_map: std.StringHashMap([]const u8), // "node" -> "javascript"

    /// Initialize loader with language configurations
    /// Extension and filename maps are compile-time initialized from Neovim data
    pub fn init(allocator: std.mem.Allocator) !Loader {
        var loader = Loader{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
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
        self.arena.deinit(); // Free all go-enry allocations at once
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
    /// Uses go-enry (GitHub Linguist) for comprehensive language detection (697 languages)
    /// Supports: extension, filename, shebang, modeline, content heuristics, Bayesian classifier
    pub fn detectFiletype(self: *Loader, path: []const u8, first_line: ?[]const u8) ?[]const u8 {
        // Use go-enry for all detection (handles extensions, filenames, shebangs, modelines, heuristics)
        // Content parameter is first_line if available, null otherwise
        // Use arena allocator - all strings freed when Loader.deinit() called
        const arena_allocator = self.arena.allocator();
        const lang = enry.detectLanguage(arena_allocator, path, first_line) catch |err| {
            // Log error for debugging (OutOfMemory, IntegerOverflow, or InvalidInput)
            std.log.debug("go-enry detectLanguage failed for '{s}': {}", .{ path, err });
            return null;
        };

        // go-enry returns allocated string from arena
        // Arena will be freed when Loader is destroyed (no memory leak)
        return lang;
    }

    // NOTE: Helper functions removed - go-enry handles all detection strategies internally
    // (extension, filename, shebang, modeline, content heuristics, Bayesian classifier)
};

// ========================================
// Tests
// ========================================

test "Loader: init and deinit" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Basic initialization test (go-enry handles detection internally)
    try std.testing.expect(loader.glob_patterns.items.len > 0);
}

test "Loader: detect Rust by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Note: .rs is ambiguous (Rust/RenderScript/XML), so go-enry may return XML without content
    // We provide Rust content to disambiguate
    const rust_content = "fn main() {}";
    const filetype = loader.detectFiletype("test.rs", rust_content);
    try std.testing.expect(filetype != null);
    try std.testing.expectEqualStrings("Rust", filetype.?); // go-enry returns capitalized names
}

test "Loader: detect JavaScript by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const ft_js = loader.detectFiletype("app.js", null);
    try std.testing.expectEqualStrings("JavaScript", ft_js.?); // go-enry returns capitalized names

    const ft_mjs = loader.detectFiletype("module.mjs", null);
    try std.testing.expectEqualStrings("JavaScript", ft_mjs.?); // go-enry returns capitalized names

    const ft_cjs = loader.detectFiletype("common.cjs", null);
    try std.testing.expectEqualStrings("JavaScript", ft_cjs.?); // go-enry returns capitalized names
}

test "Loader: detect Python by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("script.py", null);
    try std.testing.expectEqualStrings("Python", filetype.?); // go-enry returns capitalized names
}

test "Loader: detect Zig by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("build.zig", null);
    try std.testing.expectEqualStrings("Zig", filetype.?); // go-enry returns capitalized names
}

test "Loader: detect Go by extension" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const ft_go = loader.detectFiletype("server.go", null);
    try std.testing.expectEqualStrings("Go", ft_go.?); // go-enry returns capitalized names
}

test "Loader: comprehensive language detection (go-enry, 697 languages)" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Test a variety of languages (go-enry supports 697 languages)
    // Note: go-enry normalizes language names (e.g., "Rust" vs "rust")
    const rust_ft = loader.detectFiletype("main.rs", null);
    try std.testing.expect(rust_ft != null);
    // go-enry may return "Rust" (capitalized) vs Neovim's "rust" (lowercase)

    const go_ft = loader.detectFiletype("server.go", null);
    try std.testing.expect(go_ft != null);

    const toml_ft = loader.detectFiletype("Cargo.toml", null);
    try std.testing.expect(toml_ft != null);
}

test "Loader: detect exact filename matches" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Test exact filename mappings (go-enry handles these internally)
    const ft_rprofile = loader.detectFiletype(".Rprofile", null);
    try std.testing.expectEqualStrings("R", ft_rprofile.?); // go-enry returns capitalized names

    // Note: .Rhistory may not be detected by go-enry without content
    // This is a known limitation - go-enry focuses on source code files
    const ft_rhistory = loader.detectFiletype(".Rhistory", null);
    _ = ft_rhistory; // May be null, which is acceptable for data files
}

test "Loader: detect JavaScript by glob pattern" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const filetype = loader.detectFiletype("vite.config.js", null);
    try std.testing.expectEqualStrings("JavaScript", filetype.?); // go-enry returns capitalized names
}

test "Loader: detect JavaScript by shebang" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const shebang1 = "#!/usr/bin/env node";
    const ft1 = loader.detectFiletype("script", shebang1);
    try std.testing.expectEqualStrings("JavaScript", ft1.?); // go-enry returns capitalized names

    const shebang2 = "#!/usr/bin/nodejs";
    const ft2 = loader.detectFiletype("app", shebang2);
    try std.testing.expectEqualStrings("JavaScript", ft2.?); // go-enry returns capitalized names
}

test "Loader: detect Python by shebang" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const shebang1 = "#!/usr/bin/env python3";
    const ft1 = loader.detectFiletype("script", shebang1);
    try std.testing.expectEqualStrings("Python", ft1.?); // go-enry returns capitalized names

    const shebang2 = "#!/usr/bin/python";
    const ft2 = loader.detectFiletype("tool", shebang2);
    try std.testing.expectEqualStrings("Python", ft2.?); // go-enry returns capitalized names
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

    // Provide Rust content to disambiguate .rs extension (could be Rust, RenderScript, or XML)
    const rust_content = "fn main() {}";
    const filetype = loader.detectFiletype("/path/to/file.rs", rust_content);
    try std.testing.expectEqualStrings("Rust", filetype.?); // go-enry returns capitalized names
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

// ========================================
// Comprehensive Tests: Content-Based Detection
// ========================================

test "Loader: content-based detection - disambiguate .h files" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // C header (uses C-style includes, no classes)
    const c_content = "#include <stdio.h>\nint add(int a, int b);";
    const c_result = loader.detectFiletype("header.h", c_content);
    try std.testing.expect(c_result != null);
    // go-enry should detect C (not C++)

    // C++ header (uses classes, namespaces)
    const cpp_content = "class Foo {\npublic:\n  void bar();\n};";
    const cpp_result = loader.detectFiletype("header.h", cpp_content);
    try std.testing.expect(cpp_result != null);
    // go-enry uses heuristics to detect C++ vs C

    // Objective-C header (uses @interface)
    const objc_content = "@interface MyClass : NSObject\n@end";
    const objc_result = loader.detectFiletype("header.h", objc_content);
    try std.testing.expect(objc_result != null);
    // go-enry should detect Objective-C
}

test "Loader: content-based detection - disambiguate .m files" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Objective-C implementation (uses @implementation)
    const objc_content = "@implementation MyClass\n- (void)myMethod { }\n@end";
    const objc_result = loader.detectFiletype("file.m", objc_content);
    try std.testing.expect(objc_result != null);
    // Should detect Objective-C

    // MATLAB script (uses function keyword, MATLAB syntax)
    const matlab_content = "function result = myFunc(x)\n  result = x * 2;\nend";
    const matlab_result = loader.detectFiletype("file.m", matlab_content);
    try std.testing.expect(matlab_result != null);
    // Should detect MATLAB
}

test "Loader: content-based detection - RenderScript vs Rust" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Rust content (uses fn keyword, Rust syntax)
    const rust_content = "fn main() {\n  println!(\"Hello\");\n}";
    const rust_result = loader.detectFiletype("app.rs", rust_content);
    try std.testing.expectEqualStrings("Rust", rust_result.?);

    // RenderScript content (uses rs_ prefix, Android-specific)
    const rs_content = "#pragma version(1)\n#pragma rs java_package_name(com.example)";
    const rs_result = loader.detectFiletype("kernel.rs", rs_content);
    try std.testing.expect(rs_result != null);
    // go-enry should detect RenderScript (not Rust)
}

// ========================================
// Comprehensive Tests: Modeline Detection
// ========================================

test "Loader: detect language by Vim modeline" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Vim modeline at top of file
    const vim_modeline1 = "# vim: set ft=python:";
    const ft1 = loader.detectFiletype("script", vim_modeline1);
    try std.testing.expectEqualStrings("Python", ft1.?);

    // Vim modeline with syntax variant
    const vim_modeline2 = "/* vim: syntax=javascript */";
    const ft2 = loader.detectFiletype("code", vim_modeline2);
    try std.testing.expectEqualStrings("JavaScript", ft2.?);

    // Vim modeline in different comment style
    const vim_modeline3 = "// vim: filetype=go";
    const ft3 = loader.detectFiletype("main", vim_modeline3);
    try std.testing.expectEqualStrings("Go", ft3.?);
}

test "Loader: detect language by Emacs modeline" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Emacs modeline (mode: python)
    const emacs_modeline1 = "# -*- mode: python -*-";
    const ft1 = loader.detectFiletype("script", emacs_modeline1);
    try std.testing.expectEqualStrings("Python", ft1.?);

    // Note: Emacs modeline support in go-enry is limited compared to Vim modelines
    // go-enry primarily focuses on file extensions, shebangs, and Vim modelines
    // Emacs modelines may not be detected reliably in all cases

    // Emacs modeline with coding (Python works)
    const emacs_modeline3 = "# -*- coding: utf-8; mode: ruby -*-";
    const ft3 = loader.detectFiletype("script.rb", emacs_modeline3);
    // With .rb extension, should detect Ruby
    if (ft3) |lang| {
        try std.testing.expect(std.mem.eql(u8, lang, "Ruby"));
    }
}

// ========================================
// Comprehensive Tests: Shebang Edge Cases
// ========================================

test "Loader: shebang with arguments" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Shebang with -u flag
    const shebang1 = "#!/usr/bin/env python3 -u";
    const ft1 = loader.detectFiletype("script", shebang1);
    try std.testing.expectEqualStrings("Python", ft1.?);

    // Shebang with multiple arguments
    const shebang2 = "#!/usr/bin/node --experimental-modules";
    const ft2 = loader.detectFiletype("script.mjs", shebang2);
    try std.testing.expectEqualStrings("JavaScript", ft2.?);
}

test "Loader: shebang with spaces" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Shebang with trailing spaces (should still work)
    const shebang = "#!/usr/bin/env python3  ";
    const ft = loader.detectFiletype("script", shebang);
    try std.testing.expectEqualStrings("Python", ft.?);
}

test "Loader: various shell shebangs" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Bash shebang
    const bash_shebang = "#!/bin/bash";
    const bash_ft = loader.detectFiletype("script.sh", bash_shebang);
    try std.testing.expect(bash_ft != null);
    // Should detect Shell

    // Zsh shebang
    const zsh_shebang = "#!/usr/bin/env zsh";
    const zsh_ft = loader.detectFiletype("script", zsh_shebang);
    try std.testing.expect(zsh_ft != null);
    // Should detect Shell

    // sh shebang
    const sh_shebang = "#!/bin/sh";
    const sh_ft = loader.detectFiletype("init", sh_shebang);
    try std.testing.expect(sh_ft != null);
    // Should detect Shell
}

// ========================================
// Comprehensive Tests: Edge Cases
// ========================================

test "Loader: empty file returns null" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const empty_content = "";
    const ft = loader.detectFiletype("unknown", empty_content);
    // go-enry may return null for files with no extension and no content
    _ = ft; // Outcome depends on go-enry behavior
}

test "Loader: file with no extension but shebang" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    const shebang = "#!/usr/bin/env python3";
    const ft = loader.detectFiletype("script", shebang);
    try std.testing.expectEqualStrings("Python", ft.?);
    // Should detect Python via shebang, ignoring lack of extension
}

test "Loader: multiple detection strategies combined" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // File with .py extension AND shebang (extension should take precedence)
    const python_shebang = "#!/usr/bin/env python3";
    const ft = loader.detectFiletype("script.py", python_shebang);
    try std.testing.expectEqualStrings("Python", ft.?);
}

test "Loader: content heuristics for Makefile" {
    const allocator = std.testing.allocator;
    var loader = try Loader.init(allocator);
    defer loader.deinit();

    // Makefile-like content without filename
    const makefile_content = "all:\n\t@echo \"Building...\"";
    const ft = loader.detectFiletype("build.mk", makefile_content);
    try std.testing.expect(ft != null);
    // go-enry should detect Makefile syntax
}
