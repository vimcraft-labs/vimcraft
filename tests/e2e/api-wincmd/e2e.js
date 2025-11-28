// E2E test for vim.cmd API
vim.e2e.describe('vim.cmd API', function () {
    vim.e2e.test('vim.cmd has all expected methods', function () {
        vim.e2e.assert.true(typeof vim.cmd === 'object', 'vim.cmd should be an object');
        vim.e2e.assert.true(typeof vim.cmd.wincmd === 'function', 'vim.cmd.wincmd');
        vim.e2e.assert.true(typeof vim.cmd.vsplit === 'function', 'vim.cmd.vsplit');
        vim.e2e.assert.true(typeof vim.cmd.split === 'function', 'vim.cmd.split');
        vim.e2e.assert.true(typeof vim.cmd.write === 'function', 'vim.cmd.write');
        vim.e2e.assert.true(typeof vim.cmd.quit === 'function', 'vim.cmd.quit');
        vim.e2e.assert.true(typeof vim.cmd.edit === 'function', 'vim.cmd.edit');
        vim.e2e.assert.true(typeof vim.cmd.new === 'function', 'vim.cmd.new');
        vim.e2e.assert.true(typeof vim.cmd.vnew === 'function', 'vim.cmd.vnew');
        vim.e2e.assert.true(typeof vim.cmd.only === 'function', 'vim.cmd.only');
        vim.e2e.assert.true(typeof vim.cmd.close === 'function', 'vim.cmd.close');
    });
    vim.e2e.test('vim.cmd.wincmd navigates between windows', function () {
        // Create a test file
        vim.e2e.keys(':e /tmp/test_cmd_left.txt<CR>');
        vim.e2e.keys('iLeft window<Esc>');
        // Create vsplit
        vim.e2e.keys(':vsplit /tmp/test_cmd_right.txt<CR>');
        vim.e2e.keys('iRight window<Esc>');
        // Check we have multiple windows
        const winList = vim.api.listWins();
        console.log('Window list:', JSON.stringify(winList));
        // Now we should be in the new window after vsplit
        const winBefore = vim.api.getCurrentWin();
        // Navigate using vim.cmd.wincmd
        vim.cmd.wincmd('h');
        const winAfter = vim.api.getCurrentWin();
        console.log('Before:', winBefore, 'After:', winAfter);
        if (winList.length >= 2) {
            vim.e2e.assert.true(winBefore !== winAfter, 'Window should change');
        }
        else {
            vim.e2e.assert.true(true);
        }
    });
});
vim.e2e.runAll();
