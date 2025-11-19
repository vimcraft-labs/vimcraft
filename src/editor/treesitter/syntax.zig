/// Tree-sitter Syntax Manager
/// Ties together Parser, Query, and HighlightIterator for syntax highlighting
///
/// Architecture:
/// - Syntax: Manages Tree + Query lifecycle
/// - Lazy Loading: Query only loaded on first highlighter() call
/// - Iterator Factory: Returns HighlightIterator for viewport ranges
///
/// Usage:
///   var syntax = try Syntax.init(allocator, tree, language, "zig");
///   defer syntax.deinit();
///
///   // Lazy load query and get iterator for visible range
///   var iter = try syntax.highlighter(.{ .start_byte = 0, .end_byte = 1000 });
///   defer iter.deinit();
///
///   while (iter.next()) |highlight| {
///       // Apply styling based on highlight.capture_name
///   }
///
/// Design:
/// - OnceCell pattern: Query loaded once, cached for subsequent calls
/// - Zero-copy: HighlightIterator borrows from Syntax's query
/// - RAII: Syntax owns Tree and Query, iterator borrows
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;
const Query = @import("query.zig").Query;
const HighlightIterator = @import("highlight.zig").HighlightIterator;
const Range = @import("highlight.zig").Range;

/// Syntax errors
pub const SyntaxError = error{
    QueryLoadFailed,
    IteratorCreationFailed,
    InvalidLanguage,
};

