# Development Guide

Contributing to OpenVim - setup, workflow, and guidelines.

---

## 📖 Overview

Welcome to OpenVim development! This guide will help you set up your development environment, understand the codebase, and contribute effectively.

**Tech Stack**:
- **Core**: Zig 0.13+ (systems programming)
- **Runtime**: Hermes JavaScript engine
- **Bridge**: JSI (JavaScript Interface)
- **Config**: JavaScript/TypeScript

---

## 📚 Documents in This Category

### [Building OpenVim](./building.md)
**Purpose**: Build system and development setup
**Read if**: You're setting up for the first time
**Key topics**:
- Requirements
- Build commands
- Development build vs production
- Hybrid build system (Zig + clang++)
- Troubleshooting build issues

### [Testing Guide](./testing.md)
**Purpose**: Testing strategy and commands
**Read if**: You're adding features or fixing bugs
**Key topics**:
- Unit tests (zig test)
- Integration tests
- End-to-end tests
- Test organization
- Writing new tests
- CI/CD pipeline

### [Code Organization](./code-organization.md)
**Purpose**: Project structure and module organization
**Read if**: You want to understand where code goes
**Key topics**:
- Directory structure
- Module responsibilities
- File naming conventions
- Import patterns
- Adding new modules

### [Contributing Guidelines](./contributing.md)
**Purpose**: How to contribute to OpenVim
**Read if**: You're ready to submit code
**Key topics**:
- Contribution workflow
- Code style
- Commit messages
- Pull request process
- Review process
- Community guidelines

---

## 🚀 Quick Start (15 Minutes)

### 1. Clone and Build

```bash
# Clone repository
git clone https://github.com/vimcraft-labs/vimcraft
cd vimcraft

# Initialize submodules
git submodule update --init

# Build OpenVim
zig build

# Run tests
zig build test

# Run OpenVim
./zig-out/bin/vimcraft README.md
```

### 2. Set Up Development Environment

```bash
# Install development tools
npm install

# Build TypeScript types
npm run build:config

# Watch for config changes
npm run watch:config &

# Run with hot reload
./zig-out/bin/vimcraft init.ts
```

### 3. Make Your First Change

```bash
# Create a branch
git checkout -b feature/my-feature

# Make changes to src/

# Build and test
zig build
zig build test

# Run manual test
./zig-out/bin/vimcraft test-file.txt

# Commit changes
git add .
git commit -m "feat: add my feature"

# Push and create PR
git push origin feature/my-feature
```

See: [Contributing Guidelines](./contributing.md) for complete workflow.

---

## 🗂️ Project Structure

```
vimcraft/
├── src/                        # Core editor (Zig)
│   ├── main.zig               # Entry point
│   ├── buffer/                # Text buffer management
│   ├── display/               # Terminal rendering
│   ├── mode/                  # Mode system (N/I/V)
│   ├── movement/              # Vim motions
│   ├── jsi/                   # JSI bridge (Zig + C++)
│   │   ├── hermes.zig        # Zig bindings
│   │   ├── hermes_c_api.cpp  # C++ wrapper
│   │   └── jsi_api.zig       # JavaScript API
│   ├── api/                   # NEW: Public API layer
│   ├── config/                # NEW: Configuration system
│   └── event/                 # NEW: Event system
├── packages/types/            # TypeScript types
│   └── src/index.d.ts        # Type definitions
├── docs/                      # Documentation
├── examples/                  # Hermes+JSI demos
├── vendor/                    # Git submodules
│   ├── hermes/               # Hermes engine
│   ├── neovim/               # Reference
│   ├── helix/                # Reference
│   └── ghostty/              # Reference
├── build.zig                 # Zig build system
├── Makefile.hermes          # Hermes+JSI build
├── init.ts                   # Example config
└── CLAUDE.md                 # Project context
```

See: [Code Organization](./code-organization.md) for details.

---

## 🎯 Development Workflow

### Daily Development

```bash
# Start with latest main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/my-feature

# Build and test iteratively
zig build && zig build test

# Run manual tests
./zig-out/bin/vimcraft test-file.txt

# Commit incrementally
git add .
git commit -m "feat: implement X"

# Push when ready
git push origin feature/my-feature
```

### Hot Reload Development

```bash
# Terminal 1: Watch TypeScript config
npm run watch:config

# Terminal 2: Run OpenVim
./zig-out/bin/vimcraft init.ts

# Edit init.ts
# Save file
# Config reloads automatically!
```

### Testing Workflow

```bash
# Run all tests
zig build test

# Run specific test
zig test src/buffer/buffer.zig

# Run integration tests
./test_vimcraft.sh

# Check for memory leaks (future)
zig build test -Doptimize=Debug
```

---

## 🔍 Finding Your Way Around

### "I want to add a new Vim motion"

**Module**: `src/movement/movement.zig`
**Pattern**: Study existing motions (w, b, e)
**Test**: Add unit tests in same file
**Reference**: [Roadmap - Phase 3](../roadmap/phase-3-text-editing.md)

### "I want to implement a vim.opt option"

**Module**: `src/config/options.zig` (Phase 4)
**Pattern**: Study cursorLine implementation
**Test**: Unit test + integration test
**Reference**: [Roadmap - Phase 4](../roadmap/phase-4-plugin-system.md)

### "I want to add a vim.api function"

**Module**: `src/api/` (create if needed)
**Files**:
- `src/api/api.zig` - Function implementation
- `src/jsi/jsi_api.zig` - JavaScript binding
**Test**: Integration test calling from JS
**Reference**: [API Documentation](../api/vim-api.md)

