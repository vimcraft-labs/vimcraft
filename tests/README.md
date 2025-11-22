# Vimcraft Testing Guide

Vimcraft uses a simple **two-level testing architecture**:

| Level | Command | Speed | What It Tests |
|-------|---------|-------|---------------|
| **Unit** | `zig build test` | ~1ms/test | Pure Zig functions |
| **E2E** | `vimc test <sandbox>` | ~100ms/test | Full stack (TypeScript + Hermes + Terminal) |

## Quick Start

```bash
# Run all unit tests (pure Zig)
zig build test

# Run E2E tests (full stack)
./zig-out/bin/vimc test tests/e2e/basic

# Run all E2E test suites
for dir in tests/e2e/*/; do ./zig-out/bin/vimc test "$dir"; done
```

---

## Level 1: Unit Tests (`zig build test`)

**What**: Pure Zig function testing - no JavaScript, no terminal, no I/O.

**Location**: Colocated with source files (`src/**/*_test.zig`)

**Characteristics**:
- Fast (~1ms per test)
- In-process (no external dependencies)
- Tests individual functions in isolation
- Uses `std.testing` assertions

**Example**:
```zig
// src/editor/buffer/buffer_test.zig
test "insert character at cursor" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.insertChar('a');
    try std.testing.expectEqualStrings("a", buffer.content.items);
}
```

**Run specific test**:
```bash
zig test src/editor/buffer/buffer_test.zig --test-filter "insert"
```

---

## Level 2: E2E Tests (`vimc test`)

**What**: Full-stack testing with real Hermes runtime, TypeScript plugins, and terminal I/O.

**Location**: `tests/e2e/<category>/e2e.ts`

**Characteristics**:
- Slower (~100ms per test) due to process spawn
- Fresh process per test suite (100% isolation)
- Tests real user behavior
- JSON output for LLM consumption

### Directory Structure

```
tests/e2e/
├── basic/
│   └── e2e.ts          # Basic navigation and mode tests
├── motion/
│   └── e2e.ts          # vim.motion API tests
├── buffer/
│   └── e2e.ts          # Buffer operation tests
├── cursor/
│   └── e2e.ts          # Cursor API tests
├── options/
│   └── e2e.ts          # vim.opt tests
├── keymap/
│   └── e2e.ts          # vim.keymap tests
└── rendering/
    └── e2e.ts          # Terminal rendering tests
```

### Writing E2E Tests

```typescript
// tests/e2e/motion/e2e.ts
vim.e2e.describe("Motion API", function() {
    vim.e2e.test("right() moves cursor right by 1", function() {
        const before = vim.e2e.getCursor();
        vim.motion.right();
        const after = vim.e2e.getCursor();
        vim.e2e.assert.equal(after.col, before.col + 1);
    });

    vim.e2e.test("raw keys 'jjj' moves down 3 lines", function() {
        vim.e2e.keys("jjj");
        const cursor = vim.e2e.getCursor();
        vim.e2e.assert.equal(cursor.line, 3);
    });
});

vim.e2e.runAll();
```

### E2E API Reference

**Test Structure**:
```typescript
vim.e2e.describe("Suite Name", function() { ... });
vim.e2e.test("test name", function() { ... });
vim.e2e.runAll();
```

**Input**:
```typescript
vim.e2e.keys("jjj");              // Raw Vim keys
vim.e2e.keys(":e file.txt\r");    // Ex command
vim.e2e.keys("i");                // Enter insert mode
vim.e2e.keys("\x1b");             // ESC key
```

**State Queries**:
```typescript
vim.e2e.getCursor();              // { line, col }
vim.e2e.getMode();                // "NORMAL" | "INSERT" | "VISUAL"
vim.e2e.getState();               // Full editor state
vim.e2e.checkpoint("label");      // Capture intermediate state
```

**Assertions**:
```typescript
vim.e2e.assert.equal(a, b, "message");
vim.e2e.assert.mode("NORMAL");
vim.e2e.assert.cursorAt(line, col);
```

### JSON Output

`vimc test` outputs structured JSON for LLM consumption:

```json
{
  "total": 3,
  "passed": 2,
  "failed": 1,
  "duration_ms": 150,
  "tests": [
    {
      "suite": "Motion API",
      "name": "right() moves cursor",
      "passed": true,
      "duration_ms": 48,
      "logs": ["cursor moved to col 1"],
      "state_before": {"mode": "NORMAL", "cursor": {"line": 0, "col": 0}},
      "state_after": {"mode": "NORMAL", "cursor": {"line": 0, "col": 1}},
      "checkpoints": []
    }
  ]
}
```

---

## When to Use Each Level

| Scenario | Use Unit Tests | Use E2E Tests |
|----------|----------------|---------------|
| Testing a pure function | ✅ | |
| Testing buffer operations | ✅ | |
| Testing Vim command behavior | | ✅ |
| Testing JavaScript plugin APIs | | ✅ |
| Testing terminal rendering | | ✅ |
| Regression test for user bug | | ✅ |
| Performance-sensitive code | ✅ | |

---

## CI Integration

```yaml
# .github/workflows/test.yml
jobs:
  test:
    steps:
      - name: Unit Tests
        run: zig build test

      - name: E2E Tests
        run: |
          zig build
          for dir in tests/e2e/*/; do
            ./zig-out/bin/vimc test "$dir"
          done
```

---

## Debugging Test Failures

### Unit Test Failures

```bash
# Run with verbose output
zig build test -- --verbose

# Run specific test
zig test src/editor/buffer/buffer_test.zig --test-filter "insert"
```

### E2E Test Failures

The JSON output includes:
- `state_before` / `state_after` - See exact state transitions
- `checkpoints` - Intermediate states during test
- `logs` - console.log output from test
- `error_message` - Assertion failure details

```bash
# Run single E2E test for debugging
./zig-out/bin/vimc test tests/e2e/motion 2>&1 | jq .
```

---

## Related Documentation

- [docs/api/vim-e2e.md](../docs/api/vim-e2e.md) - Full vim.e2e API reference
- [CLAUDE.md](../CLAUDE.md) - TDD workflow and testing principles
