// ============================================================================
// PERF-TREESITTER: Test with REAL source file + syntax highlighting
// ============================================================================
// This tests the FULL render pipeline including tree-sitter parsing
// ============================================================================

vim.e2e.describe("Tree-sitter Performance", function() {

    vim.e2e.test("open .zig file: 50j < 300ms", function() {
        // Enable ALL options like user config
        vim.opt.signcolumn = "yes";
        vim.opt.number = true;
        vim.opt.relativeNumber = true;
        vim.opt.cursorLine = true;

        // Open a REAL source file with tree-sitter syntax
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50j (.zig file + tree-sitter): " + elapsed + "ms (" + (elapsed/50).toFixed(2) + "ms/move)");
        vim.e2e.assert.true(elapsed <= 300, "50j (.zig) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("open .ts file: 50j < 300ms", function() {
        // Open TypeScript file
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/system/jsi/runtime.ts\r");
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50j (.ts file + tree-sitter): " + elapsed + "ms (" + (elapsed/50).toFixed(2) + "ms/move)");
        vim.e2e.assert.true(elapsed <= 300, "50j (.ts) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("large file: 100j < 500ms", function() {
        // Open a large source file
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/editor/buffer/buffer.zig\r");
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(100));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100j (large .zig): " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 500, "100j (large .zig) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("O(n) scaling with syntax", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start10 = Date.now();
        vim.e2e.keys("j".repeat(10));
        vim.e2e.pty.render();
        const time10 = Math.max(Date.now() - start10, 1);

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start100 = Date.now();
        vim.e2e.keys("j".repeat(100));
        vim.e2e.pty.render();
        const time100 = Date.now() - start100;

        const ratio = time100 / time10;
        console.log("[BENCH] O(n) with syntax: 10j=" + time10 + "ms, 100j=" + time100 + "ms, ratio=" + ratio.toFixed(2) + "x");

        vim.e2e.assert.true(ratio <= 15, "Ratio " + ratio.toFixed(2) + "x suggests O(n^2)!");
    });
});

const results = vim.e2e.runAll();
console.log("\n=== TREE-SITTER PERF: " + results.passed + " passed, " + results.failed + " failed ===");
