// Markdown Syntax Highlighting E2E Tests
// Tests that markdown content is typed correctly
vim.e2e.describe("Markdown Syntax Highlighting", function () {
    vim.e2e.test("buffer contains markdown content", function () {
        // Check buffer contains our typed content
        vim.e2e.assert.bufferContains("# Hello World");
        vim.e2e.assert.bufferContains("**bold**");
        vim.e2e.assert.bufferContains("## Section Two");
        vim.e2e.assert.bufferContains("- Item 1");
    });
    vim.e2e.test("buffer has correct structure", function () {
        const state = vim.e2e.getState();
        console.log("Mode:", state.mode);
        console.log("Lines:", state.buffer.lineCount);
        console.log("Cursor:", state.cursor.line, state.cursor.col);
        console.log("Buffer lines:", JSON.stringify(state.buffer.lines));
        // Should be back in NORMAL mode after ESC
        vim.e2e.assert.mode("NORMAL");
        // Should have 8 lines of markdown content
        vim.e2e.assert.true(state.buffer.lineCount >= 8, "Should have at least 8 lines");
        // Cursor should be at start (gg0)
        vim.e2e.assert.cursorAt(0, 0);
    });
    vim.e2e.test("filetype can be set and retrieved", function () {
        // Set filetype to markdown
        vim.bo.filetype = "markdown";
        // Verify we're still in working state
        vim.e2e.assert.mode("NORMAL");
        // Now verify the getter returns the correct value
        // (This was previously broken due to dangling pointer bug - fixed in buffer.zig:setFiletype)
        const ft = vim.bo.filetype;
        console.log("Filetype after set:", ft);
        vim.e2e.assert.equal(ft, "markdown", "filetype should be 'markdown'");
    });
    vim.e2e.test("syntax highlighting emits SGR codes", function () {
        // Filetype should already be set from config.ts
        // Start PTY capture to record terminal escape codes
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        // Trigger a render cycle
        vim.e2e.pty.render();
        // Count SGR codes (ESC[...m - color/attribute codes)
        const sgrCount = vim.e2e.pty.countSGRCodes();
        console.log("SGR codes emitted:", sgrCount);
        // Stop capture
        vim.e2e.pty.stopCapture();
        // With syntax highlighting, we should have many SGR codes for colors
        // Without highlighting, we'd have very few (just basic reset codes)
        // Markdown headings, bold, lists should generate color codes
        vim.e2e.assert.true(sgrCount > 10, "Should emit SGR codes for syntax highlighting (got " + sgrCount + ")");
    });
});
vim.e2e.runAll();
