// Test setup for buffer API tests
// Creates a buffer with test content for API testing
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
// Exit insert mode
vim.e2e.keys("\x1b");
// Go to beginning of file
vim.e2e.keys("gg0");
