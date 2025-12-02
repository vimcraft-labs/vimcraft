/// Tree-sitter Query Wrapper
/// Zig-friendly wrapper around TSQuery C API for highlights.scm queries
///
/// Architecture:
/// - TSQuery (C): Compiled query pattern from .scm files
/// - Query (Zig): RAII wrapper with init/deinit (owns C query pointer)
/// - Query files: highlights.scm in vendor/tree-sitter-{lang}/queries/
///
/// Usage:
///   const query = try Query.loadFromFile(allocator, language, "highlights.scm");
///   defer query.deinit();
///
///   // Query contains compiled patterns ready for cursor execution
///   const capture_count = query.getCaptureCount();
///
/// Future enhancements:
/// - Support for injections.scm (embedded languages)
/// - Support for locals.scm (semantic scoping)
/// - Query optimization and caching
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Query errors (Zig-style error union)
pub const QueryError = error{
    QueryCompilationFailed,
    SyntaxError,
    NodeTypeError,
    FieldError,
    CaptureError,
    StructureError,
    LanguageError,
    FileNotFound,
    OutOfMemory,
};

// ============================================================================
// Global Query Cache
// ============================================================================
// Cache compiled queries by language name to avoid re-reading files and
// re-compiling queries on every LanguageTree creation.
// CRITICAL: TypeScript query loading takes 180ms without caching!
//
// Cache entries are NEVER freed - they live for the lifetime of the process.
// This is intentional: queries are large, compilation is expensive, and
// memory is cheap. A typical editor session uses <10MB for all queries.
// ============================================================================

/// Cached query entry - stores TSQuery pointer and source
/// The TSQuery pointer is borrowed by callers who need a Query wrapper
const CachedQuery = struct {
    ts_query: *c.TSQuery,
    source: []const u8, // Owned by cache, lives forever
};

/// Global cache for highlight queries
var global_highlight_cache: ?std.StringHashMap(CachedQuery) = null;
var global_injection_cache: ?std.StringHashMap(CachedQuery) = null;

/// Page allocator for cache entries (never freed, uses mmap)
const cache_allocator = std.heap.page_allocator;

fn ensureCacheInitialized() void {
    if (global_highlight_cache == null) {
        global_highlight_cache = std.StringHashMap(CachedQuery).init(cache_allocator);
    }
    if (global_injection_cache == null) {
        global_injection_cache = std.StringHashMap(CachedQuery).init(cache_allocator);
    }
}

/// Store a query in the highlight cache (takes ownership of ts_query and source)
fn cacheHighlightQuery(lang: []const u8, ts_query: *c.TSQuery, source: []const u8) void {
    ensureCacheInitialized();
    const lang_copy = cache_allocator.dupe(u8, lang) catch return;
    global_highlight_cache.?.put(lang_copy, CachedQuery{
        .ts_query = ts_query,
        .source = source,
    }) catch {};
}

/// Get a cached highlight query (returns TSQuery pointer, not a full Query)
fn getCachedHighlightQuery(lang: []const u8) ?*c.TSQuery {
    ensureCacheInitialized();
    const entry = global_highlight_cache.?.get(lang) orelse return null;
    return entry.ts_query;
}

