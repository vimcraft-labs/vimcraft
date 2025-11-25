// Setup buffer content for PTY debug test
vim.e2e.keys("iLine 1: Hello World");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 2: Second line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 3: Third line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 4: Fourth line");
vim.e2e.keys(String.fromCharCode(13));
vim.e2e.keys("Line 5: Fifth line");
vim.e2e.keys("\x1b");
vim.e2e.keys("gg0");
