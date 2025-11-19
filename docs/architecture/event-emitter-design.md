# Event Emitter Design (Phase 4 Critical Feature)

**Status**: 🚧 Implementation in progress
**Priority**: CRITICAL (blocker for autocommands)
**Effort**: 3-5 days
**Inspired by**: React Native JSI event system, Node.js EventEmitter

---

## Overview

Event emitters enable **Native → JavaScript** asynchronous communication, allowing Zig code to trigger JavaScript callbacks when editor events occur (buffer changes, mode switches, etc.).

**Critical for Phase 4**: Autocommands (`vim.on('BufEnter', ...)`) won't work without this.

---

## Architecture

### Design Pattern: Observer Pattern

```
┌─────────────────────┐
│  Native Code (Zig)  │
│                     │
│  buffer.loadFile()  │ ───┐
│  mode.enterInsert() │    │
│  cursor.move()      │    │
└─────────────────────┘    │
                           │ emit('BufEnter', args)
                           ↓
┌─────────────────────────────────────┐
│     EventEmitter (Zig)              │
│                                     │
│  events: StringHashMap(            │
│    ArrayList(CallbackRef)          │
│  )                                  │
│                                     │
│  "BufEnter" → [callback1, cb2, ...] │
│  "InsertLeave" → [callback3, ...]   │
└─────────────────────────────────────┘
                           │
                           │ call all callbacks
                           ↓
┌─────────────────────────────────────┐
│     JavaScript Callbacks            │
│                                     │
│  vim.on('BufEnter', (bufnr) => {   │
│      console.log('Enter buf', bufnr)│
│  });                                │
└─────────────────────────────────────┘
```

---

## Core Components

### 1. EventEmitter Struct (Zig)

```zig
// src/system/jsi/event_emitter.zig
const std = @import("std");
const c = @import("c_api.zig").c;

/// EventEmitter - manages event listeners and emission
pub const EventEmitter = struct {
    /// Map of event name → list of callbacks
    callbacks: std.StringHashMap(std.ArrayList(*c.OVHermesValue)),

    /// JSI runtime for calling callbacks
    runtime: *c.OVHermesRuntime,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) EventEmitter {
        return .{
            .callbacks = std.StringHashMap(std.ArrayList(*c.OVHermesValue)).init(allocator),
            .runtime = runtime,
            .allocator = allocator,
        };
    }

    /// Register a callback for an event
    pub fn on(self: *EventEmitter, event_name: []const u8, callback: *c.OVHermesValue) !void {
        // Get or create callback list for this event
        const entry = try self.callbacks.getOrPut(event_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayList(*c.OVHermesValue).init(self.allocator);
        }

        // Clone callback to keep reference alive
        const callback_clone = c.hermes_value_clone(self.runtime, callback);
        try entry.value_ptr.append(callback_clone);
    }

    /// Remove a callback for an event
    pub fn off(self: *EventEmitter, event_name: []const u8, callback: *c.OVHermesValue) !void {
        // Find and remove matching callback
        const list = self.callbacks.getPtr(event_name) orelse return;

        // TODO: Compare callbacks (need value equality check)
        // For now, remove all callbacks for this event
        for (list.items) |cb| {
            c.hermes_value_destroy(cb);
        }
        list.clearAndFree();
    }

    /// Emit an event with arguments
    pub fn emit(self: *EventEmitter, event_name: []const u8, args: []const *c.OVHermesValue) !void {
        const list = self.callbacks.get(event_name) orelse return; // No listeners

        // Call each registered callback
        for (list.items) |callback| {
            const result = c.hermes_call_function(
                self.runtime,
                callback,
                @constCast(args.ptr),
                args.len
            );

            if (result == null) {
                // Callback threw an error
                const err_msg = c.hermes_get_exception_message(self.runtime);
                std.debug.print("[EventEmitter] Callback error for '{s}': {s}\n", .{event_name, err_msg});
                // Continue calling other callbacks
                continue;
            }

            c.hermes_value_destroy(result);
        }
    }

    /// Remove all callbacks (called on config reload)
    pub fn removeAll(self: *EventEmitter) void {
        var iter = self.callbacks.valueIterator();
        while (iter.next()) |list| {
            for (list.items) |callback| {
                c.hermes_value_destroy(callback);
            }
            list.deinit();
        }
        self.callbacks.clearAndFree();
    }

    pub fn deinit(self: *EventEmitter) void {
        self.removeAll();
        self.callbacks.deinit();
    }
};
```

---