/// Zig wrapper for TSQuery
/// Can either OWN the query (will free on deinit) or BORROW from cache (won't free)
/// Lifetime: If owned, caller must call deinit(). If borrowed, deinit() is a no-op.
pub const Query = struct {
    query: *c.TSQuery,
    allocator: std.mem.Allocator,
    source: []const u8, // Keep source for debugging/error messages
    owned: bool, // If true, deinit() frees the TSQuery. If false, it's borrowed from cache.

    /// Create a new query from source string
    /// Caller owns returned Query and must call deinit()
    ///
    /// Parameters:
    /// - language: TSLanguage pointer (from languages.zig)
    /// - source: Query source code (highlights.scm contents)
    ///
    /// Returns:
    /// - Compiled Query on success
    /// - QueryError on compilation failure
    pub fn init(
        allocator: std.mem.Allocator,
        language: *const c.TSLanguage,
        source: []const u8,
    ) QueryError!Query {
        var error_offset: u32 = 0;
        var error_type: c.TSQueryError = c.TSQueryErrorNone;

        const query = c.ts_query_new(
            language,
            source.ptr,
            @intCast(source.len),
            &error_offset,
            &error_type,
        ) orelse {
            // Query compilation failed - map C error to Zig error
            return switch (error_type) {
                c.TSQueryErrorSyntax => QueryError.SyntaxError,
                c.TSQueryErrorNodeType => QueryError.NodeTypeError,
                c.TSQueryErrorField => QueryError.FieldError,
                c.TSQueryErrorCapture => QueryError.CaptureError,
                c.TSQueryErrorStructure => QueryError.StructureError,
                c.TSQueryErrorLanguage => QueryError.LanguageError,
                else => QueryError.QueryCompilationFailed,
            };
        };

        // Keep a copy of source for debugging (small overhead, ~2KB per language)
        const source_copy = try allocator.dupe(u8, source);

        return Query{
            .query = query,
            .allocator = allocator,
            .source = source_copy,
            .owned = true,
        };
    }

    /// Create a borrowed Query wrapper around a cached TSQuery
    /// The Query does NOT own the TSQuery - deinit() is a no-op
    fn initBorrowed(ts_query: *c.TSQuery) Query {
        return Query{
            .query = ts_query,
            .allocator = undefined, // Not used for borrowed queries
            .source = "", // Not used for borrowed queries
            .owned = false,
        };
    }

    /// Load query from file path
    /// Convenience wrapper around init() that reads file contents
    ///
    /// Parameters:
    /// - language: TSLanguage pointer
    /// - file_path: Absolute path to .scm file
    ///
    /// Example:
    ///   const query = try Query.loadFromFile(
    ///       allocator,
    ///       tree_sitter_zig(),
    ///       "vendor/tree-sitter-zig/queries/highlights.scm"
    ///   );
    pub fn loadFromFile(
        allocator: std.mem.Allocator,
        language: *const c.TSLanguage,
        file_path: []const u8,
    ) QueryError!Query {
        // Read file contents
        const file = std.fs.cwd().openFile(file_path, .{}) catch {
            return QueryError.FileNotFound;
        };
        defer file.close();

        const source = file.readToEndAlloc(allocator, 1024 * 1024) catch {
            return QueryError.OutOfMemory;
        };
        defer allocator.free(source);

        // Compile query (init() makes its own copy of source)
        return try init(allocator, language, source);
    }

    /// Load query from language name (CACHED)
    /// First checks global cache, then loads and caches if not found.
    /// Returns BORROWED Query wrapper - deinit() is a no-op.
    ///
    /// Parameters:
    /// - allocator: Used only for temporary allocations during loading
    /// - language_name: Language identifier ("zig", "javascript", etc.)
    /// - language: TSLanguage pointer for that language
    ///
    /// Example:
    ///   const query = try Query.loadForLanguage(allocator, "zig", tree_sitter_zig());
    ///   defer query.deinit();  // No-op for cached queries
    pub fn loadForLanguage(
        allocator: std.mem.Allocator,
        language_name: []const u8,
        language: *const c.TSLanguage,
    ) QueryError!Query {
        // Check cache first - O(1) lookup, instant if cached
        if (getCachedHighlightQuery(language_name)) |cached| {
            return initBorrowed(cached);
        }

        // Not cached - load, compile, cache, return borrowed
        const source = try loadQuerySource(allocator, language_name);
        // source is allocated with cache_allocator, owned by cache

        const ts_query = compileQuery(language, source) catch |err| {
            cache_allocator.free(source);
            return err;
        };

        // Cache it (never freed)
        cacheHighlightQuery(language_name, ts_query, source);

        return initBorrowed(ts_query);
    }

    /// Load query source from files (handles special cases)
    /// Returns source allocated with cache_allocator (for permanent caching)
    fn loadQuerySource(allocator: std.mem.Allocator, language_name: []const u8) QueryError![]const u8 {
        _ = allocator; // Unused - we use cache_allocator for permanent storage

        // SPECIAL CASE: Markdown has nested directory structure
        if (std.mem.eql(u8, language_name, "markdown")) {
            const md_path = "vendor/tree-sitter-markdown/tree-sitter-markdown/queries/highlights.scm";
            return readFileForCache(md_path);
        }

        // SPECIAL CASE: Markdown inline parser
        if (std.mem.eql(u8, language_name, "markdown_inline")) {
            const md_inline_path = "vendor/tree-sitter-markdown/tree-sitter-markdown-inline/queries/highlights.scm";
            return readFileForCache(md_inline_path);
        }

        // SPECIAL CASE: TypeScript needs JavaScript base + TypeScript highlights
        if (std.mem.eql(u8, language_name, "typescript")) {
            const js_path = "vendor/tree-sitter-javascript/queries/highlights.scm";
            const ts_path = "vendor/tree-sitter-typescript/queries/highlights.scm";

            const js_source = readFileForCache(js_path) catch return QueryError.FileNotFound;
            defer cache_allocator.free(js_source);

            const ts_source = readFileForCache(ts_path) catch return QueryError.FileNotFound;
            defer cache_allocator.free(ts_source);

            // Combine both queries
            return std.fmt.allocPrint(
                cache_allocator,
                "{s}\n; TypeScript-specific highlights\n{s}",
                .{ js_source, ts_source },
            ) catch return QueryError.OutOfMemory;
        }

        // Standard case: Load single highlights.scm file
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "vendor/tree-sitter-{s}/queries/highlights.scm", .{language_name}) catch {
            return QueryError.FileNotFound;
        };

        return readFileForCache(path);
    }

    /// Read file contents using cache_allocator (for permanent storage)
    fn readFileForCache(path: []const u8) QueryError![]const u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return QueryError.FileNotFound;
        };
        defer file.close();

        return file.readToEndAlloc(cache_allocator, 1024 * 1024) catch {
            return QueryError.OutOfMemory;
        };
    }

    /// Compile query source into TSQuery
    fn compileQuery(language: *const c.TSLanguage, source: []const u8) QueryError!*c.TSQuery {
        var error_offset: u32 = 0;
        var error_type: c.TSQueryError = c.TSQueryErrorNone;

        return c.ts_query_new(
            language,
            source.ptr,
            @intCast(source.len),
            &error_offset,
            &error_type,
        ) orelse {
            return switch (error_type) {
                c.TSQueryErrorSyntax => QueryError.SyntaxError,
                c.TSQueryErrorNodeType => QueryError.NodeTypeError,
                c.TSQueryErrorField => QueryError.FieldError,
                c.TSQueryErrorCapture => QueryError.CaptureError,
                c.TSQueryErrorStructure => QueryError.StructureError,
                c.TSQueryErrorLanguage => QueryError.LanguageError,
                else => QueryError.QueryCompilationFailed,
            };
        };
    }

    /// Load injection query for a language
    /// Automatically resolves path to vendor/tree-sitter-{lang}/queries/injections.scm
    ///
    /// Unlike loadForLanguage, this returns null if the file doesn't exist
    /// (not all languages have injections.scm)
    ///
    /// Parameters:
    /// - language_name: Language identifier ("markdown", "javascript", etc.)
    /// - language: TSLanguage pointer for that language
    ///
    /// Returns:
    /// - Query if injections.scm exists and compiles successfully
    /// - null if file doesn't exist or compilation fails
    pub fn loadInjectionQuery(
        allocator: std.mem.Allocator,
        language_name: []const u8,
        language: *const c.TSLanguage,
    ) ?Query {
        // SPECIAL CASE: Markdown has nested directory structure
        if (std.mem.eql(u8, language_name, "markdown")) {
            const md_path = "vendor/tree-sitter-markdown/tree-sitter-markdown/queries/injections.scm";
            return loadFromFile(allocator, language, md_path) catch null;
        }

        // SPECIAL CASE: Markdown inline parser
        if (std.mem.eql(u8, language_name, "markdown_inline")) {
            const md_inline_path = "vendor/tree-sitter-markdown/tree-sitter-markdown-inline/queries/injections.scm";
            return loadFromFile(allocator, language, md_inline_path) catch null;
        }

        // Standard case: Load single injections.scm file
        const path = std.fmt.allocPrint(
            allocator,
            "vendor/tree-sitter-{s}/queries/injections.scm",
            .{language_name},
        ) catch return null;
        defer allocator.free(path);

        return loadFromFile(allocator, language, path) catch null;
    }

    /// Free query resources (no-op for borrowed queries)
    pub fn deinit(self: *Query) void {
        if (!self.owned) {
            // Borrowed from cache - don't free
            return;
        }
        c.ts_query_delete(self.query);
        self.allocator.free(self.source);
    }

    /// Get number of patterns in query
    pub fn getPatternCount(self: *const Query) u32 {
        return c.ts_query_pattern_count(self.query);
    }

    /// Get number of captures in query
    /// Captures are named groups like @function, @keyword, etc.
    pub fn getCaptureCount(self: *const Query) u32 {
        return c.ts_query_capture_count(self.query);
    }

    /// Get capture name by ID
    /// Returns null-terminated string (borrowed from query, do not free)
    ///
    /// Example:
    ///   const name = query.getCaptureName(0);  // "function.name"
    pub fn getCaptureName(self: *const Query, id: u32) []const u8 {
        var length: u32 = 0;
        const name_ptr = c.ts_query_capture_name_for_id(self.query, id, &length);
        return name_ptr[0..length];
    }

    /// Get all capture names
    /// Returns slice of capture names (caller owns memory)
    pub fn getCaptureNames(self: *const Query, allocator: std.mem.Allocator) ![][]const u8 {
        const count = self.getCaptureCount();
        const names = try allocator.alloc([]const u8, count);

        for (0..count) |i| {
            names[i] = self.getCaptureName(@intCast(i));
        }

        return names;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Query: compile simple query" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const zig_lang = languages.getLanguage("zig").?;

    // Simple query that matches function calls
    const source =
        \\(IDENTIFIER) @function.call
    ;

    var query = try Query.init(allocator, zig_lang, source);
    defer query.deinit();

    // Query compiled successfully (if init() succeeded, query is non-null)
    try std.testing.expect(query.getCaptureCount() > 0);
}

