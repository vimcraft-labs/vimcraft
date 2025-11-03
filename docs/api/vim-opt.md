# vim.opt Reference

Editor options interface (vim.opt.*).

---

## Overview

The `vim.opt` interface provides an ergonomic way to set editor options, similar to Neovim's vim.opt.

**Current Status**: Basic implementation (Phase 1+2), full implementation in Phase 4

---

## Display Options

### number

Show line numbers.

**Type**: boolean
**Default**: false

```typescript
vim.opt.number = true;
```

### relativeNumber

Show relative line numbers.

**Type**: boolean
**Default**: false

```typescript
vim.opt.relativeNumber = true;
```

### cursorLine

Highlight the screen line of the cursor.

**Type**: boolean
**Default**: false
**Status**: ✅ Implemented

```typescript
vim.opt.cursorLine = true;
```

---

## Indentation Options

### tabStop

Number of spaces a <Tab> counts for.

**Type**: number
**Default**: 8

```typescript
vim.opt.tabStop = 4;
```

### expandTab

Use spaces instead of tabs.

**Type**: boolean
**Default**: false

```typescript
vim.opt.expandTab = true;
```

---

For complete options list, see [TypeScript Types](./typescript-types.md).
