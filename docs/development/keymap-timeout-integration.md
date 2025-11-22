# Keymap Timeout Integration Guide (Phase 4.5)

**Status**: Infrastructure Complete ✅ | setTimeout Integration Pending 📅

**Date**: December 2025

## Overview

This document describes how to integrate setTimeout-based timeouts for pending keymap states in Phase 4.5. The core pending key accumulation infrastructure is complete (see `src/editor/keymap/keymap.zig:232-259`), but timeout behavior is deferred until the timer system is fully operational.

## Current State (Phase 4)

### What Works Now

1. **Pending State Accumulation** (`keymap.zig:232-259`):
   - `lookup()` returns `LookupResult.pending` for partial matches
   - Pending keys accumulated in `KeymapManager.pending_keys`
   - ESC cancels pending state

2. **Editor Integration** (`editor.zig:285-337`):
   - `handleNormalMode()` handles `.pending` result by returning early
   - ESC handler clears pending state via `clearPending()`

3. **Test Coverage** (`keymap.zig:558-598`):
   - Test "hasPrefix detects ambiguous mappings (j vs jk)" validates pending behavior

### What's Deferred to Phase 4.5

- **Timeout Mechanism**: Start timer when `.pending` returned
- **Timeout Behavior**: Execute first pending key as literal when timer fires
- **Timer Cancellation**: Cancel timer when next key pressed or ESC pressed

## Phase 4.5 Implementation Plan

### 1. Add Timer ID to KeymapManager

**File**: `src/editor/keymap/keymap.zig`

**Changes**:

```zig
pub const KeymapManager = struct {
    allocator: std.mem.Allocator,
    mappings: std.StringHashMap(KeymapEntry),
    pending_keys: std.ArrayList(u8),

    /// Timer ID for pending key timeout (null if no timer active)
    /// When timer fires → execute first pending key as literal
    pending_timer_id: ?usize,  // <-- ADD THIS FIELD
```

**Update Methods**:

```zig
pub fn init(allocator: std.mem.Allocator) KeymapManager {
    return .{
        .allocator = allocator,
        .mappings = std.StringHashMap(KeymapEntry).init(allocator),
        .pending_keys = std.ArrayList(u8){},
        .pending_timer_id = null,  // <-- ADD THIS
    };
}

pub fn clearPending(self: *KeymapManager) void {
    self.pending_keys.clearRetainingCapacity();

    // Cancel active timer if any
    if (self.pending_timer_id) |timer_id| {
        __nativeClearTimer(timer_id);  // <-- ADD THIS
        self.pending_timer_id = null;
    }
}
```

### 2. Expose Timeout Setting

**File**: `src/editor/config/options.zig` (to be created) or add to existing options system

**Add Option**:

```zig
/// Timeout in milliseconds for keymap pending state
/// Neovim default: 1000ms (vim.opt.timeoutlen)
pub const timeoutlen: u32 = 1000;
```

**JavaScript API** (for user configuration):

```javascript
// User can configure in index.js:
vim.opt.timeoutlen = 500;  // 500ms timeout (faster than default)
```

### 3. Modify handleNormalMode() for Timeout

**File**: `src/editor/editor.zig`

**Current Code** (lines 329-334):

```zig
.pending => {
    // Partial match - waiting for more keys
    // NOTE: setTimeout timeout integration happens in Phase 4.5
    // For now, just return and wait for next key
    // User can press ESC to cancel (Step 4)
    return;
},
```

**Phase 4.5 Code** (replace above):

```zig
.pending => {
    // Partial match - waiting for more keys
    // Start timeout timer (Neovim behavior: execute first key as literal on timeout)

    // Cancel any existing timer first
    if (self.keymap_mgr.pending_timer_id) |old_timer_id| {
        __nativeClearTimer(old_timer_id);
    }

    // Start new timer
    const timeout_ms = self.config.timeoutlen;  // Get from vim.opt.timeoutlen
    const timer_id = try self.startKeymapTimeout(timeout_ms);
    self.keymap_mgr.pending_timer_id = timer_id;

    return;
},
```

### 4. Add Timeout Callback

**File**: `src/editor/editor.zig`

**New Method**:

