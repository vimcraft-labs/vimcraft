# Vimcraft Debug Protocol (ODP)

## Architecture

```
┌─────────────────┐     stdin/stdout JSON    ┌───────────────┐
│   Vimcraft       │ ←─────────────────────→  │  LLM (Claude) │
│   (--debug      │                           │               │
│    -protocol)   │                           │               │
│ • Editor core   │  Queries/Commands/Events │ • Parse JSON  │
│ • State export  │ ←────────────────────→   │ • Understand  │
│ • Debug hooks   │                           │ • Iterate     │
│ • Event stream  │                           │ • Verify      │
└─────────────────┘                           └───────────────┘
```

**MCP-Style Communication**: Direct stdin/stdout JSON-RPC between Vimcraft and LLM, no intermediate tools needed.

## Design Principles

1. **LLM-First**: All output designed for easy LLM parsing
2. **Structured Data**: JSON everywhere (no parsing strings)
3. **Type-Safe**: Zig types serialize to JSON schema
4. **Deterministic**: Same input → same output (for testing)
5. **Efficient**: Zero-copy where possible, fast IPC
6. **Introspectable**: Full editor state available
7. **Event-Driven**: Subscribe to editor events

## Communication Protocol

### Transport Layer

**stdin/stdout (MCP-Style)**
```bash
# Start Vimcraft in debug protocol mode
./vimcraft --debug-protocol

# Send JSON commands via stdin
echo '{"cmd":"get_state","id":"1"}'

# Read JSON responses from stdout
{"status":"ok","result":{...},"id":"1"}
```

**Characteristics**:
- Simple, no socket setup
- Works in any environment
- Same pattern as MCP (Model Context Protocol)
- Direct LLM-to-editor communication

### Message Format

```json
{
  "id": "unique-request-id",
  "cmd": "command_name",
  "args": { /* command-specific */ },
  "timestamp": 1234567890
}
```

Response:
```json
{
  "id": "unique-request-id",
  "status": "ok" | "error",
  "result": { /* command-specific */ },
  "error": "error message if status=error",
  "timestamp": 1234567891,
  "duration_ns": 1000
}
```

## Core Commands

### 1. State Queries

#### `get_state` - Full Editor State
```json
Request:
{
  "cmd": "get_state"
}

Response:
{
  "status": "ok",
  "result": {
    "mode": "NORMAL" | "INSERT" | "VISUAL" | "VISUAL_LINE" | "VISUAL_BLOCK",
    "cursor": {"line": 5, "col": 10},
    "buffer": {
      "path": "/path/to/file.txt",
      "lines": ["line 1", "line 2", ...],
      "modified": false,
      "line_count": 100
    },
    "visual": {
      "active": true,
      "mode": "char" | "line" | "block",
      "anchor": {"line": 5, "col": 5}
    },
    "registers": {
      "\"": {"lines": ["text"], "type": "char"},
      "a": {"lines": ["more"], "type": "line"},
      ...
    }
  }
}
```

#### `get_cursor` - Cursor Position
```json
Request:  {"cmd": "get_cursor"}
Response: {"status": "ok", "result": {"line": 5, "col": 10}}
```

#### `get_visual` - Visual Selection
```json
Request: {"cmd": "get_visual"}
Response: {
  "status": "ok",
  "result": {
    "active": true,
    "mode": "char",
    "anchor": {"line": 5, "col": 5},
    "head": {"line": 5, "col": 10},
    "text": ["Hello"]
  }
}
```

#### `get_registers` - All Registers
```json
Request: {"cmd": "get_registers"}
Response: {
  "status": "ok",
  "result": {
    "\"": {"lines": ["last yank"], "type": "char", "timestamp": 123},
    "a": {"lines": ["register a"], "type": "line", "timestamp": 456},
    "1": {"lines": ["delete history 1"], "type": "char"},
    ...
  }
}
```

#### `get_register` - Specific Register
```json
Request: {"cmd": "get_register", "args": {"name": "a"}}
Response: {
  "status": "ok",
  "result": {
    "name": "a",
    "lines": ["content"],
    "type": "char",
    "width": 0,
    "timestamp": 1234567890
  }
}
```

### 2. Commands

#### `execute_keys` - Send Keystrokes
```json
Request: {
  "cmd": "execute_keys",
  "args": {"keys": "viw"}
}
Response: {
  "status": "ok",
  "result": {
    "keys_processed": 3,
    "final_state": { /* abbreviated state */ }
  }
}
```

#### `load_file` - Load File
```json
Request: {
  "cmd": "load_file",
  "args": {"path": "/tmp/test.txt"}
}
Response: {
  "status": "ok",
  "result": {"lines_loaded": 100}
}
```

### 3. Assertions (for Testing)

#### `assert_cursor` - Verify Cursor Position
```json
Request: {
  "cmd": "assert_cursor",
  "args": {"line": 5, "col": 10}
}
Response: {
  "status": "ok",  // or "error" if mismatch
  "result": {
    "expected": {"line": 5, "col": 10},
    "actual": {"line": 5, "col": 10},
    "match": true
  }
}
```

#### `assert_mode` - Verify Mode
```json
Request: {
  "cmd": "assert_mode",
  "args": {"mode": "VISUAL"}
}
Response: {
  "status": "ok",
  "result": {
    "expected": "VISUAL",
    "actual": "VISUAL",
    "match": true
  }
}
```

