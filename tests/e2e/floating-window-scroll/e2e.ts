// Test floating window positioning when viewport is scrolled
// Bug: Opening floating window at cursor causes viewport to jump

vim.e2e.describe("floating window scroll bug", function() {

    vim.e2e.test("opening floating window should not change viewport", function() {
        const buf = vim.api.getCurrentBuf();

        // Create 300 lines of content
        const lines: string[] = [];
        for (let i = 0; i < 300; i++) {
            lines.push(`Line ${i + 1}: some content here`);
        }
        vim.api.bufSetLines(buf, 0, -1, false, lines);

        // Move cursor to line 228 (simulating the bug scenario)
        vim.e2e.keys('228G');

        // Get viewport state BEFORE opening floating window
        const cursorBefore = vim.api.winGetCursor(0);
        const viewportTopBefore = vim.fn.line('w0');  // First visible line

        vim.e2e.assert.equal(cursorBefore[0], 228, "cursor should be on line 228");

        // Create floating window relative to cursor
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["Hunk 1 of 4", "+added line"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 0,
            col: 4,
            width: 20,
            height: 3,
            border: 'rounded',
            style: 'minimal',
        });

        // Get viewport state AFTER opening floating window
        const cursorAfter = vim.api.winGetCursor(0);
        const viewportTopAfter = vim.fn.line('w0');

        // Viewport should NOT have changed
        vim.e2e.assert.equal(cursorAfter[0], cursorBefore[0],
            `cursor line should not change: was ${cursorBefore[0]}, now ${cursorAfter[0]}`);
        vim.e2e.assert.equal(viewportTopAfter, viewportTopBefore,
            `viewport top should not change: was ${viewportTopBefore}, now ${viewportTopAfter}`);

        // Clean up
        if (floatWin) {
            vim.api.winClose(floatWin, true);
        }
    });

    vim.e2e.test("floating window position is correct when scrolled", function() {
        const buf = vim.api.getCurrentBuf();

        // Create 300 lines
        const lines: string[] = [];
        for (let i = 0; i < 300; i++) {
            lines.push(`Line ${i + 1}`);
        }
        vim.api.bufSetLines(buf, 0, -1, false, lines);

        // Move to line 150
        vim.e2e.keys('150G');

        const cursor = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(cursor[0], 150, "cursor should be on line 150");

        // Open floating window
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["popup"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 1,
            col: 2,
            width: 10,
            height: 2,
            border: 'single',
            style: 'minimal',
        });

        // Get floating window config to verify position
        const config = vim.api.winGetConfig(floatWin);

        // The row/col in config should match what we requested
        vim.e2e.assert.equal(config.row, 1, "float window row offset should be 1");
        vim.e2e.assert.equal(config.col, 2, "float window col offset should be 2");

        vim.api.winClose(floatWin, true);
    });
});

vim.e2e.runAll();
