// ============================================================================
// PERF-CRITICAL: Performance Regression Guards
// ============================================================================
// Real E2E tests: PTY + Hermes JSI + full render pipeline
// AGGRESSIVE thresholds - catches regressions like O(n) in render loops
//
// Run: vimc test tests/e2e/perf-critical
// ============================================================================

const THRESHOLDS = {
    // Frame timing (aggressive - we want headroom)
    SINGLE_FRAME_MS: 8,
    AVG_RENDER_MS: 5,
    MAX_FRAME_SPIKE_MS: 10,

    // Navigation (must feel instant)
    SINGLE_MOVE_MS: 3,
    RAPID_50_MS: 150,
    RAPID_100_MS: 300,

    // O(n) scaling (detects O(n²) bugs)
    LINEAR_RATIO_MAX: 15,

    // Stress
    MIXED_100_MS: 400,
    MODE_SWITCH_100_MS: 200,

    // PTY
    PTY_OVERHEAD_PERCENT: 30,
};

// ============================================================================
// FRAME RENDER
// ============================================================================
vim.e2e.describe("Frame Render", function() {
    vim.e2e.test("single frame < 8ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] Single frame: " + elapsed + "ms (max: " + THRESHOLDS.SINGLE_FRAME_MS + "ms)");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_FRAME_MS,
            "Frame " + elapsed + "ms > " + THRESHOLDS.SINGLE_FRAME_MS + "ms");
    });

    vim.e2e.test("avg render < 5ms", function() {
        vim.e2e.keys("gg");
        for (let i = 0; i < 20; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }

        const stats = vim.e2e.pty.getRenderStats();
        console.log("[BENCH] Avg render: " + stats.avgRenderMs.toFixed(2) + "ms (max: " + THRESHOLDS.AVG_RENDER_MS + "ms)");
        vim.e2e.assert.true(stats.avgRenderMs <= THRESHOLDS.AVG_RENDER_MS,
            "Avg " + stats.avgRenderMs.toFixed(2) + "ms > " + THRESHOLDS.AVG_RENDER_MS + "ms");
    });

    vim.e2e.test("no frame spikes > 10ms in 10 frames", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        let maxFrame = 0;
        for (let i = 0; i < 10; i++) {
            const start = Date.now();
            vim.e2e.keys("j");
            vim.e2e.pty.render();
            const elapsed = Date.now() - start;
            if (elapsed > maxFrame) maxFrame = elapsed;
        }

        console.log("[BENCH] Max frame spike: " + maxFrame + "ms (max: " + THRESHOLDS.MAX_FRAME_SPIKE_MS + "ms)");
        vim.e2e.assert.true(maxFrame <= THRESHOLDS.MAX_FRAME_SPIKE_MS,
            "Spike " + maxFrame + "ms > " + THRESHOLDS.MAX_FRAME_SPIKE_MS + "ms");
    });
});

// ============================================================================
// NAVIGATION (j/k/h/l)
// ============================================================================
vim.e2e.describe("Navigation", function() {
    vim.e2e.test("j < 3ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] j: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_MOVE_MS, "j " + elapsed + "ms");
    });

    vim.e2e.test("k < 3ms", function() {
        vim.e2e.keys("10j");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("k");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] k: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_MOVE_MS, "k " + elapsed + "ms");
    });

    vim.e2e.test("h < 3ms", function() {
        vim.e2e.keys("gg$");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("h");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] h: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_MOVE_MS, "h " + elapsed + "ms");
    });

    vim.e2e.test("l < 3ms", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("l");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] l: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_MOVE_MS, "l " + elapsed + "ms");
    });

    vim.e2e.test("50j < 150ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50j: " + elapsed + "ms (" + (elapsed/50).toFixed(2) + "ms/move)");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_50_MS,
            "50j " + elapsed + "ms > " + THRESHOLDS.RAPID_50_MS + "ms");
    });

    vim.e2e.test("100j < 300ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(100));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100j: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_100_MS,
            "100j " + elapsed + "ms > " + THRESHOLDS.RAPID_100_MS + "ms");
    });

    vim.e2e.test("50k < 150ms", function() {
        vim.e2e.keys("100j");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("k".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50k: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_50_MS, "50k " + elapsed + "ms");
    });

    vim.e2e.test("50l < 150ms", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("l".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50l: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_50_MS, "50l " + elapsed + "ms");
    });

    vim.e2e.test("50h < 150ms", function() {
        vim.e2e.keys("gg$");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("h".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50h: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_50_MS, "50h " + elapsed + "ms");
    });
});

