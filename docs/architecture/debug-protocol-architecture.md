# Debug Protocol Architecture

## Overview

Vimcraft's debug protocol allows external tools to query and control the editor through a JSON-RPC interface. The protocol supports two modes:

1. **Headless Mode** (`--debug-protocol`): Stdin/stdout communication for automated testing
2. **Terminal Mode** (`VIMC_DEBUG_SOCKET=1`): Unix socket for live debugging while editor runs

## Implementation Status

### Current Architecture (Dual Implementation)

After investigation, we maintain **two separate implementations** for valid architectural reasons:

```
src/backends/debug/
├── server.zig              # Headless mode server (30+ commands)
│   └── Uses: EditorContext (headless editor with integrated Display)
│
src/backends/terminal/
└── debug_socket.zig        # Terminal mode server (6 commands + get_terminal_updates)
    └── Uses: Terminal Editor + Display (separate instances)
```

### Why Two Implementations?

**Type Incompatibility**:
- Terminal mode uses `Editor` struct (src/editor/editor.zig)
- Headless mode uses `EditorContext` struct (src/backends/debug/editor_context.zig)
- These have **different internal types** (Pending Command, PendingRegister, CommandBuffer defined separately)
- Cannot create simple wrapper without deep copying or extensive refactoring

**Different Lifecycles**:
- Terminal mode: Editor + Display created separately, live in main event loop
- Headless mode: EditorContext owns both editor and display, manages lifecycle

**Trade-offs Accepted**:
- ✅ **Pros**: Clean separation, no type hacks, each mode optimized for its use case
- ❌ **Cons**: 233 lines of duplication (12.5% of debug protocol codebase)

### Commands Supported

**Headless Mode** (server.zig): 30+ commands
- All query commands (get_state, get_cursor, get_layers, get_terminal_updates, etc.)
- Mutation commands (execute_keys, load_file, set_buffer, set_option)
- Assertion commands (assert_cursor, assert_mode, etc.)

**Terminal Mode** (debug_socket.zig): 6 read-only commands
- `ping` - Health check
- `get_state` - Full editor snapshot
- `get_cursor` - Cursor position
- `get_mode` - Current mode
- `get_gutter_state` - Gutter configuration
- `get_terminal_updates` - ✨ NEW: ANSI rendering output (added in this session)

### Key Improvement: get_terminal_updates

The `get_terminal_updates` command was added to BOTH implementations in this session:

**Purpose**: Captures raw compositor updates + simulated ANSI terminal output for debugging rendering bugs

**Response Structure**:
```json
{
  "raw_updates": [{row, col, char, fg, bg, bold, italic, underline}],
  "update_count": 1920,
  "ansi_bytes": "\\x1b[1;1HHello...",
  "ansi_breakdown": [
    {"seq": "\\x1b[1;1H", "desc": "Move cursor to row=0, col=0"},
    {"seq": "H", "desc": "Write char 'H' (U+0048)"}
  ],
  "optimizations": {
    "adjacent_cells_skipped": 1896,
    "attribute_changes_deduped": 42,
    "char_zero_to_space": 15
  }
}
```

**Usage**: Debug gutter bugs, cursor positioning, colors, performance issues

## Alternative Considered: Full Unification

We investigated unifying both implementations into a single Server, but encountered fundamental blockers:

1. **Type Mismatch**: Cannot cast Editor → EditorContext without extensive refactoring
2. **Shallow Copy Issue**: Struct assignment copies values, creating shared ArrayList pointers → dangling pointer risk
3. **Complexity**: Would require generic Server or trait-based abstraction → over-engineering

**Principal Engineer Recommendation**: Accept dual implementation, reduce duplication via shared handler extraction if needed in future.

## Future Improvements

If duplication becomes problematic (>20% of codebase), consider:

1. **Extract Shared Handlers**: Move command logic to `src/backends/debug/handlers.zig`
   - Both servers call shared functions
   - Reduces duplication from 233 to ~50 lines

2. **Adapter Pattern**: Create EditorAdapter interface
   - `HeadlessAdapter`: Wraps EditorContext
   - `TerminalAdapter`: Wraps Editor + Display
   - Server becomes generic over adapter type

3. **Unify Types**: Merge Editor and EditorContext into single type
   - Requires significant refactoring across codebase
   - Benefits beyond debug protocol unclear

## Conclusion

**Current Status**: Dual implementation with `get_terminal_updates` available in both modes

**Decision**: Maintain separate implementations - the 12.5% duplication is acceptable given type incompatibility

**Success Metric**: ✅ Both modes support full debug protocol functionality needed for development

---

**Last Updated**: December 2025
**Status**: Implemented and tested
