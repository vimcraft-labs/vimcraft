# vim.api Reference

Complete reference for vim.api.* functions (Neovim-compatible API).

---

## Overview

The `vim.api` namespace contains all low-level nvim_* functions. These provide full control over the editor.

**Status**: Phase 3-4 implementation ongoing

See [Quick Reference](./quick-reference.md) for tier-based priority.

---

## Buffer Functions

### nvim_get_current_buf()

Get the current buffer handle.

**Returns**: Buffer (number)

**Example**:
```typescript
const buf = vim.api.nvim_get_current_buf();
console.log(`Current buffer: ${buf}`);
```

### nvim_buf_get_lines(buffer, start, end, strict)

Get buffer lines.

**Parameters**:
- `buffer` (Buffer): Buffer handle (0 = current)
- `start` (number): Start line (0-indexed)
- `end` (number): End line (exclusive, -1 = end of buffer)
- `strict` (boolean): Strict indexing

**Returns**: string[]

**Example**:
```typescript
const lines = vim.api.nvim_buf_get_lines(0, 0, -1, false);
console.log(`Total lines: ${lines.length}`);
```

---

## Window Functions

### nvim_get_current_win()

Get the current window handle.

**Returns**: Window (number)

### nvim_win_get_cursor(window)

Get window cursor position.

**Returns**: [number, number] - [row (1-indexed), col (0-indexed)]

---

## Highlight Functions

### nvim_set_hl(namespace, name, opts)

Set a highlight group.

**Parameters**:
- `namespace` (Namespace): Namespace ID (0 = global)
- `name` (string): Highlight group name
- `opts` (HighlightOpts): Styling options

**Example**:
```typescript
vim.api.nvim_set_hl(0, 'Comment', {
  fg: '#6c6c6c',
  italic: true
});
```

---

## Autocommand Functions

**Status**: Phase 4 (planned)

### nvim_create_autocmd(event, opts)

Create an autocommand.

**Example** (Phase 4):
```typescript
vim.api.nvim_create_autocmd('BufRead', {
  pattern: '*.js',
  callback: (args) => {
    console.log(`Loaded ${args.file}`);
  }
});
```

---

For complete function list, see generated types in `packages/types/src/index.d.ts`.
