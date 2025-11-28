// Test setup for cursor boundary tests
// Creates buffer with test content using Enter key (char code 13)
// Enter insert mode and type test content
vim.e2e.keys("iHello World");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Second Line");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Third Line");
// Exit insert mode
vim.e2e.keys("\x1b");
// Go to beginning of file
vim.e2e.keys("gg0");