/// Syntax manager (owns Tree and Query)
///
/// Lifecycle:
/// - Syntax owns TSTree (deletes on deinit)
/// - Syntax owns Query (lazy loaded, deleted on deinit)
/// - HighlightIterator borrows from Syntax (caller owns iterator)
pub const Syntax = struct {
    tree: *c.TSTree, // Owned (caller transfers ownership via init)
    language: *const c.TSLanguage, // Reference (not owned)
    language_name: []const u8, // For query loading (e.g., "zig", "javascript")
    query: ?Query, // Lazy loaded on first highlighter() call
    allocator: std.mem.Allocator,

    /// Create a new syntax manager
    /// Takes ownership of tree (will delete on deinit)
    ///
    /// Parameters:
    /// - allocator: Memory allocator
    /// - tree: Parsed syntax tree (ownership transferred)
    /// - language: TSLanguage pointer (must outlive Syntax)
    /// - language_name: Language identifier for query loading (e.g., "zig")
    ///
    /// Returns:
    /// - Syntax manager ready for highlighter() calls
    pub fn init(
        allocator: std.mem.Allocator,
        tree: *c.TSTree,
        language: *const c.TSLanguage,
        language_name: []const u8,
    ) !Syntax {
        // Keep a copy of language_name for query loading
        const name_copy = try allocator.dupe(u8, language_name);

        return Syntax{
            .tree = tree,
            .language = language,
            .language_name = name_copy,
            .query = null, // Lazy loaded
            .allocator = allocator,
        };
    }

    /// Free syntax manager resources
    /// Deletes tree, query, and language_name copy
    pub fn deinit(self: *Syntax) void {
        // Delete tree (we own it)
        c.ts_tree_delete(self.tree);

        // Delete query if loaded
        if (self.query) |*query| {
            query.deinit();
        }

        // Free language_name copy
        self.allocator.free(self.language_name);
    }

    /// Get highlight iterator for a byte range
    /// Lazy loads query on first call, then caches for subsequent calls
    ///
    /// Parameters:
    /// - range: Byte range to highlight (viewport optimization)
    ///
    /// Returns:
    /// - HighlightIterator (caller owns, must call deinit)
    ///
    /// Performance:
    /// - First call: ~2-5ms (loads and compiles highlights.scm)
    /// - Subsequent calls: ~0.1ms (query cached, just creates iterator)
    pub fn highlighter(self: *Syntax, range: Range) !HighlightIterator {
        // Lazy load query if not already loaded
        if (self.query == null) {
            self.query = Query.loadForLanguage(
                self.allocator,
                self.language_name,
                self.language,
            ) catch {
                return SyntaxError.QueryLoadFailed;
            };
        }

        // Create iterator (borrows from self.query)
        const iter = HighlightIterator.init(
            self.allocator,
            &self.query.?,
            self.tree,
            range,
        ) catch {
            return SyntaxError.IteratorCreationFailed;
        };
        return iter;
    }

    /// Update tree for incremental parsing
    /// Used when buffer changes (e.g., user types)
    ///
    /// Parameters:
    /// - new_tree: New parsed tree (ownership transferred)
    ///
    /// Note: Old tree is deleted, query remains cached
    pub fn updateTree(self: *Syntax, new_tree: *c.TSTree) void {
        // Delete old tree
        c.ts_tree_delete(self.tree);

        // Replace with new tree
        self.tree = new_tree;
    }

    /// Get query capture count (for debugging)
    /// Returns 0 if query not loaded yet
    pub fn getCaptureCount(self: *const Syntax) u32 {
        if (self.query) |*query| {
            return query.getCaptureCount();
        }
        return 0;
    }

    /// Check if query is loaded
    pub fn isQueryLoaded(self: *const Syntax) bool {
        return self.query != null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Syntax: init and deinit" {
    const languages = @import("languages.zig");
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    // Parse simple Zig code
    const zig_lang = languages.getLanguage("zig").?;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parser.setLanguage(zig_lang);
    const source = "const x: u32 = 42;";
    const tree = try parser.parseString(null, source);
    // Note: tree ownership transferred to Syntax

    // Create syntax manager
    var syntax = try Syntax.init(allocator, tree, zig_lang, "zig");
    defer syntax.deinit(); // Will delete tree

    // Syntax created successfully
    try std.testing.expect(!syntax.isQueryLoaded()); // Query not loaded yet
}

test "Syntax: lazy query loading" {
    const languages = @import("languages.zig");
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    // Setup
    const zig_lang = languages.getLanguage("zig").?;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parser.setLanguage(zig_lang);
    const source = "const x: u32 = 42;";
    const tree = try parser.parseString(null, source);

    var syntax = try Syntax.init(allocator, tree, zig_lang, "zig");
    defer syntax.deinit();

    // Query not loaded initially
    try std.testing.expect(!syntax.isQueryLoaded());
    try std.testing.expectEqual(@as(u32, 0), syntax.getCaptureCount());

    // First highlighter() call loads query
    const range = Range{ .start_byte = 0, .end_byte = @intCast(source.len) };
    var iter1 = try syntax.highlighter(range);
    defer iter1.deinit();

    // Query now loaded
    try std.testing.expect(syntax.isQueryLoaded());
    try std.testing.expect(syntax.getCaptureCount() > 0);

    // Second highlighter() call reuses cached query
    var iter2 = try syntax.highlighter(range);
    defer iter2.deinit();

    // Query still loaded (not reloaded)
    try std.testing.expect(syntax.isQueryLoaded());
}

test "Syntax: highlighter yields correct highlights" {
    const languages = @import("languages.zig");
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    // Setup
    const zig_lang = languages.getLanguage("zig").?;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parser.setLanguage(zig_lang);
    const source = "const x: u32 = 42;";
    const tree = try parser.parseString(null, source);

    var syntax = try Syntax.init(allocator, tree, zig_lang, "zig");
    defer syntax.deinit();

    // Get iterator and collect highlights
    const range = Range{ .start_byte = 0, .end_byte = @intCast(source.len) };
    var iter = try syntax.highlighter(range);
    defer iter.deinit();

    var count: usize = 0;
    while (iter.next()) |highlight| {
        // Verify highlight has valid data
        try std.testing.expect(highlight.range.start_byte <= highlight.range.end_byte);
        try std.testing.expect(highlight.range.end_byte <= source.len);
        try std.testing.expect(highlight.capture_name.len > 0);
        count += 1;
    }

    // Should yield at least one highlight
    try std.testing.expect(count > 0);
}

test "Syntax: multiple iterators from same syntax" {
    const languages = @import("languages.zig");
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    // Setup
    const zig_lang = languages.getLanguage("zig").?;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parser.setLanguage(zig_lang);
    const source = "const a = 1;\nconst b = 2;\nconst c = 3;";
    const tree = try parser.parseString(null, source);

    var syntax = try Syntax.init(allocator, tree, zig_lang, "zig");
    defer syntax.deinit();

    // Create iterator for first line
    const range1 = Range{ .start_byte = 0, .end_byte = 12 };
    var iter1 = try syntax.highlighter(range1);
    defer iter1.deinit();

    var count1: usize = 0;
    while (iter1.next()) |_| {
        count1 += 1;
    }

    // Create iterator for second line (query already loaded)
    const range2 = Range{ .start_byte = 13, .end_byte = 25 };
    var iter2 = try syntax.highlighter(range2);
    defer iter2.deinit();

    var count2: usize = 0;
    while (iter2.next()) |_| {
        count2 += 1;
    }

    // Both iterators should yield highlights
    try std.testing.expect(count1 > 0);
    try std.testing.expect(count2 > 0);
}

test "Syntax: updateTree replaces tree" {
    const languages = @import("languages.zig");
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    // Setup
    const zig_lang = languages.getLanguage("zig").?;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parser.setLanguage(zig_lang);

    // Parse first version
    const source1 = "const x = 1;";
    const tree1 = try parser.parseString(null, source1);
    var syntax = try Syntax.init(allocator, tree1, zig_lang, "zig");
    defer syntax.deinit();

    // Get initial highlights
    const range1 = Range{ .start_byte = 0, .end_byte = @intCast(source1.len) };
    var iter1 = try syntax.highlighter(range1);
    defer iter1.deinit();

    var count1: usize = 0;
    while (iter1.next()) |_| {
        count1 += 1;
    }

    // Update tree (simulate user editing)
    const source2 = "const x = 2;\nconst y = 3;";
    const tree2 = try parser.parseString(null, source2);
    syntax.updateTree(tree2);

    // Get highlights from updated tree
    const range2 = Range{ .start_byte = 0, .end_byte = @intCast(source2.len) };
    var iter2 = try syntax.highlighter(range2);
    defer iter2.deinit();

    var count2: usize = 0;
    while (iter2.next()) |_| {
        count2 += 1;
    }

    // Second tree should have more highlights (more code)
    try std.testing.expect(count2 > count1);
}

test "Syntax: handles invalid language gracefully" {
    const languages = @import("languages.zig");
    const Parser = @import("parser.zig").Parser;
    const allocator = std.testing.allocator;

    // Setup with valid language
    const zig_lang = languages.getLanguage("zig").?;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parser.setLanguage(zig_lang);
    const source = "const x = 1;";
    const tree = try parser.parseString(null, source);

    // Create syntax with invalid language name (no highlights.scm file)
    var syntax = try Syntax.init(allocator, tree, zig_lang, "nonexistent");
    defer syntax.deinit();

    // highlighter() should fail gracefully
    const range = Range{ .start_byte = 0, .end_byte = @intCast(source.len) };
    const result = syntax.highlighter(range);
    try std.testing.expectError(SyntaxError.QueryLoadFailed, result);
}
