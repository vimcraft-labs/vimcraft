# Vimcraft JavaScript API Reference

**Version**: 0.4.0 (January 2025)
**Architecture**: HostObject-based (zero-copy JSI)
**Compatibility**: Neovim-compatible subset

This document provides comprehensive API reference for all JavaScript APIs exposed by Vimcraft's plugin system.

---

## Table of Contents

1. [vim.motion](#vimmotion) - Cursor movement primitives
2. [vim.opt](#vimopt) - Configuration options (auto-scoped)
3. [vim.optLocal](#vimoptlocal) - Buffer-local options
4. [vim.optGlobal](#vimoptglobal) - Global options
5. [vim.bo](#vimbo) - Buffer properties
6. [vim.cursor](#vimcursor) - Cursor control and animation
7. [vim.layer](#vimlayer) - Virtual text and compositing
8. [vim.keymap](#vimkeymap) - Custom key mappings
9. [vim.filetype](#vimfiletype) - Language detection
10. [vim.buffer](#vimbuffer) - Buffer content access
11. [Global Functions](#global-functions) - setTimeout, console, etc.

---

## vim.motion

Cursor movement primitives for programmatic navigation.

**Performance**: ~168 ns/call (zero-copy HostObject)

### Methods

#### Character Motion

##### `vim.motion.left()`
Move cursor one character left (equivalent to `h`).

**Example**:
```javascript
vim.motion.left();
```

##### `vim.motion.right()`
Move cursor one character right (equivalent to `l`).

##### `vim.motion.up()`
Move cursor one line up (equivalent to `k`).

##### `vim.motion.down()`
Move cursor one line down (equivalent to `j`).

#### Line Motion

##### `vim.motion.toLineStart()`
Move cursor to start of line (column 0, equivalent to `0`).

##### `vim.motion.toLineEnd()`
Move cursor to end of line (equivalent to `$`).

##### `vim.motion.toFirstNonBlank()`
Move cursor to first non-whitespace character (equivalent to `^`).

#### Word Motion

##### `vim.motion.wordForward()`
Move cursor forward to start of next word (equivalent to `w`).

##### `vim.motion.wordBackward()`
Move cursor backward to start of previous word (equivalent to `b`).

##### `vim.motion.wordEnd()`
Move cursor to end of current word (equivalent to `e`).

#### File Motion

##### `vim.motion.toFileStart()`
Move cursor to first line of file (equivalent to `gg`).

##### `vim.motion.toFileEnd()`
Move cursor to last line of file (equivalent to `G`).

#### Scrolling

##### `vim.motion.scrollHalfPageDown()`
Scroll half page down (equivalent to `Ctrl+D`).

##### `vim.motion.scrollHalfPageUp()`
Scroll half page up (equivalent to `Ctrl+U`).

### Use Cases

**Animated Cursor Trails**:
```javascript
// Smooth cursor animation using requestAnimationFrame
let targetPos = vim.cursor.getPosition();

function animateCursor() {
  const currentPos = vim.cursor.getPosition();

  if (currentPos.row !== targetPos.row || currentPos.col !== targetPos.col) {
    // Interpolate position
    const row = Math.floor(currentPos.row + (targetPos.row - currentPos.row) * 0.3);
    const col = Math.floor(currentPos.col + (targetPos.col - currentPos.col) * 0.3);

    vim.cursor.setRenderPosition(row, col);
    requestAnimationFrame(animateCursor);
  } else {
    vim.cursor.clearRenderPosition();
  }
}

// Trigger on cursor movement
vim.keymap.set('n', 'j', () => {
  vim.motion.down();
  targetPos = vim.cursor.getPosition();
  requestAnimationFrame(animateCursor);
});
```

---

## vim.opt

Auto-scoped configuration options (Neovim-compatible).

**Behavior**: Reads buffer-local value if set, falls back to global value.

**Performance**: ~168 ns/property access (zero-copy HostObject)

### Supported Options

#### Display Options

##### `vim.opt.number: boolean`
Show line numbers.

**Default**: `false`

**Example**:
```javascript
vim.opt.number = true;  // Enable line numbers
```

##### `vim.opt.relativenumber: boolean`
Show relative line numbers.

**Default**: `false`

##### `vim.opt.cursorline: boolean`
Highlight current line.

**Default**: `false`

##### `vim.opt.list: boolean`
Show invisible characters (tabs, spaces, etc.).

**Default**: `false`

##### `vim.opt.listchars: string | object`
Characters to show for invisible characters.

**Default**: `"tab:> ,trail:~"`

**String format**: `"tab:→·,space:·,trail:~"`

**Object format** (auto-converted):
```javascript
vim.opt.listchars = {
  tab: "→·",
  space: "·",
  trail: "~",
  eol: "↲"
};
// Converted to: "tab:→·,space:·,trail:~,eol:↲"
```

##### `vim.opt.wrap: boolean`
Wrap long lines.

**Default**: `true`

##### `vim.opt.linebreak: boolean`
Wrap at word boundaries (requires `wrap` enabled).

**Default**: `false`

#### Indentation Options

##### `vim.opt.tabstop: number`
Number of spaces a tab character represents.

**Default**: `8`

**Example**:
```javascript
vim.opt.tabstop = 4;
```

##### `vim.opt.shiftwidth: number`
Number of spaces for auto-indent.

**Default**: `8`

##### `vim.opt.expandtab: boolean`
Convert tabs to spaces.

**Default**: `false`

##### `vim.opt.autoindent: boolean`
Copy indent from current line when starting new line.

**Default**: `true`

##### `vim.opt.smartindent: boolean`
Smart auto-indenting for C-like languages.

**Default**: `false`

#### Search Options

##### `vim.opt.ignorecase: boolean`
Case-insensitive search.

**Default**: `false`

##### `vim.opt.smartcase: boolean`
Override `ignorecase` if search contains uppercase.

**Default**: `false`

##### `vim.opt.hlsearch: boolean`
Highlight search matches.

**Default**: `true`

##### `vim.opt.incsearch: boolean`
Show search matches as you type.

**Default**: `true`

#### Editor Behavior

##### `vim.opt.mouse: string`
Enable mouse support (`"a"` = all modes).

**Default**: `""`

##### `vim.opt.clipboard: string`
Sync with system clipboard (`"unnamedplus"` = system clipboard).

**Default**: `""`

##### `vim.opt.timeout: boolean`
Enable key mapping timeout.

**Default**: `true`

##### `vim.opt.timeoutlen: number`
Timeout duration in milliseconds.

**Default**: `1000`

### Scope Behavior

**Auto-scoped** (reads local first, falls back to global):
```javascript
// Set global default
vim.opt.tabstop = 8;

// Set buffer-local override
vim.optLocal.tabstop = 4;

// Reads buffer-local value
console.log(vim.opt.tabstop); // 4
```

---

## vim.optLocal

Buffer-local configuration options (explicit local scope).

**Behavior**: Always reads/writes buffer-local value. Does NOT fall back to global.

### Example

```javascript
// Set buffer-local tabstop (only affects current buffer)
vim.optLocal.tabstop = 4;

// Set buffer-local listchars
vim.optLocal.listchars = { tab: "→·", trail: "~" };

// Read buffer-local value (returns null if not set)
const localTabstop = vim.optLocal.tabstop;
```

**When to use**: When you want explicit buffer-local configuration without global fallback.

---

## vim.optGlobal

Global configuration options (explicit global scope).

**Behavior**: Always reads/writes global value. Ignores buffer-local overrides.

### Example

```javascript
// Set global default for all buffers
vim.optGlobal.tabstop = 8;

// Set global listchars
vim.optGlobal.listchars = { tab: "> ", trail: "~" };

// Read global value (ignores buffer-local overrides)
const globalTabstop = vim.optGlobal.tabstop; // Always 8
```

**When to use**: When you want to set global defaults that apply to all buffers.

---

## vim.bo

Buffer-local properties (Neovim-compatible).

### Properties

##### `vim.bo.filetype: string`
Detected programming language for current buffer.

**Read/Write**: Yes (can override auto-detection)

**Example**:
```javascript
// Read detected filetype
console.log(vim.bo.filetype); // "rust"

// Override filetype
vim.bo.filetype = "javascript";
```

**Auto-detection**: Set automatically by `vim.filetype.match()`.

---

## vim.cursor

Cursor control and animation support.

### Methods

##### `vim.cursor.getPosition(): {row: number, col: number}`
Get current cursor position.

**Returns**: Object with `row` (0-indexed line) and `col` (0-indexed column).

**Example**:
```javascript
const pos = vim.cursor.getPosition();
console.log(`Cursor at line ${pos.row + 1}, column ${pos.col + 1}`);
```

##### `vim.cursor.setRenderPosition(row: number, col: number): void`
Override cursor render position (for animations).

**Parameters**:
- `row`: Line number (0-indexed)
- `col`: Column number (0-indexed)

**Note**: This only affects rendering, not logical cursor position.

**Example**:
```javascript
// Render cursor at line 10, column 5 (for animation)
vim.cursor.setRenderPosition(10, 5);
```

##### `vim.cursor.clearRenderPosition(): void`
Restore normal cursor rendering.

**Example**:
```javascript
vim.cursor.clearRenderPosition();
```

### Use Cases

**Smear Cursor Effect**:
```javascript
// Create trailing cursor effect
let trail = [];
const TRAIL_LENGTH = 10;

function updateCursor() {
  const pos = vim.cursor.getPosition();

  // Add current position to trail
  trail.unshift({ row: pos.row, col: pos.col });
  if (trail.length > TRAIL_LENGTH) trail.pop();

  // Render trail with decreasing opacity
  trail.forEach((p, i) => {
    const opacity = 1.0 - (i / TRAIL_LENGTH);
    vim.layer.drawVirtualText(p.row, p.col, "█", 0xFFFFFF, 0x000000);
    vim.layer.setLayerOpacity(0, opacity);
  });
}

setInterval(updateCursor, 16); // 60fps
```

---

## vim.layer

Virtual text rendering and compositing (Neovim-style extmarks).

### Methods

##### `vim.layer.drawVirtualText(row: number, col: number, text: string, fg: number, bg: number): void`
Draw virtual text at position (does not modify buffer content).

**Parameters**:
- `row`: Line number (0-indexed)
- `col`: Column number (0-indexed)
- `text`: String to render
- `fg`: Foreground color (24-bit RGB, e.g., `0xFF0000` = red)
- `bg`: Background color (24-bit RGB, e.g., `0x000000` = black)

**Example**:
```javascript
// Draw error message in red
vim.layer.drawVirtualText(5, 0, "Error: undefined variable", 0xFF0000, 0x000000);
```

##### `vim.layer.clearVirtualText(row: number): void`
Clear all virtual text on line.

**Example**:
```javascript
vim.layer.clearVirtualText(5);
```

##### `vim.layer.getViewportInfo(): {top: number, bottom: number, height: number}`
Get current viewport bounds.

**Returns**: Object with:
- `top`: First visible line (0-indexed)
- `bottom`: Last visible line (0-indexed)
- `height`: Viewport height in lines

##### `vim.layer.getGutterWidth(): number`
Get width of line number gutter.

**Returns**: Gutter width in characters.

##### `vim.layer.createLayer(name: string): number`
Create named compositing layer.

**Returns**: Layer ID (integer).

**Example**:
```javascript
const diagnosticsLayer = vim.layer.createLayer("diagnostics");
```

##### `vim.layer.renderVirtualText(layerId: number, row: number, col: number, text: string, fg: number, bg: number): void`
Render virtual text to specific layer.

**Example**:
```javascript
vim.layer.renderVirtualText(diagnosticsLayer, 5, 0, "Warning", 0xFFFF00, 0x000000);
```

##### `vim.layer.setLayerOpacity(layerId: number, opacity: number): void`
Set layer transparency.

**Parameters**:
- `layerId`: Layer ID from `createLayer()`
- `opacity`: 0.0 (fully transparent) to 1.0 (fully opaque)

**Example**:
```javascript
vim.layer.setLayerOpacity(diagnosticsLayer, 0.5);
```

##### `vim.layer.clearLayer(layerId: number): void`
Clear all content on layer.

##### `vim.layer.destroyLayer(layerId: number): void`
Remove layer entirely.

### Use Cases

**LSP Diagnostics**:
```javascript
const diagnosticsLayer = vim.layer.createLayer("diagnostics");

function showDiagnostics(diagnostics) {
  vim.layer.clearLayer(diagnosticsLayer);

  diagnostics.forEach(diag => {
    const color = diag.severity === "error" ? 0xFF0000 : 0xFFFF00;
    vim.layer.renderVirtualText(
      diagnosticsLayer,
      diag.line,
      diag.column,
      diag.message,
      color,
      0x000000
    );
  });
}
```

---

## vim.keymap

Custom key mapping system (Neovim-compatible).

### Methods

##### `vim.keymap.set(mode: string, lhs: string, rhs: string | function, opts?: object): void`
Register custom key mapping.

**Parameters**:
- `mode`: Mode string
  - `'n'`: Normal mode
  - `'i'`: Insert mode
  - `'v'`: Visual mode
  - `'c'`: Command mode
- `lhs`: Key sequence to map (e.g., `'H'`, `'<leader>w'`)
- `rhs`: Command string or callback function
- `opts`: Optional configuration
  - `noremap`: boolean - Non-recursive mapping (default: `false`)
  - `silent`: boolean - Don't show command in status line (default: `false`)
  - `buffer`: boolean - Buffer-local mapping (default: `false`)

**Example (string command)**:
```javascript
// Map H to move left (recursive)
vim.keymap.set('n', 'H', 'h');

// Map H to move left (non-recursive)
vim.keymap.set('n', 'H', 'h', { noremap: true });
```

**Example (callback function)**:
```javascript
// Map <leader>w to save file
vim.keymap.set('n', '<leader>w', () => {
  console.log('Saving file...');
  // Save logic here
}, { noremap: true, silent: true });
```

**Example (buffer-local)**:
```javascript
// Map gd to go to definition (only in current buffer)
vim.keymap.set('n', 'gd', () => {
  jumpToDefinition();
}, { buffer: true });
```

##### `vim.keymap.del(mode: string, lhs: string): void`
Delete key mapping.

**Example**:
```javascript
vim.keymap.del('n', 'H');
```

---

## vim.filetype

Programming language detection (GitHub Linguist via go-enry).

**Coverage**: 697 languages

### Methods

##### `vim.filetype.match(opts: {filename?: string, buf?: number}): string | null`
Detect programming language.

**Parameters**:
- `opts.filename`: File path (e.g., `"main.rs"`)
- `opts.buf`: Buffer number (e.g., `0` for current)

**Returns**: Language name (e.g., `"Rust"`) or `null` if unknown.

**Detection strategies** (applied in order):
1. Filename matching (`"Makefile"` → `"Makefile"`)
2. Extension matching (`".rs"` → `"Rust"`)
3. Shebang detection (`#!/bin/bash` → `"Shell"`)
4. Modeline parsing (`# vim: set ft=python:` → `"Python"`)
5. Content heuristics (regexp-based disambiguation)
6. Bayesian classifier (last resort)

**Example (filename)**:
```javascript
const lang = vim.filetype.match({ filename: "main.rs" });
console.log(lang); // "Rust"
```

**Example (buffer)**:
```javascript
const lang = vim.filetype.match({ buf: 0 });
console.log(lang); // Detected language for current buffer
```

**Example (set buffer filetype)**:
```javascript
const lang = vim.filetype.match({ filename: "Dockerfile" });
if (lang) {
  vim.bo.filetype = lang.toLowerCase(); // "dockerfile"
}
```

---

## vim.buffer

Buffer content access (zero-copy ArrayBuffer).

### Methods

##### `vim.buffer.getContent(): ArrayBuffer`
Get buffer content as ArrayBuffer (zero-copy snapshot).

**Returns**: ArrayBuffer containing all buffer bytes.

**Note**: This is a READ-ONLY snapshot. Buffer modifications invalidate this ArrayBuffer.

**Example**:
```javascript
const content = vim.buffer.getContent();
const text = new TextDecoder().decode(content);
console.log(text);
```

##### `vim.buffer.getLineContent(lineNum: number): ArrayBuffer`
Get single line as ArrayBuffer (zero-copy view).

**Parameters**:
- `lineNum`: Line number (0-indexed)

**Returns**: ArrayBuffer containing line bytes (includes newline if present).

**Example**:
```javascript
const line5 = vim.buffer.getLineContent(5);
const lineText = new TextDecoder().decode(line5);
```

##### `vim.buffer.getLength(): number`
Get buffer content length in bytes.

**Example**:
```javascript
const byteCount = vim.buffer.getLength();
```

##### `vim.buffer.getLineCount(): number`
Get number of lines in buffer.

**Example**:
```javascript
const lineCount = vim.buffer.getLineCount();
```

### Use Cases

**Search Buffer Content**:
```javascript
function searchBuffer(pattern) {
  const content = vim.buffer.getContent();
  const text = new TextDecoder().decode(content);

  const matches = [];
  let match;
  const regex = new RegExp(pattern, 'g');

  while ((match = regex.exec(text)) !== null) {
    matches.push({
      index: match.index,
      text: match[0]
    });
  }

  return matches;
}
```

**Line-by-Line Processing**:
```javascript
const lineCount = vim.buffer.getLineCount();

for (let i = 0; i < lineCount; i++) {
  const lineBuffer = vim.buffer.getLineContent(i);
  const lineText = new TextDecoder().decode(lineBuffer);

  // Process line
  if (lineText.includes('TODO')) {
    console.log(`TODO on line ${i + 1}: ${lineText.trim()}`);
  }
}
```

---

## Global Functions

### Timers

##### `setTimeout(callback: function, delay: number): number`
Execute callback after delay.

**Returns**: Timer ID (for `clearTimeout`).

**Example**:
```javascript
const timerId = setTimeout(() => {
  console.log('Delayed execution');
}, 1000);
```

##### `setInterval(callback: function, delay: number): number`
Execute callback repeatedly at interval.

**Returns**: Timer ID (for `clearInterval`).

**Example**:
```javascript
const intervalId = setInterval(() => {
  console.log('Repeated execution');
}, 1000);
```

##### `clearTimeout(timerId: number): void`
Cancel timeout.

##### `clearInterval(timerId: number): void`
Cancel interval.

### Animation

##### `requestAnimationFrame(callback: function): number`
Execute callback on next render frame (~16ms for 60fps).

**Returns**: Frame ID (for `cancelAnimationFrame`).

**Example**:
```javascript
function animate() {
  // Animation logic
  updateCursorPosition();

  requestAnimationFrame(animate); // Loop
}

requestAnimationFrame(animate);
```

##### `cancelAnimationFrame(frameId: number): void`
Cancel animation frame request.

### Console

##### `console.log(...args: any[]): void`
Log to console (Chrome DevTools + file logs).

**Example**:
```javascript
console.log('Message', { key: 'value' });
```

### Performance

##### `performance.now(): number`
Get current timestamp in milliseconds (since epoch).

##### `performance.mark(name: string): void`
Create named performance mark.

##### `performance.measure(name: string, startMark: string, endMark: string): void`
Measure time between marks.

**Example**:
```javascript
performance.mark('start');
// ... expensive operation ...
performance.mark('end');
performance.measure('operation', 'start', 'end');

const measures = performance.getEntriesByType('measure');
console.log(measures[0].duration); // ms
```

---

## Complete Plugin Example

**Smear Cursor Plugin** (inspired by smear_cursor.nvim):

```javascript
// Configuration
const CONFIG = {
  trailLength: 10,
  updateInterval: 16, // 60fps
  fadeRate: 0.1,
};

// State
let cursorTrail = [];
let lastPosition = vim.cursor.getPosition();
let animationFrameId = null;

// Trail rendering
function renderTrail() {
  const currentPos = vim.cursor.getPosition();

  // Detect movement
  if (currentPos.row !== lastPosition.row || currentPos.col !== lastPosition.col) {
    // Add to trail
    cursorTrail.unshift({ ...currentPos, opacity: 1.0 });

    // Limit trail length
    if (cursorTrail.length > CONFIG.trailLength) {
      cursorTrail.pop();
    }

    lastPosition = currentPos;
  }

  // Update trail opacity
  cursorTrail.forEach((pos, i) => {
    pos.opacity -= CONFIG.fadeRate;

    if (pos.opacity > 0) {
      vim.cursor.setRenderPosition(pos.row, pos.col);
      // Render with fading opacity
    }
  });

  // Remove fully faded positions
  cursorTrail = cursorTrail.filter(pos => pos.opacity > 0);

  // Continue animation
  animationFrameId = requestAnimationFrame(renderTrail);
}

// Start plugin
renderTrail();

// Cleanup on disable
function disable() {
  if (animationFrameId !== null) {
    cancelAnimationFrame(animationFrameId);
    animationFrameId = null;
  }
  vim.cursor.clearRenderPosition();
  cursorTrail = [];
}
```

---

## Performance Considerations

### HostObject Property Access
- **~168 ns/call** - Zero-copy JSI
- **6M ops/sec** - High throughput
- **No serialization** - Direct memory access

### Best Practices

1. **Batch operations**: Group multiple property accesses
2. **Cache values**: Store frequently accessed properties
3. **Use requestAnimationFrame**: For smooth 60fps animations
4. **Avoid hot loops**: Don't call JSI in tight loops (cache instead)

**Example (efficient)**:
```javascript
// Cache option values
const cachedTabstop = vim.opt.tabstop;
const cachedNumber = vim.opt.number;

// Use cached values in loop
for (let i = 0; i < 1000; i++) {
  processLine(i, cachedTabstop, cachedNumber);
}
```

**Example (inefficient)**:
```javascript
// Don't do this - calls JSI 1000 times!
for (let i = 0; i < 1000; i++) {
  processLine(i, vim.opt.tabstop, vim.opt.number);
}
```

---

## Migration from Legacy API

See [Migration Guide](./vim-api-migration-guide.md) for detailed migration instructions.

**Quick comparison**:

| Legacy | HostObject |
|--------|------------|
| `moveLeft()` | `vim.motion.left()` |
| `setOption("number", true)` | `vim.opt.number = true` |
| `getOption("number")` | `vim.opt.number` |
| `getCursorPosition()` | `vim.cursor.getPosition()` |
| `drawVirtualText(...)` | `vim.layer.drawVirtualText(...)` |

---

## See Also

- [JSI HostObject Architecture](../architecture/jsi-hostobject-architecture.md)
- [Migration Guide](./vim-api-migration-guide.md)
- [Plugin SDK Vision](../architecture/plugin-sdk-vision.md)
