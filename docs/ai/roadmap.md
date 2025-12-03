# Vimcraft AI Primitives Implementation Roadmap

**Timeline:** 4 weeks (Phase 5.1-5.2)
**Approach:** Native Zig, zero dependencies
**Specification:** See [spec.md](spec.md) for complete primitive specs

---

## Quick Reference

| Primitive | LOC | Tests | Files |
|-----------|-----|-------|-------|
| 1. Stream API | 200 | 200 | `http_client.zig`, `sse_parser.zig` |
| 2. Tool Call Parser | 500 | 800 | `tool_call_parser.zig` ← THE hard one |
| 3. Provider Abstraction | 550 | 500 | `provider.zig`, `providers/*.zig` |
| 4. Token Estimation | 50 | 100 | `token_utils.zig` |
| 5. Message Formatting | 100 | 100 | `message_format.zig` |
| 6. Context Helpers | 250 | 200 | `context_helpers.zig` |
| 7. Tool Registry | 200 | 200 | `tool_registry.zig` |

**Total:** 1,850 LOC code + 2,100 LOC tests = 3,950 LOC

---

## Timeline

| Week | Phase | Focus |
|------|-------|-------|
| 1-1.5 | 5.1 | HTTP + SSE + JSI bridge |
| 1.5-2.5 | 5.1 | StreamingToolCallParser + 66+ tests |
| 3-3.5 | 5.2 | Providers (Anthropic, OpenAI, Ollama) + error translation |
| 3.5-4 | 5.2 | Helpers (token, format, context, tools) |

---

## Phase 5.1: Core Primitives (2.5 weeks)

### Week 1 (Days 1-5): Foundation

#### Day 1-2: Core Types + HTTP Wrapper

**TODO:**
- [ ] Create `src/system/ai/` directory structure
- [ ] Implement `src/system/ai/types.zig` (150 LOC)
  - [ ] `Role` enum (system, user, assistant)
  - [ ] `Message` struct
  - [ ] `ChatResponse` struct with deinit
  - [ ] `StreamEvent` union type
  - [ ] `Tool` struct
  - [ ] `ChatOptions` struct
- [ ] Implement `src/system/ai/http_client.zig` (100 LOC)
  - [ ] Wrapper around `std.http.Client`
  - [ ] POST request helper
  - [ ] Header management
  - [ ] Response reading (10MB limit)
  - [ ] Error handling
- [ ] Write unit tests (100 LOC)

**Files Created:**
```
src/system/ai/
├── types.zig         (150 LOC)
└── http_client.zig   (100 LOC)

tests/unit/ai/
├── types_test.zig         (50 LOC)
└── http_client_test.zig   (50 LOC)
```

**Success:** Types compile, HTTP wrapper makes requests

---

#### Day 3: SSE Streaming Parser

**TODO:**
- [ ] Implement `src/system/ai/sse_parser.zig` (100 LOC)
  - [ ] `Event` struct (event_type, data, id)
  - [ ] `Parser` struct with reader
  - [ ] `next()` method (state machine)
  - [ ] Handle `data:`, `event:`, `id:` lines
  - [ ] Handle `[DONE]` terminator
  - [ ] Handle empty lines
- [ ] Write comprehensive tests (100 LOC)
  - [ ] Basic event parsing
  - [ ] Multi-line events
  - [ ] [DONE] termination
  - [ ] Malformed events

**Files:** `sse_parser.zig` (100 LOC), `sse_parser_test.zig` (100 LOC)

**Success:** Parser extracts SSE events correctly

---

#### Day 4: StreamingToolCallParser (Basic)

