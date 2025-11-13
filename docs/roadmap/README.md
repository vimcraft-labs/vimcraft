# Implementation Roadmap

Vimcraft's development plan from current state to full Neovim compatibility.

---

## 📖 Overview

Vimcraft follows a **phased implementation approach**, building from core text editing to advanced features:

**Current Status**: Phase 1+2+3 Complete ✅
**Next Milestone**: Phase 4 - Plugin System (6-8 weeks)
**Ultimate Goal**: Full Neovim API compatibility with better performance

---

## 📚 Documents in This Category

### [Implementation Roadmap](./implementation-roadmap.md) ⭐ MAIN DOCUMENT
**Purpose**: Complete development plan (600+ lines)
**Read if**: You want to understand the full project trajectory
**Key sections**:
- Grand design and architecture
- Feature status matrix (all phases)
- Week-by-week implementation plan (next 10 weeks)
- Code organization guidelines
- Success metrics per phase
- Long-term vision (6 months, 1 year, 2 years)

### [Phase 3: Text Editing](./phase-3-text-editing.md)
**Purpose**: Next milestone detailed breakdown
**Read if**: You're contributing to Phase 3
**Key topics**:
- Delete operators (x, dd, dw, d{motion})
- Change operators (c, cc, cw, c{motion})
- Yank/paste & registers
- Undo/redo system
- Visual mode operators
- Task assignments and estimates

### [Phase 4: Plugin System](./phase-4-plugin-system.md)
**Purpose**: Plugin system implementation plan
**Read if**: You're planning ahead or want to contribute
**Key topics**:
- vim.opt full implementation
- vim.keymap system
- Autocommand architecture
- User commands
- Event system
- vim.fn bridge

### [Phase 5+: Advanced Features](./phase-5-advanced.md)
**Purpose**: Long-term feature roadmap
**Read if**: You're curious about the future
**Key topics**:
- Search and replace
- Command mode (: commands)
- Syntax highlighting (Tree-sitter)
- LSP integration
- Diagnostic system
- Split windows
- Tab pages
- Macros

---

## 📊 Phase Overview

### ✅ Phase 1+2: Foundation (Complete)

**Status**: Shipped
**Duration**: Initial development
**What we built**:
- Text display system
- File loading
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert/Visual)
- Terminal rendering (ANSI codes)
- Hermes+JSI integration
- Basic configuration API
- Hot reload system

### ✅ Phase 3: Text Editing (Complete)

**Status**: Completed
**Duration**: 4-6 weeks
**Timeline**: Weeks 1-6
**What we built**:
- Delete operators (x, dd, dw, d{motion}) ✅
- Change operators (c, cc, cw, c{motion}) ✅
- Yank/paste (y, p, P) with registers ✅
- Undo/redo stack (linear history) ✅
- Visual mode operators (y, d, c in v/V/Ctrl-V modes) ✅
- Register system (39 Neovim-compatible registers) ✅

**Progress**: 6/6 weeks complete

See: [Phase 3: Text Editing](./phase-3-text-editing.md)

### 📅 Phase 4: Plugin System (Planned)

**Status**: After Phase 3
**Duration**: 6-8 weeks
**Timeline**: Weeks 7-14
**What we'll build**:
- vim.opt full implementation (all 70+ options)
- vim.keymap.set/del system
- Autocommand architecture
- Event firing system
- User commands
- vim.fn function bridge

See: [Phase 4: Plugin System](./phase-4-plugin-system.md)

### 🔮 Phase 5+: Advanced Features (Future)

**Status**: Long-term
**Duration**: 8-12+ weeks
**Timeline**: Months 4-12
**What we'll build**:
- Search and replace (/, ?, :s)
- Command mode (: parser)
- Ex commands (:w, :q, :e, etc.)
- Tree-sitter syntax highlighting
- LSP integration
- Diagnostic system
- Split windows
- Tab pages
- Macros (q, @)

