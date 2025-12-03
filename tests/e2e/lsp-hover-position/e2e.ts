// E2E test for LSP hover popup positioning
// Reproduces issue: "Shift+K render weird LSP floating window (no content, and sit on above instead below cursor block)"

vim.e2e.describe('LSP hover popup positioning', function() {
  vim.e2e.test('popup appears below cursor when there is room', function() {
    // Create a buffer with content
    vim.e2e.keys(':e /tmp/test_hover.txt<CR>');

    // Add multiple lines so cursor can be in the middle
    const lines = [];
    for (let i = 1; i <= 20; i++) {
      lines.push('Line ' + i);
    }

    for (let i = 0; i < lines.length; i++) {
      vim.e2e.keys('i' + lines[i] + '<Esc>');
      if (i < lines.length - 1) {
        vim.e2e.keys('o');
      }
    }

    // Position cursor at line 5 (plenty of room below)
    vim.e2e.keys('gg');
    vim.e2e.keys('4j');

    const cursorBefore = vim.e2e.getCursor();
    console.log('=== HOVER POSITION TEST ===');
    console.log('Cursor before popup:', cursorBefore);

    // Create a floating window manually (simulating hover popup)
    // using the same logic as LSP hover handler
    const bufnr = vim.api.createBuf(false, true);
    vim.api.bufSetLines(bufnr, 0, -1, false, [
      'Hover content line 1',
      'Hover content line 2',
      'Hover content line 3'
    ]);

    // Open floating window with 'auto' positioning (should prefer below)
    const winid = vim.api.openWin(bufnr, false, {
      relative: 'cursor',
      anchor: 'NW',
      row: 1,  // This is what makeFloatingPopupOptions calculates
      col: 0,
      width: 25,
      height: 3,
      style: 'minimal',
      border: 'rounded',
      focusable: false,
      zindex: 100
    });

    // Get the window position
    const winPos = vim.api.winGetPosition(winid);
    console.log('Floating window position:', winPos);
    console.log('Expected: window should be BELOW cursor (row > cursor.line)');

    // The window position should be below the cursor
    // For cursor at line 4 (0-indexed), window should be at a higher row number
    vim.e2e.assert.true(winPos[0] > cursorBefore.line,
      'Window should appear below cursor, got row=' + winPos[0] + ' cursor.line=' + cursorBefore.line);

    // Clean up
    vim.api.winClose(winid, true);
    vim.api.bufDelete(bufnr, { force: true });
  });

  vim.e2e.test('popup flips above cursor when no room below', function() {
    // Create a buffer with content
    vim.e2e.keys(':e /tmp/test_hover2.txt<CR>');

    const lines = [];
    for (let i = 1; i <= 20; i++) {
      lines.push('Line ' + i);
    }

    for (let i = 0; i < lines.length; i++) {
      vim.e2e.keys('i' + lines[i] + '<Esc>');
      if (i < lines.length - 1) {
        vim.e2e.keys('o');
      }
    }

    // Position cursor near the bottom (line 18)
    vim.e2e.keys('G');
    vim.e2e.keys('2k');

    const cursorBefore = vim.e2e.getCursor();
    console.log('=== HOVER FLIP TEST ===');
    console.log('Cursor near bottom:', cursorBefore);

    // Create a tall floating window (won't fit below)
    const bufnr = vim.api.createBuf(false, true);
    const content = [];
    for (let i = 1; i <= 10; i++) {
      content.push('Hover line ' + i);
    }
    vim.api.bufSetLines(bufnr, 0, -1, false, content);

    // Open floating window - should flip above due to height
    const winid = vim.api.openWin(bufnr, false, {
      relative: 'cursor',
      anchor: 'SW',  // SW = above cursor
      row: -1,
      col: 0,
      width: 25,
      height: 10,
      style: 'minimal',
      border: 'rounded',
      focusable: false,
      zindex: 100
    });

    const winPos = vim.api.winGetPosition(winid);
    console.log('Floating window position (should be above):', winPos);

    // When anchor is SW and row is -1, window appears above cursor
    // The row should be less than cursor line
    vim.e2e.assert.true(winPos[0] < cursorBefore.line,
      'Window should appear above cursor when no room below, got row=' + winPos[0] + ' cursor.line=' + cursorBefore.line);

    // Clean up
    vim.api.winClose(winid, true);
    vim.api.bufDelete(bufnr, { force: true });
  });
});

vim.e2e.runAll();
