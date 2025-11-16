# Refactor Phase 1: Critical Architecture Fixes Before Feature Scaling

## Executive Summary

Before adding Phase 4 features (plugin system, vim.opt, keymaps), we need to fix critical architectural issues that will become exponentially harder to fix later. This document outlines the must-fix issues and provides a concrete action plan.

## Why Refactor Now?

### Cost Analysis
- **Fix now**: ~1 week of focused work
- **Fix after plugins**: ~1 month (breaking plugin API, migration pain)
- **Fix after LSP**: ~2-3 months (complete event system rewrite)
- **Never fix**: Permanent technical debt, memory leaks in production

### Risk Matrix
| Issue | Current Impact | Future Impact | Fix Complexity |
|-------|---------------|---------------|----------------|
| Memory leaks | Users lose data | Plugin crashes | Low (1-2 days) |
| Layer violations | Hard to test | Can't swap backends | Medium (2-3 days) |
| No event system | 10ms input lag | Can't do LSP/async | High (3-4 days) |
| Memory ownership | Confusing | Crashes at scale | Low (1 day) |

## Critical Issues

### 🔴 Issue #1: Systematic Memory Leaks in Delete Operations

**The Problem**: Every delete/change operation frees the deleted text without storing it in registers. This breaks Vim's fundamental behavior where deleted text is accessible via registers.

**Current Bad Pattern** (repeated 20+ times):
```zig
// In editor.zig lines 355-357, 360-362, etc.
'd' => { // dd - delete line
    const result = try self.edit_ops.deleteCurrentLine(&self.buffer);
    defer self.allocator.free(result.deleted_text);
    // TODO: Store in register  <-- NEVER IMPLEMENTED!
}
```

**Why This Matters**:
- Violates Vim behavior (deleted text should go to registers)
- Memory allocated then immediately freed without being used
- Users can't recover deleted text with `p` after restart
- Shows systematic problem that will spread to new features

**Proposed Fix**:
```zig
/// Executes a delete operation and stores result in appropriate register
/// Takes ownership of the deleted text (no need for caller to free)
fn executeDeleteOperation(
    self: *Editor,
    comptime deleteFn: anytype,
    register_mode: RegisterMode,
) !void {
    const result = try deleteFn(&self.buffer);
    const reg = self.pending_register.getSelected() orelse '"';

    // Transfer ownership to register manager
    try self.register_mgr.store(reg, result.deleted_text, register_mode);
    // No defer free needed - register owns the memory now

    self.pending_register.clear();
}
```

### 🔴 Issue #2: Core Layer Depends on Backend Layer

**The Problem**: The core editor imports backend-specific types, violating dependency inversion principle.

**Current Violations**:
```zig
// In src/editor/editor.zig lines 6-7
const VisualState = @import("../backends/terminal/visual/visual.zig").VisualState;
const YankHighlight = @import("../backends/terminal/visual/yank_highlight.zig").YankHighlight;
```

**Why This Matters**:
- Can't compile editor without terminal backend
- Can't unit test editor in isolation
- Can't add alternative backends (GUI, web)
- Circular dependency waiting to happen

**Dependency Graph (WRONG)**:
```
editor/editor.zig
    ↓ imports
backends/terminal/visual/  ← This is backwards!
```

**Proposed Fix**:
```
src/editor/
  ├── visual/
  │   ├── state.zig        # VisualState (core concept)
  │   └── highlight.zig    # YankHighlight (core concept)
  └── editor.zig           # Imports from visual/

backends/terminal/
  └── visual/               # Terminal-specific rendering using core types
```

### 🟡 Issue #3: Blocking Synchronous I/O

**The Problem**: Main loop blocks for 10ms on every iteration, preventing async operations.

**Current Code**:
```zig
// main.zig line 195
running = try backend.handleInput(10, &needs_render);  // Blocks 10ms!
```

**Why This Matters**:
- Can't handle LSP responses while waiting for input
- Can't implement timers for animations
- Can't monitor file changes
- 10ms latency on every operation

**Proposed Event System**:
```zig
pub const EventSource = enum {
    Stdin,
    Timer,
    LSP,
    FileWatcher,
    Plugin,
};

pub const Event = union(EventSource) {
    Stdin: []const u8,
    Timer: TimerId,
    LSP: LspMessage,
    FileWatcher: FileChange,
    Plugin: PluginMessage,
};

pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    sources: std.ArrayList(*EventSource),
    pending: std.fifo.LinearFifo(Event, .Dynamic),

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        return .{
            .allocator = allocator,
            .sources = std.ArrayList(*EventSource).init(allocator),
            .pending = std.fifo.LinearFifo(Event, .Dynamic).init(allocator),
        };
    }

    pub fn addSource(self: *EventLoop, source: *EventSource) !void {
        try self.sources.append(source);
    }

    /// Poll all sources, return immediately if event available
    pub fn poll(self: *EventLoop, timeout_ms: i32) !?Event {
        // Check pending events first
        if (self.pending.readItem()) |event| {
            return event;
        }

        // Poll all sources with timeout
        // ... poll implementation

        return self.pending.readItem();
    }
};
```

