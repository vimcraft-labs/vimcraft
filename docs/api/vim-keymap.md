# vim.keymap Reference

Key mapping system (vim.keymap.*).

---

## Overview

The `vim.keymap` interface provides an ergonomic way to create key mappings.

**Status**: Phase 4 (planned)

---

## vim.keymap.set()

Create a key mapping.

**Signature**:
```typescript
vim.keymap.set(
  mode: MapMode | MapMode[],
  lhs: string,
  rhs: string | (() => void),
  opts?: KeymapOpts
): void
```

**Example** (Phase 4):
```typescript
vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
vim.keymap.set('i', 'jk', '<Esc>', { noremap: true });
vim.keymap.set('n', '<leader>d', () => {
  console.log('Custom delete action');
});
```

---

## vim.keymap.del()

Delete a key mapping.

**Example** (Phase 4):
```typescript
vim.keymap.del('n', '<leader>w');
```

---

See [Quick Reference](./quick-reference.md) for complete details.
