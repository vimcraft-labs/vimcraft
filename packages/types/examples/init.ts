/// <reference types="@vimcraft/types" />

// Vimcraft Configuration Example (TypeScript)
// This file demonstrates the typed Vimcraft API

console.log('🚀 Loading Vimcraft config...');

// ============================================================================
// Highlight Groups
// ============================================================================

// Cursor line highlighting
vim.highlight('CursorLine', {
  bg: '#2b2b2b',
});

// Line numbers
vim.highlight('LineNr', {
  fg: '#6c6c6c',
});

// Comments
vim.highlight('Comment', {
  fg: '#5c6370',
  italic: true,
});

// Strings
vim.highlight('String', {
  fg: '#98c379',
});

// Keywords
vim.highlight('Keyword', {
  fg: '#c678dd',
  bold: true,
});

// ============================================================================
// Editor Options
// ============================================================================

vim.opt.cursorline = true;

// ============================================================================
// Timers Example
// ============================================================================

// Show a message every 5 seconds
setInterval(() => {
  console.log('⏰ Auto-save would happen here...');
}, 5000);

// Delayed initialization
setTimeout(() => {
  console.log('✅ Config fully loaded!');
}, 100);

console.log('📝 Config loaded successfully!');