test "Query: load from file (Zig)" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const zig_lang = languages.getLanguage("zig").?;

    var query = try Query.loadFromFile(
        allocator,
        zig_lang,
        "vendor/tree-sitter-zig/queries/highlights.scm",
    );
    defer query.deinit();

    // Verify query loaded and has captures
    const capture_count = query.getCaptureCount();
    try std.testing.expect(capture_count > 0);

    // Verify we can get capture names
    const names = try query.getCaptureNames(allocator);
    defer allocator.free(names);

    try std.testing.expect(names.len == capture_count);
}

test "Query: load for language (JavaScript)" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const js_lang = languages.getLanguage("javascript").?;

    var query = try Query.loadForLanguage(allocator, "javascript", js_lang);
    defer query.deinit();

    // Verify query loaded
    try std.testing.expect(query.getCaptureCount() > 0);
    try std.testing.expect(query.getPatternCount() > 0);
}

test "Query: load for language (Markdown)" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const md_lang = languages.getLanguage("markdown").?;

    var query = try Query.loadForLanguage(allocator, "markdown", md_lang);
    defer query.deinit();

    // Verify query loaded from nested path
    try std.testing.expect(query.getCaptureCount() > 0);
    try std.testing.expect(query.getPatternCount() > 0);

    // Verify we have markdown-specific captures (text.title, punctuation.special, etc.)
    const names = try query.getCaptureNames(allocator);
    defer allocator.free(names);
    try std.testing.expect(names.len > 0);
}

