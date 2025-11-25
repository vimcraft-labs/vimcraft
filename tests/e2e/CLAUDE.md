# E2E Testing

Domain-specific guidance for end-to-end testing with Hermes and TypeScript.

## Overview

Full-stack testing with fresh Vimcraft process per test for 100% isolation. Tests run TypeScript→JavaScript→Hermes bytecode.

## Key Files

| Component | File:Line | Purpose |
|-----------|-----------|---------|
| **Test Runner** | `test.zig:234` | Process spawning, PTY management |
| **vim.e2e API** | `src/system/jsi/e2e_api.zig:345` | Testing framework |
| **Type Defs** | `vim.d.ts:567` | TypeScript declarations |
| **Examples** | `*/e2e.ts` | Test case files |
| **Config** | `*/config.ts` | Optional plugin setup |

## Decision Tree

```
Writing test for?
├── Cursor movement → tests/e2e/motion/
├── Text editing → tests/e2e/editing/
├── Visual mode → tests/e2e/visual/
├── Terminal output → tests/e2e/rendering/ (use vim.e2e.pty.*)
├── JS API → tests/e2e/api/*/
└── New feature → Create new sandbox

What to test?
├── State correctness → vim.e2e.getState()
├── Cursor position → vim.e2e.assert.cursorAt()
├── Buffer content → vim.e2e.assert.bufferEquals()
├── Terminal codes → vim.e2e.pty.count*()
└── Debug info → vim.e2e.getLogs()

Test failing?
├── Add console.log → Check output
├── Get state → vim.e2e.getState()
├── Check logs → vim.e2e.getLogs()
├── Capture PTY → vim.e2e.pty.getCaptured()
└── Simplify test → Isolate issue
```

## Architecture Flow

```
TypeScript (e2e.ts)
    ↓ esbuild
JavaScript
    ↓ hermesc
Bytecode (.hbc)
    ↓ Load
Fresh Vimcraft Process
    ↓ Execute
Test Results
    ↓ Exit code
Pass/Fail
```

## Test Structure

### Directory Layout
```
tests/e2e/
├── sandbox-name/
│   ├── e2e.ts        # Test cases (REQUIRED)
│   └── config.ts     # Plugin code (optional)
```

### Test File Pattern
```typescript
// e2e.ts
vim.e2e.describe("Feature", function() {
    vim.e2e.test("behavior", function() {
        // Setup
        vim.e2e.keys(":e /tmp/test.txt<CR>");

        // Action
        vim.e2e.keys("dd");

        // Assert
        vim.e2e.assert.cursorAt(0, 0);
    });
});

vim.e2e.runAll();  // MANDATORY
```

## vim.e2e API Reference

### Test Structure

| Method | Purpose | Example |
|--------|---------|---------|
| `describe(name, fn)` | Test suite | `vim.e2e.describe("Motion", () => {})` |
| `test(name, fn)` | Test case | `vim.e2e.test("hjkl", () => {})` |
| `runAll()` | Execute tests | `vim.e2e.runAll()` |

### Input Methods

| Method | Purpose | Example |
|--------|---------|---------|
| `keys(seq)` | Send keys | `vim.e2e.keys("dd")` |
| `feedkeys(keys)` | Alt input | `vim.e2e.feedkeys("jjj")` |

### State Inspection

| Method | Returns | Use Case |
|--------|---------|----------|
| `getCursor()` | `{line, col}` | Position check |
| `getMode()` | `"NORMAL"/"INSERT"` | Mode verify |
| `getState()` | Full state object | Debug |
| `getLayers()` | Layer info | Compositor |
| `getLogs(opts)` | Log entries | Debug logs |

### PTY Terminal Capture

| Method | Purpose | Example |
|--------|---------|---------|
| `pty.startCapture()` | Begin capture | Before operations |
| `pty.stopCapture()` | End capture | After operations |
| `pty.clear()` | Clear terminal | Reset state |
| `pty.render()` | Force render | Trigger output |
| `pty.countHideCursor()` | Count `\x1b[?25l` | Flicker detection |
| `pty.countShowCursor()` | Count `\x1b[?25h` | Flicker detection |
| `pty.countCursorPositionCodes()` | Count moves | Optimization check |
| `pty.countSGRCodes()` | Count colors | Color optimization |
| `pty.countPattern(regex)` | Custom count | Any pattern |

### Assertions

| Method | Purpose | Example |
|--------|---------|---------|
| `assert.equal(a, b)` | Equality | `assert.equal(mode, "NORMAL")` |
| `assert.true(cond)` | Truth | `assert.true(count < 10)` |
| `assert.cursorAt(l, c)` | Position | `assert.cursorAt(0, 0)` |
| `assert.mode(m)` | Mode | `assert.mode("INSERT")` |
| `assert.bufferContains(t)` | Contains | `assert.bufferContains("hello")` |
| `assert.bufferEquals(t)` | Exact | `assert.bufferEquals("hello\n")` |

