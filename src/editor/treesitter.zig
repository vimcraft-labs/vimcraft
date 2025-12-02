/// Tree-sitter Module
/// Central export point for all tree-sitter functionality
///
/// This module re-exports all tree-sitter components for easy importing:
/// - C API wrapper (c_api.zig)
/// - Parser wrapper (parser.zig)
/// - Language parsers (languages.zig)
/// - Query system (query.zig)
/// - Loader integration (loader.zig)
///
/// Usage:
///   const treesitter = @import("editor/treesitter.zig");
///   var parser = try treesitter.Parser.init(allocator);
///   const lang = treesitter.getLanguage("zig");
const std = @import("std");

// Re-export C API wrapper
pub const c_api = @import("treesitter/c_api.zig");
pub const c = c_api.c;

// Re-export core types
pub const Parser = @import("treesitter/parser.zig").Parser;
pub const ParserError = @import("treesitter/parser.zig").ParserError;

// Re-export language registry
pub const getLanguage = @import("treesitter/languages.zig").getLanguage;
pub const listLanguages = @import("treesitter/languages.zig").listLanguages;

// Re-export query system
pub const Query = @import("treesitter/query.zig").Query;
pub const QueryError = @import("treesitter/query.zig").QueryError;

// Re-export highlight iterator
pub const HighlightIterator = @import("treesitter/highlight.zig").HighlightIterator;
pub const Highlight = @import("treesitter/highlight.zig").Highlight;
pub const Range = @import("treesitter/highlight.zig").Range;
pub const IteratorError = @import("treesitter/highlight.zig").IteratorError;

// Re-export syntax manager
pub const Syntax = @import("treesitter/syntax.zig").Syntax;
pub const SyntaxError = @import("treesitter/syntax.zig").SyntaxError;

// Re-export predicates module (for injection processing)
pub const predicates = @import("treesitter/predicates.zig");
pub const Metadata = predicates.Metadata;
pub const processMatchPredicates = predicates.processMatchPredicates;
pub const getOffsetAdjustment = predicates.getOffsetAdjustment;

// Re-export LanguageTree (recursive parser management)
pub const language_tree = @import("treesitter/language_tree.zig");
pub const LanguageTree = language_tree.LanguageTree;
pub const LanguageTreeError = language_tree.LanguageTreeError;
pub const Range6 = language_tree.Range6;

// Re-export filetype loader
pub const Loader = @import("treesitter/loader.zig").Loader;

// Re-export syntax highlighter (adapts tree-sitter to rendering)
pub const syntax_highlighter = @import("treesitter/syntax_highlighter.zig");
pub const SyntaxHighlighter = syntax_highlighter.SyntaxHighlighter;
pub const StyledHighlight = syntax_highlighter.StyledHighlight;
pub const StyledHighlightIterator = syntax_highlighter.StyledHighlightIterator;
pub const LanguageTreeHighlighter = syntax_highlighter.LanguageTreeHighlighter;
pub const MultiTreeStyledHighlightIterator = syntax_highlighter.MultiTreeStyledHighlightIterator;

// Import test files to ensure they run
test {
    std.testing.refAllDecls(@This());
    _ = @import("treesitter/c_api.zig");
    _ = @import("treesitter/parser.zig");
    _ = @import("treesitter/languages.zig");
    _ = @import("treesitter/query.zig");
    _ = @import("treesitter/highlight.zig");
    _ = @import("treesitter/syntax.zig");
    _ = @import("treesitter/predicates.zig");
    _ = @import("treesitter/language_tree.zig");
    _ = @import("treesitter/loader.zig");
    _ = @import("treesitter/syntax_highlighter.zig");
}
