// @ts-check
/// <reference types="@vimcraft/types" />

// Vimcraft Configuration Example (JavaScript with type checking)
// Add the @ts-check comment above to enable type checking in VS Code

console.log('Loading Vimcraft config...');

// Highlight groups - you get autocomplete for 'bg', 'fg', etc.
vim.highlight('CursorLine', { bg: '#2b2b2b' });
vim.highlight('LineNr', { fg: '#6c6c6c' });
vim.highlight('Comment', { fg: '#5c6370', italic: true });

// Editor options - TypeScript knows 'cursorline' is boolean
vim.opt.cursorline = true;

// Timers with proper types
const intervalId = setInterval(() => {
  console.log('Interval tick');
}, 2000);

// TypeScript knows intervalId is a number
// @ts-expect-error - This would be caught by TypeScript
// clearInterval('not a number');

console.log('Config loaded!');
