# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Quick Navigation

**Critical Workflows**:
- [Testing Architecture](#testing-architecture-hybrid-approach) - PTY + Debug Protocol (complementary systems)
- [Test-Driven Development (TDD)](#test-driven-development-tdd) - MANDATORY workflow: write tests first
- [Logging Architecture](#logging-architecture) - Use `editor.logger`, not `std.debug.print`
- [Debugging Principles](#debugging-principles) - 8 proven principles + tool selection guide
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

## Testing Architecture: Hybrid Approach

**Critical**: Vimcraft uses **two complementary testing systems** for comprehensive coverage:

1. **PTY Testing** (95% terminal coverage) - Tests actual terminal backend via pseudoterminals
2. **Debug Protocol** (100% state introspection) - Inspects internal state and logs

See [docs/development/pty-testing.md](docs/development/pty-testing.md) for complete PTY guide.

### Quick Reference: When to Use Each System

**PTY Tests** (`zig build pty_tests`):
- ✅ **Terminal I/O validation** - Input parsing, ANSI output, user experience
- ✅ **Regression tests** - User-facing bugs (like `Aii` inserting on wrong line)
- ✅ **Render timing bugs** - Issues that only appear when rendering between keystrokes

**Debug Protocol** (`./zig-out/bin/vimc --debug-protocol`):
- ✅ **State inspection** - Cursor position, mode, registers, buffer content
- ✅ **Layer debugging** - Compositor pipeline, layer composition
- ✅ **Log analysis** - Filtered logs with `get_logs` command

**Best Practice**: Use BOTH! PTY reproduces user-facing bugs, Debug Protocol diagnoses root causes.

### Example: Hybrid Debugging Workflow

```bash
# Step 1: Reproduce bug with PTY (simulates real user)
zig test src/backends/terminal/tests/core_tests.zig --test-filter "Aii"
# Test fails: "ii" appears on line 2 instead of line 1

# Step 2: Diagnose with Debug Protocol (inspect internal state)
./zig-out/bin/vimc --debug-protocol &
PID=$!

echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'
echo '{"cmd":"get_state","id":"2"}'
# Response shows: cursor at (0,12), mode=INSERT

echo '{"cmd":"get_logs","args":{"level":"debug","max_bytes":4096},"id":"3"}'
# Logs reveal: "Skipping buildLineIndex (in transaction)"

kill $PID

# Step 3: Identify root cause
# enterInsertMode() starts transaction → prevents line_starts rebuild

# Step 4: Fix and verify with both systems
zig build test         # Unit tests pass
zig build pty_tests    # PTY tests pass (user experience validated)
```

## Debug Protocol & Verification System

**Role**: State introspection and logging (complements PTY tests, does NOT replace them)

### Background Mode (REQUIRED for Multi-Command Debugging)

**❌ WRONG** (one-shot mode wastes 67% on startup):
```bash
echo '{"cmd":"get_state","id":"1"}' | ./zig-out/bin/vimcraft --debug-protocol  # 195ms (130ms startup!)
```

**✅ CORRECT** (background mode - 10x faster):
```bash
./zig-out/bin/vimcraft --debug-protocol &
VIMCRAFT_PID=$!
echo '{"cmd":"get_state","id":"1"}'        # 65ms (no startup overhead)
echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'  # 65ms
kill $VIMCRAFT_PID
```

**Rule**: ALWAYS use background mode for 2+ commands. Startup cost amortized → 2.5x faster for 10 commands.

### Core Features

**Architecture**: Dual implementation with shared handlers (73% code deduplication)
- Terminal Mode: Unix socket server for live sessions (`debug_socket.zig`)
- Headless Mode: stdio/socket server for automated testing (`server.zig`)
- Shared Handlers: 5 unified command implementations (`handlers.zig`)
- Protocol: JSON-RPC over stdin/stdout (MCP-style) → Deep introspection, fast iteration, deterministic results

**Key Commands**:
- `get_state` - Full editor snapshot (mode, cursor, buffer, visual, registers)
- `execute_keys "viw"` - Simulate keystrokes
- `get_layers` - Layer state inspection
- `get_logs {"level":"info","max_bytes":4096}` - Query logs (size-limited for LLM context)

**Status**: Background mode ready ✅, JSON parser robust ✅, 8 layers tracked ✅, Handler unification complete ✅. See [docs/development/debug-protocol.md](docs/development/debug-protocol.md) for protocol spec, [docs/reviews/debug-handlers-unification-review.md](docs/reviews/debug-handlers-unification-review.md) for architecture details.

### When and How to Use Debug Protocol

**Decision Checklist** (use debug protocol when):
- [ ] Debugging crashes or panics → ALWAYS use to get exact line numbers
- [ ] Investigating rendering bugs → Use to inspect layer state at each stage
- [ ] Verifying multi-step operations → Use to check state after each step
- [ ] Testing new features → Use to verify correctness systematically
- [ ] User reports "X doesn't work" → Use to reproduce and inspect state

**Workflow Template for Bugs**:
```bash
# 1. Start in background mode (CRITICAL for multi-command debugging)
./zig-out/bin/vimcraft --debug-protocol &
PID=$!

# 2. Load test case
echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'

# 3. Execute operation that triggers bug
echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'

# 4. Inspect state at each pipeline stage
echo '{"cmd":"get_state","id":"3"}'        # Overall state
echo '{"cmd":"get_layers","id":"4"}'       # Layer composition
echo '{"cmd":"get_logs","args":{"level":"debug","max_bytes":4096},"id":"5"}'  # Debug logs

# 5. Analyze results, implement fix, repeat
kill $PID
```

**Common Debugging Scenarios**:

| Symptom | Debug Protocol Workflow |
|---------|------------------------|
| **Crash/Panic** | Run with `--debug-protocol` to get stack trace with exact line numbers |
| **No text rendered** | `get_layers` → check buffer layer has text → `get_logs` → check compositor blending |
| **Wrong colors** | `get_state` → inspect fg/bg values → `get_layers` → check layer colors |
| **Command doesn't work** | `execute_keys` → `get_state` → verify mode/cursor changed as expected |
| **Performance issue** | Check `duration_ns` in responses → identify slow commands |

**Key Principle**: For ANY bug investigation with 2+ debug commands, ALWAYS use background mode (not one-shot).

## Logging Architecture

**Core→Backend design**: ALL logging through `editor.logger` (or `editor_ctx.logger` in headless).

**Principle**: Single Source of Truth
- ✅ `editor.logger.debug("Cursor at row={} col={}", .{row, col})`
- ✅ `editor.logger.info("LAYER[cursor]: dirty={} cells={}", .{dirty, count})`
- ✅ Log transformations: `"Blend: {u}+{u}→{u}", .{src.char, dst.char, result.char}`
- ❌ NO `std.debug.print()` (bypasses logging system)
- ❌ NO unstructured output

**Backends**:
- Terminal mode (`--debug`): Chrome DevTools Console via CDP
- Headless mode (`--debug-protocol`): `get_logs` command with size limits
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
8. **Use the Right Tool** - Debug Protocol for logic bugs, PTY for rendering bugs

### Debug Protocol vs PTY Testing: Real-World Case Study

**Cursor Flickering Bug** (January 2025) - Perfect example of tool selection:

**Bug**: Cursor flickered between bright/faded states during rapid input (holding 'j')

**What Debug Protocol Shows** (not helpful for this bug):
```json
{"mode":"NORMAL","cursor":{"line":10,"col":0}}  // Internal state correct ✅
// But NO information about terminal escape codes being sent!
```

**What PTY Testing Would Catch** (immediately reveals the problem):
```zig
test "cursor codes not redundant" {
    var pty = try PTY.spawn("./zig-out/bin/vimcraft");

    // Hold 'j' for rapid movement
    for (0..20) |_| {
        try pty.send("j");
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    const output = try pty.readAll();
    // Count escape codes: \x1b[?25l (hide), \x1b[?25h (show)
    const hide_count = std.mem.count(u8, output, "\x1b[?25l");
    const show_count = std.mem.count(u8, output, "\x1b[?25h");

    // FAIL: Expected 0, got 20! (cursor toggled on EVERY render)
    try expectEqual(@as(usize, 0), hide_count);
}
```

**Root Causes Found** (only discoverable via terminal output inspection):
1. Redundant cursor shape codes (`\x1b[2 q`) sent 20× per second
2. Redundant cursor visibility toggle (`\x1b[?25l`, `\x1b[?25h`) 40× per second

**Key Insight**: Debug Protocol shows state is correct, but PTY testing reveals rendering bugs. Neither tool alone is sufficient - you need BOTH!

### Tool Selection Guide

**Use Debug Protocol When**:
- ✅ Debugging crashes/panics (exact stack traces)
- ✅ Verifying internal state (cursor position, mode, buffer content)
- ✅ Tracing logic errors (wrong calculations, incorrect flow)
- ✅ Inspecting layer composition (what's enabled/dirty)
- ✅ Analyzing logs for state transitions

**Use PTY Testing When**:
- ✅ Validating terminal output (ANSI escape codes)
- ✅ Catching visual artifacts (flickering, incorrect colors)
- ✅ Testing timing-sensitive bugs (rapid input handling)
- ✅ Verifying user experience (what user actually sees)
- ✅ Counting redundant operations (escape code frequency)

**Use BOTH When**:
- ✅ Complex bugs with state + rendering components
- ✅ First reproducing with PTY, then diagnosing with Debug Protocol
- ✅ Verifying complete fix (state correct AND rendering smooth)

### Common Bug Patterns by Tool

**Caught by Debug Protocol**:
- Early return optimization → Skips validation (check opacity >= 1.0 returns)
- Type conversion → Loses data (@intFromFloat with NaN/Infinity)
- Null handling → Assumes non-null when optional (check .? usage)
- State transitions → Mode not changing, cursor wrong position
- Logic errors → Wrong calculations, incorrect conditions

**Caught ONLY by PTY Testing**:
- Redundant escape codes → Terminal codes sent unnecessarily
- Visual flickering → Cursor visibility toggled too often
- Color bleeding → ANSI reset codes missing
- Terminal-specific bugs → Works in one terminal, breaks in another
- Performance issues → Too many escape codes overwhelming terminal

**Requires Both Tools**:
- Input handling bugs → Key processed (Debug) but display wrong (PTY)
- Rendering pipeline bugs → State correct but output corrupted
- Timing bugs → State updates but render lags

### Debugging Workflow Examples

**Mandatory Workflow for Crashes**:
```
1. REPRODUCE with debug protocol (get exact stack trace)
2. READ error output (don't guess - read the panic message)
3. ZONE scope (narrow to exact function/line, not "somewhere in X")
4. IMPLEMENT fix (single targeted fix, not shotgun approach)
5. VERIFY with debug protocol (test passes = bug fixed)
6. ITERATE if needed (but should fix in 1-2 iterations max)
```

**Rendering Bug Investigation Workflow**:
```bash
# Use debug protocol to inspect each pipeline stage
./zig-out/bin/vimcraft --debug-protocol &

# 1. Verify source data (Buffer layer)
echo '{"cmd":"get_state","id":"1"}'  # Check buffer content

# 2. Check layer composition (Compositor)
echo '{"cmd":"get_layers","id":"2"}'  # Are layers enabled/dirty?

# 3. Query debug logs (transformations)
echo '{"cmd":"get_logs","args":{"max_bytes":4096},"id":"3"}'  # Check blend/diff logs

# 4. Identify WHERE data is lost (Buffer→Compositor→Diff→Terminal)
# Bug is in the stage where data exists before but not after
```

**Terminal Output Bug Workflow** (NEW):
```bash
# Step 1: Write PTY test to capture actual output
zig test src/backends/terminal/tests/output_test.zig

# Step 2: Parse terminal output for escape codes
# Look for patterns like:
# - Redundant codes (same code sent multiple times)
# - Missing codes (expected code not present)
# - Wrong order (codes sent in incorrect sequence)

# Step 3: Add state tracking to prevent redundancy
# Example: track last_cursor_shape to avoid re-sending
```

**Add Debug Logs When Investigating** (make data flow visible):
```zig
// Log transformations (CRITICAL for tracing bugs)
editor.logger.debug("TRANSFORM[{s}]: before={} after={}", .{component, before, after});
editor.logger.debug("LAYER[{s}]: enabled={} dirty={} cells={}", .{name, enabled, dirty, count});
editor.logger.debug("BLEND: src={u} dst={u} result={u}", .{src.char, dst.char, result.char});

// NEW: Log terminal escape codes for PTY debugging
editor.logger.debug("ESCAPE: sending {s}", .{escape_code});
editor.logger.debug("CURSOR: shape={s} visibility={}", .{shape, visible});
```

**Success Metrics**: Fix in 1-2 iterations (not 5-10), root cause identified (not guessed), verified with BOTH debug protocol AND PTY tests.

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
5. **Use Debug Protocol**: Verify fixes with `--debug-protocol` for integration testing.

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

**Step 5: Verify with Debug Protocol**
```bash
# Create integration test
cat > /tmp/test_o.txt << 'EOF'
abc
EOF

{
    echo '{"cmd":"load_file","args":{"path":"/tmp/test_o.txt"},"id":"1"}'
    echo '{"cmd":"execute_keys","args":{"keys":"o"},"id":"2"}'
    echo '{"cmd":"execute_keys","args":{"keys":"def"},"id":"3"}'
    echo '{"cmd":"get_cursor","id":"4"}'
    echo '{"cmd":"shutdown","id":"99"}'
} | ./zig-out/bin/vimcraft --debug-protocol

# Verify: cursor at (1,3), file contains "abc\ndef"
```

### Common TDD Mistakes

1. **Writing Tests After Implementation** → Tests validate bugs instead of catching them
2. **Testing Implementation Details** → Tests break on refactoring
3. **Vague Assertions** → Tests pass but don't verify correctness
4. **No Edge Cases** → Bugs slip through common-case tests
5. **Ignoring Test Failures** → "I'll fix the test later" → Technical debt

### TDD + Debug Protocol

**Best Practice**: Combine unit tests (fast) with debug protocol (integration):

```
Unit Test (zig build test)     → Verify logic correctness
Debug Protocol (--debug-protocol) → Verify end-to-end behavior
```

**Workflow**:
1. Write unit test specifying behavior
2. Implement until unit test passes
3. Verify with debug protocol to catch integration issues
4. If debug protocol reveals issues, write MORE unit tests

### Success Criteria

- ✅ Test written BEFORE code
- ✅ Test fails initially (proves it catches the bug)
- ✅ Test specifies correct behavior (not current behavior)
- ✅ Test passes after implementation
- ✅ Debug protocol confirms fix works end-to-end

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
│   │   └── debug/            # Debug protocol backend
│   │       ├── protocol.zig  # JSON-RPC commands
│   │       ├── server.zig    # Debug server
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

#### Migrated APIs (7 total, 11 HostObjects)

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
- `src/backends/debug/{protocol,server,state}.zig` - Debug protocol

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
