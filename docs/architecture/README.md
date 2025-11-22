# Architecture Documentation

Understanding Vimcraft's design, architecture, and technical decisions.

---

## 📖 Overview

Vimcraft follows a **four-layer architecture** inspired by Neovim but implemented with modern technologies:

```
┌─────────────────────────────────────────┐
│  Layer 4: User Configuration (index.js)  │
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
**Purpose**: Understand Vimcraft's core architectural pattern
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

### [JSI HostObject Design](./jsi-hostobject-design.md)
**Purpose**: Deep dive into zero-copy property dispatch pattern
**Read if**: You're implementing new APIs or understanding JSI internals
**Key topics**:
- HostObject vs HostFunction
- Zero-copy dispatch mechanism
- Performance characteristics
- Implementation patterns

### [JSI HostObject Migration](./jsi-hostobject-migration-summary.md)
**Purpose**: Summary of migration from HostFunction to HostObject
**Read if**: You want to understand the evolution of the API design
**Key topics**:
- Why we migrated
- Performance improvements
- Code changes made
- Lessons learned

### [JSI Gap Analysis](./jsi-gap-analysis.md) 🚨 **CRITICAL for Phase 4**
**Purpose**: Identify missing JSI features needed for plugin system
**Read if**: You're planning Phase 4 implementation
**Key topics**:
- React Native JSI vs Vimcraft comparison
- Event emitters (CRITICAL - needed for autocommands)
- Module system (CRITICAL - needed for plugins)
- Error throwing and boundaries
- Implementation priorities

### [TypeScript Support](./typescript-support.md) 🆕 **Phase 4 Feature**
**Purpose**: Architecture for TypeScript integration using SWC
**Read if**: You want to understand TypeScript support design or implement it
**Key topics**:
- SWC integration (Rust → C → Zig FFI)
- Transparent require() for .ts files
- Plugin ecosystem (GitHub-based, no npm)
- Optional TypeScript LSP plugin
- Hot reload with transpile cache
- Source map support

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

Vimcraft replicates Neovim's proven API design:
- `vim.api.*` - Core functions (150+ nvim_* functions)
- `vim.opt.*` - Options interface
- `vim.keymap.*` - Key mappings
- `vim.g/b/w/t/v/env` - Variable scopes

See [Neovim Analysis](./neovim-analysis.md) for complete reference.

### 4. Hot Reload Built-in

Unlike Neovim (requires plugins), Vimcraft has native hot reload:
- Automatic config file watching
- Preserves editor state
- Cleans up timers/intervals
- Fast iteration cycle

See [Design Decisions](./design-decisions.md#hot-reload) for rationale.

---

## 📊 Architecture Comparison

| Aspect | Neovim | Vimcraft |
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