### "I want to fix a bug"

1. **Reproduce**: Write test that fails
2. **Locate**: Find relevant module
3. **Fix**: Make minimal change
4. **Test**: Verify test passes
5. **Verify**: Run full test suite

---

## 🎓 Learning Resources

### Understanding the Codebase

**Start here**:
1. [Architecture Overview](../architecture/) - Big picture
2. [Code Organization](./code-organization.md) - Where things are
3. [Neovim Analysis](../architecture/neovim-analysis.md) - Design reference

**Key files to study**:
- `src/main.zig` - Entry point and event loop
- `src/jsi/jsi_api.zig` - Zig ↔ JavaScript bridge
- `src/buffer/buffer.zig` - Text buffer structure
- `src/movement/movement.zig` - Movement primitives

### Zig Language

**Resources**:
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Learn](https://ziglearn.org/)
- Ghostty source (vendor/ghostty/) - Zig best practices

**Key concepts**:
- Allocators and memory management
- Error handling (try, catch, error unions)
- Comptime (compile-time execution)
- C interop (for Hermes integration)

### Hermes & JSI

**Resources**:
- `vendor/hermes/` - Hermes source
- `examples/` - Working JSI examples
- [JSI Documentation](https://github.com/facebook/hermes/tree/main/API/jsi)

**Key concepts**:
- Zero-copy function calls
- Type conversion at boundaries
- Host function registration
- Error propagation

---

## 📊 Code Style & Standards

### Zig Code

**Style**:
```zig
// Use 4-space indentation (Zig convention)
// Run `zig fmt` before committing
// snake_case for functions
// PascalCase for types

pub fn exampleFunction(allocator: Allocator, value: usize) !void {
    const buffer = try allocator.alloc(u8, value);
    defer allocator.free(buffer);
    // Implementation...
}
```

**Conventions**:
- Explicit error handling (no hidden errors)
- Allocators passed as parameters
- Defer for cleanup
- Const by default

See: [Contributing Guidelines - Code Style](./contributing.md#code-style)

### TypeScript/JavaScript

**Style**:
```typescript
// Use camelCase for variables and functions
// Use PascalCase for types and interfaces
// Use TypeScript for type safety

interface ExampleOptions {
  value: number;
  name: string;
}

function exampleFunction(opts: ExampleOptions): void {
  // Implementation...
}
```

**Conventions**:
- camelCase for vim.opt options (not snake_case)
- Avoid ! (non-null assertion) in types
- Document public APIs
- Use TypeScript for autocomplete

---

## 🧪 Testing Guidelines

### Unit Tests

```zig
// src/buffer/buffer.zig

test "buffer append line" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.appendLine("Hello, World!");
    try std.testing.expectEqual(@as(usize, 1), buffer.lineCount());
}
```

### Integration Tests

```typescript
// Test JavaScript → Zig interaction
vim.opt.cursorLine = true;
console.assert(vim.opt.cursorLine === true);
```

### Test Coverage

**Required**:
- All new functions have unit tests
- All bug fixes have regression tests
- Integration tests for API functions

**Optional**:
- Performance benchmarks
- Stress tests
- Property-based tests

See: [Testing Guide](./testing.md) for details.

---

## 📝 Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance

**Example**:
```
feat(movement): add word motion (w/b/e)

Implement forward word (w), backward word (b), and end of word (e)
motions following Vim semantics.

- Handle punctuation boundaries
- Skip consecutive whitespace
- Add unit tests for edge cases

Closes #123
```

See: [Contributing Guidelines - Commits](./contributing.md#commits)

---

## 🔗 Related Documentation

- [Architecture](../architecture/) - System design
- [API Documentation](../api/) - API reference
- [Roadmap](../roadmap/) - What to implement
- [Guides](../guides/) - User guides

---

## 🆘 Getting Help

### Documentation

1. Check relevant docs section
2. Search existing issues
3. Review reference codebases (neovim, helix, ghostty)

### Community

- **GitHub Discussions**: Ask questions
- **GitHub Issues**: Report bugs, request features
- **Pull Requests**: Get code review

### Common Questions

**Q: How do I add a new option to vim.opt?**
A: See [Roadmap - Phase 4](../roadmap/phase-4-plugin-system.md#vim-opt)

**Q: Where do I put new API functions?**
A: Create/add to `src/api/` directory

**Q: How do I test Zig ↔ JavaScript integration?**
A: See `examples/` for patterns, add integration tests

**Q: What coding standards should I follow?**
A: Run `zig fmt`, follow existing code patterns

---

## 🎯 Contribution Priorities

### High Priority (Phase 3)

- Delete operators (x, dd, dw, d{motion})
- Change operators (c, cc, cw, c{motion})
- Yank/paste & registers
- Undo/redo system
- Visual mode operators

See: [Roadmap - Phase 3](../roadmap/phase-3-text-editing.md)

### Medium Priority (Phase 4)

- vim.opt implementation
- vim.keymap system
- Autocommand system
- User commands

See: [Roadmap - Phase 4](../roadmap/phase-4-plugin-system.md)

### Future (Phase 5+)

- Search/replace
- LSP integration
- Tree-sitter
- Split windows

See: [Roadmap - Phase 5+](../roadmap/phase-5-advanced.md)

---

**Last Updated**: November 3, 2025
**Current Phase**: Phase 3 - Text Editing
**Contribution Status**: Open for PRs!
