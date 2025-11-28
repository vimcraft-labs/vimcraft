// vim.fn LSP Prerequisites Tests
// Tests for vim.fn.getCwd(), vim.fn.executable(), and vim.fn.expand()

vim.e2e.describe('vim.fn LSP Prerequisites', function() {
  // ============================================================================
  // vim.fn.getCwd() Tests
  // ============================================================================

  vim.e2e.test('vim.fn.getCwd returns a string', function() {
    const cwd = vim.fn.getCwd();
    vim.e2e.assert.equal(typeof cwd, 'string', 'getCwd should return a string');
  });

  vim.e2e.test('vim.fn.getCwd returns non-empty path', function() {
    const cwd = vim.fn.getCwd();
    vim.e2e.assert.true(cwd.length > 0, 'getCwd should return a non-empty path');
  });

  vim.e2e.test('vim.fn.getCwd returns absolute path', function() {
    const cwd = vim.fn.getCwd();
    vim.e2e.assert.true(cwd.startsWith('/'), 'getCwd should return an absolute path starting with /');
  });

  // ============================================================================
  // vim.fn.executable() Tests
  // ============================================================================

  vim.e2e.test('vim.fn.executable returns 1 for existing command (sh)', function() {
    // sh should exist on all Unix systems
    const result = vim.fn.executable('sh');
    vim.e2e.assert.equal(result, 1, 'sh should be executable');
  });

  vim.e2e.test('vim.fn.executable returns 1 for existing command (ls)', function() {
    const result = vim.fn.executable('ls');
    vim.e2e.assert.equal(result, 1, 'ls should be executable');
  });

  vim.e2e.test('vim.fn.executable returns 0 for non-existent command', function() {
    const result = vim.fn.executable('this_command_does_not_exist_12345');
    vim.e2e.assert.equal(result, 0, 'non-existent command should return 0');
  });

  vim.e2e.test('vim.fn.executable handles absolute path', function() {
    const result = vim.fn.executable('/bin/sh');
    vim.e2e.assert.equal(result, 1, '/bin/sh should be executable');
  });

  vim.e2e.test('vim.fn.executable returns 0 for non-existent absolute path', function() {
    const result = vim.fn.executable('/nonexistent/path/to/binary');
    vim.e2e.assert.equal(result, 0, 'non-existent absolute path should return 0');
  });

  // ============================================================================
  // vim.fn.expand() Tests
  // ============================================================================

  vim.e2e.test('vim.fn.expand % returns buffer name', function() {
    const result = vim.fn.expand('%');
    vim.e2e.assert.equal(typeof result, 'string', 'expand % should return a string');
  });

  vim.e2e.test('vim.fn.expand %:p returns full path', function() {
    const result = vim.fn.expand('%:p');
    vim.e2e.assert.equal(typeof result, 'string', 'expand %:p should return a string');
  });

  vim.e2e.test('vim.fn.expand %:t returns tail (filename only)', function() {
    // Set a known buffer name to test
    const buf = vim.api.getCurrentBuf();
    vim.api.bufSetName(buf, '/some/path/to/testfile.txt');

    const result = vim.fn.expand('%:t');
    vim.e2e.assert.equal(result, 'testfile.txt', 'expand %:t should return just the filename');
  });

  vim.e2e.test('vim.fn.expand returns input for unknown expressions', function() {
    const result = vim.fn.expand('unknown_expr');
    vim.e2e.assert.equal(result, 'unknown_expr', 'expand should return input for unknown expressions');
  });

  // ============================================================================
  // Integration: LSP use case simulation
  // ============================================================================

  vim.e2e.test('LSP root_dir pattern works', function() {
    // This simulates how LSP plugins determine root_dir
    const cwd = vim.fn.getCwd();
    vim.e2e.assert.true(cwd.length > 0, 'should be able to get cwd for LSP root_dir');
    vim.e2e.assert.true(cwd.startsWith('/'), 'cwd should be absolute for LSP');
  });

  vim.e2e.test('LSP server binary check pattern works', function() {
    // This simulates how LSP plugins check if server binary exists
    // Using 'node' as a common example
    const hasNode = vim.fn.executable('node');
    // We don't assert node exists, just that the function returns valid values
    vim.e2e.assert.true(hasNode === 0 || hasNode === 1, 'executable should return 0 or 1');
  });
});

vim.e2e.runAll();
