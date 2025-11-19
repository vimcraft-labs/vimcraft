# vim.buffer.getChangedTick() API

## Overview

`vim.buffer.getChangedTick()` returns a monotonically increasing counter that tracks buffer modifications. This is **Neovim-compatible** and equivalent to `nvim_buf_get_changedtick()` and `b:changedtick`.

## API Signature

```typescript
vim.buffer.getChangedTick(): number
```

**Returns**: Current buffer version as a number (u64 internally)

## Purpose

The changedtick counter **increments on EVERY buffer modification**:
- Insert/delete characters
- Paste operations
- Undo/redo
- Load file
- Visual mode operations

Use it to detect when **cached data becomes stale**.

## Usage Pattern

### Safe ArrayBuffer Access

```javascript
// Get ArrayBuffer and capture current tick
const ab = vim.buffer.getContent();
const tick = vim.buffer.getChangedTick();  // e.g., tick = 42
const view = new Uint8Array(ab);

// ... user might edit buffer ...

// Before using ArrayBuffer, check if buffer changed
if (vim.buffer.getChangedTick() === tick) {
    // SAFE: Buffer hasn't changed, ArrayBuffer still valid
    const text = new TextDecoder().decode(view);
    console.log(text);
} else {
    // UNSAFE: Buffer changed, must get fresh ArrayBuffer
    console.warn("Buffer changed! ArrayBuffer is stale.");
    const freshAb = vim.buffer.getContent();
    const freshView = new Uint8Array(freshAb);
    const text = new TextDecoder().decode(freshView);
}
```

### LSP Completion Validation

```javascript
// Request completions
const tick = vim.buffer.getChangedTick();
const completions = await requestCompletions();

// Validate completions are still relevant
if (vim.buffer.getChangedTick() !== tick) {
    console.log("Buffer changed during completion, ignoring results");
    return;
}

// Safe to apply completions
applyCompletions(completions);
```

### Cache Invalidation

```javascript
let cachedParse = null;
let cachedTick = 0;

function getParsedBuffer() {
    const currentTick = vim.buffer.getChangedTick();

    if (cachedParse && cachedTick === currentTick) {
        // Cache hit: buffer hasn't changed
        return cachedParse;
    }

    // Cache miss: buffer changed, re-parse
    const ab = vim.buffer.getContent();
    cachedParse = expensiveParse(ab);
    cachedTick = currentTick;

    return cachedParse;
}
```

## Real-World Use Cases

### 1. Tree-sitter Incremental Parsing
```javascript
const tick = vim.buffer.getChangedTick();
const tree = parser.parse(bufferContent);

if (vim.buffer.getChangedTick() !== tick) {
    // Buffer changed during parse, re-parse
    tree = parser.parse(vim.buffer.getContent());
}
```

### 2. Diagnostics Caching
```javascript
async function updateDiagnostics() {
    const tick = vim.buffer.getChangedTick();
    const diagnostics = await lintBuffer();

    // Check buffer wasn't modified during async lint
    if (vim.buffer.getChangedTick() === tick) {
        applyDiagnostics(diagnostics);
    }
}
```

### 3. Debounced Operations
```javascript
let lastTick = 0;

function onBufferChange() {
    const currentTick = vim.buffer.getChangedTick();

    if (currentTick !== lastTick) {
        // Buffer actually changed
        scheduleReparse();
        lastTick = currentTick;
    }
}
```

## Implementation Details

### Internal Representation
- Stored as `version: u64` in Buffer struct (buffer.zig:73)
- Incremented by `incrementVersion()` helper function
- Wrapping add (`+%=`) - overflow is acceptable (2^64 operations needed)

### Increment Locations
The counter increments **before** every buffer modification:
- **buffer.zig**: insertChar, deleteChar, deleteCharBefore, undo, redo, deleteLine, deleteWord, loadFile
- **edit.zig**: deleteRange (all delete operations)
- **paste.zig**: All 8 paste functions (char-wise, line-wise, block-wise)
- **visual_ops.zig**: All 3 visual delete functions

Total: **20+ increment sites** covering ALL buffer modifications.

## Neovim Compatibility

### API Equivalence
| Vimcraft | Neovim | Purpose |
|----------|--------|---------|
| `vim.buffer.getChangedTick()` | `nvim_buf_get_changedtick(bufnr)` | Get changedtick counter |
| N/A | `b:changedtick` | VimScript variable access |
| Passed to callbacks | Passed to `on_lines`, `on_bytes` | Event callbacks |

### Usage Comparison

**Neovim Lua**:
```lua
local tick = vim.api.nvim_buf_get_changedtick(0)
-- or
local tick = vim.b.changedtick
```

**Vimcraft JavaScript**:
```javascript
const tick = vim.buffer.getChangedTick();
```

### Callback Integration (Future)
When Vimcraft implements buffer update callbacks (Phase 4), changedtick will be passed as a parameter:

```javascript
vim.buffer.attach({
    on_lines: function(event, bufnr, changedtick, firstLine, lastLine, ...) {
        // changedtick parameter automatically provided
        console.log("Buffer tick:", changedtick);
    }
});
```

## Performance

- **O(1) operation** - simple u64 field read
- **No allocation** - returns number directly
- **Zero overhead** - just a counter increment on modifications

## Safety Considerations

### ✅ What This Enables
- Detection of stale ArrayBuffers
- Cache invalidation strategies
- Synchronization between async operations

### ⚠️ What This Doesn't Prevent
- Use-after-free if you **ignore** changedtick checks
- Accessing invalid memory if you don't validate before use
- Race conditions in multi-threaded scenarios (future concern)

### Best Practices
1. **Always capture tick** when getting ArrayBuffer
2. **Always validate tick** before using cached data
3. **Re-fetch on mismatch** - don't try to "fix" stale data
4. **Document assumptions** - make it clear when data must be fresh

## Testing

### Manual Test
```javascript
// Load buffer
vim.executeKeys(":e /tmp/test.txt\n");

// Get initial tick
const tick1 = vim.buffer.getChangedTick();
console.log("Initial tick:", tick1);

// Modify buffer
vim.executeKeys("iHello\x1b");  // Insert "Hello"

// Check tick incremented
const tick2 = vim.buffer.getChangedTick();
console.log("After insert:", tick2);
console.assert(tick2 > tick1, "Tick should increment!");

// Multiple edits
vim.executeKeys("x");  // Delete char
const tick3 = vim.buffer.getChangedTick();
console.assert(tick3 > tick2, "Tick increments on delete!");
```

## References

- **Neovim API**: https://neovim.io/doc/user/api.html#nvim_buf_get_changedtick()
- **Neovim Source**: `src/nvim/api/buffer.c:838` (nvim_buf_get_changedtick)
- **Vimcraft Source**: `src/system/jsi/buffer_api.zig:179` (getBufferChangedTick)
- **Buffer Version**: `src/editor/buffer/buffer.zig:73` (version field)

## Status

✅ **Implemented** (January 2025)
- Function added: `getBufferChangedTick()`
- Exposed via HostObject: `vim.buffer.getChangedTick()`
- Neovim-compatible naming and behavior
- Comprehensive documentation

**Next Steps**:
1. Add to buffer update callbacks (Phase 4)
2. Implement Proxy-based automatic validation (optional)
3. Add performance profiling for version tracking overhead
