// Window API E2E Tests
// Tests vim.api window functions with real editor state
// TDD: Write tests first, let them fail, then implement

vim.e2e.describe("vim.api.getCurrentWin", function() {
    vim.e2e.test("returns window handle 0 (current window)", function() {
        const win = vim.api.getCurrentWin();
        vim.e2e.assert.equal(win, 0, "getCurrentWin should return 0 for current window");
    });

    vim.e2e.test("returns a number type", function() {
        const win = vim.api.getCurrentWin();
        vim.e2e.assert.equal(typeof win, "number", "Window handle should be a number");
    });
});

vim.e2e.describe("vim.api.winGetCursor", function() {
    vim.e2e.test("returns cursor position as [row, col]", function() {
        // Cursor should be at start after config.ts runs gg0
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(Array.isArray(pos), "Should return an array");
        vim.e2e.assert.equal(pos.length, 2, "Should return [row, col]");
    });

    vim.e2e.test("row is 1-indexed (Neovim convention)", function() {
        // After gg0, cursor at first line
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 1, "First line should be row 1 (1-indexed)");
    });

    vim.e2e.test("col is 0-indexed (Neovim convention)", function() {
        // After gg0, cursor at first column
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[1], 0, "First column should be col 0 (0-indexed)");
    });

    vim.e2e.test("reflects cursor movement", function() {
        // First go to known position, then move
        vim.e2e.keys("gg0");  // Go to start
        vim.e2e.keys("jj");   // Move down 2 lines (to line 3, 1-indexed)
        vim.e2e.keys("lllll"); // Move right 5 cols
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 3, "Should be on line 3");
        vim.e2e.assert.equal(pos[1], 5, "Should be at column 5");
    });
});

vim.e2e.describe("vim.api.winSetCursor", function() {
    vim.e2e.test("sets cursor to specified position", function() {
        // Set cursor to line 2, col 3
        vim.api.winSetCursor(0, [2, 3]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 2, "Row should be 2");
        vim.e2e.assert.equal(pos[1], 3, "Col should be 3");
    });

    vim.e2e.test("clamps to valid line range", function() {
        // Try to set cursor beyond buffer
        vim.api.winSetCursor(0, [100, 0]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(pos[0] <= 5, "Row should be clamped to buffer size");
    });

    vim.e2e.test("clamps to valid column range", function() {
        // Set to line 1, then try invalid column
        vim.api.winSetCursor(0, [1, 1000]);
        const pos = vim.api.winGetCursor(0);
        // Column should be clamped to line length
        vim.e2e.assert.true(pos[1] < 1000, "Col should be clamped to line length");
    });
});

vim.e2e.describe("vim.api.winIsValid", function() {
    vim.e2e.test("returns true for current window (0)", function() {
        const valid = vim.api.winIsValid(0);
        vim.e2e.assert.true(valid, "Window 0 should always be valid");
    });

    vim.e2e.test("returns false for invalid window handle", function() {
        const valid = vim.api.winIsValid(9999);
        vim.e2e.assert.false(valid, "Window 9999 should not be valid");
    });
});

vim.e2e.describe("vim.api.winGetBuf", function() {
    vim.e2e.test("returns buffer handle for window", function() {
        const buf = vim.api.winGetBuf(0);
        vim.e2e.assert.equal(buf, 0, "Window 0 should contain buffer 0");
    });
});

vim.e2e.describe("vim.api.winGetHeight", function() {
    vim.e2e.test("returns window height as number", function() {
        const height = vim.api.winGetHeight(0);
        vim.e2e.assert.equal(typeof height, "number", "Height should be a number");
        vim.e2e.assert.true(height > 0, "Height should be positive");
    });
});

vim.e2e.describe("vim.api.winGetWidth", function() {
    vim.e2e.test("returns window width as number", function() {
        const width = vim.api.winGetWidth(0);
        vim.e2e.assert.equal(typeof width, "number", "Width should be a number");
        vim.e2e.assert.true(width > 0, "Width should be positive");
    });
});

vim.e2e.runAll();
