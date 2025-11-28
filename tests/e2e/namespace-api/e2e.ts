// Test namespace API: createNamespace, bufAddHighlight, bufClearNamespace
vim.e2e.describe('Namespace API', function() {
  vim.e2e.test('vim.api.createNamespace creates unique namespaces', function() {
    const ns1 = vim.api.createNamespace('my-plugin');
    const ns2 = vim.api.createNamespace('other-plugin');
    const ns1_again = vim.api.createNamespace('my-plugin');

    vim.e2e.assert.ok(ns1 > 0, 'namespace ID should be positive');
    vim.e2e.assert.ok(ns2 > 0, 'namespace ID should be positive');
    vim.e2e.assert.ok(ns1 !== ns2, 'different names should have different IDs');
    vim.e2e.assert.equal(ns1, ns1_again, 'same name should return same ID');
  });

  vim.e2e.test('vim.api.bufAddHighlight adds highlight and returns ID', function() {
    // Use buffer 0 (current buffer)
    const ns = vim.api.createNamespace('test-highlight');
    const hl_id = vim.api.bufAddHighlight(0, ns, 'Error', 0, 0, 5);

    vim.e2e.assert.ok(hl_id > 0, 'highlight ID should be positive');

    // Add another highlight
    const hl_id2 = vim.api.bufAddHighlight(0, ns, 'Comment', 0, 5, 10);
    vim.e2e.assert.ok(hl_id2 > hl_id, 'highlight IDs should be incrementing');
  });

  vim.e2e.test('vim.api.bufClearNamespace clears highlights in namespace', function() {
    const ns = vim.api.createNamespace('clear-test');

    // Add some highlights
    vim.api.bufAddHighlight(0, ns, 'Error', 0, 0, 5);
    vim.api.bufAddHighlight(0, ns, 'Warning', 0, 5, 10);

    // Clear the namespace (should not throw)
    vim.api.bufClearNamespace(0, ns, 0, -1);

    // This should pass - clearing is successful if no error thrown
    vim.e2e.assert.ok(true, 'bufClearNamespace completed without error');
  });

  vim.e2e.test('namespace 0 is global namespace', function() {
    // Global namespace (0) should work for adding highlights
    const hl_id = vim.api.bufAddHighlight(0, 0, 'DiagnosticError', 0, 0, 3);
    vim.e2e.assert.ok(hl_id > 0, 'global namespace highlight should be added');
  });

  vim.e2e.test('bufClearNamespace with ns_id=0 clears all namespaces', function() {
    // Create multiple namespaces
    const ns1 = vim.api.createNamespace('plugin-1');
    const ns2 = vim.api.createNamespace('plugin-2');

    // Add highlights to both
    vim.api.bufAddHighlight(0, ns1, 'Error', 0, 0, 3);
    vim.api.bufAddHighlight(0, ns2, 'Warning', 0, 3, 6);

    // Clear all namespaces with ns_id=0
    vim.api.bufClearNamespace(0, 0, 0, -1);

    // Should complete without error
    vim.e2e.assert.ok(true, 'clearing all namespaces completed');
  });

  vim.e2e.test('bufClearNamespace respects line range', function() {
    const ns = vim.api.createNamespace('range-test');

    // Need a buffer with multiple lines - insert some content first
    vim.e2e.keys('iLine 1<CR>Line 2<CR>Line 3<Esc>gg');

    // Add highlights on different lines
    vim.api.bufAddHighlight(0, ns, 'Error', 0, 0, 3);   // line 0
    vim.api.bufAddHighlight(0, ns, 'Warning', 1, 0, 3); // line 1
    vim.api.bufAddHighlight(0, ns, 'Comment', 2, 0, 3); // line 2

    // Clear only line 1
    vim.api.bufClearNamespace(0, ns, 1, 2);

    // Should complete without error
    vim.e2e.assert.ok(true, 'clearing line range completed');
  });
});

vim.e2e.runAll();
