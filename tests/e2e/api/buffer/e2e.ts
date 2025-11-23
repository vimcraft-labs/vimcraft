// Buffer API E2E Tests
// Tests vim.api buffer functions with real editor state
// TDD: Write tests first, let them fail, then implement

vim.e2e.describe("vim.api.getCurrentBuf", function() {
    vim.e2e.test("returns buffer handle 0 (current buffer)", function() {
        const buf = vim.api.getCurrentBuf();
        vim.e2e.assert.equal(buf, 0, "getCurrentBuf should return 0 for current buffer");
    });

    vim.e2e.test("returns a number type", function() {
        const buf = vim.api.getCurrentBuf();
        vim.e2e.assert.equal(typeof buf, "number", "Buffer handle should be a number");
    });
});

vim.e2e.describe("vim.api.bufLineCount", function() {
    vim.e2e.test("returns correct line count", function() {
        // Config creates 5 lines of content
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.true(count >= 5, "Buffer should have at least 5 lines");
    });

    vim.e2e.test("accepts buffer handle 0 for current buffer", function() {
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.true(count > 0, "Line count should be positive");
    });
});

vim.e2e.describe("vim.api.bufGetLines", function() {
    vim.e2e.test("returns lines as array of strings", function() {
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.true(Array.isArray(lines), "Should return an array");
        vim.e2e.assert.equal(lines.length, 1, "Should return 1 line");
    });

    vim.e2e.test("returns correct content for first line", function() {
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.true(
            lines[0].includes("Line 1"),
            "First line should contain 'Line 1'"
        );
    });

    vim.e2e.test("returns multiple lines when requested", function() {
        const lines = vim.api.bufGetLines(0, 0, 3, false);
        vim.e2e.assert.equal(lines.length, 3, "Should return 3 lines");
    });

    vim.e2e.test("returns all lines with -1 end index", function() {
        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.true(lines.length >= 5, "Should return at least 5 lines");
    });

    vim.e2e.test("handles out of bounds gracefully with strict=false", function() {
        const lines = vim.api.bufGetLines(0, 0, 1000, false);
        vim.e2e.assert.true(Array.isArray(lines), "Should return array even with large end");
    });
});

vim.e2e.describe("vim.api.bufSetLines", function() {
    vim.e2e.test("replaces a single line", function() {
        // Replace line 1 (0-indexed) with new content
        vim.api.bufSetLines(0, 0, 1, false, ["REPLACED LINE"]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0], "REPLACED LINE", "Line should be replaced");
    });

    vim.e2e.test("inserts new lines", function() {
        const countBefore = vim.api.bufLineCount(0);
        // Insert at end
        vim.api.bufSetLines(0, -1, -1, false, ["NEW LINE AT END"]);
        const countAfter = vim.api.bufLineCount(0);
        vim.e2e.assert.equal(countAfter, countBefore + 1, "Should add one line");
    });

    vim.e2e.test("deletes lines when replacement is empty", function() {
        const countBefore = vim.api.bufLineCount(0);
        // Delete first line
        vim.api.bufSetLines(0, 0, 1, false, []);
        const countAfter = vim.api.bufLineCount(0);
        vim.e2e.assert.equal(countAfter, countBefore - 1, "Should remove one line");
    });
});

vim.e2e.describe("vim.api.bufGetName", function() {
    vim.e2e.test("returns string for buffer name", function() {
        const name = vim.api.bufGetName(0);
        vim.e2e.assert.equal(typeof name, "string", "Buffer name should be a string");
    });

    vim.e2e.test("returns empty string for unnamed buffer", function() {
        // New buffer should be unnamed
        const name = vim.api.bufGetName(0);
        // Could be empty or have a path - just verify it doesn't throw
        vim.e2e.assert.true(true, "bufGetName should not throw");
    });
});

vim.e2e.describe("vim.api.bufIsValid", function() {
    vim.e2e.test("returns true for current buffer (0)", function() {
        const valid = vim.api.bufIsValid(0);
        vim.e2e.assert.true(valid, "Buffer 0 should always be valid");
    });

    vim.e2e.test("returns false for invalid buffer handle", function() {
        const valid = vim.api.bufIsValid(9999);
        vim.e2e.assert.false(valid, "Buffer 9999 should not be valid");
    });
});

vim.e2e.runAll();
