// ============================================================================
// PERF-RENDER-ISOLATION: Render Performance Regression Tests
// ============================================================================
// Critical performance tests to catch regressions in render pipeline.
// Tests isolate each feature's contribution and verify cache effectiveness.
//
// KEY METRICS (with highlight cache):
// - Empty buffer:      < 3ms
// - With options:      < 5ms
// - Tree-sitter cold:  < 25ms (cache miss)
// - Tree-sitter warm:  < 5ms  (cache hit - THE IMPORTANT ONE!)
//
// If tree-sitter cached tests jump to 10ms+, the highlight cache is BROKEN!
// ============================================================================

// Performance thresholds (in ms)
const THRESHOLD = {
    BASELINE: 3,        // Empty buffer, no features
    WITH_OPTIONS: 5,    // Line numbers, signcolumn, cursorline
    WITH_EXTMARKS: 5,   // 50 extmarks (signs)
    TREE_SITTER: 5,     // With syntax highlighting (cache hit)
    CACHE_COLD: 25,     // First render (cache miss) - allowed to be slower
    FULL_CONFIG: 5,     // Everything enabled (cache hit)
    MOVEMENT: 30,       // Movement commands (include key processing overhead)
    STRESS: 50,         // Stress tests (rapid movement, many features)
};

// Number of iterations for averaging
const ITERATIONS = 10;

// Helper: measure average render time over N iterations using j movement
function measureRenderTime(iterations: number): number {
    let totalMs = 0;
    for (let i = 0; i < iterations; i++) {
        const start = Date.now();
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        totalMs += Date.now() - start;
    }
    return totalMs / iterations;
}

// ============================================================================
// BASIC PERFORMANCE TESTS
// ============================================================================

vim.e2e.describe("Basic Render Performance", function() {

    vim.e2e.test("baseline: empty buffer", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] Empty buffer: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.BASELINE + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.BASELINE,
            "Empty buffer: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.BASELINE + "ms - BASELINE REGRESSION!");
    });

    vim.e2e.test("+ line numbers", function() {
        vim.opt.number = true;
        vim.opt.relativeNumber = true;
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] + line numbers: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.WITH_OPTIONS + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.WITH_OPTIONS,
            "+ line numbers: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.WITH_OPTIONS + "ms");
    });

    vim.e2e.test("+ signcolumn + cursorline", function() {
        vim.opt.signcolumn = "yes";
        vim.opt.cursorLine = true;
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] + signcolumn + cursorline: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.WITH_OPTIONS + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.WITH_OPTIONS,
            "+ signcolumn + cursorline: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.WITH_OPTIONS + "ms");
    });

    vim.e2e.test("+ 50 extmarks", function() {
        const ns = vim.api.createNamespace("test-signs");
        for (let i = 0; i < 50; i++) {
            vim.api.bufSetExtmark(0, ns, i, 0, { signText: "+", signHlGroup: "GitSignsAdd" });
        }
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] + 50 extmarks: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.WITH_EXTMARKS + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.WITH_EXTMARKS,
            "+ 50 extmarks: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.WITH_EXTMARKS + "ms");
    });
});

// ============================================================================
// TREE-SITTER & CACHE TESTS (CRITICAL!)
// ============================================================================

vim.e2e.describe("Tree-sitter & Cache", function() {

    vim.e2e.test("tree-sitter: cold vs cached (CRITICAL)", function() {
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.keys("gg");

        // Cold render (cache miss)
        const coldStart = Date.now();
        vim.e2e.pty.render();
        const coldMs = Date.now() - coldStart;

        // Cached renders (just j movement, stay near top)
        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] Tree-sitter cold: " + coldMs.toFixed(2) + "ms, cached: " + avgMs.toFixed(2) + "ms");
        console.log("[PERF] Cache speedup: " + (coldMs / avgMs).toFixed(1) + "x");

        vim.e2e.assert.true(coldMs <= THRESHOLD.CACHE_COLD,
            "Tree-sitter cold: " + coldMs.toFixed(2) + "ms exceeds " + THRESHOLD.CACHE_COLD + "ms");
        vim.e2e.assert.true(avgMs <= THRESHOLD.TREE_SITTER,
            "Tree-sitter cached: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.TREE_SITTER + "ms - CACHE BROKEN!");
    });

    vim.e2e.test("cache: new file cold start", function() {
        // Load a different file to test fresh cache
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/editor/editor.zig\r");
        vim.e2e.keys("gg");

        const cold1 = Date.now();
        vim.e2e.pty.render();
        const coldMs = Date.now() - cold1;

        vim.e2e.keys("j");
        const warm1 = Date.now();
        vim.e2e.pty.render();
        const warmMs = Date.now() - warm1;

        console.log("[PERF] Cache test - cold: " + coldMs.toFixed(2) + "ms, warm: " + warmMs.toFixed(2) + "ms");
        vim.e2e.assert.true(warmMs <= THRESHOLD.TREE_SITTER,
            "Warm render: " + warmMs.toFixed(2) + "ms - CACHE NOT WORKING!");
    });

    vim.e2e.test("full config: all features enabled", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] FULL CONFIG: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.FULL_CONFIG + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.FULL_CONFIG,
            "FULL CONFIG: " + avgMs.toFixed(2) + "ms - PERFORMANCE REGRESSION!");
    });
});

