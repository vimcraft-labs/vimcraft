// E2E Test: Substitute Command (:s/pattern/replacement/[flags])
// Tests the substitute command implementation in editor.zig

// ============================================================================
// Basic Substitution Tests
// ============================================================================

vim.e2e.describe("Basic Substitute", function() {
    vim.e2e.test("basic substitution replaces first match", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo bar foo baz'
        ]);
        vim.e2e.keys("gg0");

        // Substitute first foo with hello
        vim.e2e.keys(":s/foo/hello/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hello bar foo baz", "should replace first foo only");
    });

    vim.e2e.test("empty replacement deletes matched text", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello //\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "world", "should delete hello and space");
    });

    vim.e2e.test("replacement with longer text", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'a b c'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/b/longer/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "a longer c", "should replace with longer text");
    });

    vim.e2e.test("replacement with shorter text", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/hi/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hi world", "should replace with shorter text");
    });
});

// ============================================================================
// g Flag Tests (Global - all matches on line)
// ============================================================================

vim.e2e.describe("g Flag (Global)", function() {
    vim.e2e.test("g flag replaces all matches on line", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo bar foo baz foo'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/foo/x/g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "x bar x baz x", "should replace all foo with x");
    });

    vim.e2e.test("g flag with no matches does nothing", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        // This should not error with 'e' flag
        vim.e2e.keys(":s/xyz/abc/ge\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hello world", "line should be unchanged");
    });

    vim.e2e.test("g flag deletes all matches when replacement empty", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'a-b-c-d'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/-//g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "abcd", "should delete all dashes");
    });
});

// ============================================================================
// i Flag Tests (Case Insensitive)
// ============================================================================

vim.e2e.describe("i Flag (Case Insensitive)", function() {
    vim.e2e.test("i flag matches regardless of case", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'Hello HELLO hello'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/X/i\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "X HELLO hello", "should replace first Hello (any case)");
    });

    vim.e2e.test("i flag with g flag replaces all case variants", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'Hello HELLO hello HeLLo'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/X/gi\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "X X X X", "should replace all case variants");
    });

    vim.e2e.test("without i flag is case sensitive", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'Hello HELLO hello'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/X/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "Hello HELLO X", "should only replace exact case match");
    });
});

// ============================================================================
// smartCase Tests
// ============================================================================

vim.e2e.describe("smartCase Option", function() {
    vim.e2e.test("smartCase with lowercase pattern is case-insensitive", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo Foo FOO'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/foo/X/g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "X X X", "lowercase pattern matches all case variants");
    });

    vim.e2e.test("smartCase with uppercase pattern is case-sensitive", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo Foo FOO'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/Foo/X/g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "foo X FOO", "uppercase pattern only matches exact case");
    });

    vim.e2e.test("i flag overrides smartCase", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo Foo FOO'
        ]);
        vim.e2e.keys("gg0");

        // 'i' flag should force case-insensitive despite uppercase in pattern
        vim.e2e.keys(":s/FOO/X/gi\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "X X X", "i flag overrides smartCase");
    });

    vim.e2e.test("smartCase disabled when ignoreCase is false", function() {
        vim.opt.ignoreCase = false;
        vim.opt.smartCase = true;
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo Foo FOO'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/foo/X/g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "X Foo FOO", "smartCase has no effect when ignoreCase=false");
    });
});

// ============================================================================
// e Flag Tests (No Error on Pattern Not Found)
// ============================================================================

vim.e2e.describe("e Flag (No Error)", function() {
    vim.e2e.test("e flag suppresses error when pattern not found", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        // Without e flag, pattern not found would show error
        // With e flag, it should silently do nothing
        vim.e2e.keys(":s/xyz/abc/e\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hello world", "line should be unchanged");
        // Test passes if no error occurred
    });

    vim.e2e.test("e flag still replaces when pattern found", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/hi/e\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hi world", "should still replace when found");
    });
});

// ============================================================================
// n Flag Tests (Count Only, No Replace)
// ============================================================================

vim.e2e.describe("n Flag (Count Only)", function() {
    vim.e2e.test("n flag counts matches without replacing", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo bar foo baz foo'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/foo/x/n\r");

        // Line should be unchanged
        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "foo bar foo baz foo", "line should be unchanged with n flag");
    });

    vim.e2e.test("n flag with g counts all matches", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'aaa bbb aaa ccc aaa'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/aaa/x/gn\r");

        // Line should still be unchanged
        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "aaa bbb aaa ccc aaa", "line unchanged with gn flags");
    });
});

// ============================================================================
// Empty Pattern Tests (Reuse Last Search)
// ============================================================================

