/// Tree-sitter Parser Wrapper
/// Zig-friendly wrapper around TSParser C API
///
/// Architecture:
/// - TSParser (C): Stateful parser object (parses source code into syntax trees)
/// - Parser (Zig): RAII wrapper with init/deinit (owns C parser pointer)
/// - TSTree (C): Immutable syntax tree (returned by parseString)
///
/// Usage:
///   var parser = try Parser.init(allocator);
///   defer parser.deinit();
///
///   try parser.setLanguage(tree_sitter_rust());
///   const tree = try parser.parseString(null, source_code);
///   defer c.ts_tree_delete(tree);
///
/// Future enhancements:
/// - Tree wrapper (RAII for TSTree)
/// - Incremental parsing (reuse old tree)
/// - Query execution (highlights.scm)
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Parser errors (Zig-style error union)
pub const ParserError = error{
    ParserCreationFailed,
    LanguageVersionMismatch,
    ParseFailed,
};

/// Zig wrapper for TSParser (owns the C parser pointer)
/// Lifetime: Parser owns TSParser, caller owns TSTree
pub const Parser = struct {
    parser: *c.TSParser,
    allocator: std.mem.Allocator,

    /// Create a new parser
    /// Caller owns returned Parser and must call deinit()
    pub fn init(allocator: std.mem.Allocator) ParserError!Parser {
        const parser = c.ts_parser_new() orelse return ParserError.ParserCreationFailed;
        return Parser{
            .parser = parser,
            .allocator = allocator,
        };
    }

    /// Free parser resources
    pub fn deinit(self: *Parser) void {
        c.ts_parser_delete(self.parser);
    }

    /// Set the language for parsing
    /// Returns error if language ABI version is incompatible
    ///
    /// Language ABI version must be between:
    /// - Min: TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION (13)
    /// - Max: TREE_SITTER_LANGUAGE_VERSION (15)
    pub fn setLanguage(self: *Parser, language: *const c.TSLanguage) ParserError!void {
        if (!c.ts_parser_set_language(self.parser, language)) {
            return ParserError.LanguageVersionMismatch;
        }
    }

    /// Parse a string into a syntax tree
    ///
    /// Parameters:
    /// - old_tree: Previous tree for incremental parsing (null for full parse)
    /// - source: UTF-8 source code bytes
    ///
    /// Returns:
    /// - Owned TSTree pointer (caller must call ts_tree_delete)
    ///
    /// Performance:
    /// - Full parse: O(n) where n = source length
    /// - Incremental: O(m) where m = changed bytes (reuses unchanged subtrees)
    pub fn parseString(self: *Parser, old_tree: ?*c.TSTree, source: []const u8) ParserError!*c.TSTree {
        const tree = c.ts_parser_parse_string(
            self.parser,
            old_tree,
            source.ptr,
            @intCast(source.len),
        ) orelse return ParserError.ParseFailed;
        return tree;
    }

    /// Reset the parser (clears internal state)
    /// Use this when switching to a different document
    pub fn reset(self: *Parser) void {
        c.ts_parser_reset(self.parser);
    }

    /// Get the current language
    /// Returns null if no language has been set
    pub fn getLanguage(self: *Parser) ?*const c.TSLanguage {
        return c.ts_parser_language(self.parser);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Parser: init and deinit" {
    const allocator = std.testing.allocator;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Parser is created (if init() succeeded, parser is non-null)
    // Verify no language is set initially
    try std.testing.expect(parser.getLanguage() == null);
}

test "Parser: reset" {
    const allocator = std.testing.allocator;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Reset should not crash (no language set)
    parser.reset();
}

// Note: setLanguage and parseString tests require actual language parsers
// (e.g., tree-sitter-rust, tree-sitter-javascript) which will be added in Week 1 Task 2
// For now, we verify that the Parser wrapper compiles and basic operations work
