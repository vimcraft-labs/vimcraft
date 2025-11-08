# Multi-Layer Rendering Architectures for Terminal Text Editors

**Research Date:** 2025-11-08
**Context:** OpenVim architecture planning for cursor trail overlay and future floating windows
**Research Scope:** Terminal compositor patterns, editor-specific multi-layer systems, headless core design, and best practices

## Executive Summary

Terminal text editors face a unique challenge: achieving multi-layer rendering (floating windows, overlays, popups) without native Z-ordering support from the terminal. This research examines three proven approaches:

1. **Helix's Component Stack** - Simple Vec-based layering with immediate-mode rendering
2. **Neovim's Grid Compositor** - Z-indexed grid arrays with dirty region compositing
3. **Xi Editor's Headless Core** - Complete separation of logical layers from rendering layers

**Recommendation for OpenVim:** Adopt a **hybrid Neovim+Helix pattern with headless-first design** - combine Neovim's grid compositor concepts with Helix's simplicity, exposed via JSI for plugin-driven layer management.

---

## 1. Terminal Compositor Patterns (TUI Frameworks)

### 1.1 Ratatui (Rust TUI Framework)

**Architecture:** Immediate-mode rendering with buffer-based compositing

**Key Components:**
- **Terminal struct:** Manages internal buffer, handles backend communication, coordinates render cycle
- **Buffer:** Intermediate representation storing cells before terminal output
- **Backend:** Pluggable (Crossterm, Termion) - handles actual ANSI code generation
- **Layout system:** Constraint-based space allocation (Percentage, Min, Max, Fill)

**Rendering Flow:**
```
Widget::render() → Buffer (intermediate) → diff() → Backend → Terminal
```