### 2. JavaScript API (vim.on / vim.off / vim.emit)

```javascript
// Exposed via HostObject in src/system/jsi/vim_api.zig

// Register event listener
vim.on('BufEnter', (bufnr) => {
    console.log('Entered buffer', bufnr);
});

// Remove event listener
vim.off('BufEnter', callback);

// Emit custom event (for testing / user events)
vim.emit('CustomEvent', arg1, arg2);
```

---

### 3. Host Function Implementations

```zig
// src/system/jsi/event_api.zig

/// vim.on(event_name, callback)
pub export fn eventOn(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (count < 2) return null;

    const rt = runtime orelse return null;
    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name (arg 0)
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Get callback (arg 1)
    const callback = args[1] orelse return null;

    // Register callback
    emitter.on(event_name, callback) catch {
        return c.hermes_value_create_undefined(rt);
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.off(event_name, callback)
pub export fn eventOff(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (count < 2) return null;

    const rt = runtime orelse return null;
    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Get callback
    const callback = args[1] orelse return null;

    // Remove callback
    emitter.off(event_name, callback) catch {
        return c.hermes_value_create_undefined(rt);
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.emit(event_name, ...args)
pub export fn eventEmit(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (count < 1) return null;

    const rt = runtime orelse return null;
    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name
    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Collect remaining args
    const event_args = args[1..count];

    // Emit event
    emitter.emit(event_name, event_args) catch {
        return c.hermes_value_create_undefined(rt);
    };

    return c.hermes_value_create_undefined(rt);
}
```

---

### 4. Integration with Editor

```zig
// src/editor/editor.zig

pub const Editor = struct {
    // ... existing fields ...

    /// Event emitter for autocommands
    event_emitter: ?*EventEmitter,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return Editor{
            // ... existing initialization ...
            .event_emitter = null, // Initialized when JSI runtime created
        };
    }

    /// Trigger autocommand event
    pub fn triggerAutocommand(self: *Editor, event: []const u8, args: anytype) void {
        const emitter = self.event_emitter orelse return; // No JSI runtime yet

        // Convert args to JSI values
        var jsi_args = std.ArrayList(*c.OVHermesValue).init(self.allocator);
        defer jsi_args.deinit();

        // Example: BufEnter with buffer number
        inline for (args) |arg| {
            const val = switch (@TypeOf(arg)) {
                usize => c.hermes_value_create_number(self.jsi_runtime, @floatFromInt(arg)),
                []const u8 => c.hermes_value_create_string(self.jsi_runtime, arg.ptr, arg.len),
                else => @compileError("Unsupported arg type"),
            };
            jsi_args.append(val) catch continue;
        }

        // Emit event
        emitter.emit(event, jsi_args.items) catch |err| {
            std.debug.print("[Editor] Failed to emit '{s}': {}\n", .{event, err});
        };

        // Clean up JSI values
        for (jsi_args.items) |val| {
            c.hermes_value_destroy(val);
        }
    }
};
```

---

## Autocommand Events (Neovim-compatible)

### Buffer Events
- `BufEnter` - After entering buffer
- `BufLeave` - Before leaving buffer
- `BufNew` - After creating new buffer
- `BufRead` - After reading buffer
- `BufWrite` - Before writing buffer
- `BufWritePost` - After writing buffer

### Insert Mode Events
- `InsertEnter` - Entering insert mode
- `InsertLeave` - Leaving insert mode
- `InsertChange` - Insert mode changed (e.g., i to a)

### Text Change Events
- `TextChanged` - Text changed in normal mode
- `TextChangedI` - Text changed in insert mode
- `TextYankPost` - After yank operation

### Mode Events
- `ModeChanged` - Mode changed (pattern: old_mode:new_mode)

### Window Events
- `WinEnter` - After entering window
- `WinLeave` - Before leaving window

### File Events
- `FileType` - File type detected

---

## Usage Examples

### Example 1: Auto-format on Save

```javascript
vim.on('BufWritePre', () => {
    // Format buffer before saving
    vim.lsp.buf.format({ async: false });
});
```

### Example 2: LSP Attach on File Type

```javascript
vim.on('FileType', (filetype) => {
    if (filetype === 'javascript' || filetype === 'typescript') {
        vim.lsp.start({
            name: 'tsserver',
            cmd: ['typescript-language-server', '--stdio'],
        });
    }
});
```

### Example 3: Incremental Parsing on Text Change

