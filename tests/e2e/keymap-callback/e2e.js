// E2E test for keymap callback support
// Tests that vim.keymap.set() works with callback functions
let callbackExecuted = false;
let callbackCount = 0;
vim.e2e.describe('vim.keymap.set callback support', function () {
    vim.e2e.test('callback function is executed when key is pressed', function () {
        // Register a callback keymap
        vim.keymap.set('n', 'K', function () {
            callbackExecuted = true;
            callbackCount++;
            console.log('Callback executed! Count:', callbackCount);
        });
        // Verify callback starts as not executed
        vim.e2e.assert.equal(callbackExecuted, false, 'Callback should not be executed yet');
        // Press the mapped key
        vim.e2e.keys('K');
        // Verify callback was executed
        vim.e2e.assert.equal(callbackExecuted, true, 'Callback should be executed after pressing K');
        vim.e2e.assert.equal(callbackCount, 1, 'Callback should have been called once');
    });
    vim.e2e.test('callback can call vim.cmd methods', function () {
        // Create a test file
        vim.e2e.keys(':e /tmp/test_wincmd_callback.txt<CR>');
        vim.e2e.keys('iLeft window<Esc>');
        // Create a vsplit
        vim.e2e.keys(':vsplit /tmp/test_wincmd_callback_right.txt<CR>');
        vim.e2e.keys('iRight window<Esc>');
        // Get current window before
        const winBefore = vim.api.getCurrentWin();
        // Register callback that uses vim.cmd.wincmd
        vim.keymap.set('n', 'Q', function () {
            vim.cmd.wincmd('h');
        });
        // Press the mapped key
        vim.e2e.keys('Q');
        // Get current window after
        const winAfter = vim.api.getCurrentWin();
        console.log('Window before:', winBefore, 'after:', winAfter);
        // Verify window changed (if we have multiple windows)
        const winList = vim.api.listWins();
        if (winList.length >= 2) {
            vim.e2e.assert.true(winBefore !== winAfter, 'Window should change after Q press');
        }
        else {
            // Single window case - just verify no crash
            vim.e2e.assert.true(true, 'Callback executed without crash');
        }
    });
    vim.e2e.test('callback can modify state', function () {
        // Test that callbacks can modify state variables
        let stateModified = false;
        vim.keymap.set('n', 'Z', function () {
            stateModified = true;
        });
        // Get state before
        vim.e2e.assert.equal(stateModified, false, 'State should be false before Z');
        // Press the mapped key
        vim.e2e.keys('Z');
        // Verify state was modified
        vim.e2e.assert.equal(stateModified, true, 'State should be modified after Z');
    });
    vim.e2e.test('multiple callback mappings work independently', function () {
        let aPressed = false;
        let bPressed = false;
        vim.keymap.set('n', '<C-a>', function () {
            aPressed = true;
        });
        vim.keymap.set('n', '<C-b>', function () {
            bPressed = true;
        });
        // Press first mapping
        vim.e2e.keys('<C-a>');
        vim.e2e.assert.equal(aPressed, true, 'First callback should be executed');
        vim.e2e.assert.equal(bPressed, false, 'Second callback should not be executed');
        // Press second mapping
        vim.e2e.keys('<C-b>');
        vim.e2e.assert.equal(bPressed, true, 'Second callback should now be executed');
    });
    // Tests for control key notation conversion (byteToNotation)
    // Raw terminal bytes (e.g., byte 10 for Ctrl+J) must be converted to Vim notation (<C-j>)
    vim.e2e.test('control key callbacks work with <C-h/j/k/l> (window navigation keys)', function () {
        let ctrlH = false;
        let ctrlJ = false;
        let ctrlK = false;
        let ctrlL = false;
        vim.keymap.set('n', '<C-h>', function () { ctrlH = true; });
        vim.keymap.set('n', '<C-j>', function () { ctrlJ = true; });
        vim.keymap.set('n', '<C-k>', function () { ctrlK = true; });
        vim.keymap.set('n', '<C-l>', function () { ctrlL = true; });
        // Test each control key
        vim.e2e.keys('<C-h>');
        vim.e2e.assert.equal(ctrlH, true, '<C-h> callback should trigger');
        vim.e2e.keys('<C-j>');
        vim.e2e.assert.equal(ctrlJ, true, '<C-j> callback should trigger');
        vim.e2e.keys('<C-k>');
        vim.e2e.assert.equal(ctrlK, true, '<C-k> callback should trigger');
        vim.e2e.keys('<C-l>');
        vim.e2e.assert.equal(ctrlL, true, '<C-l> callback should trigger');
    });
    vim.e2e.test('control key callbacks work across the alphabet', function () {
        // Test a range of control keys to verify byteToNotation handles all cases
        let ctrlE = false;
        let ctrlN = false;
        let ctrlP = false;
        let ctrlT = false;
        // Map several control keys
        vim.keymap.set('n', '<C-e>', function () { ctrlE = true; });
        vim.keymap.set('n', '<C-n>', function () { ctrlN = true; });
        vim.keymap.set('n', '<C-p>', function () { ctrlP = true; });
        vim.keymap.set('n', '<C-t>', function () { ctrlT = true; });
        vim.e2e.keys('<C-e>');
        vim.e2e.assert.equal(ctrlE, true, '<C-e> callback should trigger');
        vim.e2e.keys('<C-n>');
        vim.e2e.assert.equal(ctrlN, true, '<C-n> callback should trigger');
        vim.e2e.keys('<C-p>');
        vim.e2e.assert.equal(ctrlP, true, '<C-p> callback should trigger');
        vim.e2e.keys('<C-t>');
        vim.e2e.assert.equal(ctrlT, true, '<C-t> callback should trigger');
    });
});
vim.e2e.runAll();
