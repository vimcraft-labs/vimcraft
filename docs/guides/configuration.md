# Configuration Guide

Learn how to configure OpenVim with init.js and TypeScript.

---

## Overview

OpenVim uses JavaScript for configuration, similar to Neovim's Lua. Your config file is located at:

```
~/.config/openvim/init.js
```

With TypeScript, you can use:

```
~/.config/openvim/init.ts
```

---

## Basic Configuration

### Setting Options

```javascript
// ~/.config/openvim/init.js

// Display options
vim.opt.number = true;
vim.opt.relativeNumber = true;
vim.opt.cursorLine = true;

// Indentation
vim.opt.tabStop = 4;
vim.opt.shiftWidth = 4;
vim.opt.expandTab = true;
```

See [vim.opt Reference](../api/vim-opt.md) for all options.

### Customizing Highlights

```javascript
const colors = {
  bg: '#1e1e1e',
  fg: '#d4d4d4',
  blue: '#61afef',
  green: '#98c379',
};

vim.highlight('CursorLine', { bg: colors.bg });
vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
vim.highlight('Function', { fg: colors.blue, bold: true });
vim.highlight('String', { fg: colors.green });
```

### Using Variables

```javascript
// Global variables (g:)
vim.g.mapleader = ' ';
vim.g.my_custom_var = 'value';

// Buffer-local (b:)
vim.b.filetype = 'javascript';
```

---

## Hot Reload

OpenVim automatically reloads config when you save the file!

```javascript
// Edit ~/.config/openvim/init.js
// Save the file
// Config reloads automatically - no restart needed!

console.log('Config reloaded!');
```

---

## Advanced Configuration

### Organizing Your Config

```javascript
// ~/.config/openvim/init.js

// Colors
const colors = require('./colors.js');

// Options
require('./options.js');

// Highlights
require('./highlights.js');

console.log('✅ OpenVim configured!');
```

### Using TypeScript (Recommended)

See [TypeScript Setup Guide](./typescript-setup.md)

---

## Examples

See [init.ts](../../init.ts) in the repository for a complete example.

---

**Status**: Basic config works, advanced features coming in Phase 4
