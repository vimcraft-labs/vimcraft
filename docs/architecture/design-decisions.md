# Design Decisions

Why we made certain technical choices in OpenVim.

---

## Language Choices

### Why Zig for Core?

**Chosen**: Zig
**Alternatives**: C, C++, Rust

**Reasons**:
- Simpler than C++, more control than Rust
- Excellent C interop (for Hermes)
- Fast compile times
- No hidden allocations
- Safety without runtime cost

### Why JavaScript for Plugins?

**Chosen**: JavaScript/TypeScript
**Alternatives**: Lua, Python

**Reasons**:
- Larger developer base
- Better tooling (TypeScript, IDEs)
- Rich ecosystem (npm)
- Hermes is fast and small
- Easy async/await

---

## Runtime Selection

### Why Hermes?

**Chosen**: Hermes
**Alternatives**: V8, JavaScriptCore, Lua

**Reasons**:
- Ahead-of-time bytecode compilation
- Small memory footprint
- Fast startup
- JSI for zero-copy bridge
- Mobile-optimized (React Native)

---

## API Design

### Why Replicate Neovim's API?

**Decision**: Match Neovim API exactly

**Reasons**:
- 10+ years of proven design
- Large existing user base
- Plugin portability
- Clear migration path
- Well-documented

### Why Add Ergonomic Wrappers?

**Decision**: Both vim.api.* AND vim.opt, vim.keymap

**Reasons**:
- Beginners want simple
- Power users want control
- Best of both worlds

---

See [Neovim Analysis](./neovim-analysis.md) for research that informed these decisions.
