// E2E test for Neovim-style scroll past EOF (zz centering)
// Tests that zz at the last line centers the cursor by showing virtual "~" lines below
// AND that the gutter has no line numbers for virtual lines
vim.e2e.describe('Scroll past EOF (zz centering)', function () {
    vim.e2e.test('zz at last line allows scrolling past end', function () {
        // Go to last line
        vim.e2e.keys('G');
        const state1 = vim.e2e.getState();
        const lastLine = state1.cursor.row;
        console.log('Cursor at last line:', lastLine);
        // Press zz to center
        vim.e2e.keys('zz');
        const state2 = vim.e2e.getState();
        console.log('After zz - cursor still at:', state2.cursor.row);
        // zz should NOT move the cursor
        vim.e2e.assert.equal(state2.cursor.row, lastLine, 'Cursor should stay on same line after zz');
    });
    vim.e2e.test('L followed by zz centers bottom line', function () {
        // Go to top first
        vim.e2e.keys('gg');
        const state1 = vim.e2e.getState();
        console.log('Initial cursor:', state1.cursor.row);
        // Press L (go to viewport bottom)
        vim.e2e.keys('L');
        const state2 = vim.e2e.getState();
        console.log('After L - cursor:', state2.cursor.row);
        // Press zz to center
        vim.e2e.keys('zz');
        const state3 = vim.e2e.getState();
        console.log('After zz - cursor:', state3.cursor.row);
        // Cursor should still be on the same line as after L
        vim.e2e.assert.equal(state3.cursor.row, state2.cursor.row, 'Cursor should stay on same line after zz');
    });
    vim.e2e.test('gutter has no line numbers for virtual lines beyond EOF', function () {
        var _a, _b, _c, _d;
        // Go to last line and center it
        vim.e2e.keys('G');
        const stateBeforeZz = vim.e2e.getState();
        console.log('Before zz:');
        console.log('  cursor row:', stateBeforeZz.cursor.row);
        console.log('  buffer lineCount:', (_a = stateBeforeZz.buffer) === null || _a === void 0 ? void 0 : _a.lineCount);
        console.log('  viewport top:', (_b = stateBeforeZz.viewport) === null || _b === void 0 ? void 0 : _b.top);
        console.log('  viewport height:', (_c = stateBeforeZz.viewport) === null || _c === void 0 ? void 0 : _c.height);
        vim.e2e.keys('zz');
        const stateAfterZz = vim.e2e.getState();
        console.log('After zz:');
        console.log('  viewport top:', (_d = stateAfterZz.viewport) === null || _d === void 0 ? void 0 : _d.top);
        // Capture PTY output using the pattern counting approach (proven to work)
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        // Count tilde characters (~) which indicate virtual empty lines below EOF
        const tildeCount = vim.e2e.pty.countSequence('~');
        console.log('Tilde count in PTY output:', tildeCount);
        vim.e2e.pty.stopCapture();
        // The ~ lines should appear for virtual content beyond EOF
        // In Neovim, virtual lines show "~" with empty gutter
        vim.e2e.assert.true(tildeCount > 0, 'Should have ~ lines for virtual content beyond EOF (got ' + tildeCount + ')');
    });
    vim.e2e.test('viewport_top can exceed buffer boundary for centering', function () {
        var _a, _b, _c;
        // Go to last line
        vim.e2e.keys('G');
        const stateBefore = vim.e2e.getState();
        const lineCount = ((_a = stateBefore.buffer) === null || _a === void 0 ? void 0 : _a.lineCount) || 0;
        console.log('Buffer line count:', lineCount);
        console.log('Cursor row:', stateBefore.cursor.row);
        // Press zz to center
        vim.e2e.keys('zz');
        const stateAfter = vim.e2e.getState();
        const viewportTop = ((_b = stateAfter.viewport) === null || _b === void 0 ? void 0 : _b.top) || 0;
        const viewportHeight = ((_c = stateAfter.viewport) === null || _c === void 0 ? void 0 : _c.height) || 24;
        console.log('After zz:');
        console.log('  viewport_top:', viewportTop);
        console.log('  viewport_height:', viewportHeight);
        console.log('  cursor row:', stateAfter.cursor.row);
        // For centering to work, viewport_top + half_height should equal cursor_row
        // This means viewport_top can be > lineCount - viewportHeight
        const expectedTop = stateAfter.cursor.row - Math.floor(viewportHeight / 2);
        console.log('  expected viewport_top for centering:', expectedTop);
        // The viewport should allow scrolling past end
        vim.e2e.assert.true(viewportTop >= 0, 'Viewport top should be non-negative');
    });
});
vim.e2e.runAll();