See: [Phase 5+: Advanced Features](./phase-5-advanced.md)

---

## 🎯 Current Focus (Week-by-Week)

### Week 1-2: Delete & Change Operators 🎯 CURRENT

**Goals**:
- Implement x (delete char)
- Implement dd (delete line)
- Implement dw (delete word)
- Implement d{motion} (general delete)
- Implement c{motion} (change operators)
- Transaction system for undo

**Deliverables**:
- `src/buffer/edit.zig` - Edit operations
- `src/undo/transaction.zig` - Change tracking
- Unit tests
- Demo config

### Week 3-4: Yank/Paste & Registers

**Goals**:
- Register system (unnamed + named)
- Yank operations (y, yy, y{motion})
- Paste operations (p, P)
- Integration with delete/change

**Deliverables**:
- `src/register/register.zig` - Register manager
- Clipboard support (optional)
- :reg command (inspect registers)

### Week 5-6: Undo/Redo System

**Goals**:
- Undo tree structure
- u (undo) command
- Ctrl+R (redo) command
- Transaction boundaries
- Persistent undo (optional)

**Deliverables**:
- `src/undo/undo_tree.zig` - Undo tree
- Integration with all edit operations
- Undo tree visualization (optional)

### Week 7-8: Visual Mode Completion

**Goals**:
- Character visual mode
- Line visual (V)
- Visual operators (d, c, y)
- Visual highlighting

**Deliverables**:
- Visual selection in buffer
- Visual mode operators
- Demo showing visual operations

### Week 9-10: vim.opt Implementation

**Goals**:
- Options manager in Zig
- vim.opt proxy in JavaScript
- All Phase 3 options working
- Type conversion layer

**Deliverables**:
- `src/config/options.zig` - Options manager
- `src/config/option_defs.zig` - Metadata
- JavaScript proxy
- Unit tests

---

## 📈 Progress Tracking

### Phase 3 Tasks (Total: ~40 tasks)

**Delete Operators** (8 tasks):
- [ ] Create edit.zig module
- [ ] Implement x (delete char)
- [ ] Implement dd (delete line)
- [ ] Implement dw (delete word)
- [ ] Implement d{motion} framework
- [ ] Transaction system
- [ ] Unit tests
- [ ] Integration tests

**Change Operators** (6 tasks):
- [ ] Implement c{motion} framework
- [ ] Implement cc (change line)
- [ ] Implement C (change to EOL)
- [ ] Enter insert mode after change
- [ ] Transaction integration
- [ ] Unit tests

**Yank/Paste** (8 tasks):
- [ ] Create register.zig module
- [ ] Unnamed register
- [ ] Named registers (a-z)
- [ ] Yank operations
- [ ] Paste after (p)
- [ ] Paste before (P)
- [ ] :reg command
- [ ] Unit tests

**Undo/Redo** (10 tasks):
- [ ] Create undo_tree.zig
- [ ] Undo tree structure
- [ ] Transaction boundaries
- [ ] u (undo) command
- [ ] Ctrl+R (redo) command
- [ ] Branch navigation (optional)
- [ ] Persistent undo (optional)
- [ ] Integration with all ops
- [ ] Unit tests
- [ ] Stress tests

**Visual Mode** (8 tasks):
- [ ] Character visual mode
- [ ] Line visual (V)
- [ ] Visual selection display
- [ ] Visual delete (d)
- [ ] Visual change (c)
- [ ] Visual yank (y)
- [ ] Mode transitions
- [ ] Integration tests

---

## 🎓 How to Use This Roadmap

### If You're a Contributor

1. **Check Current Phase**: See what phase we're in
2. **Pick a Task**: Choose from current week's tasks
3. **Read Detail Doc**: Check phase-specific document
4. **Implement**: Follow architecture guidelines
5. **Test**: Write tests for your changes
6. **Submit**: Create PR with clear description

### If You're Planning

