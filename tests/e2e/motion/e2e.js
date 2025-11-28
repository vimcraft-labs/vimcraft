// Motion API E2E Tests
// Tests vim.motion.* API with real editor state
vim.e2e.describe("Motion API Existence", function () {
    vim.e2e.test("basic motions are functions", function () {
        vim.e2e.assert.true(typeof vim.motion.left === 'function', 'vim.motion.left should be a function');
        vim.e2e.assert.true(typeof vim.motion.right === 'function', 'vim.motion.right should be a function');
        vim.e2e.assert.true(typeof vim.motion.up === 'function', 'vim.motion.up should be a function');
        vim.e2e.assert.true(typeof vim.motion.down === 'function', 'vim.motion.down should be a function');
    });
    vim.e2e.test("line motions are functions", function () {
        vim.e2e.assert.true(typeof vim.motion.lineStart === 'function', 'vim.motion.lineStart should be a function');
        vim.e2e.assert.true(typeof vim.motion.lineEnd === 'function', 'vim.motion.lineEnd should be a function');
    });
    vim.e2e.test("word motions are functions", function () {
        vim.e2e.assert.true(typeof vim.motion.wordForward === 'function', 'vim.motion.wordForward should be a function');
        vim.e2e.assert.true(typeof vim.motion.wordBackward === 'function', 'vim.motion.wordBackward should be a function');
        vim.e2e.assert.true(typeof vim.motion.wordEnd === 'function', 'vim.motion.wordEnd should be a function');
    });
    vim.e2e.test("file motions are functions", function () {
        vim.e2e.assert.true(typeof vim.motion.fileStart === 'function', 'vim.motion.fileStart should be a function');
        vim.e2e.assert.true(typeof vim.motion.fileEnd === 'function', 'vim.motion.fileEnd should be a function');
    });
});
vim.e2e.describe("Motion Behavior", function () {
    vim.e2e.test("right() moves cursor right by 1", function () {
        vim.e2e.checkpoint("before motion");
        const before = vim.e2e.getCursor();
        vim.motion.right();
        vim.e2e.checkpoint("after motion");
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col + 1, "cursor should move right by 1");
    });
    vim.e2e.test("left() moves cursor left by 1", function () {
        // First move right to have room
        vim.motion.right();
        vim.motion.right();
        const before = vim.e2e.getCursor();
        vim.motion.left();
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col - 1, "cursor should move left by 1");
    });
    vim.e2e.test("down() moves cursor down by 1", function () {
        const before = vim.e2e.getCursor();
        vim.motion.down();
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.line, before.line + 1, "cursor should move down by 1");
    });
    vim.e2e.test("up() moves cursor up by 1", function () {
        // First move down to have room
        vim.motion.down();
        const before = vim.e2e.getCursor();
        vim.motion.up();
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.line, before.line - 1, "cursor should move up by 1");
    });
});
vim.e2e.runAll();
