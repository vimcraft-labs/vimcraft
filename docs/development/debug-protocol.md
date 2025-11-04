# OpenVim Debug Protocol (ODP)

## Architecture

```
┌─────────────────┐         JSON/IPC         ┌──────────────┐
│   OpenVim       │ ←─────────────────────→  │     ovdb     │
│   (--debug)     │                           │  (debugger)  │
│                 │                           │              │
│ • Editor core   │  Queries/Commands/Events │ • Query      │
│ • State export  │ ←────────────────────→   │ • Assert     │
│ • Debug hooks   │                           │ • Verify     │
│ • Event stream  │                           │ • Report     │
└─────────────────┘                           └──────────────┘
         ↑                                            ↓
         │                                            │
         │                                    ┌───────────────┐
         │                                    │  LLM (Claude) │
         └────────────────────────────────────│  Parse JSON   │
                  Clear structured output     │  Understand   │
                                              │  Iterate      │
                                              └───────────────┘
```

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

**Option 1: stdin/stdout (Simple)**
```bash
# Start OpenVim in debug mode
./openvim --debug-protocol

# ovdb connects via stdin/stdout
echo '{"cmd":"get_state"}' | ./openvim --debug-protocol
```

**Option 2: Unix Socket (Preferred)**
```bash
# OpenVim listens on socket
./openvim --debug-socket=/tmp/openvim-debug.sock

# ovdb connects
./ovdb connect /tmp/openvim-debug.sock
```

**Option 3: Shared Memory (Fastest)**
- For performance-critical debugging
- Zero-copy state access

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

OpenVim can emit events for debugging:

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

## ovdb (OpenVim Debugger) CLI

### Interactive Mode

```bash
$ ./ovdb connect /tmp/openvim-debug.sock

ovdb> get_state
{
  "mode": "NORMAL",
  "cursor": {"line": 0, "col": 0},
  ...
}

ovdb> execute_keys viw
Keys processed: 3

ovdb> get_visual
{
  "active": true,
  "mode": "char",
  ...
}

ovdb> assert_cursor 0 5
✓ PASS: cursor at (0, 5)

ovdb> quit
```

### Script Mode

```bash
$ cat test.ovdb
load_file /tmp/test.txt
execute_keys viw
assert_visual_active true
assert_visual_mode char
execute_keys y
assert_register " "Hello"
quit

$ ./ovdb run test.ovdb
[1/6] load_file /tmp/test.txt ✓
[2/6] execute_keys viw ✓
[3/6] assert_visual_active true ✓
[4/6] assert_visual_mode char ✓
[5/6] execute_keys y ✓
[6/6] assert_register " "Hello" ✓

✓ All 6 tests passed
```

### LLM-Friendly Output

```bash
$ ./ovdb run test.ovdb --format=json
{
  "test_file": "test.ovdb",
  "total": 6,
  "passed": 6,
  "failed": 0,
  "tests": [
    {"name": "load_file", "status": "pass", "duration_ms": 1.2},
    {"name": "execute_keys", "status": "pass", "duration_ms": 0.5},
    ...
  ],
  "summary": {
    "status": "pass",
    "duration_total_ms": 12.5
  }
}
```

## Implementation Files

```
src/
├── debug/
│   ├── protocol.zig      # Protocol definitions (Command, Response, Event)
│   ├── state.zig         # EditorState serialization to JSON
│   ├── server.zig        # Debug server (handles requests)
│   └── events.zig        # Event emission
├── main.zig              # Add --debug-protocol flag
└── ...

tools/
└── ovdb/
    ├── main.zig          # ovdb CLI entry point
    ├── client.zig        # Connect to OpenVim debug server
    ├── repl.zig          # Interactive REPL
    ├── script.zig        # Script execution (.ovdb files)
    ├── assertions.zig    # Assertion framework
    └── reporter.zig      # Test result reporting (human + JSON)
```

## Example: LLM Verification Workflow

```bash
# 1. Claude implements visual mode feature
# 2. Claude writes test script
$ cat > test_visual.ovdb << EOF
load_file /tmp/test.txt
execute_keys v
assert_mode VISUAL
assert_visual_mode char
execute_keys lll
assert_visual_anchor 0 0
assert_cursor 0 3
execute_keys y
assert_register " "Hel"
EOF

# 3. Claude runs test
$ ./ovdb run test_visual.ovdb --format=json
{
  "status": "pass",
  "passed": 7,
  "failed": 0,
  ...
}

# 4. Claude parses JSON, sees all pass ✓
# 5. If failure, Claude gets exact error:
{
  "status": "fail",
  "tests": [
    {
      "name": "assert_register",
      "status": "fail",
      "expected": "Hel",
      "actual": "Hello",
      "diff": "+ lo"  // Clear diff
    }
  ]
}

# 6. Claude fixes code, re-runs
```

## Benefits for LLM

1. **Structured Output**: JSON is easy to parse
2. **Deterministic**: Same input → same output
3. **Clear Failures**: Exact expected vs actual
4. **Fast Iteration**: No process spawning overhead
5. **Deep Introspection**: Full editor state available
6. **Type-Safe**: Zig ensures correctness
7. **Self-Documenting**: JSON schema is the API

## Next Steps

1. Implement `src/debug/protocol.zig` - Command/Response types
2. Implement `src/debug/state.zig` - EditorState → JSON serialization
3. Implement `src/debug/server.zig` - Request handling
4. Implement `tools/ovdb/` - Debugger CLI
5. Write tests using ovdb
6. Document in TESTING.md
