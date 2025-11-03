# Architecture Documentation

Understanding OpenVim's design, architecture, and technical decisions.

---

## 📖 Overview

OpenVim follows a **four-layer architecture** inspired by Neovim but implemented with modern technologies:

```
┌─────────────────────────────────────────┐
│  Layer 4: User Configuration (init.js)  │
└─────────────────────────────────────────┘
                  ↕
┌─────────────────────────────────────────┐
│  Layer 3: JavaScript API (vim.*)        │
└─────────────────────────────────────────┘
                  ↕
┌─────────────────────────────────────────┐
│  Layer 2: JSI Bridge (Zero-copy)        │
└─────────────────────────────────────────┘
                  ↕
┌─────────────────────────────────────────┐
│  Layer 1: Editor Core (Zig)             │
└─────────────────────────────────────────┘
```

---

## 📚 Documents in This Category

### [Four-Layer Design](./four-layer-design.md)
**Purpose**: Understand OpenVim's core architectural pattern
**Read if**: You want to understand how the system is organized
**Key topics**:
- Layer responsibilities
- Communication between layers
- Design rationale
- Comparison with Neovim

### [Neovim Analysis](./neovim-analysis.md)
**Purpose**: Deep dive into Neovim's architecture (1,723 lines)
**Read if**: You're implementing features and need reference
**Key topics**:
- Neovim's API organization (13 categories)
- Implementation patterns
- Design patterns (metatables, namespaces, lazy loading)
- Feature gap analysis
- Code examples

### [Design Decisions](./design-decisions.md)
**Purpose**: Understand why we made certain technical choices
**Read if**: You're curious about the "why" behind decisions
**Key topics**:
- Why Zig over C/C++/Rust
- Why Hermes over Lua
- Why JavaScript for plugins
- Buffer storage choices
- API design choices

---

## 🎯 Quick Links by Topic

### Understanding the System
- [Four-Layer Design](./four-layer-design.md#overview)
- [Layer Responsibilities](./four-layer-design.md#layer-responsibilities)
- [Why Four Layers?](./four-layer-design.md#why-four-layers)

### Neovim Compatibility
- [Neovim's Architecture](./neovim-analysis.md#architecture-overview)
- [API Organization](./neovim-analysis.md#api-organization)
- [Feature Gap Analysis](./neovim-analysis.md#feature-gap-analysis)

### Technical Decisions
- [Language Choices](./design-decisions.md#language-choices)
- [Runtime Selection](./design-decisions.md#runtime-selection)
- [API Design](./design-decisions.md#api-design)

---

## 🔍 Key Architectural Concepts

### 1. Four-Layer Separation

Each layer has clear responsibilities:
- **Layer 1 (Zig Core)**: Performance-critical operations
- **Layer 2 (JSI Bridge)**: Zero-copy integration
- **Layer 3 (JS API)**: User-facing API
- **Layer 4 (Config)**: User configuration

See [Four-Layer Design](./four-layer-design.md) for details.

### 2. Zero-Copy Bridge

JSI (JavaScript Interface) enables:
- Direct function calls between Zig and JavaScript
- No serialization overhead
- Type conversion only at boundaries
- ~13x faster than traditional FFI

See [Four-Layer Design](./four-layer-design.md#layer-2-jsi-bridge) for details.

### 3. Neovim-Compatible API

OpenVim replicates Neovim's proven API design:
- `vim.api.*` - Core functions (150+ nvim_* functions)
- `vim.opt.*` - Options interface
- `vim.keymap.*` - Key mappings
- `vim.g/b/w/t/v/env` - Variable scopes

See [Neovim Analysis](./neovim-analysis.md) for complete reference.

### 4. Hot Reload Built-in

Unlike Neovim (requires plugins), OpenVim has native hot reload:
- Automatic config file watching
- Preserves editor state
- Cleans up timers/intervals
- Fast iteration cycle

See [Design Decisions](./design-decisions.md#hot-reload) for rationale.

---

## 📊 Architecture Comparison

| Aspect | Neovim | OpenVim |
|--------|--------|---------|
| **Core Language** | C (~100K lines) | Zig (~10K lines target) |
| **Plugin Language** | Lua 5.1 | JavaScript (Hermes) |
| **API Bridge** | Lua C API | JSI (zero-copy) |
| **Startup** | ~150ms | < 100ms (target) |
| **Hot Reload** | Plugin-based | Built-in |
| **Type System** | Runtime + hints | TypeScript native |
| **API Functions** | 150+ nvim_* | 150+ (compatible) |

---

## 🎓 Learning Path

### Beginner (Just getting started)

1. Read [Four-Layer Design](./four-layer-design.md) - 20 min
2. Understand layer responsibilities
3. See how pieces fit together

### Intermediate (Want to implement features)

1. Read [Neovim Analysis](./neovim-analysis.md) sections as needed
2. Study relevant code examples
3. Reference API patterns

### Advanced (Want to make architectural changes)

1. Read full [Neovim Analysis](./neovim-analysis.md) - 2-3 hours
2. Study [Design Decisions](./design-decisions.md)
3. Review Neovim source code (../neovim/)

---

## 🔗 Related Documentation

- [API Documentation](../api/) - API reference and types
- [Implementation Roadmap](../roadmap/) - What to build next
- [Development Guide](../development/) - How to contribute
- [Research](../research/) - Background research

---

## 📝 Contributing to Architecture Docs

Found something unclear or want to add details?

1. Check existing documents
2. Add clarifications or examples
3. Keep consistency with existing style
4. Update this index if adding new docs

---

**Last Updated**: November 3, 2025
**Status**: Core architecture stable, Phase 3+ implementation ongoing