## Common Patterns

### Testing Motion
```typescript
vim.e2e.test("word motion", () => {
    vim.e2e.keys("iHello world<Esc>0");
    vim.e2e.keys("w");
    vim.e2e.assert.cursorAt(0, 6);
});
```

### Testing Editing
```typescript
vim.e2e.test("delete line", () => {
    vim.e2e.keys("iLine1<CR>Line2<Esc>gg");
    vim.e2e.keys("dd");
    vim.e2e.assert.bufferEquals("Line2\n");
});
```

### Testing Terminal Output
```typescript
vim.e2e.test("no flicker", () => {
    vim.e2e.pty.startCapture();
    vim.e2e.keys("jjjjj");
    vim.e2e.pty.render();

    const hides = vim.e2e.pty.countHideCursor();
    vim.e2e.assert.true(hides < 10);

    vim.e2e.pty.stopCapture();
});
```

### Testing Plugin
```typescript
// config.ts
vim.keymap.set('n', 'K', () => {
    vim.motion.up();
    vim.motion.up();
});

// e2e.ts
vim.e2e.test("custom map", () => {
    vim.e2e.keys("5j");
    vim.e2e.keys("K");
    vim.e2e.assert.cursorAt(3, 0);
});
```

## Running Tests

| Command | Purpose | Example |
|---------|---------|---------|
| Single sandbox | Test one feature | `vimc test tests/e2e/motion` |
| All tests | Full suite | `for d in tests/e2e/*/; do vimc test "$d"; done` |
| Debug mode | Verbose output | `vimc test tests/e2e/motion --debug` |

> **Note**: Do NOT prefix with `DYLD_LIBRARY_PATH=...`. The binary handles library paths internally. Just use `vimc test <path>` directly.

## Troubleshooting

| Problem | Likely Cause | Fix | Reference |
|---------|--------------|-----|-----------|
| Test hangs | Process not killed | Check defer pty.kill() | `test.zig:234` |
| No output | Missing runAll() | Add vim.e2e.runAll() | End of e2e.ts |
| State wrong | Timing issue | Operations are sync | No await needed |
| PTY empty | No render() call | Call pty.render() | After operations |

## Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Process spawn | ~100ms | Fresh isolation |
| TypeScript transpile | ~50ms | esbuild |
| Bytecode compile | ~20ms | Cached after first |
| PTY capture | ~10ms | Per render |

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| State pollution | Works alone, fails in suite | Each test gets fresh process |
| Missing runAll() | No tests execute | Add at end of file |
| Wrong assertions | False positives | Use specific asserts |
| PTY not captured | No terminal data | Start capture before ops |

## Test Categories

| Category | Location | Purpose |
|----------|----------|---------|
| **motion** | `tests/e2e/motion/` | Cursor movements |
| **editing** | `tests/e2e/editing/` | Text modifications |
| **visual** | `tests/e2e/visual/` | Visual mode |
| **rendering** | `tests/e2e/rendering/` | Terminal output |
| **api/*** | `tests/e2e/api/*/` | JavaScript APIs |
| **options** | `tests/e2e/options/` | Vim options |
| **autocmd** | `tests/e2e/autocmd/` | Autocommands |

## Writing New Tests

### 1. Create Sandbox
```bash
mkdir tests/e2e/my-feature
```

### 2. Write Test
```typescript
// tests/e2e/my-feature/e2e.ts
vim.e2e.describe("My Feature", () => {
    vim.e2e.test("does X", () => {
        vim.e2e.keys("...");
        vim.e2e.assert.cursorAt(0, 0);
    });
});
vim.e2e.runAll();
```

### 3. Optional Config
```typescript
// tests/e2e/my-feature/config.ts
// Plugin setup code
```

### 4. Run
```bash
vimc test tests/e2e/my-feature
```

## Debug Workflow

```typescript
// Add debug output
const state = vim.e2e.getState();
console.log("State:", JSON.stringify(state));

const logs = vim.e2e.getLogs({level: "debug", maxBytes: 4096});
console.log("Logs:", logs);

// Check terminal
vim.e2e.pty.startCapture();
// ... operations ...
const output = vim.e2e.pty.getCaptured();
console.log("Terminal:", output);
```

## Future Work

| Feature | Phase | Benefit |
|---------|-------|---------|
| Parallel execution | 5 | 10x faster suite |
| Coverage reporting | 5 | Quality metrics |
| Visual regression | 6 | Screenshot diffs |
| Performance bench | 6 | Speed tracking |

## Cross-References

**Parent**: [Main CLAUDE.md](../../CLAUDE.md)
**Related**: [JSI System](../../src/system/jsi/CLAUDE.md) · [Editor Core](../../src/editor/CLAUDE.md)
**Docs**: [Testing Architecture](../../docs/development/testing-architecture.md) · [E2E Terminal Capture](../../docs/development/e2e-terminal-capture.md)