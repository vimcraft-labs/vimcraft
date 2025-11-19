# Vimcraft API Migration Guide

**From**: Legacy function-based JSI
**To**: HostObject-based API (v0.4.0)
**Performance Gain**: 3-5x faster

This guide helps you migrate existing plugins from the legacy function-based API to the new HostObject-based API.

---

## Why Migrate?

### Performance
- **3-5x faster** property access (~168 ns vs 500-800 ns)
- **Zero-copy** data transfer
- **O(1) property dispatch** via StaticStringMap

### Developer Experience
- **Cleaner syntax**: `vim.opt.number = true` vs `setOption("number", true)`
- **Type safety**: Better IDE autocomplete
- **Chrome DevTools**: Inspect vim objects in debugger

### Future-proof
- **HostObject pattern** is the foundation for all future APIs
- **Backwards compatibility** maintained during transition period
- **Active development** focused on HostObject APIs

---

## Migration Strategy

### Option 1: Gradual Migration (Recommended)

Migrate one API at a time, test thoroughly:

```javascript
// Week 1: Migrate vim.opt
// Before
setOption("number", true);

// After
vim.opt.number = true;

// Week 2: Migrate vim.motion
// Before
moveLeft();

// After
vim.motion.left();

// Week 3: Test + polish
```

### Option 2: Full Rewrite

For small plugins, rewrite entirely using new API:

```javascript
// Old plugin.js
function setup() {
  setOption("number", true);
  setOption("cursorline", true);
  keymapSet('n', 'H', 'h', { noremap: true });
}

// New plugin.js
function setup() {
  vim.opt.number = true;
  vim.opt.cursorline = true;
  vim.keymap.set('n', 'H', 'h', { noremap: true });
}
```

---

## API Migration Table

### vim.motion (Cursor Movement)

| Legacy | HostObject |
|--------|------------|
| `moveLeft()` | `vim.motion.left()` |
| `moveRight()` | `vim.motion.right()` |
| `moveUp()` | `vim.motion.up()` |
| `moveDown()` | `vim.motion.down()` |
| `moveToLineStart()` | `vim.motion.toLineStart()` |
| `moveToLineEnd()` | `vim.motion.toLineEnd()` |
| `moveToFirstNonBlank()` | `vim.motion.toFirstNonBlank()` |
| `moveWordForward()` | `vim.motion.wordForward()` |
| `moveWordBackward()` | `vim.motion.wordBackward()` |
| `moveWordEnd()` | `vim.motion.wordEnd()` |
| `moveToFileStart()` | `vim.motion.toFileStart()` |
| `moveToFileEnd()` | `vim.motion.toFileEnd()` |
| `scrollHalfPageDown()` | `vim.motion.scrollHalfPageDown()` |
| `scrollHalfPageUp()` | `vim.motion.scrollHalfPageUp()` |

**Migration example**:
```javascript
// Before
function moveToNextWord() {
  moveWordForward();
}

// After
function moveToNextWord() {
  vim.motion.wordForward();
}
```

### vim.opt (Configuration Options)

| Legacy | HostObject |
|--------|------------|
| `setOption(name, value)` | `vim.opt[name] = value` |
| `getOption(name)` | `vim.opt[name]` |
| `setOptionLocal(name, value)` | `vim.optLocal[name] = value` |
| `getOptionLocal(name)` | `vim.optLocal[name]` |
| `setOptionGlobal(name, value)` | `vim.optGlobal[name] = value` |
| `getOptionGlobal(name)` | `vim.optGlobal[name]` |

**Migration example**:
```javascript
// Before
setOption("number", true);
setOption("tabstop", 4);
setOption("listchars", "tab:→·,trail:~");

const isNumber = getOption("number");

// After
vim.opt.number = true;
vim.opt.tabstop = 4;
vim.opt.listchars = { tab: "→·", trail: "~" }; // Object format!

const isNumber = vim.opt.number;
```

**Special case: listchars**

