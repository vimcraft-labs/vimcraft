# OpenVim Implementation Roadmap
## Neovim-Compatible Editor in Zig + JavaScript

**Version**: 1.0
**Date**: November 3, 2025
**Based On**: Neovim 0.12.0 API Analysis

---

## Executive Summary

OpenVim aims to create a **Neovim-compatible text editor** with:
- **Core**: Written in Zig (fast, safe systems programming)
- **Plugins**: JavaScript/TypeScript via Hermes engine
- **Bridge**: Zero-copy JSI integration
- **Goal**: Seamless migration for Neovim users with better startup performance

**Current Status**: Phase 1+2 Complete (Text display, Navigation)
**Next**: Phase 3 (Text editing operators)

---

## Grand Design

### Four-Layer Architecture

```
┌─────────────────────────────────────────────────────┐
│  Layer 4: User Configuration (init.js)              │
│  - User's ~/.config/openvim/init.js                 │
│  - Plugins loaded from plugin/**/*.js               │
│  - File-type plugins from ftplugin/**/*.js          │
└─────────────────────────────────────────────────────┘
                        ↓↑
┌─────────────────────────────────────────────────────┐
│  Layer 3: JavaScript API (vim.* global)             │
│  - vim.api.* (Core Neovim API)                      │
│  - vim.opt.* (Ergonomic options)                    │
│  - vim.keymap.* (Key mappings)                      │
│  - vim.diagnostic.* (LSP diagnostics)               │
│  - vim.g/b/w/t/v/env (Variable scopes)              │
└─────────────────────────────────────────────────────┘
                        ↓↑
┌─────────────────────────────────────────────────────┐
│  Layer 2: JSI Bridge (C++/Zig)                      │
│  - Hermes C API wrapper (hermes_c_api.cpp)          │
│  - Zig FFI bindings (src/jsi/hermes.zig)           │
│  - Zero-copy function calls                         │
│  - Type conversion at boundary                      │
└─────────────────────────────────────────────────────┘
                        ↓↑
┌─────────────────────────────────────────────────────┐
│  Layer 1: Editor Core (Zig)                         │
│  - Buffer management (src/buffer/)                  │
│  - Display rendering (src/display/)                 │
│  - Input handling (src/input/)                      │
│  - Mode system (src/mode/)                          │
│  - Movement primitives (src/movement/)              │
└─────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Neovim Compatibility First**: If it works in Neovim, it should work (or be easy to port) in OpenVim
2. **Performance Matters**: Zig core + Hermes bytecode = faster than Neovim's Lua
3. **Beautiful APIs**: Both ergonomic wrappers AND low-level API access
4. **Hot Reload Built-in**: Already working! Neovim doesn't have this natively
5. **Zero-Copy Bridge**: JSI enables direct Zig ↔ JavaScript calls

---

## Feature Status Matrix

### Phase 1+2: Text Display & Navigation ✅ COMPLETE

| Feature | Status | Notes |
|---------|--------|-------|
| Text display | ✅ Complete | ArrayList-based buffer |
| Terminal rendering | ✅ Complete | ANSI escape codes |
| Basic navigation (hjkl) | ✅ Complete | Character movement |
| Word motions (w/b/e) | ✅ Complete | Word boundaries |
| Line motions (0/$) | ✅ Complete | Start/end of line |
| File motions (gg/G) | ✅ Complete | First/last line |
| Scrolling (Ctrl+D/U) | ✅ Complete | Half page scroll |
| Mode system (N/I/V) | ✅ Complete | Normal, Insert, Visual |
| Status line | ✅ Complete | Shows mode and position |
| File loading | ✅ Complete | Read files from disk |

### Phase 3: Text Editing (Next - 4-6 weeks)

| Feature | Priority | Complexity | Est. Time |
|---------|----------|------------|-----------|
| **Delete Operators** | CRITICAL | Medium | 1 week |
| - x (delete char) | HIGH | Low | 2 days |
| - dd (delete line) | HIGH | Low | 2 days |
| - dw (delete word) | HIGH | Medium | 3 days |
| - d{motion} (general) | HIGH | Medium | 3 days |
| **Change Operators** | CRITICAL | Medium | 1 week |
| - c{motion} (change) | HIGH | Medium | 4 days |
| - cc (change line) | HIGH | Low | 2 days |
| - C (change to EOL) | HIGH | Low | 1 day |
| **Insert Operations** | CRITICAL | Medium | 1 week |
| - i/a (insert before/after) | ✅ Complete | - |
| - I/A (line start/end) | ✅ Complete | - |
| - o/O (open line) | HIGH | Medium | 3 days |
| - Character insertion | HIGH | Medium | 3 days |
| - Backspace/Delete | HIGH | Low | 1 day |
| **Yank/Paste** | HIGH | High | 1 week |
| - y{motion} (yank) | HIGH | Medium | 3 days |
| - yy (yank line) | HIGH | Low | 1 day |
| - p/P (paste after/before) | HIGH | Medium | 3 days |
| **Registers** | HIGH | Medium | 3 days |
| - Unnamed register ("") | HIGH | Low | 1 day |
| - Named registers (a-z) | MED | Medium | 2 days |
| **Undo/Redo** | CRITICAL | High | 1 week |
| - Undo tree structure | HIGH | High | 4 days |
| - u (undo) | HIGH | Medium | 2 days |
| - Ctrl+R (redo) | HIGH | Medium | 2 days |
| - Change transactions | HIGH | High | 3 days |
| **Visual Mode** | HIGH | Medium | 3 days |
| - Character visual | MED | Medium | 2 days |
| - Line visual (V) | MED | Low | 1 day |
| - Block visual (Ctrl+V) | LOW | High | (defer to Phase 5) |

**Phase 3 Total**: 4-6 weeks

### Phase 4: Plugin System (6-8 weeks)

| Feature | Priority | Complexity | Est. Time |
|---------|----------|------------|-----------|
| **vim.opt Interface** | CRITICAL | High | 2 weeks |
| - Options manager (Zig) | HIGH | High | 1 week |
| - vim.opt proxy (JS) | HIGH | Medium | 3 days |
| - vim.opt_local/opt_global | MED | Medium | 2 days |
| - Type conversion layer | HIGH | High | 3 days |
| **vim.api Core Functions** | CRITICAL | High | 2 weeks |
| - Buffer functions | HIGH | High | 1 week |
| - Window functions | MED | Medium | 3 days |
| - Option get/set | HIGH | Medium | 2 days |
| - Variable get/set | MED | Low | 2 days |
| **vim.keymap** | CRITICAL | High | 1 week |
| - Keymap registry (Zig) | HIGH | High | 4 days |
| - vim.keymap.set/del (JS) | HIGH | Medium | 2 days |
| - Mode-specific maps | HIGH | Medium | 2 days |
| **Autocommands** | HIGH | High | 2 weeks |
| - Event system (Zig) | HIGH | High | 1 week |
| - vim.api.nvim_create_autocmd | HIGH | Medium | 3 days |
| - Augroups | MED | Medium | 2 days |
| - Event firing | HIGH | High | 3 days |
| **User Commands** | MED | Medium | 1 week |
| - Command registry | MED | Medium | 3 days |
| - vim.api.nvim_create_user_command | MED | Medium | 3 days |
| - Argument parsing | MED | Low | 2 days |
| **vim.fn Bridge** | MED | Medium | 1 week |
| - Function call proxy | MED | Medium | 3 days |
| - Essential functions | MED | Medium | 4 days |

**Phase 4 Total**: 6-8 weeks

### Phase 5: Advanced Features (8-12 weeks)

| Feature | Priority | Complexity | Est. Time |
|---------|----------|------------|-----------|
| **Search/Replace** | HIGH | High | 2 weeks |
| - / and ? search | HIGH | High | 1 week |
| - n/N navigation | MED | Low | 2 days |
| - :s substitute | HIGH | Very High | 1 week |
| - Search highlighting | MED | Medium | 2 days |
| **Command Mode** | HIGH | High | 2 weeks |
| - : command parser | HIGH | High | 1 week |
| - Ex commands (:w, :q, :e) | HIGH | Medium | 1 week |
| - Range support | MED | High | 3 days |
| **Syntax Highlighting** | MED | Very High | 3 weeks |
| - Tree-sitter integration | MED | Very High | 2 weeks |
| - Highlight application | MED | High | 1 week |
| **Split Windows** | MED | Very High | 2 weeks |
| - Window management | MED | Very High | 1 week |
| - vsplit/hsplit | MED | High | 1 week |
| **Tab Pages** | LOW | High | 1 week |
| **Macros (q/@)** | MED | High | 1 week |
| **LSP Integration** | MED | Very High | 4 weeks |
| **Diagnostics** | MED | High | 2 weeks |

**Phase 5 Total**: 8-12 weeks

### Phase 6: Performance & Polish (Ongoing)

| Feature | Priority | Complexity |
|---------|----------|------------|
| Rope data structure | HIGH | Very High |
| Incremental rendering | HIGH | Very High |
| Large file handling (>100MB) | MED | High |
| Memory optimization | HIGH | High |
| Benchmark suite | HIGH | Medium |

### Phase 7: Neovim Compatibility (Ongoing)

| Feature | Priority | Complexity |
|---------|----------|------------|
| Neovim API compatibility layer | HIGH | High |
| Remote plugin support | LOW | Very High |
| Vimscript subset | LOW | Very High |

---

## Current Implementation Status

### What Works Today

**Editor Core**:
- ✅ Text buffer management (ArrayList-based)
- ✅ Terminal rendering with ANSI codes
- ✅ Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- ✅ Mode system (Normal/Insert/Visual)
- ✅ Status line display
- ✅ File loading

**JavaScript Integration**:
- ✅ Hermes engine integration
- ✅ JSI zero-copy bridge (demos working)
- ✅ console.log() to Chrome DevTools
- ✅ setTimeout/setInterval/clearTimeout/clearInterval
- ✅ Config hot reload (automatic on file save)
- ✅ vim.highlight() API
- ✅ vim.opt.cursorLine (basic implementation)
- ✅ vim.g/b/w/t/v/env variable scopes (stub)

**TypeScript Types**:
- ✅ @openvim/types package v0.3.0
- ✅ Full vim.api.* types (150+ functions)
- ✅ vim.opt interface (80+ options)
- ✅ vim.keymap types
- ✅ Autocommand types
- ✅ Diagnostic types
- ✅ IDE autocomplete support

### What's Missing (Priority Order)

**CRITICAL (Phase 3)**:
1. Delete operators (x, dd, dw, d{motion})
2. Change operators (c, cc, cw, c{motion})
3. Yank/paste (y, yy, p, P)
4. Undo/redo tree
5. Basic registers

**VERY HIGH (Phase 4)**:
1. vim.opt full implementation
2. vim.keymap.set/del
3. vim.api buffer functions
4. Autocommand system
5. Event firing

**HIGH (Phase 5)**:
1. Search and replace (/, ?, :s)
2. Command mode (: parser)
3. Ex commands (:w, :q, :e)
4. Tree-sitter syntax highlighting
5. vim.diagnostic implementation

---

## Implementation Guidelines

### Code Organization

```
src/
├── api/                    # NEW: Public API layer
│   ├── api.zig            # vim.api.* functions
│   ├── buffer.zig         # Buffer operations (nvim_buf_*)
│   ├── window.zig         # Window operations (nvim_win_*)
│   ├── keymap.zig         # Keymap operations (nvim_*keymap*)
│   ├── autocmd.zig        # Autocommand system
│   └── command.zig        # User commands
├── buffer/                 # EXISTING: Buffer management
│   ├── buffer.zig         # Core buffer structure
│   ├── line.zig           # Line operations
│   └── edit.zig           # NEW: Edit operations
├── config/                 # NEW: Configuration system
│   ├── options.zig        # Options manager
│   └── option_defs.zig    # Option metadata
├── display/                # EXISTING: Rendering
│   └── display.zig        # Terminal rendering
├── event/                  # NEW: Event system
│   ├── autocommand.zig    # Autocommand manager
│   └── events.zig         # Event types
├── input/                  # EXISTING: Input handling
│   └── input.zig          # Key processing
├── jsi/                    # EXISTING: JSI bridge
│   ├── hermes.zig         # Zig bindings
│   ├── hermes_c_api.cpp   # C++ wrapper
│   ├── hermes_c_api.h     # C API header
│   └── jsi_api.zig        # JavaScript API
├── mode/                   # EXISTING: Mode system
│   └── mode.zig           # Mode state machine
├── movement/               # EXISTING: Motion primitives
│   └── movement.zig       # Vim motions
├── register/               # NEW: Register system
│   └── register.zig       # Named registers
├── undo/                   # NEW: Undo system
│   └── undo_tree.zig      # Undo/redo tree
└── main.zig                # EXISTING: Entry point
```

### Naming Conventions

**Zig Side**:
- snake_case for functions: `get_current_buffer()`
- PascalCase for types: `BufferHandle`
- Option names match Vim: `cursorline`, `relativenumber`

**JavaScript Side**:
- camelCase for options: `vim.opt.cursorLine`, `vim.opt.relativeNumber`
- Full Neovim naming for API: `vim.api.nvim_buf_get_lines()`
- Ergonomic aliases: `vim.keymap.set()` wraps `vim.api.nvim_set_keymap()`

**Backwards Compatibility**:
- Support both naming conventions in Zig
- Example: Accept both "cursorLine" and "cursorline"

### Testing Strategy

**Unit Tests** (zig test):
- Buffer operations
- Movement primitives
- Undo tree
- Register management
- Option type conversion

**Integration Tests** (JavaScript + Zig):
- API function calls
- Option get/set
- Event firing
- Keymap registration

**End-to-End Tests** (test_openvim.sh):
- Load config
- Execute operations
- Verify state
- Check output

### Performance Targets

| Metric | Target | Neovim Baseline |
|--------|--------|-----------------|
| Cold startup | < 100ms | ~150ms |
| Hot reload | < 50ms | N/A (not native) |
| Large file (10MB) | < 500ms | ~1s |
| Buffer switch | < 10ms | ~20ms |
| Keystroke latency | < 16ms | ~20ms |

---

## Next Steps (Week-by-Week)

### Week 1-2: Delete & Change Operators

**Goals**:
- Implement x, dd, dw, d{motion}
- Implement c, cc, cw, c{motion}
- Transaction system for changes

**Deliverables**:
- `src/buffer/edit.zig` - Edit operations
- `src/undo/transaction.zig` - Change tracking
- Unit tests for operators
- Demo config with operator bindings

### Week 3-4: Yank/Paste & Registers

**Goals**:
- Implement register system
- Yank operations (y, yy, y{motion})
- Paste operations (p, P)
- Unnamed + named registers

**Deliverables**:
- `src/register/register.zig` - Register manager
- Integration with delete/change operators
- Clipboard support (optional)
- Register inspection (:reg)

### Week 5-6: Undo/Redo System

**Goals**:
- Implement undo tree
- u (undo) command
- Ctrl+R (redo) command
- Transaction boundaries

**Deliverables**:
- `src/undo/undo_tree.zig` - Undo tree structure
- Integration with all edit operations
- Persistent undo (optional)
- Undo tree visualization (optional)

### Week 7-8: Visual Mode Completion

**Goals**:
- Character visual mode
- Line visual mode (V)
- Visual operators (d, c, y on selection)
- Visual mode highlighting

**Deliverables**:
- Visual selection in buffer
- Visual mode operators
- Visual mode highlighting
- Demo config showing visual operations

### Week 9-10: vim.opt Implementation

**Goals**:
- Options manager in Zig
- vim.opt proxy in JavaScript
- All Phase 3 options working
- Type conversion layer

**Deliverables**:
- `src/config/options.zig` - Options manager
- `src/config/option_defs.zig` - Option metadata
- JavaScript proxy for vim.opt
- Unit tests for option system

---

## Architecture Decisions

### Why Zig?

- **Performance**: Compiles to native code, no GC pauses
- **Safety**: Compile-time checks, no undefined behavior
- **Simplicity**: Cleaner than C++, more control than Rust
- **Interop**: Easy C FFI for Hermes integration

### Why Hermes?

- **Bytecode**: Fast startup, small memory footprint
- **JSI**: Zero-copy bridge to native code
- **Ecosystem**: JavaScript is familiar to millions
- **TypeScript**: Excellent IDE support via types package

### Why Not Lua (like Neovim)?

- **Startup Speed**: Hermes bytecode > Lua 5.1 interpreter
- **Ecosystem**: More developers know JavaScript
- **Types**: TypeScript support from day one
- **Hot Reload**: Easier to implement with Hermes

### Key Technical Choices

**Buffer Storage**: ArrayList (Phase 1-3) → Rope (Phase 6)
- Reason: Simplicity first, optimize later

**Rendering**: ANSI escape codes (current) → Virtual terminal (future)
- Reason: Works today, optimize for large files later

**API Layer**: Expose nvim_* functions AND ergonomic wrappers
- Reason: Power users want low-level, beginners want simple

**Configuration**: JavaScript in ~/.config/openvim/init.js
- Reason: Neovim-style but with JavaScript instead of Lua

---

## Success Metrics

### Phase 3 Success (Text Editing)

- ✅ All delete operators work correctly
- ✅ All change operators work correctly
- ✅ Yank/paste with registers functional
- ✅ Undo/redo never loses data
- ✅ Visual mode operators work
- ✅ Performance: < 16ms latency for all operations

### Phase 4 Success (Plugin System)

- ✅ vim.opt can get/set all 80+ options
- ✅ vim.keymap can register and execute mappings
- ✅ Autocommands fire correctly for all events
- ✅ User commands can be registered and invoked
- ✅ Neovim config can be ported with minimal changes

### Phase 5+ Success (Advanced Features)

- ✅ Search and replace works for complex patterns
- ✅ Syntax highlighting via Tree-sitter
- ✅ LSP diagnostics display correctly
- ✅ Split windows and tabs functional
- ✅ Macros can be recorded and replayed

---

## Long-Term Vision

### 6 Months

- ✅ Phase 3-4 complete
- ✅ Basic text editing with plugin system
- ✅ Users can write simple plugins
- ✅ Config migration guide from Neovim

### 1 Year

- ✅ Phase 5 mostly complete
- ✅ LSP integration working
- ✅ Tree-sitter syntax highlighting
- ✅ Most Neovim plugins can be ported
- ✅ Performance better than Neovim

### 2 Years

- ✅ Full Neovim API parity
- ✅ Rich plugin ecosystem
- ✅ Remote plugin support
- ✅ Considered a viable Neovim alternative

---

## Resources

### Documentation

- **ANALYSIS_SUMMARY.md** - Research findings overview
- **NEOVIM_ARCHITECTURE_ANALYSIS.md** - Deep technical reference
- **NEOVIM_API_QUICK_REFERENCE.md** - Quick lookup while coding
- **TYPES_REFERENCE.md** - TypeScript types usage guide
- **CLAUDE.md** - Project context for development
- **This file** - Implementation roadmap

### Reference Codebases

- `../neovim/` - Neovim source (API reference)
- `../helix/` - Helix editor (design patterns)
- `../ghostty/` - Ghostty terminal (Zig best practices)

### Key Files to Study

**Neovim**:
- `runtime/lua/vim/_options.lua` (933 lines) - Options system
- `runtime/lua/vim/keymap.lua` (133 lines) - Keymap API
- `runtime/lua/vim/_editor.lua` (1,300 lines) - Main vim table
- `src/nvim/api/vim.c` (78KB) - Core API implementation
- `src/nvim/api/autocmd.c` (28KB) - Autocommand system
- `src/nvim/buffer.c` (45KB) - Buffer management

---

## Contributing

### Getting Started

1. Read this roadmap completely
2. Review ANALYSIS_SUMMARY.md for design patterns
3. Check current phase in this document
4. Pick a task from the current phase
5. Read relevant Neovim source for reference
6. Implement in Zig + JavaScript
7. Write tests
8. Submit PR with clear description

### Development Workflow

```bash
# Build OpenVim
zig build

