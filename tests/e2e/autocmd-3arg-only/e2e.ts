// Isolated test for 3-arg style autocmd
// This test file ONLY uses the 3-arg smear-cursor style

vim.e2e.describe('vim.autocmd.create 3-arg only', () => {
  vim.e2e.test('callback fires on cursor movement with 3-arg style', () => {
    let called = false;

    // Insert text first so cursor can move
    vim.e2e.keys('ihello world');
    vim.e2e.keys('<Esc>0');  // Go to start of line

    // Register autocmd smear-cursor style (group, event, callback)
    const id = vim.autocmd.create('TestGroup', 'CursorMoved', () => {
      called = true;
    });

    // Verify id is returned
    vim.e2e.assert.equal(typeof id, 'number', 'should return autocmd id');

    // Move cursor right (should trigger callback)
    vim.e2e.keys('l');

    vim.e2e.assert.equal(called, true, `callback should have been called, called=${called}`);
  });
});

vim.e2e.runAll();
