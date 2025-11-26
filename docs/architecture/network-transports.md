# Network Transport Architecture

This document describes the four network transports needed for a comprehensive plugin system in Vimcraft.

## TODO

### Phase 0: Sync Subprocess - COMPLETE
- [x] Create `process_api.zig` with sync `spawn()` implementation
- [x] Implement `process.spawn(cmd, args?, opts?)` JavaScript API
- [x] Capture stdout/stderr/exit code
- [x] Support working directory option
- [x] Write E2E test (`tests/e2e/process-spawn/`)

### Phase 1: Async Subprocess (stdio) - BLOCKED
**Blocker**: Zig 0.15 `@cImport` cannot handle libuv's circular type dependencies
(`uv_stream_t` ↔ `uv_read_cb`). See Implementation Notes above.

When unblocked:
- [ ] Add libuv `uv_spawn` bindings to Zig (`src/system/event_loop/`)
- [ ] Implement `uv_pipe_t` for stdin/stdout/stderr handles
- [ ] Create `process_api.zig` with spawnAsync implementation
- [ ] Add callback registry in `runtime.js` (`_processCallbacks`, `__handleProcessEvent`)
- [ ] Implement `process.spawnAsync()` JavaScript API
- [ ] Add `proc.stdin.write()` for sending data
- [ ] Add `proc.onStdout()`, `proc.onStderr()`, `proc.onExit()` callbacks
- [ ] Add `proc.kill()` for signal handling
- [ ] Create LSP message framing helper (Content-Length parsing)
- [ ] Test with real LSP server (`typescript-language-server` or `zls`)

### Phase 2: TCP Sockets - MEDIUM PRIORITY
- [ ] Add libuv `uv_tcp_t` bindings to Zig
- [ ] Implement `uv_tcp_connect()` for client connections
- [ ] Create `socket_api.zig` with TCP implementation
- [ ] Add callback registry in `runtime.js` (`_socketCallbacks`, `__handleSocketEvent`)
- [ ] Implement `net.Socket` JavaScript API
- [ ] Add `socket.connect()`, `socket.write()`, `socket.end()`
- [ ] Add `socket.on('data'|'error'|'close')` event handlers
- [ ] Write E2E test with TCP echo server
- [ ] Test with LSP server in TCP mode

### Phase 3: WebSocket - MEDIUM PRIORITY
- [ ] Implement WebSocket HTTP Upgrade handshake (reuse fetch infrastructure)
- [ ] Implement WebSocket frame parser (opcode, length, mask, payload)
- [ ] Implement WebSocket frame serializer
- [ ] Add ping/pong keep-alive handling
- [ ] Add close handshake (status code, reason)
- [ ] Create `websocket_api.zig` with WebSocket implementation
- [ ] Add callback registry in `runtime.js` (`_wsCallbacks`, `__handleWebSocketEvent`)
- [ ] Implement browser-compatible `WebSocket` JavaScript API
- [ ] Support both text and binary messages (ArrayBuffer)
- [ ] Write E2E test with WebSocket echo server
- [ ] Test with real streaming API

### Shared Infrastructure
- [ ] Create `NetworkError` class in `runtime.js`
- [ ] Add TypeScript declarations to `vim.d.ts` for all new APIs
- [ ] Update CLAUDE.md with new API documentation
- [ ] Add examples to `examples/` directory

## Overview

| Transport | Status | Primary Use Case | Implementation |
|-----------|--------|------------------|----------------|
| **HTTP** | ✅ Implemented | REST APIs, one-shot requests | `fetch()` via libcurl + libuv |
| **stdio (sync)** | ✅ Implemented | Simple commands | `process.spawn()` via `std.process.Child` |
| **stdio (async)** | 🚧 Blocked | Local LSP servers | Blocked by Zig 0.15 libuv type issue |
| **TCP** | ❌ Planned | Remote servers, custom protocols | `uv_tcp_t` via libuv |
| **WebSocket** | ❌ Planned | Streaming, real-time collaboration | WebSocket protocol over TCP |