### 🟡 Issue #4: Inconsistent Memory Ownership

**The Problem**: No clear rules about who owns allocated memory.

**Examples of Confusion**:
```zig
// Who owns the returned text?
fn deleteWord(self: *EditOps, buffer: *Buffer) !DeleteResult  // Caller frees?
fn yankWord(self: *EditOps, buffer: *Buffer) ![]u8           // Caller frees?
fn store(self: *RegisterManager, text: []u8) !void            // Register owns?
```

**Proposed Documentation Standard**:
```zig
/// Deletes word at cursor position.
/// Returns: Allocated text that CALLER must free.
/// Example:
///   const result = try ops.deleteWord(buffer);
///   defer allocator.free(result.deleted_text);
pub fn deleteWord(self: *EditOps, buffer: *Buffer) !DeleteResult

/// Stores text in register.
/// Takes ownership of text parameter - do NOT free after calling.
/// Example:
///   const text = try allocator.dupe(u8, "hello");
///   try mgr.store('a', text);  // mgr now owns text
pub fn store(self: *RegisterManager, register: u8, text: []u8) !void
```

## Implementation Plan

### Phase 1: Fix Memory Leaks (Days 1-2)

**Goal**: Ensure all deleted text is properly stored in registers.

**TODO List**:

- [ ] **Task 1.1**: Create helper function in editor.zig
  ```zig
  // Add after line 591 in editor.zig
  fn executeDeleteOperation(
      self: *Editor,
      deleteFn: fn(*Buffer) anyerror!DeleteResult,
      mode: RegisterMode,
  ) !void {
      const result = try deleteFn(&self.buffer);
      const reg = self.pending_register.getSelected() orelse '"';
      try self.register_mgr.store(reg, result.deleted_text, mode);
      self.pending_register.clear();
  }
  ```

- [ ] **Task 1.2**: Update all 'd' command handlers
  ```zig
  // Replace lines 355-358
  'd' => { // dd - delete line
      try self.executeDeleteOperation(
          EditOps.deleteCurrentLine,
          .line_wise
      );
  },
  ```

- [ ] **Task 1.3**: Update all 'c' command handlers
  ```zig
  // Replace lines 384-388
  'c' => { // cc - change line
      try self.executeDeleteOperation(
          EditOps.deleteCurrentLine,
          .line_wise
      );
      self.enterInsertMode();
  },
  ```

- [ ] **Task 1.4**: Add test verifying register storage
  ```zig
  test "deleted text goes to register" {
      var editor = try Editor.init(allocator);
      defer editor.deinit();

      try editor.buffer.setContent("hello world");
      try editor.executeKeys("dd");

      const reg_content = editor.register_mgr.get('"');
      try expect(reg_content != null);
      try expectEqualStrings("hello world", reg_content.?);
  }
  ```

### Phase 2: Fix Layer Violations (Days 3-4)

**Goal**: Move visual concepts from backend to core.

**TODO List**:

- [ ] **Task 2.1**: Create core visual module structure
  ```bash
  mkdir -p src/editor/visual
  ```

- [ ] **Task 2.2**: Move VisualState to core
  ```bash
  # Move and update imports
  mv src/backends/terminal/visual/visual.zig src/editor/visual/state.zig

  # Update the moved file's imports to use relative paths
  # Remove any terminal-specific code
  ```

- [ ] **Task 2.3**: Extract core YankHighlight interface
  ```zig
  // src/editor/visual/highlight.zig
  pub const YankHighlight = struct {
      start: Position,
      end: Position,
      mode: HighlightMode,
      timestamp: i64,
      duration_ms: i64 = 200,

      pub fn init(start: Position, end: Position, mode: HighlightMode) YankHighlight {
          return .{
              .start = start,
              .end = end,
              .mode = mode,
              .timestamp = std.time.milliTimestamp(),
          };
      }

      pub fn isVisible(self: *const YankHighlight) bool {
          const now = std.time.milliTimestamp();
          return (now - self.timestamp) < self.duration_ms;
      }
  };
  ```

- [ ] **Task 2.4**: Update all imports
  ```zig
  // In src/editor/editor.zig, replace lines 6-7
  const VisualState = @import("visual/state.zig").VisualState;
  const YankHighlight = @import("visual/highlight.zig").YankHighlight;
  ```

- [ ] **Task 2.5**: Create backend adapters
  ```zig
  // src/backends/terminal/visual/renderer.zig
  const core = @import("../../../editor/visual/state.zig");

  pub fn renderVisualSelection(
      state: core.VisualState,
      // ... terminal specific params
  ) void {
      // Terminal-specific rendering using core types
  }
  ```

### Phase 3: Event System Foundation (Days 5-7)

**Goal**: Replace blocking I/O with event-driven architecture.

**TODO List**:

- [ ] **Task 3.1**: Create event system module
  ```zig
  // src/core/event.zig
  pub const EventLoop = struct {
      // Implementation from above
  };
  ```

