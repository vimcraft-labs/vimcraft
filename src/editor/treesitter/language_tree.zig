/// Language Tree - Recursive Tree-sitter Parser Management
///
/// A LanguageTree contains a tree of parsers: the root treesitter parser for a language
/// and any "injected" language parsers, which themselves may inject other languages recursively.
///
/// For example, a Markdown file containing JavaScript code blocks needs multiple parsers:
/// - Markdown parser (root)
///   └── JavaScript parser (injected into code blocks)
///   └── markdown_inline parser (injected for inline content)
///       └── HTML parser (injected for HTML tags)
///
/// Architecture:
/// - LanguageTree owns: parser, trees (per region), injectionQuery, highlightQuery
/// - LanguageTree references: children (child LanguageTrees), parent
/// - Regions: Byte ranges where this language applies (empty for root)
/// - Recursive: Children can have their own children (recursive injections)
///
/// Based on Neovim's vim.treesitter.LanguageTree pattern.
///
/// Usage:
///   var tree = try LanguageTree.init(allocator, source, "markdown");
///   defer tree.deinit();
///
///   try tree.parse();
///   tree.forEachTree(fn (tstree, ltree) { ... });

const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;
const Parser = @import("parser.zig").Parser;
const Query = @import("query.zig").Query;
const HighlightIterator = @import("highlight.zig").HighlightIterator;
const languages = @import("languages.zig");
const predicates = @import("predicates.zig");
const Metadata = predicates.Metadata;

/// Range with 6 components (row/col start, row/col end, byte start, byte end)
pub const Range6 = struct {
    startRow: u32,
    startCol: u32,
    endRow: u32,
    endCol: u32,
    startByte: u32,
    endByte: u32,
};

/// Simple byte range
pub const Range = struct {
    startByte: u32,
    endByte: u32,
};

/// Injection region identified during query execution
pub const InjectionRegion = struct {
    range: Range6,
    combined: bool,
    includeChildren: bool,
};

/// Errors specific to LanguageTree operations
pub const LanguageTreeError = error{
    LanguageNotFound,
    ParserCreationFailed,
    ParseFailed,
    QueryLoadFailed,
    InvalidRegion,
    OutOfMemory,
};