vim.e2e.describe("Empty Pattern (Reuse Last Search)", function() {
    vim.e2e.test("empty pattern reuses last search pattern", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo bar foo baz'
        ]);
        vim.e2e.keys("gg0");

        // First do a search to set the pattern
        vim.e2e.keys("/foo\r");

        // Now substitute with empty pattern
        vim.e2e.keys(":s//replaced/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "replaced bar foo baz", "should use last search pattern");
    });

    vim.e2e.test("empty pattern with g flag", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'test test test'
        ]);
        vim.e2e.keys("gg0");

        // Set search pattern
        vim.e2e.keys("/test\r");

        // Substitute all with empty pattern
        vim.e2e.keys(":s//X/g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "X X X", "should replace all with last search pattern");
    });
});

// ============================================================================
// Alternate Delimiter Tests
// ============================================================================

vim.e2e.describe("Alternate Delimiter", function() {
    vim.e2e.test("pipe delimiter works", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo/bar/baz'
        ]);
        vim.e2e.keys("gg0");

        // Use | as delimiter to avoid escaping /
        vim.e2e.keys(":s|/|-|g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "foo-bar-baz", "should work with pipe delimiter");
    });

    vim.e2e.test("hash delimiter works", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'path/to/file'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s#/#-#g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "path-to-file", "should work with hash delimiter");
    });
});

// ============================================================================
// Escaped Delimiter Tests
// ============================================================================

vim.e2e.describe("Escaped Delimiter", function() {
    vim.e2e.test("escaped delimiter in pattern", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'a/b/c'
        ]);
        vim.e2e.keys("gg0");

        // Escape the / in pattern
        vim.e2e.keys(":s/\\//X/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "aXb/c", "should match escaped delimiter");
    });

    vim.e2e.test("escaped delimiter in replacement", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/a\\/b/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "a/b", "should insert escaped delimiter in replacement");
    });
});

// ============================================================================
// Undo/Redo Tests
// ============================================================================

vim.e2e.describe("Undo/Redo", function() {
    vim.e2e.test("substitute can be undone", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'original text'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/original/modified/\r");

        let lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "modified text", "should be modified");

        // Undo
        vim.e2e.keys("u");

        lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "original text", "should be undone");
    });

    vim.e2e.test("substitute can be redone", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'original text'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/original/modified/\r");
        vim.e2e.keys("u");  // Undo
        vim.e2e.keys("\x12");  // Ctrl-R for redo

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "modified text", "should be redone");
    });

    vim.e2e.test("global substitute undone as single operation", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'foo foo foo'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/foo/bar/g\r");

        let lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "bar bar bar", "all should be replaced");

        // Single undo should restore all
        vim.e2e.keys("u");

        lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "foo foo foo", "single undo should restore all");
    });
});

// ============================================================================
// Edge Cases
// ============================================================================

vim.e2e.describe("Edge Cases", function() {
    vim.e2e.test("substitute at start of line", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/hi/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hi world", "should replace at start");
    });

    vim.e2e.test("substitute at end of line", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello world'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/world/universe/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "hello universe", "should replace at end");
    });

    vim.e2e.test("substitute entire line", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/hello/world/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "world", "should replace entire line content");
    });

    vim.e2e.test("substitute with special characters", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'hello.world'
        ]);
        vim.e2e.keys("gg0");

        // Note: . is literal in substitute (not regex)
        vim.e2e.keys(":s/./X/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        // First . should be replaced
        vim.e2e.assert.equal(lines[0], "helloXworld", "should replace literal dot");
    });

    vim.e2e.test("substitute on empty line does nothing", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            ''
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/foo/bar/e\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "", "empty line stays empty");
    });

    vim.e2e.test("overlapping matches", function() {
        vim.api.bufSetLines(0, 0, -1, false, [
            'aaa'
        ]);
        vim.e2e.keys("gg0");

        // Pattern 'aa' appears twice overlapping in 'aaa'
        // Vim replaces non-overlapping: aa -> X leaves a, so "Xa"
        vim.e2e.keys(":s/aa/X/g\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "Xa", "should handle overlapping patterns");
    });

    // Note: Unicode pattern/replacement tests are skipped because vim.e2e.keys()
    // doesn't support multi-byte UTF-8 input yet. The substitute implementation
    // itself correctly handles UTF-8 (byte-based comparison works for UTF-8).
    // TODO: Add Unicode tests when keyboard input supports multi-byte characters.

    vim.e2e.test("substitute with unicode in content (ASCII pattern)", function() {
        // Test that substitute works correctly when the line contains unicode
        // but the pattern is ASCII
        vim.api.bufSetLines(0, 0, -1, false, [
            'Hello 世界 World'
        ]);
        vim.e2e.keys("gg0");

        vim.e2e.keys(":s/World/Earth/\r");

        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines[0], "Hello 世界 Earth", "should work with unicode in content");
    });
});

// Run all tests
const results = vim.e2e.runAll();
console.log("Substitute Command E2E tests:", results.passed, "passed,", results.failed, "failed");