- [ ] **Task 3.2**: Create stdin event source
  ```zig
  // src/core/event/stdin.zig
  pub const StdinSource = struct {
      fd: std.fs.File.Handle,
      buffer: [256]u8 = undefined,

      pub fn poll(self: *StdinSource, timeout_ms: i32) !?[]const u8 {
          // Non-blocking read implementation
      }
  };
  ```

- [ ] **Task 3.3**: Integrate with main loop
  ```zig
  // main.zig
  var event_loop = try EventLoop.init(allocator);
  defer event_loop.deinit();

  var stdin_source = StdinSource{ .fd = std.io.getStdIn().handle };
  try event_loop.addSource(&stdin_source);

  while (running) {
      if (try event_loop.poll(10)) |event| {
          switch (event) {
              .Stdin => |input| try backend.handleInput(input, &needs_render),
              .Timer => |id| try backend.handleTimer(id),
              // ... other event types
          }
      }

      if (needs_render) {
          try backend.render();
          needs_render = false;
      }
  }
  ```

- [ ] **Task 3.4**: Add timer support
  ```zig
  pub const TimerSource = struct {
      timers: std.AutoHashMap(TimerId, Timer),
      next_id: TimerId = 0,

      pub fn addTimer(self: *TimerSource, duration_ms: i64) !TimerId {
          const id = self.next_id;
          self.next_id += 1;
          try self.timers.put(id, Timer{
              .deadline = std.time.milliTimestamp() + duration_ms,
          });
          return id;
      }
  };
  ```

### Phase 4: Document Memory Ownership (Day 8)

**Goal**: Clear documentation of memory ownership rules.

**TODO List**:

- [ ] **Task 4.1**: Create ownership documentation
  ```markdown
  // docs/architecture/memory-ownership.md
  # Memory Ownership Rules

  ## Principles
  1. Functions that allocate must document who frees
  2. Functions that take ownership must document it
  3. Use consistent naming: `dupe`, `alloc`, `owned` prefixes

  ## Patterns
  ...
  ```

- [ ] **Task 4.2**: Annotate all allocating functions
  ```zig
  /// Returns: Newly allocated string. Caller owns memory.
  pub fn getAllocatedString(self: *Self) ![]u8

  /// Takes ownership of `text`. Do not free after calling.
  pub fn takeOwnership(self: *Self, text: []u8) !void

  /// Returns: Slice into internal buffer. Do NOT free.
  pub fn getBorrowedSlice(self: *Self) []const u8
  ```

- [ ] **Task 4.3**: Add ownership tests
  ```zig
  test "register takes ownership of text" {
      var mgr = RegisterManager.init(allocator);
      defer mgr.deinit();

      const text = try allocator.dupe(u8, "test");
      try mgr.store('a', text);
      // Do NOT free text here - mgr owns it

      // Verify mgr frees it on deinit
  }
  ```

## Success Criteria

### Memory Leaks Fixed
- [ ] All delete operations store text in registers
- [ ] No TODOs about storing in registers remain
- [ ] Tests verify deleted text is recoverable

### Layer Violations Fixed
- [ ] Editor compiles without backend imports
- [ ] Can unit test editor without terminal
- [ ] Clear core → backend dependency flow

### Event System Working
- [ ] No blocking I/O in main loop
- [ ] Can handle multiple event sources
- [ ] Sub-10ms response time to input

### Memory Ownership Clear
- [ ] All allocating functions documented
- [ ] No confusion about who frees what
- [ ] Consistent patterns throughout codebase

## Testing Strategy

### Unit Tests
```bash
# After each phase
zig build test

# Specific test targets
zig test src/editor/editor.zig
zig test src/editor/register/register.zig
```

### Integration Tests
```bash
# Test with debug protocol
echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}' | ./zig-out/bin/vimcraft --debug-protocol
```

### Memory Leak Detection
```bash
# Run with Valgrind (Linux/Mac)
valgrind --leak-check=full ./zig-out/bin/vimcraft test.txt

# Use Zig's built-in allocator debugging
zig build -Doptimize=Debug
```

## Timeline

| Phase | Duration | Priority | Blocking? |
|-------|----------|----------|-----------|
| Fix Memory Leaks | 2 days | CRITICAL | Yes - blocks Phase 4 |
| Fix Layer Violations | 2 days | CRITICAL | Yes - blocks testing |
| Event System | 3 days | HIGH | Yes - blocks LSP |
| Documentation | 1 day | MEDIUM | No |

**Total: 8 days** (with buffer)

## Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing features | Medium | High | Comprehensive test suite first |
| Event system complexity | High | Medium | Start simple, iterate |
| Merge conflicts | Low | Low | Work on separate branch |

## Conclusion

These refactors are **non-negotiable** if we want a maintainable codebase. The memory leaks in particular show a systematic problem that needs fixing before it spreads to plugin APIs.

The good news: All of these fixes are straightforward and will make the codebase significantly more robust. Let's tackle them systematically and build on a solid foundation!