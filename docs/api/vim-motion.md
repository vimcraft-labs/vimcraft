# vim.motion API

JavaScript API for programmatically triggering Vim motion commands.

## Overview

The `vim.motion` API exposes the same core movement functions that keyboard commands use, allowing plugins to script complex navigation patterns.

## Character Motion

```javascript
vim.motion.left()       // h - move left one character
vim.motion.right()      // l - move right one character
vim.motion.up()         // k - move up one line
vim.motion.down()       // j - move down one line
```

## Line Motion

```javascript
vim.motion.toLineStart()       // 0 - move to start of line
vim.motion.toLineEnd()         // $ - move to end of line
vim.motion.toFirstNonBlank()   // ^ - move to first non-blank character
```

## Word Motion

```javascript
vim.motion.wordForward()       // w - move to start of next word
vim.motion.wordBackward()      // b - move to start of previous word
vim.motion.wordEnd()           // e - move to end of word
```

## File Motion

```javascript
vim.motion.toFileStart()       // gg - move to start of file
vim.motion.toFileEnd()         // G - move to end of file
```

## Viewport Motion

```javascript
vim.motion.toViewportTop()     // H - move to top of screen
vim.motion.toViewportMiddle()  // M - move to middle of screen
vim.motion.toViewportBottom()  // L - move to bottom of screen
```

## Scrolling

```javascript
vim.motion.scrollHalfPageDown()  // Ctrl+D - scroll down half page
vim.motion.scrollHalfPageUp()    // Ctrl+U - scroll up half page
```

## Example Usage

```javascript
// Plugin: jump-to-definition.js
function jumpToDefinition() {
  vim.motion.toFileStart();
  vim.search.findNext("^function myFunc");
  vim.motion.toFirstNonBlank();
}

// Plugin: smart-scroll.js
function centerCursor() {
  const line = vim.api.getCurrentLine();
  vim.motion.toViewportMiddle();
}

// Plugin: bracket-navigator.js
function nextBracket() {
  vim.motion.wordForward();
  while (vim.api.getCharUnderCursor() !== '{') {
    vim.motion.wordForward();
  }
}
```

## Architecture

All `vim.motion.*` functions call the same core movement primitives in `movement.zig` that keyboard commands use, ensuring consistent behavior.

```
Keyboard 'H' ────┐
                 ├──→ movement.moveToViewportTop()
vim.motion.toViewportTop() ──┘
```

## Implementation Status

- ✅ Character motion (h/j/k/l)
- ✅ Line motion (0/$^)
- ✅ Word motion (w/b/e)
- ✅ File motion (gg/G)
- ✅ Viewport motion (H/M/L)
- ✅ Scrolling (Ctrl+D/U)

Total: 16 motion functions exposed

## Implementation Details

### The State Update Problem

JavaScript APIs (like `vim.motion.right()`, `vim.opt.number = true`) modify editor state, but the main event loop doesn't automatically know to re-render the screen. Without marking state as "dirty", changes are invisible until the next user input.

**Example Bug**:
```javascript
// This moves cursor but screen doesn't update until next keypress
setInterval(() => {
    vim.motion.right();
}, 1000);
```

### Solution: Dirty Flag Pattern

All JavaScript APIs that modify editor state use a dirty flag pattern to trigger re-renders.

#### For APIs with Editor Context

```zig
// In your JSI function, after modifying state:
editor.js_state_dirty = true;  // Triggers re-render on next event loop
```

#### For APIs with Custom Context Structs

```zig
// 1. Add js_state_dirty pointer to context:
pub const MyContext = struct {
    // ... other fields ...
    js_state_dirty: ?*bool = null, // null for headless mode
};

// 2. In your function:
if (ctx.js_state_dirty) |dirty| {
    dirty.* = true;
}
```

#### Wiring in jsi_api.zig

```zig
const ctx = allocator.create(MyContext) catch @panic("...");
ctx.* = MyContext{
    // ... other fields ...
    .js_state_dirty = if (@TypeOf(editor_or_context) == *Editor)
        &editor_or_context.js_state_dirty
    else
        null, // EditorContext (headless) doesn't need dirty tracking
};
```

### vim.motion Implementation

**Location**: `src/system/jsi/motion_api.zig`

```zig
// Context structure
pub const MotionContext = struct {
    buffer: *Buffer,
    viewport_top: *usize,
    viewport_height: usize,
    js_state_dirty: ?*bool, // Pointer to editor's dirty flag

    /// Mark editor state as dirty (triggers re-render in main loop)
    inline fn markDirty(self: *const MotionContext) void {
        if (self.js_state_dirty) |dirty_flag| {
            dirty_flag.* = true;
        }
    }
};

// Example motion function
export fn moveRight(...) callconv(.c) ?*c.OVHermesValue {
    movement.moveRight(ctx.buffer);  // Modify state
    ctx.markDirty();                 // Trigger render
    return c.hermes_value_create_undefined(runtime);
}
```

### Tested APIs

The dirty flag pattern is implemented and tested in:

- ✅ **vim.motion.*** (16 functions) - `motion_api.zig`
- ✅ **cursor API** (setCursorRenderPosition, clearCursorRenderPosition) - `cursor_api.zig:84,107`
- ✅ **config API** (setHighlight, setOption, setOptionWithScope) - `config_api.zig:89,255,450`

### Tests

See `src/editor/editor_test.zig` for unit tests verifying the dirty flag mechanism works correctly across operations.
