// E2E Test: Gitsigns rendering in sign column
// Tests the full workflow: signColumn = "yes" + extmarks with signText → visible signs

vim.e2e.describe("gitsigns rendering", function() {

    vim.e2e.test("sign is rendered with correct character", function() {
        const ns = vim.api.createNamespace("gitsigns_simple");
        const bufnr = vim.api.getCurrentBuf();

        // Add content to the buffer
        vim.api.bufSetLines(bufnr, 0, -1, false, ["Hello world", "Line 2", "Line 3"]);

        // Set a sign with "+" character on line 0
        vim.api.bufSetExtmark(bufnr, ns, 0, 0, {
            signText: "+",
            signHlGroup: "GitSignsAdd"
        });

        // Capture terminal output
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        vim.e2e.pty.stopCapture();

        // The sign "+" should appear in the output
        const plusCount = vim.e2e.pty.countSequence("+");
        vim.e2e.assert.true(plusCount > 0, "sign '+' should appear in terminal output");
    });
});

// Run tests and show results
const results = vim.e2e.runAll();
console.log("Tests:", results.passed, "passed,", results.failed, "failed");