1. **Understand Phases**: Read full implementation roadmap
2. **See Dependencies**: Understand what builds on what
3. **Estimate Timeline**: Use provided time estimates
4. **Plan Resources**: Know what skills are needed

### If You're Curious

1. **Check Progress**: See current phase completion
2. **See Future**: Read Phase 5+ plans
3. **Compare Neovim**: Understand parity goals
4. **Track Milestones**: Watch phase completions

---

## 🔍 Quick Links by Topic

### Current Work
- [Week 1-2 Tasks](./phase-3-text-editing.md#week-1-2)
- [Delete Operators](./phase-3-text-editing.md#delete-operators)
- [Code Organization](./implementation-roadmap.md#code-organization)

### Near Future (Phase 3)
- [Yank/Paste Plan](./phase-3-text-editing.md#yank-paste)
- [Undo/Redo Design](./phase-3-text-editing.md#undo-redo)
- [Visual Mode](./phase-3-text-editing.md#visual-mode)

### Medium Term (Phase 4)
- [Plugin System](./phase-4-plugin-system.md)
- [vim.opt Design](./phase-4-plugin-system.md#vim-opt)
- [Autocommands](./phase-4-plugin-system.md#autocommands)

### Long Term (Phase 5+)
- [Search/Replace](./phase-5-advanced.md#search-replace)
- [LSP Integration](./phase-5-advanced.md#lsp)
- [Tree-sitter](./phase-5-advanced.md#treesitter)

---

## 📊 Feature Priority Matrix

### CRITICAL (Must have for usability)
- ✅ Text display
- ✅ Navigation
- ✅ Delete operators
- ✅ Change operators
- ✅ Undo/redo
- ✅ Yank/paste
- 📅 vim.opt
- 📅 vim.keymap

### HIGH (Important for productivity)
- ✅ Mode system
- ✅ File loading
- ✅ Visual mode
- 📅 Autocommands
- 📅 User commands
- 📅 Search/replace

### MEDIUM (Nice to have)
- ✅ Hot reload
- 📅 Syntax highlighting
- 📅 Split windows
- 📅 Diagnostics
- 📅 LSP

### LOW (Future enhancements)
- 📅 Macros
- 📅 Tab pages
- 📅 Remote plugins

Legend: ✅ Complete | 🚧 In Progress | 📅 Planned

---

## 🏆 Success Criteria

### Phase 3 Success
- ✅ All delete operators work correctly
- ✅ All change operators work correctly
- ✅ Yank/paste with registers functional
- ✅ Undo/redo never loses data
- ✅ Visual mode operators work
- ✅ Performance: < 16ms latency

### Phase 4 Success
- ✅ vim.opt can get/set all 70+ options
- ✅ vim.keymap can register mappings
- ✅ Autocommands fire correctly
- ✅ User commands work
- ✅ Neovim configs easily portable

### Long-term Success
- ✅ Full Neovim API parity
- ✅ Startup < 100ms
- ✅ Rich plugin ecosystem
- ✅ Better performance than Neovim

---

## 🔗 Related Documentation

- [Architecture](../architecture/) - System design
- [API Documentation](../api/) - API reference
- [Development Guide](../development/) - How to contribute
- [Research](../research/) - Background analysis

---

## 📝 Contributing to Roadmap

### Updating Progress

1. Mark tasks as complete: ~~Task~~ or change 🚧 to ✅
2. Update week numbers as we progress
3. Add new tasks if discovered during implementation
4. Update time estimates based on actual progress

### Proposing Changes

1. Discuss in GitHub issues first
2. Consider dependencies and phase order
3. Update affected phase documents
4. Update this index

---

**Last Updated**: November 11, 2025
**Current Phase**: Phase 3 Complete ✅ - Ready for Phase 4
**Next Milestone**: Plugin System (vim.opt, vim.keymap, autocommands)
**Long-term Goal**: Neovim parity in 6-12 months
