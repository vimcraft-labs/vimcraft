# E2E Terminal Capture

**Terminal output validation using vim.e2e.pty API**

## Overview

Vimcraft validates terminal rendering through E2E tests using the `vim.e2e.pty.*` API. This captures actual ANSI escape codes sent to the terminal, enabling validation of rendering optimizations and detection of visual bugs.

### Why PTY Capture in E2E?

**Problem**: Standard E2E tests (`vim.e2e.getState()`) show internal state but not terminal output
- State shows cursor at (3, 0) - correct
- But terminal might be sending redundant escape codes - invisible to state inspection

**Solution**: `vim.e2e.pty.*` API captures raw terminal output
- See exactly what escape codes are sent
- Count cursor visibility toggles (`\x1b[?25l`, `\x1b[?25h`)
- Detect flickering, redundant codes, rendering bugs

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    E2E Test (TypeScript)                         │
│                                                                  │
│   vim.e2e.pty.startCapture();                                   │
│   vim.e2e.keys("jjjjj");        // Rapid cursor movement         │
│   vim.e2e.pty.render();         // Force render + capture        │
│   const codes = vim.e2e.pty.countHideCursor();                  │
│   vim.e2e.pty.stopCapture();                                    │
└──────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Vimcraft Runtime                              │
│                                                                  │
│   Terminal Backend ──> ANSI Output ──> Capture Buffer           │
│                                                                  │
│   Escape codes stored for inspection by vim.e2e.pty.*           │
└─────────────────────────────────────────────────────────────────┘
```

## vim.e2e.pty API

### Capture Control

```typescript
// Start capturing terminal output
vim.e2e.pty.startCapture();

// Stop capturing (clears buffer)
vim.e2e.pty.stopCapture();

// Force render cycle and capture output
vim.e2e.pty.render();

// Get raw captured output
const raw = vim.e2e.pty.getRawOutput();
```

### Escape Code Analysis

```typescript
// Count cursor visibility toggles
const hideCount = vim.e2e.pty.countHideCursor();  // \x1b[?25l
const showCount = vim.e2e.pty.countShowCursor();  // \x1b[?25h

// Count SGR (color/attribute) codes
const sgrCount = vim.e2e.pty.countSgrCodes();

// Count cursor position codes
const posCount = vim.e2e.pty.countCursorPosition();  // \x1b[{row};{col}H

// Get render statistics
const stats = vim.e2e.pty.getRenderStats();
// { framesRendered, cellsUpdated, escapeCodesSent }
```

### Pattern Matching

```typescript
// Count occurrences of specific escape pattern
const count = vim.e2e.pty.countPattern("\x1b[2 q");  // Block cursor

// Check if pattern exists
const hasReset = vim.e2e.pty.containsPattern("\x1b[0m");  // SGR reset
```

## Writing PTY Tests

### Basic Structure

```typescript
// tests/e2e/rendering/e2e.ts

vim.e2e.describe("Rendering Optimizations", function() {
    vim.e2e.test("cursor tracking reduces position codes", function() {
        vim.e2e.pty.startCapture();

        // Send 10 cursor movements
        vim.e2e.keys("llllllllll");
        vim.e2e.pty.render();

        const positionCodes = vim.e2e.pty.countCursorPosition();
        vim.e2e.pty.stopCapture();

        // With cursor tracking, should be much less than 10
        vim.e2e.assert.true(
            positionCodes < 20,
            `Expected <20 position codes, got ${positionCodes}`
        );
    });
});

