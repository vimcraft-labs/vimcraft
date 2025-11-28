// Test setup - create buffer with multiple lines
vim.e2e.keys("iLine 1: Hello World");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 2: Second line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 3: Third line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 4: Fourth line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 5: Fifth line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 6: Sixth line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 7: Seventh line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 8: Eighth line");
// Exit insert mode and go to top
vim.e2e.keys("\x1b");
vim.e2e.keys("gg0");
