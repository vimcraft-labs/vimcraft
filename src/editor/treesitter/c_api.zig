/// Tree-sitter C API wrapper
/// Provides Zig-friendly interface to tree-sitter C library
///
/// Architecture:
/// - Core library: vendor/tree-sitter/lib/src/*.c (13 C source files)
/// - C API: tree_sitter/api.h (types, parser, tree, query, cursor)
/// - This module: Import C API via @cImport, re-export common types
///
/// Usage:
///   const ts = @import("c_api.zig");
///   const parser = ts.c.ts_parser_new();
///   defer ts.c.ts_parser_delete(parser);
const std = @import("std");

// Import tree-sitter C API with POSIX macros (required on Unix-like systems)
pub const c = @cImport({
    // POSIX compatibility (required by tree-sitter core library)
    @cDefine("_POSIX_C_SOURCE", "200112L");
    @cDefine("_DEFAULT_SOURCE", "");
    @cDefine("_DARWIN_C_SOURCE", "");

    // Tree-sitter API header (parser, tree, query, cursor)
    @cInclude("tree_sitter/api.h");
});

// Re-export common types for convenience (Zig-style naming)
pub const TSParser = c.TSParser;
pub const TSTree = c.TSTree;
pub const TSNode = c.TSNode;
pub const TSQuery = c.TSQuery;
pub const TSQueryCursor = c.TSQueryCursor;
pub const TSQueryMatch = c.TSQueryMatch;
pub const TSQueryCapture = c.TSQueryCapture;
pub const TSPoint = c.TSPoint;
pub const TSRange = c.TSRange;
pub const TSLanguage = c.TSLanguage;
pub const TSInput = c.TSInput;
pub const TSInputEncoding = c.TSInputEncoding;
pub const TSSymbol = c.TSSymbol;
pub const TSFieldId = c.TSFieldId;

// Common constants
pub const TREE_SITTER_LANGUAGE_VERSION = c.TREE_SITTER_LANGUAGE_VERSION;
pub const TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION = c.TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION;

// Test that C API is importable
test "c_api: import tree-sitter C API" {
    // Verify ABI version constants are defined
    try std.testing.expect(TREE_SITTER_LANGUAGE_VERSION == 15); // Current ABI version
    try std.testing.expect(TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION == 13); // Min compatible
}
