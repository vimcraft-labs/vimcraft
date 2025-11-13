# Neovim API Quick Reference for Vimcraft Implementation

## Most Important APIs to Implement First

### Tier 1: Essential (Phase 3-4)
These are what users expect immediately:

```javascript
// Options (vim.o, vim.opt)
ov.opt.number = true;
ov.opt.shiftwidth = 4;
ov.opt.number:get()
ov.opt_local.wrap = false;
ov.opt_global.number = true;

// Keymaps (vim.keymap)
ov.keymap.set('n', 'x', callback, { buffer: true })
ov.keymap.del('n', 'x')

// Core API (vim.api)
ov.api.nvim_get_current_buf()
ov.api.nvim_buf_get_lines(bufnr, start, end, strict)
ov.api.nvim_buf_set_lines(bufnr, start, end, strict, lines)
ov.api.nvim_set_keymap(mode, lhs, rhs, opts)

// Variables (vim.g, vim.b, etc)
ov.g.mapleader = ' '
ov.b.filetype = 'lua'
```

### Tier 2: Important (Phase 4)
Automate editor behavior:

```javascript
// Autocommands (vim.api.nvim_create_autocmd)
ov.api.nvim_create_autocmd('FileType', {
  pattern: '*.lua',
  callback: (args) => {}
})

// User Commands (vim.api.nvim_create_user_command)
ov.api.nvim_create_user_command('MyCmd', callback, { nargs: '*' })

// Highlighting (vim.api.nvim_set_hl)
ov.api.nvim_set_hl(0, 'MyGroup', { fg: '#fff', bg: 'red' })
```

### Tier 3: Nice to Have (Phase 5+)
Advanced features:

```javascript
// Diagnostics (vim.diagnostic)
ov.diagnostic.set(ns, bufnr, diags)
ov.diagnostic.get(bufnr, opts)
ov.diagnostic.config({...})

// LSP (vim.lsp)
// Defer until later - complex subsystem

// TreeSitter (vim.treesitter)
// Defer until later - needs parser integration
```

## API Naming Convention

### Principle: Exact Neovim Mirror

Option 1: Use `ov.api.*` for everything
```javascript
ov.api.nvim_set_keymap(mode, lhs, rhs, opts)
ov.api.nvim_create_autocmd(event, opts)
ov.api.nvim_buf_get_lines(bufnr, start, end, strict)
```

Option 2: Create ergonomic aliases (recommended)
```javascript
// Both work:
ov.api.nvim_set_keymap('n', 'x', 'dd')
ov.keymap.set('n', 'x', 'dd')  // Alias

ov.api.nvim_create_autocmd('BufRead', {...})
ov.autocmd.create('BufRead', {...})  // Alias
```

Suggested aliases:
- `ov.keymap.*` → `ov.api.nvim_*keymap*`
- `ov.autocmd.*` → `ov.api.nvim_*autocmd*`
- `ov.cmd.*` → `ov.api.nvim_cmd*`
- `ov.opt.*` → `ov.api.nvim_*option*`

## Buffer/Window Handle System

Like Neovim, use integer handles:

```javascript
// Buffer handles
0 = current buffer
1, 2, 3, ... = specific buffers

// Window handles
0 = current window
1, 2, 3, ... = specific windows
```

Example:
```javascript
ov.api.nvim_buf_set_lines(5, 0, -1, false, ['new', 'lines'])
// Set lines in buffer 5
```

## Option Type Handling

Options have different metatypes. Vimcraft must handle:

```javascript
// Boolean
ov.opt.number = true
ov.opt.number = false

// Number
ov.opt.shiftwidth = 4
ov.opt.tabstop = 8

// String
ov.opt.colorscheme = 'default'
ov.opt.background = 'dark'

// Array (comma-separated)
ov.opt.wildignore = ['*.o', '*.a', '*.pyc']

// Set (flags - comma or space separated)
ov.opt.formatoptions = { n: true, j: true }

// Map (key:value pairs)
ov.opt.listchars = { space: '_', tab: '>~' }
```

## Event System

Autocommand events (minimum viable set):

```javascript
// File events
'BufRead'       // Buffer opened for reading
'BufWrite'      // Buffer about to be written
'BufWritePre'   // Before BufWrite
'BufWritePost'  // After BufWrite
'BufDelete'     // Buffer deleted
'FileType'      // After filetype set

// Window events
'WinEnter'      // Window became current
'WinLeave'      // Window lost focus

// Mode events
'InsertEnter'   // Entered Insert mode
'InsertLeave'   // Left Insert mode
'ModeChanged'   // Mode changed

// Content events
'TextChanged'   // Text changed
'CursorMoved'   // Cursor moved (Normal mode)
'CursorMovedI'  // Cursor moved (Insert mode)

// Startup/shutdown
'VimEnter'      // Nvim initialization done
'VimLeave'      // Exiting
```

## Highlight Priority System

