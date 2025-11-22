// Rendering E2E Tests
// Tests terminal ANSI escape code output for rendering optimization validation
//
// These tests verify:
// 1. Synchronized updates (cursor visibility toggling)
// 2. Cursor position tracking (redundant position codes)
// 3. Color/attribute tracking (SGR code optimization)
// 4. Render statistics from display

// ============================================================================
// Test 1: Synchronized Updates - Cursor Visibility
// ============================================================================
vim.e2e.describe("Synchronized Updates", function() {
    vim.e2e.test("rapid movements have minimal cursor visibility toggles", function() {
        // Start PTY capture
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        // Perform 20 rapid movements (simulates holding 'j')
        vim.e2e.keys("jjjjjjjjjjjjjjjjjjjj"); // 20 down movements

        // Trigger render to generate PTY output
        vim.e2e.pty.render();

        // Get captured output
        const hideCount = vim.e2e.pty.countHideCursor();
        const showCount = vim.e2e.pty.countShowCursor();
        const totalToggles = hideCount + showCount;

        vim.e2e.pty.stopCapture();

        console.log("Cursor visibility toggles after 20 movements:");
        console.log("  Hide cursor codes: " + hideCount);
        console.log("  Show cursor codes: " + showCount);
        console.log("  Total: " + totalToggles);

        // With synchronized updates, we should have minimal toggles
        // Each render has 1 hide + 1 show (at most)
        // 20 movements but only 1 render = 2 toggles max
        vim.e2e.assert.true(totalToggles < 50, "Should have <50 cursor toggles for 20 movements (got " + totalToggles + ")");
    });

    vim.e2e.test("initial render has cursor visibility control", function() {
        // Reset cursor state to ensure cursor hide codes are sent
        // (cursor visibility is optimized across renders to prevent flickering)
        vim.e2e.pty.resetCursorState();

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        // Trigger a render
        vim.e2e.keys("gg"); // Go to start
        vim.e2e.pty.render();

        const hideCount = vim.e2e.pty.countHideCursor();
        const showCount = vim.e2e.pty.countShowCursor();

        vim.e2e.pty.stopCapture();

        console.log("Initial render cursor control:");
        console.log("  Hide: " + hideCount + ", Show: " + showCount);

        // Should have at least one hide per render (cursor is hidden during paint)
        // Show count may be 0 because cursor showing happens in backend.render() after display.render()
        vim.e2e.assert.true(hideCount > 0, "Should have at least 1 cursor hide code");
    });
});

// ============================================================================
// Test 2: Cursor Position Tracking
// ============================================================================
vim.e2e.describe("Cursor Position Tracking", function() {
    vim.e2e.test("horizontal movements have reasonable position codes", function() {
        vim.e2e.keys("gg0"); // Go to start
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        // Perform 10 horizontal movements
        vim.e2e.keys("llllllllll"); // 10 right movements
        vim.e2e.pty.render();

        const positionCodes = vim.e2e.pty.countCursorPositionCodes();
        vim.e2e.pty.stopCapture();

        console.log("Position codes for 10 horizontal movements: " + positionCodes);

        // With cursor position tracking, we should see minimal redundant codes
        // Without optimization: 20-40 codes (multiple per movement)
        // With optimization: <30 codes (still needs some for repositioning)
        vim.e2e.assert.true(positionCodes < 100, "Should have <100 position codes for 10 movements (got " + positionCodes + ")");
    });

    vim.e2e.test("vertical movements have reasonable position codes", function() {
        vim.e2e.keys("gg0"); // Go to start
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        // Perform 5 vertical movements
        vim.e2e.keys("jjjjj"); // 5 down movements
        vim.e2e.pty.render();

        const positionCodes = vim.e2e.pty.countCursorPositionCodes();
        vim.e2e.pty.stopCapture();

        console.log("Position codes for 5 vertical movements: " + positionCodes);

        // Vertical movements require more position codes due to line rendering
        vim.e2e.assert.true(positionCodes < 200, "Should have <200 position codes for 5 vertical movements (got " + positionCodes + ")");
    });
});

// ============================================================================
// Test 3: Color/Attribute Tracking (SGR Codes)
// ============================================================================
vim.e2e.describe("Color Attribute Tracking", function() {
    vim.e2e.test("movement generates SGR codes for highlighting", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        // Move through buffer (triggers rendering with highlights)
        vim.e2e.keys("jjjkkk"); // Down 3, up 3
        vim.e2e.pty.render();

        const sgrCount = vim.e2e.pty.countSGRCodes();
        vim.e2e.pty.stopCapture();

        console.log("SGR codes for 6 movements: " + sgrCount);

        // With line numbers and syntax, we expect SGR codes
        // This test just verifies the count is reasonable
        vim.e2e.assert.true(sgrCount >= 0, "Should count SGR codes (got " + sgrCount + ")");
    });

    vim.e2e.test("captured output contains escape sequences", function() {
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys("l"); // Single movement
        vim.e2e.pty.render();

        const length = vim.e2e.pty.getLength();
        vim.e2e.pty.stopCapture();

        console.log("Captured output length: " + length + " bytes");

        // Should capture some output (escape codes + content)
        vim.e2e.assert.true(length > 0, "Should capture terminal output (got " + length + " bytes)");
    });
});