**TODO:**
- [ ] Implement `src/system/ai/tool_call_parser.zig` (300 LOC - basic)
  - [ ] `PartialCall` struct
  - [ ] `ToolCallParser` struct
    - [ ] `buffer: ArrayList(u8)`
    - [ ] `depth: usize` (JSON nesting)
    - [ ] `in_string: bool`
    - [ ] `escape_next: bool`
  - [ ] `feed()` method (state machine)
    - [ ] Track `{` and `}` for depth
    - [ ] Track `"` for string state
    - [ ] Track `\` for escapes
    - [ ] Emit when depth returns to 0
- [ ] Write initial tests (400 LOC)
  - [ ] Basic fragmentation (5 tests)
  - [ ] String state tracking (5 tests)
  - [ ] Depth tracking (5 tests)

**Files:** `tool_call_parser.zig` (300 LOC), `tool_call_parser_test.zig` (400 LOC)

**Success:** Basic JSON reconstruction works

---

#### Day 5: JSI Bridge (Stream API)

**TODO:**
- [ ] Implement `src/system/jsi/ai_api.zig` (100 LOC)
  - [ ] `AIApi` HostObject struct
  - [ ] `init()` method
  - [ ] `registerHostObject()` method
  - [ ] `stream()` wrapper (async iterator to JSI)
  - [ ] Event emission helpers
- [ ] Register `vim.ai` global object
- [ ] Write basic integration test

**Files:** `src/system/jsi/ai_api.zig` (100 LOC)

**Success:** `vim.ai.stream()` callable from JavaScript

---

### Week 1.5-2.5 (Days 6-12): Tool Parsing Hardening

#### Day 6-7: StreamingToolCallParser (Advanced)

**TODO:**
- [ ] Extend `tool_call_parser.zig` (+200 LOC)
  - [ ] Multi-tool tracking
    - [ ] `active_calls: HashMap([]const u8, PartialCall)`
  - [ ] ID collision detection
  - [ ] Unicode escaping (`\u0041`)
  - [ ] Nested array handling
- [ ] Write advanced tests (+400 LOC)
  - [ ] Multi-tool interleaving (11 tests)
  - [ ] ID collision (12 tests)
  - [ ] Unicode handling (6 tests)
  - [ ] Nested arrays (5 tests)

**Success:** Multi-tool calls handled, ID collisions detected

---

#### Day 8-10: Comprehensive Testing (66+ Cases)

**TODO:**
- [ ] Implement all 66+ test cases (800 LOC total)
  - [ ] Basic fragmentation (5 tests) ✓
  - [ ] String escaping (14 tests)
    - [ ] Escaped quotes: `\"hello\"`
    - [ ] Escaped backslash: `\\path\\`
    - [ ] Mixed escapes
    - [ ] Split at escape boundary
  - [ ] Nested structures (10 tests)
    - [ ] Nested objects: `{"a":{"b":{"c":"d"}}}`
    - [ ] Nested arrays: `[[1,2],[3,4]]`
    - [ ] Mixed nesting
  - [ ] Multi-tool interleaving (11 tests) ✓
  - [ ] ID collision (12 tests) ✓
  - [ ] Malformed JSON (8 tests)
    - [ ] Missing closing brace
    - [ ] Unclosed string
    - [ ] Invalid escapes
    - [ ] Repair strategies
  - [ ] Unicode handling (6 tests) ✓
- [ ] Stress tests
  - [ ] 1000+ byte tool args
  - [ ] 50+ fragments
  - [ ] 10+ concurrent tools
- [ ] Performance benchmarks
  - [ ] Target: < 50μs per fragment
  - [ ] Target: < 1ms complete reconstruction

**Success:** All 66+ tests pass, performance targets met

---

#### Day 11-12: Integration + Bug Fixes

**TODO:**
- [ ] Integrate parser with stream API
- [ ] Add E2E test (TypeScript)
  - [ ] Test with real Anthropic API
  - [ ] Test tool call fragmentation
  - [ ] Verify args reconstruction
- [ ] Fix discovered bugs
- [ ] Code review and refactor
- [ ] Documentation

**Success:** E2E test with real API passes

---

### Phase 5.1 Milestone

**Deliverables:**
- [x] HTTP client + SSE parser (200 LOC)
- [x] StreamingToolCallParser (500 LOC)
- [x] JSI bridge (100 LOC)
- [x] Comprehensive tests (800 LOC)

**Total:** 800 LOC code + 800 LOC tests

---

## Phase 5.2: Multi-Provider + Helpers (1.5 weeks)

### Week 3 (Days 13-17): Providers