vim.e2e.runAll();
```

### Testing Synchronized Updates

```typescript
vim.e2e.test("synchronized updates prevent flickering", function() {
    vim.e2e.pty.startCapture();

    // Rapid movements that would cause flickering without sync
    vim.e2e.keys("jjjjjjjjjjjjjjjjjjjj"); // 20 movements

    vim.e2e.pty.render();

    const hideCount = vim.e2e.pty.countHideCursor();
    const showCount = vim.e2e.pty.countShowCursor();

    vim.e2e.pty.stopCapture();

    // With synchronized updates, cursor toggles are batched
    const totalToggles = hideCount + showCount;
    vim.e2e.assert.true(
        totalToggles < 50,
        `Expected <50 cursor toggles, got ${totalToggles} (flickering detected)`
    );
});
```

### Testing Color Attribute Tracking

```typescript
vim.e2e.test("attribute tracking deduplicates SGR codes", function() {
    // Load file with syntax highlighting
    vim.e2e.keys(":e tests/fixtures/sample.ts\n");

    vim.e2e.pty.startCapture();
    vim.e2e.pty.render();

    const stats = vim.e2e.pty.getRenderStats();
    vim.e2e.pty.stopCapture();

    console.log("SGR codes sent:", stats.sgrCodesSent);
    console.log("SGR codes deduped:", stats.sgrCodesDeduped);

    // Deduplication should catch some redundant codes
    vim.e2e.assert.true(
        stats.sgrCodesDeduped > 0,
        "Expected some SGR deduplication"
    );
});
```

## Test Coverage

### What PTY Capture Tests

- Terminal escape code generation
- Rendering optimization effectiveness
- Cursor flickering detection
- Synchronized update verification
- Color/attribute deduplication
- Scroll region usage (future)

### What PTY Capture Does NOT Test

- Internal editor state (use `vim.e2e.getState()`)
- Buffer content (use `vim.e2e.getState().buffer`)
- Mode transitions (use `vim.e2e.getMode()`)
- Layer composition (use `vim.e2e.getLayers()`)

## Running PTY Tests

```bash
# Run all E2E tests including rendering
vimc test tests/e2e/rendering

# Run specific rendering test
vimc test tests/e2e/rendering --filter "synchronized"

# Run with verbose output
VIMCRAFT_DEBUG=1 vimc test tests/e2e/rendering
```

## Best Practices

### 1. Always Use Capture Boundaries

```typescript
vim.e2e.pty.startCapture();
try {
    // ... test code ...
} finally {
    vim.e2e.pty.stopCapture();  // Always clean up
}
```

### 2. Force Render Before Counting

```typescript
vim.e2e.keys("jjj");
vim.e2e.pty.render();  // Ensure output is captured
const count = vim.e2e.pty.countCursorPosition();
```

### 3. Use Thresholds, Not Exact Counts

```typescript
// Good: Threshold-based assertion
vim.e2e.assert.true(toggles < 50, "Too many toggles");

// Bad: Exact count (brittle, depends on implementation)
vim.e2e.assert.equal(toggles, 3, "Expected exactly 3 toggles");
```

### 4. Log Stats for Debugging

```typescript
const stats = vim.e2e.pty.getRenderStats();
console.log("Render stats:", JSON.stringify(stats, null, 2));
// Helpful when test fails to understand what happened
```

## Existing PTY Tests

Location: `tests/e2e/rendering/e2e.ts`

| Test | Purpose |
|------|---------|
| Synchronized Updates | Verify DCS sequences reduce flickering |
| Cursor Position Tracking | Verify position code deduplication |
| Color Attribute Tracking | Verify SGR code optimization |
| Render Statistics | Verify stats collection works |
| Escape Sequence Patterns | Verify specific escape code generation |
| Flickering Detection | Verify no excessive cursor toggles |

## Migration from Old PTY Tests

The old Zig-based PTY test infrastructure (`src/backends/terminal/tests/pty.zig`) has been deprecated. All terminal output validation now uses the `vim.e2e.pty.*` API.

### Old Approach (Deprecated)

```zig
// OLD: Zig PTY spawning
var pty = try spawnVimcraft(allocator);
defer pty.kill();
try pty.write("jjj");
const output = try pty.read(&buf, 1000);
const count = std.mem.count(u8, output, "\x1b[?25l");
```

### New Approach (Current)

```typescript
// NEW: TypeScript E2E with vim.e2e.pty
vim.e2e.pty.startCapture();
vim.e2e.keys("jjj");
vim.e2e.pty.render();
const count = vim.e2e.pty.countHideCursor();
vim.e2e.pty.stopCapture();
```

## Related Documentation

- [testing-architecture.md](testing-architecture.md) - Two-level test design
- [docs/api/vim-e2e.md](../api/vim-e2e.md) - Full vim.e2e API reference
- [CLAUDE.md](../../CLAUDE.md) - Project overview and debugging principles

---

**Status**: Active (November 2025)
**Maintainer**: See CLAUDE.md for development workflows
