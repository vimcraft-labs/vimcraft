// Test vim.ai.state.* API (editor state access for AI features)
vim.e2e.describe("vim.ai.state API", () => {

vim.e2e.test("vim.ai.state.buffer returns buffer content", () => {
  vim.e2e.keys("iHello World<Esc>");
  const content = vim.ai.state.buffer();
  vim.e2e.assert.equal(content, "Hello World");
});

vim.e2e.test("vim.ai.state.cursor returns cursor position", () => {
  vim.e2e.keys("iLine 1<CR>Line 2<CR>Line 3<Esc>");
  vim.e2e.keys("gg0"); // Go to start
  const cursor = vim.ai.state.cursor();
  vim.e2e.assert.equal(cursor.row, 0);
  vim.e2e.assert.equal(cursor.col, 0);

  vim.e2e.keys("j$"); // Go to end of line 2
  const cursor2 = vim.ai.state.cursor();
  vim.e2e.assert.equal(cursor2.row, 1);
});

vim.e2e.test("vim.ai.state.line returns current line", () => {
  vim.e2e.keys("iFirst Line<CR>Second Line<CR>Third Line<Esc>");
  vim.e2e.keys("gg"); // Go to first line
  vim.e2e.assert.equal(vim.ai.state.line(), "First Line");

  vim.e2e.keys("j"); // Go to second line
  vim.e2e.assert.equal(vim.ai.state.line(), "Second Line");
});

vim.e2e.test("vim.ai.state.lineCount returns correct count", () => {
  vim.e2e.keys("iLine 1<CR>Line 2<CR>Line 3<Esc>");
  vim.e2e.assert.equal(vim.ai.state.lineCount(), 3);
});

vim.e2e.test("vim.ai.state.lines returns line range", () => {
  vim.e2e.keys("iLine 0<CR>Line 1<CR>Line 2<CR>Line 3<Esc>");
  const lines = vim.ai.state.lines(1, 3);
  vim.e2e.assert.equal(lines.length, 2);
  vim.e2e.assert.equal(lines[0], "Line 1");
  vim.e2e.assert.equal(lines[1], "Line 2");
});

// vim.ai.state.selection() requires visual mode - skip for now
// as it needs more complex setup

vim.e2e.test("vim.ai namespace structure is correct", () => {
  // Verify new namespace structure
  vim.e2e.assert.equal(typeof vim.ai, "object");

  // vim.ai.state.* - Editor state access
  vim.e2e.assert.equal(typeof vim.ai.state, "object");
  vim.e2e.assert.equal(typeof vim.ai.state.buffer, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.cursor, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.line, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.lines, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.lineCount, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.filename, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.filetype, "function");
  vim.e2e.assert.equal(typeof vim.ai.state.selection, "function");

  // vim.ai.storage.* - Pattern/edge persistence
  vim.e2e.assert.equal(typeof vim.ai.storage, "object");
  vim.e2e.assert.equal(typeof vim.ai.storage.patterns, "object");
  vim.e2e.assert.equal(typeof vim.ai.storage.edges, "object");

  // vim.ai.providers.* - LLM provider abstraction
  vim.e2e.assert.equal(typeof vim.ai.providers, "object");
  vim.e2e.assert.equal(typeof vim.ai.providers.configure, "function");
  vim.e2e.assert.equal(typeof vim.ai.providers.buildRequest, "function");

  // vim.ai.utils.* - Utility functions
  vim.e2e.assert.equal(typeof vim.ai.utils, "object");
  vim.e2e.assert.equal(typeof vim.ai.utils.estimateTokens, "function");
  vim.e2e.assert.equal(typeof vim.ai.utils.getLastError, "function");

  // vim.ai.storage.conversations.* - Conversation persistence
  vim.e2e.assert.equal(typeof vim.ai.storage.conversations, "object");
  vim.e2e.assert.equal(typeof vim.ai.storage.conversations.add, "function");
  vim.e2e.assert.equal(typeof vim.ai.storage.conversations.get, "function");
});

vim.e2e.test("vim.ai.utils.getLastError returns null initially", () => {
  // No operations performed, so no error
  const err = vim.ai.utils.getLastError();
  vim.e2e.assert.equal(err, null);
});

}); // End describe

vim.e2e.runAll();
