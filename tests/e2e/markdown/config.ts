// Markdown Syntax Highlighting Test - Configuration
// Sets up buffer content for testing markdown tree-sitter highlighting

// Use Enter key (char code 13) for newlines, same as cursor-boundary test
const ENTER = String.fromCharCode(13);

// Enter insert mode and type markdown content line by line
vim.e2e.keys("i# Hello World");
vim.e2e.keys(ENTER);
vim.e2e.keys(ENTER); // empty line
vim.e2e.keys("This is **bold** and *italic* text.");
vim.e2e.keys(ENTER);
vim.e2e.keys(ENTER); // empty line
vim.e2e.keys("## Section Two");
vim.e2e.keys(ENTER);
vim.e2e.keys(ENTER); // empty line
vim.e2e.keys("- Item 1");
vim.e2e.keys(ENTER);
vim.e2e.keys("- Item 2");
// Exit insert mode
vim.e2e.keys("\x1b");
// Go to start
vim.e2e.keys("gg0");

// Set filetype to markdown to trigger tree-sitter syntax highlighting
vim.bo.filetype = "markdown";
