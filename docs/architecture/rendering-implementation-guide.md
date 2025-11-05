# Rendering Implementation Guide

**Status**: Implementation Details  
**Date**: November 5, 2025  
**Audience**: Contributors implementing rendering features  
**Related**: [Rendering Architecture](./rendering-architecture.md)

---

## Quick Reference

### Current Rendering Pipeline

```
Input Event
    ↓
Handle Input (mode, buffer modification, etc.)
    ↓
Mark buffer/config dirty
    ↓
render() called
├─ adjustViewport()         [~0.1ms]
├─ updateGridFromBuffer()   [~1ms]
├─ diff()                   [~0.3ms]
├─ renderUpdates()          [~0.5ms]
└─ swapBuffers()            [<0.1ms]
    ↓
ANSI codes sent to terminal [~0.5ms]
```

**Total time**: ~2-3ms (good for 60fps)

---

## Key Components by File

### `display.zig` (806 lines)

**Main rendering orchestrator**

Key methods:
- `render()` - Main entry point, orchestrates pipeline
- `adjustViewport()` - Ensures cursor is visible
- `updateGridFromBuffer()` - Populates grid from buffer
- `renderUpdates()` - Outputs ANSI codes for changed cells
- `getTerminalSize()` - Handles terminal resize

Performance critical sections:
- `updateGridFromBuffer()` lines 379-600: Character-by-character rendering
- `renderUpdates()` lines 629-740: ANSI code generation
- Gutter rendering integration

**Optimization opportunities**:
- Line 381-398: Could batch gutter rendering
- Line 509-576: Slow path for visual/yank highlighting
- Line 629+: Adjacent cell detection (already optimized)

### `screen_grid.zig` (321 lines)

**Grid data structure and diff algorithm**

Key structures:
- `Cell` - Individual terminal cell with colors and attributes
- `ScreenGrid` - Double-buffered 2D grid
- `Update` - Changed cell information

Key methods:
- `diff()` - Core change detection algorithm
- `setCell()` - Write to current grid
- `setString()` - Fast path for text rendering
- `swapBuffers()` - Prepare for next frame

Performance critical:
- Lines 203-226: `diff()` iterates all dirty lines
- Lines 21-49: `Cell.eql()` is called for every diff cell

**Optimization opportunities**:
- Reduce Cell.eql() calls (already checking dirty_lines first)
- Could use rectangular damage regions instead of per-line bitset
- Combining character handling (lines 273-290)

### `gutter.zig` (201 lines)

**Modular gutter system (line numbers, signs)**

Key structures:
- `GutterManager` - Manages multiple gutter columns
- `GutterColumn` - Individual column with renderer
- Line number modes: absolute, relative, hybrid

Key methods:
- `registerColumn()` - Add new gutter column
- `renderLine()` - Render all columns for a line
- `getTotalWidth()` - Sum of enabled column widths
- `calculateLineNumberWidth()` - Width needed for line count

Performance characteristics:
- Width calculation: O(1) cached, invalidated on line count change
- Rendering: O(columns) per line (typically 1-2)
- Integration: Transparent to main rendering

**Note**: Gutter rendering happens per-line within `updateGridFromBuffer()`

### `char_width.zig` (167 lines)

**Unicode width calculations via Ghostty's uucode**

Key functions:
- `codepointWidth()` - Get width (0, 1, or 2)
- `stringWidth()` - Width of UTF-8 string
- `byteToDisplayColumn()` - Convert byte offset to display position
- `displayColumnToByte()` - Reverse mapping

Performance:
- `codepointWidth()` is O(1) lookup via uucode property
- Byte conversion: O(n) where n = string length
- Called frequently during rendering

**Critical for**:
- Cursor positioning with emoji
- Horizontal scrolling with wide characters
- Cell width determination

---

## Rendering Flow Details

### Step 1: `adjustViewport()` (lines 786-798)

Ensures cursor stays visible:

```
if cursor.row >= viewport_top + visible_rows:
    scroll down to show cursor
if cursor.row < viewport_top:
    scroll up to show cursor
```

**Time**: ~0.1ms
**Note**: Also handles horizontal scroll (per-line basis)

### Step 2: `updateGridFromBuffer()` (lines 378-600)

Most complex step - renders all visible content:

```
for each visible line (viewport_top to viewport_top + terminal_rows):
    render gutter (line numbers, signs)
    render text content:
        - fast path: just setString() for plain text
        - slow path: character-by-character for visual/yank highlighting
    apply visual selection colors
    apply yank flash colors
    pad line to terminal width
render status line
```