The new API supports object format (auto-converted to string):

```javascript
// Old: String only
setOption("listchars", "tab:→·,space:·,trail:~");

// New: Object (recommended)
vim.opt.listchars = {
  tab: "→·",
  space: "·",
  trail: "~"
};

// New: String (still supported)
vim.opt.listchars = "tab:→·,space:·,trail:~";
```

### vim.cursor (Cursor Control)

| Legacy | HostObject |
|--------|------------|
| `getCursorPosition()` | `vim.cursor.getPosition()` |
| `setCursorRenderPosition(row, col)` | `vim.cursor.setRenderPosition(row, col)` |
| `clearCursorRenderPosition()` | `vim.cursor.clearRenderPosition()` |

**Migration example**:
```javascript
// Before
const pos = getCursorPosition();
setCursorRenderPosition(pos.row + 1, pos.col);
clearCursorRenderPosition();

// After
const pos = vim.cursor.getPosition();
vim.cursor.setRenderPosition(pos.row + 1, pos.col);
vim.cursor.clearRenderPosition();
```

### vim.layer (Virtual Text)

| Legacy | HostObject |
|--------|------------|
| `drawVirtualText(row, col, text, fg, bg)` | `vim.layer.drawVirtualText(row, col, text, fg, bg)` |
| `clearVirtualText(row)` | `vim.layer.clearVirtualText(row)` |
| `getViewportInfo()` | `vim.layer.getViewportInfo()` |
| `getGutterWidth()` | `vim.layer.getGutterWidth()` |
| `createLayer(name)` | `vim.layer.createLayer(name)` |
| `renderVirtualText(...)` | `vim.layer.renderVirtualText(...)` |
| `setLayerOpacity(id, opacity)` | `vim.layer.setLayerOpacity(id, opacity)` |
| `clearLayer(id)` | `vim.layer.clearLayer(id)` |
| `destroyLayer(id)` | `vim.layer.destroyLayer(id)` |

**Migration example**:
```javascript
// Before
drawVirtualText(5, 0, "Error", 0xFF0000, 0x000000);
clearVirtualText(5);

const layerId = createLayer("diagnostics");
renderVirtualText(layerId, 10, 0, "Warning", 0xFFFF00, 0x000000);
setLayerOpacity(layerId, 0.5);

// After
vim.layer.drawVirtualText(5, 0, "Error", 0xFF0000, 0x000000);
vim.layer.clearVirtualText(5);

const layerId = vim.layer.createLayer("diagnostics");
vim.layer.renderVirtualText(layerId, 10, 0, "Warning", 0xFFFF00, 0x000000);
vim.layer.setLayerOpacity(layerId, 0.5);
```

### vim.keymap (Key Mappings)

| Legacy | HostObject |
|--------|------------|
| `keymapSet(mode, lhs, rhs, opts)` | `vim.keymap.set(mode, lhs, rhs, opts)` |
| `keymapDel(mode, lhs)` | `vim.keymap.del(mode, lhs)` |

**Migration example**:
```javascript
// Before
keymapSet('n', 'H', 'h', { noremap: true });
keymapSet('n', '<leader>w', () => saveFile(), { silent: true });
keymapDel('n', 'H');

// After
vim.keymap.set('n', 'H', 'h', { noremap: true });
vim.keymap.set('n', '<leader>w', () => saveFile(), { silent: true });
vim.keymap.del('n', 'H');
```

### vim.filetype (Language Detection)

| Legacy | HostObject | Notes |
|--------|------------|-------|
| `vim_filetype_match(opts)` | `vim.filetype.match(opts)` | Now uses **go-enry** (697 languages) |

**Migration example**:
```javascript
// Before (Neovim Lua-based detection)
const ft = vim_filetype_match({ filename: "main.rs" });

// After (go-enry based detection)
const ft = vim.filetype.match({ filename: "main.rs" }); // "Rust"

// Auto-set buffer filetype
if (ft) {
  vim.bo.filetype = ft.toLowerCase();
}
```

