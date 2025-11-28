// Rendering Tests - Configuration
// Sets up buffer content for testing terminal escape codes
// Create a multi-line buffer for rendering tests
const testContent = [
    "Line 0: Test content for PTY rendering",
    "Line 1: Cursor movement validation",
    "Line 2: ANSI escape code testing",
    "Line 3: Synchronized updates check",
    "Line 4: Flickering detection test",
    "Line 5: Color attribute tracking",
    "Line 6: Position code optimization",
    "Line 7: Frame rate throttling",
    "Line 8: Event batching verification",
    "Line 9: Performance optimization",
    "Line 10: Final line for scrolling",
].join("\n");
// Set buffer content via inserting (vim.e2e.keys for insert)
vim.e2e.keys("i" + testContent + "\x1b");
vim.e2e.keys("gg0"); // Go to start
// Enable line numbers for gutter rendering tests
vim.opt.number = true;