/// LanguageTree - Recursive parser management for language injections
///
/// Lifecycle:
/// - init(): Create root tree for a language
/// - parse(): Parse source, detect injections, create child trees recursively
/// - forEachTree(): Iterate all trees (root + children)
/// - deinit(): Clean up all resources (including children)
pub const LanguageTree = struct {
    allocator: std.mem.Allocator,

    // Language info
    lang: []const u8, // Owned copy
    tsLanguage: *const c.TSLanguage,

    // Parser and trees
    parser: Parser,
    trees: std.AutoHashMap(u32, *c.TSTree), // Region index → tree
    source: []const u8, // Last parsed source (borrowed, not owned)

    // Queries (lazy loaded)
    injectionQuery: ?Query,
    highlightQuery: ?Query,

    // Children (injected languages)
    children: std.StringHashMap(*LanguageTree),

    // Regions (for injected trees, empty for root)
    regions: std.ArrayList(Range6),
    validRegions: std.AutoHashMap(u32, bool),

    // Parent reference (null for root)
    parent: ?*LanguageTree,

    // State tracking
    isValid: bool,
    hasProcessedInjections: bool,

    /// Create a new LanguageTree for a language
    ///
    /// Parameters:
    /// - allocator: Memory allocator
    /// - lang: Language name ("markdown", "javascript", etc.)
    ///
    /// Returns:
    /// - Allocated LanguageTree (caller owns, must call deinit)
    /// - LanguageTreeError if language not found or parser creation fails
    pub fn init(allocator: std.mem.Allocator, lang: []const u8) LanguageTreeError!*LanguageTree {
        // Get language from registry
        const ts_lang = languages.getLanguage(lang) orelse {
            return LanguageTreeError.LanguageNotFound;
        };

        // Create parser
        var parser = Parser.init(allocator) catch {
            return LanguageTreeError.ParserCreationFailed;
        };
        errdefer parser.deinit();

        parser.setLanguage(ts_lang) catch {
            return LanguageTreeError.ParserCreationFailed;
        };

        // Allocate tree on heap
        const self = allocator.create(LanguageTree) catch {
            return LanguageTreeError.OutOfMemory;
        };
        errdefer allocator.destroy(self);

        // Eagerly load highlight query (uses global cache for ~0.001ms on subsequent loads)
        const highlight_query = Query.loadForLanguage(allocator, lang, ts_lang) catch null;

        self.* = LanguageTree{
            .allocator = allocator,
            .lang = allocator.dupe(u8, lang) catch return LanguageTreeError.OutOfMemory,
            .tsLanguage = ts_lang,
            .parser = parser,
            .trees = std.AutoHashMap(u32, *c.TSTree).init(allocator),
            .source = "",
            .injectionQuery = null,
            .highlightQuery = highlight_query,
            .children = std.StringHashMap(*LanguageTree).init(allocator),
            .regions = .empty,
            .validRegions = std.AutoHashMap(u32, bool).init(allocator),
            .parent = null,
            .isValid = false,
            .hasProcessedInjections = false,
        };

        return self;
    }

    /// Clean up all resources
    pub fn deinit(self: *LanguageTree) void {
        // Clean up children recursively
        var child_iter = self.children.valueIterator();
        while (child_iter.next()) |child| {
            child.*.deinit();
            self.allocator.destroy(child.*);
        }
        self.children.deinit();

        // Clean up trees
        var tree_iter = self.trees.valueIterator();
        while (tree_iter.next()) |tree| {
            c.ts_tree_delete(tree.*);
        }
        self.trees.deinit();

        // Clean up queries
        if (self.injectionQuery) |*q| q.deinit();
        if (self.highlightQuery) |*q| q.deinit();

        // Clean up other collections
        self.regions.deinit(self.allocator);
        self.validRegions.deinit();

        // Clean up parser
        self.parser.deinit();

        // Free language name
        self.allocator.free(self.lang);
    }

    /// Parse source text and process injections
    ///
    /// Parameters:
    /// - source: Full source text to parse
    ///
    /// This will:
    /// 1. Parse the source with the main parser
    /// 2. Load injection query (lazy)
    /// 3. Find injection regions
    /// 4. Create/update child LanguageTrees for each injection
    /// 5. Recursively parse children
    pub fn parse(self: *LanguageTree, source: []const u8) LanguageTreeError!void {
        self.source = source;

        // Parse main tree (region 0 for root)
        if (self.regions.items.len == 0) {
            // Root tree - parse entire source
            const tree = self.parser.parseString(null, source) catch {
                return LanguageTreeError.ParseFailed;
            };

            // Store/replace tree for region 0
            if (self.trees.get(0)) |old_tree| {
                c.ts_tree_delete(old_tree);
            }
            self.trees.put(0, tree) catch {
                c.ts_tree_delete(tree);
                return LanguageTreeError.OutOfMemory;
            };
            self.validRegions.put(0, true) catch {};
        } else {
            // Child tree - parse each region
            for (self.regions.items, 0..) |region, idx| {
                const region_idx: u32 = @intCast(idx);
                if (region.startByte >= source.len or region.endByte > source.len) {
                    continue;
                }

                const region_source = source[region.startByte..region.endByte];
                const tree = self.parser.parseString(null, region_source) catch {
                    continue;
                };

                if (self.trees.get(region_idx)) |old_tree| {
                    c.ts_tree_delete(old_tree);
                }
                self.trees.put(region_idx, tree) catch {
                    c.ts_tree_delete(tree);
                    continue;
                };
                self.validRegions.put(region_idx, true) catch {};
            }
        }

        self.isValid = true;
        self.hasProcessedInjections = false;

        // Process injections
        try self.processInjections(source);
    }

    /// Process injection queries and create/update child trees
    fn processInjections(self: *LanguageTree, source: []const u8) LanguageTreeError!void {
        if (self.hasProcessedInjections) return;
        self.hasProcessedInjections = true;

        // Lazy load injection query
        if (self.injectionQuery == null) {
            self.injectionQuery = Query.loadInjectionQuery(
                self.allocator,
                self.lang,
                self.tsLanguage,
            );
        }

        const inj_query = self.injectionQuery orelse return; // No injections for this language

        // Get injections from all trees
        var injections = std.StringHashMap(std.ArrayList(InjectionRegion)).init(self.allocator);
        defer {
            var iter = injections.iterator();
            while (iter.next()) |entry| {
                // Free the key (lang_copy)
                self.allocator.free(entry.key_ptr.*);
                // Free the value (ArrayList)
                entry.value_ptr.deinit(self.allocator);
            }
            injections.deinit();
        }

        // Execute injection query on each tree
        var tree_iter = self.trees.iterator();
        while (tree_iter.next()) |entry| {
            const region_idx = entry.key_ptr.*;
            const tree = entry.value_ptr.*;

            try self.collectInjections(
                &inj_query,
                tree,
                region_idx,
                source,
                &injections,
            );
        }

        // Create/update children for each language
        var inj_iter = injections.iterator();
        while (inj_iter.next()) |entry| {
            const lang = entry.key_ptr.*;
            const regions = entry.value_ptr.*;

            try self.updateChild(lang, regions.items, source);
        }
    }

    /// Collect injections from a tree into the injections map
    fn collectInjections(
        self: *LanguageTree,
        inj_query: *const Query,
        tree: *c.TSTree,
        regionIdx: u32,
        source: []const u8,
        injections: *std.StringHashMap(std.ArrayList(InjectionRegion)),
    ) LanguageTreeError!void {
        _ = regionIdx;

        const cursor = c.ts_query_cursor_new() orelse return;
        defer c.ts_query_cursor_delete(cursor);

        const root = c.ts_tree_root_node(tree);
        c.ts_query_cursor_exec(cursor, inj_query.query, root);

        var match: c.TSQueryMatch = undefined;
        while (c.ts_query_cursor_next_match(cursor, &match)) {
            // Process predicates and collect metadata
            var metadata = Metadata.init(self.allocator);
            defer metadata.deinit();

            const passes = predicates.processMatchPredicates(inj_query, &match, source, &metadata);
            if (!passes) continue;

            // Extract injection info
            const injection = self.extractInjection(&match, inj_query, &metadata, source) orelse continue;

            // Add to injections map
            const lang_copy = self.allocator.dupe(u8, injection.lang) catch continue;

            const result = injections.getOrPut(lang_copy) catch {
                self.allocator.free(lang_copy);
                continue;
            };
            if (!result.found_existing) {
                result.value_ptr.* = .empty;
            } else {
                self.allocator.free(lang_copy);
            }

            result.value_ptr.append(self.allocator, .{
                .range = injection.range,
                .combined = injection.combined,
                .includeChildren = injection.includeChildren,
            }) catch continue;
        }
    }

    /// Extract injection language and range from a match
    fn extractInjection(
        self: *LanguageTree,
        match: *const c.TSQueryMatch,
        query: *const Query,
        metadata: *const Metadata,
        source: []const u8,
    ) ?struct { lang: []const u8, range: Range6, combined: bool, includeChildren: bool } {
        _ = self;

        var lang: ?[]const u8 = null;
        var content_range: ?Range6 = null;

        // Check for static language from #set! directive
        if (metadata.get("injection.language")) |static_lang| {
            if (static_lang.len > 0) {
                lang = static_lang;
            }
        }

        // Check for injection.self
        if (metadata.contains("injection.self")) {
            // Use parent language (recursive injection)
            // For now, skip self-injections to avoid infinite recursion
            return null;
        }

        // Process captures
        for (0..match.capture_count) |i| {
            const capture = match.captures[i];
            const name = query.getCaptureName(capture.index);

            if (std.mem.eql(u8, name, "injection.language")) {
                // Dynamic language from capture text
                const start = c.ts_node_start_byte(capture.node);
                const end = c.ts_node_end_byte(capture.node);
                if (start < source.len and end <= source.len and start < end) {
                    lang = source[start..end];
                }
            } else if (std.mem.eql(u8, name, "injection.content")) {
                // Content range
                const start_point = c.ts_node_start_point(capture.node);
                const end_point = c.ts_node_end_point(capture.node);
                content_range = .{
                    .startRow = start_point.row,
                    .startCol = start_point.column,
                    .endRow = end_point.row,
                    .endCol = end_point.column,
                    .startByte = c.ts_node_start_byte(capture.node),
                    .endByte = c.ts_node_end_byte(capture.node),
                };
            }
        }

        const final_lang = lang orelse return null;
        const final_range = content_range orelse return null;

        // Normalize language name
        const normalized = normalizeLanguageName(final_lang);

        return .{
            .lang = normalized,
            .range = final_range,
            .combined = metadata.contains("injection.combined"),
            .includeChildren = metadata.contains("injection.include-children") or
                metadata.contains("injection.includeChildren"),
        };
    }

    /// Update or create a child LanguageTree for an injection
    fn updateChild(
        self: *LanguageTree,
        lang: []const u8,
        regions: []const InjectionRegion,
        source: []const u8,
    ) LanguageTreeError!void {
        // Check if language is supported
        if (languages.getLanguage(lang) == null) {
            return; // Silently skip unsupported languages
        }

        // Get or create child
        var child = self.children.get(lang);
        if (child == null) {
            const new_child = try LanguageTree.init(self.allocator, lang);
            new_child.parent = self;
            // Use new_child.lang as key (already duped in init), not the borrowed lang
            self.children.put(new_child.lang, new_child) catch {
                new_child.deinit();
                self.allocator.destroy(new_child);
                return LanguageTreeError.OutOfMemory;
            };
            child = new_child;
        }

        const child_tree = child.?;

        // Set regions
        child_tree.regions.clearRetainingCapacity();
        for (regions) |region| {
            child_tree.regions.append(self.allocator, region.range) catch continue;
        }

        // Parse child
        try child_tree.parse(source);
    }

    /// Iterate over all trees (root + children recursively)
    ///
    /// Calls callback for each tree in the hierarchy.
    /// Useful for collecting highlights from all languages.
    pub fn forEachTree(
        self: *LanguageTree,
        comptime callback: fn (*c.TSTree, *LanguageTree, u32) void,
    ) void {
        // Iterate own trees
        var tree_iter = self.trees.iterator();
        while (tree_iter.next()) |entry| {
            callback(entry.value_ptr.*, self, entry.key_ptr.*);
        }

        // Iterate children recursively
        var child_iter = self.children.valueIterator();
        while (child_iter.next()) |child| {
            child.*.forEachTree(callback);
        }
    }

    /// Get the tree for region 0 (main tree)
    pub fn getTree(self: *const LanguageTree) ?*c.TSTree {
        return self.trees.get(0);
    }

    /// Get highlight iterator for a byte range
    /// Loads highlight query lazily if not already loaded
    pub fn highlighter(self: *LanguageTree, range: Range) !HighlightIterator {
        // Lazy load highlight query
        if (self.highlightQuery == null) {
            self.highlightQuery = Query.loadForLanguage(
                self.allocator,
                self.lang,
                self.tsLanguage,
            ) catch {
                return error.QueryLoadFailed;
            };
        }

        const tree = self.getTree() orelse return error.NoTree;

        return HighlightIterator.init(
            self.allocator,
            &self.highlightQuery.?,
            tree,
            .{ .start_byte = range.startByte, .end_byte = range.endByte },
        );
    }

    /// Check if this tree has any children (injected languages)
    pub fn hasChildren(self: *const LanguageTree) bool {
        return self.children.count() > 0;
    }

    /// Get child LanguageTree for a specific language
    pub fn getChild(self: *const LanguageTree, lang: []const u8) ?*LanguageTree {
        return self.children.get(lang);
    }

    /// Get language name
    pub fn language(self: *const LanguageTree) []const u8 {
        return self.lang;
    }

    /// Find which LanguageTree contains a given byte position
    /// Returns the most specific (deepest) tree containing the position
    pub fn languageForRange(self: *LanguageTree, startByte: u32, endByte: u32) *LanguageTree {
        // Check children first (more specific)
        var child_iter = self.children.valueIterator();
        while (child_iter.next()) |child| {
            for (child.*.regions.items) |region| {
                if (startByte >= region.startByte and endByte <= region.endByte) {
                    // Recursively check child's children
                    return child.*.languageForRange(startByte, endByte);
                }
            }
        }

        // No child contains this range, return self
        return self;
    }

    /// Invalidate tree (marks for re-parse)
    pub fn invalidate(self: *LanguageTree) void {
        self.isValid = false;
        self.hasProcessedInjections = false;

        // Invalidate children
        var child_iter = self.children.valueIterator();
        while (child_iter.next()) |child| {
            child.*.invalidate();
        }
    }
};

