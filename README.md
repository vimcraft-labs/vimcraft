# OpenVim

**A Neovim-compatible text editor written in Zig with JavaScript/TypeScript plugin support**

[![Phase](https://img.shields.io/badge/Phase-1+2%20Complete-success)](docs/roadmap/)
[![Zig](https://img.shields.io/badge/Zig-0.13+-orange)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 🎯 What is OpenVim?

OpenVim is a modern text editor that combines:
- **Zig core**: Fast, safe systems programming
- **Hermes runtime**: JavaScript/TypeScript for configuration and plugins
- **JSI bridge**: Zero-copy integration (Zig ↔ JavaScript)
- **Neovim API**: Full compatibility for seamless migration

**Vision**: Neovim's power with modern architecture, better performance, and JavaScript plugins.

---

## ✨ Key Features

### Available Now (Phase 1+2) ✅
- 📝 Text display and file loading
- ⚡ Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- 🎮 Mode system (Normal/Insert/Visual)
- 🖥️ Terminal rendering with ANSI codes
- 🔄 Hot reload (automatic config reload on save)
- 🎨 Syntax highlighting configuration
- ⚙️ Basic configuration API (vim.opt, vim.highlight)

### Coming Soon (Phase 3-4) 🚧
- ✂️ Text editing operators (delete, change, yank/paste)
- ↩️ Undo/redo system
- 🔌 Full plugin system (vim.keymap, autocommands)
- 🎯 Neovim API compatibility

### Future (Phase 5+) 📅
- 🔍 Search and replace
- 🌳 Tree-sitter syntax highlighting
- 🔧 LSP integration
- 📊 Diagnostics system

See [Implementation Roadmap](docs/roadmap/) for complete details.

---

## 🚀 Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/openvim
cd openvim

# Initialize Hermes submodule
git submodule update --init

# Build OpenVim
zig build

# Run with a file
./zig-out/bin/openvim README.md
```

See [Getting Started Guide](docs/guides/getting-started.md) for detailed instructions.

### Basic Configuration

```bash
# Create config directory
mkdir -p ~/.config/openvim

# Create init.js
cat > ~/.config/openvim/init.js << 'EOF'
// Basic OpenVim configuration
vim.opt.cursorLine = true;
vim.opt.number = true;

vim.highlight('Comment', { fg: '#6c6c6c', italic: true });

console.log('✅ OpenVim ready!');
EOF

# Run OpenVim (config loads automatically)
./zig-out/bin/openvim README.md
```

See [Configuration Guide](docs/guides/configuration.md) for more options.

---

## 📖 Documentation

### 🎯 [Main Documentation Hub](docs/)
Complete index of all documentation.

### Quick Links by Purpose

**New Users**:
- [Getting Started](docs/guides/getting-started.md) - Install and run
- [Configuration Guide](docs/guides/configuration.md) - Customize your setup
- [TypeScript Setup](docs/guides/typescript-setup.md) - IDE autocomplete

**Understanding the Design**:
- [Architecture Overview](docs/architecture/) - System design
- [Four-Layer Design](docs/architecture/four-layer-design.md) - Core pattern
- [Neovim Analysis](docs/architecture/neovim-analysis.md) - Design inspiration

**API Reference**:
- [API Quick Reference](docs/api/quick-reference.md) - Fast lookup
- [vim.opt Reference](docs/api/vim-opt.md) - Editor options
- [TypeScript Types](docs/api/typescript-types.md) - Type definitions

**Contributing**:
- [Development Guide](docs/development/) - Setup and workflow
- [Implementation Roadmap](docs/roadmap/) - What to work on
- [Contributing Guidelines](docs/development/contributing.md) - How to contribute

**Research & Background**:
- [Neovim Analysis Summary](docs/research/neovim-analysis-summary.md) - Research overview
- [Design Decisions](docs/architecture/design-decisions.md) - Why we made choices

---

## 🏗️ Architecture

OpenVim follows a **four-layer architecture**:

```
┌─────────────────────────────────────────────────────┐
│  Layer 4: User Configuration (init.js)              │
│  - User's ~/.config/openvim/init.js                 │
│  - JavaScript/TypeScript for maximum flexibility     │
└─────────────────────────────────────────────────────┘
                        ↓↑
┌─────────────────────────────────────────────────────┐
│  Layer 3: JavaScript API (vim.*)                    │
│  - vim.api.* (Core Neovim API)                      │
│  - vim.opt.* (Ergonomic options)                    │
│  - vim.keymap.* (Key mappings)                      │
│  - Full TypeScript type definitions                 │
└─────────────────────────────────────────────────────┘
                        ↓↑
┌─────────────────────────────────────────────────────┐
│  Layer 2: JSI Bridge (Zero-copy)                    │
│  - Hermes C API wrapper (hermes_c_api.cpp)          │
│  - Zig FFI bindings (src/jsi/hermes.zig)           │
│  - Direct function calls, no serialization         │
└─────────────────────────────────────────────────────┘
                        ↓↑
┌─────────────────────────────────────────────────────┐
│  Layer 1: Editor Core (Zig)                         │
│  - Buffer management, rendering, input handling     │
│  - Performance-critical operations                  │
│  - Direct hardware access                           │
└─────────────────────────────────────────────────────┘
```

See [Architecture Documentation](docs/architecture/) for details.

---

## 💡 Why OpenVim?

### vs Neovim

| Feature | Neovim | OpenVim |
|---------|--------|---------|
| **Core Language** | C | Zig |
| **Plugin Language** | Lua | JavaScript/TypeScript |
| **Startup Time** | ~150ms | < 100ms (target) |
| **Hot Reload** | Plugin-based | Built-in |
| **Type System** | Runtime hints | TypeScript native |
| **API** | 150+ functions | Compatible 150+ |

### Advantages

- **Faster Startup**: Hermes bytecode vs Lua interpreter
- **Better Hot Reload**: Native support, no plugins needed
- **Modern Stack**: Zig + JavaScript with full IDE support
- **Larger Ecosystem**: More developers know JavaScript
- **Zero-Copy Bridge**: JSI enables direct Zig ↔ JS calls

### Compatibility

OpenVim replicates Neovim's API for easy migration:
- Same `vim.api.*` functions
- Similar `vim.opt`, `vim.keymap` interfaces
- Compatible autocommand system (Phase 4)
- Easy config porting (Lua → JavaScript)

---

## 🎓 Development

### Project Status

- ✅ **Phase 1+2**: Text display & navigation (Complete)
- 🚧 **Phase 3**: Text editing operators (Next, 4-6 weeks)
- 📅 **Phase 4**: Plugin system (6-8 weeks)
- 📅 **Phase 5+**: Advanced features (8+ weeks)

See [Implementation Roadmap](docs/roadmap/implementation-roadmap.md) for complete timeline.

### Contributing

We welcome contributions! Here's how to get started:

1. **Pick a Task**: Check [Roadmap](docs/roadmap/) for current work
2. **Read Docs**: See [Development Guide](docs/development/)
3. **Submit PR**: Follow [Contributing Guidelines](docs/development/contributing.md)

**Priority Areas (Phase 3)**:
- Delete operators (x, dd, dw, d{motion})
- Change operators (c, cc, cw, c{motion})
- Yank/paste & registers
- Undo/redo system
- Visual mode operators

### Tech Stack

- **Core**: Zig 0.13+ (systems programming language)
- **Runtime**: Hermes (React Native's JS engine)
- **Bridge**: JSI (JavaScript Interface for zero-copy)
- **Types**: TypeScript (full IDE support)

### Build Requirements

- Zig 0.13 or later
- Git (for submodules)
- C++ compiler (clang++, for Hermes integration)
- Node.js (optional, for TypeScript config)

See [Building OpenVim](docs/development/building.md) for complete instructions.

---

## 📊 Project Statistics

- **Core Code**: ~5,000 lines of Zig (Phase 1+2)
- **Documentation**: 25+ documents, 15,000+ lines
- **TypeScript Types**: 1,091 lines (v0.3.0)
- **API Coverage**: 150+ functions typed
- **Development Time**: Active since October 2024

---

## 🔗 Links

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/yourusername/openvim/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/openvim/discussions)

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Neovim**: For API design and inspiration
- **Hermes**: For fast, lightweight JavaScript runtime
- **Zig**: For modern systems programming language
- **Helix**: For design patterns and reference
- **Ghostty**: For Zig best practices

---

## 🗺️ Roadmap Summary

| Phase | Status | Timeline | Features |
|-------|--------|----------|----------|
| 1+2 | ✅ Complete | Done | Display, navigation, basic config |
| 3 | 🚧 Next | 4-6 weeks | Text editing operators |
| 4 | 📅 Planned | 6-8 weeks | Plugin system, full vim.opt |
| 5+ | 📅 Future | 8+ weeks | LSP, Tree-sitter, advanced features |

**Goal**: Full Neovim API parity in 6-12 months

---

## 💬 Contact

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and community discussion

---

**Happy coding! 🚀**

For detailed documentation, visit [docs/](docs/)