// ============================================================================
// O(n) SCALING - Detects O(n²) Regressions
// ============================================================================
vim.e2e.describe("O(n) Scaling", function() {
    vim.e2e.test("vertical: 100j NOT 10x slower than 10j", function() {
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
        console.log("[BENCH] O(n) vertical: 10j=" + time10 + "ms, 100j=" + time100 + "ms, ratio=" + ratio.toFixed(2) + "x");

        vim.e2e.assert.true(ratio <= THRESHOLDS.LINEAR_RATIO_MAX,
            "Ratio " + ratio.toFixed(2) + "x suggests O(n²)! Max: " + THRESHOLDS.LINEAR_RATIO_MAX + "x");
    });

    vim.e2e.test("horizontal: 100l NOT 10x slower than 10l", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        const start10 = Date.now();
        vim.e2e.keys("l".repeat(10));
        vim.e2e.pty.render();
        const time10 = Math.max(Date.now() - start10, 1);

        vim.e2e.keys("0");
        vim.e2e.pty.render();

        const start100 = Date.now();
        vim.e2e.keys("l".repeat(100));
        vim.e2e.pty.render();
        const time100 = Date.now() - start100;

        const ratio = time100 / time10;
        console.log("[BENCH] O(n) horizontal: 10l=" + time10 + "ms, 100l=" + time100 + "ms, ratio=" + ratio.toFixed(2) + "x");

        vim.e2e.assert.true(ratio <= THRESHOLDS.LINEAR_RATIO_MAX,
            "Horizontal ratio " + ratio.toFixed(2) + "x suggests O(n²)!");
    });

    vim.e2e.test("alternating: 100 jk NOT 10x slower than 10 jk", function() {
        vim.e2e.keys("50j");
        vim.e2e.pty.render();

        const start10 = Date.now();
        for (let i = 0; i < 10; i++) vim.e2e.keys("jk");
        vim.e2e.pty.render();
        const time10 = Math.max(Date.now() - start10, 1);

        const start100 = Date.now();
        for (let i = 0; i < 100; i++) vim.e2e.keys("jk");
        vim.e2e.pty.render();
        const time100 = Date.now() - start100;

        const ratio = time100 / time10;
        console.log("[BENCH] O(n) alternating: 10jk=" + time10 + "ms, 100jk=" + time100 + "ms, ratio=" + ratio.toFixed(2) + "x");

        vim.e2e.assert.true(ratio <= THRESHOLDS.LINEAR_RATIO_MAX,
            "Alternating ratio " + ratio.toFixed(2) + "x too high!");
    });
});

// ============================================================================
// MODE SWITCHING
// ============================================================================
vim.e2e.describe("Mode Switch", function() {
    vim.e2e.test("i->Esc < 3ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("i\x1b");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] i->Esc: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_MOVE_MS, "Mode switch " + elapsed + "ms");
    });

    vim.e2e.test("v->Esc < 3ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("v\x1b");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] v->Esc: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.SINGLE_MOVE_MS, "Visual switch " + elapsed + "ms");
    });

    vim.e2e.test("100 mode switches < 200ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        for (let i = 0; i < 100; i++) {
            vim.e2e.keys("i\x1b");
        }
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100 mode switches: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.MODE_SWITCH_100_MS,
            "100 switches " + elapsed + "ms > " + THRESHOLDS.MODE_SWITCH_100_MS + "ms");
    });
});

// ============================================================================
// STRESS TESTS
// ============================================================================
vim.e2e.describe("Stress", function() {
    vim.e2e.test("100 mixed moves < 400ms", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        const start = Date.now();
        for (let i = 0; i < 25; i++) {
            vim.e2e.keys("jjll");
        }
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100 mixed: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.MIXED_100_MS,
            "100 mixed " + elapsed + "ms > " + THRESHOLDS.MIXED_100_MS + "ms");
    });

    vim.e2e.test("50 diagonal < 200ms", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        const start = Date.now();
        for (let i = 0; i < 50; i++) {
            vim.e2e.keys("jl");
        }
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50 diagonal: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 200, "Diagonal " + elapsed + "ms");
    });

    vim.e2e.test("50 word motions < 150ms", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("w".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50w: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_50_MS, "50w " + elapsed + "ms");
    });

    vim.e2e.test("50 word back < 150ms", function() {
        vim.e2e.keys("G$");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("b".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50b: " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= THRESHOLDS.RAPID_50_MS, "50b " + elapsed + "ms");
    });
});