```javascript
// Priority levels (lower = rendered first)
ov.hl.priorities = {
  syntax:          50,    // Syntax highlighting
  treesitter:      100,   // Tree-sitter highlighting
  semantic_tokens: 125,   // LSP semantic highlighting
  diagnostics:     150,   // Error/warning underlines
  user:            200,   // User-triggered highlights
}

// Usage
ov.hl.range(bufnr, ns, 'Error', {0, 0}, {0, 5}, {
  priority: ov.hl.priorities.user
})
```

## Variable Scopes

Like Neovim, support scope prefixes:

```javascript
ov.g.*  // Global (g:)
ov.b.*  // Buffer-local (b:)
ov.w.*  // Window-local (w:)
ov.t.*  // Tabpage-local (t:)
ov.v.*  // Built-in (v:) - mostly read-only
ov.env.*  // Environment variables
```

All are accessed via Proxy objects:
```javascript
ov.g.mapleader = ' '
ov.b[5].filetype = 'lua'  // Buffer 5
ov.w[7].curswant = 10    // Window 7
```

## Type Conversion Rules

**Zig → JavaScript**:
```
null        → undefined
bool        → boolean
int         → number
float       → number (may lose precision)
string      → string
array       → array
table/dict  → object
```

**JavaScript → Zig**:
```
undefined   → null
boolean     → bool
number      → int64 or float64
string      → string
array       → array
object      → dict/table
null        → nil
```

## Error Handling Pattern

```javascript
// All API calls may throw errors
try {
  ov.api.nvim_buf_set_lines(5, 0, -1, false, lines)
} catch (e) {
  console.error(`Failed to set lines: ${e.message}`)
  // Error message matches Neovim format
}
```

Error codes (follow Neovim):
- `E901`: Invalid buffer
- `E902`: Invalid window
- `E903`: Invalid range
- etc.

## Command Mode Support

Minimal ex-command implementation:

```javascript
// Execute single command
ov.cmd.set({ cmd: 'split', args: ['file.lua'] })

// Dynamic command wrapper
ov.cmd.split({ 'file.lua' })
ov.cmd.vsplit()
ov.cmd.edit({ 'newfile.txt' })

// Multiline vimscript (defer to Phase 5+)
// Not needed initially
```

## Backward Compatibility

**Golden Rule**: If it works in Neovim, it should work (or be easy to port) in Vimcraft.

```javascript
// Neovim style
vim.keymap.set('n', 'x', function() end)

// Vimcraft equivalent
ov.keymap.set('n', 'x', function() {})

// User conversion effort: zero (just rename vim → ov)
```

## Performance Considerations

### What to Cache
- Option definitions (immutable)
- Autocommand IDs (small list)
- Keymap definitions (static after init)

### What NOT to Cache
- Current buffer/window (may change)
- Option values (change frequently)
- Variable values (mutable)

### Lazy Load
- Only load when first accessed:
  - LSP subsystem
  - TreeSitter module
  - Heavy stdlib modules

## Testing Checklist

For each API function:

- [ ] Works with no args
- [ ] Works with required args
- [ ] Works with optional args
- [ ] Handles invalid buffer/window handles
- [ ] Handles edge cases (empty buffer, invalid ranges)
- [ ] Error messages are clear
- [ ] Return values match Neovim's

Example test:
```javascript
function testNvimBufGetLines() {
  const lines = ov.api.nvim_buf_get_lines(0, 0, 5, false)
  console.assert(Array.isArray(lines))
  console.assert(lines.length <= 5)
}
```

## File Structure Recommendation

```
src/
├── config/
│   ├── options.zig      # Options manager
│   └── option_defs.zig  # Option metadata
├── api/
│   ├── api.zig          # Public API interface
│   ├── buffer.zig       # Buffer operations
│   ├── window.zig       # Window operations
│   ├── keymap.zig       # Keymap operations
│   └── autocmd.zig      # Autocommand system
├── event/
│   ├── autocommand.zig  # Autocommand manager
│   └── events.zig       # Event types
└── jsi/
    ├── jsi_api.zig      # Zig→JavaScript bridge
    └── js_runtime.zig   # JavaScript integration
```

## Key Files from Neovim to Study

For implementation reference:

1. `/runtime/lua/vim/_options.lua` (933 lines)
   - How to implement option system
   - Type conversion patterns

2. `/runtime/lua/vim/keymap.lua` (133 lines)
   - Simple, clear implementation
   - Good model for Vimcraft API

3. `/runtime/lua/vim/_editor.lua` (1,300 lines)
   - Metatable accessor pattern
   - Variable scope system

4. `/src/nvim/api/vim.c` (78KB)
   - API function patterns
   - Error handling

5. `/src/nvim/api/autocmd.c` (28KB)
   - Autocommand implementation
   - Event firing pattern

---

**Usage**: Keep this file open while implementing Phase 3+4  
**Updated**: November 3, 2025  
**Status**: Ready for implementation

