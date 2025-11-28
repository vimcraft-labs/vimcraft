# Vimcraft LSP Implementation Plan

**Version**: 0.1.0 (Draft)
**Status**: Planning Phase
**Target**: Phase 5 (Q2 2025)

This document outlines the complete LSP (Language Server Protocol) implementation plan for Vimcraft, including all prerequisite APIs that must be implemented first.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Implementation Phases](#implementation-phases)
5. [API Reference](#api-reference)
6. [Testing Strategy](#testing-strategy)
7. [TODO Checklist](#todo-checklist)

---

## Overview

### What is LSP?

The Language Server Protocol (LSP) defines a standard protocol for communication between editors and language servers. Language servers provide IDE features like:

- **Diagnostics** (errors, warnings)
- **Hover** (type info, documentation)
- **Go to Definition**
- **Find References**
- **Completion**
- **Rename**
- **Code Actions**

### Vimcraft LSP Goals

| Goal | Priority | Notes |
|------|----------|-------|
| Neovim-compatible API | High | `vim.lsp.*` namespace |
| TypeScript/JavaScript support | High | Via typescript-language-server |
| Zig support | High | Via zls |
| Rust support | Medium | Via rust-analyzer |
| Minimal configuration | High | Auto-detect language servers |
| Plugin extensibility | Medium | Custom handlers via JS |

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Vimcraft Editor                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   vim.lsp    │  │vim.diagnostic│  │    vim.api.*         │  │
│  │   (JS API)   │  │   (JS API)   │  │  (Prerequisite APIs) │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │              │
│  ┌──────┴─────────────────┴──────────────────────┴───────────┐  │
│  │                    JSI Bridge (Zig ↔ JS)                  │  │
│  └──────────────────────────┬────────────────────────────────┘  │
│                             │                                   │
│  ┌──────────────────────────┴────────────────────────────────┐  │
│  │                   LSP Client (Zig)                        │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │  Transport  │  │  Protocol   │  │    Handlers     │   │  │
│  │  │   (stdio)   │  │  (JSON-RPC) │  │  (diagnostics)  │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │
│  └───────────────────────────┬───────────────────────────────┘  │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │ stdio (stdin/stdout)
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Language Server Process                       │
│  (typescript-language-server, zls, rust-analyzer, etc.)         │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User types code
   ↓
2. Buffer change triggers didChange notification
   ↓
3. LSP client sends JSON-RPC to language server
   ↓
4. Language server responds (diagnostics, completions, etc.)
   ↓
5. LSP client parses response
   ↓
6. vim.diagnostic displays errors (via extmarks)
   ↓
7. UI updates (virtual text, signs, floating windows)
```

---

## Prerequisites

These APIs must be implemented **before** starting LSP work.

### Priority 1: Namespace & Extmarks (Foundation)

Extmarks are the foundation for all LSP UI - diagnostics, inlay hints, virtual text.

| API | Status | File | Description |
|-----|--------|------|-------------|
| `vim.api.createNamespace(name)` | [ ] TODO | `namespace_api.zig` | Create namespace for extmarks |
| `vim.api.getNamespaces()` | [ ] TODO | `namespace_api.zig` | List all namespaces |
| `vim.api.bufSetExtmark(buf, ns, line, col, opts)` | [ ] TODO | `extmark_api.zig` | Set extmark (virtual text, signs) |
| `vim.api.bufGetExtmarks(buf, ns, start, end, opts)` | [ ] TODO | `extmark_api.zig` | Query extmarks |
| `vim.api.bufDelExtmark(buf, ns, id)` | [ ] TODO | `extmark_api.zig` | Delete extmark |
| `vim.api.bufClearNamespace(buf, ns, start, end)` | [ ] TODO | `extmark_api.zig` | Clear all extmarks in namespace |

**Extmark Options** (subset for LSP):
```typescript
interface ExtmarkOpts {
  id?: number;              // Reuse existing extmark
  end_line?: number;        // Multi-line extmark
  end_col?: number;         // End column
  virt_text?: [string, string][]; // Virtual text [[text, hl_group], ...]
  virt_text_pos?: 'eol' | 'overlay' | 'right_align';
  hl_group?: string;        // Highlight group
  sign_text?: string;       // Sign column text (2 chars max)
  sign_hl_group?: string;   // Sign highlight
  priority?: number;        // Render priority (higher = on top)
}
```

### Priority 2: vim.fn Basics

Essential Vimscript functions needed by LSP.

| API | Status | File | Description |
|-----|--------|------|-------------|
| `vim.fn.executable(cmd)` | [ ] TODO | `fn_api.zig` | Check if binary exists (0/1) |
| `vim.fn.getcwd()` | [ ] TODO | `fn_api.zig` | Get current working directory |
| `vim.fn.expand(expr)` | [ ] TODO | `fn_api.zig` | Expand special chars (`%`, `~`, `<cword>`) |
| `vim.fn.fnamemodify(path, mods)` | [ ] TODO | `fn_api.zig` | Modify filename (`:p`, `:h`, `:t`) |
| `vim.fn.filereadable(path)` | [ ] TODO | `fn_api.zig` | Check if file readable (0/1) |
| `vim.fn.isdirectory(path)` | [ ] TODO | `fn_api.zig` | Check if directory (0/1) |
| `vim.fn.getline(lnum)` | [ ] TODO | `fn_api.zig` | Get line content |
| `vim.fn.mode()` | [ ] TODO | `fn_api.zig` | Get current mode string |
| `vim.fn.col(expr)` | [ ] TODO | `fn_api.zig` | Get column (`.` = cursor) |
| `vim.fn.line(expr)` | [ ] TODO | `fn_api.zig` | Get line number (`.` = cursor) |

### Priority 3: Floating Windows

Required for hover, signature help, and completion popups.

| API | Status | File | Description |
|-----|--------|------|-------------|
| `vim.api.openWin(buf, enter, config)` | [ ] TODO | `window_api.zig` | Open floating window |
| `vim.api.winSetConfig(win, config)` | [ ] TODO | `window_api.zig` | Update window config |
| `vim.api.winGetConfig(win)` | [ ] TODO | `window_api.zig` | Get window config |
| `vim.api.winHide(win)` | [ ] TODO | `window_api.zig` | Hide floating window |

**Floating Window Config**:
```typescript
interface FloatConfig {
  relative: 'editor' | 'win' | 'cursor';
  row: number;        // Row offset
  col: number;        // Column offset
  width: number;      // Window width
  height: number;     // Window height
  anchor?: 'NW' | 'NE' | 'SW' | 'SE';
  focusable?: boolean;
  border?: 'none' | 'single' | 'double' | 'rounded' | 'solid' | 'shadow';
  title?: string;
  title_pos?: 'left' | 'center' | 'right';
  style?: 'minimal';  // No line numbers, etc.
  zindex?: number;    // Stack order
}
```

### Priority 4: Options & Keymaps

For LSP configuration and default keybindings.

| API | Status | File | Description |
|-----|--------|------|-------------|
| `vim.api.getOption(name)` | [ ] TODO | `option_api.zig` | Get global option |
| `vim.api.setOption(name, value)` | [ ] TODO | `option_api.zig` | Set global option |
| `vim.api.setKeymap(mode, lhs, rhs, opts)` | [ ] TODO | `keymap_api.zig` | Set keymap |
| `vim.api.delKeymap(mode, lhs)` | [ ] TODO | `keymap_api.zig` | Delete keymap |
| `vim.api.getKeymap(mode)` | [ ] TODO | `keymap_api.zig` | List keymaps |

### Priority 5: Diagnostics Module

High-level diagnostic management (built on extmarks).

| API | Status | File | Description |
|-----|--------|------|-------------|
| `vim.diagnostic.set(ns, buf, diagnostics, opts)` | [ ] TODO | `diagnostic_api.zig` | Set buffer diagnostics |
| `vim.diagnostic.get(buf, opts)` | [ ] TODO | `diagnostic_api.zig` | Get diagnostics |
| `vim.diagnostic.hide(ns, buf)` | [ ] TODO | `diagnostic_api.zig` | Hide diagnostics |
| `vim.diagnostic.show(ns, buf, diagnostics, opts)` | [ ] TODO | `diagnostic_api.zig` | Show diagnostics |
| `vim.diagnostic.reset(ns, buf)` | [ ] TODO | `diagnostic_api.zig` | Clear diagnostics |
| `vim.diagnostic.open_float(opts)` | [ ] TODO | `diagnostic_api.zig` | Show diagnostic popup |
| `vim.diagnostic.goto_next(opts)` | [ ] TODO | `diagnostic_api.zig` | Jump to next diagnostic |
| `vim.diagnostic.goto_prev(opts)` | [ ] TODO | `diagnostic_api.zig` | Jump to prev diagnostic |
| `vim.diagnostic.setqflist(opts)` | [ ] TODO | `diagnostic_api.zig` | Populate quickfix list |

**Diagnostic Object**:
```typescript
interface Diagnostic {
  lnum: number;           // 0-indexed line
  col: number;            // 0-indexed column
  end_lnum?: number;      // End line
  end_col?: number;       // End column
  severity: DiagnosticSeverity;
  message: string;
  source?: string;        // "typescript", "eslint", etc.
  code?: string | number; // Error code
}

enum DiagnosticSeverity {
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  HINT = 4,
}
```

---

## Implementation Phases

### Phase 1: Foundation APIs (2-3 weeks)

**Goal**: Implement all prerequisite APIs.

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 1 | Namespace + Extmarks | `createNamespace`, `bufSetExtmark`, `bufGetExtmarks` |
| 1 | Extmark rendering | Virtual text displayed in terminal |
| 2 | vim.fn basics | `executable`, `getcwd`, `expand`, `fnamemodify` |
| 2 | More vim.fn | `getline`, `mode`, `col`, `line` |
| 3 | Floating windows | `openWin`, `winSetConfig`, border rendering |
| 3 | Options & Keymaps | `getOption`, `setOption`, `setKeymap` |

**Milestone**: Can display virtual text and floating windows.

### Phase 2: Diagnostics Module (1-2 weeks)

**Goal**: Implement `vim.diagnostic.*` API.

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 4 | Diagnostic storage | Per-buffer diagnostic registry |
| 4 | Diagnostic rendering | Virtual text + sign column |
| 5 | Diagnostic navigation | `goto_next`, `goto_prev` |
| 5 | Diagnostic float | `open_float` with formatted message |

**Milestone**: Can show diagnostic errors from hardcoded test data.

### Phase 3: LSP Client Core (2-3 weeks)

**Goal**: Basic LSP client that can start server and exchange messages.

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 6 | JSON-RPC transport | Parse/serialize LSP messages |
| 6 | Process spawning | Start language server via stdio |
| 7 | Initialize handshake | Send initialize, receive capabilities |
| 7 | Document sync | textDocument/didOpen, didChange, didClose |
| 8 | Diagnostic handler | publishDiagnostics → vim.diagnostic |

**Milestone**: Real diagnostics from typescript-language-server.

### Phase 4: LSP Features (2-3 weeks)

**Goal**: Implement common LSP features.

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 9 | Hover | textDocument/hover → floating window |
| 9 | Go to definition | textDocument/definition → jump |
| 10 | Find references | textDocument/references → quickfix list |
| 10 | Completion | textDocument/completion → popup menu |
| 11 | Code actions | textDocument/codeAction → menu |
| 11 | Rename | textDocument/rename → apply edits |

**Milestone**: Full IDE experience with TypeScript files.

### Phase 5: Polish & Configuration (1-2 weeks)

**Goal**: Configuration API and quality of life.

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 12 | vim.lsp.config | Language server configuration |
| 12 | Auto-attach | Automatic buffer attachment |
| 13 | Error handling | Graceful server crash recovery |
| 13 | Documentation | API docs, user guide |

**Milestone**: Production-ready LSP support.

---

## API Reference

### vim.lsp

Core LSP client API.

#### `vim.lsp.start(config)`

Start a language server.

```typescript
interface LspConfig {
  name: string;           // Client name (for logging)
  cmd: string[];          // Command to start server
  root_dir?: string;      // Project root (auto-detected if omitted)
  capabilities?: object;  // Client capabilities override
  handlers?: object;      // Custom notification/request handlers
  on_attach?: (client: LspClient, bufnr: number) => void;
  on_exit?: (code: number, signal: string) => void;
}

vim.lsp.start({
  name: 'typescript',
  cmd: ['typescript-language-server', '--stdio'],
  root_dir: vim.fn.getcwd(),
  on_attach: (client, bufnr) => {
    // Set up keymaps
    vim.keymap.set('n', 'K', () => vim.lsp.buf.hover(), { buffer: bufnr });
    vim.keymap.set('n', 'gd', () => vim.lsp.buf.definition(), { buffer: bufnr });
  },
});
```

#### `vim.lsp.buf_attach_client(bufnr, client_id)`

Attach buffer to LSP client.

#### `vim.lsp.buf_detach_client(bufnr, client_id)`

Detach buffer from LSP client.

#### `vim.lsp.get_clients(filter?)`

Get active LSP clients.

```typescript
const clients = vim.lsp.get_clients({ bufnr: 0 });
```

#### `vim.lsp.stop_client(client_id, force?)`

Stop LSP client.

### vim.lsp.buf

Buffer-scoped LSP operations.

| Method | LSP Method | Description |
|--------|------------|-------------|
| `vim.lsp.buf.hover()` | textDocument/hover | Show hover info |
| `vim.lsp.buf.definition()` | textDocument/definition | Go to definition |
| `vim.lsp.buf.declaration()` | textDocument/declaration | Go to declaration |
| `vim.lsp.buf.type_definition()` | textDocument/typeDefinition | Go to type definition |
| `vim.lsp.buf.implementation()` | textDocument/implementation | Go to implementation |
| `vim.lsp.buf.references()` | textDocument/references | Find references |
| `vim.lsp.buf.completion()` | textDocument/completion | Trigger completion |
| `vim.lsp.buf.signature_help()` | textDocument/signatureHelp | Show signature |
| `vim.lsp.buf.rename(new_name?)` | textDocument/rename | Rename symbol |
| `vim.lsp.buf.code_action()` | textDocument/codeAction | Show code actions |
| `vim.lsp.buf.format(opts?)` | textDocument/formatting | Format buffer |

### vim.lsp.handlers

Default handlers for LSP notifications/requests.

```typescript
// Override hover handler
vim.lsp.handlers['textDocument/hover'] = (err, result, ctx, config) => {
  if (result && result.contents) {
    // Custom hover display
    showCustomHover(result.contents);
  }
};
```

---

## Testing Strategy

### Unit Tests

Test individual API functions in isolation.

```
tests/unit/api/
├── namespace_api_test.zig
├── extmark_api_test.zig
├── fn_api_test.zig
├── window_api_test.zig
├── diagnostic_api_test.zig
└── lsp_client_test.zig
```

### E2E Tests

Test full LSP workflow with mock server.

```
tests/e2e/
├── lsp-client/
│   ├── mock-lsp-server.js    # Mock LSP server (exists)
│   ├── e2e.ts                # LSP integration tests
│   └── config.ts             # Test setup
├── extmarks/
│   ├── e2e.ts                # Extmark rendering tests
│   └── config.ts
├── diagnostics/
│   ├── e2e.ts                # Diagnostic display tests
│   └── config.ts
└── floating-windows/
    ├── e2e.ts                # Floating window tests
    └── config.ts
```

### Mock LSP Server

Already exists at `tests/e2e/lsp-client/mock-lsp-server.js`:

- Handles: initialize, shutdown, hover, definition, references
- Sends: publishDiagnostics notification
- Useful for deterministic testing

### Real Server Tests (Manual)

| Server | Language | Install | Test File |
|--------|----------|---------|-----------|
| typescript-language-server | TypeScript | `npm i -g typescript-language-server` | `test.ts` |
| zls | Zig | `brew install zls` | `test.zig` |
| rust-analyzer | Rust | `rustup component add rust-analyzer` | `test.rs` |

---

## TODO Checklist

### Phase 1: Foundation APIs

#### Namespace API
- [ ] Create `src/system/jsi/namespace_api.zig`
- [ ] Implement namespace registry (string → integer ID)
- [ ] `createNamespace(name)` - create or get existing namespace
- [ ] `getNamespaces()` - list all namespaces
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/namespace/e2e.ts`

#### Extmark API
- [ ] Create `src/system/jsi/extmark_api.zig`
- [ ] Implement extmark storage per buffer/namespace
- [ ] `bufSetExtmark(buf, ns, line, col, opts)` - create/update extmark
- [ ] `bufGetExtmarks(buf, ns, start, end, opts)` - query extmarks
- [ ] `bufDelExtmark(buf, ns, id)` - delete single extmark
- [ ] `bufClearNamespace(buf, ns, start, end)` - clear range
- [ ] Extmark rendering in `output_renderer.zig`
- [ ] Virtual text support (eol, overlay, right_align)
- [ ] Sign column support (2-char signs)
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/extmarks/e2e.ts`

#### vim.fn API
- [ ] Create `src/system/jsi/fn_api.zig`
- [ ] `executable(cmd)` - check PATH for binary
- [ ] `getcwd()` - return current working directory
- [ ] `expand(expr)` - expand `%` (current file), `~` (home), `<cword>` (word under cursor)
- [ ] `fnamemodify(path, mods)` - `:p` (full path), `:h` (head), `:t` (tail), `:e` (extension)
- [ ] `filereadable(path)` - check file exists and readable
- [ ] `isdirectory(path)` - check path is directory
- [ ] `getline(lnum)` - get line content (1-indexed)
- [ ] `mode()` - return mode string ('n', 'i', 'v', etc.)
- [ ] `col(expr)` - get column (`.` = cursor column)
- [ ] `line(expr)` - get line (`.` = cursor line, `$` = last line)
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/vim-fn/e2e.ts`

#### Floating Windows
- [ ] Implement floating window data structure
- [ ] `openWin(buf, enter, config)` - create floating window
- [ ] `winSetConfig(win, config)` - update window config
- [ ] `winGetConfig(win)` - get window config
- [ ] `winHide(win)` - hide (not close) window
- [ ] Border rendering (single, double, rounded)
- [ ] Title rendering (left, center, right)
- [ ] Z-index stacking for multiple floats
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/floating-windows/e2e.ts`

#### Options API
- [ ] `getOption(name)` - get global option value
- [ ] `setOption(name, value)` - set global option value
- [ ] `bufGetOption(buf, name)` - get buffer-local option
- [ ] `bufSetOption(buf, name, value)` - set buffer-local option
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/options-api/e2e.ts`

#### Keymap API
- [ ] `setKeymap(mode, lhs, rhs, opts)` - set keymap
- [ ] `delKeymap(mode, lhs)` - delete keymap
- [ ] `getKeymap(mode)` - list keymaps for mode
- [ ] `bufSetKeymap(buf, mode, lhs, rhs, opts)` - buffer-local keymap
- [ ] `bufDelKeymap(buf, mode, lhs)` - delete buffer-local keymap
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/keymap-api/e2e.ts`

### Phase 2: Diagnostics Module

- [ ] Create `src/system/jsi/diagnostic_api.zig`
- [ ] Implement diagnostic storage (per namespace, per buffer)
- [ ] `vim.diagnostic.set(ns, buf, diagnostics, opts)`
- [ ] `vim.diagnostic.get(buf, opts)`
- [ ] `vim.diagnostic.hide(ns, buf)`
- [ ] `vim.diagnostic.show(ns, buf, diagnostics, opts)`
- [ ] `vim.diagnostic.reset(ns, buf)`
- [ ] `vim.diagnostic.open_float(opts)` - show diagnostic in floating window
- [ ] `vim.diagnostic.goto_next(opts)` - jump to next diagnostic
- [ ] `vim.diagnostic.goto_prev(opts)` - jump to prev diagnostic
- [ ] Severity-based highlighting (Error=red, Warn=yellow, Info=blue, Hint=green)
- [ ] Sign column icons
- [ ] Virtual text display (end of line)
- [ ] Underline highlighting (squiggly lines)
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test `tests/e2e/diagnostics/e2e.ts`

### Phase 3: LSP Client Core

- [ ] Create `src/system/lsp/client.zig` - LSP client implementation
- [ ] Create `src/system/lsp/transport.zig` - JSON-RPC over stdio
- [ ] Create `src/system/lsp/protocol.zig` - LSP message types
- [ ] Implement JSON-RPC message framing (Content-Length header)
- [ ] Implement request/response correlation (id matching)
- [ ] `vim.lsp.start(config)` - start language server
- [ ] `vim.lsp.stop_client(client_id)` - stop language server
- [ ] `vim.lsp.get_clients(filter)` - list active clients
- [ ] `vim.lsp.buf_attach_client(bufnr, client_id)` - attach buffer
- [ ] `vim.lsp.buf_detach_client(bufnr, client_id)` - detach buffer
- [ ] Initialize handshake (initialize → initialized)
- [ ] Document sync (didOpen, didChange, didClose, didSave)
- [ ] Diagnostic handler (publishDiagnostics → vim.diagnostic)
- [ ] Register in `jsi_api.zig`
- [ ] Add TypeScript types to `vim.d.ts`
- [ ] Write E2E test with mock server `tests/e2e/lsp-client/e2e.ts`

### Phase 4: LSP Features

#### Hover
- [ ] `vim.lsp.buf.hover()` - send textDocument/hover request
- [ ] Parse MarkupContent response
- [ ] Display in floating window
- [ ] Markdown rendering (basic)
- [ ] Write E2E test

#### Go to Definition
- [ ] `vim.lsp.buf.definition()` - send textDocument/definition
- [ ] Handle Location / LocationLink response
- [ ] Jump to file:line:col
- [ ] Handle multiple results (quickfix list)
- [ ] Write E2E test

#### Find References
- [ ] `vim.lsp.buf.references()` - send textDocument/references
- [ ] Populate quickfix list with results
- [ ] Write E2E test

#### Completion
- [ ] `vim.lsp.buf.completion()` - send textDocument/completion
- [ ] Completion menu UI
- [ ] CompletionItem handling
- [ ] Snippet expansion (basic)
- [ ] Write E2E test

#### Code Actions
- [ ] `vim.lsp.buf.code_action()` - send textDocument/codeAction
- [ ] Action menu UI
- [ ] Apply workspace edits
- [ ] Write E2E test

#### Rename
- [ ] `vim.lsp.buf.rename(new_name?)` - send textDocument/rename
- [ ] Prompt for new name if not provided
- [ ] Apply workspace edits across files
- [ ] Write E2E test

#### Format
- [ ] `vim.lsp.buf.format(opts?)` - send textDocument/formatting
- [ ] Apply text edits to buffer
- [ ] Write E2E test

### Phase 5: Polish

- [ ] `vim.lsp.config` - declarative server configuration
- [ ] Auto-start server on buffer open (by filetype)
- [ ] Auto-attach buffer to running server
- [ ] Server crash recovery
- [ ] Rate limiting for didChange notifications
- [ ] Incremental document sync (optimization)
- [ ] Progress notifications ($/progress)
- [ ] Documentation: `docs/guides/lsp-setup.md`
- [ ] Documentation: Update `docs/api/vim-api-reference.md`

---

## References

- [LSP Specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
- [Neovim vim.lsp.lua](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp.lua)
- [Neovim vim.diagnostic.lua](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/diagnostic.lua)

---

## See Also

- [vim.api Reference](./vim-api-reference.md)
- [E2E Testing Guide](../../tests/e2e/CLAUDE.md)
- [JSI Architecture](../architecture/jsi-hostobject-architecture.md)
- [Roadmap Phase 5](../roadmap/phase-5-lsp-treesitter.md)
