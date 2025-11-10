# OpenVim Documentation

**Version**: 0.3.0
**Last Updated**: November 3, 2025
**Current Phase**: Phase 1+2 Complete, Phase 3 Ready

Welcome to OpenVim documentation! This is your entry point to all project documentation, organized by purpose and audience.

---

## 📖 Quick Navigation

### New to OpenVim?
👉 Start here: [Getting Started Guide](./guides/getting-started.md)

### Want to understand the design?
👉 Read: [Architecture Overview](./architecture/)

### Ready to implement features?
👉 Check: [Implementation Roadmap](./roadmap/)

### Need API reference?
👉 Look at: [API Documentation](./api/)

### Contributing to the project?
👉 See: [Development Guide](./development/)

---

## 📚 Documentation Categories

### 🎯 [Guides](./guides/)
**For**: New users and contributors
**Purpose**: Get started quickly, understand core concepts

- [Getting Started](./guides/getting-started.md) - Installation and first steps
- [Configuration Guide](./guides/configuration.md) - How to configure OpenVim
- [TypeScript Guide](./guides/typescript-setup.md) - Using TypeScript for config

### 🏗️ [Architecture](./architecture/)
**For**: Developers wanting to understand the system design
**Purpose**: Deep technical understanding of OpenVim's architecture

- [Overview](./architecture/README.md) - Architecture summary
- [Four-Layer Design](./architecture/four-layer-design.md) - Core architectural pattern
- [Neovim Analysis](./architecture/neovim-analysis.md) - Deep dive into Neovim's design
- [Design Decisions](./architecture/design-decisions.md) - Why we made certain choices

### 🔌 [API Documentation](./api/)
**For**: Plugin developers and advanced users
**Purpose**: Complete API reference for configuration and plugins

- [Quick Reference](./api/quick-reference.md) - Fast lookup while coding
- [vim.api Reference](./api/vim-api.md) - Core API functions (nvim_*)
- [vim.opt Reference](./api/vim-opt.md) - Editor options
- [vim.keymap Reference](./api/vim-keymap.md) - Key mapping system
- [TypeScript Types](./api/typescript-types.md) - Type definitions guide

### 🗺️ [Roadmap](./roadmap/)
**For**: Contributors and project planners
**Purpose**: Implementation plan and future direction

- [Overview](./roadmap/README.md) - Roadmap summary
- [Implementation Roadmap](./roadmap/implementation-roadmap.md) - Complete roadmap
- [Phase 3: Text Editing](./roadmap/phase-3-text-editing.md) - Next milestone
- [Phase 4: Plugin System](./roadmap/phase-4-plugin-system.md) - Future milestone
- [Phase 5+: Advanced Features](./roadmap/phase-5-advanced.md) - Long-term goals

### 🔬 [Research](./research/)
**For**: Understanding Neovim compatibility and design choices
**Purpose**: Background research that informed OpenVim's design

- [Neovim Analysis Summary](./research/neovim-analysis-summary.md) - Executive summary
- [Neovim Mimic Summary](./research/neovim-mimic-summary.md) - What we accomplished
- [Research Index](./research/README.md) - All research documents

### 💻 [Development](./development/)
**For**: Contributors working on OpenVim
**Purpose**: Development workflow, testing, code organization

- [Development Guide](./development/README.md) - Start here for contributing
- [Building OpenVim](./development/building.md) - Build instructions
- [Testing Guide](./development/testing.md) - How to test changes
- [Code Organization](./development/code-organization.md) - Project structure
- [Contributing Guidelines](./development/contributing.md) - How to contribute

---

## 🎯 Documentation by Use Case

### "I want to use OpenVim"

1. [Getting Started Guide](./guides/getting-started.md) - Install and run
2. [Configuration Guide](./guides/configuration.md) - Customize your setup
3. [API Quick Reference](./api/quick-reference.md) - Available features

### "I want to understand how OpenVim works"

1. [Architecture Overview](./architecture/README.md) - Big picture
2. [Four-Layer Design](./architecture/four-layer-design.md) - Core pattern
3. [Neovim Analysis](./architecture/neovim-analysis.md) - Design inspiration

### "I want to write a plugin"

1. [TypeScript Types](./api/typescript-types.md) - Type definitions
2. [vim.api Reference](./api/vim-api.md) - Available functions
3. [Configuration Guide](./guides/configuration.md) - Plugin loading

### "I want to contribute code"

1. [Development Guide](./development/README.md) - Development setup
2. [Implementation Roadmap](./roadmap/implementation-roadmap.md) - What to work on
3. [Code Organization](./development/code-organization.md) - Where code goes
4. [Contributing Guidelines](./development/contributing.md) - Contribution process

### "I'm migrating from Neovim"

1. [Neovim Mimic Summary](./research/neovim-mimic-summary.md) - Compatibility overview
2. [API Quick Reference](./api/quick-reference.md) - API comparison
3. [Configuration Guide](./guides/configuration.md) - Porting your config

---

## 📊 Project Status

### ✅ Completed (Phase 1+2)
- Text display and file loading
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert/Visual)
- Terminal rendering
- Hermes+JSI integration
- Hot reload system
- Basic configuration API

### 🚧 In Progress (Phase 3)
- Delete operators (x, dd, dw, d{motion})
- Change operators (c, cc, cw, c{motion})
- Yank/paste & registers
- Undo/redo system
- Visual mode operators

