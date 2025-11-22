# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Quick Navigation

**Critical Workflows**:
- [Testing Architecture](#testing-architecture-two-level-design) - Unit tests + E2E (vimc test)
- [Test-Driven Development (TDD)](#test-driven-development-tdd) - MANDATORY workflow: write tests first
- [Logging Architecture](#logging-architecture) - Use `editor.logger`, not `std.debug.print`
- [Debugging Principles](#debugging-principles) - 8 proven principles + tool selection guide
- [Rendering Optimizations](#rendering-optimizations-phase-4---january-2025) - 2-10x performance improvements
- [Build Commands](#build-commands) - How to build and run

**Project Info**: [Overview](#project-overview) · [Architecture](#architecture) · [Key Files](#key-files) · [Navigation](#navigation-commands) · [Roadmap](#roadmap)

**Documentation**: All docs in `docs/` - see [docs/README.md](docs/README.md) for navigation. Follow structure: add to correct category, update category README, link from main index.

---

## Project Overview

**Vimcraft** - Neovim-compatible editor in Zig with Hermes JavaScript engine for plugins via JSI (zero-copy bidirectional communication).

**Status**: Phase 1+2+3 Complete ✅ (December 2025)
- Text display and file loading
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert/Visual)
- **Delete operators (x, dd, dw, d{motion})** ✨
- **Change operators (c{motion}, cc, C)** ✨
- **Yank/paste (y{motion}, yy, p, P)** ✨
- **Bracketed paste (Cmd+V/Ctrl+V)** ✨
- **Register system (39 registers)** ✨
- **Undo/redo (u, Ctrl+R) with transaction grouping** ✨
- **Visual mode (v, V with d/c/y operators)** ✨
- **Visual paste replace (single undo operation)** ✨
- Terminal rendering (ANSI codes)
- Hermes+JSI demos working (not yet in main editor)

**Reference Codebases**: `../neovim` (API compatibility), `../helix` (design patterns), `../ghostty` (Zig best practices)

## Testing Architecture: Two-Level Design

**Critical**: Vimcraft uses a **simple two-level test architecture**:

```
tests/
├── unit/           # Level 1: Pure Zig only (no Hermes)
└── e2e/            # Level 2: Full stack (PTY + Hermes + TypeScript)
```

See [docs/development/testing-architecture.md](docs/development/testing-architecture.md) for complete guide.

### Level 1: Unit Tests (Pure Zig)

**Location**: `tests/unit/`
**Run**: `zig build test`
**Speed**: ~1ms per test

**What belongs here**:
- Buffer operations (insert, delete, getLine)
- Rope data structure (balance, split, concat)
- Movement calculations (cursor math, boundary checks)
- Compositor logic (cell blending, layer operations)
- Pure functions with no external dependencies

**Key rule**: **NO Hermes runtime in unit tests**. If it needs JavaScript, it's an E2E test.

```zig
// tests/unit/buffer_test.zig
test "buffer insert at position" {
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.insertAt(0, "hello");
    try std.testing.expectEqualStrings("hello", buffer.content.items);
}
```

### Level 2: E2E Tests (Full Stack)

**Location**: `tests/e2e/`
**Run**: `vimc test <sandbox>` (e.g., `vimc test tests/e2e/motion`)
**Speed**: ~100ms per test (fresh process each)

**What belongs here**:
- Vim command sequences (`jjj`, `viwd`, `dd`)
- TypeScript plugin behavior (`vim.motion.*`, `vim.opt.*`)
- User-facing workflows (editing, visual mode, registers)
- Terminal rendering validation (ANSI escape codes)
- Anything that needs Hermes/JSI

**Architecture**: PTY + JSON protocol

```
┌────────────────────────────────────────────┐
│              Vimcraft Process              │
│                                            │
│   stdin ──> Vim commands ──> Editor        │
│                                │           │
│                                v           │
│                          Terminal renders  │
│                          to PTY (internal) │
│                                │           │
│   stdout <── JSON state responses          │
│                                            │
└────────────────────────────────────────────┘
```

**Each E2E test has a sandbox** with its own TypeScript plugin:

```
tests/e2e/
├── motion/
│   ├── config.ts        # Optional TypeScript plugin for this test
│   └── e2e.ts           # Test cases (TypeScript)
├── rendering/
│   ├── config.ts        # Plugin config
│   └── e2e.ts           # PTY capture tests for terminal output
└── ...
```

**Example E2E test**:
```typescript
// tests/e2e/motion/e2e.ts
vim.e2e.describe("vim.motion API", function() {
    vim.e2e.test("left moves cursor", function() {
        vim.e2e.keys("lllll");  // Move to col 5
        vim.motion.left();       // Execute motion
        vim.e2e.assert.cursorAt(0, 4);  // Assert col 4
    });
});
vim.e2e.runAll();
```

### Test Isolation: Fresh Process Per Test

**Critical**: Each E2E test spawns a **fresh Vimcraft process** for 100% isolation.

Why not session reuse?
- Hermes has no "unload module" capability
- Global JS variables persist between tests
- Timers, user commands, keymaps leak across tests
- 100ms startup is fast enough

```zig
test "test A" {
    var pty = try spawnVimcraft();  // Fresh process
    defer pty.kill();
    // ... test A ...
}  // Process killed

test "test B" {
    var pty = try spawnVimcraft();  // Fresh process (no state from A)
    defer pty.kill();
    // ... test B ...
}
```

### PTY + JSON Protocol

**Input**: Raw Vim commands (what you'd type in Vim)
**Output**: JSON state responses (structured, parseable)

```bash
# Send Vim commands
:e /tmp/test.txt
jjj
:DebugState

# Receive JSON
{"cursor":{"row":3,"col":0},"mode":"NORMAL","modified":false}
```

**Available debug commands**:
- `:DebugState` - Full editor state snapshot
- `:DebugLayers` - Compositor layer info
- `:DebugRegisters` - All register contents
- `:DebugLogs` - Recent log entries

### TypeScript Plugin Flow in E2E

```
config.ts → esbuild → config.js → hermesc → config.hbc → Hermes
```

1. **Write TypeScript plugin** (`config.ts`)
2. **Transpile** to JavaScript via esbuild
3. **Compile** to Hermes bytecode (.hbc)
4. **Cache** for subsequent runs
5. **Load** in fresh Vimcraft process

### Build Commands

```bash
zig build test                          # Run unit tests only (fast, ~100ms total)
vimc test tests/e2e/motion              # Run single E2E test sandbox
for d in tests/e2e/*/; do vimc test "$d"; done  # Run all E2E tests
```

### When to Write Each Type

| Scenario | Test Type | Why |
|----------|-----------|-----|
| Buffer insert/delete | Unit | Pure Zig logic |
| Rope balancing | Unit | Data structure |
| Cursor boundary check | Unit | Pure calculation |
| `vim.motion.left()` works | E2E | Needs Hermes + Editor |
| `:MyCommand` works | E2E | Needs plugin loaded |
| Visual mode + yank | E2E | User workflow |
| ANSI escape codes | E2E | Terminal rendering |

### Current Test Structure

| Location | Purpose |
|----------|---------|
| `src/**/*_test.zig` | Pure Zig unit tests (run via `zig build test`) |
| `tests/e2e/*/e2e.ts` | E2E tests with Hermes runtime |
| `tests/e2e/rendering/e2e.ts` | Terminal output validation (ANSI escape codes) |

### Quick Reference

```
Unit tests:
- Pure Zig only
- No Hermes
- ~1ms per test
- zig build test

E2E tests:
- Full stack (Hermes + TypeScript)
- Fresh process per test
- ~100ms per test
- vimc test tests/e2e/<sandbox>
```

## Logging Architecture

**Core→Backend design**: ALL logging through `editor.logger`.

**Principle**: Single Source of Truth
- ✅ `editor.logger.debug("Cursor at row={} col={}", .{row, col})`
- ✅ `editor.logger.info("LAYER[cursor]: dirty={} cells={}", .{dirty, count})`
- ✅ Log transformations: `"Blend: {u}+{u}→{u}", .{src.char, dst.char, result.char}`
- ❌ NO `std.debug.print()` (bypasses logging system)
- ❌ NO unstructured output

**Backends**:
- Terminal mode (`--debug`): Chrome DevTools Console via CDP
- E2E mode (`vimc test`): `vim.e2e.getLogs()` for test introspection
- Ring buffer (1000 entries, FIFO)

**When to Log**: State transitions, user actions, errors, transformations. AVOID hot loops, trivial getters.

## Debugging Principles

**8 Proven Principles** (from cursorline and cursor flickering bug fixes):

1. **Simplest Test Case** - Single file, minimal content (not full app)
2. **Trust User Reports** - Don't over-theorize, believe symptom descriptions
3. **Check Data Flow** - Trace through pipeline: Buffer→Compositor→Diff→Terminal
4. **Type Conversions** - Red flag for data loss (early returns, optional handling)
5. **Log Transformations** - Show before→after, not just final state
6. **Targeted Tests** - Verify fix + edge cases + no side effects
7. **Follow Breadcrumbs** - User reports contain critical clues
8. **Use the Right Tool** - E2E tests for logic bugs, `vim.e2e.pty.*` for rendering bugs

### E2E PTY Capture for Rendering Bugs

**Cursor Flickering Bug** (January 2025) - Perfect example of tool selection:

**Bug**: Cursor flickered between bright/faded states during rapid input (holding 'j')

**What basic E2E Tests Show** (not helpful for this bug):
```json
{"mode":"NORMAL","cursor":{"line":10,"col":0}}  // Internal state correct ✅
// But NO information about terminal escape codes being sent!
```

**What `vim.e2e.pty.*` Catches** (immediately reveals the problem):
```typescript
// tests/e2e/rendering/e2e.ts
vim.e2e.describe("Cursor Flickering", function() {
    vim.e2e.test("rapid movements have minimal cursor toggles", function() {
        vim.e2e.pty.startCapture();
        vim.e2e.keys("jjjjjjjjjjjjjjjjjjjj"); // 20 rapid movements
        vim.e2e.pty.render();

        const hideCount = vim.e2e.pty.countHideCursor();
        const showCount = vim.e2e.pty.countShowCursor();
        vim.e2e.pty.stopCapture();

        // Should be <10 toggles, not 40!
        vim.e2e.assert.true(hideCount + showCount < 10, "Excessive flickering");
    });
});
```

**Root Causes Found** (via `vim.e2e.pty.*` API):
1. Redundant cursor shape codes (`\x1b[2 q`) sent 20× per second
2. Redundant cursor visibility toggle (`\x1b[?25l`, `\x1b[?25h`) 40× per second

**Key Insight**: Basic E2E tests show state is correct, but `vim.e2e.pty.*` captures actual terminal output to reveal rendering bugs.

### Tool Selection Guide

**Use `vim.e2e.*` (state inspection) When**:
- ✅ Debugging crashes/panics (exact stack traces)
- ✅ Verifying internal state (cursor position, mode, buffer content)
- ✅ Tracing logic errors (wrong calculations, incorrect flow)
- ✅ Inspecting layer composition (what's enabled/dirty)
- ✅ Analyzing logs for state transitions

**Use `vim.e2e.pty.*` (terminal capture) When**:
- ✅ Validating terminal output (ANSI escape codes)
- ✅ Catching visual artifacts (flickering, incorrect colors)
- ✅ Testing timing-sensitive bugs (rapid input handling)
- ✅ Verifying user experience (what user actually sees)
- ✅ Counting redundant operations (escape code frequency)

**Combine Both When**:
- ✅ Complex bugs with state + rendering components
- ✅ First reproduce with `vim.e2e.pty.*`, then diagnose with state APIs
- ✅ Verifying complete fix (state correct AND rendering smooth)

### Common Bug Patterns by Tool

**Caught by `vim.e2e.*` (state inspection)**:
- Early return optimization → Skips validation (check opacity >= 1.0 returns)
- Type conversion → Loses data (@intFromFloat with NaN/Infinity)
- Null handling → Assumes non-null when optional (check .? usage)
- State transitions → Mode not changing, cursor wrong position
- Logic errors → Wrong calculations, incorrect conditions

**Caught by `vim.e2e.pty.*` (terminal capture)**:
- Redundant escape codes → Terminal codes sent unnecessarily
- Visual flickering → Cursor visibility toggled too often
- Color bleeding → ANSI reset codes missing
- Terminal-specific bugs → Works in one terminal, breaks in another
- Performance issues → Too many escape codes overwhelming terminal

**Requires Both**:
- Input handling bugs → Key processed (state OK) but display wrong (terminal output)
- Rendering pipeline bugs → State correct but output corrupted
- Timing bugs → State updates but render lags

### Debugging Workflow Examples

**Mandatory Workflow for Crashes**:
```
1. REPRODUCE with E2E test (get exact stack trace)
2. READ error output (don't guess - read the panic message)
3. ZONE scope (narrow to exact function/line, not "somewhere in X")
4. IMPLEMENT fix (single targeted fix, not shotgun approach)
5. VERIFY with E2E test (test passes = bug fixed)
6. ITERATE if needed (but should fix in 1-2 iterations max)
```

**Rendering Bug Investigation Workflow**:
```typescript
// Use vim.e2e API to inspect each pipeline stage
vim.e2e.describe("Debug rendering bug", function() {
    vim.e2e.test("check layer composition", function() {
        // 1. Verify source data (Buffer layer)
        const state = vim.e2e.getState();
        console.log("Buffer:", state.buffer);

        // 2. Check layer composition (Compositor)
        const layers = vim.e2e.getLayers();
        console.log("Layers:", layers);

        // 3. Query debug logs (transformations)
        const logs = vim.e2e.getLogs({ level: "debug", maxBytes: 4096 });
        console.log("Logs:", logs);

        // 4. Identify WHERE data is lost (Buffer→Compositor→Diff→Terminal)
    });
});
vim.e2e.runAll();
```

**Terminal Output Bug Workflow**:
```typescript
// tests/e2e/rendering/e2e.ts - Use vim.e2e.pty.* API
vim.e2e.describe("Debug terminal output", function() {
    vim.e2e.test("check escape codes", function() {
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys("jjj");  // Trigger movements
        vim.e2e.pty.render();

        // Count specific escape codes
        const hideCount = vim.e2e.pty.countHideCursor();
        const posCount = vim.e2e.pty.countCursorPositionCodes();
        const sgrCount = vim.e2e.pty.countSGRCodes();

        vim.e2e.pty.stopCapture();

        console.log("Hide cursor codes:", hideCount);
        console.log("Position codes:", posCount);
        console.log("SGR codes:", sgrCount);
    });
});
```

**Add Debug Logs When Investigating** (make data flow visible):
```zig
// Log transformations (CRITICAL for tracing bugs)
editor.logger.debug("TRANSFORM[{s}]: before={} after={}", .{component, before, after});
editor.logger.debug("LAYER[{s}]: enabled={} dirty={} cells={}", .{name, enabled, dirty, count});
editor.logger.debug("BLEND: src={u} dst={u} result={u}", .{src.char, dst.char, result.char});

// Log terminal escape codes for debugging
editor.logger.debug("ESCAPE: sending {s}", .{escape_code});
editor.logger.debug("CURSOR: shape={s} visibility={}", .{shape, visible});
```

**Success Metrics**: Fix in 1-2 iterations (not 5-10), root cause identified (not guessed), verified with E2E tests (state + terminal output).

**Reference**: See [docs/bugfixes/cursor-flickering-fix.md](docs/bugfixes/cursor-flickering-fix.md) for detailed case study.

## Test-Driven Development (TDD)

**CRITICAL**: Vimcraft strictly follows TDD methodology to ensure correctness and prevent regressions.

### TDD Workflow (MANDATORY)

```
1. WRITE FAILING TEST FIRST (specify correct behavior)
2. VERIFY TEST FAILS (confirms test catches the bug)
3. IMPLEMENT MINIMUM CODE (make test pass)
4. VERIFY TEST PASSES (confirms fix works)
5. REFACTOR IF NEEDED (improve code while tests pass)
```

### Why TDD Matters

**Anti-Pattern** (testing current behavior):
```zig
// ❌ WRONG: Test validates what code DOES (buggy behavior)
test "o command" {
    try editor.executeKeys("o");
    const result = editor.buffer.content.items;
    try std.testing.expectEqualStrings("ab\nc", result); // Tests the BUG!
}
```

**Correct Pattern** (testing desired behavior):
```zig
// ✅ CORRECT: Test specifies what code SHOULD do
test "o command opens line AFTER current line" {
    // Setup: "abc\n"
    try editor.buffer.content.appendSlice(allocator, "abc\n");
    try editor.buffer.buildLineIndex();

    // Execute 'o' from position (0,0)
    try editor.executeKeys("o");

    // Expected: Cursor at (1,0), mode INSERT, buffer unchanged except newline added
    try std.testing.expectEqual(@as(usize, 1), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.col);
    try std.testing.expect(editor.mode_manager.isInsert());
    // Verify newline was inserted AFTER 'abc', not before 'c'
    try std.testing.expectEqualStrings("abc\n\n", editor.buffer.content.items);
}
```

### TDD Rules for Vimcraft

1. **Write Test First**: NO exceptions. Test must fail before implementation.
2. **Test Correct Behavior**: Specify what SHOULD happen, not what currently happens.
3. **Edge Cases**: Explicitly test boundaries (empty lines, end of file, etc.).
4. **One Test Per Behavior**: Each test verifies ONE specific behavior.
5. **Use E2E Tests**: Verify fixes with `vimc test` for integration testing.

### Example: TDD for Bug Fix

**User Report**: "`o` command includes last character of current line"

**Step 1: Write Failing Test**
```zig
test "o command does NOT include last character" {
    try editor.buffer.content.appendSlice(allocator, "abc\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 0, .col = 1 }; // At 'b'

    try editor.executeKeys("o");
    try editor.executeKeys("def"); // Type on new line

    // Should be "abc\ndef", NOT "ab\ndefc"
    try std.testing.expectEqualStrings("abc\ndef\n", editor.buffer.content.items);
}
```

**Step 2: Verify Test Fails** (run `zig build test`)
- Test output: Expected "abc\ndef\n", got "ab\ndefc\n" ✅ Test correctly detects bug

**Step 3: Implement Fix**
```zig
'o' => {
    const visual_len = self.buffer.getLineLengthVisual(self.buffer.cursor.row);
    self.buffer.cursor.col = visual_len; // Position AFTER last char
    try self.buffer.insertChar('\n');
    self.mode_manager.enterInsert();
},
```

**Step 4: Verify Test Passes** (run `zig build test`)
- All tests pass ✅

**Step 5: Verify with E2E Test**
```typescript
// tests/e2e/o_command/e2e.ts
vim.e2e.describe("o command bug fix", function() {
    vim.e2e.test("o does NOT include last character", function() {
        // Setup: Create file with "abc"
        vim.e2e.keys(":e /tmp/test_o.txt<CR>");
        vim.e2e.keys("cwabc<Esc>");

        // Execute 'o' from position (0,0)
        vim.e2e.keys("0o");
        vim.e2e.keys("def<Esc>");

        // Verify: cursor at (1,3), file contains "abc\ndef"
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.cursorAt(1, 2);  // After ESC, cursor at col 2
    });
});
vim.e2e.runAll();
```

### Common TDD Mistakes

1. **Writing Tests After Implementation** → Tests validate bugs instead of catching them
2. **Testing Implementation Details** → Tests break on refactoring
3. **Vague Assertions** → Tests pass but don't verify correctness
4. **No Edge Cases** → Bugs slip through common-case tests
5. **Ignoring Test Failures** → "I'll fix the test later" → Technical debt

### TDD + E2E Tests

**Best Practice**: Combine unit tests (fast) with E2E tests (integration):

```
Unit Test (zig build test)    → Verify logic correctness
E2E Test (vimc test)          → Verify end-to-end behavior
```

**Workflow**:
1. Write unit test specifying behavior
2. Implement until unit test passes
3. Verify with E2E test to catch integration issues
4. If E2E test reveals issues, write MORE unit tests

### Success Criteria

- ✅ Test written BEFORE code
- ✅ Test fails initially (proves it catches the bug)
- ✅ Test specifies correct behavior (not current behavior)
- ✅ Test passes after implementation
- ✅ E2E test confirms fix works end-to-end

**Remember**: Tests are specifications, not validation. Write the test you WISH you had when debugging.

## Architecture

### Current (Phase 1+2+3)

```
vimcraft/
├── src/
│   ├── main.zig              # Entry point, event loop
│   ├── editor/               # Editor core
│   │   ├── editor.zig        # Main editor coordinator
│   │   ├── buffer/           # Text buffer management
│   │   │   ├── buffer.zig    # Buffer (ArrayList-based, transactions, undo)
│   │   │   ├── edit.zig      # Edit operations (delete, change)
│   │   │   ├── yank.zig      # Yank operations
│   │   │   ├── paste.zig     # Paste operations
│   │   │   └── visual_ops.zig # Visual mode operators
│   │   ├── register/         # Register system
│   │   │   └── register.zig  # 39 registers (unnamed + named)
│   │   └── config/           # Configuration
│   │       └── highlights.zig # Highlight settings
│   ├── backends/             # Backend implementations
│   │   ├── terminal/         # Terminal backend
│   │   │   ├── backend.zig   # Terminal I/O (bracketed paste)
│   │   │   ├── display/      # Terminal rendering
│   │   │   └── visual/       # Visual mode
│   │   └── debug/            # Debug utilities
│   │       ├── protocol.zig  # JSON-RPC commands (used by E2E)
│   │       └── state.zig     # State serialization
│   ├── mode/mode.zig         # Mode state machine
│   ├── movement/movement.zig # Vim movement primitives
│   ├── core/log.zig          # Unified logging (ring buffer)
│   └── system/jsi/           # Hermes JSI bridge
├── examples/                 # Hermes+JSI demos
├── vendor/                   # Git submodules (hermes, ghostty, neovim)
└── build.zig                 # Zig build system
```

### Three-Layer Vision

1. **Editor Core (Zig)** - Buffer management, rendering, input handling
2. **JSI Bridge (C++)** - Zero-copy interface between Zig and JavaScript (~13x faster than FFI)
3. **Plugin Layer (JavaScript)** - Extensions, LSP, configs via Hermes bytecode

### Keymap Architecture: Immediate Execution + Stateful Pending

**Critical Design Decision** (December 2025): After deep analysis of Neovim and Helix, Vimcraft uses **Helix-style stateful keymaps** instead of Neovim's typeahead buffer.

**Why**: Immediate execution is essential for clean JSI integration:
```javascript
// Plugin-friendly: Synchronous execution
vim.keymap.set('n', 'K', () => {
    vim.motion.up();  // Immediate
    vim.motion.up();  // Clean, no buffering
});
```

**Architecture Comparison**:

| Feature | Neovim | Helix | Vimcraft |
|---------|--------|-------|----------|
| Input Model | Buffered (`typebuf`) | Immediate | Immediate ✅ |
| Pending State | In typeahead buffer | In keymap state | In keymap state ✅ |
| Timeout Support | Yes (blocking I/O) | No (ESC to cancel) | Optional (via setTimeout) |
| JSI-Friendly | No (C-style buffering) | N/A | Yes ✅ |

**Key Implementation**:
- `KeymapManager` has `pending_keys: ArrayList(u8)` for accumulating partial matches
- `lookup()` returns `LookupResult` enum: `.matched`, `.pending`, `.not_found`
- On `.pending`, caller waits for next key (or timeout expires)
- Timeout uses JSI `setTimeout` (React Native-style async)

**Rationale**:
1. ✅ **Preserves immediate execution** (original design intent)
2. ✅ **Proven by Helix** (production-ready architecture)
3. ✅ **No typeahead buffer** (simpler than Neovim)
4. ✅ **Optional timeout** (can be disabled for cleaner UX)
5. ✅ **Future-proof** (won't need refactoring in Phase 5-6)

**Reference**: Helix uses `state: Vec<KeyEvent>` in `Keymaps` struct (keymap.rs:293), proving immediate execution + stateful pending works in production.

**Status**: Buffer-local mappings ✅, Prefix detection ✅, Timeout support 🚧 (Phase 4).

### Hybrid Build System

**Critical**: Zig linker bug (C++ exception metadata in `__eh_frame`) requires hybrid build:
1. Zig compiles to `.o` object files (`zig build-obj`)
2. `clang++` performs final linking with Hermes libraries

This is the **proper solution**, not a workaround.

### Filetype Detection (go-enry Integration)

**System**: Runtime language detection using go-enry (GitHub Linguist C library, 697 languages).

**Why go-enry over Neovim's filetype.lua**:
- ✅ **Content-based detection** (handles `.h` disambiguation, shebangs, modelines)
- ✅ **Industry standard** (same engine powering GitHub.com language detection)
- ✅ **2x faster** than Ruby Linguist, 697 languages vs Neovim's 1,437 patterns
- ✅ **Bayesian classifier** for ambiguous files (`.rs` → Rust vs RenderScript)
- ✅ **No build-time generation** (simpler build process)

**Architecture**:
- C Library: `vendor/go-enry/.shared/darwin/libenry.dylib` (10MB, built from Go)
- C FFI: `src/system/enry/c_api.zig` (GoString/GoSlice type mappings)
- Zig Wrapper: `src/system/enry/enry.zig` (high-level API)
- Integration: `src/editor/treesitter/loader.zig` calls `enry.detectLanguage()`

**Detection Strategies** (in order):
1. Extension → `.rs` → Rust
2. Filename → `Makefile` → Makefile
3. Shebang → `#!/usr/bin/env python` → Python
4. Modeline → `# vim: set ft=python:` → Python
5. Content heuristics → Disambiguates C vs C++ for `.h` files
6. Bayesian classifier → Final fallback for ambiguous cases

**Build Integration**:
```zig
// build.zig (lines 289-299)
exe.addLibraryPath(b.path("vendor/go-enry/.shared/darwin"));
exe.linkSystemLibrary("enry");
exe.addRPath(b.path("vendor/go-enry/.shared/darwin"));
```

**Runtime Path** (macOS):
```bash
DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin:vendor/hermes/build/API/hermes:vendor/hermes/build/jsi
```

**Known Issues**:
- Memory leaks (allocated language strings not freed - minor, only once per file open)
- TODO: Use arena allocator or cache results (documented in loader.zig:126)

**Testing**:
- Unit tests: `zig build test` → Verifies .c, Makefile, .rs detection
- Stack traces confirm integration: c_api.zig → enry.zig → loader.zig → vim_filetype_match

**Code Locations**:
- C FFI: src/system/enry/c_api.zig:1-83
- Zig wrapper: src/system/enry/enry.zig:1-53
- Integration: src/editor/treesitter/loader.zig:119-128
- Build config: build.zig:289-299

### JSI HostObject Architecture (Zero-Copy Plugin API)

**Status**: ✅ Complete (January 2025) - 7 major APIs migrated, 3-5x performance gain

**Architecture**: React Native-inspired zero-copy property access pattern for JavaScript↔Zig communication.

**Performance**:
- Property access: ~168 ns/call (6M ops/sec)
- **3-5x faster** than legacy function-based JSI
- Zero serialization overhead
- O(1) property dispatch via StaticStringMap

#### HostObject Pattern Overview

**Flow**:
```
JavaScript → Proxy → C++ CustomHostObject → Zig HostObject Getter → Implementation
```

**Key Components**:

1. **JavaScript Proxy** (`runtime.js`) - Chrome DevTools support, special handling
2. **C++ CustomHostObject** (`hermes_c_api.cpp`) - JSI↔Zig bridge
3. **Zig HostObject Getter** (`*_api.zig`) - O(1) dispatch via StaticStringMap
4. **Zig Implementation** - Core functionality

#### Migrated APIs (8 total, 12 HostObjects)

**1. vim.motion** (motion_api.zig)
- 13 cursor movement primitives
- Use case: Smooth cursor animations (smear-cursor)

**2. vim.opt/optLocal/optGlobal/bo** (config_api.zig)
- 80+ Vim options with dynamic property access
- Auto-scoped (opt), explicit local (optLocal), explicit global (optGlobal)
- Buffer properties (bo) - filetype, etc.

**3. vim.cursor** (cursor_api.zig)
- getPosition(), setRenderPosition(), clearRenderPosition()
- Use case: Animated cursor plugins

**4. vim.layer** (layer_api.zig)
- 9 methods for virtual text rendering
- Use case: Neovim-style extmarks (diagnostics, inline hints)

**5. vim.keymap** (keymap_api.zig)
- set(), del() - Custom key mappings
- Neovim-compatible: mode, lhs, rhs, opts

**6. vim.filetype** (filetype_api.zig)
- match() - Language detection via go-enry (697 languages)
- Returns GitHub Linguist language names ("Rust", "JavaScript")

**7. vim.buffer** (buffer_api.zig) - NEW!
- getContent() → ArrayBuffer (zero-copy snapshot)
- getLineContent(n) → ArrayBuffer (line view)
- getLength(), getLineCount()
- Use case: Zero-copy buffer content access from JavaScript

**8. vim.e2e** (e2e_api.zig) - NEW!
- E2E testing and plugin development debugging API
- keys(), getCursor(), getState(), getMode(), getLayers(), getLogs()
- describe(), test(), runAll() - Jest/Mocha-style test structure
- assert.* - Rich assertion library (equal, mode, cursorAt, bufferContains)
- Use case: E2E tests AND interactive plugin debugging
- See [docs/api/vim-e2e.md](docs/api/vim-e2e.md) for complete API reference

#### Implementation Pattern

**Step 1: Zig HostObject Getter** (O(1) property dispatch):
```zig
pub export fn vimOptHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    // O(1) dispatch via StaticStringMap
    const PropertyMap = std.StaticStringMap(...).initComptime(.{
        .{ "method1", method1Function },
        .{ "method2", method2Function },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}
```

**Step 2: JavaScript Proxy Wrapper** (special handling):
```javascript
vim.opt = new Proxy(
    { get [Symbol.toStringTag]() { return 'vim.opt'; } },
    {
        get(target, prop) {
            if (prop === Symbol.toStringTag) return 'vim.opt';
            if (typeof prop === 'symbol') return undefined;
            return vimOpt[prop]; // Direct HostObject access (zero-copy)
        },
        set(target, prop, value) {
            if (typeof prop === 'symbol') return false;
            vimOpt[prop] = value; // Direct HostObject write
            return true;
        },
        ownKeys(target) {
            // Fetch fresh snapshot for Chrome DevTools
            const allOptions = getAllOptions();
            for (const key of Object.keys(target)) delete target[key];
            Object.assign(target, allOptions);
            return Object.keys(target);
        }
    }
);
```

**Step 3: Registration**:
```zig
pub fn register(runtime: *c.OVHermesRuntime, context: *Context) void {
    c.hermes_register_host_object(
        runtime,
        "vimOpt",
        vimOptHostObjectGet,
        vimOptHostObjectSet, // or null for read-only
        vimOptHostObjectEnumerator,
        @ptrCast(context),
    );
}
```

#### Rope Data Structure (Future Buffer Optimization)

**Location**: `src/editor/buffer/rope.zig`

**Purpose**: Tree-based string for O(log n) edits (vs ArrayList's O(n))

**Performance**:
| Operation | ArrayList | Rope |
|-----------|-----------|------|
| Insert/Delete | O(n) | O(log n) |
| Concat | O(n) | O(1) |
| Index | O(1) | O(log n) |

**Structure**:
- Internal nodes: Concatenation (left + right subtrees)
- Leaf nodes: String slices (512 bytes for cache locality)
- Self-balancing: Weight heuristic (left subtree byte count)

**Status**: Implementation complete ✅, buffer migration pending (Phase 6)

**Future**: When buffer migrates to Rope, ArrayBuffer can expose Rope leaf nodes directly (true zero-copy, no snapshot semantics).

#### API Migration Path

**Legacy (Phase 1-3)**:
```javascript
setOption("number", true);
moveLeft();
getCursorPosition();
```

**HostObject (Phase 4+)**:
```javascript
vim.opt.number = true;
vim.motion.left();
vim.cursor.getPosition();
```

**Backwards Compatibility**: Dual registration maintained during transition.

**Timeline**:
- Phase 4 (Current): Both APIs supported
- Phase 5 (TBD): Deprecation warnings for legacy
- Phase 6 (TBD): Legacy removal

#### Documentation

- **API Reference**: [docs/api/vim-api-reference.md](docs/api/vim-api-reference.md) - Complete API documentation
- **Migration Guide**: [docs/api/vim-api-migration-guide.md](docs/api/vim-api-migration-guide.md) - Legacy→HostObject migration
- **Architecture Details**: [docs/architecture/jsi-hostobject-architecture.md](docs/architecture/jsi-hostobject-architecture.md) - Deep dive
- **Migration Summary**: [docs/architecture/jsi-hostobject-migration-summary.md](docs/architecture/jsi-hostobject-migration-summary.md) - Metrics and lessons learned

#### Performance Benchmarks

**Property Lookup** (1M iterations):
```
Time per lookup: 168 ns
Operations/sec: 6M ops/sec
Speedup vs legacy: 3-5x
```

**Code Location**: `src/system/jsi/tests/benchmark.zig`

#### Common Pitfalls

1. **Hot loops**: Cache property values, don't call JSI 1000x
   ```javascript
   // ❌ Inefficient (1000 JSI calls)
   for (let i = 0; i < 1000; i++) {
     process(vim.opt.tabstop);
   }

   // ✅ Efficient (1 JSI call)
   const tabstop = vim.opt.tabstop;
   for (let i = 0; i < 1000; i++) {
     process(tabstop);
   }
   ```

2. **Calling convention**: Use `.c` not `.C` (Zig 0.13+)

3. **Function visibility**: Use `pub export fn` not `export fn` (Zig+C visibility)

4. **ArrayBuffer snapshots**: Buffer modifications invalidate ArrayBuffers (TODO: version tracking)

## Rendering Optimizations (Phase 4 - January 2025)

**Status**: ✅ Core optimizations complete, 2-10x performance improvement for plugins

Vimcraft implements a comprehensive set of rendering optimizations combining techniques from **Neovim**, **Helix**, and modern terminal emulators. These optimizations ensure smooth performance even with aggressive plugin rendering.

### Summary of Optimizations

| Optimization | Status | Impact | Implementation |
|--------------|--------|--------|----------------|
| **1. Synchronized Updates** | ✅ Complete | 2x improvement | DCS sequences (`\x1bP=1s\x1b\\` ... `\x1bP=2s\x1b\\`) |
| **2. Event Batching** | ✅ Exists | Architectural win | Main loop renders once per iteration |
| **3. Render Throttling** | ✅ Complete | Plugin protection | 60 FPS limit (16.67ms frame time) |
| **4. Color/Attribute Tracking** | ✅ Exists | Helix pattern | Within-frame deduplication |
| **5. Cursor Position Tracking** | ✅ Complete | Eliminates flicker | Cross-frame state persistence |
| **6. Scroll Regions** | 🏗️ Infrastructure | Future Phase 6 | Primitives ready, integration deferred |
| **7. Rectangular Dirty Regions** | 📋 Deferred | Future Phase 6 | Requires diff algorithm refactor |
| **8. Compositor Fast-Path** | ✅ Complete (Week 3) | 1.6-1.8x speedup | Integer-only blending + zero-cost copy |
| **9. Terminal Output Batching** | ✅ Complete (Week 4) | 30-70% reduction | Sort updates by (row, col) |

### 1. Terminal Synchronized Updates ✅

**Problem**: Terminal updates incrementally during render → visible tearing/flickering
**Solution**: Batch ALL output and flush atomically (DCS sequences)

**Implementation** (`terminal_control.zig:139-162`, `display.zig:426,494`):
```zig
// Begin synchronized update
try self.beginSynchronizedUpdate();  // \x1bP=1s\x1b\\

// ... all rendering code ...

// End synchronized update (atomic flush)
try self.endSynchronizedUpdate();    // \x1bP=2s\x1b\\
try self.flush();
```

**Supported Terminals**: iTerm2, Alacritty, WezTerm, tmux
**Performance**: ~2x improvement (eliminates all mid-frame tearing)
**Graceful Degradation**: Auto-disables if terminal doesn't support DCS

### 2. Redraw Event Batching ✅

**Problem**: Multiple state changes trigger multiple renders per loop iteration
**Solution**: Accumulate all state changes, render once per iteration

**Implementation** (`main.zig:690-743`):
```zig
while (running) {
    // Accumulate state changes
    if (event_processor.tick()) needs_render = true;
    if (reload_state.needs_reload) needs_render = true;
    if (editor.js_state_dirty) needs_render = true;

    // Single render at end of iteration
    if (needs_render) {
        try backend.render();
        needs_render = false;
    }
}
```

**Performance**: 10-100x improvement (prevents redundant renders)
**Pattern**: Neovim-style redraw event batching

### 3. Render Throttling ✅

**Problem**: Plugins can trigger unlimited renders → freeze editor
**Solution**: Frame rate limiting using nanosecond-precision timing

**Implementation** (`main.zig:126-152,727-742`):
```zig
pub const RenderThrottle = struct {
    max_renders_per_sec: u64 = 60,
    last_render_time_ns: i128 = 0,
    min_frame_time_ns: i128,  // 16.67ms for 60 FPS

    pub fn shouldRender(self: *RenderThrottle) bool {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_render_time_ns;
        if (elapsed >= self.min_frame_time_ns) {
            self.last_render_time_ns = now;
            return true;
        }
        return false;  // Throttled!
    }
};
```

**Performance**: Prevents plugin-induced freezing
**Configuration**: Default 60 FPS (can be adjusted)
**Tracking**: `render_stats.throttled_renders` counts skipped frames

### 4. Color and Attribute Tracking ✅

**Problem**: Redundant escape codes for colors/attributes → terminal overhead
**Solution**: Track current state, only send changes (Helix pattern)

**Implementation** (`output_renderer.zig:46-181`):
```zig
// Track state WITHIN frame
var current_fg: ?highlights.Color = null;
var current_bg: ?highlights.Color = null;
var current_bold: bool = false;
var current_italic: bool = false;
var current_underline: bool = false;

// Only send if changed
if (update.cell.fg) |fg| {
    if (current_fg == null or !colorEql(current_fg.?, fg)) {
        // Send foreground escape code
        current_fg = fg;
    } else {
        opts.attribute_changes_deduped += 1;  // Track savings
    }
}
```

**Performance**: 50-90% reduction in attribute escape codes
**Pattern**: Helix optimization (resets attributes at end of frame)
**Tracking**: `optimizations.attribute_changes_deduped` counts skipped codes

### 5. Cursor Position Tracking ✅

**Problem**: Redundant cursor position codes during rapid movement → flickering
**Solution**: Track last position ACROSS frames, only move if changed

**Implementation** (`display.zig:69-74,478-485`):
```zig
// State persistence (across frames)
last_cursor_row: usize = 0,
last_cursor_col: usize = 0,

// Only move if position changed
if (self.last_cursor_row != screen_row or self.last_cursor_col != clamped_col) {
    try self.moveCursor(screen_row, clamped_col);
    self.last_cursor_row = screen_row;
    self.last_cursor_col = clamped_col;
}
```

**Performance**: Eliminated cursor flickering during rapid input (holding 'j')
**Impact**: Reduces cursor position codes from 42 to 0 for 10 movements
**Pattern**: Cross-frame state tracking (unlike within-frame color tracking)

### 6. Scroll Region Optimization 🏗️

**Problem**: Scrolling re-renders all visible lines → expensive
**Solution**: Use terminal native scroll regions (VT100 sequences)

**Infrastructure** (`terminal_control.zig:164-195`):
```zig
/// Set scroll region (0-indexed)
pub fn setScrollRegion(self: *Display, top: usize, bottom: usize) !void {
    try print(self, "\x1b[{d};{d}r", .{ top + 1, bottom + 1 });
}

/// Scroll content up by n lines
pub fn scrollUp(self: *Display, lines: usize) !void {
    if (lines == 0) return;
    try print(self, "\x1b[{d}S", .{lines});
}

/// Scroll content down by n lines
pub fn scrollDown(self: *Display, lines: usize) !void {
    if (lines == 0) return;
    try print(self, "\x1b[{d}T", .{lines});
}
```

**Status**: Infrastructure complete, integration deferred to Phase 6
**Complexity**: Requires render pipeline refactoring (scroll detection, direction tracking)
**Potential**: 10-100x improvement for scrolling operations

### 7. Rectangular Dirty Regions 📋

**Problem**: Currently track dirty LINES, but often only part of line changed
**Solution**: Track dirty RECTANGLES (row_start, row_end, col_start, col_end)

**Status**: Deferred to Phase 6 (requires diff algorithm refactor)
**Complexity**: High - changes to compositor, diff, and update structures
**Potential**: 50-90% reduction in cells updated for partial line changes

### 8. Compositor Fast-Path Blending ✅ (Week 3)

**Problem**: Porter-Duff alpha blending uses floating-point math for all cells, even fully opaque ones
**Solution**: Integer-only blending with fast-path for opacity 1.0

**Implementation** (`compositor.zig:341-416`):

**Fast-Path** (opacity >= 1.0, 95% of cells):
```zig
fn blendCell(src: Cell, dst: Cell, opacity: f32) Cell {
    // Fully opaque? Just replace (zero-cost copy)
    if (opacity >= 1.0 and src.char != 0 and src.char != ' ') return src;

    // ... blending for 0 < opacity < 1.0 ...
}
```

**Slow-Path** (0 < opacity < 1.0, 5% of cells):
```zig
fn blendChannel(src: u8, dst: u8, alpha: f32) u8 {
    // Integer-only blending (3x faster than floating-point)
    const alpha_int: u32 = @intFromFloat(@min(255.0, @max(0.0, alpha * 255.0)));
    const inv_alpha: u32 = 255 - alpha_int;

    const src_u32: u32 = @as(u32, src);
    const dst_u32: u32 = @as(u32, dst);

    const blended: u32 = (src_u32 * alpha_int + dst_u32 * inv_alpha) / 255;
    return @intCast(@min(255, blended));
}
```

**Performance Impact**:
- Fast-path (opacity 1.0): 0 cycles - zero-cost copy ✅
- Slow-path (opacity < 1.0): 3x faster than floating-point ✅
- Overall compositor: 1.6-1.8x speedup (7-13ms → 4-8ms)

**Metrics Tracked** (`compositor.zig:333-335`):
```zig
cells_fast_path_blended: usize = 0,  // Zero-cost copy operations
cells_slow_path_blended: usize = 0,  // Integer blending operations
```

**Reference**: Neovim uses similar integer-only blending ([grid.c:235](https://github.com/neovim/neovim/blob/master/src/nvim/grid.c#L235))

**Documentation**: [docs/development/week3-compositor-optimization.md](docs/development/week3-compositor-optimization.md)

### 9. Terminal Output Batching ✅ (Week 4)

**Problem**: Diff produces updates in arbitrary order → cursor jumps around screen → wasted cursor position codes
**Solution**: Sort updates by (row, col) before rendering to maximize adjacent cell batching

**Implementation** (`output_renderer.zig:46-58`):

```zig
// Sort updates to maximize spatial adjacency
const sorted_updates = try allocator.dupe(Update, updates);
defer allocator.free(sorted_updates);

std.mem.sort(Update, sorted_updates, {}, struct {
    fn lessThan(_: void, a: Update, b: Update) bool {
        if (a.row != b.row) return a.row < b.row;
        return a.col < b.col;
    }
}.lessThan);

// Process sorted updates (maximizes adjacent cell batching)
for (sorted_updates) |update| {
    // Existing adjacent cell skipping now triggers 8x more often!
    // ...
}
```

**Example Improvement**:

```
Unsorted: [(2,5), (0,10), (2,6), (1,0)]
  → Move (2,5) → char
  → Move (0,10) → char
  → Move (2,6) → char  ← WASTED! Was adjacent to (2,5)
  → Move (1,0) → char
  Total: 4 cursor moves

Sorted: [(0,10), (1,0), (2,5), (2,6)]
  → Move (0,10) → char
  → Move (1,0) → char
  → Move (2,5) → char
  → char  ← No move! Adjacent to (2,5)
  Total: 3 cursor moves (25% reduction)
```

**Performance Impact**:
- Random scatter: 5-15% reduction in cursor moves
- Horizontal text edits: 50-70% reduction (typical)
- Vertical column edits: 60-90% reduction
- **Synergy**: 8x higher hit rate for adjacent cell skipping

**Overhead**: O(N log N) sort ~1μs (negligible vs 50μs saved per cursor move)

**Metrics Tracked** (`output_renderer.zig:19-21`):
```zig
cursor_moves_total: usize = 0,    // Position codes sent
updates_sorted: usize = 0,        // Updates batched
```

**Documentation**: [docs/development/week4-terminal-batching.md](docs/development/week4-terminal-batching.md)

### Performance Benchmarks

**Before Optimizations** (theoretical baseline):
- 20 movements × 2 cursor codes each = 40 cursor position codes
- No synchronized updates = visible tearing on every frame
- No throttling = plugins can freeze editor
- No batching = multiple renders per loop iteration

**After Optimizations** (current):
- 20 movements × 0 cursor codes = 0 (100% reduction via tracking)
- Synchronized updates = zero tearing (2x perceived smoothness)
- Throttling = 60 FPS max (plugin protection)
- Batching = 1 render per iteration (architectural win)

**Measured Impact**:
- Cursor flickering: ✅ Eliminated (0 redundant position codes)
- Frame tearing: ✅ Eliminated (synchronized updates)
- Plugin spam: ✅ Protected (60 FPS throttle)
- Attribute overhead: ✅ Reduced by 50-90% (within-frame tracking)

### Code Locations

**Main Event Loop** (`src/main.zig`):
- Lines 126-152: `RenderThrottle` struct definition
- Lines 688-743: Main event loop with throttling integration
- Lines 1035-1090: Debug mode event loop with throttling integration

**Terminal Control** (`src/backends/terminal/display/terminal_control.zig`):
- Lines 139-162: Synchronized update (DCS sequences)
- Lines 164-195: Scroll region primitives (infrastructure)

**Display Manager** (`src/backends/terminal/display/display.zig`):
- Lines 69-74: Cursor position tracking state
- Lines 218-240: Scroll region wrapper functions
- Lines 426,494: Synchronized update integration in render()
- Lines 478-485: Cursor position tracking in render()

**Output Renderer** (`src/backends/terminal/display/output_renderer.zig`):
- Lines 46-53: Color/attribute tracking state
- Lines 84-181: Within-frame deduplication logic
- Lines 14-18: Optimization statistics

### Reference Materials

**Inspiration Sources**:
- **Neovim**: Grid protocol, redraw event batching
- **Helix**: Synchronized updates, attribute tracking, adjacent cell skipping
- **Modern Terminals**: iTerm2/Alacritty/WezTerm rendering techniques

**Related Bug Fixes**:
- [docs/bugfixes/cursor-flickering-fix.md](docs/bugfixes/cursor-flickering-fix.md) - Cursor position tracking case study

**Future Work**:
- Phase 6: Integrate scroll region optimization (requires viewport tracking)
- Phase 6: Implement rectangular dirty regions (requires diff algorithm refactor)
- Phase 7: Add terminal capability detection (query synchronization support)

### Key Takeaways

1. **Layered Optimizations**: Each optimization targets a different bottleneck (batching → throttling → deduplication → tracking)
2. **Graceful Degradation**: Optimizations fail gracefully (e.g., synchronized updates auto-disable)
3. **Measured Impact**: All optimizations have concrete metrics (throttled_renders, attribute_changes_deduped)
4. **Phase 6 Readiness**: Infrastructure for advanced optimizations (scroll regions) is ready for future integration

**Result**: Vimcraft now has production-ready rendering performance suitable for aggressive plugin use (smear-cursor, virtual text, diagnostics, etc.).

### Testing Infrastructure

**Status**: ✅ E2E tests with `vim.e2e.pty.*` API for terminal output validation

Rendering optimizations are validated using the E2E test framework with PTY capture capabilities.

**Location**: `tests/e2e/rendering/e2e.ts`
**Run**: `vimc test tests/e2e/rendering/`

**6 Test Categories**:

1. **Synchronized Updates** - Cursor visibility toggle counts
2. **Cursor Position Tracking** - Position code frequency
3. **Color/Attribute Tracking** - SGR code optimization
4. **Render Statistics** - Frame counts and timing
5. **Escape Sequence Patterns** - Custom pattern counting
6. **Flickering Detection** - Rapid input cursor stability

**Example Test**:
```typescript
vim.e2e.describe("Synchronized Updates", function() {
    vim.e2e.test("rapid movements have minimal cursor toggles", function() {
        vim.e2e.pty.startCapture();
        vim.e2e.keys("jjjjjjjjjjjjjjjjjjjj"); // 20 movements
        vim.e2e.pty.render();

        const hideCount = vim.e2e.pty.countHideCursor();
        const showCount = vim.e2e.pty.countShowCursor();
        vim.e2e.pty.stopCapture();

        vim.e2e.assert.true(hideCount + showCount < 50,
            "Should have <50 cursor toggles");
    });
});
```

**Running Tests**:
```bash
vimc test tests/e2e/rendering/   # Run rendering optimization tests
```

## Build Commands

### Main Editor

```bash
zig build                          # Build
./zig-out/bin/vimcraft <filename>   # Run
zig build test                     # Test
zig fmt src/                       # Format (4 spaces)
```

### Hermes+JSI Demos

```bash
make -f Makefile.hermes all      # Build demos
make -f Makefile.hermes test-zig # Run Zig→JS demo
make -f Makefile.hermes test-jsi # Run JS→Zig demo
```

### Bytecode

```bash
./hermesc -emit-binary -out output.hbc input.js  # Compile to .hbc
```

## Key Files

**Editor Core**:
- `src/editor/editor.zig` - Main editor coordinator
- `src/editor/buffer/buffer.zig` - Text buffer with transactions & undo
- `src/editor/buffer/{edit,yank,paste,visual_ops}.zig` - Text operations
- `src/editor/register/register.zig` - Register system (39 registers)

**Backends**:
- `src/backends/terminal/backend.zig` - Terminal I/O (bracketed paste)
- `src/backends/terminal/display/` - Terminal rendering
- `src/backends/debug/{protocol,state}.zig` - State serialization (used by E2E)

**System**:
- `src/main.zig` - Entry point
- `src/mode/mode.zig` - Mode state machine
- `src/movement/movement.zig` - Vim motion primitives
- `src/core/log.zig` - Unified logging
- `src/system/jsi/hermes_c_api.{h,cpp}` - Hermes JSI bridge

**Build**: `build.zig` (hybrid build system)

## Navigation Commands

**Character**: `h/j/k/l` · **Line**: `0/$^` · **Word**: `w/b/e`
**File**: `gg/G/Ctrl+D/Ctrl+U` · **Mode**: `i/a/I/A/ESC/q`

See Phase 1+2 complete list in original docs.

## Development Workflow

### Adding Host Functions (Zig callable from JS)

```zig
// 1. Define with C calling convention
export fn my_function(runtime: ?*c.OVHermesRuntime, context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue, arg_count: usize) callconv(.C) ?*c.OVHermesValue {
    // Implementation
}

// 2. Register
c.hermes_register_host_function(runtime, "myFunction", my_function, null);

// 3. JavaScript calls: myFunction(arg1, arg2)
```

### Testing Changes

Test both directions: Zig→JS and JS→Zig. Use `make -f Makefile.hermes test-zig` as smoke test.

**JavaScript API Pattern**: When JavaScript APIs modify editor state, set `js_state_dirty = true` to trigger re-render. See implementation details in [docs/api/vim-motion.md](docs/api/vim-motion.md) and existing examples in motion_api.zig, cursor_api.zig, config_api.zig.

### Building Hermes

If `vendor/hermes/build/` missing:
```bash
cd vendor/hermes && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -DHERMES_ENABLE_DEBUGGER=OFF -GNinja
ninja hermes hermesc  # ~287MB, gitignored
```

## Common Issues

**Terminal stuck after crash**: `reset` or `stty sane`
**"posix not found"**: Upgrade to Zig 0.13+ (`std.os.*` → `std.posix.*`)
**Submodule missing**: `git submodule update --init`
**Hermes dylib error**: Set `DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi` (Makefile handles this)

## Important Technical Details

**Hermes Submodule**: Pinned to ef620c2 (v0.12.0), use `git submodule update --init`
**Name Collisions**: All C types use `OV` prefix (`OVHermesRuntime`, `OVHermesValue`)
**Zig Formatting**: 4 spaces for indentation (`zig fmt src/`)
**Runtime Path (macOS)**: `DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi`

## Roadmap

**Phase 1+2** ✅ Text Display & Navigation (COMPLETE)
**Phase 3** ✅ Text Editing (COMPLETE - December 2025)
  - Delete operators (x, dd, dw, d{motion})
  - Change operators (c{motion}, cc, C)
  - Yank/paste (y{motion}, yy, p, P)
  - Bracketed paste (Cmd+V/Ctrl+V)
  - Register system (39 registers)
  - Undo/redo (u, Ctrl+R) with transaction grouping
  - Visual mode (v, V with d/c/y operators)
  - Visual paste replace (single undo operation)

**Phase 4** 🚧 Plugin System (NEXT - 6-8 weeks)
  - vim.opt full implementation (80+ options)
  - vim.keymap.set/del (key mapping system)
  - Autocommand system (event firing)
  - User command registration
  - vim.api buffer functions

**Phase 5** 📅 Advanced Features (Tree-sitter, LSP, search/replace, splits, tabs, macros)
**Phase 6** 📅 Performance (Rope data structure, incremental rendering, large files)
**Phase 7** 📅 Neovim Compatibility (Ex commands, options, API layer)

See [docs/roadmap/](docs/roadmap/) for detailed implementation plans.

## Documentation Maintenance

**Rule**: Documentation is first-class - update alongside code.

**When to Update**:
- New feature → API docs + guides
- Architecture change → Architecture docs + CLAUDE.md
- Bug fix → Troubleshooting (if user-facing)
- Roadmap item → Phase status

**Checklist Before Completion**:
- [ ] APIs documented in `docs/api/`
- [ ] Architecture changes in `docs/architecture/`
- [ ] Status updated in `docs/roadmap/`
- [ ] Entry points updated (`docs/README.md`)
- [ ] Links tested

**Quick Wins**: Fix broken links daily, add cross-references, update status markers (✅/🚧/📅).

**Remember**: Well-documented project = joy to work on. Poor docs = eternal debt.

---

**For complete details**: See [docs/README.md](docs/README.md) for full documentation navigation.
