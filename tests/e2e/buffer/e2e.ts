// Buffer API E2E Tests
// Tests vim.buffer.* API with real editor state

vim.e2e.describe("Buffer API Existence", function() {
    vim.e2e.test("getLength exists and returns number", function() {
        const len = vim.buffer.getLength();
        vim.e2e.assert.true(typeof len === 'number', 'getLength should return a number');
        vim.e2e.assert.true(len >= 0, 'getLength should return non-negative');
    });

    vim.e2e.test("getLineCount exists and returns number", function() {
        const count = vim.buffer.getLineCount();
        vim.e2e.assert.true(typeof count === 'number', 'getLineCount should return a number');
        vim.e2e.assert.true(count >= 0, 'getLineCount should return non-negative');
    });

    vim.e2e.test("getChangedTick exists and returns number", function() {
        const tick = vim.buffer.getChangedTick();
        vim.e2e.assert.true(typeof tick === 'number', 'getChangedTick should return a number');
        vim.e2e.assert.true(tick >= 0, 'getChangedTick should return non-negative');
    });
});

vim.e2e.describe("Buffer Content Access", function() {
    vim.e2e.test("getContent returns ArrayBuffer", function() {
        const content = vim.buffer.getContent();
        vim.e2e.assert.true(content instanceof ArrayBuffer, 'getContent should return ArrayBuffer');
    });

    vim.e2e.test("getLineContent returns ArrayBuffer for valid line", function() {
        const lineCount = vim.buffer.getLineCount();
        if (lineCount > 0) {
            const line = vim.buffer.getLineContent(0);
            vim.e2e.assert.true(line instanceof ArrayBuffer, 'getLineContent should return ArrayBuffer');
        }
    });
});

vim.e2e.runAll();