### 📅 Planned (Phase 4+)
- vim.opt full implementation
- vim.keymap system
- Autocommand system
- User commands
- LSP integration
- Tree-sitter syntax highlighting

See [Implementation Roadmap](./roadmap/implementation-roadmap.md) for complete details.

---

## 🔍 Quick Reference by Topic

### Core Concepts
- [Four-Layer Architecture](./architecture/four-layer-design.md)
- [JSI Bridge](./architecture/four-layer-design.md#layer-2-jsi-bridge)
- [Hot Reload](./guides/configuration.md#hot-reload)

### Configuration
- [init.js Setup](./guides/configuration.md#init-js)
- [vim.opt Options](./api/vim-opt.md)
- [Highlight Groups](./api/vim-api.md#highlight-functions)
- [TypeScript Config](./guides/typescript-setup.md)

### Development
- [Build Commands](./development/building.md)
- [Project Structure](./development/code-organization.md)
- [Testing](./development/testing.md)
- [Phase 3 Tasks](./roadmap/phase-3-text-editing.md)

### API Reference
- [Core API (vim.api.*)](./api/vim-api.md)
- [Options (vim.opt.*)](./api/vim-opt.md)
- [Keymap (vim.keymap.*)](./api/vim-keymap.md)
- [TypeScript Types](./api/typescript-types.md)

---

## 📦 Document Index (Alphabetical)

| Document | Category | Purpose |
|----------|----------|---------|
| [API Quick Reference](./api/quick-reference.md) | API | Fast lookup while coding |
| [Architecture Overview](./architecture/README.md) | Architecture | System design overview |
| [Building OpenVim](./development/building.md) | Development | Build instructions |
| [Code Organization](./development/code-organization.md) | Development | Project structure |
| [Configuration Guide](./guides/configuration.md) | Guides | How to configure |
| [Contributing Guidelines](./development/contributing.md) | Development | How to contribute |
| [Design Decisions](./architecture/design-decisions.md) | Architecture | Why we made choices |
| [Development Guide](./development/README.md) | Development | Contributing setup |
| [Four-Layer Design](./architecture/four-layer-design.md) | Architecture | Core pattern |
| [Getting Started](./guides/getting-started.md) | Guides | Installation and first steps |
| [Implementation Roadmap](./roadmap/implementation-roadmap.md) | Roadmap | Complete implementation plan |
| [Neovim Analysis](./architecture/neovim-analysis.md) | Architecture | Deep Neovim analysis |
| [Neovim Analysis Summary](./research/neovim-analysis-summary.md) | Research | Executive summary |
| [Neovim Mimic Summary](./research/neovim-mimic-summary.md) | Research | Compatibility work done |
| [Phase 3: Text Editing](./roadmap/phase-3-text-editing.md) | Roadmap | Next milestone |
| [Phase 4: Plugin System](./roadmap/phase-4-plugin-system.md) | Roadmap | Future milestone |
| [Phase 5+: Advanced](./roadmap/phase-5-advanced.md) | Roadmap | Long-term goals |
| [Testing Guide](./development/testing.md) | Development | How to test |
| [TypeScript Guide](./guides/typescript-setup.md) | Guides | TypeScript setup |
| [TypeScript Types](./api/typescript-types.md) | API | Type definitions |
| [vim.api Reference](./api/vim-api.md) | API | Core API functions |
| [vim.keymap Reference](./api/vim-keymap.md) | API | Key mapping system |
| [vim.opt Reference](./api/vim-opt.md) | API | Editor options |

---

## 🆘 Need Help?

### Common Questions

**Q: Where do I start?**
A: See [Getting Started Guide](./guides/getting-started.md)

**Q: How do I configure OpenVim?**
A: See [Configuration Guide](./guides/configuration.md)

**Q: What features are available?**
A: See [Project Status](#-project-status) above or [API Quick Reference](./api/quick-reference.md)

**Q: How can I contribute?**
A: See [Development Guide](./development/README.md) and [Contributing Guidelines](./development/contributing.md)

**Q: How is OpenVim different from Neovim?**
A: See [Neovim Mimic Summary](./research/neovim-mimic-summary.md)

**Q: What's the implementation plan?**
A: See [Implementation Roadmap](./roadmap/implementation-roadmap.md)

### More Resources

- **GitHub Issues**: [Report bugs or request features](https://github.com/vimcraft-labs/vimcraft/issues)
- **Project README**: [Root README.md](../README.md)
- **CLAUDE.md**: [Project context for AI assistants](../CLAUDE.md)

---

## 📝 Contributing to Documentation

Found an error or want to improve docs?

1. Check [Contributing Guidelines](./development/contributing.md)
2. Documentation source is in `docs/` directory
3. Use markdown format
4. Update this index if adding new documents
5. Submit a pull request

---

## 📅 Documentation Roadmap

### Planned Documentation

- [ ] Plugin development tutorial
- [ ] Performance optimization guide
- [ ] Debugging guide
- [ ] LSP integration guide (Phase 5)
- [ ] Tree-sitter guide (Phase 5)
- [ ] Advanced configuration examples
- [ ] Migration guide from Neovim
- [ ] Video tutorials

---

**Happy coding! 🚀**

For the latest updates, see [Implementation Roadmap](./roadmap/implementation-roadmap.md)
