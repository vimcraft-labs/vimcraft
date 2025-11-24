# Terminal Backend

Domain-specific guidance for terminal rendering and input handling.

## Overview

Handles all terminal I/O, rendering optimization, and display management with ANSI escape codes.

## ⚠️ Sacred Files

| File | Why Sacred | Modification Risk |
|------|------------|-------------------|
| `display.zig:426-494` | Synchronized update core | Breaks all terminal rendering |
| `compositor.zig:341-416` | Fast-path blending critical | 2x performance regression |

## Key Files

| Component | File:Line | Purpose |
|-----------|-----------|---------|
| **Backend** | `backend.zig:89` | Terminal I/O, raw mode, signals |
| **Input** | `input_handler.zig:234` | Key parsing, bracketed paste |
| **Display** | `display/display.zig:426` | Render pipeline coordinator |
| **Compositor** | `display/compositor.zig:341` | Layer blending, fast-path |
| **Output** | `display/output_renderer.zig:46` | ANSI generation, sorting |
| **Terminal** | `display/terminal_control.zig:139` | Low-level escape codes |
| **Grid** | `display/screen_grid.zig:67` | 2D cell grid, diff algo |
| **Window** | `display/window_renderer.zig:67` | Window content rendering |
| **Separator** | `display/separator_renderer.zig:45` | Split separators |
| **Visual** | `visual/visual_renderer.zig:123` | Visual selection highlight |

## Decision Tree

```
Fixing rendering bug?
├── Cursor flicker → display.zig:478 (position tracking)
├── Tearing → display.zig:426 (synchronized updates)
├── Color wrong → output_renderer.zig:84 (attribute tracking)
├── Slow render → compositor.zig:341 (check fast-path)
└── Escape codes → terminal_control.zig:139 (low-level)

Optimizing performance?
├── Too many renders → main.zig:690 (event batching)
├── Redundant codes → output_renderer.zig:46 (deduplication)
├── Slow blending → compositor.zig:341 (fast-path stats)
└── Cursor jumps → output_renderer.zig:46 (update sorting)

Adding display feature?
├── New layer → compositor.zig (add to enum)
├── ANSI sequence → terminal_control.zig (implement)
├── Grid operation → screen_grid.zig (cell logic)
└── Window border → window_renderer.zig (rendering)
```

## Architecture Flow

| Stage | Direction | Components |
|-------|-----------|------------|
| **Input** | Terminal → backend → input_handler → Editor | Key events |
| **Render** | Editor → Compositor → Diff → output_renderer → Terminal | Display updates |

## Performance Optimizations

| # | Optimization | Impact | Status | Location |
|---|--------------|--------|--------|----------|
| 1 | Synchronized Updates | 2x smoother | ✅ | `display.zig:426` |
| 2 | Event Batching | 10-100x fewer | ✅ | `main.zig:690` |
| 3 | Render Throttling | 60 FPS cap | ✅ | `main.zig:126` |
| 4 | Color Tracking | 50-90% fewer | ✅ | `output_renderer.zig:84` |
| 5 | Cursor Tracking | No flicker | ✅ | `display.zig:478` |
| 6 | Scroll Regions | 10-100x scroll | 🏗️ | `terminal_control.zig:164` |
| 7 | Dirty Rectangles | 50-90% cells | 📋 | Future Phase 6 |
| 8 | Fast-Path Blend | 1.8x speedup | ✅ | `compositor.zig:341` |
| 9 | Update Sorting | 30-70% moves | ✅ | `output_renderer.zig:46` |

## Common Tasks

| Task | Implementation | Location |
|------|----------------|----------|
| **Add layer** | Define enum → Render function → Register | `compositor.zig` |
| **Optimize render** | Measure with E2E → Add metrics → Verify | `vim.e2e.pty.*` |
| **Debug output** | Add logger → Capture PTY → Analyze | `display.zig` |
| **New ANSI code** | Implement → Test terminals → Document | `terminal_control.zig` |

## Code Patterns