### Implementation Notes

**Sync subprocess (`process.spawn`)**: Fully implemented and tested. Supports:
- Command execution with arguments
- Working directory option
- Capture stdout/stderr/exit code
- See `tests/e2e/process-spawn/` for examples

**Async subprocess (`process.spawnAsync`)**: Blocked by Zig 0.15 `@cImport` circular type dependency.
The libuv headers have circular references between `uv_stream_t` and `uv_read_cb` that Zig 0.15's
`@cImport` cannot resolve. Workarounds being investigated:
1. Thread-based approach (like fetch_api.zig uses)
2. Manual extern declarations instead of @cImport
3. Wait for Zig fix

## 1. HTTP Transport

### Status: ✅ Implemented

### API
```javascript
// Browser-compatible fetch API with Promises
const response = await fetch('https://api.example.com/data', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ key: 'value' })
});

const data = response.json();
```

### Use Cases
- REST API calls (GitHub, GitLab, etc.)
- AI completions (non-streaming)
- Package registry queries
- OAuth token exchange
- Webhook notifications

### Implementation Details
- **Backend**: libcurl for HTTP/HTTPS
- **Async**: libuv thread pool (`uv_queue_work`)
- **Pattern**: React Native callback registry
- **Features**: AbortController support, custom headers, request body

### Files
- `src/system/jsi/fetch_api.zig` - Native implementation
- `src/system/jsi/runtime.js` - JavaScript wrapper

---

## 2. stdio Transport (Async Subprocess)

### Status: ❌ Planned (High Priority)

### Proposed API
```javascript
// Spawn persistent subprocess with bidirectional pipes
const proc = process.spawnAsync('rust-analyzer', [], {
  cwd: '/project',
  env: { RUST_LOG: 'info' }
});

// Event-based communication
proc.onStdout((data) => {
  // Handle stdout data (LSP responses)
  const messages = parseLspMessages(data);
  messages.forEach(handleLspMessage);
});

proc.onStderr((data) => {
  console.error('LSP stderr:', data);
});

proc.onExit((code, signal) => {
  console.log('LSP exited:', code);
});

// Send data to stdin
proc.stdin.write(formatLspMessage({
  jsonrpc: '2.0',
  method: 'initialize',
  params: { capabilities: {} },
  id: 1
}));

// Graceful shutdown
proc.kill('SIGTERM');
```

### Use Cases

#### Language Server Protocol (LSP)
The primary use case. Most LSP servers communicate via stdio:

| Server | Language | Transport |
|--------|----------|-----------|
| `rust-analyzer` | Rust | stdio |
| `gopls` | Go | stdio |
| `typescript-language-server` | TypeScript/JavaScript | stdio |
| `clangd` | C/C++ | stdio |
| `pyright` | Python | stdio |
| `lua-language-server` | Lua | stdio |
| `zls` | Zig | stdio |

#### Other Tools
- **Formatters**: `prettier`, `rustfmt`, `gofmt` (with streaming input)
- **Linters**: `eslint_d`, `rubocop` (daemon mode)
- **REPLs**: `node`, `python`, `lua` (interactive)
- **Git**: Long-running git operations with progress
- **Build tools**: `cargo watch`, `npm run watch`

### Implementation Plan

```
JavaScript (process.spawnAsync)
    ↓ stores callbacks in registry
Native (Zig)
    ↓ uv_spawn() + uv_pipe_t
libuv event loop
    ↓ UV_READABLE events on stdout/stderr
Callbacks fired via __handleProcessEvent(id, event, data)
```

#### libuv APIs needed
- `uv_spawn()` - Spawn child process
- `uv_pipe_t` - Pipe handles for stdin/stdout/stderr
- `uv_read_start()` - Async read from pipes
- `uv_write()` - Async write to stdin
- `uv_process_kill()` - Send signals

