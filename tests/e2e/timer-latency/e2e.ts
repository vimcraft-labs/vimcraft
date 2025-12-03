// E2E Test: Timer latency analysis
// Measures exactly where time is spent from keymap callback to setTimeout(0)

vim.e2e.describe('Timer Latency Analysis', () => {

  vim.e2e.test('setTimeout(0) latency after keymap callback', () => {
    // Track timing from keymap execution
    let keymapStartTime = 0;
    let keymapEndTime = 0;
    let setTimeoutFired = false;
    let setTimeoutTime = 0;

    // Register a keymap that times everything
    vim.keymap.set('n', 'T', () => {
      keymapStartTime = Date.now();

      // Do some work (simulate hover: create floating window)
      const buf = vim.api.createBuf(false, true);
      vim.api.bufSetLines(buf, 0, -1, false, ['Test line']);
      const win = vim.api.openWin(buf, false, {
        relative: 'editor',
        row: 5,
        col: 10,
        width: 20,
        height: 3,
        style: 'minimal',
        border: 'single',
      });

      // Schedule setTimeout(0) to measure when it fires
      setTimeout(() => {
        setTimeoutTime = Date.now();
        setTimeoutFired = true;
      }, 0);

      keymapEndTime = Date.now();

      // Clean up
      vim.api.winClose(win, true);
    });

    // Force render first to establish baseline
    vim.e2e.pty.render();

    // Trigger keymap
    vim.e2e.keys('T');

    // Wait for setTimeout to fire by doing more renders
    // Each render cycles through the event loop
    for (let i = 0; i < 10; i++) {
      vim.e2e.pty.render();
      if (setTimeoutFired) break;
    }

    console.log('=== TIMER LATENCY ===');
    console.log('  Keymap start:     ' + keymapStartTime);
    console.log('  Keymap end:       ' + keymapEndTime);
    console.log('  setTimeout fired: ' + setTimeoutTime);
    console.log('  ---');
    console.log('  Keymap duration:  ' + (keymapEndTime - keymapStartTime) + 'ms (JS work)');
    console.log('  Timer latency:    ' + (setTimeoutTime - keymapEndTime) + 'ms (from JS end to setTimeout)');
    console.log('  Total:            ' + (setTimeoutTime - keymapStartTime) + 'ms (from keymap start)');

    vim.e2e.assert.true(setTimeoutFired, 'setTimeout should have fired');
    vim.e2e.assert.true(setTimeoutTime - keymapEndTime < 50,
      'setTimeout(0) latency should be < 50ms, got: ' + (setTimeoutTime - keymapEndTime) + 'ms');
  });

  vim.e2e.test('setTimeout(0) without window creation', () => {
    // Minimal test - just setTimeout(0) from keymap
    let startTime = 0;
    let endTime = 0;
    let fired = false;

    vim.keymap.set('n', 'U', () => {
      startTime = Date.now();
      setTimeout(() => {
        endTime = Date.now();
        fired = true;
      }, 0);
    });

    vim.e2e.pty.render();
    vim.e2e.keys('U');

    for (let i = 0; i < 10; i++) {
      vim.e2e.pty.render();
      if (fired) break;
    }

    const latency = endTime - startTime;
    console.log('=== MINIMAL TIMER ===');
    console.log('  Latency: ' + latency + 'ms (setTimeout(0) only, no work)');

    vim.e2e.assert.true(fired, 'setTimeout should have fired');
    vim.e2e.assert.true(latency < 50, 'Minimal setTimeout(0) should be < 50ms, got: ' + latency + 'ms');
  });

  vim.e2e.test('render count to fire setTimeout(0)', () => {
    // How many render cycles needed for setTimeout(0) to fire?
    let fired = false;
    let renderCount = 0;

    vim.keymap.set('n', 'V', () => {
      setTimeout(() => { fired = true; }, 0);
    });

    vim.e2e.keys('V');

    while (!fired && renderCount < 20) {
      vim.e2e.pty.render();
      renderCount++;
    }

    console.log('=== RENDER CYCLES ===');
    console.log('  Renders until setTimeout(0) fired: ' + renderCount);

    vim.e2e.assert.true(fired, 'setTimeout should fire within 20 renders');
    vim.e2e.assert.true(renderCount <= 3,
      'setTimeout(0) should fire within 3 renders, took: ' + renderCount);
  });
});

vim.e2e.runAll();
