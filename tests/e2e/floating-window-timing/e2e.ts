// E2E Test: Floating window render timing with detailed breakdown

vim.e2e.describe('Floating Window Timing', () => {
  vim.e2e.test('baseline render timing breakdown', () => {
    vim.e2e.pty.render();
    const stats = vim.e2e.pty.getRenderStats() as any;
    console.log('=== BASELINE RENDER ===');
    console.log('  Total render:  ' + stats.lastRenderMs.toFixed(2) + 'ms');
    console.log('  Layer update:  ' + (stats.layerUpdateMs || 0).toFixed(2) + 'ms');
    console.log('  Compositor:    ' + (stats.compositorMs || 0).toFixed(2) + 'ms');
    console.log('  Diff:          ' + (stats.diffMs || 0).toFixed(2) + 'ms');
    console.log('  Output:        ' + (stats.outputMs || 0).toFixed(2) + 'ms');
    console.log('  Flush:         ' + (stats.flushMs || 0).toFixed(2) + 'ms (0 in E2E)');
    console.log('  Cells updated: ' + stats.cellsUpdatedLast);
    vim.e2e.assert.true(stats.lastRenderMs < 50, 'Baseline should be < 50ms');
  });

  vim.e2e.test('second render (no changes) breakdown', () => {
    // First render to populate previous buffer
    vim.e2e.pty.render();

    // Second render - should be fast with 0 cells!
    vim.e2e.pty.render();
    const stats = vim.e2e.pty.getRenderStats() as any;
    console.log('=== SECOND RENDER (no changes) ===');
    console.log('  Total render:  ' + stats.lastRenderMs.toFixed(2) + 'ms');
    console.log('  Layer update:  ' + (stats.layerUpdateMs || 0).toFixed(2) + 'ms');
    console.log('  Compositor:    ' + (stats.compositorMs || 0).toFixed(2) + 'ms');
    console.log('  Diff:          ' + (stats.diffMs || 0).toFixed(2) + 'ms');
    console.log('  Output:        ' + (stats.outputMs || 0).toFixed(2) + 'ms');
    console.log('  Cells updated: ' + stats.cellsUpdatedLast);

    // Expect 0 cells updated when nothing changed
    vim.e2e.assert.true(stats.cellsUpdatedLast === 0,
      'Second render should update 0 cells, got: ' + stats.cellsUpdatedLast);
  });

  vim.e2e.test('floating window render breakdown', () => {
    // First render to establish baseline
    vim.e2e.pty.render();

    // Create floating window (simulates hover popup)
    const buf = vim.api.createBuf(false, true);
    vim.api.bufSetLines(buf, 0, -1, false, ['Hover info', 'Type: number', 'More details here']);
    const win = vim.api.openWin(buf, false, {
      relative: 'editor',
      row: 5,
      col: 10,
      width: 30,
      height: 5,
      style: 'minimal',
      border: 'rounded',
    });

    // Render with floating
    vim.e2e.pty.render();
    const stats = vim.e2e.pty.getRenderStats() as any;
    console.log('=== FLOATING WINDOW RENDER ===');
    console.log('  Total render:  ' + stats.lastRenderMs.toFixed(2) + 'ms');
    console.log('  Layer update:  ' + (stats.layerUpdateMs || 0).toFixed(2) + 'ms');
    console.log('  Compositor:    ' + (stats.compositorMs || 0).toFixed(2) + 'ms');
    console.log('  Diff:          ' + (stats.diffMs || 0).toFixed(2) + 'ms');
    console.log('  Output:        ' + (stats.outputMs || 0).toFixed(2) + 'ms');
    console.log('  Cells updated: ' + stats.cellsUpdatedLast);

    // Clean up
    vim.api.winClose(win, true);

    vim.e2e.assert.true(stats.lastRenderMs < 100, 'Floating render should be < 100ms');
  });

  vim.e2e.test('cell count progression', () => {
    // First render - populates previous buffer
    vim.e2e.pty.render();
    const firstCells = vim.e2e.pty.getRenderStats().cellsUpdatedLast;

    // Second render WITHOUT changes - should be 0 cells!
    vim.e2e.pty.render();
    const secondCells = vim.e2e.pty.getRenderStats().cellsUpdatedLast;

    // Third render - add floating window
    const buf = vim.api.createBuf(false, true);
    vim.api.bufSetLines(buf, 0, -1, false, ['Hover']);
    const win = vim.api.openWin(buf, false, {
      relative: 'editor',
      row: 5,
      col: 10,
      width: 20,
      height: 3,
      style: 'minimal',
      border: 'single',
    });
    vim.e2e.pty.render();
    const floatingCells = vim.e2e.pty.getRenderStats().cellsUpdatedLast;

    console.log('=== CELL COUNTS ===');
    console.log('  First render:    ' + firstCells + ' cells (full screen expected)');
    console.log('  Second render:   ' + secondCells + ' cells (0 expected)');
    console.log('  Floating render: ' + floatingCells + ' cells (popup only expected)');

    vim.api.winClose(win, true);

    // Second render should be 0 (diff optimization)
    vim.e2e.assert.true(secondCells === 0, 'Second render should update 0 cells, got: ' + secondCells);
    // Floating should update fewer cells than first render
    vim.e2e.assert.true(floatingCells < firstCells,
      'Floating should update fewer than ' + firstCells + ' cells, got: ' + floatingCells);
  });
});

vim.e2e.runAll();
