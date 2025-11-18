# Terminal Backend Debugging

## Problem

The debug protocol (`--debug-protocol`) only works in headless mode. When running the terminal backend interactively, we can't use stdin/stdout for debugging because they're being used by the terminal itself.

## Solution: Unix Domain Socket Debug Server

Run a debug protocol server on a Unix socket alongside the terminal backend. This allows querying editor state without interfering with terminal I/O.

### Architecture

```
┌─────────────────────────────────────┐
│  Terminal Backend (vimc /tmp/file)  │
│  ┌──────────────┐  ┌──────────────┐ │
│  │   Terminal   │  │ Debug Server │ │
│  │     I/O      │  │ (Unix Socket)│ │
│  │  (tty/stdin) │  │/tmp/vimc.sock│ │
│  └──────────────┘  └──────────────┘ │
│         │                  │         │
│         │                  │         │
│    Editor State ───────────┘         │
└─────────────────────────────────────┘
          │                  │
          ▼                  ▼
    User keystrokes    Debug client
    (normal editing)   (query state)
```

### Usage

#### Start editor with debug socket:
```bash
vimc --debug-socket /tmp/test.txt
# Creates Unix socket at /tmp/vimc.sock
```

#### Query from another terminal:
```bash
# Send JSON command to socket
echo '{"cmd":"get_state","id":"1"}' | nc -U /tmp/vimc.sock

# Or use a helper script
./tools/vimc-debug get_state
./tools/vimc-debug get_gutter_state
```

### Implementation Plan

1. **Add socket server to runEditor()** - Start debug server in background thread
2. **Reuse existing protocol** - Same JSON-RPC commands as `--debug-protocol`
3. **Thread safety** - Read-only queries (no state mutation from debug client)
4. **Socket cleanup** - Remove socket file on exit

### Debug Commands for Gutter Investigation

```bash
# Check gutter state
echo '{"cmd":"get_gutter_state","id":"1"}' | nc -U /tmp/vimc.sock

# Response:
{
  "gutter_width": 2,
  "cached_line_count": 1,
  "columns": [
    {"name": "line_numbers", "enabled": true, "cached_width": 2, "cache_key": 0}
  ],
  "line_number_config": {"number": true, "relative_number": false},
  "sign_column_config": {"mode": "yes"}
}
```

### Benefits

- **Non-intrusive** - Doesn't interfere with terminal rendering
- **On-demand** - Query only when needed
- **Same protocol** - Reuses existing debug protocol infrastructure
- **Fast** - Local socket communication
- **Safe** - Read-only queries by default

### Next Steps

1. Create `src/backends/terminal/debug_socket.zig`
2. Add `get_gutter_state` command to protocol
3. Create helper script `tools/vimc-debug`
4. Test with gutter bug investigation
