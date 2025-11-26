// E2E test for vim.api.createUserCmd
// Tests custom Ex commands created via JavaScript

let helloExecuted = false;
let helloArgs = '';
let helloBang = false;

vim.api.createUserCmd('Hello', ({ args, bang }) => {
    helloExecuted = true;
    helloArgs = args;
    helloBang = bang;
    console.log('Hello command executed with args:', args);
}, { desc: 'A test hello command' });

// Test command that captures args - proves callback actually runs with correct data
let lastCmdName = '';
let lastCmdArgs = '';
let lastCmdBang = false;
vim.api.createUserCmd('Capture', ({ name, args, bang }) => {
    lastCmdName = name;
    lastCmdArgs = args;
    lastCmdBang = bang;
    console.log('Capture executed:', name, args, bang);
}, { desc: 'Test command that captures all args' });

vim.e2e.describe('vim.api.createUserCmd', function() {
    vim.e2e.test('user command is registered and executed', function() {
        vim.e2e.assert.equal(helloExecuted, false, 'Should not be executed yet');
        
        // Execute the user command
        vim.e2e.keys(':Hello<CR>');
        
        vim.e2e.assert.equal(helloExecuted, true, 'Hello command should be executed');
    });

    vim.e2e.test('user command receives args', function() {
        helloExecuted = false;
        helloArgs = '';
        
        vim.e2e.keys(':Hello world test<CR>');
        
        vim.e2e.assert.equal(helloExecuted, true, 'Command should be executed');
        vim.e2e.assert.equal(helloArgs, 'world test', 'Args should be "world test"');
    });

    vim.e2e.test('user command receives bang flag', function() {
        helloExecuted = false;
        helloBang = false;

        vim.e2e.keys(':Hello!<CR>');

        vim.e2e.assert.equal(helloExecuted, true, 'Command should be executed');
        vim.e2e.assert.equal(helloBang, true, 'Bang should be true');
    });

    vim.e2e.test('user command callback receives name property', function() {
        lastCmdName = '';
        lastCmdArgs = '';
        lastCmdBang = false;

        // Execute Capture command with args and bang
        vim.e2e.keys(':Capture! foo bar<CR>');

        // Verify all properties were passed correctly
        vim.e2e.assert.equal(lastCmdName, 'Capture', 'Name should be "Capture"');
        vim.e2e.assert.equal(lastCmdArgs, 'foo bar', 'Args should be "foo bar"');
        vim.e2e.assert.equal(lastCmdBang, true, 'Bang should be true');
    });
});

vim.e2e.runAll();