#### `assert_register` - Verify Register Content
```json
Request: {
  "cmd": "assert_register",
  "args": {"name": "a", "text": "expected"}
}
Response: {
  "status": "ok",
  "result": {
    "expected": "expected",
    "actual": "expected",
    "match": true
  }
}
```

### 4. Performance

#### `benchmark` - Measure Operation Performance
```json
Request: {
  "cmd": "benchmark",
  "args": {
    "operation": "yank_line",
    "iterations": 1000
  }
}
Response: {
  "status": "ok",
  "result": {
    "iterations": 1000,
    "total_ns": 12345678,
    "avg_ns": 12345,
    "avg_ms": 0.012,
    "min_ns": 10000,
    "max_ns": 20000,
    "within_target": true,
    "target_ms": 16
  }
}
```

## Event Stream

Vimcraft can emit events for debugging:

```json
{
  "type": "event",
  "name": "mode_changed",
  "data": {
    "old_mode": "NORMAL",
    "new_mode": "VISUAL",
    "timestamp": 1234567890
  }
}

{
  "type": "event",
  "name": "buffer_changed",
  "data": {
    "line": 5,
    "old_text": "Hello",
    "new_text": "Hello World",
    "timestamp": 1234567891
  }
}

{
  "type": "event",
  "name": "register_changed",
  "data": {
    "register": "a",
    "old_content": null,
    "new_content": {"lines": ["text"], "type": "char"},
    "timestamp": 1234567892
  }
}
```

## Usage Examples

### Basic Debugging

```bash
# Start Vimcraft in debug mode (background process)
$ ./vimcraft --debug-protocol &

# Send commands via stdin
$ echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'
# Response: {"status":"ok","result":{"lines_loaded":5},"id":"1"}

$ echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'
# Response: {"status":"ok","result":{"keys_processed":3},"id":"2"}

$ echo '{"cmd":"get_visual","id":"3"}'
# Response: {"status":"ok","result":{"active":true,"mode":"char",...},"id":"3"}
```

### Testing Workflow

```bash
# 1. Start Vimcraft
$ ./vimcraft --debug-protocol > /tmp/responses.jsonl &

# 2. Send test sequence
$ cat > /tmp/test_commands.jsonl << EOF
{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}
{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}
{"cmd":"assert_cursor","args":{"line":0,"col":3},"id":"3"}
{"cmd":"assert_mode","args":{"mode":"VISUAL"},"id":"4"}
EOF

# 3. Pipe commands
$ cat /tmp/test_commands.jsonl | ./vimcraft --debug-protocol

# 4. Parse responses (all JSON)
$ cat /tmp/responses.jsonl | jq '.status'
```

## Implementation Files

```
src/
├── debug/
│   ├── protocol.zig      # Protocol definitions (Command, Response, Event)
│   ├── state.zig         # EditorState serialization to JSON
│   ├── server.zig        # Debug server (handles requests via stdin/stdout)
│   └── events.zig        # Event emission
├── main.zig              # --debug-protocol flag handling
└── ...
```

## Example: LLM Verification Workflow

```bash
# 1. Claude implements visual mode feature
# 2. Start Vimcraft in debug mode
$ ./vimcraft --debug-protocol &

# 3. Send test sequence via stdin
$ echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'
$ echo '{"cmd":"execute_keys","args":{"keys":"v"},"id":"2"}'
$ echo '{"cmd":"get_mode","id":"3"}'
# Response: {"status":"ok","result":{"mode":"VISUAL"},"id":"3"}

$ echo '{"cmd":"get_visual","id":"4"}'
# Response: {"status":"ok","result":{"active":true,"mode":"char",...},"id":"4"}

$ echo '{"cmd":"execute_keys","args":{"keys":"lll"},"id":"5"}'
$ echo '{"cmd":"get_cursor","id":"6"}'
# Response: {"status":"ok","result":{"line":0,"col":3},"id":"6"}

$ echo '{"cmd":"execute_keys","args":{"keys":"y"},"id":"7"}'
$ echo '{"cmd":"get_register","args":{"name":"\""},"id":"8"}'
# Response: {"status":"ok","result":{"lines":["Hel"],...},"id":"8"}

# 4. Claude parses JSON responses, verifies all expectations met ✓
# 5. If failure, Claude gets exact structured error
# 6. Claude fixes code, re-runs (fast iteration)
```

## Benefits for LLM

1. **Structured Output**: JSON is easy to parse
2. **Deterministic**: Same input → same output
3. **Clear Failures**: Exact expected vs actual
4. **Fast Iteration**: No process spawning overhead
5. **Deep Introspection**: Full editor state available
6. **Type-Safe**: Zig ensures correctness
7. **Self-Documenting**: JSON schema is the API

## Status

✅ **Implemented**:
1. `src/debug/protocol.zig` - Command/Response types
2. `src/debug/state.zig` - EditorState → JSON serialization
3. `src/debug/server.zig` - stdin/stdout request handling
4. MCP-style JSON-RPC communication

🚧 **In Progress**:
- Additional layer inspection commands (`get_layers`, `get_layer_cells`, `get_output_grid`)
- Performance profiling commands
- Event subscription system

📅 **Future**:
- Real-time event streaming
- Breakpoint support
- Step-through debugging
