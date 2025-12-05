// ============================================================================
// PERF-CACHE-CHECK: Is tree-sitter cache working?
// ============================================================================
// We measure: 1st render (cold cache) vs 2nd+ renders (warm cache)
// If cache is working: 1st should be slow, 2nd+ should be fast
// ============================================================================

vim.e2e.describe("Cache Check", function() {

    vim.e2e.test("cold vs warm cache", function() {
        // Enable all options like user config
        vim.opt.signcolumn = "yes";
        vim.opt.number = true;
        vim.opt.relativeNumber = true;
        vim.opt.cursorLine = true;

        // Open a REAL source file with tree-sitter syntax
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        // COLD: First 5j (cache is cold, should build cache)
        const coldStart = Date.now();
        for (let i = 0; i < 5; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        const coldTime = Date.now() - coldStart;

        // Go back to start
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        // WARM: Same 5j (cache should be warm now)
        const warmStart = Date.now();
        for (let i = 0; i < 5; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        const warmTime = Date.now() - warmStart;

        console.log("[CACHE] Cold (1st pass): " + coldTime + "ms (" + (coldTime/5).toFixed(2) + "ms/move)");
        console.log("[CACHE] Warm (2nd pass): " + warmTime + "ms (" + (warmTime/5).toFixed(2) + "ms/move)");

        const speedup = coldTime / Math.max(warmTime, 1);
        console.log("[CACHE] Speedup: " + speedup.toFixed(2) + "x");

        // If cache works: warm should be at least 2x faster
        if (speedup >= 2) {
            console.log("[CACHE] Cache IS working (2nd pass is " + speedup.toFixed(1) + "x faster)");
        } else if (speedup >= 1.3) {
            console.log("[CACHE] Cache PARTIALLY working (2nd pass is " + speedup.toFixed(1) + "x faster)");
        } else {
            console.log("[CACHE] Cache NOT working (no significant speedup)");
        }

        vim.e2e.assert.true(true, "Diagnostic test always passes");
    });

    vim.e2e.test("same lines multiple times", function() {
        // Navigate to middle, then j/k repeatedly on SAME lines
        vim.e2e.keys("50j");
        vim.e2e.pty.render();

        // First pass - build cache for lines 50-55
        const pass1Start = Date.now();
        for (let i = 0; i < 5; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        vim.e2e.keys("5k"); // back to 50
        vim.e2e.pty.render();
        const pass1Time = Date.now() - pass1Start;

        // Second pass - SAME lines should be cached
        const pass2Start = Date.now();
        for (let i = 0; i < 5; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        vim.e2e.keys("5k");
        vim.e2e.pty.render();
        const pass2Time = Date.now() - pass2Start;

        // Third pass - definitely cached
        const pass3Start = Date.now();
        for (let i = 0; i < 5; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        const pass3Time = Date.now() - pass3Start;

        console.log("[CACHE] Pass 1: " + pass1Time + "ms");
        console.log("[CACHE] Pass 2: " + pass2Time + "ms");
        console.log("[CACHE] Pass 3: " + pass3Time + "ms");

        vim.e2e.assert.true(true, "Diagnostic test");
    });

});

const results = vim.e2e.runAll();
console.log("\n=== CACHE CHECK: " + results.passed + " passed, " + results.failed + " failed ===");