#### Day 13-14: Provider Abstraction

**TODO:**
- [ ] Implement `src/system/ai/provider.zig` (150 LOC)
  - [ ] `Provider` interface
    - [ ] `chat()` method signature
    - [ ] `chatStream()` method signature
  - [ ] `ProviderType` enum
  - [ ] Provider detection logic
  - [ ] Provider registration
- [ ] Write provider interface tests (100 LOC)

**Files:** `provider.zig` (150 LOC), `provider_test.zig` (100 LOC)

**Success:** Provider interface defined, swappable

---

#### Day 14-15: Anthropic Provider

**TODO:**
- [ ] Implement `src/system/ai/providers/anthropic.zig` (200 LOC)
  - [ ] `AnthropicClient` struct
  - [ ] `init()` with API key from env
  - [ ] `chat()` method
    - [ ] Build JSON request
    - [ ] POST to `/v1/messages`
    - [ ] Headers: `x-api-key`, `anthropic-version: 2023-06-01`
    - [ ] Parse JSON response
    - [ ] Map to `ChatResponse`
  - [ ] `chatStream()` method (SSE)
  - [ ] Error handling
- [ ] Write Anthropic tests (200 LOC)

**Files:** `providers/anthropic.zig` (200 LOC), `providers/anthropic_test.zig` (200 LOC)

**Success:** Anthropic provider works end-to-end

---

#### Day 15: OpenAI Provider

**TODO:**
- [ ] Implement `src/system/ai/providers/openai.zig` (100 LOC)
  - [ ] `OpenAIClient` struct
  - [ ] Endpoint: `/v1/chat/completions`
  - [ ] Header: `Authorization: Bearer {api_key}`
  - [ ] OpenAI response format
- [ ] Write OpenAI tests (100 LOC)

**Files:** `providers/openai.zig` (100 LOC), `providers/openai_test.zig` (100 LOC)

**Success:** OpenAI provider works

---

#### Day 16: Ollama Provider

**TODO:**
- [ ] Implement `src/system/ai/providers/ollama.zig` (100 LOC)
  - [ ] `OllamaClient` struct
  - [ ] Endpoint: `http://localhost:11434/v1/chat/completions`
  - [ ] OpenAI-compatible API
  - [ ] No auth required
- [ ] Write Ollama tests (100 LOC)

**Files:** `providers/ollama.zig` (100 LOC), `providers/ollama_test.zig` (100 LOC)

**Success:** Ollama provider works locally

---

#### Day 17: Error Translation

**TODO:**
- [ ] Implement `src/system/ai/error_translation.zig` (250 LOC)
  - [ ] `AIError` union type
    - [ ] `rate_limit` (429)
    - [ ] `invalid_request` (400)
    - [ ] `auth_failed` (401)
    - [ ] `context_length_exceeded`
    - [ ] `network_error`
  - [ ] Per-provider error mapping
  - [ ] Error message formatting
- [ ] Write error translation tests (200 LOC)

**Files:** `error_translation.zig` (250 LOC), `error_translation_test.zig` (200 LOC)

**Success:** All provider errors map to AIError

---

### Week 3.5-4 (Days 18-20): Helpers

#### Day 18: Token Estimation + Message Formatting

**TODO:**
- [ ] Implement `src/system/ai/token_utils.zig` (50 LOC)
  - [ ] `estimateTokens(text: []const u8) usize`
  - [ ] Heuristic: `text.len / 4`
- [ ] Implement `src/system/ai/message_format.zig` (100 LOC)
  - [ ] `formatMessage(role, content) Message`
  - [ ] Normalize to OpenAI format
  - [ ] Handle tool use/result messages
- [ ] Write tests (200 LOC total)

**Files:** `token_utils.zig` (50 LOC), `message_format.zig` (100 LOC)

**Success:** Token estimation ±10% accurate, message formatting handles all types

---

#### Day 19: Context Helpers

