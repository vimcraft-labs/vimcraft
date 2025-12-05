// Test floating window positioning to ensure no cursor overlap
vim.e2e.describe("floating window position", function() {

    vim.e2e.test("floating window col offset avoids cursor", function() {
        // Set up buffer with text
        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetLines(buf, 0, -1, false, [
            "line one",
            "line two",
            "line three",
            "line four",
        ]);

        // Move cursor using keys (more reliable than winSetCursor in tests)
        vim.e2e.keys('jllll');  // Down one line, right 4 cols

        // Create floating window with col: 4 offset
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["preview content"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 1,
            col: 4,  // Should position window 4 cols right of cursor
            width: 20,
            height: 3,
            border: 'rounded',
            style: 'minimal',
        });

        vim.e2e.assert.true(floatWin !== null, "floating window should be created");

        // Get the window config to verify position
        const config = vim.api.winGetConfig(floatWin);
        vim.e2e.assert.true(config !== null, "should get window config");

        // The col offset should be >= 4 (no overlap with cursor)
        vim.e2e.assert.true(config.col >= 4,
            `floating window col (${config.col}) should be >= 4 to avoid cursor overlap`);

        // Clean up
        vim.api.winClose(floatWin, true);
    });

    vim.e2e.test("col: 0 would overlap cursor", function() {
        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetLines(buf, 0, -1, false, ["test line"]);
        vim.api.winSetCursor(0, [1, 5]);

        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["content"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 1,
            col: 0,  // This would overlap!
            width: 10,
            height: 2,
            border: 'single',
            style: 'minimal',
        });

        const config = vim.api.winGetConfig(floatWin);

        // col: 0 means window starts at cursor position (overlap)
        vim.e2e.assert.equal(config.col, 0, "col: 0 starts at cursor (overlap)");

        vim.api.winClose(floatWin, true);
    });

    vim.e2e.test("col: 4 provides safe clearance", function() {
        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetLines(buf, 0, -1, false, ["some text here"]);
        vim.api.winSetCursor(0, [1, 3]);

        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["Hunk 1 of 4", "+added line"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 1,
            col: 4,  // Safe clearance
            width: 15,
            height: 3,
            border: 'rounded',
            style: 'minimal',
        });

        const config = vim.api.winGetConfig(floatWin);

        // Window should be at least 4 cols away from cursor
        // Cursor at col 3, window border starts at col 3+4=7
        // This means there's a gap between cursor and window
        vim.e2e.assert.true(config.col >= 4,
            `col offset ${config.col} should be >= 4 for safe clearance`);

        vim.api.winClose(floatWin, true);
    });

    vim.e2e.test("floating window uses NormalFloat highlight (occludes cursorline)", function() {
        // This test verifies that floating windows use NormalFloat highlight
        // which has an explicit background, preventing CursorLine from bleeding through

        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetLines(buf, 0, -1, false, ["test line one", "test line two"]);

        // Enable cursorline
        vim.opt.cursorLine = true;

        // Set NormalFloat to have a distinct background
        vim.highlight('NormalFloat', { bg: '#2a2b3c' });

        // Create floating window
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["popup content"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 0,
            col: 4,
            width: 15,
            height: 2,
            border: 'rounded',
            style: 'minimal',
        });

        // Window should be valid
        vim.e2e.assert.true(vim.api.winIsValid(floatWin), "floating window should be valid");

        // Clean up
        vim.api.winClose(floatWin, true);
    });

    vim.e2e.test("floating window auto-closes on cursor move", function() {
        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetLines(buf, 0, -1, false, [
            "line one",
            "line two",
            "line three",
        ]);

        // Create floating window
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["preview"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 0,
            col: 4,
            width: 10,
            height: 2,
            border: 'rounded',
            style: 'minimal',
        });

        // Window should exist
        vim.e2e.assert.true(floatWin !== null, "window should be created");
        vim.e2e.assert.true(vim.api.winIsValid(floatWin), "window should be valid");

        // Set up CursorMoved autocmd to close the window (like previewHunk does)
        vim.api.createAutocmd('CursorMoved', {
            callback: () => {
                try {
                    vim.api.winClose(floatWin, true);
                } catch (_) {}
                return true;
            },
            once: true,
        });

        // Move cursor - this should trigger autocmd and close window
        vim.e2e.keys('j');

        // Window should now be closed
        vim.e2e.assert.true(!vim.api.winIsValid(floatWin),
            "window should be closed after cursor move");
    });

    // === SCROLL BUG TESTS ===
    // Bug: Opening floating window when cursor is on scrolled line causes:
    // 1. Viewport to jump
    // 2. Popup to appear at wrong position

    vim.e2e.test("scrolled viewport: opening float should NOT jump viewport", function() {
        const buf = vim.api.getCurrentBuf();

        // Create 300 lines (enough to require scrolling)
        const lines: string[] = [];
        for (let i = 0; i < 300; i++) {
            lines.push("Line " + (i + 1) + ": content for testing scroll bug");
        }
        vim.api.bufSetLines(buf, 0, -1, false, lines);

        // Move cursor to line 228 (deep in file, definitely scrolled)
        vim.e2e.keys('228G');

        // Capture cursor position BEFORE opening float
        const cursorBefore = vim.api.winGetCursor(0);
        console.log("Cursor BEFORE float:", JSON.stringify(cursorBefore));

        vim.e2e.assert.equal(cursorBefore[0], 228, "cursor should be at line 228 before float");

        // Open floating window exactly like git-bundle previewHunk does
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, [
            "Hunk 1 of 4",
            "+added line 1",
            "+added line 2"
        ]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 0,
            col: 4,
            width: 30,
            height: 4,
            border: 'rounded',
            style: 'minimal',
        });

        // Capture cursor position AFTER opening float
        const cursorAfter = vim.api.winGetCursor(0);
        console.log("Cursor AFTER float:", JSON.stringify(cursorAfter));

        // BUG: If cursor jumped, the viewport likely jumped too
        vim.e2e.assert.equal(cursorAfter[0], cursorBefore[0],
            "BUG: cursor line jumped from " + cursorBefore[0] + " to " + cursorAfter[0]);
        vim.e2e.assert.equal(cursorAfter[1], cursorBefore[1],
            "BUG: cursor col jumped from " + cursorBefore[1] + " to " + cursorAfter[1]);

        // Clean up
        vim.api.winClose(floatWin, true);
    });

    vim.e2e.test("<leader>gp simulation: float at scrolled position", function() {
        vim.mapleader = ' ';

        const buf = vim.api.getCurrentBuf();

        // Create 200 lines
        const lines: string[] = [];
        for (let i = 0; i < 200; i++) {
            lines.push("Line " + (i + 1));
        }
        vim.api.bufSetLines(buf, 0, -1, false, lines);

        // Track positions for debugging
        let cursorWhenCallbackRuns: [number, number] | null = null;
        let floatWinId: number | null = null;

        // Set up <leader>gp exactly like git-bundle
        vim.keymap.set('n', '<leader>gp', function() {
            cursorWhenCallbackRuns = vim.api.winGetCursor(0);
            console.log("Inside callback, cursor:", JSON.stringify(cursorWhenCallbackRuns));

            const previewBuf = vim.api.createBuf(false, true);
            vim.api.bufSetLines(previewBuf, 0, -1, false, ["Hunk preview", "+line"]);

            floatWinId = vim.api.openWin(previewBuf, false, {
                relative: 'cursor',
                row: 0,
                col: 4,
                width: 20,
                height: 3,
                border: 'rounded',
                style: 'minimal',
            });
        });

        // Move to line 150 (scrolled position)
        vim.e2e.keys('150G');

        const cursorBeforeLeader = vim.api.winGetCursor(0);
        console.log("Before <leader>gp:", JSON.stringify(cursorBeforeLeader));
        vim.e2e.assert.equal(cursorBeforeLeader[0], 150, "Should be at line 150");

        // Execute <leader>gp (space + g + p)
        vim.e2e.keys(' gp');

        // Check callback ran
        vim.e2e.assert.true(cursorWhenCallbackRuns !== null, "Callback should have run");
        vim.e2e.assert.true(floatWinId !== null && floatWinId > 0, "Float window should exist");

        // BUG CHECK: Inside the callback, cursor should still be at line 150
        if (cursorWhenCallbackRuns) {
            vim.e2e.assert.equal(cursorWhenCallbackRuns[0], 150,
                "BUG: Cursor jumped to " + cursorWhenCallbackRuns[0] + " during callback (expected 150)");
        }

        // Final cursor check
        const cursorFinal = vim.api.winGetCursor(0);
        console.log("Final cursor:", JSON.stringify(cursorFinal));
        vim.e2e.assert.equal(cursorFinal[0], 150,
            "BUG: Final cursor at " + cursorFinal[0] + " (expected 150)");

        // Clean up
        if (floatWinId) {
            vim.api.winClose(floatWinId, true);
        }
    });

    vim.e2e.test("PTY capture: float renders at correct screen row", function() {
        const buf = vim.api.getCurrentBuf();

        // Create 50 lines
        const lines: string[] = [];
        for (let i = 0; i < 50; i++) {
            lines.push("Line " + (i + 1) + " test");
        }
        vim.api.bufSetLines(buf, 0, -1, false, lines);

        // Move to line 25 (may or may not scroll depending on terminal height)
        vim.e2e.keys('25G');

        vim.e2e.pty.startCapture();

        // Open float with unique text
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["UNIQUE_MARKER_123"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 1,
            col: 2,
            width: 20,
            height: 2,
            border: 'single',
            style: 'minimal',
        });

        vim.e2e.pty.render();
        vim.e2e.pty.stopCapture();

        // Check floating window was created
        vim.e2e.assert.true(floatWin > 0, "Floating window should be created");

        // Verify it by checking window is valid
        vim.e2e.assert.true(vim.api.winIsValid(floatWin), "Floating window should be valid");

        // Clean up
        vim.api.winClose(floatWin, true);
    });

    vim.e2e.test("float window absolute position calculation (scrolled)", function() {
        const buf = vim.api.getCurrentBuf();

        // Create 100 lines
        const lines: string[] = [];
        for (let i = 0; i < 100; i++) {
            lines.push("Line " + (i + 1) + " test");
        }
        vim.api.bufSetLines(buf, 0, -1, false, lines);

        // Move to line 80 (definitely scrolled)
        vim.e2e.keys('80G');

        const cursor = vim.api.winGetCursor(0);
        console.log("Cursor at:", JSON.stringify(cursor));
        vim.e2e.assert.equal(cursor[0], 80, "Cursor should be at line 80");

        // Open floating window
        const floatBuf = vim.api.createBuf(false, true);
        vim.api.bufSetLines(floatBuf, 0, -1, false, ["Float content"]);

        const floatWin = vim.api.openWin(floatBuf, false, {
            relative: 'cursor',
            row: 0,
            col: 4,
            width: 15,
            height: 2,
            border: 'rounded',
            style: 'minimal',
        });

        // Get window config
        const config = vim.api.winGetConfig(floatWin);
        console.log("Float config:", JSON.stringify(config));

        // The stored config should have the original relative offsets
        vim.e2e.assert.equal(config.relative, 'cursor', "Relative should be 'cursor'");
        vim.e2e.assert.equal(config.row, 0, "Row offset should be 0");
        vim.e2e.assert.equal(config.col, 4, "Col offset should be 4");

        // Check cursor didn't move
        const cursorAfter = vim.api.winGetCursor(0);
        console.log("Cursor after:", JSON.stringify(cursorAfter));
        vim.e2e.assert.equal(cursorAfter[0], 80, "Cursor should still be at line 80");

        vim.api.winClose(floatWin, true);
    });
});

vim.e2e.runAll();