test "Query: load for language (Markdown Inline)" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const md_inline_lang = languages.getLanguage("markdown_inline").?;

    var query = try Query.loadForLanguage(allocator, "markdown_inline", md_inline_lang);
    defer query.deinit();

    // Verify query loaded from nested path
    try std.testing.expect(query.getCaptureCount() > 0);
    try std.testing.expect(query.getPatternCount() > 0);

    // Verify we have inline-specific captures (text.emphasis, text.strong, etc.)
    const names = try query.getCaptureNames(allocator);
    defer allocator.free(names);
    try std.testing.expect(names.len > 0);
}

test "Query: syntax error handling" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const zig_lang = languages.getLanguage("zig").?;

    // Invalid syntax (missing closing paren)
    const invalid_source =
        \\(IDENTIFIER @function
    ;

    const result = Query.init(allocator, zig_lang, invalid_source);
    try std.testing.expectError(QueryError.SyntaxError, result);
}

test "Query: capture names" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const zig_lang = languages.getLanguage("zig").?;

    const source =
        \\(IDENTIFIER) @variable
        \\(BUILTINIDENTIFIER) @function.builtin
    ;

    var query = try Query.init(allocator, zig_lang, source);
    defer query.deinit();

    // Verify capture count
    try std.testing.expectEqual(@as(u32, 2), query.getCaptureCount());

    // Verify capture names
    const name0 = query.getCaptureName(0);
    const name1 = query.getCaptureName(1);

    try std.testing.expect(std.mem.eql(u8, name0, "variable") or std.mem.eql(u8, name0, "function.builtin"));
    try std.testing.expect(std.mem.eql(u8, name1, "variable") or std.mem.eql(u8, name1, "function.builtin"));
}

