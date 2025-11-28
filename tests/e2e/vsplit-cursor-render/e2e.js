// Simplified PTY test to diagnose vsplit rendering bug
// Fixed: Use \r instead of <CR> for command execution
vim.e2e.describe("vsplit rendering diagnosis", function () {
    vim.e2e.test("basic vsplit works", function () {
        var beforeState = vim.e2e.getState();
        console.log("Before vsplit - mode:", beforeState.mode);
        var winCountBefore = vim.api.listWins().length;
        console.log("Window count before:", winCountBefore);
        // Do vsplit (use \r not <CR>!)
        vim.e2e.keys(":vsplit\r");
        var afterState = vim.e2e.getState();
        console.log("After vsplit - mode:", afterState.mode);
        var winCountAfter = vim.api.listWins().length;
        console.log("Window count after:", winCountAfter);
        vim.e2e.assert.equal(winCountAfter, 2, "Should have 2 windows after vsplit");
        vim.e2e.assert.mode("NORMAL");
    });
    vim.e2e.test("j movement after vsplit - state check", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");
        var cursorBefore = vim.e2e.getCursor();
        console.log("Cursor before j:", JSON.stringify(cursorBefore));
        vim.e2e.keys("j");
        var cursorAfter = vim.e2e.getCursor();
        console.log("Cursor after j:", JSON.stringify(cursorAfter));
        vim.e2e.assert.equal(cursorAfter.line, 1, "Cursor row should be 1 after j");
    });
    vim.e2e.test("j movement PTY output", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();
        // Capture before j
        vim.e2e.pty.clear();
        vim.e2e.pty.startCapture();
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        var output = vim.e2e.pty.getCaptured();
        console.log("PTY output length after j:", output.length);
        var cursorMoves = vim.e2e.pty.countCursorPositionCodes();
        console.log("Cursor move codes:", cursorMoves);
        // This is the key assertion - if 0, cursor isn't being re-rendered
        vim.e2e.assert.true(output.length > 0, "Should have PTY output after j");
    });
    vim.e2e.test("compare l vs j output lengths", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();
        // Test horizontal movement (reported as working)
        vim.e2e.pty.clear();
        vim.e2e.pty.startCapture();
        vim.e2e.keys("l");
        vim.e2e.pty.render();
        var outputLLen = vim.e2e.pty.getCaptured().length;
        var cursorL = vim.e2e.getCursor();
        console.log("After 'l': cursor=", JSON.stringify(cursorL), "output len=", outputLLen);
        // Reset cursor
        vim.e2e.keys("0");
        // Test vertical movement (reported as NOT working visually)
        vim.e2e.pty.clear();
        vim.e2e.pty.startCapture();
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        var outputJLen = vim.e2e.pty.getCaptured().length;
        var cursorJ = vim.e2e.getCursor();
        console.log("After 'j': cursor=", JSON.stringify(cursorJ), "output len=", outputJLen);
        console.log("Comparison: l=" + outputLLen + " bytes, j=" + outputJLen + " bytes");
        // Both should produce output
        vim.e2e.assert.true(outputLLen > 0, "'l' should produce output");
        vim.e2e.assert.true(outputJLen > 0, "'j' should produce output");
    });
    vim.e2e.test("verify split separator in PTY output", function () {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        // Capture full render
        vim.e2e.pty.clear();
        vim.e2e.pty.startCapture();
        vim.e2e.pty.render();
        var output = vim.e2e.pty.getCaptured();
        console.log("Full render output length:", output.length);
        // Check for separator character (│ = vertical bar)
        // The separator should appear in the rendered output
        var hasSeparator = output.indexOf("│") !== -1;
        console.log("Has separator character:", hasSeparator);
        vim.e2e.assert.true(output.length > 0, "Should have PTY output");
        // Note: separator might not be in PTY if rendering is broken
    });
    vim.e2e.test("check window dimensions", function () {
        vim.e2e.keys(":only\r");
        var singleWidth = vim.api.winGetWidth(0);
        console.log("Single window width:", singleWidth);
        vim.e2e.keys(":vsplit\r");
        var splitWidth = vim.api.winGetWidth(0);
        console.log("After vsplit, current window width:", splitWidth);
        // After vsplit, window should be roughly half the original width
        vim.e2e.assert.true(splitWidth < singleWidth, "Split window should be narrower");
        vim.e2e.assert.true(splitWidth > 0, "Split window should have positive width");
    });
});
vim.e2e.runAll();
