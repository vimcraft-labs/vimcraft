# Vimcraft AI Primitives Specification

**Status:** VALIDATED ✅
**Philosophy:** Extract timeless primitives, let users compose workflows
**Analysis:** 427,757 LOC across 4 production AI CLIs
**Timeline:** 4 weeks implementation

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [The 7 Primitives](#the-7-primitives)
3. [Validation](#validation)
4. [Architecture](#architecture)
5. [Success Criteria](#success-criteria)
6. [File Structure](#file-structure)

---

## Philosophy

### Core Insight

**We are NOT building an AI agent CLI.**
**We ARE providing AI primitives through `vim.ai.*` API.**

Just like Vimcraft provides:
- `vim.motion.*` - Movement primitives (users compose into navigation)
- `vim.buffer.*` - Text primitives (users compose into editing)
- `vim.register.*` - Storage primitives (users compose into copy/paste)

We provide:
- `vim.ai.*` - AI primitives (users compose into workflows)

### What We Provide vs What Users Compose

| We Provide | Why | Users Compose | Why |
|------------|-----|---------------|-----|
| **StreamingToolCallParser** | Too hard (500 LOC, 66+ edge cases) | **Multi-turn state** | Every workflow differs |
| **Provider abstraction** | Future-proof (97% shared code) | **Compression logic** | Domain-specific needs |
| **SSE parsing** | Spec compliance, edge cases | **Confirmation flows** | User preferences vary |
| **Token estimation** | Universal need, trivial to provide | **Prompt templates** | Infinite variations |
| **Message formatting** | Prevents boilerplate | **Tool selection** | Workflow-specific |
| **Context helpers** | Editor-specific, zero-copy | **Error handling** | Retry strategies vary |
| **Tool registry** | Type safety, validation | | |

**Key Principle:** We solve the **hard, timeless problems**. Users solve the **workflow, domain problems**.

---

## The 7 Primitives

### 1. Stream API - `vim.ai.stream(options)`

**Purpose:** Async generator for streaming AI responses

**Why Timeless:** All modern AI APIs stream. This will never change.

**API:**
```typescript
for await (const event of vim.ai.stream({
  provider: 'anthropic' | 'openai' | 'ollama',
  model?: string,
  messages: Message[],
  tools?: Tool[],
  temperature?: number,
  maxTokens?: number,
})) {
  match event.type {
    'content' => vim.ui.print(event.text);
    'tool_call' => await handleTool(event);
    'error' => handleError(event.error);
    'done' => break;
  }
}
```

**Implementation:**
- Native HTTP client (`std.http.Client`)
- SSE (Server-Sent Events) parser
- Event emission via JSI async iterator
- Automatic reconnection on network errors

**Files:** `http_client.zig` (100 LOC), `sse_parser.zig` (100 LOC)
**Tests:** 200 LOC

---

### 2. StreamingToolCallParser - Built Into Stream

**Purpose:** Reconstruct fragmented JSON tool calls across stream chunks

**Why Timeless:** ALL streaming APIs fragment large JSON. This is THE hard problem.

**The Problem:**
```javascript
// Provider sends tool call split across 10+ events:
Event 1: '{"id":"call_1","name":"read_file","args":{"p'
Event 2: 'ath":"/Users/foo/bar.js","enco'
Event 3: 'ding":"utf-8"}}'

// Our parser emits ONE complete tool_call event:
{ type: 'tool_call', id: 'call_1', name: 'read_file',
  args: { path: '/Users/foo/bar.js', encoding: 'utf-8' } }
```

**Edge Cases Handled (66+ test cases):**
- JSON split mid-object: `{"arg":"val` → `ue"}`
- String escaping: `"text with \"quotes\""` split across chunks
- Nested objects/arrays at arbitrary depth
- Multi-tool interleaving (2+ tools in one response)
- ID collision detection (duplicate IDs)
- Unicode escaping (`\u0041` split)
- Malformed JSON repair

**Implementation:**
```zig
const ToolCallParser = struct {
    buffer: ArrayList(u8),           // Accumulate fragments
    depth: usize,                     // JSON nesting level
    in_string: bool,                  // Inside string?
    escape_next: bool,                // Next char escaped?
    active_calls: HashMap([]const u8, PartialCall),  // Track multi-tool

    fn feed(self: *Parser, chunk: []const u8) !?ToolCall {
        // State machine for JSON reconstruction
        // - Track { } for depth
        // - Track " for string state
        // - Track \ for escapes
        // - Emit when depth returns to 0
    }
};
```

**Files:** `tool_call_parser.zig` (500 LOC)
**Tests:** 800 LOC (66+ cases)

**Critical:** This is THE hardest primitive. Users should NEVER implement this themselves.

---

### 3. Provider Abstraction - Transparent Switching

**Purpose:** Switch providers without changing code

**Why Timeless:** Multi-provider support is universal (never lock-in to one vendor)

**Pattern:**
```
User Code (provider-agnostic)
    ↕
OpenAI Chat Completions format (wire protocol)
    ↕
Provider Adapters (Anthropic, OpenAI, Ollama)
```

**Usage:**
```javascript
// Same code, different providers - zero changes needed
vim.ai.stream({ provider: 'anthropic', messages });
vim.ai.stream({ provider: 'openai', messages });
vim.ai.stream({ provider: 'ollama', messages });
```

**Provider Plugins:**

| Provider | LOC | Translation Needed |
|----------|-----|-------------------|
| OpenAI | 100 | None (canonical format) |
| Anthropic | 200 | Messages → Anthropic format, tool schema |
| Ollama | 100 | Messages → Ollama format, local endpoint |

**Error Translation:**
```zig
const AIError = union(enum) {
    rate_limit: struct { retry_after: ?u64 },
    invalid_request: struct { message: []const u8 },
    auth_failed: struct { provider: []const u8 },
    context_length_exceeded: struct { tokens: usize, max: usize },
    network_error: struct { message: []const u8 },
};
```

**Files:** `provider.zig` (150 LOC), `providers/*.zig` (400 LOC), `error_translation.zig` (250 LOC)
**Tests:** 500 LOC

---

### 4. Token Estimation - `vim.ai.estimateTokens(text)`

**Purpose:** Fast token counting for context limit checks

**Why Timeless:** Every API has token limits. Users need to estimate before calling.

**API:**
```typescript
function estimateTokens(text: string): number;
```

**Implementation:**
```zig
// Simple heuristic: ~4 chars/token (validated by all 4 CLIs)
pub fn estimateTokens(text: []const u8) usize {
    return text.len / 4;
}
```

**Usage:**
```javascript
const tokens = vim.ai.estimateTokens(vim.buffer.getText());
if (tokens > 100000) {
  vim.ui.notify('Buffer too large for context window');
  return;
}
```

**Files:** `token_utils.zig` (50 LOC)
**Tests:** 100 LOC

---

### 5. Message Formatting - `vim.ai.formatMessage(role, content)`

**Purpose:** Normalize messages to provider format

**Why Timeless:** Provider APIs have different shapes, need normalization

**API:**
```typescript
function formatMessage(
  role: 'user' | 'assistant' | 'system',
  content: string | MessageContent
): Message;

type MessageContent =
  | { type: 'text', text: string }
  | { type: 'tool_use', id: string, name: string, input: object }
  | { type: 'tool_result', tool_use_id: string, content: string };
```

**Usage:**
```javascript
const messages = [
  vim.ai.formatMessage('user', 'Explain this'),
  vim.ai.formatMessage('assistant', 'Sure, this code...'),
  vim.ai.formatMessage('user', 'Thanks!'),
];
```

**Files:** `message_format.zig` (100 LOC)
**Tests:** 100 LOC

---

### 6. Context Helpers - `vim.ai.context.*`

**Purpose:** Easy access to editor state for AI context

**Why Timeless:** All AI agents need editor context (buffer, selection, symbols, diagnostics)

**API:**
```typescript
namespace vim.ai.context {
  function buffer(bufnr?: number): string;
  function selection(): { text: string, range: Range };
  function symbols(): Symbol[];  // Tree-sitter
  function diagnostics(): Diagnostic[];  // LSP
  function files(patterns: string[]): FileContext[];
}
```

**Implementation:**

| Helper | Implementation | LOC |
|--------|---------------|-----|
| `buffer()` | Access `editor.current_buffer.lines.items` (zero-copy) | 30 |
| `selection()` | Get visual selection range + text | 40 |
| `symbols()` | Tree-sitter query for symbols | 80 |
| `diagnostics()` | LSP diagnostics via existing API | 50 |
| `files()` | Glob + read multiple files | 50 |

**Usage:**
```javascript
const context = {
  current: vim.ai.context.buffer(),
  selection: vim.ai.context.selection(),
  symbols: vim.ai.context.symbols(),
  diagnostics: vim.ai.context.diagnostics(),
  files: vim.ai.context.files(['*.js', '*.ts']),
};
```

**Files:** `context_helpers.zig` (250 LOC)
**Tests:** 200 LOC

**Key Feature:** Zero-copy access to editor state (no serialization overhead)

---

### 7. Tool Registry - `vim.ai.tools.register(tool)`

**Purpose:** Register functions AI can call

**Why Timeless:** Function calling is universal across all providers

**API:**
```typescript
namespace vim.ai.tools {
  function register(tool: Tool): void;
  function unregister(name: string): void;
  function get(name: string): Tool | undefined;
  function list(): Tool[];
}

type Tool = {
  name: string;
  description: string;
  parameters: JSONSchema;
  execute: (args: object) => Promise<string>;
};
```

**Usage:**
```javascript
vim.ai.tools.register({
  name: 'grep_code',
  description: 'Search for pattern in codebase',
  parameters: {
    type: 'object',
    properties: {
      pattern: { type: 'string' },
      files: { type: 'array', items: { type: 'string' } },
    },
    required: ['pattern'],
  },
  execute: async (args) => {
    const results = vim.grep(args.pattern, args.files || ['**/*']);
    return JSON.stringify(results);
  },
});
```

**Files:** `tool_registry.zig` (200 LOC)
**Tests:** 200 LOC

---

## Validation

### Sources

**427,757 LOC analyzed across 4 production AI CLIs:**

| CLI | LOC | Findings |
|-----|-----|----------|
| **Claude Code** | 11,625 | Simple async/await, tool fragmentation unhandled |
| **Gemini CLI** | 230,966 | Compression critical (Phase 1, not deferrable) |
| **Codex** | 182,000 | SQ/EQ can be skipped, history normalization synchronous |
| **Qwen Code** | 3,166 + 5,859 tests | Test-to-code ratio 1.8:1, StreamingToolCallParser critical |

### Validation Matrix

| Primitive | Claude Code | Gemini CLI | Codex | Qwen Code | Verdict |
|-----------|-------------|------------|-------|-----------|---------|
| **Streaming API** | ✅ Core | ✅ Core | ✅ Core | ✅ Core | **UNIVERSAL** |
| **Tool Call Parser** | ⚠️ 880 LOC | ✅ 500 LOC | ✅ Critical | ✅ 414+793 tests | **MUST PROVIDE** |
| **Provider Abstraction** | ⚠️ Single | ✅ Multi | ✅ Multi | ✅ 97% shared | **MUST PROVIDE** |
| **Token Estimation** | ✅ Present | ✅ Present | ✅ Present | ✅ Present | **HELPER PRIMITIVE** |
| **Message Format** | ✅ Present | ✅ Present | ✅ Present | ✅ Present | **HELPER PRIMITIVE** |
| **Context Helpers** | ✅ Present | ✅ Present | ✅ Present | ✅ Present | **HELPER PRIMITIVE** |
| **Tool Registry** | ✅ Present | ✅ Present | ✅ Present | ✅ Present | **UNIVERSAL** |

### Key Findings

#### Finding 1: StreamingToolCallParser is THE Primitive Users Need

**Evidence:** All 4 CLIs implement this (414-880 LOC, 66+ test cases)

**Why Critical:** Too hard for users to get right. JSON fragmentation has infinite edge cases:
- Nested depth tracking
- String state (inside quotes?)
- Escape sequences
- Multi-tool interleaving
- ID collision

**Decision:** **MUST PROVIDE** - Users should never implement this themselves.

---

#### Finding 2: Provider Abstraction Enables Future-Proofing

**Evidence:** 97% code shared between providers (Qwen validates)

**Why Critical:** Users shouldn't care about provider differences.

**Decision:** **MUST PROVIDE** - OpenAI format as internal wire protocol.

---

#### Finding 3: Token Estimation is Simple But Universal

**Evidence:** All 4 CLIs use ~4 chars/token heuristic

**Decision:** **HELPER PRIMITIVE** - 50 LOC, massive user convenience.

---

#### Finding 4: Multi-Turn State is User-Specific

**Evidence:** All 4 CLIs manage state differently:
- Claude Code: Per-request context
- Gemini CLI: Persistent with compression
- Codex: SQ/EQ with history normalization
- Qwen Code: Simple array

**Why NOT a Primitive:** Every workflow has different needs.

**Decision:** **USER COMPOSES** - Provide `estimateTokens()`, user decides when/how to compress.

---

#### Finding 5: Confirmation Logic is Application-Specific

**Evidence:** All 4 CLIs have different confirmation strategies.

**Decision:** **USER COMPOSES** - Provide `vim.ui.confirm()`, user builds logic.

---

## Architecture

### Layering

```
┌─────────────────────────────────────────────────────────┐
│                    USER PLUGINS                         │
│  (Code review, chat, refactor, doc gen, etc.)          │
│  • Multi-turn state management                         │
│  • Compression logic (when to call estimateTokens())  │
│  • Confirmation flows (vim.ui.confirm() + rules)       │
│  • Prompt templates (JavaScript template strings)      │
│  • Workflow orchestration                              │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ Uses
                          ▼
┌─────────────────────────────────────────────────────────┐
│              vim.ai.* PRIMITIVES (Phase 5)              │
│  ┌─────────────────────────────────────────────────┐   │
│  │ 1. vim.ai.stream(options)                       │   │
│  │    → Streaming with tool call events           │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 2. StreamingToolCallParser (built-in)          │   │
│  │    → 500 LOC, 66+ tests, handles fragments     │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 3. Provider abstraction (transparent)           │   │
│  │    → Switch anthropic/openai/ollama seamlessly │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 4. vim.ai.estimateTokens(text)                 │   │
│  │    → Fast ~4 chars/token approximation         │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 5. vim.ai.formatMessage(role, content)         │   │
│  │    → Normalize to provider format              │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 6. vim.ai.context.* helpers                    │   │
│  │    → buffer(), selection(), symbols(), etc.    │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 7. vim.ai.tools.register(tool)                 │   │
│  │    → Register callable functions               │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ Built on
                          ▼
┌─────────────────────────────────────────────────────────┐
│              EXISTING VIMCRAFT PRIMITIVES               │
│  • vim.buffer.* (text operations)                      │
│  • vim.motion.* (cursor movement)                      │
│  • vim.ui.* (user interface)                           │
│  • vim.fs.* (file system)                              │
└─────────────────────────────────────────────────────────┘
```

### Design Patterns

#### Pattern 1: Event-Based Streaming

**Why:** Async generators provide backpressure, cancellation, clean composition

```javascript
for await (const event of vim.ai.stream({ ... })) {
  match event.type {
    'content' => // Streaming text
    'tool_call' => // AI wants tool
    'error' => // Error occurred
    'done' => // Stream complete
  }
}
```

---

#### Pattern 2: Provider Abstraction via Wire Protocol

**Why:** 97% code shared between providers (validated by Qwen Code)

```
User Code
    ↓
OpenAI Chat Completions format (canonical)
    ↓
Provider Adapter (translate to/from provider)
    ↓
Provider API (Anthropic, OpenAI, Ollama)
```

---

#### Pattern 3: Zero-Copy Context

**Why:** Vimcraft already has buffer content in memory, use JSI HostObjects

```zig
// No serialization, direct memory access
const buffer_text = editor.buffers.get(bufnr).text;

// Expose as JSI property (zero-copy)
pub fn getProperty(obj: *ContextHelper, name: []const u8) JSValue {
    if (mem.eql(u8, name, "buffer")) {
        return JSValue.fromString(buffer_text);  // No copy
    }
}
```

**Benefits:**
- < 100μs overhead (JSI)
- No serialization/deserialization
- Large buffers (10MB+) are fast

---

#### Pattern 4: User Owns State

**Why:** Every workflow manages state differently

```javascript
// User manages history (simple array)
const history = [];

// User decides when to call AI
history.push(vim.ai.formatMessage('user', prompt));

// User decides when to compress
if (vim.ai.estimateTokens(JSON.stringify(history)) > threshold) {
  // User's compression logic
}
```

---

## Success Criteria

Phase 5 ships when all 4 scenarios work flawlessly:

### 1. Streaming with Tool Calls

```javascript
for await (const event of vim.ai.stream({
  provider: 'anthropic',
  messages: [{ role: 'user', content: 'read src/main.zig' }],
  tools: [readFileTool],
})) {
  if (event.type === 'tool_call') {
    // Tool args are COMPLETE (500+ bytes split across 10+ events)
    const result = await readFileTool.execute(event.args);
    // User decides what to do with result
  }
}
```

**Validation:** 500+ byte tool args split across 10+ events reassemble correctly.

---

### 2. Provider Switching

```javascript
// Same code, different providers - zero changes
vim.ai.stream({ provider: 'anthropic', messages });
vim.ai.stream({ provider: 'openai', messages });
vim.ai.stream({ provider: 'ollama', messages });
```

**Validation:** Same code works with all 3 providers, errors are normalized.

---

### 3. Context Gathering

```javascript
// One-liners for editor context
const code = vim.ai.context.buffer();
const selection = vim.ai.context.selection();
const symbols = vim.ai.context.symbols();
const diagnostics = vim.ai.context.diagnostics();
```

**Validation:** Context helpers return correct data, zero-copy access verified.

---

### 4. Users Can Compose Workflows

```javascript
// User builds a simple code review agent (their plugin, 100-200 LOC)
const history = [];

async function reviewFile() {
  const code = vim.ai.context.buffer();
  const diagnostics = vim.ai.context.diagnostics();

  history.push(vim.ai.formatMessage('user',
    `Review:\n${code}\n\nIssues:\n${diagnostics}`
  ));

  for await (const event of vim.ai.stream({
    provider: 'anthropic',
    messages: history,
  })) {
    if (event.type === 'content') {
      vim.ui.print(event.text);
      history.push(vim.ai.formatMessage('assistant', event.text));
    }
  }

  // User manages state, decides when to compress
  if (vim.ai.estimateTokens(JSON.stringify(history)) > 50000) {
    history.splice(1, history.length - 10);
  }
}
```

**Validation:** Users can build working workflows with primitives, no missing functionality.

---

## File Structure

### Implementation Files

```
src/system/ai/
├── types.zig                    (150 LOC) - Core types
├── http_client.zig              (100 LOC) - HTTP wrapper
├── sse_parser.zig               (100 LOC) - SSE streaming
├── tool_call_parser.zig         (500 LOC) - THE critical component
├── provider.zig                 (150 LOC) - Provider interface
├── error_translation.zig        (250 LOC) - Error mapping
├── token_utils.zig              (50 LOC)  - Token estimation
├── message_format.zig           (100 LOC) - Message normalization
├── context_helpers.zig          (250 LOC) - Editor context access
├── tool_registry.zig            (200 LOC) - Tool management
└── providers/
    ├── anthropic.zig            (200 LOC) - Anthropic implementation
    ├── openai.zig               (100 LOC) - OpenAI implementation
    └── ollama.zig               (100 LOC) - Ollama implementation

src/system/jsi/
└── ai_api.zig                   (200 LOC) - JSI HostObject bridge
```

**Total Implementation:** 1,850 LOC

### Test Files

```
tests/unit/ai/
├── types_test.zig               (50 LOC)
├── http_client_test.zig         (50 LOC)
├── sse_parser_test.zig          (100 LOC)
├── tool_call_parser_test.zig    (800 LOC) - THE comprehensive suite
├── provider_test.zig            (100 LOC)
├── error_translation_test.zig   (200 LOC)
├── token_utils_test.zig         (100 LOC)
├── message_format_test.zig      (100 LOC)
├── context_helpers_test.zig     (200 LOC)
├── tool_registry_test.zig       (200 LOC)
└── providers/
    ├── anthropic_test.zig       (200 LOC)
    ├── openai_test.zig          (100 LOC)
    └── ollama_test.zig          (100 LOC)

tests/e2e/ai-primitives/
└── e2e.ts                       (300 LOC) - Integration tests
```

**Total Tests:** 2,100 LOC

**Grand Total:** 1,850 LOC code + 2,100 LOC tests = **3,950 LOC**

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **HTTP + SSE** | Zig std.http.Client | Streaming foundation |
| **Tool Parser** | Zig (native) | JSON reconstruction |
| **Providers** | Zig (native plugins) | Anthropic, OpenAI, Ollama |
| **Context Helpers** | Zig (editor API integration) | Zero-copy context |
| **JSI Bridge** | Zig → Hermes JSI | Expose vim.ai.* to JavaScript |
| **User API** | JavaScript/TypeScript | Plugin development |

**Total:** ~1,850 LOC implementation + 2,100 LOC tests

**No external dependencies:** Pure Zig + existing Vimcraft APIs

---

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| **JSI Overhead** | < 100μs | Single HostObject call |
| **Context Building** | < 5ms | Zero-copy references only |
| **SSE Parsing** | < 50μs/chunk | Optimized state machine |
| **Tool Call Reconstruction** | < 1ms | Even for 1000+ byte args |
| **Memory** | < 10MB overhead | Cleanup with defer |

---

## Cross-References

- [roadmap.md](roadmap.md) - Implementation plan with day-by-day TODOs
- [research.md](historical/research.md) - Analysis of 4 production codebases
