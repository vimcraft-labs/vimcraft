/// Tree-sitter Build Module
/// Configures tree-sitter core library and language parsers
const std = @import("std");

/// Tree-sitter core C source files
const tree_sitter_sources = [_][]const u8{
    "alloc.c",
    "get_changed_ranges.c",
    "language.c",
    "lexer.c",
    "node.c",
    "parser.c",
    "point.c",
    "query.c",
    "stack.c",
    "subtree.c",
    "tree_cursor.c",
    "tree.c",
    "wasm_store.c",
};

/// Add tree-sitter core library to a compile step
pub fn addTreeSitterCore(b: *std.Build, step: *std.Build.Step.Compile) void {
    // Include paths
    step.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    step.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Core source files
    step.addCSourceFiles(.{
        .root = b.path("vendor/tree-sitter/lib/src"),
        .files = &tree_sitter_sources,
        .flags = &.{"-std=c11"},
    });

    // POSIX compatibility macros
    step.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    step.root_module.addCMacro("_DEFAULT_SOURCE", "");
    step.root_module.addCMacro("_DARWIN_C_SOURCE", "");
}

/// Add tree-sitter language parser include paths
pub fn addLanguageParserIncludes(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    step.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    step.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    step.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    step.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    step.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    step.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));
}

/// Add bundled language parsers (C, Zig, JS, TS, TSX, Markdown)
pub fn addLanguageParsers(b: *std.Build, step: *std.Build.Step.Compile) void {
    const c_flags = &[_][]const u8{"-std=c11"};

    // C parser
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-c/src/parser.c"),
        .flags = c_flags,
    });

    // Zig parser
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = c_flags,
    });

    // JavaScript parser (with external scanner)
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/parser.c"),
        .flags = c_flags,
    });
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/scanner.c"),
        .flags = c_flags,
    });

    // TypeScript parser (with scanner)
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/parser.c"),
        .flags = c_flags,
    });
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/scanner.c"),
        .flags = c_flags,
    });

    // TSX parser (with scanner)
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/parser.c"),
        .flags = c_flags,
    });
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/scanner.c"),
        .flags = c_flags,
    });

    // Markdown parser (with scanner)
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"),
        .flags = c_flags,
    });
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"),
        .flags = c_flags,
    });

    // Markdown inline parser (with scanner)
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"),
        .flags = c_flags,
    });
    step.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"),
        .flags = c_flags,
    });
}

/// Add all tree-sitter components (core + language parsers)
pub fn addAll(b: *std.Build, step: *std.Build.Step.Compile) void {
    addTreeSitterCore(b, step);
    addLanguageParserIncludes(b, step);
    addLanguageParsers(b, step);
}
