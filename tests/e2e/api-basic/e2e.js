console.log('[e2e.ts] Basic API Test');
console.log('[e2e.ts] vim.api.getMode:', typeof vim.api.getMode);
vim.e2e.describe('Basic API Tests', function () {
    vim.e2e.test('getMode returns valid object', function () {
        const mode = vim.api.getMode();
        console.log('Mode result:', JSON.stringify(mode));
        vim.e2e.assert.true(mode !== undefined, 'mode should exist');
        vim.e2e.assert.true(typeof mode.mode === 'string', 'mode.mode should be string');
    });
    vim.e2e.test('getCurrentWin returns number', function () {
        const win = vim.api.getCurrentWin();
        console.log('Win result:', win);
        vim.e2e.assert.true(typeof win === 'number', 'should be number');
    });
    vim.e2e.test('getCurrentBuf returns number', function () {
        const buf = vim.api.getCurrentBuf();
        console.log('Buf result:', buf);
        vim.e2e.assert.true(typeof buf === 'number', 'should be number');
    });
});
vim.e2e.runAll();