### Synchronized Updates (MANDATORY)
```zig
// display.zig:426
try self.beginSynchronizedUpdate();  // \x1bP=1s\x1b\\
// ... all rendering operations ...
try self.endSynchronizedUpdate();    // \x1bP=2s\x1b\\
try self.flush();  // Atomic update
```

### Fast-Path Blending
```zig
// compositor.zig:341
fn blendCell(src: Cell, dst: Cell, opacity: f32) Cell {
    // 95% of cells hit this path
    if (opacity >= 1.0 and src.char != 0 and src.char != ' ') {
        return src;  // Zero-cost copy!
    }
    // ... slow path for partial opacity ...
}
```

### Update Sorting
```zig
// output_renderer.zig:46
// Sort by (row, col) for adjacent cell batching
std.mem.sort(Update, updates, {}, lessThan);
// Now adjacent cells skip cursor movement
```

## Troubleshooting

| Problem | Likely Cause | Fix | Reference |
|---------|--------------|-----|-----------|
| Tearing | No sync updates | Check DCS support | `display.zig:426` |
| Flickering | Redundant codes | Check cursor tracking | `display.zig:478` |
| Slow render | No fast-path | Check opacity values | `compositor.zig:341` |
| Colors wrong | State not tracked | Check SGR tracking | `output_renderer.zig:84` |
| Cursor jumps | No sorting | Enable update sort | `output_renderer.zig:46` |

## Testing Rendering

### E2E PTY Capture
```typescript
// tests/e2e/rendering/e2e.ts
vim.e2e.pty.startCapture();
vim.e2e.keys("jjjjj");
vim.e2e.pty.render();

const hides = vim.e2e.pty.countHideCursor();
const moves = vim.e2e.pty.countCursorPositionCodes();
vim.e2e.assert.true(hides < 10, "Too many hides");
```

### Performance Metrics
```zig
// output_renderer.zig:19-21
cursor_moves_total: usize = 0,
cursor_moves_saved: usize = 0,
attribute_changes_deduped: usize = 0,
```

### Debug Logging
```zig
// Add for investigation
editor.logger.debug("LAYER[{s}]: dirty={} cells={}", .{name, dirty, count});
editor.logger.debug("ESCAPE: {s}", .{escape_code});
editor.logger.debug("BLEND: fast={} slow={}", .{fast_path, slow_path});
```

## Platform Notes

| Platform | Considerations | Testing |
|----------|---------------|---------|
| **macOS** | `SIGWINCH` for resize | iTerm2, Terminal.app |
| **Linux** | Check `TERM` env var | Alacritty, xterm |
| **Windows** | Limited ANSI (use WT) | Windows Terminal only |

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| No sync updates | Visible tearing | Enable DCS sequences |
| No state tracking | 10x escape codes | Track current state |
| Hot path allocs | Slow performance | Use stack buffers |
| Wrong ANSI | Terminal artifacts | Test multiple terminals |

## Performance Benchmarks

| Metric | Before | After | Location |
|--------|--------|-------|----------|
| Cursor flicker | 42 codes | 0 codes | `display.zig:478` |
| SGR codes | 100% sent | 10% sent | `output_renderer.zig:84` |
| Blending | 15ms | 8ms | `compositor.zig:341` |
| Update batch | Random | Sorted | `output_renderer.zig:46` |

## Future Work

| Feature | Phase | Complexity | Benefit |
|---------|-------|------------|---------|
| Scroll regions | 6 | High | 10-100x for scrolling |
| Dirty rectangles | 6 | High | 50-90% fewer updates |
| Terminal caps | 7 | Medium | Auto-detect features |
| Sixel graphics | 8 | Low | Image support |

## Cross-References

**Parent**: [Main CLAUDE.md](../../../CLAUDE.md)
**Related**: [Editor Core](../../editor/CLAUDE.md) · [JSI System](../jsi/CLAUDE.md)
**Docs**: [Rendering Architecture](../../../docs/architecture/rendering-architecture.md) · [Cursor Fix](../../../docs/bugfixes/cursor-flickering-fix.md)