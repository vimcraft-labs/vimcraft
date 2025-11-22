// E2E Test: Basic Navigation
// Tests vim.e2e API for cursor movement and mode changes

vim.e2e.describe("Basic Navigation", function() {
    vim.e2e.test("cursor starts at (0, 0)", function() {
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 0, "line should be 0");
        vim.e2e.assert.equal(cursor.col, 0, "col should be 0");
    });

    vim.e2e.test("mode starts as NORMAL", function() {
        vim.e2e.assert.mode("NORMAL");
    });

    vim.e2e.test("j key moves cursor down", function() {
        vim.e2e.keys("j");
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 1, "cursor should move to line 1");
    });

    vim.e2e.test("k key moves cursor up", function() {
        vim.e2e.keys("k");
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 0, "cursor should move back to line 0");
    });
});

vim.e2e.describe("Mode Transitions", function() {
    vim.e2e.test("i enters INSERT mode", function() {
        vim.e2e.keys("i");
        vim.e2e.assert.mode("INSERT");
    });

    vim.e2e.test("Escape returns to NORMAL mode", function() {
        vim.e2e.keys("\x1b"); // ESC
        vim.e2e.assert.mode("NORMAL");
    });
});

// Run all tests and report results
const results = vim.e2e.runAll();
console.log("E2E tests completed:", results.passed, "passed,", results.failed, "failed");
