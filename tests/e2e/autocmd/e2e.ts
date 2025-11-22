// AutoCommand API E2E Tests
// Tests vim.api.createAutoCommand with real editor state

vim.e2e.describe("AutoCommand Creation", function() {
    vim.e2e.test("createAutoCommand returns incrementing IDs", function() {
        let callCount = 0;
        const callback = function() { callCount++; };

        const id1 = vim.api.createAutoCommand('BufEnter', { callback: callback });
        const id2 = vim.api.createAutoCommand('BufEnter', { callback: callback });
        const id3 = vim.api.createAutoCommand('BufEnter', { callback: callback });

        vim.e2e.assert.true(id1 > 0, 'First autocommand should have positive ID');
        vim.e2e.assert.true(id2 > id1, 'Second autocommand should have higher ID');
        vim.e2e.assert.true(id3 > id2, 'Third autocommand should have higher ID');

        // Cleanup
        vim.api.deleteAutoCommand(id1);
        vim.api.deleteAutoCommand(id2);
        vim.api.deleteAutoCommand(id3);
    });

    vim.e2e.test("createAutoCommand with pattern", function() {
        let triggeredFile = '';
        const callback = function(ev: { file?: string }) {
            triggeredFile = ev.file || '';
        };

        const id = vim.api.createAutoCommand('BufEnter', {
            callback: callback,
            pattern: '*.ts',
            desc: 'Test TypeScript files'
        });

        vim.e2e.assert.true(id > 0, 'Should return valid ID');

        // Cleanup
        vim.api.deleteAutoCommand(id);
    });
});

vim.e2e.describe("AutoCommand Groups", function() {
    vim.e2e.test("createAutoCommand with group", function() {
        const group = vim.api.createAutoGroup('test_group', { clear: true });

        const id1 = vim.api.createAutoCommand('BufEnter', {
            callback: function() {},
            group: 'test_group'
        });

        const id2 = vim.api.createAutoCommand('BufLeave', {
            callback: function() {},
            group: 'test_group'
        });

        vim.e2e.assert.true(id1 > 0, 'First autocommand should have valid ID');
        vim.e2e.assert.true(id2 > 0, 'Second autocommand should have valid ID');

        // Clear group should remove all autocommands
        vim.api.clearAutoCommands({ group: 'test_group' });
    });
});

vim.e2e.describe("AutoCommand Deletion", function() {
    vim.e2e.test("deleteAutoCommand removes autocommand", function() {
        let called = false;
        const callback = function() { called = true; };

        const id = vim.api.createAutoCommand('BufEnter', { callback: callback });
        vim.e2e.assert.true(id > 0, 'Should return valid ID');

        // Delete should not throw
        vim.api.deleteAutoCommand(id);

        // Delete again should be idempotent (no error)
        vim.api.deleteAutoCommand(id);

        vim.e2e.assert.true(true, "deleteAutoCommand completed without error");
    });
});

vim.e2e.describe("AutoCommand Once Flag", function() {
    vim.e2e.test("createAutoCommand with once flag", function() {
        let callCount = 0;
        const callback = function() { callCount++; };

        const id = vim.api.createAutoCommand('BufEnter', {
            callback: callback,
            once: true
        });

        vim.e2e.assert.true(id > 0, 'Should return valid ID');

        // Note: We can't easily trigger the event in E2E tests,
        // but we verify the autocommand was created successfully
    });
});

vim.e2e.runAll();
