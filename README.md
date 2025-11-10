# Vimcraft

**AI-Native Editor Built in Zig**

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.13+-orange)](https://ziglang.org)

Neovim-compatible with metal speed. Zig + Hermes/JSI for instant performance, TypeScript for powerful plugins. The proven Neovim architecture meets modern AI workflows—no vendor lock-in.

---

## Vision

Vimcraft is built for agentic AI development from the ground up. Unlike traditional editors that bolt on AI features as an afterthought, every aspect of Vimcraft is designed to support AI-powered workflows.

**Create custom AI agents. Build intelligent code assistants. Implement autonomous development tools**—all without waiting for vendor updates or fighting against the editor's architecture.

---

## Why Vimcraft?

### 🤖 AI-Native Workflows

Built for AI-powered development from day one. Create custom agents, intelligent assistants, and autonomous tools. No vendor lock-in, no waiting for feature releases—just pure creative freedom with TypeScript and proven Neovim APIs.

### ⚡ Metal Speed

Zig core + Hermes JSI delivers instant startup and zero-latency interactions. The Hermes engine (from React Native) provides a blazing-fast JavaScript runtime, while JSI enables direct Zig ↔ TypeScript communication with zero serialization overhead.

### 🛠️ Neovim + TypeScript

Battle-tested Neovim architecture with proven APIs you trust. Your muscle memory stays intact with full Neovim compatibility. Use TypeScript you know—with hot reload, Chrome debugger, and the entire ecosystem—to design your Editor + AI workflow.

---

## Quick Start

### Installation

```bash
# Clone the repository
git clone git@github.com:vimcraft-labs/vimcraft.git
cd vimcraft

# Initialize Hermes submodule
git submodule update --init

# Build Vimcraft
zig build

# Run
./zig-out/bin/openvim myfile.txt
```

**Requirements**: Zig 0.13+, Git, C++ compiler (clang++)

See [Getting Started Guide](docs/guides/getting-started.md) for detailed instructions.

### Configuration

Create `~/.config/openvim/init.js`:

```javascript
// Neovim-compatible API
vim.opt.cursorLine = true;
vim.opt.number = true;

vim.highlight('Comment', {
  fg: '#6c6c6c',
  italic: true
});

console.log('✅ Vimcraft ready!');
```

With hot reload built-in, changes apply instantly on save. No plugins needed.

See [Configuration Guide](docs/guides/configuration.md) for the full API.

---

## Architecture

Vimcraft uses a **four-layer architecture** that separates concerns while maintaining zero-copy performance:

```
┌─────────────────────────────────────┐
│  User Configuration (init.js)      │  ← Your TypeScript/JavaScript
│  - Full IDE autocomplete            │
│  - Hot reload on save               │
└─────────────────────────────────────┘
              ↓↑ JSI (zero-copy)
┌─────────────────────────────────────┐
│  JavaScript API (vim.*)             │  ← Neovim-compatible
│  - vim.opt.* (Options)              │
│  - vim.api.* (Core API)             │
│  - vim.keymap.* (Keybindings)       │
└─────────────────────────────────────┘
              ↓↑ JSI Bridge
┌─────────────────────────────────────┐
│  Hermes Runtime                     │  ← React Native proven
│  - Bytecode compilation             │
│  - Instant startup                  │
└─────────────────────────────────────┘
              ↓↑ C API
┌─────────────────────────────────────┐
│  Editor Core (Zig)                  │  ← Metal performance
│  - Buffer management                │
│  - Rendering pipeline               │
│  - Input handling                   │
└─────────────────────────────────────┘
```

**Key Innovation**: JSI (JavaScript Interface) enables direct Zig ↔ TypeScript function calls with zero serialization. This is the same technology powering React Native's performance.

See [Architecture Documentation](docs/architecture/) for technical details.

---

## Current Status

Vimcraft is in active development with core functionality working:

**Available Now** ✅
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, f/F/t/T, etc.)
- Text editing (insert, delete, change, yank/paste)
- Visual mode (character, line, block selection)
- Mode system (Normal, Insert, Visual, Command)
- Registers and clipboard integration
- Undo/redo system
- Configuration API (vim.opt, vim.highlight)
- Hot reload (changes apply on save)
- Chrome DevTools debugging (with `--debug` flag)

**In Development** 🚧
- Plugin system (vim.keymap, autocommands)
- LSP integration
- Tree-sitter syntax highlighting
- Advanced Neovim API compatibility

See [Implementation Roadmap](docs/roadmap/) for complete details.

---

## Documentation

### For Users
- **[Getting Started](docs/guides/getting-started.md)** - Install and first run
- **[Configuration Guide](docs/guides/configuration.md)** - Full API reference
- **[TypeScript Setup](docs/guides/typescript-setup.md)** - IDE autocomplete

### For Developers
- **[Architecture Overview](docs/architecture/)** - System design
- **[Development Guide](docs/development/)** - Contributing
- **[API Reference](docs/api/)** - Function documentation

### Technical Deep Dives
- **[Four-Layer Design](docs/architecture/four-layer-design.md)** - Core pattern
- **[JSI Bridge](docs/architecture/)** - Zero-copy integration
- **[Neovim Analysis](docs/architecture/neovim-analysis.md)** - Design inspiration

**Full Documentation**: [docs/](docs/)

---

## Tech Stack

- **Core**: Zig 0.13+ (modern systems programming)
- **Runtime**: Hermes (React Native's JavaScript engine)
- **Bridge**: JSI (JavaScript Interface for zero-copy)
- **Config**: TypeScript/JavaScript (full IDE support)

This combination delivers Neovim compatibility with instant startup, hot reload, and the entire JavaScript ecosystem for plugins.

---

## Contributing

We welcome contributions! Vimcraft is built in public with transparent development.

**How to Contribute**:
1. Check [open issues](https://github.com/vimcraft-labs/vimcraft/issues) or [roadmap](docs/roadmap/)
2. Read the [Development Guide](docs/development/)
3. Submit a PR following [Contributing Guidelines](docs/development/contributing.md)

**Good First Issues**: Check issues labeled `good-first-issue` for beginner-friendly tasks.

---

## Community

- **Issues**: [github.com/vimcraft-labs/vimcraft/issues](https://github.com/vimcraft-labs/vimcraft/issues)
- **Discussions**: [github.com/vimcraft-labs/vimcraft/discussions](https://github.com/vimcraft-labs/vimcraft/discussions)

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Acknowledgments

Vimcraft builds on the shoulders of giants:

- **Neovim** - API design and architecture inspiration
- **Hermes** - Fast, proven JavaScript runtime from React Native
- **Zig** - Modern systems programming language
- **Helix** - Design patterns and terminal rendering
- **Ghostty** - Zig best practices and project structure

---

**Built for developers who refuse to compromise.**

For complete documentation, visit [docs/](docs/)
