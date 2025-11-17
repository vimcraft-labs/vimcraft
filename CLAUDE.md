# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Quick Navigation

**Critical Workflows**:
- [Test-Driven Development (TDD)](#test-driven-development-tdd) - MANDATORY workflow: write tests first
- [Debug Protocol](#debug-protocol--verification-system) - LLM-optimized JSON testing (see [docs/development/debug-protocol.md](docs/development/debug-protocol.md))
- [Logging Architecture](#logging-architecture) - Use `editor.logger`, not `std.debug.print`
- [Debugging Principles](#debugging-principles) - 7 proven principles for efficient bug fixing
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

## Debug Protocol & Verification System

**Critical**: Vimcraft uses Zig-based debug protocol for LLM-driven development with structured JSON communication.

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

**7 Proven Principles** (from cursorline bug fix):

1. **Simplest Test Case** - Single file, minimal content (not full app)
2. **Trust User Reports** - Don't over-theorize, believe symptom descriptions
3. **Check Data Flow** - Trace through pipeline: Buffer→Compositor→Diff→Terminal
4. **Type Conversions** - Red flag for data loss (early returns, optional handling)
5. **Log Transformations** - Show before→after, not just final state
6. **Targeted Tests** - Verify fix + edge cases + no side effects
7. **Follow Breadcrumbs** - User reports contain critical clues

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

**Common Bug Patterns** (recognize and fix fast):
- Early return optimization → Skips validation (check opacity >= 1.0 returns)
- Type conversion → Loses data (@intFromFloat with NaN/Infinity)
- Null handling → Assumes non-null when optional (check .? usage)
- Dirty tracking → Changes not marked, diff misses them

**Add Debug Logs When Investigating** (make data flow visible):
```zig
// Log transformations (CRITICAL for tracing bugs)
editor.logger.debug("TRANSFORM[{s}]: before={} after={}", .{component, before, after});
editor.logger.debug("LAYER[{s}]: enabled={} dirty={} cells={}", .{name, enabled, dirty, count});
editor.logger.debug("BLEND: src={u} dst={u} result={u}", .{src.char, dst.char, result.char});
```

**Success Metrics**: Fix in 1-2 iterations (not 5-10), root cause identified (not guessed), verified with debug protocol.

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

### Hybrid Build System

**Critical**: Zig linker bug (C++ exception metadata in `__eh_frame`) requires hybrid build:
1. Zig compiles to `.o` object files (`zig build-obj`)
2. `clang++` performs final linking with Hermes libraries

This is the **proper solution**, not a workaround.

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