**Layering Approach:**
- **No explicit compositor** - relies on render order
- Draw base widgets first, overlays last (painter's algorithm)
- Each frame: full redraw to buffer, diff against previous, send only changes

**Strengths:**
- ✅ Simple immediate-mode mental model
- ✅ Efficient diff-based updates minimize ANSI codes
- ✅ Works with any terminal (no special features required)

**Weaknesses:**
- ❌ No true layer abstraction - manual Z-ordering via call order
- ❌ No saved/restored regions - must redraw occluded content

**Relevance to OpenVim:**
- Buffer-based diff optimization (already implemented in ScreenGrid)
- Constraint-based layout could inform floating window positioning

---

### 1.2 Crossterm vs Termion

**Finding:** These are **terminal manipulation libraries**, not UI frameworks.

**Crossterm:**
- Pure Rust, cross-platform (Windows, Unix)
- Higher-level API (cursor movement, styling, events)
- ~5-10 fps slower than Termion (Console API overhead)

**Termion:**
- Unix-only, thin wrapper over ANSI codes
- Faster raw performance
- Less portable

**Rendering Strategy (Both):**
- No built-in layering/compositing
- Provide cursor positioning + ANSI code generation
- **Z-ordering must be implemented by the application** (render order)

**Relevance to OpenVim:**
- OpenVim's current approach (raw ANSI codes) is equivalent to Termion's philosophy
- Crossterm's event handling might inform future input refactoring
- **Key insight:** Terminal backends don't solve layering - that's an application concern

---

## 2. Editor-Specific Multi-Layer Systems

### 2.1 Neovim's UI Compositor

**Source:** `/Users/le/projects/neovim/src/nvim/ui_compositor.c`

**Architecture:** Z-indexed grid array with area-based compositing

#### Core Data Structures

```c
// Grid with compositor metadata
struct ScreenGrid {
    // Grid content
    schar_T *chars;      // UTF-8 cell content
    sattr_T *attrs;      // Highlighting attributes
    colnr_T *vcols;      // Virtual columns (for mouse clicks)

    // Grid state
    int rows, cols;
    bool valid;          // Needs redraw?
    bool throttled;      // Don't send updates yet
    bool blending;       // Alpha blend with background

    // Compositor metadata
    int comp_row, comp_col;        // Position on composed screen
    int comp_width, comp_height;   // Requested dimensions
    size_t comp_index;             // Z-order (index in layers array)
    int zindex;                    // Logical Z-index
    bool comp_disabled;            // Temporarily ignore
};

// Global compositor state
kvec_t(ScreenGrid *) layers;  // Sorted by zindex
static schar_T *linebuf;      // Composition scratch buffer
static sattr_T *attrbuf;      // Attribute scratch buffer
```

#### Z-Index System

Predefined Z-index ranges:
```c
kZIndexDefaultGrid = 0      // Main editor grid
kZIndexFloatDefault = 50    // Floating windows
kZIndexPopupMenu = 100      // Completion menu
kZIndexMessages = 200       // Message area
kZIndexCmdlinePopupMenu = 250  // Command-line completion
```

**Z-Index Management:**
- Grids stored in `layers` vector, sorted by `zindex`
- `comp_index` = actual position in array (updated on reorder)
- `ui_comp_layers_adjust()` maintains sort order (bubble sort on insert/update)

#### Compositing Algorithm

**`compose_line(row, startcol, endcol)`:**
```c
// Baseline implementation: for each column in range
for (col in startcol..endcol) {
    // Find topmost grid covering this column
    grid = NULL;
    for (i in layers) {
        if (grid[i] covers (row, col)) {
            grid = grid[i];  // Higher index = on top
        }
    }

    // Copy cell from grid to output buffer
    linebuf[col] = grid->chars[local_offset];
    attrbuf[col] = grid->attrs[local_offset];

    // Handle blending (pumblend, winblend)
    if (grid->blending) {
        attrbuf[col] = hl_blend_attrs(bg_grid->attrs[col],
                                       attrbuf[col],
                                       &transparent);
        if (transparent) {
            linebuf[col] = bg_grid->chars[col];
        }
    }
}

// Send composed line to UI
ui_call_raw_line(1, row, startcol, endcol, linebuf, attrbuf);
```

**Dirty Region Optimization:**
- When moving a grid: only recompose exposed areas
```c
bool ui_comp_put_grid(ScreenGrid *grid, int row, int col, ...) {
    if (moved) {
        grid->comp_disabled = true;  // Exclude from composition

        // Recompose old position (now visible)
        compose_area(old_row, old_row + old_height,
                     old_col, old_col + old_width);

        grid->comp_disabled = false;

        // Recompose new position
        compose_area(new_row, new_row + new_height,
                     new_col, new_col + new_width);
    }
}
```

**Scroll Optimization:**
- If grid is occluded: recompose scrolled region (can't scroll)
- If grid is top-layer: send scroll event directly

#### Blending Support

**`pumblend` and `winblend` options:**
- Grid marked with `blending = true`
- During composition: blend attributes with background grid
- Transparent cells (`' '` or Braille blank `U+2800`) show background text

**Formula:**
```c
result_attr = hl_blend_attrs(bg_attr, fg_attr, &show_bg_text);
if (show_bg_text) {
    result_char = bg_char;
}
```

#### Mouse Hit Testing

**`ui_comp_mouse_focus(row, col)`:**
```c
// Search from top layer downward
for (i = layers.size - 1; i >= 0; i--) {
    grid = layers[i];
    if (grid->mouse_enabled &&
        row in [grid->comp_row, grid->comp_row + grid->rows) &&
        col in [grid->comp_col, grid->comp_col + grid->cols)) {
        return grid;
    }
}
return default_grid;
```

**Key Insight:** Mouse events respect visual Z-order (top layer wins)

---

### 2.2 Helix's Component Compositor

**Source:** `/Users/le/projects/helix/helix-term/src/compositor.rs`

**Architecture:** Vec-based component stack with Cursive-inspired trait system

#### Core Types

```rust
pub trait Component: Any + AnyComponent {
    // Event handling (returns Consumed or Ignored with optional callback)
    fn handle_event(&mut self, event: &Event, ctx: &mut Context)
        -> EventResult;

    // Rendering
    fn render(&mut self, area: Rect, surface: &mut Surface, ctx: &mut Context);

    // Optimization: skip render if unchanged
    fn should_update(&self) -> bool { true }

    // Cursor state
    fn cursor(&self, area: Rect, editor: &Editor) -> (Option<Position>, CursorKind);

    // Layout: child may request size larger than viewport (scrolling)
    fn required_size(&mut self, viewport: (u16, u16)) -> Option<(u16, u16)>;
}

pub struct Compositor {
    layers: Vec<Box<dyn Component>>,  // Simple stack
    area: Rect,                       // Terminal size
    full_redraw: bool,                // Force full redraw flag
}
```

#### Layering Mechanism

**Simple stack semantics:**
```rust
impl Compositor {
    // Add layer on top
    pub fn push(&mut self, layer: Box<dyn Component>) {
        self.layers.push(layer);
    }

    // Remove top layer
    pub fn pop(&mut self) -> Option<Box<dyn Component>> {
        self.layers.pop()
    }

    // Remove specific component by ID or type
    pub fn remove(&mut self, id: &'static str) -> Option<Box<dyn Component>>;
    pub fn remove_type<T: 'static>(&mut self);
}
```

**No Z-index** - order determined by vector position (last pushed = top layer)

#### Event Bubbling

**Bottom-up propagation:**
```rust
pub fn handle_event(&mut self, event: &Event, cx: &mut Context) -> bool {
    let mut callbacks = Vec::new();
    let mut consumed = false;

    // Process from top layer (last in vec) to bottom
    for layer in self.layers.iter_mut().rev() {
        match layer.handle_event(event, cx) {
            EventResult::Consumed(callback) => {
                if let Some(cb) = callback {
                    callbacks.push(cb);
                }
                consumed = true;
                break;  // Stop propagation
            }
            EventResult::Ignored(callback) => {
                if let Some(cb) = callback {
                    callbacks.push(cb);
                }
                // Continue to next layer
            }
        }
    }

    // Execute callbacks after event handling
    for callback in callbacks {
        callback(self, cx);
    }

    consumed
}
```

**Key Pattern:** Callbacks allow modifying compositor (push/pop layers) during event handling

#### Rendering

**Simple painter's algorithm:**
```rust
pub fn render(&mut self, area: Rect, surface: &mut Surface, cx: &mut Context) {
    // Render from bottom to top (first pushed = drawn first)
    for layer in &mut self.layers {
        layer.render(area, surface, cx);
    }
}
```

**Surface (Buffer):**
- Immediate-mode: each component draws directly to surface
- No saved regions - components must redraw if occluded content changes
- Diff optimization happens at buffer-to-terminal level (ratatui)

#### Cursor Management

**Top layer wins:**
```rust
pub fn cursor(&self, area: Rect, editor: &Editor) -> (Option<Position>, CursorKind) {
    // Search from top layer downward
    for layer in self.layers.iter().rev() {
        if let (Some(pos), kind) = layer.cursor(area, editor) {
            return (Some(pos), kind);
        }
    }
    (None, CursorKind::Hidden)
}
```

#### Component Examples

**Popup (container component):**
```rust
pub struct Popup<T: Component> {
    contents: T,           // Child component
    position: Option<Position>,
    size: (u16, u16),
    auto_close: bool,
    id: &'static str,
}

impl<T: Component> Component for Popup<T> {
    fn render(&mut self, area: Rect, surface: &mut Surface, cx: &mut Context) {
        // Calculate popup area (centered or at position)
        let popup_area = ...;

        // Render border (if any)
        ...

        // Render child within popup area
        self.contents.render(popup_area, surface, cx);
    }
}
```

**Overlay (full-screen dim + content):**
- Renders transparent overlay over entire screen
- Renders child content on top

---

### 2.3 Comparison: Neovim vs Helix

| Aspect | Neovim | Helix |
|--------|---------|-------|
| **Complexity** | High - full compositor | Low - simple stack |
| **Z-ordering** | Explicit (zindex field) | Implicit (vector order) |
| **Dirty tracking** | Area-based recomposition | Full redraw to buffer |
| **Blending** | Native support (pumblend) | No native support |
| **Mouse events** | Z-aware hit testing | Top layer wins |
| **TUI/GUI split** | Compositor for TUI, multigrid for GUI | TUI only |
| **Best for** | Complex overlapping UIs | Simple modal dialogs |

**OpenVim Implications:**
- Start with Helix simplicity (Vec stack)
- Add Neovim's Z-index when floating windows arrive
- Keep compositor in display layer (not core) for headless flexibility

---

## 3. Headless Core Architectures

### 3.1 Xi Editor Architecture

**Source:** Web research + Xi editor retrospective

**Core Insight:** Separate **logical representation** from **rendering representation**

#### Three-Process Model

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│  Frontend   │◄───────►│   Xi Core    │◄───────►│   Plugins    │
│   (UI)      │   RPC   │  (Headless)  │   RPC   │  (Syntax,    │
│             │         │              │         │   LSP, etc.) │
└─────────────┘         └──────────────┘         └──────────────┘
     │                        │                         │
     │                        │                         │
  Rendering              Rope CRDT              Async updates
  (layers)            (truth source)          (no blocking)
```

#### Core Responsibilities

**Xi Core (headless):**
- Text storage (Rope data structure)
- Edit operations (CRDT for concurrent edits)
- Undo/redo tree
- Selection management
- Change notifications

**Frontend (UI):**
- Grid rendering
- Input handling
- Layer management (overlays, floating windows)
- Cursor animation
- Scroll management

**Plugins (external processes):**
- Syntax highlighting (tree-sitter)
- LSP integration
- Linting
- Formatters

#### Communication Protocol

**Core → Frontend (updates):**
```json
{
  "method": "update",
  "params": {
    "ops": [
      {"op": "ins", "n": 5, "lines": ["hello"]},
      {"op": "skip", "n": 10},
      {"op": "invalidate", "n": 3}
    ],
    "pristine": false
  }
}
```

**Frontend → Core (edits):**
```json
{
  "method": "edit",
  "params": {
    "view_id": "view-1",
    "method": "insert",
    "params": {"chars": "x"}
  }
}
```

#### Key Benefits

✅ **UI independence:** Same core works with terminal, GUI, web frontends
✅ **Plugin isolation:** Syntax highlighting can't crash editor
✅ **Async everything:** Long operations never block UI
✅ **Testing:** Core logic testable without UI

#### Challenges

❌ **Latency:** Inter-process RPC adds overhead
❌ **Complexity:** Three codebases to maintain
❌ **State sync:** Core and frontend can diverge

---

### 3.2 Headless Principles Applied to OpenVim

**Current OpenVim Architecture:**
```
┌──────────────────────────────────────┐
│          OpenVim Binary              │
│  ┌────────────┐    ┌──────────────┐  │
│  │   Core     │    │   Display    │  │
│  │  (Zig)     │───►│   (Zig)      │  │
│  │            │    │   (Terminal) │  │
│  └────────────┘    └──────────────┘  │
│         │                             │
│         ▼                             │
│  ┌──────────────┐                     │
│  │  Hermes JSI  │                     │
│  │  (Plugins)   │                     │
│  └──────────────┘                     │
└──────────────────────────────────────┘
```

**Proposed Layering System (Headless-First):**

```zig
// Core: Logical layers (no rendering knowledge)
pub const LayerManager = struct {
    layers: std.ArrayList(Layer),  // Logical layer stack

    pub const Layer = struct {
        id: LayerId,
        zindex: i32,
        content: LayerContent,
        position: Rect,        // Logical position
        visible: bool,
        blending: bool,
    };

    pub const LayerContent = union(enum) {
        buffer: BufferId,      // Main editor buffer
        overlay: OverlayData,  // Generic overlay (trail, selection)
        popup: PopupData,      // Menu, completion
        float: FloatData,      // Floating window
    };
};

// Display: Rendering layers (compositor implementation)
pub const DisplayCompositor = struct {
    grid: ScreenGrid,              // Base grid
    scratch_buffers: []Cell,       // Composition scratch space

    pub fn compose(
        self: *DisplayCompositor,
        layers: []const LayerManager.Layer
    ) !void {
        // Neovim-style area composition
        for (layers) |layer| {
            if (!layer.visible) continue;

            switch (layer.content) {
                .buffer => |buf_id| self.renderBuffer(buf_id, layer.position),
                .overlay => |data| self.renderOverlay(data, layer.position),
                .popup => |data| self.renderPopup(data, layer.position),
                .float => |data| self.renderFloat(data, layer.position),
            }
        }
    }
};
```

**JSI API for Plugins:**

```javascript
// JavaScript plugin can manage layers
const trailLayer = editor.createLayer({
    type: 'overlay',
    zindex: 10,
    blending: true
});

trailLayer.setCells([
    { row: 5, col: 10, char: ' ', bg: '#ff0000' },
    { row: 5, col: 11, char: ' ', bg: '#ff3333' },
]);

editor.showLayer(trailLayer.id);

// Later
editor.hideLayer(trailLayer.id);
editor.destroyLayer(trailLayer.id);
```

**Benefits:**
- ✅ Core has no display dependencies (testable, portable)
- ✅ Compositor can be swapped (terminal → GUI)
- ✅ Plugins control layers via clean API
- ✅ Zig core + JS extensibility = best of both worlds

---

## 4. Best Practices & Recommendations

### 4.1 When to Use Saved/Restored Cells vs Full Recompose

**Saved/Restored (OpenVim's Trail Pattern):**

```zig
// TrailRenderer.zig (current implementation)
pub fn applyToGrid(self: *TrailRenderer, grid: *ScreenGrid) void {
    // 1. Restore cells from previous frame
    for (self.saved_cells.items) |saved| {
        grid.setCell(saved.row, saved.col, saved.cell);
    }

    // 2. Save current cells at trail positions
    for (self.cells.items) |trail| {
        self.saved_cells.append(SavedCell{
            .row = trail.row,
            .col = trail.col,
            .cell = grid.current[trail.row][trail.col],
        });
    }

    // 3. Overlay trail
    for (self.cells.items) |trail| {
        grid.setCell(trail.row, trail.col, trail.cell);
    }
}
```

**When to use:**
- ✅ Temporary overlays (cursor trail, search highlight flash)
- ✅ Small number of cells (< 100)
- ✅ Overlay moves frequently
- ✅ Restoring is cheaper than redrawing background

**Full Recompose (Neovim Pattern):**

```zig
pub fn compose(self: *Compositor, row: usize, col: usize) Cell {
    // Search layers top-down
    for (self.layers.items) |layer| {
        if (layer.contains(row, col)) {
            return layer.getCell(row, col);
        }
    }
    return default_cell;
}
```

**When to use:**
- ✅ Persistent overlays (floating windows, popups)
- ✅ Large areas (entire window)
- ✅ Multiple overlapping layers
- ✅ Complex blending/transparency

**Hybrid Approach (Recommended for OpenVim):**
```zig
pub const Compositor = struct {
    // Persistent layers (full recompose)
    layers: std.ArrayList(Layer),

    // Temporary overlays (save/restore)
    temp_overlays: std.ArrayList(TempOverlay),

    pub fn compose(self: *Compositor, row: usize, col: usize) Cell {
        // 1. Compose persistent layers (bottom-up)
        var cell = self.composeLayersAt(row, col);

        // 2. Apply temporary overlays (saved/restore on next frame)
        if (self.getTempOverlayAt(row, col)) |overlay| {
            cell = overlay.cell;
        }

        return cell;
    }
};
```

---

### 4.2 Z-Index Management Strategies

**Strategy 1: Predefined Ranges (Neovim)**

```zig
pub const ZIndex = enum(i32) {
    default_grid = 0,
    float_default = 50,
    popup_menu = 100,
    messages = 200,
    cmdline_popup = 250,
    _,  // Allow custom values
};
```

✅ Clear semantics
✅ Easy to reason about layering
❌ Inflexible (gaps waste space)

**Strategy 2: Relative Ordering (Helix)**

```zig
pub fn push(self: *Compositor, layer: Layer) void {
    self.layers.append(layer);  // Always on top
}

pub fn raise(self: *Compositor, id: LayerId) void {
    const idx = self.findLayer(id);
    const layer = self.layers.orderedRemove(idx);
    self.layers.append(layer);  // Move to top
}
```

✅ Simple implementation
✅ No gaps
❌ No semantic meaning to order

**Strategy 3: Hybrid (Recommended for OpenVim)**

```zig
pub const Layer = struct {
    id: LayerId,
    zindex: i32,          // Explicit order
    category: Category,   // Semantic grouping

    pub const Category = enum {
        background,   // Z: -100 to -1
        editor,       // Z: 0 to 49
        float,        // Z: 50 to 99
        popup,        // Z: 100 to 199
        overlay,      // Z: 200 to 299
        cursor,       // Z: 300+
    };
};

pub fn addLayer(self: *Compositor, layer: Layer) void {
    // Insert sorted by zindex
    const insert_idx = self.findInsertPosition(layer.zindex);
    self.layers.insert(insert_idx, layer);
}

fn findInsertPosition(self: *Compositor, zindex: i32) usize {
    // Binary search for insertion point
    var left: usize = 0;
    var right: usize = self.layers.items.len;

    while (left < right) {
        const mid = (left + right) / 2;
        if (self.layers.items[mid].zindex < zindex) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }

    return left;
}
```

Benefits:
- ✅ Explicit Z-index (precise control)
- ✅ Categories for semantic grouping
- ✅ Efficient insertion (binary search)
- ✅ Plugin-friendly (JS can specify zindex)

---

### 4.3 Efficient Dirty Tracking Across Layers

**Problem:** Minimizing redraws when layers change

**Approach 1: Per-Layer Dirty Flags (Simple)**

```zig
pub const Layer = struct {
    dirty: bool,  // Layer content changed
    visible_changed: bool,  // Visibility toggled
};

pub fn render(self: *Compositor) !void {
    for (self.layers.items) |layer| {
        if (layer.dirty or layer.visible_changed) {
            self.recomposeArea(layer.bounds);
            layer.dirty = false;
            layer.visible_changed = false;
        }
    }
}
```

✅ Simple
❌ Coarse-grained (redraws entire layer bounds)

**Approach 2: Rectangle-Based Dirty Regions (Neovim)**

```zig
pub const DirtyRegion = struct {
    start_row: usize,
    end_row: usize,
    start_col: usize,
    end_col: usize,
};

pub fn markDirty(self: *Compositor, region: DirtyRegion) !void {
    try self.dirty_regions.append(region);
}

pub fn render(self: *Compositor) !void {
    // Merge overlapping regions
    const merged = self.mergeRegions(self.dirty_regions.items);

    for (merged) |region| {
        self.recomposeArea(region);
    }

    self.dirty_regions.clearRetainingCapacity();
}

fn mergeRegions(regions: []DirtyRegion) []DirtyRegion {
    // Sort by start_row, then merge adjacent/overlapping
    std.sort.sort(DirtyRegion, regions, {}, compareRegions);

    var merged = ArrayList(DirtyRegion).init(allocator);
    var current: ?DirtyRegion = null;

    for (regions) |region| {
        if (current == null) {
            current = region;
        } else if (regionsOverlap(current.?, region)) {
            current = mergeTwo(current.?, region);
        } else {
            merged.append(current.?);
            current = region;
        }
    }

    if (current) |c| merged.append(c);
    return merged.items;
}
```

✅ Fine-grained (only redraw changed areas)
✅ Efficient for sparse updates
❌ Complex implementation
❌ Merge overhead

**Approach 3: Threshold-Based (Adaptive)**

```zig
pub const Compositor = struct {
    dirty_threshold: usize = 100,  // Cells changed

    pub fn render(self: *Compositor) !void {
        const dirty_count = self.countDirtyCells();

        if (dirty_count > self.dirty_threshold or
            dirty_count > self.grid.total_cells / 4) {
            // Too many dirty cells - just redraw everything
            self.fullRecompose();
        } else {
            // Selective recompose
            for (self.dirty_regions.items) |region| {
                self.recomposeArea(region);
            }
        }
    }
};
```

✅ Adapts to update size
✅ Avoids merge overhead for large changes
✅ Simple fallback

**Recommendation for OpenVim:** Start with Approach 1 (per-layer flags), add Approach 3 (threshold) when floating windows arrive.

---

### 4.4 Blending/Transparency in Terminals

**Challenge:** Terminals don't support true alpha blending

**Solutions:**

**1. Background Color Only (Current OpenVim Trail)**
```zig
// Overlay with background color, no foreground
const trail_cell = Cell{
    .char = ' ',  // Empty character
    .bg = Color{ .r = 255, .g = 100, .b = 0 },  // Orange
    .fg = null,   // No foreground
};
```
✅ Simple
✅ Works on all terminals
❌ Can't show text through overlay

**2. Attribute Blending (Neovim `pumblend`)**
```zig
// Simulated transparency: blend colors mathematically
fn blendColors(bg: Color, fg: Color, alpha: u8) Color {
    const alpha_f = @intToFloat(f32, alpha) / 255.0;
    return Color{
        .r = @floatToInt(u8, @intToFloat(f32, bg.r) * (1.0 - alpha_f) +
                               @intToFloat(f32, fg.r) * alpha_f),
        .g = @floatToInt(u8, @intToFloat(f32, bg.g) * (1.0 - alpha_f) +
                               @intToFloat(f32, fg.g) * alpha_f),
        .b = @floatToInt(u8, @intToFloat(f32, bg.b) * (1.0 - alpha_f) +
                               @intToFloat(f32, fg.b) * alpha_f),
    };
}
```
✅ Smooth color transitions
✅ Configurable transparency (0-255)
❌ Requires recomposing layers

**3. Character-Level Transparency (Vim Popup)**
```zig
// Special characters treated as transparent
const transparent_chars = [_]u21{ ' ', 0x2800 };  // Space, Braille blank

fn isTransparent(char: u21) bool {
    return std.mem.indexOfScalar(u21, &transparent_chars, char) != null;
}

// During composition
if (isTransparent(overlay.char)) {
    // Show background text
    cell.char = bg_layer.char;
    cell.fg = bg_layer.fg;
} else {
    // Show overlay
    cell.char = overlay.char;
    cell.fg = overlay.fg;
}
cell.bg = blendColors(bg_layer.bg, overlay.bg, overlay.alpha);
```
✅ Text shows through overlay
✅ Flexible
❌ Complex composition logic

**Recommendation for OpenVim:**
- Trail: Keep Approach 1 (simple, no text needed)
- Floating windows: Use Approach 2 (blended backgrounds)
- Future menus/popups: Consider Approach 3 (text show-through)

---

## 5. Architectural Recommendations for OpenVim

### 5.1 Short-Term (Phase 3: Text Editing)

**Goal:** Support cursor trail overlay (already working) + yank flash

**Current Implementation:**
```zig
// display.zig:369 - Trail overlay (save/restore pattern)
self.trail.applyToGrid(&self.grid);
```

✅ Already correct for temporary overlays
✅ No changes needed

**Enhancement:** Generalize for other temporary overlays
```zig
// New: TempOverlayManager
pub const TempOverlay = struct {
    id: u32,
    cells: []const TrailCell,
    lifetime: enum { single_frame, timed, manual },
    expiry_ms: ?u64,  // For timed overlays
};

pub const TempOverlayManager = struct {
    overlays: std.ArrayList(TempOverlay),
    next_id: u32,

    pub fn add(self: *Self, overlay: TempOverlay) u32 {
        const id = self.next_id;
        self.next_id += 1;
        overlay.id = id;
        self.overlays.append(overlay);
        return id;
    }

    pub fn remove(self: *Self, id: u32) void {
        const idx = std.mem.indexOfScalar(...);
        _ = self.overlays.orderedRemove(idx);
    }

    pub fn tick(self: *Self, now_ms: u64) void {
        // Remove expired overlays
        var i: usize = 0;
        while (i < self.overlays.items.len) {
            const overlay = self.overlays.items[i];
            if (overlay.lifetime == .timed and
                now_ms > overlay.expiry_ms.?) {
                _ = self.overlays.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};
```

**Usage:**
```zig
// Yank flash (500ms)
const flash_overlay = TempOverlay{
    .cells = yank_cells,
    .lifetime = .timed,
    .expiry_ms = now_ms + 500,
};
display.temp_overlays.add(flash_overlay);
```

---

### 5.2 Medium-Term (Phase 4: Plugin System)

**Goal:** Expose layer management to JavaScript plugins

**JSI API Design:**

```javascript
// JavaScript plugin API
class LayerManager {
    // Create temporary overlay (trail, flash, etc.)
    createTempOverlay(cells, lifetimeMs) {
        return native.display_create_temp_overlay(cells, lifetimeMs);
    }

    // Remove overlay
    removeOverlay(id) {
        native.display_remove_overlay(id);
    }

    // Future: Create persistent layer (floating window)
    createLayer(config) {
        return native.compositor_create_layer({
            zindex: config.zindex || 50,
            position: config.position,
            size: config.size,
            blending: config.blending || false,
        });
    }
}

// Example: Smear cursor plugin
const smearCursor = {
    trail: [],
    maxLength: 5,

    onCursorMove(newPos) {
        this.trail.push(newPos);
        if (this.trail.length > this.maxLength) {
            this.trail.shift();
        }

        const cells = this.trail.map((pos, i) => ({
            row: pos.row,
            col: pos.col,
            char: ' ',
            bg: this.fadeColor(i),  // Fade effect
        }));

        editor.layers.createTempOverlay(cells, 100);
    },

    fadeColor(index) {
        const alpha = (index / this.maxLength) * 255;
        return rgbToHex(255, 100, 0, alpha);
    }
};
```

**Zig Implementation (JSI Bridge):**

```zig
// src/jsi/display_api.zig
export fn display_create_temp_overlay(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    // Parse args: cells (array), lifetimeMs (number)
    const cells_array = args[0];
    const lifetime_ms = c.hermes_value_to_number(runtime, args[1]);

    // Convert JS array to Zig array
    var cells = std.ArrayList(TrailCell).init(allocator);
    const len = c.hermes_array_length(runtime, cells_array);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const cell_obj = c.hermes_array_get(runtime, cells_array, i);

        const row = c.hermes_object_get_number(runtime, cell_obj, "row");
        const col = c.hermes_object_get_number(runtime, cell_obj, "col");
        const char = c.hermes_object_get_number(runtime, cell_obj, "char");
        const bg = c.hermes_object_get_number(runtime, cell_obj, "bg");

        cells.append(TrailCell{
            .row = @intCast(row),
            .col = @intCast(col),
            .char = @intCast(char),
            .bg = @intCast(bg),
        });
    }

    // Add to display
    const display = getGlobalDisplay(context);
    const id = display.temp_overlays.add(TempOverlay{
        .cells = cells.items,
        .lifetime = .timed,
        .expiry_ms = now() + @intCast(lifetime_ms),
    });

    return c.hermes_number_to_value(runtime, @floatFromInt(id));
}
```

---

### 5.3 Long-Term (Phase 5+: Floating Windows)

**Goal:** Full Neovim-compatible floating window system

**Architecture:**

```zig
// Core layer manager (headless)
pub const LayerManager = struct {
    layers: std.ArrayList(Layer),
    next_id: LayerId,

    pub const Layer = struct {
        id: LayerId,
        zindex: i32,
        position: Rect,
        size: Size,
        content: LayerContent,
        config: LayerConfig,
    };

    pub const LayerContent = union(enum) {
        buffer: struct {
            buffer_id: BufferId,
            viewport: Viewport,  // Scroll offset, cursor
        },
        scratch: struct {
            lines: [][]const u8,  // Temporary text
        },
    };

    pub const LayerConfig = struct {
        blending: bool = false,
        blend_amount: u8 = 0,  // 0-255
        border: ?BorderStyle = null,
        focusable: bool = true,
        mouse_enabled: bool = true,
    };
};

// Display compositor (rendering)
pub const Compositor = struct {
    grid: ScreenGrid,
    layer_grids: std.AutoHashMap(LayerId, ScreenGrid),

    pub fn compose(self: *Compositor, layers: []const Layer) !void {
        // Clear base grid
        self.grid.clear();

        // Render layers bottom-up
        for (layers) |layer| {
            const layer_grid = self.layer_grids.get(layer.id).?;

            // Compose layer onto base grid
            self.compositeLayer(layer, layer_grid);
        }
    }

    fn compositeLayer(
        self: *Compositor,
        layer: Layer,
        layer_grid: ScreenGrid
    ) void {
        const pos = layer.position;

        for (0..layer.size.height) |row| {
            for (0..layer.size.width) |col| {
                const screen_row = pos.row + row;
                const screen_col = pos.col + col;

                if (screen_row >= self.grid.height or
                    screen_col >= self.grid.width) continue;

                var cell = layer_grid.getCell(row, col);

                // Blending
                if (layer.config.blending) {
                    const bg_cell = self.grid.getCell(screen_row, screen_col);
                    cell.bg = blendColors(
                        bg_cell.bg,
                        cell.bg,
                        layer.config.blend_amount
                    );

                    if (isTransparent(cell.char)) {
                        cell.char = bg_cell.char;
                        cell.fg = bg_cell.fg;
                    }
                }

                self.grid.setCell(screen_row, screen_col, cell);
            }
        }
    }
};
```

**JSI API:**

```javascript
// Create floating window
const float = editor.createFloatingWindow({
    width: 40,
    height: 10,
    row: 5,
    col: 10,
    zindex: 50,
    border: 'single',  // 'none', 'single', 'double', 'rounded'
    blending: true,
    blend: 30,  // 0-100%
});

// Load content
float.setBuffer(bufferId);
// or
float.setLines(['Line 1', 'Line 2', 'Line 3']);

// Show/hide
float.show();
float.hide();

// Move/resize
float.setPosition({ row: 10, col: 20 });
float.setSize({ width: 50, height: 15 });

// Destroy
float.close();
```

---

### 5.4 Implementation Phases

**Phase 3 (Current - Text Editing):**
- ✅ Trail overlay working (save/restore)
- ⏭️ Generalize to TempOverlayManager
- ⏭️ Add yank flash support
- ⏭️ Add search highlight flash

**Phase 4 (Plugin System):**
- ⏭️ Implement JSI layer API (create/remove temp overlays)
- ⏭️ Move trail logic to JS plugin (proof of concept)
- ⏭️ Document layer API for plugin developers

**Phase 5 (Advanced Features):**
- ⏭️ Implement LayerManager in core (headless)
- ⏭️ Implement Compositor in display
- ⏭️ Add floating window support
- ⏭️ JSI API for floating windows
- ⏭️ Border rendering
- ⏭️ Blending support

**Phase 6 (Performance):**
- ⏭️ Rectangle-based dirty tracking
- ⏭️ Adaptive threshold algorithm
- ⏭️ Benchmark compositor overhead
- ⏭️ Optimize hot paths

---

## 6. Key Takeaways

### 6.1 What Works Well

**Neovim's Compositor:**
- ✅ Z-indexed grid arrays scale to complex UIs
- ✅ Area-based composition minimizes redraws
- ✅ Blending support feels native
- ✅ Mouse hit testing respects visual order

**Helix's Simplicity:**
- ✅ Vec-based stack is easy to understand
- ✅ Component trait provides clean abstraction
- ✅ Event bubbling pattern is elegant
- ✅ Low complexity for simple cases

**Xi's Headless Design:**
- ✅ Core/UI separation enables multiple frontends
- ✅ Async plugins never block rendering
- ✅ Testable without UI

**OpenVim's Current Trail:**
- ✅ Save/restore pattern is perfect for temporary overlays
- ✅ Minimal overhead
- ✅ Already integrated into render pipeline

### 6.2 Pitfalls to Avoid

❌ **Don't mix logical and rendering layers** - Keep core headless
❌ **Don't over-engineer early** - Start simple (Helix), add complexity as needed (Neovim)
❌ **Don't forget mouse events** - Z-order must match visual order
❌ **Don't ignore blending** - Users expect transparency to work
❌ **Don't skip dirty tracking** - Full recompose is expensive at scale

### 6.3 Recommended Pattern for OpenVim

**Hybrid Neovim + Helix + Headless:**

1. **Core (headless):** Logical layer management (zindex, position, content)
2. **Display:** Neovim-style compositor (area composition, blending)
3. **API:** Helix-style simplicity (push/pop) + Neovim power (zindex, config)
4. **Optimization:** Start simple (per-layer dirty), add complexity when needed (rectangle tracking)

**Why this works:**
- Scales from simple overlays (trail) to complex UIs (floating windows)
- Keeps core testable and portable
- JSI API is intuitive for plugin developers
- Performance optimizations can be added incrementally

---

## 7. References

### Source Code Examined

- `/Users/le/projects/helix/helix-term/src/compositor.rs` - Helix component stack
- `/Users/le/projects/helix/docs/architecture.md` - Helix architecture overview
- `/Users/le/projects/neovim/src/nvim/ui_compositor.c` - Neovim compositor implementation
- `/Users/le/projects/neovim/src/nvim/ui_compositor.h` - Neovim compositor header
- `/Users/le/projects/neovim/src/nvim/grid_defs.h` - Neovim grid and Z-index definitions
- `/Users/le/projects/openvim/src/display/display.zig` - OpenVim current rendering
- `/Users/le/projects/openvim/src/display/trail.zig` - OpenVim trail overlay

### Web Resources

- Ratatui rendering documentation: https://ratatui.rs/concepts/rendering/
- Neovim UI compositor PR #31837: https://github.com/neovim/neovim/pull/31837
- Xi editor retrospective: https://raphlinus.github.io/xi/2020/06/27/xi-retrospective.html
- Vim popup window API (Issue #4063): https://github.com/vim/vim/issues/4063
- Helix architecture docs: https://github.com/helix-editor/helix/blob/master/docs/architecture.md

### Key Concepts

- **Immediate-mode rendering:** Redraw entire UI each frame (ratatui, Helix)
- **Retained-mode rendering:** Maintain scene graph, update only changes (not used in TUIs)
- **Painter's algorithm:** Draw back-to-front (simple Z-ordering)
- **Compositor:** System for combining multiple layers into final output
- **Dirty region:** Area of screen that needs redrawing
- **Z-index:** Explicit layer ordering (higher = on top)
- **Blending:** Simulating transparency via color interpolation

---

**Document Status:** Complete
**Next Steps:**
1. Implement TempOverlayManager (generalize trail pattern)
2. Design JSI layer API (Phase 4 preparation)
3. Prototype LayerManager in core (headless principle validation)

**Last Updated:** 2025-11-08
