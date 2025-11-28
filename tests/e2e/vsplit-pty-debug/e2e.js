// PTY debug test - analyze actual cursor position escape codes
vim.e2e.describe("vsplit PTY cursor rendering", function () {
    vim.e2e.test("analyze cursor position codes during vsplit navigation", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");
        // Reset cursor state for clean capture
        vim.e2e.pty.resetCursorState();
        // Start capture BEFORE movement
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        // Single j movement and render
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        const output = vim.e2e.pty.getOutput();
        const cursorCodes = vim.e2e.pty.countCursorPositionCodes();
        // Get current cursor state
        const cursorState = vim.e2e.getCursor();
        console.log("=== CURSOR POSITION ANALYSIS ===");
        console.log("Cursor state after j: line=" + cursorState.line + " col=" + cursorState.col);
        console.log("Total cursor position codes: " + cursorCodes);
        console.log("PTY output length: " + output.length);
        // Extract and log cursor position sequences
        let sequences = [];
        for (let i = 0; i < output.length - 3; i++) {
            if (output.charCodeAt(i) === 0x1b && output.charAt(i + 1) === '[') {
                let j = i + 2;
                while (j < output.length && j < i + 15) {
                    if (output.charAt(j) === 'H' || output.charAt(j) === 'f') {
                        sequences.push(output.substring(i + 2, j));
                        break;
                    }
                    if ((output.charCodeAt(j) >= 65 && output.charCodeAt(j) <= 90) ||
                        (output.charCodeAt(j) >= 97 && output.charCodeAt(j) <= 122 && output.charAt(j) !== 'f')) {
                        break;
                    }
                    j++;
                }
            }
        }
        console.log("Cursor position sequences (row;col format): " + sequences.join(" | "));
        vim.e2e.pty.stopCapture();
        // The test is informational
        vim.e2e.assert.true(true, "Analysis complete");
    });
    vim.e2e.test("check window dimensions after vsplit", function () {
        vim.e2e.keys(":only\r");
        const fullWidth = vim.api.winGetWidth(0);
        const fullHeight = vim.api.winGetHeight(0);
        console.log("Single window: width=" + fullWidth + " height=" + fullHeight);
        vim.e2e.keys(":vsplit\r");
        // Get both windows
        const wins = vim.api.listWins();
        console.log("Windows after vsplit: " + wins.length);
        // Current window (left, new one)
        const leftWidth = vim.api.winGetWidth(0);
        const leftPos = vim.api.winGetPosition(0);
        console.log("Left window: width=" + leftWidth + " pos=[" + leftPos[0] + "," + leftPos[1] + "]");
        // The vsplit should create two windows side by side
        vim.e2e.assert.true(leftWidth < fullWidth, "Left window should be narrower");
    });
    vim.e2e.test("cursor movement doesn't change window", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");
        const winBefore = vim.api.getCurrentWin();
        console.log("Window before movements: " + winBefore);
        // Multiple movements
        vim.e2e.keys("jjjjj");
        const winAfterJ = vim.api.getCurrentWin();
        console.log("Window after jjjjj: " + winAfterJ);
        vim.e2e.keys("lllll");
        const winAfterL = vim.api.getCurrentWin();
        console.log("Window after lllll: " + winAfterL);
        vim.e2e.keys("kkkkk");
        const winAfterK = vim.api.getCurrentWin();
        console.log("Window after kkkkk: " + winAfterK);
        vim.e2e.keys("hhhhh");
        const winAfterH = vim.api.getCurrentWin();
        console.log("Window after hhhhh: " + winAfterH);
        // Window should NOT change during hjkl
        vim.e2e.assert.equal(winBefore, winAfterJ, "Window shouldn't change on j");
        vim.e2e.assert.equal(winBefore, winAfterL, "Window shouldn't change on l");
        vim.e2e.assert.equal(winBefore, winAfterK, "Window shouldn't change on k");
        vim.e2e.assert.equal(winBefore, winAfterH, "Window shouldn't change on h");
    });
    vim.e2e.test("verify per-window cursor isolation", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");
        // Now in left window (new one)
        const leftWin = vim.api.getCurrentWin();
        console.log("Left window ID: " + leftWin);
        // Move cursor in left window
        vim.e2e.keys("jjjll");
        const leftCursor = vim.api.winGetCursor(0);
        console.log("Left window cursor after jjjll: [" + leftCursor[0] + "," + leftCursor[1] + "]");
        // Switch to right window
        vim.e2e.keys("\x17l");
        const rightWin = vim.api.getCurrentWin();
        console.log("Right window ID: " + rightWin);
        const rightCursor = vim.api.winGetCursor(0);
        console.log("Right window cursor (should be at start): [" + rightCursor[0] + "," + rightCursor[1] + "]");
        // Move cursor in right window
        vim.e2e.keys("jl");
        const rightCursorAfter = vim.api.winGetCursor(0);
        console.log("Right window cursor after jl: [" + rightCursorAfter[0] + "," + rightCursorAfter[1] + "]");
        // Switch back to left window
        vim.e2e.keys("\x17h");
        const backToLeftCursor = vim.api.winGetCursor(0);
        console.log("Back to left window cursor: [" + backToLeftCursor[0] + "," + backToLeftCursor[1] + "]");
        // Left window should have PRESERVED its cursor at jjjll position
        vim.e2e.assert.equal(backToLeftCursor[0], leftCursor[0], "Left window row should be preserved");
        vim.e2e.assert.equal(backToLeftCursor[1], leftCursor[1], "Left window col should be preserved");
        // Cursors should be DIFFERENT between windows
        vim.e2e.assert.true(leftCursor[0] !== rightCursorAfter[0] || leftCursor[1] !== rightCursorAfter[1], "Windows should have different cursor positions");
    });
});
vim.e2e.runAll();