**Key change**: Language names now follow GitHub Linguist capitalization (`"Rust"` instead of `"rust"`).

### vim.buffer (Buffer Content) - NEW!

**No legacy equivalent** - this is a new API.

```javascript
// Zero-copy buffer access (NEW)
const content = vim.buffer.getContent(); // ArrayBuffer
const text = new TextDecoder().decode(content);

// Line-level access (NEW)
const line5 = vim.buffer.getLineContent(5);

// Metadata (NEW)
const byteCount = vim.buffer.getLength();
const lineCount = vim.buffer.getLineCount();
```

---

## Common Migration Patterns

### Pattern 1: Option Configuration

**Before**:
```javascript
function configure() {
  setOption("number", true);
  setOption("relativenumber", true);
  setOption("cursorline", true);
  setOption("tabstop", 4);
  setOption("shiftwidth", 4);
  setOption("expandtab", true);
}
```

**After**:
```javascript
function configure() {
  vim.opt.number = true;
  vim.opt.relativenumber = true;
  vim.opt.cursorline = true;
  vim.opt.tabstop = 4;
  vim.opt.shiftwidth = 4;
  vim.opt.expandtab = true;
}
```

**Or (object destructuring)**:
```javascript
function configure() {
  Object.assign(vim.opt, {
    number: true,
    relativenumber: true,
    cursorline: true,
    tabstop: 4,
    shiftwidth: 4,
    expandtab: true
  });
}
```

### Pattern 2: Cursor Animation

**Before**:
```javascript
function animateCursor(targetRow, targetCol) {
  const current = getCursorPosition();

  if (current.row !== targetRow || current.col !== targetCol) {
    const newRow = Math.floor(current.row + (targetRow - current.row) * 0.3);
    const newCol = Math.floor(current.col + (targetCol - current.col) * 0.3);

    setCursorRenderPosition(newRow, newCol);
    requestAnimationFrame(() => animateCursor(targetRow, targetCol));
  } else {
    clearCursorRenderPosition();
  }
}
```

**After**:
```javascript
function animateCursor(targetRow, targetCol) {
  const current = vim.cursor.getPosition();

  if (current.row !== targetRow || current.col !== targetCol) {
    const newRow = Math.floor(current.row + (targetRow - current.row) * 0.3);
    const newCol = Math.floor(current.col + (targetCol - current.col) * 0.3);

    vim.cursor.setRenderPosition(newRow, newCol);
    requestAnimationFrame(() => animateCursor(targetRow, targetCol));
  } else {
    vim.cursor.clearRenderPosition();
  }
}
```

### Pattern 3: Virtual Text Rendering

**Before**:
```javascript
function showDiagnostics(diagnostics) {
  diagnostics.forEach(diag => {
    const color = diag.severity === "error" ? 0xFF0000 : 0xFFFF00;
    drawVirtualText(diag.line, diag.column, diag.message, color, 0x000000);
  });
}

function clearDiagnostics(lines) {
  lines.forEach(line => clearVirtualText(line));
}
```

**After**:
```javascript
function showDiagnostics(diagnostics) {
  diagnostics.forEach(diag => {
    const color = diag.severity === "error" ? 0xFF0000 : 0xFFFF00;
    vim.layer.drawVirtualText(diag.line, diag.column, diag.message, color, 0x000000);
  });
}

function clearDiagnostics(lines) {
  lines.forEach(line => vim.layer.clearVirtualText(line));
}
```

### Pattern 4: Key Mapping Setup

**Before**:
```javascript
function setupKeymaps() {
  // Navigation
  keymapSet('n', 'H', 'h', { noremap: true });
  keymapSet('n', 'J', 'j', { noremap: true });
  keymapSet('n', 'K', 'k', { noremap: true });
  keymapSet('n', 'L', 'l', { noremap: true });

  // Commands
  keymapSet('n', '<leader>w', () => saveFile(), { noremap: true, silent: true });
  keymapSet('n', '<leader>q', () => quit(), { noremap: true, silent: true });
}
```

