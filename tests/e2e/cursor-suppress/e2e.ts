// E2E test for cursor suppression API
// Tests that suppressCursor/unsuppressCursor work correctly

vim.e2e.describe('Cursor Suppression API', function() {
  vim.e2e.test('suppressCursor and unsuppressCursor exist', function() {
    vim.e2e.assert.true(typeof vim.layer.suppressCursor === 'function', 'suppressCursor should be a function');
    vim.e2e.assert.true(typeof vim.layer.unsuppressCursor === 'function', 'unsuppressCursor should be a function');
  });

  vim.e2e.test('suppressCursor hides cursor', function() {
    vim.e2e.pty.startCapture();
    vim.e2e.pty.clear();

    // Suppress cursor
    vim.layer.suppressCursor();
    vim.e2e.pty.render();

    // Should have hide cursor escape code
    const hides = vim.e2e.pty.countHideCursor();
    vim.e2e.assert.true(hides >= 1, 'should hide cursor when suppressed');

    vim.e2e.pty.stopCapture();
  });

  vim.e2e.test('unsuppressCursor shows cursor', function() {
    // First suppress
    vim.layer.suppressCursor();

    vim.e2e.pty.startCapture();
    vim.e2e.pty.clear();

    // Now unsuppress - should show cursor immediately
    vim.layer.unsuppressCursor();

    // Should have show cursor escape code
    const shows = vim.e2e.pty.countShowCursor();
    vim.e2e.assert.true(shows >= 1, 'should show cursor when unsuppressed');

    vim.e2e.pty.stopCapture();
  });

  vim.e2e.test('cursor visible after unsuppress without render', function() {
    // Start fresh capture
    vim.e2e.pty.startCapture();

    // Suppress cursor first
    vim.layer.suppressCursor();

    // Clear capture to only get unsuppress output
    vim.e2e.pty.clear();

    // Unsuppress without calling render - cursor should still appear
    vim.layer.unsuppressCursor();

    // Count show cursor codes (escape code: \x1b[?25h)
    const captured = vim.e2e.pty.getCaptured();
    const showCursorPattern = /\x1b\[\?25h/g;
    const matches = captured.match(showCursorPattern) || [];

    vim.e2e.assert.true(matches.length >= 1,
      `Expected cursor show code after unsuppress, got ${matches.length} matches. Captured: ${captured.slice(0, 100)}`);

    vim.e2e.pty.stopCapture();
  });
});

vim.e2e.runAll();