// ============================================================================
// LARGE FILE TESTS
// ============================================================================

vim.e2e.describe("Large File Performance", function() {

    vim.e2e.test("main.zig: scroll through large file", function() {
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const avgMs = measureRenderTime(ITERATIONS);

        console.log("[PERF] Large file scroll: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.TREE_SITTER + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.TREE_SITTER,
            "Large file scroll: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.TREE_SITTER + "ms");
    });

    vim.e2e.test("page jump: G and gg", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        // Jump to end
        const start1 = Date.now();
        vim.e2e.keys("G");
        vim.e2e.pty.render();
        const endJumpMs = Date.now() - start1;

        // Jump back to start
        const start2 = Date.now();
        vim.e2e.keys("gg");
        vim.e2e.pty.render();
        const startJumpMs = Date.now() - start2;

        console.log("[PERF] Jump to end: " + endJumpMs.toFixed(2) + "ms, back: " + startJumpMs.toFixed(2) + "ms");
        vim.e2e.assert.true(endJumpMs <= THRESHOLD.MOVEMENT,
            "Jump to end: " + endJumpMs.toFixed(2) + "ms exceeds " + THRESHOLD.MOVEMENT + "ms");
    });
});

// ============================================================================
// RAPID MOVEMENT STRESS TESTS
// ============================================================================

vim.e2e.describe("Rapid Movement Stress", function() {

    vim.e2e.test("rapid j/k: cursor stress", function() {
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.keys("gg");
        // Move down first
        for (let i = 0; i < 15; i++) vim.e2e.keys("j");
        vim.e2e.pty.render();

        // Rapid up/down movement
        let totalMs = 0;
        for (let i = 0; i < 10; i++) {
            const start = Date.now();
            vim.e2e.keys(i % 2 === 0 ? "jjjjj" : "kkkkk");
            vim.e2e.pty.render();
            totalMs += Date.now() - start;
        }
        const avgMs = totalMs / 10;

        console.log("[PERF] Rapid j/k: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.STRESS + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.STRESS,
            "Rapid j/k: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.STRESS + "ms");
    });

    vim.e2e.test("word motion: w stress", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        // Rapid word movement
        let totalMs = 0;
        for (let i = 0; i < 5; i++) {
            const start = Date.now();
            vim.e2e.keys("wwwww");
            vim.e2e.pty.render();
            totalMs += Date.now() - start;
        }
        const avgMs = totalMs / 5;

        console.log("[PERF] Rapid w: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.STRESS + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.STRESS,
            "Rapid w: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.STRESS + "ms");
    });

    vim.e2e.test("horizontal motion: l/h stress", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        // Rapid left/right movement
        let totalMs = 0;
        for (let i = 0; i < 10; i++) {
            const start = Date.now();
            vim.e2e.keys(i % 2 === 0 ? "lllll" : "hhhhh");
            vim.e2e.pty.render();
            totalMs += Date.now() - start;
        }
        const avgMs = totalMs / 10;

        console.log("[PERF] Rapid l/h: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.STRESS + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.STRESS,
            "Rapid l/h: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.STRESS + "ms");
    });
});

// ============================================================================
// SEARCH PERFORMANCE
// ============================================================================

vim.e2e.describe("Search Performance", function() {

    vim.e2e.test("search: highlight matches", function() {
        vim.e2e.keys(":e /Users/le/vimcraft/editor/src/main.zig\r");
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        // Perform search
        vim.e2e.keys("/const\r");
        vim.e2e.pty.render();

        // Navigate between matches
        let totalMs = 0;
        for (let i = 0; i < 5; i++) {
            const start = Date.now();
            vim.e2e.keys("n");
            vim.e2e.pty.render();
            totalMs += Date.now() - start;
        }
        const avgMs = totalMs / 5;

        console.log("[PERF] Search n: " + avgMs.toFixed(2) + "ms (threshold: " + THRESHOLD.MOVEMENT + "ms)");
        vim.e2e.assert.true(avgMs <= THRESHOLD.MOVEMENT,
            "Search n: " + avgMs.toFixed(2) + "ms exceeds " + THRESHOLD.MOVEMENT + "ms");

        // Clear search
        vim.e2e.keys(":noh\r");
    });
});

// ============================================================================
// RUN ALL TESTS
// ============================================================================

const results = vim.e2e.runAll();
console.log("\n=== RENDER PERFORMANCE: " + results.passed + " passed, " + results.failed + " failed ===");

// Summary with thresholds
console.log("\nThresholds:");
console.log("  BASELINE:    " + THRESHOLD.BASELINE + "ms (empty buffer)");
console.log("  WITH_OPTIONS:" + THRESHOLD.WITH_OPTIONS + "ms (line numbers, etc)");
console.log("  TREE_SITTER: " + THRESHOLD.TREE_SITTER + "ms (cache hit - CRITICAL!)");
console.log("  CACHE_COLD:  " + THRESHOLD.CACHE_COLD + "ms (cache miss)");
console.log("  MOVEMENT:    " + THRESHOLD.MOVEMENT + "ms (key processing)");
console.log("  STRESS:      " + THRESHOLD.STRESS + "ms (rapid movement)");

if (results.failed > 0) {
    console.log("\n[!] Performance regression detected! Check times above.");
} else {
    console.log("\nAll performance tests passed!");
}