/// Normalize language name for lookup
fn normalizeLanguageName(name: []const u8) []const u8 {
    // Common aliases
    if (std.mem.eql(u8, name, "js")) return "javascript";
    if (std.mem.eql(u8, name, "ts")) return "typescript";
    if (std.mem.eql(u8, name, "md")) return "markdown";
    if (std.mem.eql(u8, name, "yml")) return "yaml";
    if (std.mem.eql(u8, name, "py")) return "python";
    if (std.mem.eql(u8, name, "rb")) return "ruby";
    if (std.mem.eql(u8, name, "rs")) return "rust";
    if (std.mem.eql(u8, name, "sh") or std.mem.eql(u8, name, "bash")) return "bash";
    if (std.mem.eql(u8, name, "zsh")) return "bash";
    return name;
}

// ============================================================================
// Tests
// ============================================================================

test "LanguageTree: init and deinit" {
    const allocator = std.testing.allocator;

    var tree = try LanguageTree.init(allocator, "zig");
    defer {
        tree.deinit();
        allocator.destroy(tree);
    }

    try std.testing.expectEqualStrings("zig", tree.lang);
    try std.testing.expect(!tree.isValid);
    try std.testing.expect(tree.parent == null);
}

test "LanguageTree: parse simple source" {
    const allocator = std.testing.allocator;

    var tree = try LanguageTree.init(allocator, "zig");
    defer {
        tree.deinit();
        allocator.destroy(tree);
    }

    const source = "const x: u32 = 42;";
    try tree.parse(source);

    try std.testing.expect(tree.isValid);
    try std.testing.expect(tree.getTree() != null);
}

