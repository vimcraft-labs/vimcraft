// Cursor API E2E Tests
// Tests vim.cursor.* and vim.e2e.getCursor() with real editor state
vim.e2e.describe("Cursor API", function () {
    vim.e2e.test("getCursor returns object with line and col", function () {
        const pos = vim.e2e.getCursor();
        vim.e2e.assert.true(typeof pos === 'object', 'getCursor should return an object');
        vim.e2e.assert.true(typeof pos.line === 'number', 'position.line should be a number');
        vim.e2e.assert.true(typeof pos.col === 'number', 'position.col should be a number');
    });
    vim.e2e.test("cursor position values are non-negative", function () {
        const pos = vim.e2e.getCursor();
        vim.e2e.assert.true(pos.line >= 0, 'position.line should be non-negative');
        vim.e2e.assert.true(pos.col >= 0, 'position.col should be non-negative');
    });
    vim.e2e.test("getCursor is consistent (idempotent)", function () {
        const pos1 = vim.e2e.getCursor();
        const pos2 = vim.e2e.getCursor();
        vim.e2e.assert.equal(pos1.line, pos2.line, 'Consecutive getCursor calls should return same line');
        vim.e2e.assert.equal(pos1.col, pos2.col, 'Consecutive getCursor calls should return same col');
    });
});
vim.e2e.describe("Cursor Movement via Keys", function () {
    vim.e2e.test("j key moves cursor down", function () {
        const before = vim.e2e.getCursor();
        vim.e2e.keys("j");
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.line, before.line + 1, "j should move cursor down");
    });
    vim.e2e.test("k key moves cursor up", function () {
        vim.e2e.keys("j"); // Move down first to have room
        const before = vim.e2e.getCursor();
        vim.e2e.keys("k");
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.line, before.line - 1, "k should move cursor up");
    });
    vim.e2e.test("l key moves cursor right", function () {
        const before = vim.e2e.getCursor();
        vim.e2e.keys("l");
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col + 1, "l should move cursor right");
    });
    vim.e2e.test("h key moves cursor left", function () {
        vim.e2e.keys("ll"); // Move right first to have room
        const before = vim.e2e.getCursor();
        vim.e2e.keys("h");
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col - 1, "h should move cursor left");
    });
});
vim.e2e.runAll();
