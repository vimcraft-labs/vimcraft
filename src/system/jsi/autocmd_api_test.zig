/// Unit tests for AutoCommand API (vim.api.createAutoCommand)
/// Following TDD principles: Tests specify correct behavior
///
/// NOTE: Tests that require full Hermes runtime (JavaScript evaluation) are
/// skipped because the lean build doesn't support hermes_evaluate_javascript.
/// Pattern matching tests (pure Zig) always run.
///
/// For full integration testing, use debug protocol tests.
const std = @import("std");
const testing = std.testing;
const autocmd_api = @import("autocmd_api.zig");

// ============================================================================
// Pattern Matching Tests (Pure Zig - ALWAYS run, no Hermes needed)
// ============================================================================

test "matchPattern: empty pattern behavior" {
    // Empty pattern doesn't match non-empty filenames
    try testing.expect(!autocmd_api.matchPattern("", "file.js"));
    // Empty pattern matches empty filename (exact match case)
    try testing.expect(autocmd_api.matchPattern("", ""));
}

test "matchPattern: case sensitivity" {
    // Pattern matching should be case-sensitive (like Neovim)
    try testing.expect(autocmd_api.matchPattern("*.JS", "file.JS"));
    try testing.expect(!autocmd_api.matchPattern("*.JS", "file.js"));
    try testing.expect(!autocmd_api.matchPattern("*.js", "file.JS"));
}

test "matchPattern: glob patterns" {
    // *.js matches .js files
    try testing.expect(autocmd_api.matchPattern("*.js", "foo.js"));
    try testing.expect(autocmd_api.matchPattern("*.js", "/path/to/bar.js"));
    try testing.expect(!autocmd_api.matchPattern("*.js", "foo.ts"));

    // * matches everything
    try testing.expect(autocmd_api.matchPattern("*", "anything.txt"));
    try testing.expect(autocmd_api.matchPattern("*", ""));

    // Exact match
    try testing.expect(autocmd_api.matchPattern("Makefile", "Makefile"));
    try testing.expect(autocmd_api.matchPattern("Makefile", "/path/to/Makefile"));
}

test "matchPattern: extension edge cases" {
    // Multiple dots in filename
    try testing.expect(autocmd_api.matchPattern("*.js", "foo.bar.js"));
    try testing.expect(autocmd_api.matchPattern("*.min.js", "app.min.js"));
    try testing.expect(!autocmd_api.matchPattern("*.min.js", "app.js"));

    // Hidden files with extension
    try testing.expect(autocmd_api.matchPattern("*.js", ".hidden.js"));

    // No extension
    try testing.expect(!autocmd_api.matchPattern("*.js", "README"));
    try testing.expect(autocmd_api.matchPattern("README", "README"));
}

test "matchPattern: TypeScript/JavaScript files" {
    // TypeScript
    try testing.expect(autocmd_api.matchPattern("*.ts", "index.ts"));
    try testing.expect(autocmd_api.matchPattern("*.tsx", "App.tsx"));
    try testing.expect(!autocmd_api.matchPattern("*.ts", "index.tsx"));

    // JavaScript
    try testing.expect(autocmd_api.matchPattern("*.js", "index.js"));
    try testing.expect(autocmd_api.matchPattern("*.jsx", "App.jsx"));
    try testing.expect(!autocmd_api.matchPattern("*.js", "index.jsx"));

    // Type definition files
    try testing.expect(autocmd_api.matchPattern("*.d.ts", "types.d.ts"));
    try testing.expect(!autocmd_api.matchPattern("*.d.ts", "types.ts"));
}

test "matchPattern: path handling" {
    // Full paths with extension matching
    try testing.expect(autocmd_api.matchPattern("*.zig", "/Users/test/src/main.zig"));
    try testing.expect(autocmd_api.matchPattern("*.zig", "src/editor/buffer.zig"));

    // Basename matching
    try testing.expect(autocmd_api.matchPattern("build.zig", "/project/build.zig"));
    try testing.expect(autocmd_api.matchPattern("build.zig", "build.zig"));
    try testing.expect(!autocmd_api.matchPattern("build.zig", "other.zig"));

    // Common config files
    try testing.expect(autocmd_api.matchPattern("*.json", "package.json"));
    try testing.expect(autocmd_api.matchPattern("*.json", "tsconfig.json"));
    try testing.expect(autocmd_api.matchPattern("*.toml", "Cargo.toml"));
}

// ============================================================================
// AutocmdManager Tests (Require full Hermes - skipped in lean build)
// ============================================================================
//
// NOTE: The following tests are intentionally commented out because they
// require full Hermes runtime with JavaScript evaluation support, which
// is not available in the lean build (hermes_lean).
//
// To run these tests:
// 1. Build with full Hermes instead of hermes_lean
// 2. Or use integration tests via debug protocol
//
// The tests are preserved here as documentation of expected behavior:
//
// test "AutocmdManager: createAutoCommand returns incrementing IDs"
// test "AutocmdManager: createAutoCommand registers for multiple events"
// test "AutocmdManager: createAutoCommand stores pattern correctly"
// test "AutocmdManager: createAutoCommand stores group correctly"
// test "AutocmdManager: deleteAutoCommand removes autocommand by ID"
// test "AutocmdManager: deleteAutoCommand is idempotent"
// test "AutocmdManager: deleteAutoCommand with invalid ID does nothing"
// test "AutocmdManager: clearGroup removes all autocommands in group"
// test "AutocmdManager: clearGroup with nonexistent group does nothing"
// test "AutoCommand: full workflow - create, verify, delete"
// test "AutoCommand: once flag removes autocommand after execution"
