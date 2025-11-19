/// Tree-sitter Language Registration
/// Provides getLanguage() for bundled parsers (C, Zig, JS/TS, Markdown)
///
/// Bundled Languages:
/// - C (vendor/tree-sitter-c)
/// - Zig (vendor/tree-sitter-zig)
/// - JavaScript (vendor/tree-sitter-javascript)
/// - TypeScript (vendor/tree-sitter-typescript/typescript)
/// - TSX (vendor/tree-sitter-typescript/tsx)
/// - Markdown (vendor/tree-sitter-markdown/tree-sitter-markdown)
/// - Markdown Inline (vendor/tree-sitter-markdown/tree-sitter-markdown-inline)
///
/// Usage:
///   const Parser = @import("parser.zig").Parser;
///   const languages = @import("languages.zig");
///
///   var parser = try Parser.init(allocator);
///   defer parser.deinit();
///
///   const zig_lang = languages.getLanguage("zig").?;
///   try parser.setLanguage(zig_lang);
///
///   const tree = try parser.parseString(null, "const x: u32 = 42;");
///   defer c.ts_tree_delete(tree);
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;

// External language functions (defined in vendor/tree-sitter-X/src/parser.c)
// Each parser exports tree_sitter_<lang>() returning const TSLanguage*
extern fn tree_sitter_c() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_zig() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_javascript() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_typescript() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_tsx() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_markdown() callconv(.c) *const c.TSLanguage;
extern fn tree_sitter_markdown_inline() callconv(.c) *const c.TSLanguage;

/// Get language parser by name
/// Returns null if language not bundled
///
/// Supported languages:
/// - "c"
/// - "zig"
/// - "javascript"
/// - "typescript"
/// - "tsx"
/// - "markdown"
/// - "markdown_inline"
pub fn getLanguage(name: []const u8) ?*const c.TSLanguage {
    // O(1) lookup via StaticStringMap
    const LanguageMap = std.StaticStringMap(*const fn () callconv(.c) *const c.TSLanguage).initComptime(.{
        .{ "c", tree_sitter_c },
        .{ "zig", tree_sitter_zig },
        .{ "javascript", tree_sitter_javascript },
        .{ "typescript", tree_sitter_typescript },
        .{ "tsx", tree_sitter_tsx },
        .{ "markdown", tree_sitter_markdown },
        .{ "markdown_inline", tree_sitter_markdown_inline },
    });

    const lang_fn = LanguageMap.get(name) orelse return null;
    return lang_fn();
}

/// List all bundled language names
pub fn listLanguages() []const []const u8 {
    return &[_][]const u8{
        "c",
        "zig",
        "javascript",
        "typescript",
        "tsx",
        "markdown",
        "markdown_inline",
    };
}

// ============================================================================
// Tests
// ============================================================================

test "languages: all parsers load" {
    // Verify all 7 bundled parsers can be loaded
    const lang_names = comptime listLanguages();
    inline for (lang_names) |lang_name| {
        const lang = getLanguage(lang_name);
        try std.testing.expect(lang != null);
    }
}

test "languages: unknown parser returns null" {
    const lang = getLanguage("rust");
    try std.testing.expect(lang == null);
}

test "languages: parse simple Zig code" {
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const zig_lang = getLanguage("zig").?;
    try parser.setLanguage(zig_lang);

    const source = "const x: u32 = 42;";
    const tree = try parser.parseString(null, source);
    defer c.ts_tree_delete(tree);

    const root = c.ts_tree_root_node(tree);
    try std.testing.expect(!c.ts_node_is_null(root));

    // Verify tree has children (parsed successfully)
    try std.testing.expect(c.ts_node_child_count(root) > 0);
}

test "languages: parse simple C code" {
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const c_lang = getLanguage("c").?;
    try parser.setLanguage(c_lang);

    const source = "int main() { return 0; }";
    const tree = try parser.parseString(null, source);
    defer c.ts_tree_delete(tree);

    const root = c.ts_tree_root_node(tree);
    try std.testing.expect(!c.ts_node_is_null(root));
    try std.testing.expect(c.ts_node_child_count(root) > 0);
}

test "languages: parse JavaScript code" {
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const js_lang = getLanguage("javascript").?;
    try parser.setLanguage(js_lang);

    const source = "const x = 42;";
    const tree = try parser.parseString(null, source);
    defer c.ts_tree_delete(tree);

    const root = c.ts_tree_root_node(tree);
    try std.testing.expect(!c.ts_node_is_null(root));
    try std.testing.expect(c.ts_node_child_count(root) > 0);
}

test "languages: parse TypeScript code" {
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const ts_lang = getLanguage("typescript").?;
    try parser.setLanguage(ts_lang);

    const source = "const x: number = 42;";
    const tree = try parser.parseString(null, source);
    defer c.ts_tree_delete(tree);

    const root = c.ts_tree_root_node(tree);
    try std.testing.expect(!c.ts_node_is_null(root));
    try std.testing.expect(c.ts_node_child_count(root) > 0);
}

test "languages: parse Markdown code" {
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const md_lang = getLanguage("markdown").?;
    try parser.setLanguage(md_lang);

    const source = "# Hello World\n\nThis is a test.";
    const tree = try parser.parseString(null, source);
    defer c.ts_tree_delete(tree);

    const root = c.ts_tree_root_node(tree);
    try std.testing.expect(!c.ts_node_is_null(root));
    try std.testing.expect(c.ts_node_child_count(root) > 0);
}