**After**:
```javascript
function setupKeymaps() {
  // Navigation
  vim.keymap.set('n', 'H', 'h', { noremap: true });
  vim.keymap.set('n', 'J', 'j', { noremap: true });
  vim.keymap.set('n', 'K', 'k', { noremap: true });
  vim.keymap.set('n', 'L', 'l', { noremap: true });

  // Commands
  vim.keymap.set('n', '<leader>w', () => saveFile(), { noremap: true, silent: true });
  vim.keymap.set('n', '<leader>q', () => quit(), { noremap: true, silent: true });
}
```

---

## Complete Plugin Migration Example

### Legacy Plugin (smear-cursor-old.js)

```javascript
// Legacy smear cursor plugin
const TRAIL_LENGTH = 10;
let trail = [];

function updateTrail() {
  const pos = getCursorPosition();

  // Add position to trail
  trail.unshift({ row: pos.row, col: pos.col });
  if (trail.length > TRAIL_LENGTH) trail.pop();

  // Render trail
  trail.forEach((p, i) => {
    const opacity = 1.0 - (i / TRAIL_LENGTH);
    // Render trail position (simplified)
    setCursorRenderPosition(p.row, p.col);
  });

  requestAnimationFrame(updateTrail);
}

// Start
updateTrail();
```

### New HostObject Plugin (smear-cursor.js)

```javascript
// New HostObject-based smear cursor plugin
const TRAIL_LENGTH = 10;
let trail = [];

function updateTrail() {
  const pos = vim.cursor.getPosition();

  // Add position to trail
  trail.unshift({ row: pos.row, col: pos.col });
  if (trail.length > TRAIL_LENGTH) trail.pop();

  // Render trail
  trail.forEach((p, i) => {
    const opacity = 1.0 - (i / TRAIL_LENGTH);
    // Render trail position (simplified)
    vim.cursor.setRenderPosition(p.row, p.col);
  });

  requestAnimationFrame(updateTrail);
}

// Start
updateTrail();
```

**Changes**:
- `getCursorPosition()` → `vim.cursor.getPosition()`
- `setCursorRenderPosition()` → `vim.cursor.setRenderPosition()`

---

## Testing Your Migration

### Step 1: Search and Replace

Use editor search/replace to find legacy API calls:

**Search patterns**:
- `moveLeft\(\)` → `vim.motion.left()`
- `moveRight\(\)` → `vim.motion.right()`
- `setOption\(` → `vim.opt`
- `getOption\(` → `vim.opt`
- `getCursorPosition\(\)` → `vim.cursor.getPosition()`
- `drawVirtualText\(` → `vim.layer.drawVirtualText(`
- `keymapSet\(` → `vim.keymap.set(`

### Step 2: Manual Review

Check for:
1. **Option object conversion**: `listchars` string → object
2. **Filetype capitalization**: `"rust"` → `"Rust"`
3. **Scope changes**: `setOptionLocal` → `vim.optLocal`

### Step 3: Load and Test

```javascript
// Load new plugin
// Check console for errors
console.log('Plugin loaded');

// Test basic functionality
vim.opt.number = true;
console.log('Number enabled:', vim.opt.number);

// Test cursor
const pos = vim.cursor.getPosition();
console.log('Cursor position:', pos);
```

### Step 4: Performance Check

Compare performance before/after:

```javascript
// Before migration
performance.mark('start');
for (let i = 0; i < 1000; i++) {
  setOption("number", true);
  const val = getOption("number");
}
performance.mark('end');
performance.measure('legacy', 'start', 'end');

// After migration
performance.mark('start2');
for (let i = 0; i < 1000; i++) {
  vim.opt.number = true;
  const val = vim.opt.number;
}
performance.mark('end2');
performance.measure('hostobject', 'start2', 'end2');

const measures = performance.getEntriesByType('measure');
console.log('Legacy:', measures[0].duration, 'ms');
console.log('HostObject:', measures[1].duration, 'ms');
console.log('Speedup:', (measures[0].duration / measures[1].duration).toFixed(1) + 'x');
```

