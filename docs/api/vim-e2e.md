# vim.e2e API Reference

The `vim.e2e` module provides a first-class TypeScript API for E2E testing and plugin development debugging.

**Last Updated**: November 2025
**Status**: Active Development

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Core API](#core-api)
4. [State Queries](#state-queries)
5. [Test Structure](#test-structure)
6. [Assertions](#assertions)
7. [Types](#types)
8. [Plugin Development](#plugin-development)
9. [Examples](#examples)
10. [Implementation Details](#implementation-details)

---

## Overview

The `vim.e2e` module serves two purposes:

1. **E2E Testing**: Write automated tests for Vimcraft with type-safe, async/await APIs
2. **Plugin Development**: Debug plugins interactively with state inspection

### Key Features

- **Type Safety**: Full TypeScript types for all methods
- **Async/Await**: Native Promise-based flow
- **Structured Tests**: `describe`/`test` pattern (Jest/Mocha style)
- **Rich Assertions**: Built-in assertions with helpful error messages
- **State Inspection**: Query cursor, mode, buffer, layers, logs

---

## Quick Start

### Writing a Test

```typescript
// tests/e2e/my_test.ts

vim.e2e.describe("My Feature", () => {

    vim.e2e.test("basic functionality works", async () => {
        // Send keystrokes
        await vim.e2e.keys(":e /tmp/test.txt<CR>");

        // Query state
        const cursor = await vim.e2e.getCursor();

        // Assert
        vim.e2e.assert.cursorAt(0, 0);
    });
});

vim.e2e.runAll();
```

### Running Tests

```bash
# Run all E2E tests
zig build e2e

# Run specific test file
zig build e2e -- --filter my_test
```

---

## Core API

### `vim.e2e.keys(keys: string): Promise<void>`

Send raw Vim keystrokes to the editor.

**Parameters**:
- `keys`: String of keystrokes to send

**Special Keys**:
- `<CR>` or `<Enter>` - Enter key
- `<ESC>` or `<Escape>` - Escape key
- `<Tab>` - Tab key
- `<BS>` or `<Backspace>` - Backspace
- `<Space>` - Space
- `<C-x>` - Ctrl+x (e.g., `<C-d>` for Ctrl+D)

**Examples**:
```typescript
// Normal mode movements
await vim.e2e.keys("jjj");       // Move down 3 lines
await vim.e2e.keys("10l");       // Move right 10 characters
await vim.e2e.keys("gg");        // Go to start of file
await vim.e2e.keys("G");         // Go to end of file

// Ex commands
await vim.e2e.keys(":e /tmp/file.txt<CR>");  // Open file
await vim.e2e.keys(":w<CR>");                 // Save file
await vim.e2e.keys(":set number<CR>");        // Enable line numbers

// Insert mode
await vim.e2e.keys("iHello, World!<ESC>");   // Insert text

// Visual mode + operators
await vim.e2e.keys("viwd");      // Select inner word and delete
await vim.e2e.keys("Vjjd");      // Select 3 lines and delete

// Complex sequences
await vim.e2e.keys("ciw\"new text\"<ESC>");  // Change inner word
```

### `vim.e2e.send<T>(cmd: Command): Promise<T>`

Send a raw JSON protocol command. For advanced use cases.

**Parameters**:
- `cmd`: Command object with `cmd`, optional `args`, and optional `id`

**Returns**: Promise resolving to the command response

**Example**:
```typescript
// Low-level command
const response = await vim.e2e.send({
    cmd: "get_state",
    id: "custom-id-1"
});

// With arguments
const logs = await vim.e2e.send({
    cmd: "get_logs",
    args: { level: "debug", max_bytes: 4096 },
    id: "logs-1"
});
```

---

## State Queries

High-level wrappers around common state queries.

### `vim.e2e.getState(): Promise<EditorState>`

Get a full snapshot of editor state.

**Returns**: `EditorState` with mode, cursor, buffer info, and registers

**Example**:
```typescript
const state = await vim.e2e.getState();
console.log("Mode:", state.mode);
console.log("Cursor:", state.cursor.line, state.cursor.col);
console.log("Buffer lines:", state.buffer.lineCount);
console.log("Modified:", state.buffer.modified);
```

### `vim.e2e.getCursor(): Promise<CursorPosition>`

Get current cursor position.

**Returns**: `{ line: number, col: number }` (0-indexed)

**Example**:
```typescript
const cursor = await vim.e2e.getCursor();
console.log(`Cursor at line ${cursor.line}, column ${cursor.col}`);
```

### `vim.e2e.getMode(): Promise<Mode>`

Get current editor mode.

**Returns**: One of `"NORMAL"`, `"INSERT"`, `"VISUAL"`, `"VISUAL_LINE"`, `"COMMAND"`

**Example**:
```typescript
const mode = await vim.e2e.getMode();
if (mode === "INSERT") {
    console.log("Currently in insert mode");
}
```

### `vim.e2e.getLayers(): Promise<LayerState[]>`

Get compositor layer state. Useful for debugging rendering issues.

**Returns**: Array of `{ name: string, enabled: boolean, dirty: boolean }`

**Example**:
```typescript
const layers = await vim.e2e.getLayers();
for (const layer of layers) {
    console.log(`${layer.name}: enabled=${layer.enabled}, dirty=${layer.dirty}`);
}
```

### `vim.e2e.getLogs(opts?: LogOptions): Promise<string>`

Get editor logs. Useful for debugging.

**Parameters**:
- `opts.level`: Log level filter (`"debug"`, `"info"`, `"warn"`, `"error"`)
- `opts.maxBytes`: Maximum bytes to return (default: 4096)

**Returns**: String containing log entries

**Example**:
```typescript
// Get all recent logs
const allLogs = await vim.e2e.getLogs();

// Get only errors
const errors = await vim.e2e.getLogs({ level: "error" });

// Get more logs
const debugLogs = await vim.e2e.getLogs({
    level: "debug",
    maxBytes: 16384
});
```

### `vim.e2e.getBufferContent(): Promise<string>`

Get current buffer content as a string.

**Returns**: Full buffer content

**Example**:
```typescript
const content = await vim.e2e.getBufferContent();
console.log("Buffer has", content.split("\n").length, "lines");
```

---

## Test Structure

### `vim.e2e.describe(name: string, fn: () => void): void`

Group related tests together.

**Parameters**:
- `name`: Description of the test group
- `fn`: Function containing `test()` calls

**Example**:
```typescript
vim.e2e.describe("Motion Commands", () => {
    vim.e2e.test("h moves left", async () => { /* ... */ });
    vim.e2e.test("l moves right", async () => { /* ... */ });
    vim.e2e.test("j moves down", async () => { /* ... */ });
    vim.e2e.test("k moves up", async () => { /* ... */ });
});

vim.e2e.describe("Insert Mode", () => {
    vim.e2e.test("i enters insert mode", async () => { /* ... */ });
    vim.e2e.test("typing inserts characters", async () => { /* ... */ });
});
```

### `vim.e2e.test(name: string, fn: () => Promise<void>): void`

Define a single test case.

**Parameters**:
- `name`: Description of what this test verifies
- `fn`: Async function containing test logic

**Example**:
```typescript
vim.e2e.test("delete word removes text", async () => {
    // Setup
    await vim.e2e.keys(":e /tmp/test.txt<CR>");

    // Action
    await vim.e2e.keys("dw");

    // Verify
    const content = await vim.e2e.getBufferContent();
    vim.e2e.assert.bufferNotContains("deleted_word");
});
```

### `vim.e2e.runAll(): void`

Execute all defined tests. Call this at the end of your test file.

**Example**:
```typescript
vim.e2e.describe("Feature A", () => { /* ... */ });
vim.e2e.describe("Feature B", () => { /* ... */ });

// Run all tests
vim.e2e.runAll();
```

---

## Assertions

### Basic Assertions

#### `vim.e2e.assert.equal<T>(actual: T, expected: T, msg?: string): void`

Assert that two values are equal.

```typescript
vim.e2e.assert.equal(cursor.col, 5, "cursor should be at column 5");
vim.e2e.assert.equal(mode, "NORMAL");
```

#### `vim.e2e.assert.notEqual<T>(actual: T, expected: T, msg?: string): void`

Assert that two values are not equal.

```typescript
vim.e2e.assert.notEqual(cursor.line, 0, "cursor should have moved");
```

#### `vim.e2e.assert.true(condition: boolean, msg?: string): void`

Assert that a condition is true.

```typescript
vim.e2e.assert.true(content.length > 0, "buffer should not be empty");
```

#### `vim.e2e.assert.false(condition: boolean, msg?: string): void`

Assert that a condition is false.

```typescript
vim.e2e.assert.false(state.buffer.modified, "buffer should not be modified");
```

### Editor-Specific Assertions

#### `vim.e2e.assert.mode(expected: Mode, msg?: string): void`

Assert current editor mode.

```typescript
vim.e2e.assert.mode("NORMAL");
vim.e2e.assert.mode("INSERT", "should be in insert mode after 'i'");
```

#### `vim.e2e.assert.cursorAt(line: number, col: number, msg?: string): void`

Assert cursor position (0-indexed).

```typescript
vim.e2e.assert.cursorAt(0, 0);  // Start of file
vim.e2e.assert.cursorAt(5, 10, "cursor should be at line 5, col 10");
```

#### `vim.e2e.assert.bufferContains(text: string, msg?: string): void`

Assert buffer contains specific text.

```typescript
vim.e2e.assert.bufferContains("Hello, World!");
vim.e2e.assert.bufferContains("function", "should have function keyword");
```

#### `vim.e2e.assert.bufferNotContains(text: string, msg?: string): void`

Assert buffer does not contain specific text.

```typescript
vim.e2e.assert.bufferNotContains("deleted_text");
```

---

## Types

### Command

```typescript
interface Command {
    cmd: string;
    args?: Record<string, unknown>;
    id?: string;
}
```

### EditorState

```typescript
interface EditorState {
    mode: Mode;
    cursor: CursorPosition;
    buffer: BufferInfo;
    registers?: Record<string, string>;
}
```

### CursorPosition

```typescript
interface CursorPosition {
    line: number;  // 0-indexed
    col: number;   // 0-indexed
}
```

### BufferInfo

```typescript
interface BufferInfo {
    lineCount: number;
    modified: boolean;
    path?: string;
}
```

### LayerState

```typescript
interface LayerState {
    name: string;
    enabled: boolean;
    dirty: boolean;
}
```

### LogOptions

```typescript
interface LogOptions {
    level?: "debug" | "info" | "warn" | "error";
    maxBytes?: number;
}
```

### Mode

```typescript
type Mode = "NORMAL" | "INSERT" | "VISUAL" | "VISUAL_LINE" | "COMMAND";
```

---

## Plugin Development

The `vim.e2e` module is not just for testing - it's also a powerful debugging tool for plugin developers.

### Interactive Debugging

```typescript
// my-plugin.ts

async function debugMyPlugin() {
    // Set up a test scenario
    await vim.e2e.keys(":e /tmp/test-file.txt<CR>");
    await vim.e2e.keys("iTest content<ESC>");

    // Call your plugin function
    myPlugin.processBuffer();

    // Inspect state after your plugin ran
    const state = await vim.e2e.getState();
    console.log("State:", JSON.stringify(state, null, 2));

    // Check cursor position
    const cursor = await vim.e2e.getCursor();
    console.log(`Cursor at: ${cursor.line}:${cursor.col}`);

    // Check for errors
    const logs = await vim.e2e.getLogs({ level: "error" });
    if (logs.length > 0) {
        console.error("Errors found:", logs);
    }

    // Inspect layers for rendering issues
    const layers = await vim.e2e.getLayers();
    console.log("Layers:", layers);
}

// Run debugging session
debugMyPlugin();
```

### Writing Plugin Tests

```typescript
// my-plugin-tests.ts

vim.e2e.describe("My Plugin", () => {
    vim.e2e.test("initializes correctly", async () => {
        myPlugin.initialize();
        vim.e2e.assert.true(myPlugin.isInitialized());
    });

    vim.e2e.test("processes buffer content", async () => {
        await vim.e2e.keys(":e /tmp/test.txt<CR>");

        myPlugin.processBuffer();

        vim.e2e.assert.bufferContains("processed");
    });

    vim.e2e.test("handles empty buffer gracefully", async () => {
        await vim.e2e.keys(":enew<CR>");

        // Should not throw
        myPlugin.processBuffer();

        vim.e2e.assert.mode("NORMAL");
    });

    vim.e2e.test("registers keymap correctly", async () => {
        myPlugin.registerKeymaps();

        await vim.e2e.keys("<leader>mp");  // Plugin keymap

        vim.e2e.assert.mode("NORMAL");
        vim.e2e.assert.bufferContains("plugin executed");
    });
});

vim.e2e.runAll();
```

### Debugging Workflow

```
1. Write plugin code
2. Use vim.e2e to set up test scenario
3. Call plugin functions
4. Inspect state with getCursor(), getState(), getLogs()
5. Fix issues
6. Convert debugging code to automated tests
7. Run tests with `zig build e2e`
```

---

## Examples

### Complete Test File

```typescript
// tests/e2e/motion_test.ts

vim.e2e.describe("Basic Motions", () => {
    vim.e2e.test("h moves cursor left", async () => {
        await vim.e2e.keys(":e /tmp/test.txt<CR>");
        await vim.e2e.keys("llll");  // Move right 4 times

        const before = await vim.e2e.getCursor();
        await vim.e2e.keys("h");
        const after = await vim.e2e.getCursor();

        vim.e2e.assert.equal(after.col, before.col - 1);
    });

    vim.e2e.test("j moves cursor down", async () => {
        const before = await vim.e2e.getCursor();
        await vim.e2e.keys("j");
        const after = await vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 1);
    });

    vim.e2e.test("gg goes to start of file", async () => {
        await vim.e2e.keys("G");   // Go to end first
        await vim.e2e.keys("gg");  // Go to start

        vim.e2e.assert.cursorAt(0, 0);
    });
});

vim.e2e.describe("Insert Mode", () => {
    vim.e2e.test("i enters insert mode", async () => {
        await vim.e2e.keys("i");
        vim.e2e.assert.mode("INSERT");
    });

    vim.e2e.test("ESC returns to normal mode", async () => {
        await vim.e2e.keys("i");
        await vim.e2e.keys("<ESC>");
        vim.e2e.assert.mode("NORMAL");
    });

    vim.e2e.test("typing inserts text", async () => {
        await vim.e2e.keys(":enew<CR>");  // New buffer
        await vim.e2e.keys("iHello<ESC>");

        vim.e2e.assert.bufferContains("Hello");
    });
});

vim.e2e.describe("Delete Operations", () => {
    vim.e2e.test("x deletes character under cursor", async () => {
        await vim.e2e.keys(":enew<CR>");
        await vim.e2e.keys("iABC<ESC>");
        await vim.e2e.keys("0");  // Go to start
        await vim.e2e.keys("x");  // Delete 'A'

        vim.e2e.assert.bufferContains("BC");
        vim.e2e.assert.bufferNotContains("A");
    });

    vim.e2e.test("dd deletes current line", async () => {
        await vim.e2e.keys(":enew<CR>");
        await vim.e2e.keys("iLine 1<CR>Line 2<CR>Line 3<ESC>");
        await vim.e2e.keys("gg");  // Go to first line
        await vim.e2e.keys("dd"); // Delete it

        vim.e2e.assert.bufferNotContains("Line 1");
        vim.e2e.assert.bufferContains("Line 2");
    });
});

vim.e2e.runAll();
```

### Debugging a Rendering Issue

```typescript
// debug-rendering.ts

async function debugRenderingIssue() {
    // Set up scenario that causes the bug
    await vim.e2e.keys(":e /tmp/problematic-file.txt<CR>");

    // Trigger the issue
    await vim.e2e.keys("jjj");

    // Inspect layers
    const layers = await vim.e2e.getLayers();
    console.log("=== Layer State ===");
    for (const layer of layers) {
        console.log(`${layer.name}:`);
        console.log(`  enabled: ${layer.enabled}`);
        console.log(`  dirty: ${layer.dirty}`);
    }

    // Check logs for errors
    const logs = await vim.e2e.getLogs({ level: "debug", maxBytes: 8192 });
    console.log("\n=== Debug Logs ===");
    console.log(logs);

    // Verify state
    const state = await vim.e2e.getState();
    console.log("\n=== Editor State ===");
    console.log(JSON.stringify(state, null, 2));
}

debugRenderingIssue();
```

---

## Implementation Details

### Architecture

```
TypeScript Test → vim.e2e Module (JS) → sendCommand (Zig) → JSON Handler
                                      ↓
                                 PTY for keys()
```

### Promise Support

Hermes natively supports Promises. No polyfill needed.

### ID Generation

Request IDs are auto-generated as incrementing integers. Users can override:

```typescript
await vim.e2e.send({ cmd: "get_state", id: "my-custom-id" });
```

### Timeout Handling

Default timeout is 5 seconds per command. Commands that exceed this throw an error.

### Error Propagation

Zig errors become JavaScript exceptions:

```typescript
try {
    await vim.e2e.keys(":e /nonexistent/path<CR>");
} catch (e) {
    console.error("Failed to open file:", e.message);
}
```

---

## Related Documentation

- [tests/README.md](../../tests/README.md) - Testing quick start
- [docs/development/testing-architecture.md](../development/testing-architecture.md) - Full architecture