```javascript
let parseTimer = null;

vim.on('TextChanged', () => {
    // Debounce parsing
    if (parseTimer) clearTimeout(parseTimer);

    parseTimer = setTimeout(() => {
        const content = vim.buffer.getContent();
        const tick = vim.buffer.getChangedTick();

        // Parse in background...
        parser.parse(content).then(tree => {
            // Check buffer didn't change during parse
            if (vim.buffer.getChangedTick() === tick) {
                applyHighlighting(tree);
            }
        });
    }, 200);
});
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (Days 1-2)

1. ✅ Design architecture (this document)
2. Create `src/system/jsi/event_emitter.zig`
3. Implement EventEmitter struct with on/off/emit
4. Add to Editor struct
5. Basic unit tests

### Phase 2: JavaScript API (Day 3)

1. Create `src/system/jsi/event_api.zig`
2. Implement eventOn/eventOff/eventEmit host functions
3. Expose via vim HostObject
4. Test from JavaScript

### Phase 3: Autocommand Integration (Days 4-5)

1. Add triggerAutocommand() to Editor
2. Hook into buffer operations (loadFile → BufRead)
3. Hook into mode changes (enterInsert → InsertEnter)
4. Hook into text changes (insertChar → TextChanged)
5. Integration tests with real autocommands

---

## Testing Strategy

### Unit Tests (Zig)

```zig
test "EventEmitter: register and emit" {
    var emitter = EventEmitter.init(allocator, runtime);
    defer emitter.deinit();

    // Register callback
    const callback = createTestCallback();
    try emitter.on("TestEvent", callback);

    // Emit event
    const args = [_]*c.OVHermesValue{
        c.hermes_value_create_number(runtime, 42),
    };
    try emitter.emit("TestEvent", &args);

    // Verify callback was called
}
```

### Integration Tests (JavaScript)

```javascript
// Test event registration
let called = false;
vim.on('TestEvent', (arg) => {
    called = true;
    console.assert(arg === 42, "Wrong arg");
});

vim.emit('TestEvent', 42);
console.assert(called, "Callback not called");
```

---

## Performance Considerations

**Event Overhead**:
- Callback lookup: O(1) hash map access
- Callback invocation: O(n) where n = number of listeners
- Typical: 1-3 listeners per event → negligible overhead

**Memory**:
- Each callback: ~16 bytes (pointer + ref count)
- 100 autocommands × 2 events avg = ~3 KB total

**Optimization**: Lazy initialization - don't create EventEmitter until first `vim.on()` call.

---

## Error Handling

### Callback Errors

If a callback throws, catch and log but **continue calling other callbacks**:

```zig
if (result == null) {
    const err_msg = c.hermes_get_exception_message(self.runtime);
    std.debug.print("[EventEmitter] Error in '{s}' listener: {s}\n", .{event_name, err_msg});
    continue; // Don't stop other callbacks
}
```

### Event Emission Errors

Non-critical errors (missing event name, no listeners) fail silently.

---

## Lifecycle Management

### Config Reload

When config reloads, **clear all event listeners**:

```zig
pub fn reloadConfig(self: *Editor) !void {
    // Clear event listeners
    if (self.event_emitter) |emitter| {
        emitter.removeAll();
    }

    // Reload config (re-registers events)
    try self.loadConfig();
}
```

---

## Neovim Compatibility

### API Equivalence

| Vimcraft | Neovim | Notes |
|----------|--------|-------|
| `vim.on('BufEnter', cb)` | `vim.api.nvim_create_autocmd('BufEnter', {callback = cb})` | Simpler API |
| `vim.off('BufEnter', cb)` | Delete autocmd by ID | Different approach |
| `vim.emit('CustomEvent')` | `vim.api.nvim_exec_autocmds('User', {pattern = 'CustomEvent'})` | Compatible |

**Philosophy**: Vimcraft uses simpler EventEmitter pattern (like Node.js) instead of Neovim's autocmd groups/IDs.

---

## Future Enhancements (Phase 5+)

- **Event patterns**: `vim.on('BufEnter:*.js', cb)` - pattern matching
- **Once**: `vim.once('BufEnter', cb)` - auto-remove after first call
- **Priority**: `vim.on('BufEnter', cb, {priority: 100})` - execution order
- **Async events**: Support async callbacks with await

---

## Status

- ✅ **Design complete** (this document)
- 🚧 **Implementation in progress**
- ⏳ Days 1-2: Core infrastructure
- ⏳ Day 3: JavaScript API
- ⏳ Days 4-5: Autocommand integration
- ⏳ Testing and documentation

**Next**: Create `event_emitter.zig` and implement core struct.
