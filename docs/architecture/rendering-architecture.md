# Rendering Architecture Analysis for Vimcraft

**Status**: Comprehensive Design Document  
**Date**: November 5, 2025  
**Purpose**: Design an efficient, scalable rendering architecture supporting Zig core and JavaScript plugins  
**Scope**: Terminal-based editor rendering with support for complex plugins like Telescope

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Vimcraft Rendering Implementation](#current-vimcraft-rendering-implementation)
3. [Reference Architecture Analysis](#reference-architecture-analysis)
4. [React-like Concepts for Terminal Rendering](#react-like-concepts-for-terminal-rendering)
5. [Plugin Requirements Analysis](#plugin-requirements-analysis)
6. [Proposed Multi-Layer Architecture](#proposed-multi-layer-architecture)
7. [Specific Implementation Strategies](#specific-implementation-strategies)
8. [Performance Considerations](#performance-considerations)
9. [Recommendations](#recommendations)

---

## Executive Summary

### Current State

Vimcraft currently implements a **grid-based rendering architecture** inspired by Neovim with optimizations from Helix:

- **Dual-buffer system**: Current and previous frame comparison
- **Damage tracking**: Line-level dirty bit tracking
- **Incremental updates**: Only changed cells transmitted to terminal
- **Attribute caching**: Minimizes ANSI escape code generation
- **Wide character support**: Proper emoji/CJK rendering via Ghostty's uucode

This works well for single-buffer editing but faces challenges for:
- Floating windows (overlapping content)
- Real-time filtering (Telescope-like preview updates)
- Multiple windows with independent scrolling
- Plugin-driven rendering (JavaScript updating UI elements)
- Complex layouts (splits, nested windows)

### Vision

A **hierarchical, component-based rendering system** that:

1. **Separates content from presentation**: Plugins declare what to show, not how to render
2. **Enables efficient composition**: Windows, splits, and floats compose cleanly
3. **Maintains performance**: <16ms render time even with complex layouts
4. **Supports partial updates**: Only rerender changed subtrees
5. **Bridges Zig and JavaScript**: Clear API boundary for plugin rendering

---

## Current Vimcraft Rendering Implementation

### Architecture Overview (Current Implementation)

```
┌─────────────────────────────────────────────┐
│ main.zig / backend.zig - Event Loop         │
│ (Input handling + render triggers)          │
└────────────────┬────────────────────────────┘
                 │
                 ├──→ Buffer modifications
                 ├──→ Mode changes / viewport commands (zz, zt, zb)
                 ├──→ Configuration updates
                 └──→ Plugin events (extmarks, signs)
                 │
┌────────────────▼────────────────────────────┐
│ display.zig - Display Manager               │
│ (Orchestrates layer-based rendering)        │
├─────────────────────────────────────────────┤
│ 1. ViewportState.fromWindow() (snapshot)    │
│ 2. layer_renderer.updateLayers()            │
│ 3. compositor.composite(layers)             │
│ 4. output_renderer.renderUpdates()          │
│ 5. terminal flush                           │
└────────────────┬────────────────────────────┘
                 │
    ┌────────────┼────────────┬───────────────┐
    │            │            │               │
┌───▼────┐  ┌────▼─────┐  ┌───▼────┐   ┌─────▼─────┐
│ Layers │  │Compositor│  │ Screen │   │ Window    │
│        │  │          │  │ Grid   │   │ Renderer  │
│ BASE   │  │ blend()  │  │        │   │           │
│ GUTTER │  │ z-order  │  │current │   │ gutter    │
│ CURSOR │  │ opacity  │  │previous│   │ content   │
│ SEARCH │  └──────────┘  │ dirty  │   │ signs     │
│ FLOAT  │                └────────┘   └───────────┘
└────────┘                    │
                              │
┌─────────────────────────────▼───────────────┐
│ Terminal Output (ANSI Escape Codes)         │
│ (Synchronized updates, cursor tracking)     │
└─────────────────────────────────────────────┘
```

### Core Components

#### 1. **ScreenGrid** (`screen_grid.zig`)
- **2D array of Cells**: Current[height][width], Previous[height][width]
- **Cell structure**: 
  ```zig
  struct Cell {
    char: u21,                    // Base character
    fg, bg: ?Color,              // Foreground/background
    bold, italic, underline: bool // Attributes
    combining: [2]u21,           // Zero-width chars
    is_continuation: bool        // Part of wide char
  }
  ```
- **Dirty tracking**: `DynamicBitSet` per line
- **Diff algorithm**: Compare current vs previous, return changed cells

#### 2. **Display** (`display.zig`)
- **Main rendering orchestrator**
- **Viewport management**: Tracks visible region
- **Horizontal scrolling**: Per-line with wide character support
- **Grid population**: `updateGridFromBuffer()` (384 lines)
- **Change detection**: `diff()` algorithm
- **Terminal output**: `renderUpdates()` with ANSI optimization
- **Gutter integration**: Line numbers, sign column

#### 3. **Gutter System** (`gutter.zig`)
- **Modular columns**: Pluggable renderer system
- **Modes**: Absolute, relative, hybrid line numbers
- **Width calculation**: Dynamic based on line count
- **Cache invalidation**: Based on line count changes
- **Integration**: Transparent to main rendering

#### 4. **Character Width** (`char_width.zig`)
- **Unicode property queries**: Via Ghostty's uucode
- **Width classification**: 0 (zero-width), 1 (normal), 2 (wide)
- **Byte↔display conversion**: Critical for cursor positioning
- **Edge cases**: Variation selectors, combining marks, emoji

### Rendering Pipeline (5 Steps)

```
Step 1: adjustViewport()
├─ Ensures cursor is visible
├─ Scrolls vertically as needed
└─ Updates viewport_top, viewport_left

Step 2: updateGridFromBuffer()
├─ Walk visible lines (viewport_top to viewport_top+terminal_rows)
├─ For each line:
│  ├─ Render gutter (line numbers, signs)
│  ├─ Render text content with colors
│  ├─ Apply visual selection highlighting
│  ├─ Apply yank flash highlighting
│  └─ Pad to terminal width
├─ Render status line
└─ Write to grid.current[row][col]

Step 3: diff()
├─ Iterate dirty_lines bitset
├─ Compare current[row][col] vs previous[row][col]
├─ Build Update list for changed cells
└─ Return updates: Vec<{row, col, cell}>

Step 4: renderUpdates()
├─ Initialize: track current fg, bg, bold, italic, underline
├─ For each Update in order:
│  ├─ Skip continuation cells (auto-extended by terminal)
│  ├─ Optimize cursor movement (adjacent detection)
│  ├─ Only output color changes
│  ├─ Only output attribute changes
│  ├─ Write cell character + combining chars
│  └─ Track last_pos for adjacent optimization
├─ Reset all attributes
└─ Single flush to stdout

Step 5: swapBuffers()
├─ Copy current→previous
├─ Clear dirty_lines bitset
└─ Ready for next frame
```

### Performance Characteristics

| Aspect | Current | Target | Notes |
|--------|---------|--------|-------|
| **Full redraw** | ~2ms | <5ms | 80x24 grid |
| **Incremental** | <1ms | <1ms | Few cell changes |
| **Diff time** | <0.5ms | <0.5ms | Bitset iteration |
| **Terminal I/O** | ~0.5ms | <1ms | Depends on escape codes |
| **Total frame** | ~2-3ms | <5ms | <16ms for 60fps |

### Current Implementation (December 2025)

The proposed multi-layer architecture has been **fully implemented**:

1. **Layer system** (`layer.zig`): Z-ordered layers with opacity
2. **Compositor** (`compositor.zig`): Porter-Duff alpha blending
3. **Layer renderer** (`layer_renderer.zig`): Entry point for layer-based rendering
4. **Sign renderer** (`sign_renderer.zig`): Gitsigns/extmark sign rendering
5. **ViewportState**: Immutable viewport snapshots for renderers
6. **HighlightRegistry**: Unified highlight system (Neovim/Helix pattern)
7. **Floating windows**: Full z-order support for popups/menus
8. **Horizontal scroll**: Per-window viewport with cursor tracking

#### Layer Z-Index Order (Implemented)

```zig
pub const ZIndex = struct {
    pub const BASE: i32 = 0;           // Buffer content
    pub const GUTTER: i32 = 100;       // Line numbers, signs, folds
    pub const CURSOR: i32 = 200;       // Text cursor
    pub const VIRTUAL_TEXT: i32 = 300; // Inline diagnostics, hints
    pub const SELECTION: i32 = 400;    // Visual mode selection
    pub const YANK: i32 = 450;         // Yank flash highlights
    pub const SEARCH: i32 = 500;       // Search highlights
    pub const FLOAT: i32 = 600;        // Floating windows (LSP popups)
    pub const CMDLINE: i32 = 700;      // Command line
    pub const MESSAGE: i32 = 800;      // Error/info messages
    pub const MODAL: i32 = 900;        // Modal overlays/dialogs
};
```

#### Current Components

| Component | File | Purpose |
|-----------|------|---------|
| **Layer** | `layer.zig` | Layer abstraction with z-index, opacity, dirty tracking |
| **Compositor** | `compositor.zig` | Blends layers into output grid |
| **LayerRenderer** | `layer_renderer.zig` | Updates layers from buffer state |
| **SignRenderer** | `sign_renderer.zig` | Decodes UTF-8 signs for gutter |
| **WindowRenderer** | `window_renderer.zig` | Per-window content rendering |
| **VirtualText** | `virtual_text.zig` | Inline extmarks/diagnostics |
| **DirtyRect** | `dirty_rect.zig` | Rectangular damage tracking |
| **ViewportState** | `display.zig` | Immutable viewport snapshot |

### Remaining Limitations

1. **Tab pages**: Not yet implemented
2. **Scroll regions**: Could optimize large scrolls
3. **Syntax highlight caching**: Per-window cache exists but could be improved

---

## Reference Architecture Analysis

### Neovim Rendering Model

**Key insight**: Neovim separates the "grid protocol" (UI communication) from internal rendering.

```
┌──────────────────────────────────┐
│ Neovim Core (C)                  │
│ ├─ Editor state (buffer, cursor) │
│ ├─ Grid generation               │
│ └─ Event system                  │
└────────────┬──────────────────────┘
             │ (RPC: msgpack events)
             │
┌────────────▼──────────────────────┐
│ UI Clients (Protocol)             │
│ ├─ Desktop (Qt) UI                │
│ ├─ Web UI                         │
│ └─ Terminal UI (nvim-tui)         │
└───────────────────────────────────┘
```

**Grid Protocol features**:
- Multiple independent grids (main, float, statusline)
- Grid cells with attributes as references to a color palette
- Damage regions instead of per-cell updates
- Compositing with z-order
- Window decorations (titles, borders)

**Limitations for plugins**:
- Plugins render via `:highlight` and `:sign`
- Limited to pre-defined areas (gutter, decorations)
- No real-time plugin rendering to arbitrary regions
- Floating windows only in UI layer, not plugin-accessible

### Helix Rendering Optimization

**Key insights**:
- Adjacent cell skipping reduces escape codes
- Attribute caching (no redundant codes)
- Line-level dirty tracking is sufficient
- Single flush is faster than per-cell I/O

```rust
// Pseudocode from Helix
for (row, cells) in dirty_cells {
    if !is_adjacent(last_pos, current_pos) {
        output.push(format!("\x1b[{};{}H", row, col));
    }
    if color_changed(current_fg, new_fg) {
        output.push(ansi_code(new_fg));
        current_fg = new_fg;
    }
    output.push(cell.char);
    last_pos = (row, col);
}
output.flush();  // Single write
```

### Ghostty Terminal Rendering

**Key insights**:
- Cell-based grid with attributes
- Unicode property support (width, combining)
- Damage tracking at grid level
- Efficient terminal protocol (SGR codes)
- No full redraws except on resize

### React Model (for inspiration)

While React works on a virtual DOM, some principles apply:

```
Render Phase:          Commit Phase:           Effect Phase:
─────────────         ──────────────          ─────────────
render()         →    apply_diff()       →    terminal_output()
├─ Input events       ├─ Update grid       ├─ ANSI codes
├─ State              ├─ Invalidate cache  ├─ Flush to TTY
└─ Props              └─ Schedule effects  └─ Update cursor
```

**Applicable patterns**:
- Reconciliation (diffing) for efficient updates
- Component trees for composition
- Props/state separation
- Memoization of expensive calculations
- Batched updates

---

## React-like Concepts for Terminal Rendering

### 1. Virtual Terminal Grid

Instead of rendering directly to a physical grid, render to a **virtual grid** that can be reconciled:

```zig
pub const VirtualGrid = struct {
    cells: [][]Cell,
    layers: []Layer,  // Support z-order
    damage: DamageRegion,  // Rectangular regions instead of per-cell
    components: []Component,  // Component tree
};

pub const Layer = struct {
    id: u32,
    z_order: i32,
    cells: [][]Cell,  // Sparse grid (only changed cells)
    bounds: Rectangle,
};
```

**Benefits**:
- Compose grids from multiple sources
- Support overlapping content (floats)
- Clear z-order semantics
- Partial updates per layer
- Component-based organization

### 2. Component Model

Define rendering as composable components:

```typescript
// JavaScript side (plugin authors)
type Component = {
  render(props: Props): Element;
  width?: number;
  height?: number;
};

interface Element {
  type: "grid" | "text" | "border";
  props: Props;
  children?: Element[];
}

// Example: Telescope preview
const TelescopePreview: Component = {
  render({ results, selected, preview_text }) {
    return {
      type: "grid",
      props: { width: 80, height: 24 },
      children: [
        { type: "text", props: { text: "results", x: 0, y: 0 } },
        { type: "border", props: { style: "rounded" } },
        { type: "text", props: { text: preview_text, x: 2, y: 2 } },
      ],
    };
  },
};
```

**Benefits**:
- Declarative rendering
- Reusable components
- Clear props/state separation
- Easier testing
- Better plugin isolation

### 3. Dirty Checking

Track state changes at multiple granularities:

```zig
pub const DirtyLevel = enum {
    clean,          // No changes
    attributes,     // Only colors/style changed
    layout,         // Size/position changed
    content,        // Text changed
    structure,      // Children changed
};

pub const Component = struct {
    id: u32,
    dirty: DirtyLevel = .clean,
    rendered: ?VirtualGrid = null,
    
    pub fn shouldRender(self: Component) bool {
        return self.dirty != .clean;
    }
    
    pub fn markDirty(self: *Component, level: DirtyLevel) void {
        if (@intFromEnum(level) > @intFromEnum(self.dirty)) {
            self.dirty = level;
        }
    }
};
```

**Benefits**:
- Skip rendering if only structure changed
- Avoid re-rendering unaffected subtrees
- Support memoization/caching
- Efficient partial updates

### 4. Render Batching

Collect updates and apply atomically:

```zig
pub const RenderBatch = struct {
    updates: ArrayList(Update),
    component_updates: ArrayList(ComponentUpdate),
    cursor_pos: Position,
    timestamp: i64,
    
    pub fn flush(self: *RenderBatch, display: *Display) !void {
        // Apply all updates at once
        display.applyBatch(self);
    }
};

// In event loop:
var batch = try RenderBatch.init(allocator);
defer batch.deinit();

// Queue all updates
try batch.queue(update1);
try batch.queue(update2);
try batch.queue(update3);

// Single flush
try batch.flush(display);
```

**Benefits**:
- Atomic updates (no tearing)
- Reduced redraw cycles
- Better cache locality
- Easier debugging

### 5. Declarative API for Plugins

Instead of direct grid manipulation:

```javascript
// Current (imperative): plugins must manage grids
vim.api.nvim_buf_set_text(buf, line, col, line, col+1, ["new text"]);

// Proposed (declarative): plugins declare what to show
vim.render.float({
  id: "telescope",
  title: "Find Files",
  width: 80,
  height: 24,
  content: {
    type: "list",
    items: results,
    selected: selectedIndex,
    render: (item) => item.filename,
  },
  preview: {
    type: "text",
    content: previewText,
    syntax: "javascript",
  },
});
```

**Benefits**:
- Plugins don't think about grids
- Vimcraft handles layout and rendering
- Consistent UI across plugins
- Easier to add features (syntax highlighting, etc.)

---

## Plugin Requirements Analysis

### Telescope (Reference Complex Plugin)

Telescope needs:

1. **Main picker window**: 
   - List of items (files, grep results, etc.)
   - Real-time filtering
   - Cursor position tracking
   - Keyboard navigation

2. **Preview pane** (optional):
   - File preview (syntax highlighted)
   - Or search context
   - Real-time updates as user navigates

3. **Floating window**:
   - Centered or positioned
   - Z-order above main editor
   - Borders and title
   - Scrollable content

4. **Status line**:
   - Item count
   - Search term
   - Current/total position

### Rendering Requirements

| Feature | Challenge | Solution |
|---------|-----------|----------|
| **Floating window** | Overlaps main buffer | Multi-layer grid with z-order |
| **Real-time filtering** | Need to rerender list while user types | Efficient diff per region |
| **Preview pane** | Shows different file as user navigates | Decoupled rendering per pane |
| **Syntax highlight** | Not in current renderer | Extend highlight groups system |
| **Responsive** | Large file lists (~10K items) | Virtual scrolling, lazy rendering |
| **Borders/decorations** | Not part of grid | Separate decoration layer |
| **Mouse support** | Click to select | Region-based hit detection |

### API Needs

```typescript
// Floating window creation
vim.api.nvim_open_win(buffer, enter, {
  relative: "editor",
  row: 10,
  col: 20,
  width: 80,
  height: 24,
  zindex: 50,
  border: "rounded",
  title: "Find Files",
});

// Rendering to specific window
vim.api.nvim_win_set_lines(win, {
  lines: ["file1.txt", "file2.txt", ...],
  highlights: [
    { line: 0, col: 0, end_col: 8, hl_group: "TelescopeMatched" },
  ],
});

// Real-time updates (efficient incremental)
vim.api.nvim_win_patch_lines(win, {
  start_line: 5,
  updates: [
    { line: 5, content: "filtered_file_1.txt", highlights: [...] },
  ],
});
```

---

## Implemented Multi-Layer Architecture

> **Status**: Fully implemented as of December 2025. See `src/backends/terminal/display/` for implementation.

### Layer 1: Core Grid System (Zig)

**Responsibility**: Manage terminal cell grid and ANSI output

```zig
pub const TerminalGrid = struct {
    // Physical terminal grid
    cells: [][]Cell,
    width: usize,
    height: usize,
    
    // Dirty region tracking (rectangles instead of per-cell)
    damaged_regions: ArrayList(Rectangle),
    
    // Palette for highlight groups
    highlights: HashMap([]const u8, Highlight),
    
    // Methods
    pub fn setCell(row, col, cell: Cell) void;
    pub fn getCell(row, col) ?Cell;
    pub fn markRegionDirty(rect: Rectangle) void;
    pub fn diff() ![]Update;
    pub fn renderAnsi() ![]const u8;
};
```

**Implementation approach**:
- Keep current ScreenGrid as foundation
- Add damage region tracking
- Enhance diff to work with regions
- Add highlight group system
- Improve ANSI generation

### Layer 2: Window Manager (Zig)

**Responsibility**: Manage window tree, layouts, and composition

```zig
pub const WindowTree = struct {
    pub const Window = struct {
        id: u32,
        parent: ?*Window,
        children: ArrayList(*Window),
        bounds: Rectangle,
        buffer: *Buffer,
        
        grid: VirtualGrid,  // What this window renders
        dirty: DirtyLevel,
        
        pub fn render(self: *Window) !VirtualGrid;
        pub fn resize(self: *Window, width, height) !void;
    };
    
    pub const Layout = enum {
        vsplit,   // |
        hsplit,   // -
        float,    // Floating
        tab,      // Tab page
    };
    
    root: *Window,
    layout_root: Layout,
    
    pub fn splitWindow(window: *Window, layout: Layout) !*Window;
    pub fn closeWindow(window: *Window) !void;
    pub fn focusWindow(window: *Window) void;
    pub fn reconcile() !void;  // Recompute all layouts
};
```

**Key features**:
- Tree of windows with layout information
- Bounds calculation (recursive layout engine)
- Support splits, floats, tabs
- Dirty tracking per window
- Partial reconciliation

### Layer 3: Rendering Engine (Zig/JavaScript bridge)

**Responsibility**: Combine windows into output, coordinate updates

```zig
pub const RenderEngine = struct {
    window_tree: *WindowTree,
    terminal_grid: *TerminalGrid,
    
    // Caching
    last_frame: VirtualGrid,
    layer_cache: HashMap(u32, LayerCache),
    
    pub fn render(self: *RenderEngine) !void {
        // 1. Reconcile window tree if dirty
        try self.window_tree.reconcile();
        
        // 2. Render each window to its virtual grid
        try self.renderWindows();
        
        // 3. Composite windows with z-order
        try self.composite();
        
        // 4. Diff and output
        const updates = try self.terminal_grid.diff();
        try self.outputAnsi(updates);
    }
    
    fn renderWindows(self: *RenderEngine) !void {
        // Depth-first traversal, render dirty windows
        try self.renderWindowRecursive(self.window_tree.root);
    }
    
    fn composite(self: *RenderEngine) !void {
        // Merge all window grids into terminal grid with z-order
        // Handle floating windows last (highest z-order)
    }
};
```

**Algorithm**: Depth-first rendering with dirty checking

```
render(window):
  if !window.dirty:
    return cached_grid
  
  if window.is_leaf():
    grid = render_buffer(window.buffer, window.bounds)
  else:
    for child in window.children:
      child_grid = render(child)
      composite(grid, child_grid, child.bounds)
  
  cache[window.id] = grid
  return grid
```

### Layer 4: Plugin API (JavaScript)

**Responsibility**: Expose rendering to plugins

```typescript
// vim.render namespace
namespace vim.render {
  // Float window
  function createFloat(config: FloatConfig): FloatWindow;
  function closeFloat(win_id: number): void;
  
  // Content rendering
  interface FloatWindow {
    setContent(content: RenderableContent): Promise<void>;
    setLines(lines: string[]): Promise<void>;
    setHighlights(hl: HighlightRange[]): Promise<void>;
    scroll(offset: number): void;
    close(): void;
  }
  
  type RenderableContent = 
    | { type: "text"; content: string }
    | { type: "lines"; lines: string[] }
    | { type: "buffer"; buffer: number }
    | { type: "component"; component: Component };
  
  // Components
  interface Component {
    render(): RenderableContent;
    width: number;
    height: number;
  }
}

// Example usage
const float = vim.render.createFloat({
  relative: "editor",
  width: 80,
  height: 20,
  title: "Results",
});

await float.setLines(results.map(r => r.filename));
float.setHighlights([
  { line: 0, col: 0, end_col: 8, group: "TelescopeMatched" },
]);
```

---

## Specific Implementation Strategies

### 1. Damage Tracking Evolution

**Current**: Per-line dirty bitset  
**Enhanced**: Rectangular damage regions

```zig
pub const DamageRegion = struct {
    min_row: usize,
    max_row: usize,
    min_col: usize,
    max_col: usize,
    
    pub fn contains(self: DamageRegion, row: usize, col: usize) bool {
        return row >= self.min_row and row <= self.max_row and
               col >= self.min_col and col <= self.max_col;
    }
    
    pub fn union(self: *DamageRegion, other: DamageRegion) void {
        self.min_row = @min(self.min_row, other.min_row);
        self.max_row = @max(self.max_row, other.max_row);
        self.min_col = @min(self.min_col, other.min_col);
        self.max_col = @max(self.max_col, other.max_col);
    }
};

// Usage
var damage = DamageRegion.empty();

// Window moved
damage.union(old_window_bounds);
damage.union(new_window_bounds);

// Only check cells in damage region
for (damage.min_row..damage.max_row) |row| {
    for (damage.min_col..damage.max_col) |col| {
        if (hasChanged(row, col)) {
            try updates.append(Update{...});
        }
    }
}
```

**Benefits**:
- More efficient than per-cell or per-line tracking
- Handles floating windows well
- Reduces unnecessary diff work
- Scales with damage size, not grid size

### 2. Render Batching Strategy

**Current**: Single render() call per frame  
**Enhanced**: Batch multiple updates before rendering

```zig
pub const RenderBatch = struct {
    changes: ArrayList(Change),
    needs_reconcile: bool = false,
    needs_relayout: bool = false,
    
    pub fn addChange(self: *RenderBatch, change: Change) !void {
        try self.changes.append(change);
        
        // Mark what needs recomputation
        switch (change.kind) {
            .buffer_modified => {},  // Render affected window
            .window_resized => self.needs_relayout = true,
            .window_created => self.needs_reconcile = true,
            .highlight_changed => {},
            .mode_changed => {},
        }
    }
    
    pub fn flush(self: *RenderBatch, engine: *RenderEngine) !void {
        if (self.needs_reconcile) {
            try engine.window_tree.reconcile();
        }
        if (self.needs_relayout) {
            try engine.relayoutWindows();
        }
        
        // Render all affected windows
        try engine.renderDirtyWindows();
        
        // Single composite + output
        try engine.composite();
        try engine.outputAnsi();
        
        self.changes.clearRetainingCapacity();
        self.needs_reconcile = false;
        self.needs_relayout = false;
    }
};

// In event loop
var batch = try RenderBatch.init(allocator);
defer batch.deinit();

// Queue all changes from this frame
for (input_events) |event| {
    try handleEvent(event, buffer, &batch);
}

// Single render call
try batch.flush(engine);
```

**Benefits**:
- Atomic frame updates
- Avoid multiple reconciliations
- Better cache locality
- Clearer semantics

### 3. Plugin Rendering Isolation

**Problem**: Plugins rendering directly to grid can corrupt state  
**Solution**: Separate plugin-rendered regions

```zig
pub const WindowContent = struct {
    // Core buffer rendering
    buffer_grid: VirtualGrid,
    
    // Plugin overlays
    decorations: ArrayList(Decoration),  // Inline decorations
    inline_highlights: ArrayList(HighlightRange),
    
    // Floating content (plugins)
    floats: ArrayList(*FloatingWindow),
    
    pub fn composite(self: *WindowContent) !VirtualGrid {
        var result = self.buffer_grid;
        
        // Apply inline highlights
        for (self.inline_highlights.items) |hl| {
            try applyHighlight(&result, hl);
        }
        
        // Apply decorations
        for (self.decorations.items) |dec| {
            try applyDecoration(&result, dec);
        }
        
        // Render floats on top
        for (self.floats.items) |float| {
            try compositeFloat(&result, float);
        }
        
        return result;
    }
};

// Plugins can't directly access buffer_grid
pub const PluginAPI = struct {
    pub fn setInlineHighlight(
        win_id: u32,
        range: HighlightRange,
    ) !void {
        const window = windows.get(win_id) orelse return;
        try window.content.inline_highlights.append(range);
        window.markDirty(.attributes);
    }
    
    pub fn createFloat(config: FloatConfig) !FloatingWindowHandle {
        const float = try FloatingWindow.create(allocator, config);
        try window.content.floats.append(float);
        window.markDirty(.structure);
        return float.id;
    }
};
```

**Benefits**:
- Plugins can't corrupt core state
- Clear API boundaries
- Compositing is deterministic
- Easy to debug plugin rendering issues

### 4. Virtual Scrolling for Large Lists

For Telescope with 10K+ items:

```typescript
interface VirtualList {
  total_items: number;
  visible_height: number;
  item_height: number;
  scroll_offset: number;
  
  render(): string[] {
    const start = Math.floor(this.scroll_offset / this.item_height);
    const end = start + this.visible_height;
    
    const result = [];
    for (let i = start; i < end; i++) {
      result.push(this.getItem(i));
    }
    return result;
  }
}
```

**Benefits**:
- O(viewport) rendering instead of O(items)
- Responsive even with large datasets
- Smooth scrolling
- Memory efficient

### 5. Syntax Highlighting for Plugins

Extend highlight groups to plugins:

```zig
pub const HighlightRegistry = struct {
    groups: HashMap([]const u8, Highlight),
    
    pub fn registerGroup(self: *HighlightRegistry, name: []const u8, hl: Highlight) !void {
        try self.groups.put(name, hl);
    }
    
    pub fn getGroup(self: *HighlightRegistry, name: []const u8) ?Highlight {
        return self.groups.get(name);
    }
    
    // Vim-standard groups
    pub fn initDefaults(self: *HighlightRegistry) !void {
        try self.registerGroup("Normal", defaultNormal);
        try self.registerGroup("Visual", defaultVisual);
        try self.registerGroup("TelescopeMatched", telescopeMatched);
        try self.registerGroup("TelescopeSelection", telescopeSelection);
    }
};

// In rendering
for (matches) |match| {
    const hl = highlight_registry.getGroup("TelescopeMatched") 
        orelse defaultHighlight;
    
    cells[row][col].fg = hl.fg;
    cells[row][col].bg = hl.bg;
    cells[row][col].bold = hl.bold;
}
```

---

## Performance Considerations

### Target Performance

- **60 FPS minimum**: 16.6ms per frame budget
- **Display update**: <5ms (most time for input processing)
- **Diff operation**: <1ms
- **ANSI generation**: <1ms
- **Terminal I/O**: <2ms

### Optimization Techniques

1. **Caching**
   - Cache cell computations per window
   - Invalidate on dirty marks only
   - LRU cache for frequently rendered windows

2. **Lazy evaluation**
   - Don't render off-screen content
   - Virtual scrolling for large lists
   - Component memoization

3. **Batching**
   - Coalesce multiple updates
   - Single terminal write per frame
   - Group ANSI codes

4. **Data structure selection**
   - BitSet for dirty tracking (cache-efficient)
   - HashMap for highlight groups (name lookups)
   - ArrayList for sparse updates

5. **Algorithmic improvements**
   - O(dirty_area) instead of O(grid)
   - Rectangular damage vs per-cell
   - Depth-first tree traversal (cache locality)

### Benchmarking Strategy

```zig
pub const Benchmark = struct {
    name: []const u8,
    start_ns: i64,
    end_ns: i64,
    
    pub fn begin(name: []const u8) Benchmark {
        return .{
            .name = name,
            .start_ns = std.time.nanoTimestamp(),
            .end_ns = 0,
        };
    }
    
    pub fn end(self: *Benchmark) void {
        self.end_ns = std.time.nanoTimestamp();
    }
    
    pub fn elapsed_ms(self: Benchmark) f64 {
        return @as(f64, @floatFromInt(self.end_ns - self.start_ns)) / 1_000_000.0;
    }
};

// Usage
var bench = Benchmark.begin("render");
try display.render(buffer, status, config, visual_state, yank_highlight);
bench.end();
debug_log.log("Render took {d:.2}ms", .{bench.elapsed_ms()});
```

### Profile-guided optimization

1. Log all major operations with timing
2. Identify bottlenecks (diff, rendering, I/O)
3. Optimize hot paths
4. Measure improvements

---

## Implementation Status

### Phase 1: Foundation ✅ Complete
**Goal**: Enhance current grid system without breaking changes

1. ✅ **Damage region tracking** - `dirty_rect.zig`
2. ✅ **Highlight system** - `HighlightRegistry` in `highlight_api.zig`
3. ✅ **Diff algorithm** - Rectangle-based in compositor
4. ✅ **Render batching** - Single flush per frame

### Phase 2: Window Manager ✅ Complete
**Goal**: Support splits and floating windows

1. ✅ **Window tree** - `window.zig`, `window_layout.zig`
2. ✅ **Split operations** - vsplit/hsplit implemented
3. ✅ **Floating windows** - Z-order via `layer.zig` ZIndex
4. ✅ **Layer rendering** - `compositor.zig` with alpha blending

### Phase 3: Plugin API ✅ Complete
**Goal**: Enable plugin rendering safely

1. ✅ **Declarative API** - `vim.api.openWin()`, `vim.api.bufSetExtmark()`
2. ✅ **Safeguards** - Namespace isolation for extmarks
3. ✅ **Plugin examples** - git-bundle (gitsigns), LSP popups
4. ✅ **Performance** - <5ms render with floating windows

### Phase 4: Advanced Features ✅ Mostly Complete
**Goal**: Full feature parity with mature editors

1. ✅ **Syntax highlighting** - Tree-sitter with `HighlightCache`
2. ✅ **Search highlighting** - Search layer with match highlights
3. ✅ **Completion menus** - Floating window support
4. ✅ **Diagnostics display** - Virtual text extmarks

### Remaining Work

| Feature | Status | Notes |
|---------|--------|-------|
| Tab pages | 📅 Planned | Window layout extension |
| Scroll regions | 📅 Planned | Terminal optimization |
| Mouse support | 📅 Planned | Region-based hit detection |

### Key Principles

1. **Incremental changes**: No breaking rewrites, evolve gradually
2. **Performance first**: Benchmark before and after optimizations
3. **Plugin-friendly**: APIs enable third-party rendering
4. **Vim-compatible**: Maintain Neovim feature parity
5. **Clean boundaries**: Clear separation of Zig and JavaScript concerns

---

## Comparison with Neovim

| Aspect | Neovim | Vimcraft (Proposed) |
|--------|--------|-------------------|
| **Grid model** | Multiple grids (msgpack) | Single virtual grid with layers |
| **Plugin rendering** | Limited (signs, decorations) | Declarative API, full floats |
| **Performance** | Good (~2ms) | Excellent (<5ms target) |
| **Plugin safety** | Limited isolation | Clear API boundaries |
| **Type support** | Lua (dynamic) | JavaScript/TypeScript (static) |
| **Hot reload** | Plugin-based | Built-in, atomic updates |
| **Complexity** | ~100K lines C | ~10K lines Zig + JS API |

---

## Document Organization

This analysis should be split into multiple documents for clarity:

```
docs/architecture/
├── rendering-architecture.md (THIS DOCUMENT)
├── grid-system-design.md (Layer 1 details)
├── window-manager.md (Layer 2 details)
├── render-engine.md (Layer 3 details)
├── plugin-rendering-api.md (Layer 4 details)
├── performance-guide.md (Optimization techniques)
└── rendering-roadmap.md (Implementation phases)
```

---

## Conclusion

Vimcraft has a solid rendering foundation with grid-based rendering and incremental updates. The proposed multi-layer architecture builds on this strength by:

1. **Extending** damage tracking for complex layouts
2. **Composing** windows with clear z-order
3. **Isolating** plugin rendering safely
4. **Exposing** declarative APIs for plugins
5. **Maintaining** performance across all features

The path forward is incremental: enhance the current system, add window management, then expose plugin APIs. This allows continuous improvement while maintaining stability.

Key success metrics:
- <5ms render time with complex layouts
- Support for Telescope-like plugins
- Sublinear performance scaling with content
- Type-safe plugin APIs
- Zero data corruption from plugin rendering

This architecture positions Vimcraft to be a modern, maintainable alternative to Neovim while leveraging Zig's performance and JavaScript's accessibility for plugins.

---

## ViewportState Refactor (December 2025)

### Problem: Viewport State Coordination Bug

When using mappings like `H -> Hzz` (move to top of viewport, then center), rapid `j` key presses caused the cursor to flash/jump between the centered position and the viewport edge.

**Root Cause**:
1. `backend.zig` executes `zz` and sets `Window.viewport.top_line`
2. `display.zig` calls `ensureCursorVisible()` which overwrites the viewport position
3. No coordination mechanism between viewport adjustment and ensure-visible logic

### Solution: ViewportState Abstraction

Introduced `ViewportState` struct - an immutable snapshot passed to renderers:

```zig
pub const ViewportState = struct {
    top: usize,      // First visible line
    left: usize,     // Horizontal scroll
    height: usize,   // Visible rows
    width: usize,    // Visible columns

    pub fn fromWindow(win: *const Window, ...) ViewportState;
    pub fn fromDisplay(display: *const Display) ViewportState;
};
```

### Architecture Changes

| Before | After |
|--------|-------|
| Renderers read `Display.viewport_top` | Renderers receive `ViewportState` as parameter |
| Multiple sources of truth (Display, Window) | Single source: `Window.viewport.top_line` |
| Implicit data flow | Explicit parameter passing |
| Hard to test renderers | Can pass mock ViewportState |

### Data Flow

```
Window.viewport.top_line (canonical source)
        │
        ▼
ViewportState.fromWindow()
        │
        ├──→ layer_renderer.updateLayers(viewport, ...)
        ├──→ window_renderer.renderWindow(viewport, ...)
        └──→ cursor positioning
```

### Skip Flag for Viewport Adjustments

The `skip_ensure_cursor_visible` flag prevents `ensureCursorVisible` from overriding explicit viewport positioning:

```zig
// After zz/zt/zb execution
editor.skip_ensure_cursor_visible = true;

// In render
if (!editor.skip_ensure_cursor_visible) {
    win.ensureCursorVisibleWithHeight(...);
}

// After render (one-shot flag)
editor.skip_ensure_cursor_visible = false;
```

### Performance

This refactor is **zero-cost** (marginally faster):

| Access Pattern | Cost |
|---------------|------|
| `self.viewport_top` (field access) | 1 memory load |
| `viewport: ViewportState` (parameter) | 0 memory loads (register) |

Benchmark results (29 perf-critical tests):
- Single frame: 1ms
- 50j: 3ms (0.06ms/move)
- All tests: PASS

### Benefits

1. **Single Source of Truth**: Window.viewport is canonical
2. **Explicit Data Flow**: Renderers declare their inputs
3. **Testable**: Can unit test renderers with mock ViewportState
4. **Debuggable**: Easy to trace where viewport comes from
5. **No Performance Cost**: Actually marginally faster

### Related Bug Fixes (December 2025)

#### Cursor-Gutter Boundary Fix
- **Bug**: `renderCursorOnly()` used `gutter_manager.getTotalWidth()` instead of window-specific gutter width
- **Symptom**: Cursor rendered inside gutter area when line numbers enabled
- **Fix**: Use `window_renderer.calculateWindowGutterWidth()` for window-specific calculation
- **Test**: `tests/e2e/cursor-gutter-boundary/e2e.ts`

#### Horizontal Scroll Fix
- **Bug**: `viewport_scroll_needed` only checked vertical bounds, not horizontal
- **Symptom**: Moving `l` on long lines didn't scroll buffer horizontally
- **Fix**: Added horizontal scroll detection in `backend.zig` viewport check
- **Test**: `tests/e2e/horizontal-scroll/e2e.ts`

