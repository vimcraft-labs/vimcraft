// E2E Test: Search Options (incSearch, wrapScan, ignoreCase, smartCase)
// Tests the search option behaviors implemented in editor.zig

// Setup: Create a test buffer with known content
vim.api.bufSetLines(0, 0, -1, false, [
    'Hello World',
    'hello world',
    'HELLO WORLD',
    'foo bar baz',
    'FOO BAR BAZ',
    'Foo Bar Baz'
]);
vim.e2e.keys("gg0"); // Go to start

// ============================================================================
// incSearch Tests
// ============================================================================

vim.e2e.describe("incSearch Option", function() {
    vim.e2e.test("incSearch=true moves cursor while typing", function() {
        vim.opt.incSearch = true;
        vim.e2e.keys("gg0"); // Start at beginning

        // Enter search mode and type pattern
        vim.e2e.keys("/foo");

        // Cursor should have moved to first match (line 3, "foo bar baz")
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 3, "incSearch should move cursor to match while typing");

        // Cancel search
        vim.e2e.keys("\x1b");
    });

    vim.e2e.test("incSearch=false does not move cursor while typing", function() {
        vim.opt.incSearch = false;
        vim.e2e.keys("gg0"); // Start at beginning

        const startCursor = vim.e2e.getCursor();

        // Enter search mode and type pattern
        vim.e2e.keys("/foo");

        // Cursor should NOT have moved yet (incSearch disabled)
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, startCursor.line, "incSearch=false should not move cursor while typing");

        // Cancel search
        vim.e2e.keys("\x1b");

        // Reset for other tests
        vim.opt.incSearch = true;
    });

    vim.e2e.test("incSearch shows matches while typing", function() {
        vim.opt.incSearch = true;
        vim.opt.hlSearch = true;
        vim.e2e.keys("gg0");

        // Type search pattern
        vim.e2e.keys("/Hello");

        // Should find match
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 0, "should find Hello on first line");

        vim.e2e.keys("\x1b");
    });
});

// ============================================================================
// wrapScan Tests
// ============================================================================

vim.e2e.describe("wrapScan Option", function() {
    vim.e2e.test("wrapScan=true wraps from bottom to top", function() {
        vim.opt.wrapScan = true;
        vim.opt.ignoreCase = false;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search for Foo (only on line 5)
        vim.e2e.keys("/Foo\r");

        // Should be on last line (line 5)
        let cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 5, "should find Foo on line 5");

        // Press n to go to next - should wrap to top (only one Foo)
        vim.e2e.keys("n");

        // Should wrap back to line 5 (only one Foo with that exact case)
        cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 5, "should wrap back to same match");
    });

    vim.e2e.test("wrapScan=true wraps from top to bottom with N", function() {
        vim.opt.wrapScan = true;
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search forward for Hello (case insensitive - lines 0, 1, 2)
        vim.e2e.keys("/hello\r");

        // Now at first hello (line 0)
        let cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 0, "should be at first Hello");

        // Press N (previous) - should wrap to bottom
        vim.e2e.keys("N");

        cursor = vim.e2e.getCursor();
        // Should wrap to last hello match (line 2: "HELLO WORLD")
        vim.e2e.assert.equal(cursor.line, 2, "N should wrap to last Hello match");
    });

    vim.e2e.test("wrapScan=false stops at boundary", function() {
        vim.opt.wrapScan = false;
        vim.opt.ignoreCase = false;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search for FOO (only on line 4)
        vim.e2e.keys("/FOO\r");

        let cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 4, "should find FOO on line 4");

        // Press n - should not wrap (only one match)
        vim.e2e.keys("n");

        cursor = vim.e2e.getCursor();
        // Should stay on line 4 (no wrap)
        vim.e2e.assert.equal(cursor.line, 4, "should stay on same line without wrapping");

        // Reset
        vim.opt.wrapScan = true;
    });
});

// ============================================================================
// ignoreCase Tests
// ============================================================================

vim.e2e.describe("ignoreCase Option", function() {
    vim.e2e.test("ignoreCase=false matches exact case only", function() {
        vim.opt.ignoreCase = false;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search for lowercase "hello"
        vim.e2e.keys("/hello\r");

        // Should find "hello world" on line 1 (0-indexed)
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 1, "should find lowercase hello on line 1");
    });

    vim.e2e.test("ignoreCase=true matches any case", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search for lowercase "hello"
        vim.e2e.keys("/hello\r");

        // Should find first occurrence (line 0: "Hello World")
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 0, "ignoreCase should match Hello on line 0");
    });

    vim.e2e.test("ignoreCase matches FOO with foo", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search for uppercase "FOO"
        vim.e2e.keys("/FOO\r");

        // Should find first foo (line 3 with ignoreCase)
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 3, "FOO should match foo on line 3 with ignoreCase");
    });

    vim.e2e.test("ignoreCase=false FOO only matches FOO", function() {
        vim.opt.ignoreCase = false;
        vim.opt.smartCase = false;
        vim.e2e.keys("gg0");

        // Search for uppercase "FOO"
        vim.e2e.keys("/FOO\r");

        // Should find FOO on line 4 only
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 4, "FOO should only match FOO on line 4");
    });
});

