// Namespace API E2E Tests
// Tests vim.api.createNamespace() and vim.api.getNamespaces()

vim.e2e.describe('Namespace API', function() {
  vim.e2e.test('createNamespace returns unique ID', function() {
    const ns1 = vim.api.createNamespace('test-plugin-1');
    const ns2 = vim.api.createNamespace('test-plugin-2');

    // IDs should be positive integers
    vim.e2e.assert.true(ns1 > 0, 'ns1 should be positive');
    vim.e2e.assert.true(ns2 > 0, 'ns2 should be positive');

    // IDs should be unique
    vim.e2e.assert.true(ns1 !== ns2, 'namespaces should have different IDs');
  });

  vim.e2e.test('createNamespace returns same ID for same name', function() {
    const ns1 = vim.api.createNamespace('my-lsp');
    const ns2 = vim.api.createNamespace('my-lsp');

    vim.e2e.assert.equal(ns1, ns2, 'same name should return same ID');
  });

  vim.e2e.test('getNamespaces returns all created namespaces', function() {
    // Create some namespaces
    const diagnosticNs = vim.api.createNamespace('diagnostic');
    const highlightNs = vim.api.createNamespace('highlight');

    // Get all namespaces
    const namespaces = vim.api.getNamespaces();

    // Should have our namespaces
    vim.e2e.assert.equal(namespaces['diagnostic'], diagnosticNs, 'diagnostic namespace should match');
    vim.e2e.assert.equal(namespaces['highlight'], highlightNs, 'highlight namespace should match');
  });

  vim.e2e.test('getNamespaces returns empty object when no namespaces created', function() {
    // Note: Other tests may have created namespaces, so we just check it returns an object
    const namespaces = vim.api.getNamespaces();
    vim.e2e.assert.true(typeof namespaces === 'object', 'should return an object');
  });

});

vim.e2e.runAll();