```zig
/// Start timeout for pending keymap state
/// When timer fires → execute first pending key as literal
fn startKeymapTimeout(self: *Editor, timeout_ms: u32) !usize {
    // This will call JavaScript setTimeout via JSI
    // Return timer ID for cancellation

    // Pseudo-code (actual JSI integration depends on timer system design):
    // 1. Create callback that calls self.handleKeymapTimeout()
    // 2. Register callback with JavaScript runtime
    // 3. Call setTimeout(callback, timeout_ms)
    // 4. Return timer ID

    // TODO: Implement when timer system JSI bridge is ready
    return error.NotImplemented;
}

/// Called when keymap timeout fires
/// Behavior: Execute first pending key as literal, clear pending state
fn handleKeymapTimeout(self: *Editor) !void {
    if (self.keymap_mgr.pending_keys.items.len == 0) {
        // No pending keys (race condition or already cleared)
        return;
    }

    // Get first pending key
    const first_key = self.keymap_mgr.pending_keys.items[0..1];

    // Clear pending state (including timer ID)
    self.keymap_mgr.clearPending();

    // Execute first key as literal (bypass keymap lookup)
    // This matches Neovim behavior: timeout → treat as literal key
    try self.handleBuiltinCommand(first_key);
}

/// Execute key as built-in command (bypass keymap lookup)
fn handleBuiltinCommand(self: *Editor, input: []const u8) !void {
    // This is the existing code path after keymap lookup fails
    // Extract it into a separate method for reuse

    // TODO: Refactor existing built-in command handling into this method
}
```

### 5. Cancel Timer on Next Key Press

**File**: `src/editor/editor.zig`

**Modify** `handleNormalMode()` start (lines 276-280):

```zig
fn handleNormalMode(self: *Editor, input: []const u8) !void {
    // Cancel pending timer on ANY new key press
    if (self.keymap_mgr.pending_timer_id) |timer_id| {
        __nativeClearTimer(timer_id);
        self.keymap_mgr.pending_timer_id = null;
    }

    // ESC cancels pending keymap state
    if (input.len == 1 and input[0] == 27) { // ESC
        self.keymap_mgr.clearPending();  // This also cancels timer
        // ... rest of ESC handling
    }
```

### 6. JSI Integration Points

**File**: `src/system/jsi/timer_api.zig` (to be created or add to existing JSI module)

**Required Native Functions**:

```zig
/// Start a timer that calls handleKeymapTimeout() after delay_ms
export fn startKeymapTimer(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // 1. Extract delay_ms from args[0]
    // 2. Store Editor* context for callback
    // 3. Call JavaScript setTimeout via JSI
    // 4. Return timer ID as number
}

/// Cancel a timer by ID
export fn cancelKeymapTimer(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // 1. Extract timer_id from args[0]
    // 2. Call JavaScript clearTimeout(timer_id)
}
```

**JavaScript Side** (already exists in `runtime.js:22-44`):

```javascript
// These are already implemented and working!
globalThis.setTimeout = function(callback, delay) {
  const id = globalThis._nextTimerId++;
  globalThis._timerCallbacks[id] = callback;
  __nativeSetTimeout(id, delay || 0);
  return id;
};

globalThis.clearTimeout = function(id) {
  delete globalThis._timerCallbacks[id];
  __nativeClearTimer(id);
};
```

**Integration Pattern** (Zig calls JavaScript):

```zig
// In startKeymapTimeout():
// 1. Create Hermes function value from Editor.handleKeymapTimeout
const callback = try createHermesCallback(runtime, handleKeymapTimeout, @ptrCast(self));

// 2. Call JavaScript setTimeout
const timeout_val = c.hermes_value_create_number(runtime, @floatFromInt(timeout_ms));
defer c.hermes_value_destroy(timeout_val);

const set_timeout_fn = c.hermes_get_global_property(runtime, "setTimeout");
defer c.hermes_value_destroy(set_timeout_fn);

const args = [_]?*c.OVHermesValue{ callback, timeout_val };
const timer_id_val = c.hermes_call_function(runtime, set_timeout_fn, null, &args, 2);
defer c.hermes_value_destroy(timer_id_val);

// 3. Extract and return timer ID
const timer_id = c.hermes_value_get_number(timer_id_val);
return @intFromFloat(timer_id);
```

## Testing Strategy

### Unit Tests (Zig)

**File**: `src/editor/keymap/keymap.zig`

**Add Tests**:

```zig
test "KeymapManager: pending state cleared on timeout" {
    // 1. Setup "jk" mapping
    // 2. Type "j" → verify pending state
    // 3. Simulate timeout firing
    // 4. Verify pending state cleared
    // 5. Verify first key "j" executed as literal
}

test "KeymapManager: timer canceled on next key press" {
    // 1. Setup "jk" mapping
    // 2. Type "j" → verify timer started
    // 3. Type "k" before timeout
    // 4. Verify timer canceled
    // 5. Verify "jk" mapping executed
}

test "KeymapManager: timer canceled on ESC" {
    // 1. Setup "jk" mapping
    // 2. Type "j" → verify timer started
    // 3. Press ESC
    // 4. Verify timer canceled
    // 5. Verify pending state cleared
}
```