test "Query: loadInjectionQuery for markdown" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const md_lang = languages.getLanguage("markdown").?;

    var query = Query.loadInjectionQuery(allocator, "markdown", md_lang);
    try std.testing.expect(query != null);
    defer if (query) |*q| q.deinit();

    // Verify query has expected captures (injection.language, injection.content)
    const capture_count = query.?.getCaptureCount();
    try std.testing.expect(capture_count > 0);

    // Verify we have injection-related captures
    const names = try query.?.getCaptureNames(allocator);
    defer allocator.free(names);

    var has_injection_capture = false;
    for (names) |name| {
        if (std.mem.startsWith(u8, name, "injection.")) {
            has_injection_capture = true;
            break;
        }
    }
    try std.testing.expect(has_injection_capture);
}

test "Query: loadInjectionQuery for javascript" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    const js_lang = languages.getLanguage("javascript").?;

    var query = Query.loadInjectionQuery(allocator, "javascript", js_lang);
    try std.testing.expect(query != null);
    defer if (query) |*q| q.deinit();

    // JavaScript injections.scm should have captures for regex, jsdoc, etc.
    try std.testing.expect(query.?.getCaptureCount() > 0);
}

test "Query: loadInjectionQuery returns null for nonexistent" {
    const languages = @import("languages.zig");
    const allocator = std.testing.allocator;

    // Zig doesn't have a meaningful injections.scm
    const c_lang = languages.getLanguage("c").?;

    // Should return null for languages without injections.scm
    const query = Query.loadInjectionQuery(allocator, "nonexistent_lang", c_lang);
    try std.testing.expect(query == null);
}
