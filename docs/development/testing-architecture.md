# Testing Architecture: Two-Level Design

This document describes Vimcraft's testing architecture in detail.

**Last Updated**: November 2025
**Status**: Active Development

---

## Table of Contents

1. [Overview](#overview)
2. [Two-Level Test Structure](#two-level-test-structure)
3. [Level 1: Unit Tests](#level-1-unit-tests)
4. [Level 2: E2E Tests](#level-2-e2e-tests)
5. [PTY + JSON Protocol](#pty--json-protocol)
6. [Test Isolation](#test-isolation)
7. [TypeScript Plugin Flow](#typescript-plugin-flow)
8. [Build Integration](#build-integration)
9. [Migration Guide](#migration-guide)
10. [Architecture Decisions](#architecture-decisions)

---

## Overview

Vimcraft uses a **two-level test architecture** designed for:

1. **Speed**: Unit tests run in ~1ms each
2. **Isolation**: Each E2E test starts fresh (no state leakage)
3. **Coverage**: Full stack testing through real PTY + Hermes
4. **Simplicity**: Only two levels, no complex "contract" or "integration" layers

### Key Principles

- **Unit tests = Pure Zig ONLY** (no JavaScript, no PTY, no file I/O)
- **E2E tests = Full stack** (PTY + Hermes + TypeScript)
- **Fresh process per E2E test** (100% isolation)
- **No mocks in E2E** (use real editor, real state)

---

## Two-Level Test Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                         Test Pyramid                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌───────────────────────────────────────────┐               │
│    │           Level 2: E2E Tests              │  ~100ms each  │
│    │   PTY + Hermes + TypeScript               │  Full stack   │
│    │   tests/e2e/*.ts                          │               │
│    └───────────────────────────────────────────┘               │
│                                                                 │
│    ┌───────────────────────────────────────────────────────┐   │
│    │                Level 1: Unit Tests                    │   │
│    │   Pure Zig - No JavaScript, No PTY                    │   │
│    │   src/**/*_test.zig (colocated)                       │   │
│    │                                                        │   │ ~1ms each
│    │   Buffer operations, movements, registers, modes      │   │
│    └───────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why Two Levels (Not Three)?

During architecture review, Principal Engineers recommended three levels (Unit → Contract → E2E). We simplified to two because:

1. **100ms is acceptable** for E2E tests
2. **Contract tests add complexity** without clear benefit
3. **Two levels are easier to understand** and maintain
4. **Fresh process per test** eliminates state isolation concerns

---

## Level 1: Unit Tests

### Characteristics

| Aspect | Requirement |
|--------|-------------|
| Language | Pure Zig only |
| JavaScript | NOT allowed |
| PTY | NOT allowed |
| File I/O | NOT allowed (use in-memory) |
| Speed | ~1ms per test |
| Location | Colocated with source (`*_test.zig`) |

### What to Test

- Buffer operations (insert, delete, yank, paste)
- Movement calculations (word boundaries, line positions)
- Register storage and retrieval
- Mode transitions
- Syntax highlighting rules
- Configuration parsing

### What NOT to Test

- JavaScript plugin execution (use E2E)
- Terminal rendering (use E2E)
- User-facing workflows (use E2E)
- File loading (use E2E)

### Example

```zig
// src/editor/buffer/buffer_test.zig

const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;

test "insert character at cursor position" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();

    // Initial content
    try buffer.appendSlice("hello");
    buffer.cursor.col = 2;  // Position after "he"

    // Insert 'X'
    try buffer.insertChar('X');

    // Verify
    try std.testing.expectEqualStrings("heXllo", buffer.content.items);
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor.col);
}

test "delete character removes correct char" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("hello");
    buffer.cursor.col = 2;

    try buffer.deleteChar();

    try std.testing.expectEqualStrings("helo", buffer.content.items);
}
```

### Running Unit Tests

```bash
# Run all unit tests
zig build test

# Run specific file
zig test src/editor/buffer/buffer_test.zig

# Run with filter
zig build test -- --test-filter "insert"

# Verbose output
zig build test -- --verbose
```

---

## Level 2: E2E Tests

### Characteristics

| Aspect | Requirement |
|--------|-------------|
| Language | TypeScript (compiled to Hermes bytecode) |
| Runtime | Full Hermes JavaScript engine |
| Terminal | Real PTY (pseudoterminal) |
| Isolation | Fresh process per test |
| Speed | ~100ms per test |
| Location | `tests/e2e/*.ts` |

### What to Test

- Complete Vim commands (`:e`, `jjj`, `diw`)
- JavaScript plugin APIs (`vim.motion`, `vim.opt`, `vim.keymap`)
- Plugin execution (autocommands, user commands)
- Terminal I/O (input parsing, ANSI output)
- Configuration loading

### What NOT to Test

- Individual Zig function behavior (use Unit tests)
- Internal data structures (use Unit tests)

### Example

```typescript
// tests/e2e/motion_test.ts

declare const vim: {
    motion: {
        right: (count?: number) => void;
        down: (count?: number) => void;
    };
    cursor: {
        getPosition: () => { line: number; col: number };
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

function test_motion_right_moves_cursor() {
    const before = vim.cursor.getPosition();

    vim.motion.right();

    const after = vim.cursor.getPosition();
    vim.test.assertEqual(after.col, before.col + 1, 'cursor should move right by 1');

    vim.test.pass('test_motion_right_moves_cursor');
}

function test_motion_down_moves_cursor() {
    const before = vim.cursor.getPosition();

    vim.motion.down();

    const after = vim.cursor.getPosition();
    vim.test.assertEqual(after.line, before.line + 1, 'cursor should move down by 1');

    vim.test.pass('test_motion_down_moves_cursor');
}

// Run tests
test_motion_right_moves_cursor();
test_motion_down_moves_cursor();
```

### Running E2E Tests

```bash
# Run all E2E tests
zig build e2e

# Run specific test file
zig build e2e -- --filter motion

# Run with debug output
VIMCRAFT_DEBUG=1 zig build e2e
```

---

## PTY + JSON Protocol

E2E tests communicate with Vimcraft using a hybrid protocol.

### Architecture

```
┌─────────────────┐         ┌─────────────────────────────────────┐
│   Test Runner   │         │           Vimcraft Process           │
│   (Zig)         │         │                                      │
│                 │         │  ┌──────────────┐  ┌──────────────┐ │
│                 │ writes  │  │   Terminal   │  │    JSON      │ │
│  PTY Master ────┼────────►│  │   Backend    │  │   Handlers   │ │
│     fd          │         │  │              │  │              │ │
│                 │◄────────┼──│  PTY Slave   │  │  Direct      │ │
│                 │  reads  │  │              │  │  Memory      │ │
│                 │         │  └──────────────┘  └──────────────┘ │
│                 │         │         │                 ▲         │
│                 │         │         │    Same Process │         │
│                 │         │         └─────────────────┘         │
│                 │         │       (shared memory access)        │
└─────────────────┘         └─────────────────────────────────────┘
```

### Protocol Flow

```
Test Runner                          Vimcraft
    │                                    │
    │── Raw Vim: ":e /tmp/test.txt" ────>│  (terminal parses command)
    │                                    │
    │<──── JSON: {"ok":true} ────────────│
    │                                    │
    │── Raw Vim: "jjj" ─────────────────>│  (cursor moves down 3)
    │                                    │
    │── JSON: {"cmd":"get_cursor"} ─────>│  (state query)
    │                                    │
    │<── JSON: {"cursor":{"row":3}} ─────│  (state response)
    │                                    │
```

### Input: Raw Vim Commands

Send exactly what a user would type:

| Input | Description |
|-------|-------------|
| `:e file.txt` | Ex command to open file |
| `jjj` | Move down 3 lines |
| `diw` | Delete inner word |
| `iHello<ESC>` | Enter insert mode, type, exit |
| `viwd` | Visual select inner word, delete |

### Output: JSON State Queries

Query editor state with JSON:

```json
// Get full state
{"cmd":"get_state","id":"1"}

// Response
{
    "mode": "NORMAL",
    "cursor": {"row": 3, "col": 0},
    "buffer": {"lineCount": 10, "modified": false},
    "registers": {"\"": "deleted text"}
}

// Get cursor only
{"cmd":"get_cursor","id":"2"}

// Response
{"line": 3, "col": 0}

// Get mode only
{"cmd":"get_mode","id":"3"}

// Response
{"mode": "NORMAL"}
```

### Why This Design?

1. **Raw Vim input**: LLMs already know Vim commands - no new API to learn
2. **JSON output**: Machine-parseable for automated verification
3. **Single process**: PTY slave + JSON handlers share memory (fast, no IPC)
4. **Real terminal behavior**: Tests actual input parsing and ANSI output

---

## Test Isolation

### Why Fresh Process Per Test?

Each E2E test spawns a **new Vimcraft process** because:

1. **Hermes can't unload modules**: Once a JavaScript module is `require()`d, it stays loaded
2. **Global state persists**: `vim.g.*` variables, closures, WeakMaps survive between executions
3. **Plugin side effects**: Autocommands, keymaps, timers leak between tests
4. **100% reproducibility**: Each test starts from identical clean state

### What We Tried (and Rejected)

**Session reuse with reset command**: We considered adding a `{"cmd":"reset"}` command to reuse sessions.

**Rejected because**:
- Cannot guarantee 100% state reset (hidden state in closures)
- Debugging failures becomes harder ("which prior test caused this?")
- 100ms overhead is acceptable (not worth the complexity)

### Isolation Guarantee

```
Test 1: Fresh process → Runs → Process terminates
Test 2: Fresh process → Runs → Process terminates
Test 3: Fresh process → Runs → Process terminates
```

**No state leakage possible between tests.**

---

## TypeScript Plugin Flow

E2E tests use TypeScript for ergonomic test writing:

```
┌────────────────┐     ┌────────────────┐     ┌────────────────┐
│   TypeScript   │     │   JavaScript   │     │    Hermes      │
│   .ts file     │────>│   .js file     │────>│   .hbc file    │
│                │     │                │     │   (bytecode)   │
└────────────────┘     └────────────────┘     └────────────────┘
        │                      │                      │
        │    esbuild           │    hermesc           │
        │    transpile         │    compile           │
        │                      │                      │
        ▼                      ▼                      ▼
   tests/e2e/           (intermediate)          ~/.cache/
   motion_test.ts       motion_test.js          vimcraft/
                                                bytecode/
                                                motion_test.hbc
```

### Compilation Steps

1. **TypeScript → JavaScript**: esbuild transpiles TypeScript to JavaScript
2. **JavaScript → Bytecode**: `hermesc` compiles JavaScript to Hermes bytecode (.hbc)
3. **Bytecode → Execution**: Hermes VM loads and executes bytecode

### Caching

Bytecode files are cached in `~/.cache/vimcraft/bytecode/` to avoid recompilation:

- Cache key: SHA256(source content + compiler version)
- Cache invalidation: Automatic on source change
- Cache location: User cache directory (platform-specific)

### Type Declarations

See [vim.e2e Module](#vime2e-module) section below for type declarations including the `vim.e2e` testing API.

---

## vim.e2e Module

The `vim.e2e` module is a first-class TypeScript API for E2E testing and plugin development. Instead of raw JSON protocol commands, it provides type-safe, async/await based testing utilities.

### Why vim.e2e?

| Feature | Raw JSON Protocol | vim.e2e Module |
|---------|-------------------|----------------|
| Type Safety | None | Full TypeScript types |
| Async Flow | Manual ID tracking | Native Promise/async-await |
| Test Structure | Ad-hoc functions | `describe`/`test` pattern |
| Assertions | Manual comparisons | Rich assertion library |
| Dual Use | Testing only | Testing + Plugin Development |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TypeScript Test File                         │
│                                                                 │
│   vim.e2e.test("...", async () => {                            │
│       await vim.e2e.keys("jjj");                               │
│       const cursor = await vim.e2e.getCursor();                │
│   });                                                           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    vim.e2e Module (JavaScript)                  │
│                                                                 │
│   - Maintains request ID counter                                │
│   - Stores pending callbacks by ID                              │
│   - Serializes commands to JSON                                 │
│   - Calls native sendCommand() host function                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              sendCommand() Host Function (Zig)                  │
│                                                                 │
│   - Receives JSON command from JavaScript                       │
│   - Routes to appropriate handler (get_state, get_cursor, etc) │
│   - Returns JSON response                                       │
│   - For keys(): writes to PTY slave                            │
└─────────────────────────────────────────────────────────────────┘
```

### Core API

```typescript
// Send raw Vim commands (as if user typed them)
await vim.e2e.keys("jjj");              // Move down 3 lines
await vim.e2e.keys(":e file.txt<CR>");  // Open file (CR = Enter)
await vim.e2e.keys("diw");              // Delete inner word
await vim.e2e.keys("iHello<ESC>");      // Insert "Hello", exit insert mode

// Query editor state (returns Promises)
const cursor = await vim.e2e.getCursor();    // { line: 3, col: 0 }
const state = await vim.e2e.getState();      // Full editor snapshot
const mode = await vim.e2e.getMode();        // "NORMAL" | "INSERT" | ...
const layers = await vim.e2e.getLayers();    // Compositor layer state
const logs = await vim.e2e.getLogs({ level: "debug", maxBytes: 4096 });

// Low-level protocol access (if needed)
const response = await vim.e2e.send({ cmd: "get_cursor", id: "custom-id" });
```

### Test Structure

The `vim.e2e` module provides Jest/Mocha-style test organization:

```typescript
// tests/e2e/motion_test.ts

vim.e2e.describe("Motion API", () => {

    vim.e2e.test("right() moves cursor right by 1", async () => {
        const before = await vim.e2e.getCursor();

        vim.motion.right();  // Call actual vim.motion API

        const after = await vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col + 1);
    });

    vim.e2e.test("raw keys 'jjj' moves down 3 lines", async () => {
        const before = await vim.e2e.getCursor();

        await vim.e2e.keys("jjj");  // Send raw Vim keystrokes

        const after = await vim.e2e.getCursor();
        vim.e2e.assert.equal(after.line, before.line + 3);
    });

    vim.e2e.test("delete word removes text", async () => {
        await vim.e2e.keys(":e /tmp/test.txt<CR>");
        await vim.e2e.keys("dw");

        const state = await vim.e2e.getState();
        vim.e2e.assert.bufferNotContains("deleted_word");
    });
});

// Run all tests in this file
vim.e2e.runAll();
```

### Assertions

```typescript
// Basic assertions
vim.e2e.assert.equal(actual, expected, "optional message");
vim.e2e.assert.notEqual(actual, expected, "optional message");
vim.e2e.assert.true(condition, "optional message");
vim.e2e.assert.false(condition, "optional message");

// Editor-specific assertions (convenience wrappers)
vim.e2e.assert.mode("NORMAL");
vim.e2e.assert.cursorAt(3, 0);  // line 3, col 0
vim.e2e.assert.bufferContains("expected text");
vim.e2e.assert.bufferNotContains("unwanted text");
```

### Plugin Development Use Case

**Killer Feature**: Plugin developers can use `vim.e2e` during development for interactive debugging:

```typescript
// my-plugin.ts - Using vim.e2e for plugin development

// Interactive debugging during development
async function debugMyPlugin() {
    // Set up test scenario
    await vim.e2e.keys(":e /tmp/test-file.txt<CR>");

    // Call your plugin function
    myPlugin.doSomething();

    // Inspect state after your plugin ran
    const state = await vim.e2e.getState();
    console.log("State after doSomething:", JSON.stringify(state, null, 2));

    // Check for errors in logs
    const logs = await vim.e2e.getLogs({ level: "error" });
    if (logs.length > 0) {
        console.error("Errors found:", logs);
    }

    // Verify cursor position
    const cursor = await vim.e2e.getCursor();
    console.log("Cursor at:", cursor.line, cursor.col);
}

// Automated tests for your plugin
vim.e2e.describe("My Plugin", () => {
    vim.e2e.test("doSomething modifies buffer correctly", async () => {
        await vim.e2e.keys(":e /tmp/test.txt<CR>");

        myPlugin.doSomething();

        vim.e2e.assert.bufferContains("expected result");
    });

    vim.e2e.test("handles empty buffer gracefully", async () => {
        await vim.e2e.keys(":enew<CR>");  // New empty buffer

        myPlugin.doSomething();

        vim.e2e.assert.mode("NORMAL");  // Should not crash
    });
});
```

### Type Declarations

Full TypeScript declarations for `vim.e2e`:

```typescript
// tests/e2e/types.d.ts

declare namespace vim {
    // E2E Testing Module
    namespace e2e {
        // Raw Vim command execution
        function keys(keys: string): Promise<void>;

        // Low-level JSON protocol
        function send<T>(cmd: Command): Promise<T>;

        // State queries (high-level wrappers)
        function getState(): Promise<EditorState>;
        function getCursor(): Promise<CursorPosition>;
        function getMode(): Promise<Mode>;
        function getLayers(): Promise<LayerState[]>;
        function getLogs(opts?: LogOptions): Promise<string>;
        function getBufferContent(): Promise<string>;

        // Test structure
        function describe(name: string, fn: () => void): void;
        function test(name: string, fn: () => Promise<void>): void;
        function runAll(): void;

        // Assertions
        namespace assert {
            function equal<T>(actual: T, expected: T, msg?: string): void;
            function notEqual<T>(actual: T, expected: T, msg?: string): void;
            function true(condition: boolean, msg?: string): void;
            function false(condition: boolean, msg?: string): void;
            function mode(expected: Mode, msg?: string): void;
            function cursorAt(line: number, col: number, msg?: string): void;
            function bufferContains(text: string, msg?: string): void;
            function bufferNotContains(text: string, msg?: string): void;
        }
    }

    // Other vim APIs (existing)
    namespace motion { /* ... */ }
    namespace cursor { /* ... */ }
    namespace opt { /* ... */ }
    namespace keymap { /* ... */ }
}

// Supporting types
interface Command {
    cmd: string;
    args?: Record<string, unknown>;
    id?: string;
}

interface EditorState {
    mode: Mode;
    cursor: CursorPosition;
    buffer: BufferInfo;
    registers?: Record<string, string>;
}

interface CursorPosition {
    line: number;
    col: number;
}

interface BufferInfo {
    lineCount: number;
    modified: boolean;
    path?: string;
}

interface LayerState {
    name: string;
    enabled: boolean;
    dirty: boolean;
}

interface LogOptions {
    level?: "debug" | "info" | "warn" | "error";
    maxBytes?: number;
}

type Mode = "NORMAL" | "INSERT" | "VISUAL" | "VISUAL_LINE" | "COMMAND";
```

### Implementation Notes

1. **Promise Support**: Hermes natively supports Promises - no polyfill needed
2. **ID Generation**: Auto-generated incrementing IDs (user can override)
3. **Timeout Handling**: Default 5s timeout per command (configurable)
4. **Error Propagation**: Zig errors become JavaScript exceptions

### API Reference

For complete API documentation, see [docs/api/vim-e2e.md](../api/vim-e2e.md).

---

## Build Integration

### Build Targets

```bash
# Unit tests (pure Zig)
zig build test

# E2E tests (PTY + Hermes + TypeScript)
zig build e2e

# All tests
zig build test-all
```

### Build.zig Configuration

```zig
// build.zig

pub fn build(b: *std.Build) void {
    // ... existing build configuration ...

    // Unit tests (pure Zig)
    const test_step = b.step("test", "Run unit tests");
    // Add all *_test.zig files

    // E2E tests
    const e2e_step = b.step("e2e", "Run E2E tests");
    const e2e_runner = b.addExecutable(.{
        .name = "e2e_runner",
        .root_source_file = b.path("src/tools/e2e_runner/main.zig"),
    });
    // Configure E2E runner

    // Combined target
    const test_all_step = b.step("test-all", "Run all tests");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(e2e_step);
}
```

### CI/CD Integration

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.2

      - name: Setup Go (for go-enry)
        uses: actions/setup-go@v5
        with:
          go-version: '1.21'

      - name: Build Dependencies
        run: |
          # Build Hermes, libuv, go-enry
          ./scripts/build-deps.sh

      - name: Run Unit Tests
        run: zig build test

      - name: Run E2E Tests
        run: zig build e2e
```

---

## Migration Guide

### From tests/hermes/ to tests/e2e/

The `tests/hermes/` directory contained TypeScript tests that ran against **mock** vim objects. These must be migrated to `tests/e2e/` to run against the **real** editor.

### Migration Checklist

- [ ] Copy `tests/hermes/*.ts` to `tests/e2e/`
- [ ] Remove mock declarations (real `vim` object provided by runtime)
- [ ] Add real assertions (not just "function exists")
- [ ] Verify tests pass with real editor behavior
- [ ] Delete `tests/hermes/` after migration

### Before (Mock with vim.test)

```typescript
// tests/hermes/motion_test.ts (OLD - uses mocks)

// Mock vim object - NOT real behavior
declare const vim: { ... };

function test_motion_api_exists() {
    // Only checks function exists, not behavior
    vim.test.assert(typeof vim.motion.right === 'function');
    vim.test.pass('test_motion_api_exists');  // Always passes
}

test_motion_api_exists();
```

### After (Real with vim.e2e)

```typescript
// tests/e2e/motion_test.ts (NEW - real editor with vim.e2e)

vim.e2e.describe("Motion API", () => {
    vim.e2e.test("right() moves cursor right by 1", async () => {
        const before = await vim.e2e.getCursor();

        vim.motion.right();  // Real cursor movement

        const after = await vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col + 1);
    });

    vim.e2e.test("raw keys work correctly", async () => {
        await vim.e2e.keys("jjj");  // Send actual keystrokes
        vim.e2e.assert.cursorAt(3, 0);
    });
});

vim.e2e.runAll();
```

### Files to Migrate

| Old Location | New Location | Status |
|--------------|--------------|--------|
| `tests/hermes/motion_test.ts` | `tests/e2e/motion_test.ts` | Pending |
| `tests/hermes/buffer_test.ts` | `tests/e2e/buffer_test.ts` | Pending |
| `tests/hermes/cursor_test.ts` | `tests/e2e/cursor_test.ts` | Pending |
| `tests/hermes/options_test.ts` | `tests/e2e/options_test.ts` | Pending |
| `tests/hermes/keymap_test.ts` | `tests/e2e/keymap_test.ts` | Pending |
| `tests/hermes/timer_test.ts` | `tests/e2e/timer_test.ts` | Pending |
| `tests/hermes/usercommand_test.ts` | `tests/e2e/usercommand_test.ts` | Pending |
| `tests/hermes/autocmd_test.ts` | `tests/e2e/autocmd_test.ts` | Pending |

---

## Architecture Decisions

### ADR-001: Two Levels vs Three Levels

**Decision**: Use two test levels (Unit + E2E) instead of three (Unit + Contract + E2E).

**Context**: Principal Engineers recommended three levels for fine-grained testing.

**Decision Rationale**:
- 100ms E2E overhead is acceptable
- Contract tests add complexity without clear benefit
- Two levels are easier to understand and maintain
- Fresh process isolation eliminates state concerns

**Status**: Accepted

### ADR-002: Fresh Process Per E2E Test

**Decision**: Spawn new Vimcraft process for each E2E test.

**Context**: Considered session reuse with reset command for performance.

**Decision Rationale**:
- Hermes can't unload JavaScript modules
- Global state and closures persist
- 100% reproducibility is more valuable than performance
- Debugging failures is easier with isolated tests

**Status**: Accepted

### ADR-003: Raw Vim Input + JSON Output

**Decision**: Use raw Vim commands for input and JSON for output.

**Context**: Considered full JSON protocol for both directions.

**Decision Rationale**:
- LLMs already know Vim commands (no learning curve)
- JSON output is machine-parseable (automated verification)
- Hybrid approach tests real terminal input parsing
- Simpler test writing (just type Vim commands)

**Status**: Accepted

### ADR-004: Unit Tests = Pure Zig Only

**Decision**: Unit tests must not use JavaScript, PTY, or file I/O.

**Context**: Originally planned Hermes "unit tests" with mock vim objects.

**Decision Rationale**:
- Mock tests don't verify real behavior
- Any JavaScript testing requires full Hermes stack
- Pure Zig tests are fast (~1ms) and isolated
- E2E tests cover JavaScript integration

**Status**: Accepted

### ADR-005: vim.e2e Module for E2E Testing

**Decision**: Provide a first-class `vim.e2e` TypeScript API instead of raw JSON protocol.

**Context**: E2E tests originally used raw JSON commands like `{"cmd":"get_state","id":"1"}`.

**Decision Rationale**:
- **Type Safety**: Full TypeScript types prevent runtime errors
- **Async/Await**: Natural Promise-based flow instead of manual ID tracking
- **Familiar Pattern**: `describe`/`test` structure familiar to JavaScript developers
- **Dual Use**: Same API works for E2E tests AND plugin development debugging
- **Rich Assertions**: Built-in assertions with helpful error messages
- **Plugin Developer UX**: Killer feature - developers can debug plugins interactively

**Status**: Accepted

---

## Related Documentation

- [docs/api/vim-e2e.md](../api/vim-e2e.md) - **vim.e2e API reference** (full documentation)
- [tests/README.md](../../tests/README.md) - Quick reference guide
- [CLAUDE.md](../../CLAUDE.md) - Project overview
- [docs/development/pty-testing.md](pty-testing.md) - PTY test details

---

## Changelog

| Date | Change |
|------|--------|
| November 2025 | Initial architecture design |
| November 2025 | Simplified to two-level structure |
| November 2025 | Added migration guide for tests/hermes/ |
| November 2025 | Added vim.e2e module for E2E testing + plugin development |
