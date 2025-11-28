// Cursor Boundary E2E Tests
// Tests Vim-style cursor boundary behavior:
// - Normal mode: cursor stops ON last character
// - Insert mode: cursor can go AFTER last character
// - ESC from insert mode clamps cursor back to last char
// Helper to reset cursor to start (ensures we're in NORMAL mode first)
function resetCursor() {
    // Make sure we're in normal mode first
    vim.e2e.keys("\x1b");
    vim.e2e.keys("gg0");
}
vim.e2e.describe("Normal Mode Cursor Boundary", function () {
    vim.e2e.test("l key stops ON last character (not after)", function () {
        resetCursor();
        // Move to end of line with $
        vim.e2e.keys("$");
        const endPos = vim.e2e.getCursor();
        vim.e2e.checkpoint("at end with $");
        // Try to move right - should NOT move (already at boundary)
        vim.e2e.keys("l");
        const afterL = vim.e2e.getCursor();
        vim.e2e.assert.equal(afterL.col, endPos.col, "l should not move cursor past last character in normal mode");
    });
    vim.e2e.test("multiple l presses stop at last character", function () {
        resetCursor();
        // Press l many times (should stop at last char)
        vim.e2e.keys("llllllllllllllllllllllllll"); // 26 l's
        const pos1 = vim.e2e.getCursor();
        // Press l again - should not move
        vim.e2e.keys("l");
        const pos2 = vim.e2e.getCursor();
        vim.e2e.assert.equal(pos1.col, pos2.col, "cursor should stop at last character");
    });
    vim.e2e.test("$ positions cursor ON last character", function () {
        resetCursor();
        vim.e2e.keys("$"); // Go to end
        const pos = vim.e2e.getCursor();
        // "Hello World" has 11 chars (0-10), last char 'd' is at col 10
        vim.e2e.assert.equal(pos.col, 10, "$ should position cursor ON last character");
    });
});
vim.e2e.describe("Insert Mode Cursor Boundary", function () {
    vim.e2e.test("A positions cursor AFTER last character", function () {
        resetCursor();
        vim.e2e.keys("A"); // Append at end (enters insert mode, cursor after last char)
        vim.e2e.checkpoint("after A");
        const afterA = vim.e2e.getCursor();
        const mode = vim.e2e.getMode();
        vim.e2e.assert.equal(mode, "INSERT", "should be in INSERT mode after A");
        // "Hello World" has 11 chars, cursor should be at col 11 (AFTER 'd')
        vim.e2e.assert.equal(afterA.col, 11, "A should position cursor AFTER last character");
        // Exit insert mode
        vim.e2e.keys("\x1b");
    });
    vim.e2e.test("ESC from insert mode clamps cursor back to last char", function () {
        resetCursor();
        vim.e2e.keys("A"); // Append (cursor after last char)
        const insertPos = vim.e2e.getCursor();
        vim.e2e.checkpoint("insert mode position");
        vim.e2e.keys("\x1b"); // Exit insert mode
        const normalPos = vim.e2e.getCursor();
        vim.e2e.checkpoint("normal mode position after ESC");
        // In normal mode, cursor should be ON last char (col 10), not after (col 11)
        vim.e2e.assert.equal(normalPos.col, 10, "ESC should clamp cursor to last visible character");
    });
    vim.e2e.test("'a' at end of line positions cursor after last char", function () {
        resetCursor();
        vim.e2e.keys("$"); // Go to last char (col 10)
        vim.e2e.keys("a"); // Insert after cursor
        const pos = vim.e2e.getCursor();
        vim.e2e.checkpoint("after 'a' at end");
        // 'a' should put cursor after current char, so col 11
        vim.e2e.assert.equal(pos.col, 11, "a at end should position cursor after last char");
        vim.e2e.keys("\x1b");
    });
});
vim.e2e.describe("Arrow Keys in Insert Mode", function () {
    vim.e2e.test("right arrow moves cursor past last character", function () {
        resetCursor();
        // Go to last char in normal mode, then enter insert mode
        vim.e2e.keys("$"); // At col 10 (on 'd')
        vim.e2e.keys("i"); // Enter insert mode at col 10
        const beforeArrow = vim.e2e.getCursor();
        vim.e2e.checkpoint("insert mode at last char");
        vim.e2e.assert.equal(beforeArrow.col, 10, "should be at col 10 before arrow");
        // Press right arrow (ESC [ C)
        vim.e2e.keys("\x1b[C");
        const afterArrow = vim.e2e.getCursor();
        vim.e2e.checkpoint("after right arrow");
        // In insert mode, right arrow should move cursor AFTER last char (col 11)
        vim.e2e.assert.equal(afterArrow.col, 11, "right arrow should move cursor past last char in insert mode");
        vim.e2e.assert.equal(vim.e2e.getMode(), "INSERT", "should still be in INSERT mode");
        vim.e2e.keys("\x1b");
    });
    vim.e2e.test("multiple right arrows stop at end of line", function () {
        resetCursor();
        vim.e2e.keys("i"); // Enter insert mode at col 0
        // Press right arrow many times (more than line length)
        for (let i = 0; i < 15; i++) {
            vim.e2e.keys("\x1b[C");
        }
        const pos = vim.e2e.getCursor();
        vim.e2e.checkpoint("after many right arrows");
        // Should stop at col 11 (after last char of "Hello World")
        vim.e2e.assert.equal(pos.col, 11, "cursor should stop at end of line (col 11)");
        vim.e2e.keys("\x1b");
    });
    vim.e2e.test("left arrow works in insert mode", function () {
        resetCursor();
        vim.e2e.keys("A"); // Append at end (col 11)
        const before = vim.e2e.getCursor();
        vim.e2e.assert.equal(before.col, 11, "should start at col 11");
        // Press left arrow (ESC [ D)
        vim.e2e.keys("\x1b[D");
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, 10, "left arrow should move cursor left");
        vim.e2e.keys("\x1b");
    });
    vim.e2e.test("up/down arrows work in insert mode", function () {
        resetCursor();
        vim.e2e.keys("i"); // Enter insert mode on line 0
        const before = vim.e2e.getCursor();
        vim.e2e.assert.equal(before.line, 0, "should start on line 0");
        // Press down arrow (ESC [ B)
        vim.e2e.keys("\x1b[B");
        const afterDown = vim.e2e.getCursor();
        vim.e2e.assert.equal(afterDown.line, 1, "down arrow should move to line 1");
        // Press up arrow (ESC [ A)
        vim.e2e.keys("\x1b[A");
        const afterUp = vim.e2e.getCursor();
        vim.e2e.assert.equal(afterUp.line, 0, "up arrow should move back to line 0");
        vim.e2e.keys("\x1b");
    });
    vim.e2e.test("ESC after arrow movement clamps cursor correctly", function () {
        resetCursor();
        // Enter insert mode and move to end with arrow keys
        vim.e2e.keys("$"); // Go to last char
        vim.e2e.keys("i"); // Insert mode at col 10
        vim.e2e.keys("\x1b[C"); // Right arrow to col 11 (after last char)
        const insertPos = vim.e2e.getCursor();
        vim.e2e.assert.equal(insertPos.col, 11, "should be at col 11 in insert mode");
        // Exit insert mode
        vim.e2e.keys("\x1b");
        const normalPos = vim.e2e.getCursor();
        vim.e2e.checkpoint("after ESC");
        // Should clamp back to col 10 (ON last char) in normal mode
        vim.e2e.assert.equal(normalPos.col, 10, "ESC should clamp cursor to last char");
        vim.e2e.assert.equal(vim.e2e.getMode(), "NORMAL", "should be in NORMAL mode");
    });
});
vim.e2e.describe("Insert Mode a vs A Behavior", function () {
    vim.e2e.test("a enters insert mode after cursor", function () {
        resetCursor();
        const before = vim.e2e.getCursor();
        vim.e2e.keys("a"); // Insert after cursor
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(vim.e2e.getMode(), "INSERT", "should be in INSERT mode after a");
        vim.e2e.assert.equal(after.col, before.col + 1, "a should move cursor right by 1");
        vim.e2e.keys("\x1b");
    });
    vim.e2e.test("A enters insert mode at end of line", function () {
        resetCursor();
        vim.e2e.keys("A"); // Append at end
        const pos = vim.e2e.getCursor();
        vim.e2e.assert.equal(vim.e2e.getMode(), "INSERT", "should be in INSERT mode after A");
        vim.e2e.assert.equal(pos.col, 11, "A should move cursor to after last char");
        vim.e2e.keys("\x1b");
    });
});
vim.e2e.describe("o and O Commands", function () {
    vim.e2e.test("o opens new line below and enters insert mode", function () {
        resetCursor();
        const before = vim.e2e.getCursor();
        vim.e2e.keys("o"); // Open line below
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(vim.e2e.getMode(), "INSERT", "should be in INSERT mode after o");
        vim.e2e.assert.equal(after.line, before.line + 1, "o should create new line below");
        vim.e2e.assert.equal(after.col, 0, "o should position cursor at start of new line");
        vim.e2e.keys("\x1b");
        vim.e2e.keys("u"); // Undo to restore buffer
    });
    vim.e2e.test("O opens new line above and enters insert mode", function () {
        resetCursor();
        vim.e2e.keys("j"); // Move down first (to have room above)
        const before = vim.e2e.getCursor();
        vim.e2e.keys("O"); // Open line above
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(vim.e2e.getMode(), "INSERT", "should be in INSERT mode after O");
        // O inserts above, cursor stays on "new" line which is at same row number
        vim.e2e.assert.equal(after.line, before.line, "O cursor should be on inserted line");
        vim.e2e.assert.equal(after.col, 0, "O should position cursor at start of new line");
        vim.e2e.keys("\x1b");
        vim.e2e.keys("u"); // Undo to restore buffer
    });
});
vim.e2e.runAll();
