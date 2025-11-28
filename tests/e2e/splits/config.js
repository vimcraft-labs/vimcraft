// Test setup for window splits tests
// Creates a buffer with test content for cursor testing
// Enter insert mode and type test content
vim.e2e.keys("iLine 1: Hello World");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 2: Second line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 3: Third line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 4: Fourth line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 5: Fifth line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 6: Sixth line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 7: Seventh line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 8: Eighth line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 9: Ninth line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 10: Tenth line");
// Exit insert mode
vim.e2e.keys("\x1b");
// Go to beginning of file
vim.e2e.keys("gg0");
