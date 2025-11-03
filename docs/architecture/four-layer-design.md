# Four-Layer Design

OpenVim's core architectural pattern.

---

## Overview

OpenVim uses a **four-layer architecture** that separates concerns and enables clean interfaces between components.

## The Four Layers

### Layer 1: Editor Core (Zig)
Performance-critical operations written in Zig.

**Responsibilities**:
- Buffer management
- Text storage and manipulation
- Display rendering
- Input handling
- Mode system

**Why Zig**: Fast, safe, direct hardware access.

### Layer 2: JSI Bridge (C++ + Zig)
Zero-copy interface between Zig and JavaScript.

**Responsibilities**:
- Function call bridging
- Type conversion
- Error propagation
- Host function registration

**Why JSI**: ~13x faster than traditional FFI.

### Layer 3: JavaScript API (vim.*)
User-facing API exposed to configuration.

**Responsibilities**:
- vim.api.* functions
- vim.opt proxy
- vim.keymap interface
- Variable scopes

**Why JavaScript**: Familiar, rich ecosystem, TypeScript support.

### Layer 4: User Configuration (init.js)
User's configuration and plugins.

**Responsibilities**:
- Option settings
- Key mappings
- Custom functions
- Plugin loading

**Why User Space**: Maximum flexibility, safe sandboxing.

---

## Communication Flow

```
User Config (init.js)
    │  vim.opt.number = true
    ↓
JavaScript API (vim.opt)
    │  Proxy setter triggered
    ↓
JSI Bridge (hermes_c_api.cpp)
    │  Zero-copy call to Zig
    ↓
Editor Core (options.zig)
    │  Set option in config
    └──→ Trigger redraw
```

---

For complete analysis, see [Neovim Analysis](./neovim-analysis.md).
