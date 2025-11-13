# Getting Started with Vimcraft

Quick guide to installing and running Vimcraft for the first time.

---

## Prerequisites

- **Zig**: Version 0.13 or later
- **Git**: For cloning and submodules
- **C++ Compiler**: clang++ (for Hermes integration)
- **Node.js**: Optional, for TypeScript config

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/vimcraft-labs/vimcraft
cd vimcraft
```

### 2. Initialize Submodules

```bash
git submodule update --init
```

This downloads the Hermes JavaScript engine.

### 3. Build Vimcraft

```bash
zig build
```

The binary will be at `./zig-out/bin/vimcraft`.

---

## First Run

### Open a File

```bash
./zig-out/bin/vimcraft README.md
```

### Basic Navigation

- **hjkl** - Move cursor (left/down/up/right)
- **w/b/e** - Word motions (forward/backward/end)
- **gg/G** - Go to start/end of file
- **0/$** - Go to start/end of line
- **Ctrl+D/U** - Scroll half page down/up

### Exit

- **q** - Quit (in Normal mode)
- **ESC** - Return to Normal mode

---

## Creating Your Configuration

### 1. Create Config Directory

```bash
mkdir -p ~/.config/vimcraft
```

### 2. Create init.js

```bash
cat > ~/.config/vimcraft/init.js << 'ENDJS'
// Basic Vimcraft configuration
vim.opt.cursorLine = true;
console.log('✅ Vimcraft ready!');
ENDJS
```

### 3. Run Vimcraft

Config loads automatically:

```bash
./zig-out/bin/vimcraft README.md
```

---

## Next Steps

- Read [Configuration Guide](./configuration.md) for customization
- See [TypeScript Setup](./typescript-setup.md) for IDE autocomplete
- Check [API Quick Reference](../api/quick-reference.md) for available features

---

## Troubleshooting

### "zig: command not found"

Install Zig from [ziglang.org](https://ziglang.org/download/)

### "Submodule not initialized"

Run: `git submodule update --init`

### Config not loading

Check file location: `~/.config/vimcraft/init.js`

---

**Status**: Phase 1+2 Complete
**Available Features**: Display, navigation, basic config
**Coming Soon**: Text editing (Phase 3)
