# Editor Core

Domain-specific guidance for editor core components (buffers, registers, windows, text operations).

## Overview

The editor core manages all text editing logic, register system, window management, and movement primitives.

## ⚠️ Sacred Files

| File | Why Sacred | Modification Risk |
|------|------------|-------------------|
| `buffer.zig:234-267` | Transaction system core | Breaks undo/redo completely |
| `register.zig:45-89` | Memory management | Leaks or double-frees |

## Key Files

| Component | File:Line | Purpose |
|-----------|-----------|---------|
| **Editor** | `editor.zig:127` | Main coordinator, command dispatch |
| **Buffer** | `buffer/buffer.zig:234` | ArrayList storage, transactions, undo |
| **Delete** | `buffer/edit.zig:45` | Delete operations (x, dd, dw) |
| **Yank** | `buffer/yank.zig:89` | Yank operations (y{motion}, yy) |
| **Paste** | `buffer/paste.zig:123` | Paste ops (p, P, bracketed) |
| **Visual** | `buffer/visual_ops.zig:89` | Visual mode operators |
| **Rope** | `buffer/rope.zig:156` | Future O(log n) structure |
| **Registers** | `register/register.zig:45` | 39 registers management |
| **Windows** | `window.zig:67` | Window management |
| **Layout** | `window_layout.zig:234` | Binary tree split logic |
| **Options** | `config/option_defs.zig:567` | 80+ Vim option definitions |
| **Highlights** | `config/highlights.zig:123` | Syntax highlight groups |
| **Movement** | `movement/movement.zig:127` | Vim motion primitives |
| **Tree-sitter** | `treesitter/loader.zig:119` | Grammar loading + enry |

## Decision Tree

```
Adding text operation?
├── Single char → buffer/edit.zig (deleteChar)
├── Line operation → buffer/edit.zig (deleteLine)
├── Motion-based → buffer/edit.zig (deleteMotion)
├── Visual mode → buffer/visual_ops.zig
└── Yank/paste → buffer/{yank,paste}.zig

Modifying buffer?
├── Need undo → Use transactions
├── Cursor invalid → Call validateCursor()
├── Register update → Use register.setRegister()
└── Multi-step → Group with start/endTransaction

Adding window feature?
├── Split logic → window_layout.zig
├── Focus handling → window.zig
├── Rendering → backends/terminal/display/window_renderer.zig
└── Buffer association → window.zig (buffer_id field)

Adding Vim option?
├── Define option → config/option_defs.zig
├── Storage → Add to editor.options
├── JS exposure → system/jsi/config_api.zig
└── Persistence → Implement in Phase 5
```

## Common Tasks

| Task | Pattern | Location |
|------|---------|----------|
| **Add text op** | Write E2E test → Implement → Register | `buffer/*.zig` |
| **Buffer mod** | Transaction wrap → Validate cursor | `buffer.zig:234` |
| **Register access** | `getRegister()` → `setRegister()` | `register.zig:45` |
| **Window split** | `splitWindow()` → `focusWindow()` | `window_layout.zig:234` |
| **Add motion** | Implement → Test boundaries | `movement.zig:127` |

## Code Patterns

### Transaction Pattern (MANDATORY for multi-step)
```zig
// buffer.zig:234
try buffer.startTransaction();
errdefer buffer.abortTransaction();
// ... multiple operations grouped for undo ...
buffer.endTransaction();
```

### Cursor Validation (MANDATORY after buffer change)
```zig
// After any buffer modification:
try buffer.deleteChar();
buffer.validateCursor();  // Ensures valid position
```

### Register Management
```zig
// register.zig:45 - Auto-manages memory
const content = try registers.getRegister('"');  // Get unnamed
try registers.setRegister('"', "yanked text");   // Set unnamed
```

### Window Management
```zig
// window_layout.zig:234
const new_window = try layout.splitWindow(current, .horizontal);
layout.focusWindow(new_window);
try layout.closeWindow(window_id);
```

## Troubleshooting

| Problem | Likely Cause | Fix | Reference |
|---------|--------------|-----|-----------|
| Undo broken | No transaction | Wrap in start/endTransaction | `buffer.zig:234` |
| Cursor invalid | No validation | Call validateCursor() | `buffer.zig:567` |
| Memory leak | Missing defer | Add defer cleanup | `register.zig:89` |
| Register empty | Wrong register | Check register char | `register.zig:45` |
| Window focus lost | Layout not updated | Call updateFocus() | `window_layout.zig:345` |

## Performance Characteristics

| Operation | ArrayList (Current) | Rope (Future) | Crossover Point |
|-----------|-------------------|---------------|-----------------|
| Insert/Delete | O(n) | O(log n) | ~10KB file |
| Concat | O(n) | O(1) | Any size |
| Index | O(1) | O(log n) | Direct access |
| Memory | Contiguous | Fragmented | Cache locality |

## Testing Guidelines

### Unit Tests
```zig
// buffer_test.zig - Pure logic tests
test "buffer insert" {
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.insertAt(0, "hello");
    try std.testing.expectEqualStrings("hello", buffer.content.items);
}
```

### E2E Tests
```typescript
// tests/e2e/editing/e2e.ts - User workflows
vim.e2e.test("delete word", () => {
    vim.e2e.keys("iHello world<Esc>0");
    vim.e2e.keys("dw");
    vim.e2e.assert.bufferEquals("world");
});
```

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Forgetting transactions | Undo groups wrong | Always use for multi-step |
| Invalid cursor | Crash or wrong position | validateCursor() after changes |
| Register lifetime | Use-after-free | Registers own their content |
| Window dangling ref | Crash on focus | Check window exists in layout |

## Memory Management

| Component | Ownership | Cleanup |
|-----------|-----------|---------|
| Buffer content | Buffer owns | `buffer.deinit()` |
| Register content | Register owns | Automatic on set |
| Window | Layout owns | `closeWindow()` |
| Undo nodes | Buffer owns | Circular buffer pruning |

## Cross-References

**Parent**: [Main CLAUDE.md](../../CLAUDE.md)
**Related**: [Terminal Backend](../../src/backends/terminal/CLAUDE.md) · [JSI System](../../src/system/jsi/CLAUDE.md)
**Docs**: [Buffer Design](../../docs/architecture/buffer-design.md) · [Window Splits](../../docs/design/window-splits.md)