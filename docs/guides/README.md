# Guides & Tutorials

Step-by-step guides to get started with OpenVim.

---

## 📖 Overview

This section contains practical guides for users and developers getting started with OpenVim. Whether you're configuring the editor for the first time or setting up a development environment, these guides will help you.

---

## 📚 Documents in This Category

### [Getting Started](./getting-started.md) ⭐ START HERE
**Purpose**: Install OpenVim and run your first session
**Read if**: You're new to OpenVim
**Key topics**:
- Installation requirements
- Building from source
- Running OpenVim
- Basic usage
- First configuration

### [Configuration Guide](./configuration.md)
**Purpose**: Learn how to configure OpenVim
**Read if**: You want to customize your setup
**Key topics**:
- init.js structure
- Setting options (vim.opt)
- Creating keymaps (vim.keymap)
- Highlight customization
- Hot reload
- Configuration patterns

### [TypeScript Setup](./typescript-setup.md)
**Purpose**: Set up TypeScript for config files
**Read if**: You want IDE autocomplete and type checking
**Key topics**:
- Installing @openvim/types
- Configuring tsconfig.json
- Using types in init.ts
- IDE integration
- Type examples
- Troubleshooting

---

## 🎯 Quick Start (5 Minutes)

### Install & Run

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

### Create Basic Config

```bash
# Create config directory
mkdir -p ~/.config/openvim

# Create init.js
cat > ~/.config/openvim/init.js << 'EOF'
// Basic OpenVim configuration
vim.opt.cursorLine = true;
console.log('OpenVim ready!');
EOF

# Run OpenVim (config loads automatically)
./zig-out/bin/openvim README.md
```

See: [Getting Started Guide](./getting-started.md) for complete instructions.

---

## 📖 Learning Path

### Level 1: Basic Usage (30 minutes)

1. **Install OpenVim**
   - [Getting Started](./getting-started.md) - Installation
   - Build and run for the first time
   - Navigate a file

2. **Basic Configuration**
   - [Configuration Guide](./configuration.md) - Basics
   - Create init.js
   - Set a few options
   - Test hot reload

3. **Essential Commands**
   - Learn hjkl navigation
   - Practice w/b/e (word motions)
   - Try gg/G (file start/end)
   - Use Ctrl+D/U (scroll)

### Level 2: Customization (1-2 hours)

1. **TypeScript Setup**
   - [TypeScript Setup](./typescript-setup.md)
   - Install @openvim/types
   - Configure IDE
   - Get autocomplete working

2. **Advanced Configuration**
   - [Configuration Guide](./configuration.md) - Advanced
   - Customize highlights
   - Set multiple options
   - Organize config structure

3. **Understand the API**
   - [API Quick Reference](../api/quick-reference.md)
   - Learn vim.opt.*
   - Learn vim.highlight()
   - Learn vim.g variables

### Level 3: Development (2-4 hours)

1. **Build System**
   - [Building OpenVim](../development/building.md)
   - Understand build process
   - Development workflow
   - Testing changes

2. **Plugin Development**
   - Study [API Documentation](../api/)
   - Write custom functions
   - Use autocommands (Phase 4)
   - Create user commands (Phase 4)

3. **Contributing**
   - [Contributing Guidelines](../development/contributing.md)
   - [Implementation Roadmap](../roadmap/)
   - Pick a task
   - Submit PR

---

## 🔍 Quick Links by Topic

### Installation
- [Requirements](./getting-started.md#requirements)
- [Building from Source](./getting-started.md#building)
- [Running OpenVim](./getting-started.md#running)
- [First Steps](./getting-started.md#first-steps)

### Configuration
- [init.js Setup](./configuration.md#init-js)
- [Options](./configuration.md#options)
- [Highlights](./configuration.md#highlights)
- [Hot Reload](./configuration.md#hot-reload)
- [Examples](./configuration.md#examples)

### TypeScript
- [Installation](./typescript-setup.md#installation)
- [tsconfig.json](./typescript-setup.md#tsconfig)
- [IDE Setup](./typescript-setup.md#ide-setup)
- [Type Examples](./typescript-setup.md#examples)

### Navigation
- [Basic Motions](./getting-started.md#navigation)
- [Word Motions](./getting-started.md#word-motions)
- [File Motions](./getting-started.md#file-motions)
- [Scrolling](./getting-started.md#scrolling)

---

## 💡 Common Tasks

### "I want to change how OpenVim looks"

```typescript
// ~/.config/openvim/init.ts
const colors = {
  bg: '#1e1e1e',
  fg: '#d4d4d4',
  blue: '#61afef',
};

vim.highlight('CursorLine', { bg: colors.bg });
vim.highlight('LineNr', { fg: colors.fg });
vim.highlight('Function', { fg: colors.blue, bold: true });
```

See: [Configuration Guide - Highlights](./configuration.md#highlights)

### "I want to customize editor behavior"

```typescript
// ~/.config/openvim/init.ts
vim.opt.number = true;
vim.opt.relativeNumber = true;
vim.opt.cursorLine = true;
vim.opt.tabStop = 4;
vim.opt.expandTab = true;
```

See: [Configuration Guide - Options](./configuration.md#options)

### "I want IDE autocomplete for config"

```bash
# Install types package
npm install --save-dev ./packages/types

# Create tsconfig.json
# (See TypeScript Setup guide)

# Write config in init.ts
# Get full autocomplete!
```

See: [TypeScript Setup Guide](./typescript-setup.md)

### "I want to contribute"

1. Read [Getting Started](./getting-started.md) - Build OpenVim
2. Read [Development Guide](../development/README.md) - Setup
3. Check [Roadmap](../roadmap/) - Pick a task
4. Follow [Contributing Guidelines](../development/contributing.md)

---

## 🎓 Video Tutorials (Planned)

Coming soon:
- [ ] Installation and first run
- [ ] Basic configuration walkthrough
- [ ] TypeScript setup guide
- [ ] Creating your first plugin
- [ ] Contributing to OpenVim

---

## 🔗 Related Documentation

- [API Documentation](../api/) - Complete API reference
- [Architecture](../architecture/) - Understanding the system
- [Development](../development/) - Contributing code
- [Roadmap](../roadmap/) - What's coming next

---

## 🆘 Troubleshooting

### Common Issues

**Q: Build fails with "zig: command not found"**
A: Install Zig 0.13+ from [ziglang.org](https://ziglang.org)

**Q: "Hermes submodule not initialized"**
A: Run `git submodule update --init`

**Q: Config file not loading**
A: Check location: `~/.config/openvim/init.js`

**Q: TypeScript errors in init.ts**
A: Install types: `npm install --save-dev ./packages/types`

**Q: Hot reload not working**
A: Currently works on file save, check console for errors

See: [Getting Started - Troubleshooting](./getting-started.md#troubleshooting)

---

## 📝 Contributing to Guides

Found something unclear or want to add a tutorial?

1. Check existing guides
2. Add clarifications or new sections
3. Include code examples
4. Test instructions on fresh setup
5. Update this index

**Guide Template**:
```markdown
# Guide Title

Brief description of what this guide covers.

## Prerequisites
- List requirements
- Link to prior guides

## Step 1: First Step
Detailed instructions with examples

## Step 2: Second Step
More instructions

## Troubleshooting
Common issues and solutions

## Next Steps
Where to go from here
```

---

**Last Updated**: November 3, 2025
**Current Status**: Basic guides complete, more tutorials planned
