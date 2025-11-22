# API Documentation

Complete reference for Vimcraft's configuration and plugin API.

---

## 📖 Overview

Vimcraft provides a **Neovim-compatible API** for configuration and plugins:

- **vim.api.\*** - Core API functions (150+ nvim_* functions)
- **vim.opt.\*** - Editor options (70+ options)
- **vim.keymap.\*** - Key mapping system
- **vim.diagnostic.\*** - Diagnostic system
- **vim.fn.\*** - Vimscript function bridge
- **vim.g/b/w/t/v/env** - Variable scopes

All APIs are fully typed with TypeScript for excellent IDE support.

---

## 📚 Documents in This Category

### [Quick Reference](./quick-reference.md) ⭐ START HERE
**Purpose**: Fast lookup while coding (370 lines)
**Read if**: You're writing config or implementing features
**Key topics**:
- Essential APIs (Tier 1-3 priority)
- API naming conventions
- Buffer/Window handle system
- Option type handling
- Event system
- Type conversion rules
- Error handling patterns

### [vim.api Reference](./vim-api.md)
**Purpose**: Complete vim.api.* function reference
**Read if**: You need low-level API control
**Key topics**:
- Buffer functions (nvim_buf_*)
- Window functions (nvim_win_*)
- Option functions (nvim_*_option)
- Variable functions (nvim_*_var)
- Keymap functions (nvim_*_keymap)
- Highlight functions (nvim_set_hl)
- Autocommand functions (nvim_create_autocmd)
- User command functions
- Command execution
- Namespace management

### [vim.opt Reference](./vim-opt.md)
**Purpose**: Editor options documentation
**Read if**: You're configuring editor behavior
**Key topics**:
- Display options (number, cursorLine, etc.)
- Indentation options (tabStop, shiftWidth, etc.)
- Search options (ignoreCase, hlSearch, etc.)
- Window options (splitBelow, splitRight, etc.)
- Performance options (lazyRedraw, updateTime, etc.)
- All 70+ options with examples

### [vim.keymap Reference](./vim-keymap.md)
**Purpose**: Key mapping system documentation
**Read if**: You're creating custom key mappings
**Key topics**:
- vim.keymap.set() - Create mappings
- vim.keymap.del() - Delete mappings
- Mapping modes (n, i, v, x, c, t, etc.)
- Mapping options (noremap, silent, buffer, etc.)
- Callback functions
- Examples for common use cases

### [vim.filetype Reference](./vim-filetype.md) ✨ NEW
**Purpose**: Filetype detection API documentation
**Read if**: You need to detect file types for syntax highlighting or LSP
**Key topics**:
- vim.filetype.match() - Detect filetype from filename or buffer
- Four-tier detection system (extension → filename → glob → shebang)
- 1,437+ compile-time Neovim mappings
- Neovim compatibility
- Performance characteristics
- Coverage for 100+ languages

### [TypeScript Types](./typescript-types.md)
**Purpose**: Guide to using @vimcraft/types package
**Read if**: You want IDE autocomplete and type checking
**Key topics**:
- Installing @vimcraft/types
- Setting up tsconfig.json
- Using types in index.ts
- Full type coverage
- IDE integration
- Type examples

### [vim.e2e Reference](./vim-e2e.md) ✨ NEW
**Purpose**: E2E testing and plugin development debugging API
**Read if**: You're writing E2E tests or debugging plugins
**Key topics**:
- vim.e2e.keys() - Send raw Vim keystrokes
- vim.e2e.getCursor(), getState(), getMode() - State queries
- vim.e2e.describe(), test(), runAll() - Test structure
- vim.e2e.assert.* - Rich assertions
- Plugin development debugging workflow
- Full TypeScript types

---

## 🎯 API by Use Case

### "I want to configure basic editor settings"

```typescript
// Use vim.opt for ergonomic option setting
vim.opt.number = true;
vim.opt.relativeNumber = true;
vim.opt.cursorLine = true;
vim.opt.tabStop = 4;
vim.opt.expandTab = true;
```

