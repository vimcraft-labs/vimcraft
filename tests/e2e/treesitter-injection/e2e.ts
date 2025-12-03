/**
 * Tree-sitter Injection API Tests
 *
 * Tests the vim.treesitter.* API for language injections.
 * Validates the Neovim-compatible treesitter interface.
 */

console.log('[e2e.ts] Tree-sitter Injection Tests');

vim.e2e.describe('vim.treesitter API', function () {
  vim.e2e.test('hasParser returns boolean', function () {
    // Check for a language we definitely support
    const hasZig = vim.treesitter.hasParser('zig');
    console.log('hasParser(zig):', hasZig);
    vim.e2e.assert.true(typeof hasZig === 'boolean', 'should return boolean');
    vim.e2e.assert.true(hasZig === true, 'zig parser should exist');
  });

  vim.e2e.test('hasParser returns false for unknown', function () {
    const hasUnknown = vim.treesitter.hasParser('unknown_language_xyz');
    console.log('hasParser(unknown):', hasUnknown);
    vim.e2e.assert.true(hasUnknown === false, 'unknown language should return false');
  });

  vim.e2e.test('getLanguages returns array', function () {
    const languages = vim.treesitter.getLanguages();
    console.log('getLanguages count:', languages.length);
    vim.e2e.assert.true(Array.isArray(languages), 'should return array');
    vim.e2e.assert.true(languages.length > 0, 'should have languages');
    vim.e2e.assert.true(languages.includes('zig'), 'should include zig');
    vim.e2e.assert.true(languages.includes('c'), 'should include c');
  });

  vim.e2e.test('hasLanguageTree before init returns false', function () {
    const hasTree = vim.treesitter.hasLanguageTree();
    console.log('hasLanguageTree (before init):', hasTree);
    vim.e2e.assert.true(hasTree === false, 'should be false before getLanguageTree');
  });

  vim.e2e.test('getLanguageTree initializes LanguageTree', function () {
    // Initialize a language tree for the current buffer
    const result = vim.treesitter.getLanguageTree(0, 'c');
    console.log('getLanguageTree result:', result);
    vim.e2e.assert.true(typeof result === 'boolean', 'should return boolean');
  });

  vim.e2e.test('hasLanguageTree after init returns true', function () {
    // After getLanguageTree, hasLanguageTree should return true
    vim.treesitter.getLanguageTree(0, 'zig');
    const hasTree = vim.treesitter.hasLanguageTree();
    console.log('hasLanguageTree (after init):', hasTree);
    vim.e2e.assert.true(hasTree === true, 'should be true after getLanguageTree');
  });

  vim.e2e.test('updateTree succeeds after init', function () {
    // Initialize tree first
    vim.treesitter.getLanguageTree(0, 'c');

    // Update should succeed
    const result = vim.treesitter.updateTree();
    console.log('updateTree result:', result);
    vim.e2e.assert.true(typeof result === 'boolean', 'should return boolean');
    vim.e2e.assert.true(result === true, 'should succeed with initialized tree');
  });

  vim.e2e.test('getInjectedLanguages returns array', function () {
    // Initialize tree
    vim.treesitter.getLanguageTree(0, 'markdown');

    const injected = vim.treesitter.getInjectedLanguages();
    console.log('getInjectedLanguages:', injected);
    vim.e2e.assert.true(Array.isArray(injected), 'should return array');
    // May be empty if no injections are present
  });

  vim.e2e.test('languageForRange returns string or null', function () {
    // Initialize tree with content
    vim.e2e.keys('ifunction test() {}<Esc>');
    vim.treesitter.getLanguageTree(0, 'javascript');
    vim.treesitter.updateTree();

    // Query the language at byte range
    const lang = vim.treesitter.languageForRange(0, 10);
    console.log('languageForRange(0, 10):', lang);
    // Should return language name or null
    vim.e2e.assert.true(
      typeof lang === 'string' || lang === null,
      'should return string or null'
    );
  });
});

vim.e2e.describe('vim.treesitter injection workflow', function () {
  vim.e2e.test('markdown with code block workflow', function () {
    // Create markdown content with a code block
    const content = '# Header\n\n```javascript\nconst x = 1;\n```\n';
    vim.e2e.keys('i' + content + '<Esc>');

    // Initialize as markdown
    const init = vim.treesitter.getLanguageTree(0, 'markdown');
    console.log('Markdown tree init:', init);

    // Update the tree
    const updated = vim.treesitter.updateTree();
    console.log('Tree updated:', updated);

    // Check for injected languages
    const injected = vim.treesitter.getInjectedLanguages();
    console.log('Injected languages:', injected);

    // The markdown parser should detect the javascript code block
    // Note: actual injection depends on injections.scm query
    vim.e2e.assert.true(Array.isArray(injected), 'injected should be array');
  });
});

vim.e2e.runAll();