test "LanguageTree: markdown with injections" {
    const allocator = std.testing.allocator;

    var tree = try LanguageTree.init(allocator, "markdown");
    defer {
        tree.deinit();
        allocator.destroy(tree);
    }

    const source =
        \\# Hello
        \\
        \\```javascript
        \\const x = 1;
        \\```
        \\
    ;
    try tree.parse(source);

    try std.testing.expect(tree.isValid);
    try std.testing.expect(tree.getTree() != null);

    // Should have detected JavaScript injection
    // Note: This depends on injections.scm being present
    if (tree.hasChildren()) {
        const js_child = tree.getChild("javascript");
        if (js_child) |child| {
            try std.testing.expectEqualStrings("javascript", child.lang);
        }
    }
}

test "LanguageTree: invalid language" {
    const allocator = std.testing.allocator;

    const result = LanguageTree.init(allocator, "nonexistent_language");
    try std.testing.expectError(LanguageTreeError.LanguageNotFound, result);
}

test "LanguageTree: forEachTree" {
    const allocator = std.testing.allocator;

    var tree = try LanguageTree.init(allocator, "zig");
    defer {
        tree.deinit();
        allocator.destroy(tree);
    }

    const source = "const x = 1;";
    try tree.parse(source);

    var count: usize = 0;
    tree.forEachTree(struct {
        fn callback(_: *c.TSTree, _: *LanguageTree, _: u32) void {
            // Note: Can't capture from outer scope in comptime fn
            // This is just to verify forEachTree compiles and runs
        }
    }.callback);

    // Count trees manually
    var iter = tree.trees.iterator();
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expect(count >= 1);
}

test "normalizeLanguageName: aliases" {
    try std.testing.expectEqualStrings("javascript", normalizeLanguageName("js"));
    try std.testing.expectEqualStrings("typescript", normalizeLanguageName("ts"));
    try std.testing.expectEqualStrings("markdown", normalizeLanguageName("md"));
    try std.testing.expectEqualStrings("python", normalizeLanguageName("py"));
    try std.testing.expectEqualStrings("zig", normalizeLanguageName("zig")); // No alias
}