**TODO:**
- [ ] Implement `src/system/ai/context_helpers.zig` (250 LOC)
  - [ ] `buffer(bufnr?: number): string` (zero-copy)
  - [ ] `selection(): { text, range }`
  - [ ] `symbols(): Symbol[]` (tree-sitter)
  - [ ] `diagnostics(): Diagnostic[]` (LSP)
  - [ ] `files(patterns): []FileContext` (glob + read)
- [ ] Write context helper tests (200 LOC)

**Files:** `context_helpers.zig` (250 LOC), `context_helpers_test.zig` (200 LOC)

**Success:** All helpers work, zero-copy verified

---

#### Day 20: Tool Registry

**TODO:**
- [ ] Implement `src/system/ai/tool_registry.zig` (200 LOC)
  - [ ] `ToolRegistry` struct
    - [ ] `tools: HashMap`
  - [ ] `register(tool: Tool) !void`
  - [ ] `execute(name, args) ![]const u8`
  - [ ] `get(name): ?Tool`
  - [ ] `list(): []Tool`
- [ ] Write tool registry tests (200 LOC)

**Files:** `tool_registry.zig` (200 LOC), `tool_registry_test.zig` (200 LOC)

**Success:** Tools can be registered and executed

---

### Phase 5.2 Milestone

**Deliverables:**
- [x] 3 providers (400 LOC)
- [x] Error translation (250 LOC)
- [x] Token estimation (50 LOC)
- [x] Message formatting (100 LOC)
- [x] Context helpers (250 LOC)
- [x] Tool registry (200 LOC)
- [x] Tests (1,300 LOC)

**Total:** 1,050 LOC code + 1,300 LOC tests

---

## Testing Strategy

### Unit Tests (Zig)

**Run:** `zig build test`

**Coverage Target:** 70%+

**Critical Suites:**
- `tool_call_parser_test.zig` - 66+ cases (THE most important)
- `sse_parser_test.zig` - SSE edge cases
- `providers/*_test.zig` - Mock HTTP, verify formats

### E2E Tests (TypeScript)

**Run:** `vimc test tests/e2e/ai-primitives`

**Scenarios:**
```typescript
// 1. Basic streaming
const r = await vim.ai.stream({ provider: 'anthropic', messages });

// 2. Tool call fragmentation
const r = await vim.ai.stream({
  provider: 'anthropic',
  messages: [{ role: 'user', content: 'read /tmp/large.json' }],
  tools: [readFileTool],
});

// 3. Provider switching
for (const p of ['anthropic', 'openai', 'ollama']) {
  await vim.ai.stream({ provider: p, messages });
}

// 4. Context helpers
const code = vim.ai.context.buffer();
const symbols = vim.ai.context.symbols();
```

### Performance Benchmarks

**Targets:**
- JSI overhead: < 100μs
- SSE parsing: < 50μs per chunk
- Tool call reconstruction: < 1ms for 1000+ byte args
- Context gathering: < 5ms (zero-copy)

---

## Success Criteria

Phase 5 ships when all 4 work:

### 1. Streaming with Tool Calls ✓
- [ ] 500+ byte tool args split across 10+ events reassemble correctly
- [ ] All 66+ tests pass
- [ ] No data loss

### 2. Provider Switching ✓
- [ ] All 3 providers work identically
- [ ] Errors are normalized
- [ ] Zero code changes needed

### 3. Context Gathering ✓
- [ ] Zero-copy access verified
- [ ] All helpers work
- [ ] Tree-sitter symbols extracted

### 4. Users Can Compose Workflows ✓
- [ ] Users can build working workflows
- [ ] Primitives compose naturally
- [ ] No missing functionality

---

## Build System Integration

### Adding to build.zig

```zig
const ai = b.addStaticLibrary(.{
    .name = "ai",
    .root_source_file = .{ .path = "src/system/ai/ai.zig" },
    .target = target,
    .optimize = optimize,
});

exe.linkLibrary(ai);

const ai_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/system/ai/ai.zig" },
    .target = target,
    .optimize = optimize,
});

test_step.dependOn(&b.addRunArtifact(ai_tests).step);
```

---

## Cross-References

- **[spec.md](spec.md)** - Complete primitive specifications, validation, architecture
- **[research.md](historical/research.md)** - Analysis of 4 production CLIs
