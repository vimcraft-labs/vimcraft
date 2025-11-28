// E2E test for CursorMoved autocmd
// Debug test to understand why tests fail

vim.e2e.describe('CursorMoved autocmd', () => {
  vim.e2e.test('assert.ok works', () => {
    vim.e2e.assert.ok(true, 'true should be ok');
  });

  vim.e2e.test('id is positive number', () => {
    const id = vim.api.createAutocmd('CursorMoved', {
      callback: () => {},
    });

    // First verify we got a number
    vim.e2e.assert.equal(typeof id, 'number', `id should be number, got ${typeof id}`);

    // Then check it's positive
    vim.e2e.assert.ok(id > 0, `id should be > 0, got ${id}`);
  });

  vim.e2e.test('cursor movement triggers callback', () => {
    let called = false;

    // Insert some text first so cursor can move
    vim.e2e.keys('ihello world');
    vim.e2e.keys('<Esc>0');  // Go to start of line

    vim.api.createAutocmd('CursorMoved', {
      callback: () => {
        called = true;
      },
    });

    // Move cursor right (should trigger callback)
    vim.e2e.keys('l');

    // Check if callback was called
    vim.e2e.assert.equal(called, true, `callback should have been called, called=${called}`);
  });
});

vim.e2e.runAll();
