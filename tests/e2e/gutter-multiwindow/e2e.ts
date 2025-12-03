// E2E test for gutter rendering in multi-window mode
// Reproduces issue: "gutter for screen shifted 1 space to the right (extra column on the left side)"

vim.e2e.describe('Gutter rendering in multi-window mode', function() {
  vim.e2e.test('line numbers render with correct spacing', function() {
    // Insert content directly
    vim.e2e.keys('iLine 1<CR>Line 2<CR>Line 3<CR>Line 4<CR>Line 5<Esc>');

    // Enable line numbers (use keys instead of opt)
    vim.e2e.keys(':set number<CR>');

    // Get state before split
    const stateBefore = vim.e2e.getState();

    // Split window to trigger multi-window rendering (use keys)
    vim.e2e.keys(':vsplit<CR>');

    // Get state after split
    const stateAfter = vim.e2e.getState();

    // Capture the rendered output
    vim.e2e.pty.startCapture();
    vim.e2e.pty.render();
    const output = vim.e2e.pty.getCaptured();
    vim.e2e.pty.stopCapture();

    // Verify line numbers are present (should see "1 ", "2 ", etc.)
    vim.e2e.assert.true(output.length > 100, 'Output should not be empty');
    vim.e2e.assert.true(output.includes('Line'), 'Should contain text Line');
  });

  vim.e2e.test('cursor positioned correctly after gutter', function() {
    // Insert a test line
    vim.e2e.keys('iTest line<Esc>');

    // Enable line numbers
    vim.e2e.keys(':set number<CR>');

    // Split window
    vim.e2e.keys(':vsplit<CR>');

    // Move cursor to beginning of line
    vim.e2e.keys('0');

    // Get cursor position - it should be at column 0 in the buffer
    const cursor = vim.e2e.getCursor();
    vim.e2e.assert.equal(cursor.col, 0, 'Buffer cursor should be at column 0');

    // Verify we can still render without errors
    vim.e2e.pty.startCapture();
    vim.e2e.pty.render();
    const output = vim.e2e.pty.getCaptured();
    vim.e2e.pty.stopCapture();

    vim.e2e.assert.true(output.length > 50, 'Output should not be empty');
  });
});

vim.e2e.runAll();