// ============================================================================
// smartCase Tests
// ============================================================================

vim.e2e.describe("smartCase Option", function() {
    vim.e2e.test("smartCase with lowercase pattern is case-insensitive", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.e2e.keys("gg0");

        // Search for lowercase "foo" - should be case-insensitive
        vim.e2e.keys("/foo\r");

        // Should find first occurrence (line 3: "foo bar baz")
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 3, "lowercase foo should match foo (case-insensitive)");
    });

    vim.e2e.test("smartCase with uppercase pattern is case-sensitive", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.e2e.keys("gg0");

        // Search for "Foo" (has uppercase) - should be case-sensitive
        vim.e2e.keys("/Foo\r");

        // Should find "Foo Bar Baz" on line 5 only
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 5, "Foo should only match Foo on line 5 (case-sensitive)");
    });

    vim.e2e.test("smartCase FOO only matches FOO", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.e2e.keys("gg0");

        // Search for "FOO" (all uppercase) - should be case-sensitive
        vim.e2e.keys("/FOO\r");

        // Should find "FOO BAR BAZ" on line 4 only
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 4, "FOO should only match FOO on line 4");
    });

    vim.e2e.test("smartCase Hello matches Hello only", function() {
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.e2e.keys("gg0");

        // Search for "Hello" (has uppercase)
        vim.e2e.keys("/Hello\r");

        // Should find "Hello World" on line 0 only
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 0, "Hello should match Hello on line 0");

        // n should go to... nowhere else has "Hello" with that exact case
        vim.e2e.keys("n");
        const cursor2 = vim.e2e.getCursor();
        // Should wrap back to same line (only one match)
        vim.e2e.assert.equal(cursor2.line, 0, "only one Hello match exists");
    });

    vim.e2e.test("smartCase disabled with ignoreCase=false", function() {
        vim.opt.ignoreCase = false;
        vim.opt.smartCase = true; // Should have no effect
        vim.e2e.keys("gg0");

        // Search for lowercase "hello"
        vim.e2e.keys("/hello\r");

        // Should find lowercase "hello world" on line 1
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 1, "smartCase should not apply when ignoreCase=false");
    });
});

// ============================================================================
// Combined Tests
// ============================================================================

vim.e2e.describe("Search Options Combined", function() {
    vim.e2e.test("all options work together", function() {
        vim.opt.incSearch = true;
        vim.opt.hlSearch = true;
        vim.opt.wrapScan = true;
        vim.opt.ignoreCase = true;
        vim.opt.smartCase = true;
        vim.e2e.keys("gg0");

        // Type search incrementally for lowercase "bar"
        vim.e2e.keys("/bar");

        // Should move cursor while typing (incSearch) - bar matches on lines 3, 4, 5
        let cursor = vim.e2e.getCursor();
        vim.e2e.assert.true(cursor.line >= 3 && cursor.line <= 5, "incSearch should find bar on lines 3-5");

        // Commit search
        vim.e2e.keys("\r");

        // Record first match
        const firstMatch = vim.e2e.getCursor().line;

        // Navigate with n (should find next bar - cycle through 3, 4, 5)
        vim.e2e.keys("n");
        cursor = vim.e2e.getCursor();
        vim.e2e.assert.true(cursor.line >= 3 && cursor.line <= 5, "n should find another bar match");
        vim.e2e.assert.true(cursor.line !== firstMatch, "n should move to different line");

        // Navigate more
        vim.e2e.keys("n");
        cursor = vim.e2e.getCursor();
        vim.e2e.assert.true(cursor.line >= 3 && cursor.line <= 5, "n should find third bar match");

        // One more - should wrap back (wrapScan is on)
        vim.e2e.keys("n");
        cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, firstMatch, "n should wrap to first match");
    });

    vim.e2e.test("vim.cmd.nohlsearch clears highlighting", function() {
        vim.opt.hlSearch = true;
        vim.e2e.keys("gg0");

        // Do a search
        vim.e2e.keys("/foo\r");

        // Clear highlighting
        vim.cmd.nohlsearch();

        // Pattern should still work with n
        vim.e2e.keys("n");
        const cursor = vim.e2e.getCursor();
        // Should still navigate (pattern preserved)
        vim.e2e.assert.true(cursor.line >= 3, "n should still work after nohlsearch");
    });
});

// Run all tests
const results = vim.e2e.runAll();
console.log("Search Options E2E tests:", results.passed, "passed,", results.failed, "failed");