// ============================================================================
// FULL CONFIG SIMULATION - Mimics real user config
// ============================================================================
vim.e2e.describe("Full Config", function() {
    vim.e2e.test("real config: 50j < 200ms", function() {
        // Mimic user's actual config:
        vim.opt.signcolumn = "yes";
        vim.opt.number = true;
        vim.opt.relativeNumber = true;
        vim.opt.cursorLine = true;
        vim.opt.list = true;

        // Create git-like signs (like git-bundle plugin)
        const ns = vim.api.createNamespace("gitsigns");
        for (let i = 0; i < 30; i++) {
            vim.api.bufSetExtmark(0, ns, i, 0, { signText: "+", signHlGroup: "GitSignsAdd" });
        }
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50j (full config): " + elapsed + "ms (" + (elapsed/50).toFixed(2) + "ms/move)");
        vim.e2e.assert.true(elapsed <= 200, "50j (full config) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("with 500 lines: 100j < 500ms", function() {
        // Load real file content
        vim.e2e.keys(":e /tmp/perf_test_file.txt\r");
        vim.e2e.pty.render();

        // Add git signs throughout
        const ns = vim.api.createNamespace("gitsigns-file");
        for (let i = 0; i < 50; i++) {
            vim.api.bufSetExtmark(0, ns, i * 5, 0, { signText: "~", signHlGroup: "GitSignsChange" });
        }
        vim.e2e.pty.render();

        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(100));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100j (500-line file + config): " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 500, "100j took " + elapsed + "ms - TOO SLOW!");
    });
});

// ============================================================================
// REAL FILE CONTENT - Tests with actual file content
// ============================================================================
vim.e2e.describe("Real File", function() {
    vim.e2e.test("500-line file: single j < 10ms", function() {
        vim.e2e.keys(":e /tmp/perf_test_file.txt\r");
        vim.e2e.pty.render();
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j");
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] Single j (real file): " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 10, "j (real file) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("500-line file: 50j < 200ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(50));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 50j (real file): " + elapsed + "ms (" + (elapsed/50).toFixed(2) + "ms/move)");
        vim.e2e.assert.true(elapsed <= 200, "50j (real file) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("500-line file: 100j < 400ms", function() {
        vim.e2e.keys("gg");
        vim.e2e.pty.render();

        const start = Date.now();
        vim.e2e.keys("j".repeat(100));
        vim.e2e.pty.render();
        const elapsed = Date.now() - start;

        console.log("[BENCH] 100j (real file): " + elapsed + "ms");
        vim.e2e.assert.true(elapsed <= 400, "100j (real file) took " + elapsed + "ms - TOO SLOW!");
    });

    vim.e2e.test("500-line file: O(n) not O(n²)", function() {
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
        console.log("[BENCH] O(n) real file: 10j=" + time10 + "ms, 100j=" + time100 + "ms, ratio=" + ratio.toFixed(2) + "x");

        vim.e2e.assert.true(ratio <= 15, "Ratio " + ratio.toFixed(2) + "x suggests O(n²)!");
    });
});

// ============================================================================
// PTY OVERHEAD
// ============================================================================
vim.e2e.describe("PTY Overhead", function() {
    vim.e2e.test("capture adds < 30%", function() {
        vim.e2e.keys("gg");

        const startNoCap = Date.now();
        for (let i = 0; i < 30; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        const timeNoCap = Math.max(Date.now() - startNoCap, 1);

        vim.e2e.keys("gg");

        vim.e2e.pty.startCapture();
        const startCap = Date.now();
        for (let i = 0; i < 30; i++) {
            vim.e2e.keys("j");
            vim.e2e.pty.render();
        }
        const timeCap = Date.now() - startCap;
        vim.e2e.pty.stopCapture();

        const overhead = ((timeCap - timeNoCap) / timeNoCap) * 100;
        console.log("[BENCH] PTY overhead: " + overhead.toFixed(1) + "% (max: " + THRESHOLDS.PTY_OVERHEAD_PERCENT + "%)");

        vim.e2e.assert.true(overhead <= THRESHOLDS.PTY_OVERHEAD_PERCENT,
            "Overhead " + overhead.toFixed(1) + "% > " + THRESHOLDS.PTY_OVERHEAD_PERCENT + "%");
    });
});

// ============================================================================
// RUN
// ============================================================================
const results = vim.e2e.runAll();

console.log("\n" + "=".repeat(50));
console.log("PERF-CRITICAL RESULTS");
console.log("=".repeat(50));
console.log("Passed: " + results.passed + " | Failed: " + results.failed);
console.log("Duration: " + results.duration_ms + "ms");

if (results.failed > 0) {
    console.log("\n[CRITICAL] PERFORMANCE REGRESSION!");
    console.log("Fix before committing!");
}