#### LSP Message Framing
LSP uses Content-Length headers:
```
Content-Length: 52\r\n
\r\n
{"jsonrpc":"2.0","method":"initialized","params":{}}
```

Should provide helper for LSP framing:
```javascript
// Low-level: raw bytes
proc.stdin.write(buffer);

// High-level: LSP framing (optional helper)
const lsp = new LspClient(proc);
lsp.request('textDocument/completion', params).then(handleCompletion);
lsp.onNotification('textDocument/publishDiagnostics', handleDiagnostics);
```

### Priority: HIGH
Unlocks ~90% of language server integrations. This is the most impactful network feature for editor functionality.

---

## 3. TCP Socket Transport

### Status: ❌ Planned (Medium Priority)

### Proposed API
```javascript
// Create TCP connection
const socket = new net.Socket();

socket.connect(6969, '127.0.0.1', () => {
  console.log('Connected to LSP server');
});

socket.on('data', (buffer) => {
  // Handle incoming data
});

socket.on('error', (err) => {
  console.error('Socket error:', err);
});

socket.on('close', () => {
  console.log('Connection closed');
});

// Send data
socket.write(buffer);

// Close connection
socket.end();
```

### Use Cases

#### LSP over TCP
Some LSP servers support or require TCP:
```javascript
// Connect to LSP server on TCP port
const socket = new net.Socket();
socket.connect(6005, '127.0.0.1');

// Use same framing as stdio
socket.write(formatLspMessage(request));
```

#### Custom Protocols
- **Debug Adapter Protocol (DAP)** - Debugger communication
- **Database connections** - PostgreSQL, MySQL wire protocols
- **Game servers** - Custom binary protocols
- **IPC** - Inter-process communication

#### Remote Development
```javascript
// Connect to remote LSP server (SSH tunnel or direct)
const socket = new net.Socket();
socket.connect(6005, 'dev-server.example.com');
```

### Implementation Plan

```
JavaScript (net.Socket)
    ↓ stores callbacks in registry
Native (Zig)
    ↓ uv_tcp_t + uv_connect()
libuv event loop
    ↓ UV_READABLE/UV_WRITABLE events
Callbacks fired via __handleSocketEvent(id, event, data)
```

#### libuv APIs needed
- `uv_tcp_init()` - Initialize TCP handle
- `uv_tcp_connect()` - Connect to server
- `uv_read_start()` - Async read
- `uv_write()` - Async write
- `uv_close()` - Close connection

### Priority: MEDIUM
Less common than stdio for LSP, but needed for remote development and custom protocols.

---

## 4. WebSocket Transport

### Status: ❌ Planned (Medium Priority)

### Proposed API
```javascript
// Browser-compatible WebSocket API
const ws = new WebSocket('wss://api.example.com/stream');

ws.onopen = () => {
  console.log('Connected');
  ws.send(JSON.stringify({ type: 'subscribe', channel: 'updates' }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

ws.onclose = (event) => {
  console.log('Closed:', event.code, event.reason);
};

// Send message
ws.send('Hello');
ws.send(binaryData); // ArrayBuffer support

// Close connection
ws.close(1000, 'Normal closure');
```

### Use Cases

#### AI Streaming APIs
```javascript
// OpenAI streaming completions
const ws = new WebSocket('wss://api.openai.com/v1/stream');
ws.onmessage = (e) => {
  const chunk = JSON.parse(e.data);
  editor.insertText(chunk.content);
};
```

#### Real-time Collaboration
```javascript
// Y.js WebSocket provider for CRDT sync
const ws = new WebSocket('wss://collab.example.com/doc/123');
const provider = new WebsocketProvider(ws, doc);
```

#### Cloud-based LSP
Some cloud IDEs use WebSocket for LSP:
```javascript
// Gitpod, GitHub Codespaces style
const ws = new WebSocket('wss://workspace.gitpod.io/lsp');
// LSP JSON-RPC over WebSocket
```