**Key decisions**:
- Lines 489: `use_fast_path` - Skip slow path if no highlighting
- Lines 499-507: Pre-calculate highlight colors
- Lines 509-576: Slow path processes each character

**Performance bottleneck**: This is typically 1-2ms

**Optimization ideas**:
1. Better fast path detection (check visual/yank before char loop)
2. Combine visual + yank highlighting logic
3. Use SIMD for character width lookups?
4. Cache line rendering results

### Step 3: `diff()` (lines 204-226)

Change detection:

```
for each line in dirty_lines bitset:
    for each column in line:
        if current[row][col] != previous[row][col]:
            add to updates list
return updates
```

**Time**: <0.5ms typically
**Scalability**: O(dirty_lines * width)
**Limit**: If 24 rows dirty, check 24*80=1920 cells

**Optimization**: Already optimized with bitset. Could add rectangular damage tracking for complex layouts.

### Step 4: `renderUpdates()` (lines 629-740)

Output ANSI codes:

```
for each Update in updates:
    skip continuation cells (handled by terminal)
    optimize cursor movement (adjacent detection)
    only output changed colors/attributes
    write character + combining chars
reset all attributes
flush to stdout
```

**Time**: ~0.5ms
**Key optimization**: Adjacent cell detection (line 651-656)
  - Moves cursor only if not adjacent
  - Saves multiple escape codes per line

**Output optimization**:
- Batches all codes in `output_buf` ArrayList
- Single `stdout.write()` call (line 739)
- Much faster than multiple writes

### Step 5: `swapBuffers()` (lines 230-240)

Prepare for next frame:

```
copy current -> previous
clear dirty_lines bitset
```

**Time**: <0.1ms
**Note**: Could be optimized with reference swapping instead of copy

---

## Common Modifications

### Adding a New Gutter Column

Example: Adding "breadcrumbs" gutter column

```zig
// 1. Define renderer function
pub fn renderBreadcrumb(line_num: usize, cursor_line: usize, buf: []u8) usize {
    _ = cursor_line;
    // Return breadcrumb for this line
    const breadcrumb = getBreadcrumbForLine(line_num);
    return std.fmt.bufPrint(buf, "{s} ", .{breadcrumb}) catch buf[0..0];
}

// 2. Register in Display.updateGutterColumns()
try self.gutter_manager.registerColumn("breadcrumb", renderBreadcrumb);

// 3. Set column properties
if (self.gutter_manager.getColumn("breadcrumb")) |col| {
    col.cached_width = 20;  // Width in characters
}
```

### Changing Highlight Colors

Example: Make visual selection brighter

```zig
// In highlights.zig or config loading
const visual_hl = Highlight{
    .bg = Color{ .r = 100, .g = 150, .b = 255 },  // Bright blue
    .fg = Color{ .r = 0, .g = 0, .b = 0 },       // Black text
};
config.visual = visual_hl;
```

The rendering automatically uses this in `updateGridFromBuffer()` line 499.

### Adding New Visual State

Example: Add "search highlight" visual state

```zig
// In visual.zig
pub const SearchHighlight = struct {
    active: bool = false,
    ranges: ArrayList(Range),
    // ... implementation
};

// In display.zig updateGridFromBuffer()
const search_active = search_highlight.active and search_highlight.isVisible();

// In character loop (around line 545)
const final_bg = if (search_active and search_highlight.contains(char_pos))
    search_bg
else if (yank_active and yank_highlight.contains(char_pos))
    yank_bg
else if (visual_active and visual_state.contains(cursor_pos, char_pos))
    visual_bg
else
    bg_color;
```

---

## Performance Optimization Checklist

### Benchmarking

- [ ] Measure current performance with `Benchmark` struct
- [ ] Profile `updateGridFromBuffer()` with large files
- [ ] Check diff() time with many dirty lines
- [ ] Terminal I/O time with different content

### Quick wins

- [ ] Cache line number width calculation (already done)
- [ ] Skip slow path when no visual/yank (already done)
- [ ] Adjacent cell detection in renderUpdates() (already done)
- [ ] Combine color codes for adjacent cells with same color

### Medium effort

- [ ] Replace per-line dirty_lines with rectangular damage regions
- [ ] Virtual scrolling for long files
- [ ] Lazy gutter rendering (only visible lines)
- [ ] Cache highlight lookups

### Large effort

