// Test vim.mapleader and <leader> keymap expansion
vim.e2e.describe("leader keymaps", function() {

    vim.e2e.test("default mapleader is backslash", function() {
        vim.e2e.assert.equal(vim.mapleader, '\\');
    });

    vim.e2e.test("can set mapleader to space", function() {
        vim.mapleader = ' ';
        vim.e2e.assert.equal(vim.mapleader, ' ');
    });

    vim.e2e.test("vim.g.mapleader syncs with vim.mapleader", function() {
        vim.mapleader = ',';
        vim.e2e.assert.equal(vim.g.mapleader, ',');

        vim.g.mapleader = ';';
        vim.e2e.assert.equal(vim.mapleader, ';');
    });

    vim.e2e.test("<leader> keymap with space leader", function() {
        vim.mapleader = ' ';

        let called = false;
        vim.keymap.set('n', '<leader>t', function() {
            called = true;
        });

        vim.e2e.keys(' t');
        vim.e2e.assert.true(called, "leader keymap callback should be called");
    });

    vim.e2e.test("<leader> keymap with comma leader", function() {
        vim.mapleader = ',';

        let called = false;
        vim.keymap.set('n', '<leader>x', function() {
            called = true;
        });

        vim.e2e.keys(',x');
        vim.e2e.assert.true(called, "<leader>x with comma leader should work");
    });

    vim.e2e.test("<leader> multi-key sequence", function() {
        vim.mapleader = ' ';

        let called = false;
        vim.keymap.set('n', '<leader>gp', function() {
            called = true;
        });

        vim.e2e.keys(' gp');
        vim.e2e.assert.true(called, "<leader>gp should call the callback");
    });

    vim.e2e.test("<Leader> case insensitive", function() {
        vim.mapleader = ' ';

        let called = false;
        vim.keymap.set('n', '<Leader>z', function() {
            called = true;
        });

        vim.e2e.keys(' z');
        vim.e2e.assert.true(called, "<Leader> (capitalized) should also expand");
    });
});

vim.e2e.runAll();