# Run with config
./zig-out/bin/openvim init.ts

# Run tests
zig build test

# Build TypeScript config
npm run build:config

# Watch TypeScript config
npm run watch:config

# Test specific feature
./test_openvim.sh
```

### Coding Standards

**Zig**:
- Follow Zig style guide
- Use 4-space indentation
- Run `zig fmt` before commit
- Document public APIs

**JavaScript/TypeScript**:
- Use TypeScript for types
- Follow @openvim/types interfaces
- Test with hot reload

**Documentation**:
- Update CLAUDE.md for major changes
- Update this roadmap as phases complete
- Add examples to docs/

---

## Questions & Answers

**Q**: Why not fork Neovim?
**A**: Neovim is C-based with Lua. We want Zig + JavaScript for better performance, safety, and ecosystem.

**Q**: Will Neovim plugins work?
**A**: Not directly. Lua → JavaScript port needed. But API is compatible, so porting should be straightforward.

**Q**: Why JavaScript instead of Lua?
**A**: More developers know JS, better tooling (TypeScript), faster VM (Hermes), same ergonomics as Lua.

**Q**: Can I use this today?
**A**: For reading files and basic navigation, yes. For editing, wait for Phase 3 (4-6 weeks).

**Q**: How can I help?
**A**: Pick a task from current phase, implement it, test it, submit PR. Join discussions.

---

**Last Updated**: November 3, 2025
**Current Phase**: Phase 3 Ready to Start
**Next Milestone**: Delete & Change Operators (2 weeks)
**Long-term Goal**: Neovim-compatible editor with better performance
