# Vimcraft

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.13+-orange)](https://ziglang.org)

Neovim-compatible text editor built in [Zig](https://ziglang.org/) with [Hermes](https://hermesengine.dev/) JavaScript engine. Designed for building AI-powered development tools with TypeScript/JavaScript plugins using [JSI](https://github.com/react-native-community/discussions-and-proposals/issues/91) zero-copy integration.

## Installation

**Requirements**: [Zig](https://ziglang.org/) 0.13+, Git, C++ compiler (clang++)

```bash
git clone git@github.com:vimcraft-labs/vimcraft.git
cd vimcraft
git submodule update --init
zig build
./zig-out/bin/vc myfile.txt
```

## Configuration

Create `~/.config/vimcraft/init.js` with Neovim-compatible API:

```javascript
vim.opt.cursorLine = true;
vim.opt.number = true;

vim.highlight('Comment', {
  fg: '#6c6c6c',
  italic: true
});
```

Changes apply instantly with built-in hot reload. See [Configuration Guide](docs/guides/configuration.md) for the full API.

## Architecture

Four-layer design with zero-copy JSI bridge:

```
User Configuration (init.js)
    ↓↑ JSI (zero-copy)
JavaScript API (vim.*)
    ↓↑ JSI Bridge
Hermes Runtime
    ↓↑ C API
Editor Core (Zig)
```

**[JSI (JavaScript Interface)](https://github.com/react-native-community/discussions-and-proposals/issues/91)**: Direct native ↔ JavaScript calls without serialization. Synchronous execution with pointer-based parameters.

**[Hermes Engine](https://hermesengine.dev/)**: Ahead-of-time bytecode compilation for fast startup. From React Native.

**[Zig](https://ziglang.org/)**: Systems language with compile-time safety and C interoperability.

See [Architecture Documentation](docs/architecture/) for implementation details.

## Project Status

**Working**:
- Vim navigation (hjkl, w/b/e, gg/G, 0/$, f/F/t/T)
- Text editing (insert, delete, change, yank/paste)
- Visual mode (character, line, block)
- Registers and clipboard
- Undo/redo (tree-based)
- Configuration API (vim.opt, vim.highlight)
- Hot reload
- Chrome DevTools debugging (`--debug`)

**In Development**:
- Plugin system (vim.keymap, autocommands)
- [LSP](https://microsoft.github.io/language-server-protocol/) integration
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/) syntax

See [Roadmap](docs/roadmap/) for details.

## Building from Source

```bash
# Build
zig build

# Run tests
zig build test

# Format code
zig fmt src/

# Build Hermes (if needed)
cd vendor/hermes && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -GNinja
ninja hermes hermesc
```

## Documentation

- **[Getting Started](docs/guides/getting-started.md)** - Installation and first run
- **[Configuration Guide](docs/guides/configuration.md)** - API reference
- **[Development Guide](docs/development/)** - Contributing guidelines
- **[Architecture](docs/architecture/)** - System design
- **[Roadmap](docs/roadmap/)** - Implementation plan

Full documentation: [docs/](docs/)

## Contributing

1. Check [issues](https://github.com/vimcraft-labs/vimcraft/issues) or [roadmap](docs/roadmap/)
2. Read [Development Guide](docs/development/)
3. Submit PR following [Contributing Guidelines](docs/development/contributing.md)

Good first issues: Look for `good-first-issue` label.

## Project Layout

```
src/
├── editor/           # Core editor (buffer, cursor, modes)
├── backends/         # Rendering backends (terminal, debug)
├── system/           # System integration (JSI, event loop)
└── tools/            # Development tools
```

## License

MIT License - see [LICENSE](LICENSE)

## Acknowledgments

- [Neovim](https://neovim.io/) - API design and architecture
- [Hermes](https://hermesengine.dev/) - JavaScript runtime (React Native)
- [Zig](https://ziglang.org/) - Systems programming language
- [Helix](https://helix-editor.com/) - Terminal rendering patterns
- [Ghostty](https://ghostty.org/) - Zig best practices
