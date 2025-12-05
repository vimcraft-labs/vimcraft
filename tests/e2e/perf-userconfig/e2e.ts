// ============================================================================
// PERF-USERCONFIG: Test with FULL user config simulation
// ============================================================================
// This is the closest we can get to replicating user's actual experience
// ============================================================================

vim.e2e.describe("User Config Performance", function() {

    vim.e2e.test("open main.zig: 50j < 300ms", function() {
        // Open a real source file
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50j (full user config): " + elapsed + "ms (" + (elapsed/50).toFixed(2) + "ms/move)");
        vim.e2e.assert.true(elapsed <= 300, "50j took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("100j with config: < 500ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(100));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100j (full config): " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 500, "100j took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("rapid jk alternating: < 300ms", function() {
        vim.e2e.keys("50j");
        vim.e2e.pty.render();

        const start = Date.now();
        for (let i = 0; i < 50; i++) {
            vim.e2e.keys("jk");
        }
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50 jk (full config): " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 300, "50 jk took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("O(n) scaling", function() {
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
        console.log("[BENCH] O(n): 10j=" + time10 + "ms, 100j=" + time100 + "ms, ratio=" + ratio.toFixed(2) + "x");

        vim.e2e.assert.true(ratio <= 15, "Ratio " + ratio.toFixed(2) + "x suggests O(n^2)!");
    });

    vim.e2e.test("single j latency", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        // Measure single keystroke 10 times
        let totalMs = 0;
        for (let i = 0; i < 10; i++) {
            const start = Date.now();
            vim.e2e.keys("j");
            vim.e2e.pty.render();
            totalMs += Date.now() - start;
        }
        const avgMs = totalMs / 10;

        console.log("[BENCH] Single j avg: " + avgMs.toFixed(2) + "ms");
        vim.e2e.assert.true(avgMs <= 10, "Single j avg " + avgMs.toFixed(2) + "ms - TOO SLOW!");
    });
});

const results = vim.e2e.runAll();
console.log("\n=== USER CONFIG PERF: " + results.passed + " passed, " + results.failed + " failed ===");