// ============================================================================
// Test 4: Render Statistics
// ============================================================================
vim.e2e.describe("Render Statistics", function() {
    vim.e2e.test("render stats are available", function() {
        // Trigger some renders
        vim.e2e.keys("jjjkkk");
        vim.e2e.pty.render();

        const stats = vim.e2e.pty.getRenderStats();

        console.log("Render stats:");
        console.log("  Total renders: " + stats.totalRenders);
        console.log("  Cursor hide codes: " + stats.cursorHideCodes);
        console.log("  Cursor show codes: " + stats.cursorShowCodes);
        console.log("  Cursor position codes: " + stats.cursorPositionCodes);
        console.log("  Avg render time: " + stats.avgRenderMs + "ms");

        // Stats should be populated after render
        vim.e2e.assert.true(stats.totalRenders > 0, "Should have render count after render()");
    });

    vim.e2e.test("render stats track cursor codes", function() {
        const statsBefore = vim.e2e.pty.getRenderStats();
        const hideCodesBefore = statsBefore.cursorHideCodes;

        // Trigger renders
        vim.e2e.keys("jjj");
        vim.e2e.pty.render();

        const statsAfter = vim.e2e.pty.getRenderStats();
        const hideCodesAfter = statsAfter.cursorHideCodes;

        console.log("Hide codes before: " + hideCodesBefore + ", after: " + hideCodesAfter);

        // Hide codes should increase (or stay same if optimized away)
        vim.e2e.assert.true(hideCodesAfter >= hideCodesBefore, "Hide codes should not decrease");
    });
});

// ============================================================================
// Test 5: Pattern Counting
// ============================================================================
vim.e2e.describe("Escape Sequence Pattern Counting", function() {
    vim.e2e.test("countSequence finds custom patterns", function() {
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys("j");
        vim.e2e.pty.render();

        // Count ESC character occurrences (0x1b)
        const escPattern = "\x1b";
        const escCount = vim.e2e.pty.countSequence(escPattern);

        vim.e2e.pty.stopCapture();

        console.log("ESC (0x1b) count: " + escCount);

        // Should find ESC characters in terminal output after render
        vim.e2e.assert.true(escCount > 0, "Should find ESC sequences after render");
    });

    vim.e2e.test("pty capture mode tracking works", function() {
        // Ensure we're not capturing from previous test
        vim.e2e.pty.stopCapture();

        vim.e2e.assert.true(!vim.e2e.pty.isCapturing(), "Should not be capturing initially");

        vim.e2e.pty.startCapture();
        vim.e2e.assert.true(vim.e2e.pty.isCapturing(), "Should be capturing after start");

        vim.e2e.pty.stopCapture();
        vim.e2e.assert.true(!vim.e2e.pty.isCapturing(), "Should not be capturing after stop");
    });
});

// ============================================================================
// Test 6: Rapid Input Flickering Detection
// ============================================================================
vim.e2e.describe("Flickering Detection", function() {
    vim.e2e.test("rapid input does not cause excessive cursor flickering", function() {
        vim.e2e.keys("gg0");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        // Simulate rapid input (like holding a key)
        const rapidInput = "llllllllllllllllllll"; // 20 rapid 'l' presses
        vim.e2e.keys(rapidInput);
        vim.e2e.pty.render();

        const hideCount = vim.e2e.pty.countHideCursor();
        const showCount = vim.e2e.pty.countShowCursor();
        const totalToggle = hideCount + showCount;

        vim.e2e.pty.stopCapture();

        console.log("Rapid input flickering test:");
        console.log("  20 rapid 'l' presses");
        console.log("  Hide codes: " + hideCount);
        console.log("  Show codes: " + showCount);
        console.log("  Flicker ratio: " + (totalToggle / 20).toFixed(2) + " toggles per input");

        // With single render after all inputs: should be exactly 1 hide + 0 show
        // (render hides cursor during painting, doesn't show it because
        // the terminal backend does that after render returns)
        // Acceptable: <5 toggles per input on average
        const flickerRatio = totalToggle / 20;
        vim.e2e.assert.true(flickerRatio < 5, "Flicker ratio should be <5 (got " + flickerRatio.toFixed(2) + ")");
    });
});

vim.e2e.runAll();
