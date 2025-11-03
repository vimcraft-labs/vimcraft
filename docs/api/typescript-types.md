# OpenVim TypeScript Types Reference

Version: 0.2.0

## Overview

OpenVim now has comprehensive TypeScript type definitions with full autocomplete and type checking support.

## Key Features

- ✅ **camelCase naming** - All option names use camelCase (e.g., `cursorLine`, `relativeNumber`)
- ✅ **60+ editor options** - Comprehensive vim.opt interface
- ✅ **80+ highlight groups** - Standard Vim/Neovim highlight groups with autocomplete
- ✅ **Extended highlight options** - Support for undercurl, strikethrough, blend, etc.
- ✅ **Future APIs** - Types for keymap, cmd, variables (g, b, w, t, v, env)

## Usage

### Install Types

```bash
npm install --save-dev @openvim/types
```

### Configure TypeScript

```typescript
/// <reference types="@openvim/types" />

// Your config here with full type support!
```

## API Reference

### vim.highlight()

Define syntax highlighting with full type checking:

```typescript
vim.highlight('CursorLine', { bg: '#2b2b2b' });
vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
vim.highlight('Error', { fg: '#ff0000', undercurl: true, sp: '#ff0000' });
```

**Supported Options:**
- `bg`, `fg`, `sp` - Colors (hex strings)
- `blend` - Transparency (0-100)
- `bold`, `italic`, `underline`, `strikethrough`
- `undercurl`, `underdouble`, `underdotted`, `underdashed`
- `reverse`, `standout`

**Autocomplete for 80+ Highlight Groups:**
- Editor UI: `Normal`, `CursorLine`, `LineNr`, `SignColumn`, `StatusLine`...
- Syntax: `Comment`, `String`, `Function`, `Keyword`, `Type`...
- Diagnostics: `DiagnosticError`, `DiagnosticWarn`, `DiagnosticInfo`...
- Search: `Search`, `IncSearch`, `CurSearch`
- Diff: `DiffAdd`, `DiffChange`, `DiffDelete`
- And many more...

### vim.opt (Editor Options)

All option names use **camelCase**:

```typescript
// Display options
vim.opt.number = true;
vim.opt.relativeNumber = true;
vim.opt.cursorLine = true;
vim.opt.cursorColumn = true;
vim.opt.signColumn = 'yes';
vim.opt.colorColumn = '80,120';
vim.opt.scrollOff = 8;
vim.opt.wrap = false;
vim.opt.lineBreak = true;

// Indentation
vim.opt.tabStop = 2;
vim.opt.shiftWidth = 2;
vim.opt.expandTab = true;
vim.opt.smartIndent = true;
vim.opt.autoIndent = true;

// Search
vim.opt.ignoreCase = true;
vim.opt.smartCase = true;
vim.opt.hlSearch = true;
vim.opt.incSearch = true;

// Editing
vim.opt.mouse = 'a';
vim.opt.timeoutLen = 500;
vim.opt.backspace = 'indent,eol,start';

// Windows
vim.opt.splitBelow = true;
vim.opt.splitRight = true;

// Files
vim.opt.autoRead = true;
vim.opt.autoWrite = true;
vim.opt.fileEncoding = 'utf-8';

// Completion
vim.opt.wildMenu = true;
vim.opt.wildMode = 'longest:full,full';
vim.opt.completeOpt = 'menu,menuone,noselect';

// Performance
vim.opt.lazyRedraw = true;
vim.opt.updateTime = 250;
```

### Future APIs (Not Yet Implemented)

These are typed but not yet implemented in OpenVim:

```typescript
// Key mappings
vim.keymap('n', '<leader>w', ':w<CR>', { silent: true, desc: 'Save file' });

// Commands
vim.cmd('set number');
vim.ex('write');

// Variables
vim.g.mapleader = ' ';
vim.b.some_buffer_var = true;
vim.w.some_window_var = 'value';

// Clear highlights
vim.clearHighlight('Comment');
```

## Naming Convention

**All option names use camelCase:**

| Vim Name | OpenVim TypeScript | Status |
|----------|-------------------|--------|
| `cursorline` | `cursorLine` | ✅ Implemented |
| `relativenumber` | `relativeNumber` | 📋 Typed |
| `tabstop` | `tabStop` | 📋 Typed |
| `shiftwidth` | `shiftWidth` | 📋 Typed |
| `expandtab` | `expandTab` | 📋 Typed |
| `smartindent` | `smartIndent` | 📋 Typed |
| `hlsearch` | `hlSearch` | 📋 Typed |
| `incsearch` | `incSearch` | 📋 Typed |
| `ignorecase` | `ignoreCase` | 📋 Typed |
| `smartcase` | `smartCase` | 📋 Typed |

## Example Configuration

```typescript
/// <reference types="@openvim/types" />

const colors = {
  bg: '#1e1e1e',
  bgAlt: '#252526',
  bgHighlight: '#2b2b2b',
  fg: '#d4d4d4',
  gray: '#5c6370',
  green: '#98c379',
  blue: '#61afef',
  purple: '#c678dd',
};

// Highlights with autocomplete
const highlights = {
  CursorLine: { bg: colors.bgHighlight },
  LineNr: { fg: colors.gray },
  Comment: { fg: colors.gray, italic: true },
  String: { fg: colors.green },
  Function: { fg: colors.blue },
  Keyword: { fg: colors.purple, bold: true },
};

for (const [name, opts] of Object.entries(highlights)) {
  vim.highlight(name, opts);
}

// Options with camelCase
vim.opt.cursorLine = true;
vim.opt.number = true;
vim.opt.relativeNumber = true;

console.log('✅ Config loaded!');
```

## Building Your Config

```bash
# Edit init.ts
vim init.ts

# Build to ~/.config/openvim/init.js
npm run build:config

# Watch mode (auto-rebuild on changes)
npm run watch:config
```

## IDE Support

With these types, your IDE provides:

- ✅ **Autocomplete** for all vim APIs
- ✅ **Type checking** catches errors before runtime
- ✅ **JSDoc tooltips** with descriptions
- ✅ **Go to definition** for types
- ✅ **Rename refactoring** works correctly

## Migration Guide

If you have existing configs with lowercase names:

**Old (still works):**
```javascript
vim.opt.cursorline = true; // Still supported for backwards compatibility
```

**New (recommended):**
```typescript
vim.opt.cursorLine = true; // TypeScript types use camelCase
```

The Zig code supports both naming conventions for backwards compatibility.
