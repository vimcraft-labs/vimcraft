/// High-level Zig wrapper for go-enry language detection
/// Provides clean interface to GitHub Linguist-based language detection (697 languages)
const std = @import("std");
const c_api = @import("c_api.zig");

/// Detect programming language from filename and optional content
///
/// Strategy (applied in sequence):
/// 1. Extension matching (e.g., ".rs" → Rust/RenderScript, ambiguous)
/// 2. Filename matching (e.g., "Makefile" → Makefile, unambiguous)
/// 3. Shebang detection (e.g., "#!/usr/bin/env python" → Python)
/// 4. Modeline parsing (e.g., "# vim: set ft=python:" → Python)
/// 5. Content heuristics (regexp-based disambiguation for ambiguous extensions)
/// 6. Bayesian classifier (last resort for remaining ambiguity)
///
/// Returns:
/// - Allocated string with language name (caller must free)
/// - null if language cannot be determined
///
/// Examples:
/// - detectLanguage(allocator, "main.c", null) → "C"
/// - detectLanguage(allocator, "Makefile", null) → "Makefile"
/// - detectLanguage(allocator, "test.rs", "fn main() {}") → "Rust" (disambiguated from RenderScript)
/// - detectLanguage(allocator, "script", "#!/bin/bash") → "Shell" (shebang detection)
pub fn detectLanguage(
    allocator: std.mem.Allocator,
    filename: []const u8,
    content: ?[]const u8,
) c_api.EnryError!?[]const u8 {
    // Convert Zig strings to Go strings (validate input sizes)
    const go_filename = try c_api.makeGoString(filename);
    const go_content = if (content) |c|
        try c_api.makeGoSlice(c)
    else
        c_api.GoSlice{
            .data = null,
            .len = 0,
            .cap = 0,
        };

    // Call go-enry's GetLanguage (uses all strategies)
    const result = c_api.GetLanguage(go_filename, go_content);

    // Convert result to Zig string (allocate copy, propagate errors)
    return c_api.goStringToZig(allocator, result);
}

/// Detect language by extension only (fast, but may be ambiguous)
///
/// Returns:
/// - .language: Allocated string with language name (caller must free)
/// - .safe: true if unambiguous, false if multiple languages share this extension
///
/// Example:
/// - detectByExtension(allocator, "main.c") → { .language = "C", .safe = true }
/// - detectByExtension(allocator, "test.rs") → { .language = "RenderScript", .safe = false }
pub fn detectByExtension(
    allocator: std.mem.Allocator,
    filename: []const u8,
) c_api.EnryError!struct { language: ?[]const u8, safe: bool } {
    const go_filename = try c_api.makeGoString(filename);
    const result = c_api.GetLanguageByExtension(go_filename);

    return .{
        .language = try c_api.goStringToZig(allocator, result.r0),
        .safe = result.r1 != 0,
    };
}

/// Detect language by exact filename match (e.g., "Makefile", ".gitignore")
///
/// Returns:
/// - .language: Allocated string with language name (caller must free)
/// - .safe: true if match found
///
/// Example:
/// - detectByFilename(allocator, "Makefile") → { .language = "Makefile", .safe = true }
/// - detectByFilename(allocator, "random.txt") → { .language = null, .safe = false }
pub fn detectByFilename(
    allocator: std.mem.Allocator,
    filename: []const u8,
) c_api.EnryError!struct { language: ?[]const u8, safe: bool } {
    const go_filename = try c_api.makeGoString(filename);
    const result = c_api.GetLanguageByFilename(go_filename);

    return .{
        .language = try c_api.goStringToZig(allocator, result.r0),
        .safe = result.r1 != 0,
    };
}

/// Detect language by shebang line (first line of script)
///
/// Returns:
/// - .language: Allocated string with language name (caller must free)
/// - .safe: true if shebang matched
///
/// Example:
/// - detectByShebang(allocator, "#!/usr/bin/env python3\n") → { .language = "Python", .safe = true }
pub fn detectByShebang(
    allocator: std.mem.Allocator,
    content: []const u8,
) c_api.EnryError!struct { language: ?[]const u8, safe: bool } {
    const go_content = try c_api.makeGoSlice(content);
    const result = c_api.GetLanguageByShebang(go_content);

    return .{
        .language = try c_api.goStringToZig(allocator, result.r0),
        .safe = result.r1 != 0,
    };
}

/// Detect language by modeline (Vim/Emacs editor hints)
///
/// Returns:
/// - .language: Allocated string with language name (caller must free)
/// - .safe: true if modeline matched
///
/// Example:
/// - detectByModeline(allocator, "# vim: set ft=python:\n") → { .language = "Python", .safe = true }
pub fn detectByModeline(
    allocator: std.mem.Allocator,
    content: []const u8,
) c_api.EnryError!struct { language: ?[]const u8, safe: bool } {
    const go_content = try c_api.makeGoSlice(content);
    const result = c_api.GetLanguageByModeline(go_content);

    return .{
        .language = try c_api.goStringToZig(allocator, result.r0),
        .safe = result.r1 != 0,
    };
}

/// Detect language by content heuristics (regexp-based disambiguation)
///
/// Used to disambiguate ambiguous extensions (e.g., .h for C vs C++ vs Objective-C)
///
/// Returns:
/// - .language: Allocated string with language name (caller must free)
/// - .safe: true if heuristic matched
///
/// Example:
/// - detectByContent(allocator, "test.h", "#include <iostream>\nclass Foo {};") → { .language = "C++", .safe = true }
pub fn detectByContent(
    allocator: std.mem.Allocator,
    filename: []const u8,
    content: []const u8,
) c_api.EnryError!struct { language: ?[]const u8, safe: bool } {
    const go_filename = try c_api.makeGoString(filename);
    const go_content = try c_api.makeGoSlice(content);
    const result = c_api.GetLanguageByContent(go_filename, go_content);

    return .{
        .language = try c_api.goStringToZig(allocator, result.r0),
        .safe = result.r1 != 0,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "disambiguate .rs with Rust content" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test 1: Extension only (ambiguous)
    const ext_result = try detectByExtension(allocator, "main.rs");
    defer if (ext_result.language) |l| allocator.free(l);
    
    // Extension is ambiguous (Rust vs RenderScript)
    try testing.expect(!ext_result.safe);
    std.debug.print("\n.rs extension only: {s} (safe={}))\n", .{
        ext_result.language orelse "null",
        ext_result.safe,
    });

    // Test 2: Full detection with Rust content (should disambiguate)
    const rust_content = "fn main() {\n    println!(\"Hello\");\n}\n";
    const lang = try detectLanguage(allocator, "main.rs", rust_content);
    defer if (lang) |l| allocator.free(l);

    std.debug.print(".rs with Rust content: {s}\n", .{lang orelse "null"});
    try testing.expect(lang != null);
    try testing.expectEqualStrings("Rust", lang.?);

    // Test 3: Full detection with XML content (should detect mismatch)
    const xml_content = "<?xml version=\"1.0\"?>\n<root></root>\n";
    const xml_lang = try detectLanguage(allocator, "main.rs", xml_content);
    defer if (xml_lang) |l| allocator.free(l);

    std.debug.print(".rs with XML content: {s}\n", .{xml_lang orelse "null"});
    // go-enry should detect this is NOT Rust
}
