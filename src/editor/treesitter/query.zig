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

/// Zig wrapper for TSQuery (owns the C query pointer)
/// Lifetime: Query owns TSQuery, caller must call deinit()
pub const Query = struct {
    query: *c.TSQuery,
    allocator: std.mem.Allocator,
    source: []const u8, // Keep source for debugging/error messages

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

    /// Load query from language name
    /// Automatically resolves path to vendor/tree-sitter-{lang}/queries/highlights.scm
    ///
    /// Parameters:
    /// - language_name: Language identifier ("zig", "javascript", etc.)
    /// - language: TSLanguage pointer for that language
    ///
    /// Example:
    ///   const query = try Query.loadForLanguage(allocator, "zig", tree_sitter_zig());
    pub fn loadForLanguage(
        allocator: std.mem.Allocator,
        language_name: []const u8,
        language: *const c.TSLanguage,
    ) QueryError!Query {
        // SPECIAL CASE: Markdown has nested directory structure
        // tree-sitter-markdown/tree-sitter-markdown/queries/highlights.scm (block-level)
        // tree-sitter-markdown/tree-sitter-markdown-inline/queries/highlights.scm (inline)
        if (std.mem.eql(u8, language_name, "markdown")) {
            const md_path = "vendor/tree-sitter-markdown/tree-sitter-markdown/queries/highlights.scm";
            return try loadFromFile(allocator, language, md_path);
        }

        // SPECIAL CASE: Markdown inline parser (for inline elements: bold, italic, links)
        if (std.mem.eql(u8, language_name, "markdown_inline")) {
            const md_inline_path = "vendor/tree-sitter-markdown/tree-sitter-markdown-inline/queries/highlights.scm";
            return try loadFromFile(allocator, language, md_inline_path);
        }

        // SPECIAL CASE: TypeScript needs JavaScript base highlights
        // TypeScript-specific highlights.scm only has 35 lines (types, interfaces)
        // JavaScript highlights.scm has 204 lines (keywords, functions, strings, etc.)
        if (std.mem.eql(u8, language_name, "typescript")) {
            // Load JavaScript base highlights
            const js_path = "vendor/tree-sitter-javascript/queries/highlights.scm";
            const js_file = std.fs.cwd().openFile(js_path, .{}) catch {
                return QueryError.FileNotFound;
            };
            defer js_file.close();

            const js_source = js_file.readToEndAlloc(allocator, 1024 * 1024) catch {
                return QueryError.OutOfMemory;
            };
            defer allocator.free(js_source);

            // Load TypeScript-specific highlights
            const ts_path = "vendor/tree-sitter-typescript/queries/highlights.scm";
            const ts_file = std.fs.cwd().openFile(ts_path, .{}) catch {
                return QueryError.FileNotFound;
            };
            defer ts_file.close();

            const ts_source = ts_file.readToEndAlloc(allocator, 1024 * 1024) catch {
                return QueryError.OutOfMemory;
            };
            defer allocator.free(ts_source);

            // Combine both queries (JavaScript base + TypeScript specifics)
            const combined_source = try std.fmt.allocPrint(
                allocator,
                "{s}\n; TypeScript-specific highlights\n{s}",
                .{ js_source, ts_source },
            );
            defer allocator.free(combined_source);

            // Compile combined query
            return try init(allocator, language, combined_source);
        }

        // Standard case: Load single highlights.scm file
        const path = try std.fmt.allocPrint(
            allocator,
            "vendor/tree-sitter-{s}/queries/highlights.scm",
            .{language_name},
        );
        defer allocator.free(path);

        return try loadFromFile(allocator, language, path);
    }

    /// Free query resources
    pub fn deinit(self: *Query) void {
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
