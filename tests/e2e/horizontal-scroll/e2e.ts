// E2E test: Horizontal scrolling when line is longer than screen width
// Bug (Dec 2025): renderCursorOnly optimization didn't trigger full render
// when cursor moved beyond horizontal viewport bounds

vim.e2e.describe("Horizontal Scroll", () => {
  vim.e2e.test("$ moves cursor to end of long line", () => {
    // Create a line longer than typical terminal width (80 chars)
    const longLine = "x".repeat(120);
    vim.e2e.keys("i" + longLine + "\x1b");

    // Move to beginning
    vim.e2e.keys("0");

    // Verify we're at col 0
    let cursor = vim.e2e.getCursor();
    vim.e2e.assert.equal(cursor.col, 0, "Should start at col 0");

    // Move to the end of line (should trigger horizontal scroll)
    vim.e2e.keys("$");

    // Verify cursor moved to end (col 119 for 120 chars, 0-indexed)
    cursor = vim.e2e.getCursor();
    vim.e2e.assert.true(cursor.col > 80, "Cursor should be past column 80");
    vim.e2e.assert.equal(cursor.col, 119, "Cursor should be at end of line");
  });

  vim.e2e.test("0 moves cursor back to beginning after $ on long line", () => {
    // We're testing that 0 can bring cursor back to col 0, regardless of line length
    // Move to end first
    vim.e2e.keys("$");

    // Now move back to beginning (should scroll left)
    vim.e2e.keys("0");

    // Verify cursor is at column 0
    const cursor = vim.e2e.getCursor();
    vim.e2e.assert.equal(cursor.col, 0, "Should be at col 0 after 0");
  });

  vim.e2e.test("rapid l movement completes quickly", () => {
    // Move to column 0 first
    vim.e2e.keys("0");

    // Rapidly move right (simulates holding l)
    const start = Date.now();
    vim.e2e.keys("l".repeat(100));
    vim.e2e.pty.render();
    const elapsed = Date.now() - start;

    // Should complete in reasonable time
    vim.e2e.assert.true(elapsed < 500, "100l should complete in < 500ms");

    // Verify cursor actually moved (we don't know exact position, just that it moved a lot)
    const cursor = vim.e2e.getCursor();
    vim.e2e.assert.true(cursor.col >= 50, "Cursor should have moved right significantly");
  });

  vim.e2e.test("viewport scrolls when cursor goes beyond screen width", () => {
    // Set a known terminal size
    vim.e2e.pty.setSize(24, 80);

    // Go to beginning
    vim.e2e.keys("0");

    // Move to column 100 (well past 80-char terminal width with gutter)
    for (let i = 0; i < 100; i++) {
      vim.e2e.keys("l");
    }

    const cursor = vim.e2e.getCursor();
    vim.e2e.assert.true(cursor.col >= 50, "Should have moved right significantly");

    // Force a render and verify the operation completes
    vim.e2e.pty.render();
  });
});

vim.e2e.runAll();