### Integration Tests (E2E)

**File**: `tests/e2e/keymap_timeout/e2e.ts`

```typescript
// Test keymap timeout behavior via E2E tests

vim.e2e.describe("Keymap Timeout", function() {
    vim.e2e.test("timeout fires - execute first key as literal", function() {
        // Type "j" which is prefix of "jk" mapping
        vim.e2e.keys("j");

        // Wait for timeout (default 1000ms)
        // After timeout, "j" should execute as down motion
        const state = vim.e2e.getState();
        vim.e2e.assert.true(state.cursor.line > 0, "j should have moved cursor down");
    });

    vim.e2e.test("next key before timeout - execute mapping", function() {
        // Type "jk" quickly (before timeout)
        vim.e2e.keys("jk");

        // Should execute "jk" mapping (e.g., ESC to normal mode)
        const mode = vim.e2e.getMode();
        vim.e2e.assert.equal(mode, "NORMAL", "jk mapping should execute");
    });
});

vim.e2e.runAll();
```

## Behavioral Specification

### Timeout Behavior (Neovim Compatible)

1. **Pending State Entered**:
   - User types key that is prefix of mapping (e.g., "j" when "jk" is mapped)
   - Timer started with duration = `vim.opt.timeoutlen` (default 1000ms)
   - Editor waits for next key

2. **Timeout Fires**:
   - First pending key executed as literal command
   - Remaining pending keys discarded
   - Pending state cleared
   - Example: "j" → move cursor down (built-in command)

3. **Next Key Pressed Before Timeout**:
   - Timer canceled
   - New key concatenated to pending keys
   - Keymap lookup performed on full sequence
   - If full match → execute mapping
   - If still prefix → restart timer
   - If no match → execute first key as literal

4. **ESC Pressed**:
   - Timer canceled
   - Pending state cleared
   - No command executed

### Edge Cases

1. **Multiple Pending States**:
   - Only one timer active at a time
   - New timer cancels old timer
   - Example: "j" → timer1 starts, "k" → timer1 canceled, "jk" matched

2. **Recursive Mappings**:
   - Timeout only applies to user input, not recursive execution
   - `mapping_depth` protects against infinite loops (max depth = 10)

3. **Mode Changes**:
   - Pending state cleared when mode changes
   - Timer canceled on mode change
   - Example: Normal→Insert clears pending "j"

## Implementation Checklist

**Prerequisites**:
- [ ] Timer system JSI bridge complete (`__nativeSetTimeout`, `__nativeClearTimer`)
- [ ] Options system supports `vim.opt.timeoutlen`
- [ ] Hermes callback creation helper (`createHermesCallback`)

**Phase 4.5 Tasks**:
- [ ] Add `pending_timer_id` field to `KeymapManager`
- [ ] Update `init()` and `clearPending()` methods
- [ ] Add `startKeymapTimeout()` method to Editor
- [ ] Add `handleKeymapTimeout()` callback to Editor
- [ ] Refactor built-in command handling into `handleBuiltinCommand()`
- [ ] Modify `handleNormalMode()` to start/cancel timers
- [ ] Add unit tests for timeout behavior
- [ ] Add E2E tests for timeout behavior
- [ ] Update documentation with timeout examples

## Migration Notes

**Backward Compatibility**: The current implementation (Phase 4) is fully functional without timeouts. Users can:
- Use ESC to cancel pending state manually
- Rely on immediate matching for unambiguous mappings
- Phase 4.5 adds convenience (automatic timeout) without breaking existing behavior

**User Experience**: With timeouts, Vimcraft will match Neovim's keymap behavior exactly, allowing users to type familiar key sequences without thinking about pending states.

## References

- **Architecture Decision**: `CLAUDE.md` (Helix-style stateful keymaps)
- **Current Implementation**: `src/editor/keymap/keymap.zig:232-259` (lookup method)
- **Editor Integration**: `src/editor/editor.zig:285-337` (handleNormalMode)
- **Timer Infrastructure**: `src/system/jsi/runtime.js:22-44` (setTimeout/clearTimeout)
- **Neovim Compatibility**: `:help timeout` and `:help timeoutlen` for reference behavior

---

**Status**: This document provides complete implementation guidance for Phase 4.5. All integration points are documented, test strategies defined, and behavioral specifications provided.
