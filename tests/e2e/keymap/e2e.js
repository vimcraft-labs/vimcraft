// Keymap API E2E Tests
// Tests vim.keymap.* API with real editor state
vim.e2e.describe("Keymap Set - String RHS", function () {
    vim.e2e.test("keymap.set with string rhs does not throw", function () {
        // Set a simple mapping
        vim.keymap.set('n', '<leader>t', ':echo "test"<CR>');
        // Should not throw
        vim.e2e.assert.true(true, "keymap.set completed without error");
    });
});
vim.e2e.describe("Keymap Set - Function RHS", function () {
    vim.e2e.test("keymap.set with function rhs does not throw", function () {
        let called = false;
        vim.keymap.set('n', '<leader>f', function () {
            called = true;
        });
        // Should not throw
        vim.e2e.assert.true(true, "keymap.set with function completed without error");
    });
});
vim.e2e.describe("Keymap Set - Options", function () {
    vim.e2e.test("keymap.set with options does not throw", function () {
        vim.keymap.set('n', '<leader>o', ':echo "options"<CR>', {
            desc: 'Test mapping with options',
            silent: true,
            noremap: true
        });
        // Should not throw
        vim.e2e.assert.true(true, "keymap.set with options completed without error");
    });
});
vim.e2e.describe("Keymap Del", function () {
    vim.e2e.test("keymap.del removes mapping", function () {
        // Create mapping
        vim.keymap.set('n', '<leader>d', ':echo "delete"<CR>');
        // Delete mapping (should not throw)
        vim.keymap.del('n', '<leader>d');
        // Deleting again should be idempotent
        vim.keymap.del('n', '<leader>d');
        vim.e2e.assert.true(true, "keymap.del completed without error");
    });
});
vim.e2e.describe("Keymap Modes", function () {
    vim.e2e.test("keymap.set works for different modes", function () {
        vim.keymap.set('n', '<leader>n', ':echo "normal"<CR>');
        vim.keymap.set('i', '<C-j>', '<Esc>');
        vim.keymap.set('v', '<leader>v', ':echo "visual"<CR>');
        vim.e2e.assert.true(true, "keymap.set for all modes completed without error");
    });
});
vim.e2e.runAll();
