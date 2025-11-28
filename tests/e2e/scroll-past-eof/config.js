// Config for scroll-past-eof test
// Create a small file (5 lines) so we can test scroll past EOF behavior
// Enter insert mode and type test content
vim.e2e.keys("iLine 1");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 2");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 3");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 4");
vim.e2e.keys(String.fromCharCode(13)); // Enter key
vim.e2e.keys("Line 5");
// Exit insert mode
vim.e2e.keys("\x1b");
// Go to beginning of file
vim.e2e.keys("gg0");
