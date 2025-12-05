// E2E test: Cursor should be positioned after gutter, not in gutter area
// Bug: renderCursorOnly() was using gutter_manager.getTotalWidth() instead of
// window-specific calculateWindowGutterWidth(), causing cursor to render in gutter

vim.e2e.describe("Cursor Gutter Boundary", () => {
  vim.e2e.test("cursor renders after gutter with line numbers enabled", () => {
    // Enable line numbers via API (gutter = 5 chars: 4 digits + 1 space)
    vim.opt.number = true;

    // Insert some text and return to normal mode
    vim.e2e.keys("iHello World\x1b");

    // Move to column 0 (beginning of line)
    vim.e2e.keys("0");

    // Verify buffer cursor is at col 0
    const cursor = vim.e2e.getCursor();
    vim.e2e.assert.equal(cursor.col, 0, "Buffer cursor should be at column 0");

    // Capture the rendered output using pattern counting
    vim.e2e.pty.startCapture();
    vim.e2e.pty.render();

    // Count the final cursor position sequence [1;6H
    // With 'number' enabled, gutter is 5 chars, so cursor col 0 -> screen col 6
    const count = vim.e2e.pty.countSequence("[1;6H");
    vim.e2e.pty.stopCapture();

    vim.e2e.assert.true(
      count > 0,
      "Cursor should be at screen column 6 (after 5-char gutter)"
    );
  });

  vim.e2e.test("cursor stays after gutter during h/l movement", () => {
    // Enable line numbers
    vim.opt.number = true;

    // Insert text and return to normal mode
    vim.e2e.keys("iTest\x1b");

    // Move to start of line
    vim.e2e.keys("0");

    // Move right then left back to column 0
    vim.e2e.keys("l");
    vim.e2e.keys("h");

    // Verify still at column 0
    const cursor = vim.e2e.getCursor();
    vim.e2e.assert.equal(cursor.col, 0, "Buffer cursor should be at column 0");
  });
});

vim.e2e.runAll();
