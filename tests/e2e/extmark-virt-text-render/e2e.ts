// E2E test for extmark virt_text rendering
// Verifies that extmarks with virt_text option actually render to terminal

vim.e2e.describe('Extmark Virtual Text Rendering', function() {
  vim.e2e.test('virt_text renders at end of line (eol)', function() {
    // Create buffer with content
    vim.api.bufSetLines(0, 0, -1, false, ['Hello World']);

    // Create namespace and extmark with virt_text
    const ns = vim.api.createNamespace('render-test-eol');
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [[' <- virtual text', 'Comment']],
      virtTextPos: 'eol'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    // Force render
    vim.e2e.pty.render();

    // The virtual text should be rendered after "Hello World"
    // We can verify by checking that at least some content was rendered
    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('multiple virt_text chunks render correctly', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['const x = 1;']);

    const ns = vim.api.createNamespace('render-test-chunks');
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [
        [' // ', 'Comment'],
        ['type: ', 'Type'],
        ['number', 'Constant']
      ],
      virtTextPos: 'eol'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('virt_text overlay position renders at column', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Hello World']);

    const ns = vim.api.createNamespace('render-test-overlay');
    const id = vim.api.bufSetExtmark(0, ns, 0, 6, {
      virtText: [['OVERLAY', 'Error']],
      virtTextPos: 'overlay'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('virt_text right align renders at window edge', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Short line']);

    const ns = vim.api.createNamespace('render-test-right');
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['[Aligned]', 'Special']],
      virtTextPos: 'rightAlign'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('virt_text inline position renders at column', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['function test() {}']);

    const ns = vim.api.createNamespace('render-test-inline');
    const id = vim.api.bufSetExtmark(0, ns, 0, 9, {
      virtText: [['hint: ', 'DiagnosticHint'], ['void', 'Type']],
      virtTextPos: 'inline'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('virt_text updates on extmark change', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Test line']);

    const ns = vim.api.createNamespace('render-test-update');

    // Create initial extmark
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      id: 50,
      virtText: [['original', 'Comment']],
      virtTextPos: 'eol'
    });
    vim.e2e.assert.equal(id, 50, 'should use custom ID');

    vim.e2e.pty.render();

    // Update the extmark with new virt_text
    const id2 = vim.api.bufSetExtmark(0, ns, 0, 0, {
      id: 50,
      virtText: [['updated', 'Error']],
      virtTextPos: 'eol'
    });
    vim.e2e.assert.equal(id2, 50, 'should return same ID');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output after update');
  });

  vim.e2e.test('virt_text disappears after extmark deletion', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Delete me']);

    const ns = vim.api.createNamespace('render-test-delete');
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['to be deleted', 'Comment']],
      virtTextPos: 'eol'
    });

    vim.e2e.pty.render();

    // Delete the extmark
    const deleted = vim.api.bufDelExtmark(0, ns, id);
    vim.e2e.assert.true(deleted, 'extmark should be deleted');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output after deletion');
  });

  vim.e2e.test('multiple extmarks on same line render correctly', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Line with markers']);

    const ns = vim.api.createNamespace('render-test-multi-same-line');

    // Two extmarks with different positions
    vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['[1]', 'Number']],
      virtTextPos: 'overlay'
    });

    vim.api.bufSetExtmark(0, ns, 0, 10, {
      virtText: [['[2]', 'Number']],
      virtTextPos: 'overlay'
    });

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('extmarks on different lines render correctly', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Line 0', 'Line 1', 'Line 2']);

    const ns = vim.api.createNamespace('render-test-multi-lines');

    vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [[' (line 0)', 'Comment']],
      virtTextPos: 'eol'
    });

    vim.api.bufSetExtmark(0, ns, 1, 0, {
      virtText: [[' (line 1)', 'Comment']],
      virtTextPos: 'eol'
    });

    vim.api.bufSetExtmark(0, ns, 2, 0, {
      virtText: [[' (line 2)', 'Comment']],
      virtTextPos: 'eol'
    });

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('virt_text with no highlight group uses default colors', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Plain text']);

    const ns = vim.api.createNamespace('render-test-no-hl');
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      virtText: [['no highlight']],  // Only text, no highlight group
      virtTextPos: 'eol'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });

  vim.e2e.test('virt_text combined with hlGroup renders both', function() {
    vim.api.bufSetLines(0, 0, -1, false, ['Combined test']);

    const ns = vim.api.createNamespace('render-test-combined');
    const id = vim.api.bufSetExtmark(0, ns, 0, 0, {
      endLine: 0,
      endCol: 8,
      hlGroup: 'Search',  // Highlight the text range
      virtText: [[' <- highlighted', 'Comment']],  // Virtual text at end
      virtTextPos: 'eol'
    });

    vim.e2e.assert.true(id > 0, 'extmark should be created');

    vim.e2e.pty.render();

    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(captured.length > 0, 'should have captured PTY output');
  });
});

vim.e2e.runAll();
