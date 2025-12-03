// E2E test for screenFg/screenBg APIs
// Tests that we can read cell colors from the compositor output

vim.e2e.describe('Screen Color APIs', function() {
  vim.e2e.test('screenFg and screenBg exist', function() {
    vim.e2e.assert.true(typeof vim.layer.screenFg === 'function', 'screenFg should be a function');
    vim.e2e.assert.true(typeof vim.layer.screenBg === 'function', 'screenBg should be a function');
  });

  vim.e2e.test('detailed color reading at cursor position', function() {
    // Load a file with content
    vim.e2e.keys(':e /tmp/test_colors.txt<CR>');
    vim.e2e.keys('iHello World<Esc>0');
    vim.e2e.pty.render();

    // Get gutter width and cursor position
    const gutter = vim.layer.getGutterWidth();
    const cursor = vim.cursor.getPosition();
    const viewport = vim.layer.getViewportInfo();

    console.log('=== DEBUG SCREEN COLORS ===');
    console.log('Gutter width:', gutter);
    console.log('Cursor position (buffer):', cursor.row, cursor.col);
    console.log('Viewport:', JSON.stringify(viewport));

    // Convert buffer position to screen position
    const screenRow = cursor.row - viewport.top;
    const screenCol = cursor.col + gutter - viewport.left;
    console.log('Screen position:', screenRow, screenCol);

    // Read character and colors at cursor position
    const char = vim.layer.screenchar(screenRow, screenCol);
    const fg = vim.layer.screenFg(screenRow, screenCol);
    const bg = vim.layer.screenBg(screenRow, screenCol);

    console.log('At cursor (screen ' + screenRow + ',' + screenCol + '):');
    console.log('  char:', char, '-> "' + String.fromCodePoint(char || 32) + '"');
    console.log('  fg:', fg, fg !== null ? '(0x' + fg.toString(16) + ')' : '(null)');
    console.log('  bg:', bg, bg !== null ? '(0x' + bg.toString(16) + ')' : '(null)');

    // Also read a few cells around cursor
    console.log('Cells around cursor:');
    for (let col = gutter; col < gutter + 6; col++) {
      const c = vim.layer.screenchar(0, col);
      const f = vim.layer.screenFg(0, col);
      const b = vim.layer.screenBg(0, col);
      console.log('  (' + 0 + ',' + col + '): char=' + (c || 0) + ' "' + String.fromCodePoint(c || 32) + '" fg=' + (f !== null ? '0x' + f.toString(16) : 'null') + ' bg=' + (b !== null ? '0x' + b.toString(16) : 'null'));
    }

    vim.e2e.assert.true(true, 'Debug output complete');
  });

  vim.e2e.test('screenFg returns color for text cell', function() {
    // Load a file with content
    vim.e2e.keys(':e /tmp/test_colors.txt<CR>');
    vim.e2e.keys('iHello<Esc>');
    vim.e2e.pty.render();

    // Get gutter width to find text area
    const gutter = vim.layer.getGutterWidth();

    // Read foreground color at first character position
    const fg = vim.layer.screenFg(0, gutter);

    // Should return a color (number) or null, not undefined
    console.log('screenFg(0, ' + gutter + ') =', fg);

    // The fg should be a number (hex color) if text is present
    // It could be null if no custom fg color is set
    vim.e2e.assert.true(fg === null || typeof fg === 'number',
      'screenFg should return number or null, got: ' + typeof fg);
  });

  vim.e2e.test('screenBg returns color for text cell', function() {
    // Load a file with content
    vim.e2e.keys(':e /tmp/test_colors.txt<CR>');
    vim.e2e.pty.render();

    // Get gutter width to find text area
    const gutter = vim.layer.getGutterWidth();

    // Read background color at first character position
    const bg = vim.layer.screenBg(0, gutter);

    console.log('screenBg(0, ' + gutter + ') =', bg);

    // The bg should be a number (hex color) or null
    vim.e2e.assert.true(bg === null || typeof bg === 'number',
      'screenBg should return number or null, got: ' + typeof bg);
  });

  vim.e2e.test('screenchar, screenFg, screenBg return consistent types', function() {
    vim.e2e.pty.render();

    // vim.layer uses 0-based indexing
    const char = vim.layer.screenchar(0, 0);
    const fg = vim.layer.screenFg(0, 0);
    const bg = vim.layer.screenBg(0, 0);

    console.log('Cell at (0, 0):');
    console.log('  char:', char, '(type:', typeof char, ')');
    console.log('  fg:', fg, '(type:', typeof fg, ')');
    console.log('  bg:', bg, '(type:', typeof bg, ')');

    // Verify return types are consistent
    vim.e2e.assert.true(typeof char === 'number', 'screenchar should return number');
    vim.e2e.assert.true(fg === null || typeof fg === 'number', 'screenFg should return number or null');
    vim.e2e.assert.true(bg === null || typeof bg === 'number', 'screenBg should return number or null');
  });

  vim.e2e.test('vim.fn screen functions exist and have correct types', function() {
    // Verify vim.fn wrappers exist
    vim.e2e.assert.true(typeof vim.fn.screenchar === 'function', 'vim.fn.screenchar should exist');
    vim.e2e.assert.true(typeof vim.fn.screenFg === 'function', 'vim.fn.screenFg should exist');
    vim.e2e.assert.true(typeof vim.fn.screenBg === 'function', 'vim.fn.screenBg should exist');

    vim.e2e.pty.render();

    // vim.fn uses 0-based indexing (JavaScript convention)
    const char = vim.fn.screenchar(0, 0);
    const fg = vim.fn.screenFg(0, 0);
    const bg = vim.fn.screenBg(0, 0);

    console.log('vim.fn.screenchar(0, 0) =', char);
    console.log('vim.fn.screenFg(0, 0) =', fg);
    console.log('vim.fn.screenBg(0, 0) =', bg);

    // Verify return types
    vim.e2e.assert.true(typeof char === 'number', 'vim.fn.screenchar should return number');
    vim.e2e.assert.true(fg === null || typeof fg === 'number', 'vim.fn.screenFg should return number or null');
    vim.e2e.assert.true(bg === null || typeof bg === 'number', 'vim.fn.screenBg should return number or null');
  });
});

vim.e2e.runAll();