- [ ] Replace ArrayList buffer with rope data structure
- [ ] Implement window manager for splits/floats
- [ ] Cached component rendering
- [ ] Syntax highlighting integration

---

## Integration Points with Future Layers

### Layer 2: Window Manager

When window manager is added:

1. Each window calls `render_buffer()` for its portion
2. Results in a VirtualGrid per window
3. Windows are composited with z-order
4. Final grid sent to terminal

**Impact on current code**:
- `updateGridFromBuffer()` would become `WindowRenderer.render()`
- Display would orchestrate window rendering
- diff() stays the same
- renderUpdates() stays the same

### Layer 4: Plugin API

Plugins need:
- Read-only access to viewport state
- Ability to set decorations/highlights
- No direct grid access

**Impact on current code**:
- Expose: viewport_top, viewport_left, terminal_rows, terminal_cols
- Add methods: setLineDecoration(), setHighlight()
- Invalidate dirty flags on plugin changes

---

## Testing Rendering

### Unit tests

Check `screen_grid.zig` for grid-level tests:
- Cell equality (`eql()`)
- Diff detection
- String rendering with wide chars

```bash
zig build test
```

### Integration tests

Manual testing with terminal:
```bash
./zig-out/bin/openvim test_file.txt
```

Check:
- Emoji render correctly (width 2)
- Line numbers align
- Visual selection highlights properly
- Yank flash appears for 250ms

### Performance testing

Benchmark with large files:
```bash
./zig-out/bin/openvim --bench large_file.txt
```

Should see:
- Incremental updates <1ms
- Full redraws ~2-3ms
- Responsive to 60fps

---

## Debugging Rendering Issues

### Enable debug logging

In `debug/log.zig`:
```zig
const ENABLE_LOGGING = true;  // Set to true
```

Then run with:
```bash
./zig-out/bin/openvim file.txt 2>debug.log
```

Check debug.log for timing info.

### Inspect grid state

In `screen_grid.zig`, add temporary debug output:

```zig
pub fn dumpGridDebug(self: *ScreenGrid) void {
    for (0..3) |row| {  // First 3 rows
        for (0..10) |col| {  // First 10 cols
            const cell = self.current[row][col];
            std.debug.print("[{d}:{d}]={c} ", .{row, col, cell.char});
        }
        std.debug.print("\n", .{});
    }
}
```

### Common issues

| Issue | Cause | Fix |
|-------|-------|-----|
| **Emoji shows as 2 chars** | Width calculation wrong | Check `char_width.codepointWidth()` |
| **Cursor wrong position** | Byte vs display column confusion | Debug `byteToDisplayColumn()` |
| **Visual highlight missing** | Dirty flag not set | Check `visual_state.active` condition |
| **Slow rendering** | Too many dirty lines | Profile with benchmark |
| **Colors wrong** | Highlight not applied | Check color precedence in updateGridFromBuffer |

---

## Performance Targets by Phase

### Phase 1 (Current)
- Full redraw: 2-3ms
- Incremental: <1ms
- No splits/floats

### Phase 2 (Window Manager)
- Multiple windows: <5ms
- Floating windows: <5ms
- Assumes good caching

### Phase 3 (Plugin API)
- With plugin rendering: <5ms
- Requires batching and region-based updates
- Virtual scrolling for large lists

---

## Recommended Reading Order

1. Start: `display.zig` lines 302-376 (render() method)
2. Then: `screen_grid.zig` lines 62-68 (Update struct) and 203-226 (diff)
3. Deep dive: `display.zig` lines 378-600 (updateGridFromBuffer)
4. Optimize: `display.zig` lines 629-740 (renderUpdates)
5. Extend: `gutter.zig` for modular rendering

---

## Key Variables to Track

| Variable | Meaning | Set by |
|----------|---------|--------|
| `viewport_top` | First visible line (0-indexed) | `adjustViewport()` |
| `viewport_left` | Horizontal scroll offset | `adjustViewport()` |
| `terminal_rows` | Terminal height | `getTerminalSize()` |
| `terminal_cols` | Terminal width | `getTerminalSize()` |
| `dirty_lines` | Bitset of changed lines | `setCell()`, `markDirty()` |
| `current[][]` | Current frame grid | `setCell()`, `setString()` |
| `previous[][]` | Previous frame grid | `swapBuffers()` |

For debugging, add logging at the start of render():
```zig
debug_log.log("render: viewport={}:{} size={}x{}", .{
    self.viewport_top, self.viewport_left,
    self.terminal_cols, self.terminal_rows
});
```