See: [vim.opt Reference](./vim-opt.md)

### "I want to create custom key mappings"

```typescript
// Use vim.keymap for key mappings
vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
vim.keymap.set('n', '<leader>q', ':q<CR>', { silent: true });
vim.keymap.set('i', 'jk', '<Esc>', { noremap: true });
```

See: [vim.keymap Reference](./vim-keymap.md)

### "I want to customize syntax highlighting"

```typescript
// Use vim.highlight or vim.api.nvim_set_hl
vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
vim.highlight('Function', { fg: '#61afef', bold: true });
vim.api.nvim_set_hl(0, 'Error', { fg: '#e06c75', bg: '#3e2a2a' });
```

See: [Quick Reference](./quick-reference.md#highlight-functions)

### "I want to create autocommands"

```typescript
// Use vim.api.nvim_create_autocmd
vim.api.nvim_create_autocmd('BufRead', {
  pattern: '*.js',
  callback: (args) => {
    console.log(`Loaded ${args.file}`);
    vim.opt.tabStop = 2;
  }
});
```

See: [vim.api Reference](./vim-api.md#autocommand-functions)

### "I need full control with low-level API"

```typescript
// Use vim.api.nvim_* functions
const buf = vim.api.nvim_get_current_buf();
const lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false);
vim.api.nvim_buf_set_lines(buf, 0, -1, false, ['new line']);
vim.api.nvim_win_set_cursor(0, [1, 0]);
```

See: [vim.api Reference](./vim-api.md)

### "I want to detect file types for syntax highlighting"

```typescript
// Use vim.filetype.match for comprehensive filetype detection
const filetype = vim.filetype.match({ filename: "main.rs" });
console.log(filetype); // "rust"

// Detect from current buffer
const currentFiletype = vim.filetype.match({ buf: 0 });
if (currentFiletype) {
  vim.bo.filetype = currentFiletype;
}

// Route to language-specific handlers
if (filetype === "rust") {
  setupRustAnalyzer();
} else if (filetype === "javascript" || filetype === "typescript") {
  setupTSServer();
}
```

See: [vim.filetype Reference](./vim-filetype.md)

### "I want to write E2E tests or debug my plugin"

```typescript
// Use vim.e2e for testing and debugging
vim.e2e.describe("My Feature", () => {
    vim.e2e.test("basic functionality", async () => {
        await vim.e2e.keys(":e /tmp/test.txt<CR>");
        await vim.e2e.keys("iHello<ESC>");

        const cursor = await vim.e2e.getCursor();
        vim.e2e.assert.cursorAt(0, 4);
    });
});

vim.e2e.runAll();

// Or for interactive debugging:
async function debugMyPlugin() {
    const state = await vim.e2e.getState();
    const logs = await vim.e2e.getLogs({ level: "error" });
    console.log(state, logs);
}
```

See: [vim.e2e Reference](./vim-e2e.md)

---

## 📊 API Tiers (Priority)

### Tier 1: Essential (Implement First) ✅
Already available or Phase 3-4:
- vim.opt.* (basic options)
- vim.highlight()
- vim.filetype.match() (1,437+ compile-time mappings)
- vim.api.nvim_buf_get_lines()
- vim.api.nvim_buf_set_lines()
- vim.g/b/w/t/v/env variables

### Tier 2: Important (Phase 4)
Coming in plugin system phase:
- vim.keymap.set/del
- vim.api.nvim_create_autocmd
- vim.api.nvim_create_user_command
- vim.api.nvim_set_hl
- Full vim.opt implementation

### Tier 3: Advanced (Phase 5+)
Future features:
- vim.diagnostic.*
- vim.lsp.*
- vim.treesitter.*
- vim.loop.*

---

## 🔍 Quick Links by Topic

### Options
- [All Options List](./vim-opt.md#option-list)
- [Display Options](./vim-opt.md#display-options)
- [Indentation Options](./vim-opt.md#indentation-options)
- [Search Options](./vim-opt.md#search-options)

### Keymaps
- [Creating Mappings](./vim-keymap.md#creating-mappings)
- [Mapping Modes](./vim-keymap.md#modes)
- [Mapping Options](./vim-keymap.md#options)
- [Callback Functions](./vim-keymap.md#callbacks)

### Buffers & Windows
- [Buffer Functions](./vim-api.md#buffer-functions)
- [Window Functions](./vim-api.md#window-functions)
- [Handle System](./quick-reference.md#buffer-window-handle-system)

### Events & Automation
- [Autocommand Events](./quick-reference.md#event-system)
- [Creating Autocommands](./vim-api.md#autocommand-functions)
- [User Commands](./vim-api.md#user-command-functions)

### Highlighting
- [Highlight Groups](./quick-reference.md#highlight-groups)
- [Setting Highlights](./vim-api.md#highlight-functions)
- [Priority System](./quick-reference.md#highlight-priority-system)

### TypeScript
- [Setup Guide](./typescript-types.md#setup)
- [Type Examples](./typescript-types.md#examples)
- [IDE Integration](./typescript-types.md#ide-integration)

---

## 🎓 Learning Path

### Beginner (Just configuring Vimcraft)

1. Read [Quick Reference](./quick-reference.md) - Tier 1 section (15 min)
2. Learn basic [vim.opt](./vim-opt.md) options
3. Try examples in your index.ts

### Intermediate (Writing plugins)

1. Read [TypeScript Types](./typescript-types.md) - Set up IDE support
2. Study [vim.api Reference](./vim-api.md) sections you need
3. Read [vim.keymap Reference](./vim-keymap.md) for custom mappings
4. Check [Quick Reference](./quick-reference.md) for patterns

### Advanced (Deep customization)

1. Read full [vim.api Reference](./vim-api.md)
2. Understand [Type Conversion Rules](./quick-reference.md#type-conversion-rules)
3. Study [Error Handling Patterns](./quick-reference.md#error-handling-pattern)
4. Reference Neovim source when needed

---

## 📖 API Naming Conventions

### Ergonomic Wrappers (Recommended)

```typescript
vim.opt.number = true;              // Ergonomic
vim.keymap.set('n', 'x', 'dd');     // Ergonomic
vim.highlight('Comment', {...});     // Ergonomic
```

### Low-Level API (Full Control)

```typescript
vim.api.nvim_set_option('number', true);           // Low-level
vim.api.nvim_set_keymap('n', 'x', 'dd', {});       // Low-level
vim.api.nvim_set_hl(0, 'Comment', {...});          // Low-level
```

**Rule**: Use ergonomic wrappers when available, low-level API for advanced cases.

See: [Quick Reference - API Naming Convention](./quick-reference.md#api-naming-convention)

---

## 🔗 Related Documentation

- [Architecture](../architecture/) - Understand the system design
- [Guides](../guides/) - Configuration tutorials
- [Development](../development/) - Contributing API implementations
- [Roadmap](../roadmap/) - What APIs are coming

---

## 📝 Contributing to API Docs

### Adding API Documentation

1. Document all parameters and return values
2. Provide usage examples
3. Note current implementation status
4. Link to related functions
5. Update this index

### Example Template

````markdown
## vim.api.nvim_example_function

**Status**: ✅ Implemented / 🚧 Partial / ❌ Not Yet

**Signature**:
```typescript
vim.api.nvim_example_function(arg1: Type1, arg2: Type2): ReturnType
```

**Parameters**:
- `arg1` (Type1): Description
- `arg2` (Type2): Description

**Returns**: Description of return value

**Example**:
```typescript
const result = vim.api.nvim_example_function(value1, value2);
```

**See also**:
- [Related Function](#related)
````

---

**Last Updated**: November 3, 2025
**API Version**: 0.3.0
**Coverage**: 150+ functions typed, Tier 1 implemented
