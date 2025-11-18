# Phase 5: Tree-sitter + Filetype Detection Implementation

**Status**: 🚧 In Progress (Week 1)
**Timeline**: 4 weeks (Dec 2025)
**Priority**: HIGH - User requested feature

## Table of Contents

1. [Expert Validation Summary](#expert-validation-summary)
2. [Architecture Decisions](#architecture-decisions)
3. [Implementation Plan](#implementation-plan)
4. [TODO Checklist](#todo-checklist)
5. [Important Findings](#important-findings)
6. [Risk Mitigation](#risk-mitigation)

---

## Expert Validation Summary

### Reference Implementations Analyzed

1. **Helix (Rust)** - Production-ready, 1.5+ years battle-tested
2. **Neovim (Lua/C)** - Mature tree-sitter integration
3. **Pulsar (JS/WASM)** - Sept 2024 post-mortem with lessons learned
4. **Tree-sitter Official Docs** - Creator guidance and design principles

### ✅ What Tree-sitter EXCELS At

| Use Case | Confidence | Source |
|----------|------------|--------|
| **Syntax Highlighting** | ⭐⭐⭐⭐⭐ | All editors, primary use case |
| **Structural Navigation** | ⭐⭐⭐⭐ | Helix's Alt-p/o/i/n motions |
| **Code Folding** | ⭐⭐⭐⭐ | Natural tree structure |
| **Scope Detection** | ⭐⭐⭐⭐ | Function/class boundaries |

### ❌ What Tree-sitter STRUGGLES With

| Use Case | Issue | Source |
|----------|-------|--------|
| **Autocompletion** | Requires unnaturally high parse fidelity | Jake Zimmerman blog |
| **Precise Error Messages** | Error recovery is "black box" | Pulsar post-mortem |
| **Auto-indent Logic** | Too complex, better use heuristics | Multiple sources |

---

## Architecture Decisions (Validated by Experts)

### Decision 1: Native C Bindings (NOT WASM)

**Choice**: Use official Zig tree-sitter bindings
**Rationale**: Pulsar's experience shows WASM adds memory management complexity

```zig
// Use official tree-sitter Zig bindings
// https://tree-sitter.github.io/zig-tree-sitter
const tree_sitter = @import("tree-sitter");
```

**Alternative Rejected**: WebAssembly bindings (Pulsar spent months debugging memory issues)

### Decision 2: Lazy Query Loading

**Choice**: OnceCell pattern - load queries only when needed
**Rationale**: Helix's proven approach - don't load indent queries if feature disabled

```zig
pub const LanguageData = struct {
    highlight_query: ?*Query = null,  // Null until first use
    indent_query: ?*Query = null,
    textobject_query: ?*Query = null,

    pub fn getHighlightQuery(self: *LanguageData, allocator: Allocator) !*Query {
        if (self.highlight_query) |q| return q;  // Return cached

        // Load from embedded file
        const query_source = @embedFile("runtime/queries/rust/highlights.scm");
        self.highlight_query = try Query.parse(allocator, self.scope, query_source);
        return self.highlight_query.?;
    }
};
```

**Why**: Zero cost until actually used, supports feature toggles

### Decision 3: Parsing Budget (3ms limit)

**Choice**: Skip tree-sitter if parsing takes >3ms
**Rationale**: Pulsar production finding - prevents UI lag on massive/complex files

```zig
const start = std.time.nanoTimestamp();
const tree = try parser.parse(source);
const elapsed_ms = (std.time.nanoTimestamp() - start) / 1_000_000;

if (elapsed_ms > 3) {
    // File too complex, fallback to no highlighting
    editor.logger.warn("Parse timeout ({}ms), skipping tree-sitter", .{elapsed_ms});
    return;
}
```

**Threshold**: 3ms based on Pulsar's testing (keeps UI responsive)

### Decision 4: Incremental Parsing (Core Feature)

**Choice**: Use tree.edit() for byte-range updates
**Rationale**: Tree-sitter's primary design goal - "parse on every keystroke"

```zig
pub fn onBufferEdit(self: *Highlighter, start_byte: usize, old_end: usize, new_end: usize) !void {
    // Neovim's on_bytes pattern
    const edit = tree_sitter.InputEdit{
        .start_byte = start_byte,
        .old_end_byte = old_end,
        .new_end_byte = new_end,
        .start_point = byteToPoint(start_byte),
        .old_end_point = byteToPoint(old_end),
        .new_end_point = byteToPoint(new_end),
    };

    self.tree.edit(&edit);  // Update existing tree (cheap!)
    self.tree = try self.parser.parse(self.tree, self.buffer.content.items);
}
```

**Why**: Only re-parses changed regions, not entire file

### Decision 5: Compositor Integration

**Choice**: Tree-sitter → new "syntax" layer → compositor blends
**Rationale**: Reuse existing Vimcraft infrastructure

```zig
// Tree-sitter highlights → new "syntax" layer → compositor blends
try compositor.addLayer(.{
    .name = "syntax",
    .cells = syntax_highlights,
    .z_index = 5,  // Below cursor, above buffer
    .enabled = true,
});
```

**Why**: Zero new rendering code needed, proven architecture

### Decision 6: Filetype Detection Strategy

**Choice**: Three-tier lookup (Helix pattern)
**Rationale**: Fast path for common cases, comprehensive for edge cases

```
1. Extension map (O(1) lookup)    → .rs, .js, .py
2. Glob patterns (regex match)    → Makefile, *.config.js
3. Shebang inspection (first line) → #!/usr/bin/env node
```

**Why**: Covers 99% of cases with minimal overhead

---

## Implementation Plan

### Week 1: Filetype Detection (Foundation)

**Goal**: Identify language from file path/content
**Deliverable**: Open test.rs → vim.bo.filetype = "rust"

**Tasks**:
- [ ] Create `src/editor/treesitter/loader.zig`
- [ ] Implement `Loader` struct with extension/glob/shebang maps
- [ ] Add comptime language definitions (5 languages)
- [ ] Add `detectFiletype()` function (3-tier lookup)
- [ ] Hook into file open event
- [ ] Test with 5 file types (Rust, JS, Python, Zig, Markdown)

**Why This First**: No dependencies, immediate user value, validates architecture

### Week 2: Tree-sitter Core Integration

**Goal**: Parse files and build syntax trees
**Deliverable**: `:tree-sitter-subtree` shows syntax tree

**Tasks**:
- [ ] Add tree-sitter to build.zig (official Zig bindings)
- [ ] Create `src/editor/treesitter/parser.zig` wrapper
- [ ] Implement `LanguageData` with lazy loading
- [ ] Load parser for detected filetype
- [ ] Parse test file and verify tree structure
- [ ] Add `:tree-sitter-subtree` debug command

**Critical**: Use native bindings, NOT WASM

### Week 3: Syntax Highlighting

**Goal**: Map syntax tree to highlight groups
**Deliverable**: Rust code highlights in terminal

**Tasks**:
- [ ] Create `src/editor/treesitter/highlighter.zig`
- [ ] Implement `Highlighter` struct
- [ ] Load `highlights.scm` query files (embed at compile time)
- [ ] Execute queries and extract captures
- [ ] Map captures to existing highlight groups (reuse terminal/display)
- [ ] Integrate with compositor layer system
- [ ] Add `vim.treesitter.start(bufnr, lang)` API
- [ ] Add `vim.treesitter.stop(bufnr)` API

**Key**: Reuse compositor → zero new rendering code

### Week 4: Incremental Updates + Polish

**Goal**: Real-time updates during editing
**Deliverable**: Type in Insert → highlights update <5ms

**Tasks**:
- [ ] Implement `tree.edit()` with byte-range updates
- [ ] Hook into buffer insert/delete operations
- [ ] Add parsing budget (3ms limit)
- [ ] Add visible range optimization (large files)
- [ ] Benchmark: verify <5ms reparse on typical edits
- [ ] Add error handling (graceful degradation)
- [ ] Document API in `docs/api/treesitter.md`
- [ ] Update CLAUDE.md with tree-sitter status

**Performance Target**: <5ms for 90% of edits

---

## TODO Checklist

### Week 1: Filetype Detection ✅ CURRENT FOCUS

#### Core Implementation
- [ ] Create `src/editor/treesitter/` directory
- [ ] Create `src/editor/treesitter/loader.zig`
  - [ ] `Loader` struct with hash maps
  - [ ] `init()` and `deinit()` methods
  - [ ] `detectFiletype()` function
  - [ ] Extension map (`.rs` → `"rust"`)
  - [ ] Glob matcher (for `Makefile`, `*.config.js`)
  - [ ] Shebang matcher (for `#!/usr/bin/env node`)
- [ ] Define language metadata
  - [ ] Rust language config
  - [ ] JavaScript language config
  - [ ] Python language config
  - [ ] Zig language config
  - [ ] Markdown language config

#### Integration
- [ ] Add filetype detection to `src/editor/editor.zig`
- [ ] Call `detectFiletype()` on file open
- [ ] Store filetype in buffer metadata
- [ ] Expose `vim.bo.filetype` in JSI API

#### Testing
- [ ] Unit test: extension detection
- [ ] Unit test: glob pattern matching
- [ ] Unit test: shebang detection
- [ ] Integration test: open `.rs` file
- [ ] Integration test: open `Makefile`
- [ ] Integration test: open file with shebang

#### Documentation
- [ ] Document `Loader` API in code comments
- [ ] Add examples to this file

### Week 2: Tree-sitter Core (PENDING)

- [ ] Add tree-sitter dependency to build.zig
- [ ] Create parser wrapper
- [ ] Implement lazy query loading
- [ ] Add debug commands
- [ ] Test tree structure

### Week 3: Syntax Highlighting (PENDING)

- [ ] Create highlighter
- [ ] Load query files
- [ ] Execute queries
- [ ] Map to highlight groups
- [ ] Compositor integration
- [ ] API implementation

### Week 4: Incremental + Polish (PENDING)

- [ ] Incremental parsing
- [ ] Buffer edit hooks
- [ ] Performance budget
- [ ] Visible range optimization
- [ ] Benchmarking
- [ ] Documentation

---

## Important Findings

### From Helix (Rust - Production Editor)

**Architecture** (`helix-core/src/syntax.rs`):
```rust
pub struct Loader {
    languages: Vec<LanguageData>,
    languages_by_extension: HashMap<String, Language>,  // Fast O(1) lookup
    languages_by_shebang: HashMap<String, Language>,
    languages_glob_matcher: FileTypeGlobMatcher,        // Makefile, *.config.js
}

pub struct LanguageData {
    config: Arc<LanguageConfiguration>,
    syntax: OnceCell<Option<SyntaxConfig>>,              // Lazy!
    indent_query: OnceCell<Option<IndentQuery>>,         // Only load if used
    textobject_query: OnceCell<Option<TextObjectQuery>>,
}
```

**Key Lessons**:
1. **Lazy Loading is MANDATORY** - Don't load indent queries if feature disabled
2. **Three-tier filetype detection** - extension → glob → shebang
3. **Good defaults matter** - Helix needs ~30 lines of config vs Vim's 100+
4. **TOML configuration** - External `languages.toml` for user extensibility
5. **They rewrote bindings in v25.07** - "tree-house" replacement for better performance

**Quote from User Review** (1.5 years usage):
> "Helix core is much more powerful than Vim, but since there is no plugin system (yet), there is functionality that vim can acquire through plugins, that Helix does not have. The upside is, that you basically don't need to configure Helix."

### From Neovim (Lua/C - Mature Integration)

**Parser Management** (`vim/treesitter.lua`):
```lua
-- Global parser cache (per buffer + language)
local parsers = setmetatable({}, {
  __index = function(tbl, bufnr)
    rawset(tbl, bufnr, {})
    return rawget(tbl, bufnr)
  end,
})

function M.get_parser(bufnr, lang, opts)
  if parsers[bufnr][lang] then
    return parsers[bufnr][lang]  -- Return cached
  end

  local parser = M._create_parser(bufnr, lang, opts)

  -- Attach buffer lifecycle hooks
  vim.api.nvim_buf_attach(bufnr, false, {
    on_bytes = function(...) parser:_on_bytes(...) end,
    on_detach = function(...) parser:_on_detach(...) end,
  })

  return parser
end
```

**Highlighting** (`vim/treesitter/highlighter.lua`):
```lua
-- Only highlight visible range (not entire file!)
function TSHighlighter._on_range(_, win, bufnr, srow, erow)
  local self = TSHighlighter.active[bufnr]

  for _, query in ipairs(self.queries) do
    for capture, node, metadata in query:iter_captures(srow, erow) do
      local hl_group = query.captures[capture]
      local row1, col1, row2, col2 = node:range()
      vim.api.nvim_buf_set_extmark(bufnr, ns, row1, col1, {
        end_row = row2,
        end_col = col2,
        hl_group = hl_group,
      })
    end
  end
end
```

**Key Lessons**:
1. **Buffer attachment** - Parser lifecycle tied to buffer (automatic cleanup)
2. **Incremental parsing** - `on_bytes` callback updates only changed regions
3. **Visible range only** - Don't highlight entire file (performance!)
4. **Decoration provider API** - Native Neovim integration for virtual text

**Filetype Detection** (`vim/filetype.lua` - 3,238 lines!):
- Massive pattern-based system
- Helper functions: `_getlines()`, `_nextnonblank()` for complex detection
- Multi-strategy: filename → extension → pattern → shebang → content inspection

### From Pulsar (JS/WASM - Post-Mortem Sept 2024)

**Pain Points**:
1. **WASM Memory Management** - Must explicitly free tree objects, no GC
2. **Performance Issues** - 3ms parsing budget to prevent UI lag
3. **Large Files** - Files without newlines force full-file highlighting
4. **Toolchain Complexity** - Specific Emscripten versions required
5. **Error Recovery** - "Black box" process, hard to customize

**Recommendations**:
- Use native bindings, NOT WASM (learned the hard way)
- Implement parsing time budgets (3ms limit)
- Design flexible error recovery mechanisms
- Maintain backward compatibility (TextMate grammar fallback)

**Quote**:
> "Highlighting source code is hard! Tree-sitter is becoming crucial infrastructure, but parsing performance needs managing."

### From Tree-sitter Creators (Official Docs)

**Core Design Principles**:
1. **General** - Parse any programming language
2. **Fast** - Parse on every keystroke (designed for this!)
3. **Robust** - Useful results even with syntax errors
4. **Dependency-free** - Pure C11, embeds anywhere

**Incremental Parsing** (THE killer feature):
```c
void ts_tree_edit(TSTree *tree, const TSInputEdit *edit);
```

**Edit Structure**:
```c
typedef struct {
  uint32_t start_byte;
  uint32_t old_end_byte;
  uint32_t new_end_byte;
  TSPoint start_point;
  TSPoint old_end_point;
  TSPoint new_end_point;
} TSInputEdit;
```

**Key Insight**: Only re-parses changed regions, not entire file

### From Jake Zimmerman (Critical Analysis)

**Tree-sitter Limitations**:
1. **Weak Error Handling** - Poor with partial/incomplete code
2. **Autocompletion Struggles** - Needs "unnaturally high parse fidelity"
3. **Declarative Limits** - Can't run arbitrary code during parsing
4. **Ceiling on Possibilities** - Less flexible than hand-written parsers

**When to Avoid Tree-sitter**:
- Projects requiring extremely precise parsing
- Autocompletion systems needing high fidelity
- Single-language parsers where absolute accuracy is critical

**Quote**:
> "If either of these goals are important, I'd recommend rolling your own parser."

### Code Context Research Highlights

**Incremental Parsing Pattern** (from multiple sources):
```javascript
// Edit example: Replace 'let' with 'const'
const newSourceCode = 'const x = 1; console.log(x);';

tree.edit({
  startIndex: 0,
  oldEndIndex: 3,
  newEndIndex: 5,
  startPosition: {row: 0, column: 0},
  oldEndPosition: {row: 0, column: 3},
  newEndPosition: {row: 0, column: 5},
});

const newTree = parser.parse(newSourceCode, tree);
```

**Key Pattern**: Always provide old/new byte ranges + point positions

**Highlight Query Execution**:
```rust
for event in highlights {
    match event? {
        HighlightEvent::Source {start, end} => {
            eprintln!("source: {}-{}", start, end);
        },
        HighlightEvent::HighlightStart(s) => {
            eprintln!("highlight style started: {:?}", s);
        },
        HighlightEvent::HighlightEnd => {
            eprintln!("highlight style ended");
        },
    }
}
```

**Pattern**: Iterator-based query execution with start/end events

---

## Risk Mitigation

### Risk 1: Parse Performance

**Risk**: Large/complex files cause UI lag
**Mitigation**:
- 3ms parsing budget (Pulsar's finding)
- Skip tree-sitter if exceeded
- Fallback to no highlighting (graceful degradation)
- Log performance metrics for debugging

**Monitoring**:
```zig
editor.logger.debug("Parse time: {}ms (budget: 3ms)", .{elapsed_ms});
```

### Risk 2: Large Files Without Newlines

**Risk**: Single-line 10MB file forces full-file highlighting
**Mitigation**:
- Highlight visible range only (Neovim pattern)
- Add file size limit (e.g., skip if >1MB)
- Chunk-based processing for large files

**Implementation**:
```zig
if (buffer.size > 1024 * 1024) {
    // File too large, skip tree-sitter
    return;
}
```

### Risk 3: Memory Leaks

**Risk**: Tree objects not freed (WASM issue in Pulsar)
**Mitigation**:
- Zig's allocator tracking (catches leaks automatically)
- Explicit tree cleanup in deinit()
- Use defer for RAII pattern

**Pattern**:
```zig
pub fn deinit(self: *Highlighter) void {
    if (self.tree) |tree| {
        tree.delete();  // Explicit cleanup
        self.tree = null;
    }
    self.parser.delete();
}
```

### Risk 4: Complex Language Grammars

**Risk**: Some languages harder to parse (C++, Perl)
**Mitigation**:
- Start with 5 simple languages (Rust, JS, Python, Zig, Markdown)
- Add complex languages incrementally
- Monitor parse times per language
- User can disable per-language

### Risk 5: Error Handling (Black Box)

**Risk**: Can't customize error recovery
**Mitigation**:
- Accept limitation (Jake Zimmerman's advice)
- Focus on syntax highlighting (tree-sitter's strength)
- Don't attempt autocompletion (known weakness)
- Provide user feedback on parse failures

---

## Scope Boundaries

### ✅ In Scope for MVP

| Feature | Rationale |
|---------|-----------|
| Syntax highlighting (5 languages) | Core use case, proven in production |
| Filetype detection (extension/glob/shebang) | Foundation for all features |
| Incremental parsing | Tree-sitter's killer feature |
| `:tree-sitter-subtree` command | Debug/inspection tool |
| `vim.treesitter.start/stop` API | User control |
| Performance budget (3ms) | Pulsar's lesson |

### ❌ Out of Scope for MVP

| Feature | Why Excluded |
|---------|--------------|
| Auto-indent | Tree-sitter limitation (Jake Zimmerman) |
| Autocompletion | Requires higher fidelity than tree-sitter provides |
| Precise error messages | Error recovery is black box |
| Language injection (JS in HTML) | Phase 5 advanced feature |
| External scanner support | Adds complexity, defer to later |
| Runtime language loading | Embed at compile time for simplicity |
| Text objects (`af`, `if`) | Phase 5 advanced feature |
| Rainbow parentheses | Nice-to-have, not critical |

### 🔮 Future Enhancements (Post-MVP)

- Code folding (natural tree structure support)
- Syntax-aware motions (Helix's Alt-p/o/i/n)
- Text objects (function, class, comment)
- Language injection (embedded languages)
- Runtime parser loading (user-installed languages)
- Advanced queries (indent, textobject, tag)

---

## Success Criteria

### Functional Requirements

- [ ] **Filetype Detection**: Open `test.rs` → `vim.bo.filetype = "rust"`
- [ ] **Syntax Parsing**: Parse file without errors
- [ ] **Incremental Updates**: Type in Insert → highlights update in real-time
- [ ] **Performance**: 90% of edits complete in <5ms
- [ ] **Large Files**: 10,000-line file either highlights or gracefully skips
- [ ] **Debug Tools**: `:tree-sitter-subtree` shows syntax tree
- [ ] **API**: `vim.treesitter.start(bufnr, lang)` enables highlighting
- [ ] **Compositor**: Syntax layer blends with cursor/buffer layers

### Non-Functional Requirements

- [ ] **Memory**: No leaks in Zig allocator tracking
- [ ] **Performance**: Parse budget enforced (3ms limit)
- [ ] **Error Handling**: Graceful degradation on parse failures
- [ ] **Logging**: All operations logged via `editor.logger`
- [ ] **Debug Protocol**: Syntax layer inspectable via `get_layers`
- [ ] **Documentation**: API documented in `docs/api/treesitter.md`

### Quality Criteria

- [ ] All unit tests pass
- [ ] No compiler warnings
- [ ] Formatted with `zig fmt`
- [ ] Follows Vimcraft architecture patterns
- [ ] Integrates with existing compositor system
- [ ] Works with debug protocol (no regression)

---

## Timeline

**Total**: 4 weeks (~80-100 hours)

| Week | Phase | Hours | Deliverable |
|------|-------|-------|-------------|
| 1 | Filetype Detection | 20h | `vim.bo.filetype` working |
| 2 | Tree-sitter Core | 25h | `:tree-sitter-subtree` command |
| 3 | Syntax Highlighting | 30h | Rust code highlights in terminal |
| 4 | Incremental + Polish | 25h | <5ms updates, production-ready |

**Milestones**:
- End of Week 1: Can detect filetype for 5 languages
- End of Week 2: Can parse files and inspect syntax tree
- End of Week 3: Syntax highlighting works for Rust
- End of Week 4: Full incremental parsing, all 5 languages

---

## References

### Source Code Analysis

1. **Helix**: `/Users/le/projects/helix/helix-core/src/syntax.rs` (1,371 lines)
2. **Helix Config**: `/Users/le/projects/helix/helix-core/src/syntax/config.rs` (632 lines)
3. **Neovim Filetype**: `/Users/le/projects/neovim/runtime/lua/vim/filetype.lua` (3,238 lines)
4. **Neovim Tree-sitter**: `/Users/le/projects/neovim/runtime/lua/vim/treesitter.lua` (515 lines)
5. **Neovim Highlighter**: `/Users/le/projects/neovim/runtime/lua/vim/treesitter/highlighter.lua` (586 lines)

### Articles & Documentation

1. **Pulsar Post-Mortem**: https://blog.pulsar-edit.dev/posts/20240902-savetheclocktower-modern-tree-sitter-part-7/
2. **Tree-sitter Limitations**: https://blog.jez.io/tree-sitter-limitations/
3. **Tree-sitter Official Docs**: https://tree-sitter.github.io/tree-sitter/
4. **Helix Release Notes**: https://helix-editor.com/news/release-25-07-highlights.html
5. **Helix User Review**: https://felix-knorr.net/posts/2025-03-16-helix-review/
6. **Tree-sitter Complications**: https://www.masteringemacs.org/article/tree-sitter-complications-of-parsing-languages

### Key Insights

**From Production Editors**:
- Helix: Lazy loading + external config + good defaults
- Neovim: Buffer attachment + visible range + incremental parsing
- Pulsar: WASM issues + 3ms budget + error recovery challenges

**From Tree-sitter Creators**:
- Designed for every-keystroke parsing
- Incremental updates are THE killer feature
- Pure C11, zero dependencies, embeds anywhere

**From Critical Analysis**:
- Don't use for autocompletion (limitation)
- Error recovery is black box (accept it)
- Focus on syntax highlighting (strength)

---

## Notes

### Design Philosophy

**Start Simple, Validate, Iterate**:
1. Start with 5 languages (not 50)
2. Start with highlighting (not text objects)
3. Validate architecture with real usage
4. Iterate based on user feedback

**Leverage Existing Infrastructure**:
- Reuse compositor layer system
- Reuse highlight group mappings
- Reuse debug protocol integration
- Don't reinvent rendering

**Learn from Production Editors**:
- Helix: Lazy loading, external config
- Neovim: Buffer attachment, visible range
- Pulsar: What NOT to do (WASM, no budgets)

### Questions to Resolve

- [ ] Which Zig tree-sitter bindings to use? (Official: https://tree-sitter.github.io/zig-tree-sitter)
- [ ] How to embed `.scm` query files? (`@embedFile` for MVP)
- [ ] Where to store parser `.so` files? (Compile into binary for MVP)
- [ ] How to handle multiple parsers per language? (Start with one, defer injection)

### Future Considerations

- **Plugin System**: Allow users to add custom parsers
- **Language Injection**: JS in HTML, SQL in Python strings
- **Advanced Queries**: Indent, textobject, tag queries
- **Performance Profiling**: Measure parse times per language
- **User Configuration**: Enable/disable per-language, custom queries

---

**Last Updated**: 2025-01-18 (Initial draft)
**Next Review**: End of Week 1 (update with findings from filetype detection implementation)
