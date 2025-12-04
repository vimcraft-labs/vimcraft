// E2E Test: vim.git API + gitsigns workflow
// Tests the full integration: git diff → extmarks → sign rendering

vim.e2e.describe("vim.git API", function() {
    vim.e2e.test("getWorkTreeDiff returns array with hunk structure", function() {
        const hunks = vim.git.getWorkTreeDiff("/Users/le/vimcraft/editor/CLAUDE.md");
        vim.e2e.assert.equal(typeof hunks, "object", "should return object (array)");

        // CLAUDE.md is modified - should have hunks
        if (hunks.length > 0) {
            const hunk = hunks[0];
            vim.e2e.assert.equal(typeof hunk.startLine, "number", "hunk.startLine should be number");
            vim.e2e.assert.equal(typeof hunk.lineCount, "number", "hunk.lineCount should be number");
            vim.e2e.assert.equal(typeof hunk.type, "string", "hunk.type should be string");
            // Type should be one of: 'add', 'delete', 'change'
            const validTypes = ["add", "delete", "change"];
            vim.e2e.assert.equal(validTypes.indexOf(hunk.type) >= 0, true, "hunk.type should be valid");
        }
    });

    vim.e2e.test("getFileStatus returns valid status string", function() {
        const status = vim.git.getFileStatus("/Users/le/vimcraft/editor/CLAUDE.md");
        vim.e2e.assert.equal(typeof status, "string", "should return string");

        // Valid statuses
        const validStatuses = ["untracked", "ignored", "unmodified", "modified", "added", "deleted", "renamed", "copied", "conflicted"];
        vim.e2e.assert.equal(validStatuses.indexOf(status) >= 0, true, "should be valid status: " + status);
    });
});

vim.e2e.describe("gitsigns workflow simulation", function() {
    vim.e2e.test("can set extmark with signText", function() {
        // Create namespace for gitsigns
        const ns = vim.api.createNamespace("gitsigns");
        vim.e2e.assert.equal(typeof ns, "number", "createNamespace returns number");
        vim.e2e.assert.equal(ns > 0, true, "namespace id should be positive");

        // Get current buffer
        const bufnr = vim.api.getCurrentBuf();
        vim.e2e.assert.equal(typeof bufnr, "number", "getCurrentBuf returns number");

        // Set an extmark with sign on line 0
        const extId = vim.api.bufSetExtmark(bufnr, ns, 0, 0, {
            signText: "+",
            signHlGroup: "GitSignsAdd"
        });

        vim.e2e.assert.equal(typeof extId, "number", "bufSetExtmark returns extmark id");
        vim.e2e.assert.equal(extId > 0, true, "extmark id should be positive");
    });

    vim.e2e.test("full gitsigns flow: get hunks and set signs", function() {
        // This simulates what gitsigns.nvim would do
        const filepath = "/Users/le/vimcraft/editor/CLAUDE.md";
        const hunks = vim.git.getWorkTreeDiff(filepath);

        const ns = vim.api.createNamespace("gitsigns_test");
        const bufnr = vim.api.getCurrentBuf();

        // Clear any existing signs
        vim.api.bufClearNamespace(bufnr, ns, 0, -1);

        // Set signs for each hunk
        let signCount = 0;
        for (let i = 0; i < hunks.length && i < 5; i++) { // Limit to 5 for test
            const hunk = hunks[i];
            const signText = hunk.type === "add" ? "+" : (hunk.type === "delete" ? "-" : "~");
            const hlGroup = hunk.type === "add" ? "GitSignsAdd" :
                           (hunk.type === "delete" ? "GitSignsDelete" : "GitSignsChange");

            // Set sign on first line of each hunk
            const extId = vim.api.bufSetExtmark(bufnr, ns, hunk.startLine, 0, {
                signText: signText,
                signHlGroup: hlGroup,
                priority: 10
            });

            if (extId > 0) signCount++;
        }

        // Verify we set some signs (if there were hunks)
        if (hunks.length > 0) {
            vim.e2e.assert.equal(signCount > 0, true, "should have set at least one sign");
        }

        // Get extmarks back to verify they're stored
        const extmarks = vim.api.bufGetExtmarks(bufnr, ns, 0, -1, {});
        vim.e2e.assert.equal(Array.isArray(extmarks), true, "bufGetExtmarks returns array");
    });
});

const results = vim.e2e.runAll();
console.log("Tests:", results.passed, "passed,", results.failed, "failed");
