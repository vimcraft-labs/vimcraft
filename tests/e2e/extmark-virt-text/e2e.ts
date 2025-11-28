// Extmark Virtual Text E2E Tests
// Tests for bufSetExtmark with virt_text option - Neovim-compatible API

vim.e2e.describe('Extmark Virtual Text', function() {
  // ============================================================================
  // Basic virt_text creation
  // ============================================================================

  vim.e2e.test('bufSetExtmark with virt_text returns valid ID', function() {
    // Create buffer with some content
    vim.api.bufSetLines(0, 0, -1, false, ['Hello World', 'Line 2']);

    // Create namespace
    const ns = vim.api.createNamespace('test-virt-text');
    vim.e2e.assert.true(ns > 0, 'namespace should be created');

    // Set extmark with virt_text
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [[' <- this is virtual text', 'Comment']]
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  vim.e2e.test('bufSetExtmark with multiple virt_text chunks', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['const x = 1;']);

    const ns = vim.api.createNamespace('multi-chunk');

    // Multiple chunks with different highlight groups
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [
        [' // ', 'Comment'],
        ['type: ', 'Type'],
        ['number', 'Constant']
      ]
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');

    // Verify extmark exists
    const result = vim.api.bufGetExtmarkById(0, ns, id, {});
    vim.e2e.assert.true(result !== null, 'extmark should exist');
  });

  vim.e2e.test('bufSetExtmark with virtTextPos eol', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Line 1']);

    const ns = vim.api.createNamespace('eol-test');

    // Default is eol
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [[' <- EOL', 'Comment']],
      virtTextPos: 'eol'
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  vim.e2e.test('bufSetExtmark with virtTextPos overlay', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Hello World']);

    const ns = vim.api.createNamespace('overlay-test');

    // Overlay at column 6
    const id = vim.api.bufSetExtmark(0, ns, 0, 6, {
      virtText: [['OVERLAY', 'Error']],
      virtTextPos: 'overlay'
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  vim.e2e.test('bufSetExtmark with virtTextPos rightAlign', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Short line']);

    const ns = vim.api.createNamespace('right-align-test');

    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['[Aligned Right]', 'Special']],
      virtTextPos: 'rightAlign'
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  vim.e2e.test('bufSetExtmark with virtTextPos inline', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['function test() {}']);

    const ns = vim.api.createNamespace('inline-test');

    const id = vim.api.bufSetExtmark(0, ns, 0, 9, {
      virtText: [['hint: ', 'DiagnosticHint'], ['void', 'Type']],
      virtTextPos: 'inline'
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  // ============================================================================
  // Extmark with virt_text can be deleted
  // ============================================================================

  vim.e2e.test('bufDelExtmark removes virt_text extmark', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Test line']);

    const ns = vim.api.createNamespace('delete-test');

    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [[' virtual', 'Comment']]
    });

    // Verify it exists
    let result = vim.api.bufGetExtmarkById(0, ns, id, {});
    vim.e2e.assert.true(result !== null, 'extmark should exist before delete');

    // Delete it
    const deleted = vim.api.bufDelExtmark(0, ns, id);
    vim.e2e.assert.true(deleted, 'bufDelExtmark should return true');

    // Verify it's gone
    result = vim.api.bufGetExtmarkById(0, ns, id, {});
    vim.e2e.assert.true(result === null, 'extmark should not exist after delete');
  });

  // ============================================================================
  // Extmark with virt_text updates in place
  // ============================================================================

  vim.e2e.test('bufSetExtmark updates existing extmark virt_text', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Original line']);

    const ns = vim.api.createNamespace('update-test');

    // Create initial extmark
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      id: 42,
      virtText: [['original', 'Comment']]
    });

    vim.e2e.assert.equal(id, 42, 'should use provided ID');

    // Update with new virt_text
    const id2 = vim.api.bufSetExtmark(0, ns, 0, 0, {
      id: 42,
      virtText: [['updated', 'Error']]
    });

    vim.e2e.assert.equal(id2, 42, 'should return same ID');

    // Verify only one extmark exists
    const extmarks = vim.api.bufGetExtmarks(0, ns, 0, -1, {});
    vim.e2e.assert.equal(extmarks.length, 1, 'should have exactly one extmark');
  });

  // ============================================================================
  // virt_text without highlight group
  // ============================================================================

  vim.e2e.test('bufSetExtmark with virt_text no highlight group', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Plain text']);

    const ns = vim.api.createNamespace('no-hl-test');

    // Only text, no highlight group (second element omitted)
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['no highlight']]
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  // ============================================================================
  // Combined virt_text and hlGroup
  // ============================================================================

  vim.e2e.test('bufSetExtmark with both hlGroup and virt_text', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Combined test']);

    const ns = vim.api.createNamespace('combined-test');

    // Both range highlight and virtual text
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      endLine: 0,
      endCol: 8,
      hlGroup: 'Search',
      virtText: [[' <- highlighted range', 'Comment']]
    });

    vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
  });

  // ============================================================================
  // Multiple extmarks on same line
  // ============================================================================

  vim.e2e.test('multiple extmarks with virt_text on same line', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Line with multiple markers']);

    const ns = vim.api.createNamespace('multi-same-line');

    // First at position 0
    const id1 = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['[1]', 'Number']]
    });

    // Second at position 10
    const id2 = vim.api.bufSetExtmark(0, ns, 0, 10, {
      virtText: [['[2]', 'Number']]
    });

    vim.e2e.assert.true(id1 > 0, 'first extmark ID should be positive');
    vim.e2e.assert.true(id2 > 0, 'second extmark ID should be positive');
    vim.e2e.assert.true(id1 !== id2, 'extmark IDs should be different');

    const extmarks = vim.api.bufGetExtmarks(0, ns, 0, -1, {});
    vim.e2e.assert.equal(extmarks.length, 2, 'should have two extmarks');
  });

  // ============================================================================
  // Extmarks on different lines
  // ============================================================================

  vim.e2e.test('extmarks with virt_text on different lines', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Line 0', 'Line 1', 'Line 2']);

    const ns = vim.api.createNamespace('multi-line');

    vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [[' (line 0)', 'Comment']]
    });

    vim.api.bufSetExtmark(0, ns, 1, 0, {
      virtText: [[' (line 1)', 'Comment']]
    });

    vim.api.bufSetExtmark(0, ns, 2, 0, {
      virtText: [[' (line 2)', 'Comment']]
    });

    const extmarks = vim.api.bufGetExtmarks(0, ns, 0, -1, {});
    vim.e2e.assert.equal(extmarks.length, 3, 'should have three extmarks');
  });
});

vim.e2e.runAll();