Expected: **3-5x speedup**

---

## Troubleshooting

### Issue: "vim is not defined"

**Cause**: Plugin loaded before runtime initialization.

**Solution**: Check plugin load order:
```javascript
// Ensure runtime.js loads first
if (typeof vim === 'undefined') {
  throw new Error('Vimcraft runtime not initialized');
}
```

### Issue: "Property not found on vim.opt"

**Cause**: Option name typo or unsupported option.

**Solution**: Check [API Reference](./vim-api-reference.md) for supported options:
```javascript
// Supported
vim.opt.number = true;
vim.opt.tabstop = 4;

// Not supported yet (Phase 4)
vim.opt.colorcolumn = "80"; // Future feature
```

### Issue: "listchars not working"

**Cause**: Object format requires all string values.

**Solution**: Ensure all values are strings:
```javascript
// Wrong
vim.opt.listchars = { tab: 123 }; // Number not supported

// Correct
vim.opt.listchars = { tab: "→·", space: "·" };
```

### Issue: "Filetype detection returns wrong language"

**Cause**: go-enry capitalization differs from Neovim.

**Solution**: Convert to lowercase for buffer filetype:
```javascript
const lang = vim.filetype.match({ filename: "main.rs" });
if (lang) {
  vim.bo.filetype = lang.toLowerCase(); // "rust"
}
```

---

## Backwards Compatibility

**During transition** (current), both APIs work:

```javascript
// Legacy (still works)
setOption("number", true);

// HostObject (recommended)
vim.opt.number = true;
```

**Timeline**:
- **Phase 1** (Current): Dual support (Legacy + HostObject)
- **Phase 2** (TBD): Deprecation warnings for legacy API
- **Phase 3** (TBD): Legacy API removal

**Recommendation**: Migrate now to avoid future breaking changes.

---

## Performance Tips

### Tip 1: Cache Frequently Accessed Values

```javascript
// Inefficient (1000 JSI calls)
for (let i = 0; i < 1000; i++) {
  process(vim.opt.tabstop);
}

// Efficient (1 JSI call)
const tabstop = vim.opt.tabstop;
for (let i = 0; i < 1000; i++) {
  process(tabstop);
}
```

### Tip 2: Batch Property Updates

```javascript
// Inefficient (separate updates trigger multiple re-renders)
vim.opt.number = true;
vim.opt.relativenumber = true;
vim.opt.cursorline = true;

// Efficient (single batch update)
Object.assign(vim.opt, {
  number: true,
  relativenumber: true,
  cursorline: true
});
```

### Tip 3: Use requestAnimationFrame for Animations

```javascript
// Inefficient (timer drift)
setInterval(() => {
  updateCursor();
}, 16);

// Efficient (synchronized with display refresh)
function animate() {
  updateCursor();
  requestAnimationFrame(animate);
}
requestAnimationFrame(animate);
```

---

## Next Steps

1. **Read [API Reference](./vim-api-reference.md)** - Complete API documentation
2. **Review [HostObject Architecture](../architecture/jsi-hostobject-architecture.md)** - Understanding the implementation
3. **Check [Migration Summary](../architecture/jsi-hostobject-migration-summary.md)** - Technical details and metrics
4. **Join Discord** (link TBD) - Get help from community

---

## Need Help?

**Questions?**
- Check [API Reference](./vim-api-reference.md)
- Read [HostObject Architecture](../architecture/jsi-hostobject-architecture.md)
- Open GitHub issue: `https://github.com/vimcraft/editor/issues`

**Found a bug?**
- Report at: `https://github.com/vimcraft/editor/issues`
- Include: Plugin code, error message, Vimcraft version

**Want to contribute?**
- See [Contributing Guide](../../CONTRIBUTING.md) (TBD)