#### Live Features
- **Copilot-style suggestions** - Streaming completions
- **Live Share** - VS Code Live Share protocol
- **Chat integrations** - Slack, Discord bots
- **Notifications** - Push notifications from services

### Implementation Plan

```
JavaScript (WebSocket)
    ↓ stores callbacks in registry
Native (Zig)
    ↓ TCP connection + WebSocket frame protocol
libuv event loop
    ↓ Frame parsing, ping/pong handling
Callbacks fired via __handleWebSocketEvent(id, event, data)
```

#### WebSocket Protocol Requirements
1. **HTTP Upgrade handshake** - Initial connection via HTTP
2. **Frame parsing** - WebSocket frame format (opcode, length, mask, payload)
3. **Ping/Pong** - Keep-alive mechanism
4. **Close handshake** - Graceful shutdown
5. **Binary/Text** - Both message types
6. **Fragmentation** - Large message handling

#### Implementation Options
1. **Manual**: Implement WebSocket protocol in Zig (~500-800 lines)
2. **Library**: Link `libwebsockets` or `wslay` (adds dependency)

Recommend: Manual implementation to avoid dependency, protocol is well-specified.

### Priority: MEDIUM
Important for modern streaming APIs and collaboration, but less critical than stdio for core editor functionality.

---

## Implementation Roadmap

### Phase 1: Async Subprocess (stdio)
**Timeline**: 1-2 weeks
**Impact**: Unlocks LSP support

1. Add `uv_spawn` bindings to Zig
2. Implement pipe handling (stdin/stdout/stderr)
3. Create JavaScript `process.spawnAsync()` API
4. Add LSP message framing helper (optional)
5. Test with `rust-analyzer` or `typescript-language-server`

### Phase 2: TCP Sockets
**Timeline**: 1 week
**Impact**: Remote LSP, custom protocols

1. Add `uv_tcp_t` bindings
2. Implement connect/read/write/close
3. Create JavaScript `net.Socket` API
4. Test with TCP-mode LSP server

### Phase 3: WebSocket
**Timeline**: 1-2 weeks
**Impact**: Streaming APIs, collaboration

1. Implement WebSocket handshake (HTTP Upgrade)
2. Implement frame parser/serializer
3. Add ping/pong handling
4. Create JavaScript `WebSocket` API
5. Test with echo server and streaming API

---

## Shared Infrastructure

All transports share common patterns:

### Callback Registry Pattern
```javascript
// JavaScript side
globalThis._socketCallbacks = {};
globalThis._nextSocketId = 1;

globalThis.__handleSocketEvent = function(id, event, data) {
  const callbacks = globalThis._socketCallbacks[id];
  if (!callbacks) return;

  switch (event) {
    case 'data': callbacks.onData?.(data); break;
    case 'error': callbacks.onError?.(data); break;
    case 'close': callbacks.onClose?.(); break;
  }
};
```

### libuv Event Loop Integration
All network operations use the same libuv event loop:
```zig
// Already initialized for fetch/timers
var loop: *c.uv_loop_t = c.uv_default_loop();

// All transports share this loop
// - HTTP: uv_queue_work (thread pool)
// - stdio: uv_spawn + uv_pipe_t
// - TCP: uv_tcp_t
// - WebSocket: uv_tcp_t + protocol layer
```

### Error Handling
Consistent error types across transports:
```javascript
class NetworkError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'NetworkError';
    this.code = code; // ECONNREFUSED, ETIMEDOUT, etc.
  }
}
```

---

## References

- [LSP Specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [WebSocket RFC 6455](https://tools.ietf.org/html/rfc6455)
- [libuv Documentation](http://docs.libuv.org/)
- [Node.js net module](https://nodejs.org/api/net.html)
- [Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/)

## Cross-References

- [JSI HostObject Architecture](./jsi-hostobject-design.md)
- [Event Emitter Design](./event-emitter-design.md)
- [TypeScript Plugin Toolchain](./typescript-plugin-toolchain.md)
