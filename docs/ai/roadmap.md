# AI Roadmap

**Status:** Phase 9 (AI Integration)
**Architecture:** 3 Primitives (mem, chat, llm)
**Last Updated:** December 2025

---

## Visual Overview

```
                           CURRENT STATE (Foundation)
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│   │  provider.zig    │  │  storage.zig     │  │  lmdb.zig        │  │
│   │  ✅ COMPLETE     │  │  ✅ COMPLETE     │  │  ✅ COMPLETE     │  │
│   │  (610 LOC)       │  │  (772 LOC)       │  │                  │  │
│   │                  │  │                  │  │  • Transactions  │  │
│   │  • OpenAI        │  │  • Key-value     │  │  • Prefix scan   │  │
│   │  • Anthropic     │  │  • Vectors       │  │  • Escape keys   │  │
│   │  • Ollama        │  │  • Conversations │  │                  │  │
│   │  • Tool calls    │  │  • Graph edges   │  │                  │  │
│   │  • Streaming     │  │                  │  │                  │  │
│   └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                      │
│   ┌──────────────────┐  ┌──────────────────┐                        │
│   │  vectors.zig     │  │  fetch_api.zig   │                        │
│   │  ✅ COMPLETE     │  │  ✅ COMPLETE     │                        │
│   │                  │  │                  │                        │
│   │  • usearch       │  │  • Async HTTP    │                        │
│   │  • Similarity    │  │  • TLS           │                        │
│   │  • Persistence   │  │  • Streaming     │                        │
│   └──────────────────┘  └──────────────────┘                        │
│                                                                      │
│   Foundation: ~1,400 LOC already built                              │
└─────────────────────────────────────────────────────────────────────┘

                                  │
                                  │ BUILD ON TOP
                                  ▼

                           TARGET STATE (3 Primitives)
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   ┌────────────────────────────────────────────────────────────┐    │
│   │                    JavaScript (Plugin Layer)                │    │
│   │                                                             │    │
│   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │    │
│   │  │ vim.ai.mem  │  │vim.ai.chat  │  │    vim.ai.llm       │ │    │
│   │  │ 📅 PLANNED  │  │ 📅 PLANNED  │  │    📅 PLANNED       │ │    │
│   │  │             │  │             │  │                     │ │    │
│   │  │ THE         │  │ Standard    │  │    Standard         │ │    │
│   │  │ DIFFERENTIATOR │ (like CLI)  │  │    (like CLI)       │ │    │
│   │  └─────────────┘  └─────────────┘  └─────────────────────┘ │    │
│   └────────────────────────────────────────────────────────────┘    │
│                               │                                      │
│                               ▼                                      │
│   ┌────────────────────────────────────────────────────────────┐    │
│   │                      ai_api.zig (JSI)                       │    │
│   │                        📅 PLANNED                           │    │
│   └────────────────────────────────────────────────────────────┘    │
│                               │                                      │
│            ┌──────────────────┼──────────────────┐                  │
│            ▼                  ▼                  ▼                  │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐       │
│   │   mem.zig    │   │  chat.zig    │   │     llm.zig      │       │
│   │  📅 PLANNED  │   │  📅 PLANNED  │   │    📅 PLANNED    │       │
│   │  (~200 LOC)  │   │  (~150 LOC)  │   │    (~300 LOC)    │       │
│   │              │   │              │   │                  │       │
│   │  • Blocks    │   │  • Sessions  │   │  • HTTP client   │       │
│   │  • Temp      │   │  • Messages  │   │  • Tool dispatch │       │
│   │  • AI.md     │   │  • Summarize │   │  • Self-edit     │       │
│   │  • Tokens    │   │              │   │                  │       │
│   └──────────────┘   └──────────────┘   └──────────────────┘       │
│            │                  │                  │                  │
│            └──────────────────┼──────────────────┘                  │
│                               ▼                                      │
│   ┌────────────────────────────────────────────────────────────┐    │
│   │              Existing Foundation ✅                         │    │
│   │         storage.zig + provider.zig + fetch_api.zig         │    │
│   └────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## The 3 Primitives

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   vim.ai.chat + vim.ai.llm  ←  Standard (like Claude CLI, Codex)   │
│                                                                      │
│   vim.ai.mem  ←  THE DIFFERENTIATOR                                 │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                      vim.ai.mem                              │   │
│   │                                                              │   │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │   │
│   │   │   Static    │  │  Learned    │  │      Auto-generated │ │   │
│   │   │             │  │             │  │                     │ │   │
│   │   │  persona    │  │  user       │  │  repo (tree-sitter) │ │   │
│   │   │             │  │  patterns   │  │  context (file)     │ │   │
│   │   │             │  │             │  │  project (AI.md)    │ │   │
│   │   └─────────────┘  └─────────────┘  └─────────────────────┘ │   │
│   │                              │                               │   │
│   │                              ▼                               │   │
│   │   ┌─────────────────────────────────────────────────────┐   │   │
│   │   │           Temperature (context budget)               │   │   │
│   │   │                                                      │   │   │
│   │   │  persona:  1.0  (always full)                       │   │   │
│   │   │  user:     0.8  (high priority)                     │   │   │
│   │   │  project:  0.7  (AI.md file-synced)                 │   │   │
│   │   │  repo:     0.4  (summarized when tight)             │   │   │
│   │   │  context:  1.0  (always current)                    │   │   │
│   │   │  patterns: 0.5  (background learning)               │   │   │
│   │   └─────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 9.1: Memory Blocks (`vim.ai.mem`) - THE DIFFERENTIATOR

```
┌─────────────────────────────────────────────────────────────────────┐
│  Week 1: Core Memory System                                          │
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐   │
│  │  mem.zig    │────▶│ Block Store │────▶│   storage.zig       │   │
│  │             │     │             │     │   (existing LMDB)   │   │
│  │ • get/set   │     │ • JSON      │     │                     │   │
│  │ • append    │     │ • Temp      │     │   mem:block:{name}  │   │
│  │ • delete    │     │ • Source    │     │   → {content, temp} │   │
│  │ • loadFile  │     │ • Tokens    │     │                     │   │
│  │ • watchFile │     │             │     │                     │   │
│  └─────────────┘     └─────────────┘     └─────────────────────┘   │
│                                                                      │
│  Key Features:                                                       │
│  ├── Temperature controls inclusion (0.0 - 1.0)                     │
│  ├── AI.md file sync (dynamic vs CLAUDE.md static)                  │
│  ├── Token budget management                                         │
│  ├── Block types: static, learned, auto-generated                   │
│  └── LLM can self-edit via mem_append                               │
│                                                                      │
│  Deliverables:                                                       │
│  ├── src/system/ai/mem.zig              # Block operations (~200)   │
│  ├── src/system/jsi/ai_mem_api.zig      # JSI bindings (~150)       │
│  └── tests/e2e/ai-mem/e2e.ts            # E2E tests (~100)          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**API:**
```typescript
namespace vim.ai.mem {
  get(block: string): string | null;
  set(block: string, content: string): boolean;
  append(block: string, content: string): boolean;
  delete(block: string): boolean;
  list(): string[];

  temperature(block: string): number;
  setTemperature(block: string, temp: number): boolean;

  loadFile(block: string, path: string): boolean;   // AI.md sync
  watchFile(block: string, path: string): boolean;  // Auto-sync

  refresh(block: string): Promise<void>;
  tokens(block?: string): number;
  budget(): number;
  setBudget(tokens: number): void;
}
```

---

### Phase 9.2: Chat History (`vim.ai.chat`) - Standard

```
┌─────────────────────────────────────────────────────────────────────┐
│  Week 2: Conversation Management                                     │
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐   │
│  │  chat.zig   │────▶│  Sessions   │────▶│   storage.zig       │   │
│  │             │     │             │     │   (existing LMDB)   │   │
│  │ • messages  │     │ • Active    │     │                     │   │
│  │ • add       │     │ • List      │     │   conv:{id}         │   │
│  │ • clear     │     │ • Switch    │     │   conv:{id}:msg:{ts}│   │
│  │ • summarize │     │             │     │                     │   │
│  └─────────────┘     └─────────────┘     └─────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Auto-Summarize Flow (Aider-style)           │   │
│  │                                                              │   │
│  │  Messages > 10K tokens                                       │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  LLM summarize older messages                                │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  Replace old with summary, keep recent                       │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  User sees: continuous conversation                          │   │
│  │  Behind scenes: compressed history                           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  Deliverables:                                                       │
│  ├── src/system/ai/chat.zig             # Session/message (~150)    │
│  ├── src/system/jsi/ai_chat_api.zig     # JSI bindings (~100)       │
│  └── tests/e2e/ai-chat/e2e.ts           # E2E tests (~80)           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**API:**
```typescript
namespace vim.ai.chat {
  messages(limit?: number): Message[];
  add(role: Role, content: string): void;
  clear(): void;

  session(): string;
  setSession(id: string): void;
  sessions(): SessionSummary[];

  summarize(): void;  // Auto-called, but exposed
  tokens(): number;
}
```

---

### Phase 9.3: LLM Communication (`vim.ai.llm`) - Standard

```
┌─────────────────────────────────────────────────────────────────────┐
│  Week 3: API Layer                                                   │
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐   │
│  │  llm.zig    │────▶│  provider   │────▶│   fetch_api.zig     │   │
│  │             │     │  .zig ✅    │     │   (existing HTTP)   │   │
│  │ • configure │     │             │     │                     │   │
│  │ • send      │     │  • OpenAI   │     │   POST /chat        │   │
│  │ • stream    │     │  • Anthropic│     │   POST /messages    │   │
│  │             │     │  • Ollama   │     │                     │   │
│  └─────────────┘     └─────────────┘     └─────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                Self-Editing Loop (MemGPT-inspired)           │   │
│  │                                                              │   │
│  │  vim.ai.llm.send({ message: "Remember I use TypeScript" })  │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  Build prompt:                                               │   │
│  │    1. System prompt + vim.ai.mem blocks (with temperature)  │   │
│  │    2. vim.ai.chat messages                                   │   │
│  │    3. Memory tool definitions                                │   │
│  │    4. User message                                           │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  LLM API call (Anthropic/OpenAI/Ollama)                     │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  Handle response:                                            │   │
│  │    1. If tool call → execute (mem_append, mem_set)          │   │
│  │    2. Add user message to chat                               │   │
│  │    3. Add assistant response to chat                         │   │
│  │    4. Return response                                        │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  Built-in Tools (auto-registered):                                   │
│  ├── mem_get(block)              # Read memory block                │
│  ├── mem_set(block, content)     # Replace memory block             │
│  └── mem_append(block, content)  # Append to memory block           │
│                                                                      │
│  Deliverables:                                                       │
│  ├── src/system/ai/llm.zig              # API orchestration (~300)  │
│  ├── src/system/jsi/ai_llm_api.zig      # JSI bindings (~150)       │
│  └── tests/e2e/ai-llm/e2e.ts            # E2E tests (~100)          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**API:**
```typescript
namespace vim.ai.llm {
  configure(config: ProviderConfig): boolean;
  send(request: SendRequest): Promise<SendResponse>;
  stream(request: SendRequest): AsyncIterator<StreamChunk>;
  error(): string | null;
}
```

---

### Phase 9.4: JSI Integration

```
┌─────────────────────────────────────────────────────────────────────┐
│  Week 4: Plugin API                                                  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    ai_api.zig (Unified)                      │   │
│  │                                                              │   │
│  │   Registers:  vim.ai.mem, vim.ai.chat, vim.ai.llm           │   │
│  │                                                              │   │
│  │   Pattern: HostObject with StaticStringMap dispatch          │   │
│  │   (same as existing jsi_api.zig, motion_api.zig, etc.)      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  Example Plugin (init.js):                                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  // Load project context from AI.md (dynamic, not static!)  │   │
│  │  vim.ai.mem.loadFile('project', 'AI.md');                   │   │
│  │  vim.ai.mem.setTemperature('project', 0.7);                 │   │
│  │                                                              │   │
│  │  // Configure LLM                                            │   │
│  │  vim.ai.llm.configure({                                      │   │
│  │    provider: 'anthropic',                                    │   │
│  │    apiKey: process.env.ANTHROPIC_API_KEY,                   │   │
│  │    model: 'claude-sonnet-4-20250514'                         │   │
│  │  });                                                         │   │
│  │                                                              │   │
│  │  // Create AI command                                        │   │
│  │  vim.keymap.set('n', '<leader>ai', async () => {            │   │
│  │    const response = await vim.ai.llm.send({                  │   │
│  │      message: 'Explain this function'                        │   │
│  │      // mem blocks + chat history included automatically!   │   │
│  │    });                                                        │   │
│  │    vim.api.nvim_echo([[response.content, 'Normal']], true); │   │
│  │  });                                                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Dependency Graph

```
                    ┌──────────────────┐
                    │   Phase 9.4      │
                    │   JSI Integration│
                    │    (Week 4)      │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
     │ Phase 9.1   │ │ Phase 9.2   │ │ Phase 9.3   │
     │ vim.ai.mem  │ │ vim.ai.chat │ │ vim.ai.llm  │
     │  (Week 1)   │ │  (Week 2)   │ │  (Week 3)   │
     │             │ │             │ │             │
     │ DIFFERENT-  │ │  Standard   │ │  Standard   │
     │   IATOR     │ │             │ │             │
     └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
            │               │               │
            │      ┌────────┘               │
            │      │  summarize needs llm   │
            │      │                        │
            └──────┼────────────────────────┘
                   ▼
     ┌─────────────────────────────────────────┐
     │         Existing Foundation ✅           │
     │                                         │
     │  storage.zig   provider.zig   lmdb.zig │
     │    (772)         (610)                  │
     │                                         │
     │  vectors.zig   fetch_api.zig           │
     │                                         │
     │         Total: ~1,400 LOC done          │
     └─────────────────────────────────────────┘
```

---

## Implementation Order

```
CRITICAL PATH:

  ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
  │  9.1    │────▶│  9.3    │────▶│  9.2    │────▶│  9.4    │
  │  mem    │     │  llm    │     │  chat   │     │  JSI    │
  │         │     │         │     │         │     │         │
  │ Start   │     │ Needs   │     │ Summary │     │ Final   │
  │ here    │     │ mem for │     │ needs   │     │ glue    │
  │         │     │ prompt  │     │ llm     │     │         │
  └─────────┘     └─────────┘     └─────────┘     └─────────┘
     Week 1          Week 2          Week 3          Week 4

PARALLELIZABLE:
  - mem.zig core can start immediately
  - chat.zig CRUD can start with mem
  - llm.zig depends on mem for prompt building
  - chat.summarize depends on llm
```

---

## Effort Estimate

| Phase | Component | Zig LOC | JSI LOC | Tests | Total |
|-------|-----------|---------|---------|-------|-------|
| 9.1 | mem.zig | 200 | 150 | 100 | ~450 |
| 9.2 | chat.zig | 150 | 100 | 80 | ~330 |
| 9.3 | llm.zig | 300 | 150 | 100 | ~550 |
| 9.4 | Integration | 50 | - | 50 | ~100 |
| **Total** | | **700** | **400** | **330** | **~1,430** |

**Leverage existing:**

| Component | LOC | Status |
|-----------|-----|--------|
| provider.zig | 610 | ✅ Done |
| storage.zig | 772 | ✅ Done |
| lmdb.zig | ~200 | ✅ Done |
| vectors.zig | ~150 | ✅ Done |
| fetch_api.zig | ~200 | ✅ Done |
| **Foundation** | **~1,930** | **✅ Ready** |

**New code: ~1,430 LOC (leveraging ~1,930 LOC foundation)**

---

## AI.md vs CLAUDE.md

```
┌─────────────────────────────────────────────────────────────────────┐
│                         THE KEY INSIGHT                              │
│                                                                      │
│   CLAUDE.md (Claude Code):                                          │
│   ├── Always fully included in system prompt                        │
│   ├── Static: entire file dumped at conversation start              │
│   ├── Wastes tokens on irrelevant sections                          │
│   ├── Cannot be compressed or summarized                            │
│   └── LLM cannot update it                                          │
│                                                                      │
│   AI.md (Vimcraft):                                                 │
│   ├── Lives in vim.ai.mem as `project` block                        │
│   ├── Dynamic: temperature controls inclusion (0.7 default)         │
│   ├── Compressed when context is tight                              │
│   ├── LLM can append learned project knowledge                      │
│   └── Auto-syncs when file changes                                  │
│                                                                      │
│   Example:                                                           │
│     2000-token CLAUDE.md → wastes 2000 tokens EVERY turn            │
│     2000-token AI.md @ temp 0.7 → 1400 tokens normally              │
│                                 → 400 tokens when context tight     │
│                                 → grows smarter over time           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Success Criteria

| Criterion | Metric |
|-----------|--------|
| Memory works | `vim.ai.mem.get/set/append` functional |
| AI.md syncs | File changes reflect in mem block |
| Temperature works | Low-temp blocks compressed first |
| Chat persists | Sessions survive restart |
| Auto-summarize | Old messages compressed automatically |
| LLM calls work | Send/receive from Anthropic/OpenAI |
| Self-editing loop | LLM can call `mem_append` |
| Streaming works | Chunks arrive progressively |
| E2E tests pass | All tests green |

---

## File Structure (Target)

```
src/system/ai/
├── mem.zig                 # Memory block operations (~200 LOC)
├── chat.zig                # Conversation management (~150 LOC)
├── llm.zig                 # LLM API orchestration (~300 LOC)
├── storage/
│   ├── storage.zig         # ✅ Unified storage (existing)
│   ├── lmdb.zig            # ✅ Key-value store (existing)
│   └── vectors.zig         # ✅ Vector index (existing)
└── providers/
    └── provider.zig        # ✅ LLM providers (existing)

src/system/jsi/
├── ai_api.zig              # Main AI namespace registration
├── ai_mem_api.zig          # vim.ai.mem JSI bindings
├── ai_chat_api.zig         # vim.ai.chat JSI bindings
└── ai_llm_api.zig          # vim.ai.llm JSI bindings

tests/e2e/
├── ai-mem/e2e.ts           # Memory block tests
├── ai-chat/e2e.ts          # Chat history tests
└── ai-llm/e2e.ts           # LLM communication tests

~/.config/vimcraft/
├── AI.md                   # Global project instructions (dynamic!)
└── ai/
    ├── mem.json            # Memory blocks (cached)
    └── chat/               # Session histories
        ├── session-001.json
        └── session-002.json

<project-root>/
└── AI.md                   # Project-specific (overrides global)
```

---

## Future Extensions (Not in v1)

```
┌─────────────────────────────────────────────────────────────────────┐
│  DEFERRED - Add when proven necessary                                │
│                                                                      │
│  vim.ai.mcp        External tools via MCP protocol                  │
│  vim.ai.archive    Long-term vector memory (cross-session search)   │
│  Local embeddings  JIT-style pattern detection (using vectors.zig) │
│  vim.ai.agents     Multi-agent orchestration                        │
│                                                                      │
│  These extend the 3 primitives when proven necessary.               │
│  vectors.zig already exists for when we need embeddings!            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Design Philosophy

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  "Simple surface. Rich internals. Timeless design."                 │
│                                                                      │
│  Informed by:                                                        │
│  ├── MemGPT/Letta  → Self-editing memory loop                       │
│  ├── Aider         → Simple primitives (history + tree-sitter)      │
│  └── Production    → Simple beats complex                           │
│                                                                      │
│  Result: 3 primitives, not 7                                         │
│  ├── vim.ai.mem   → THE DIFFERENTIATOR (dynamic, learned)           │
│  ├── vim.ai.chat  → Standard (like CLI tools)                       │
│  └── vim.ai.llm   → Standard (SDK layer)                            │
│                                                                      │
│  Power is invisible:                                                 │
│  ├── Temperature auto-manages context budget                        │
│  ├── AI.md syncs dynamically (vs static CLAUDE.md)                  │
│  ├── LLM learns preferences via self-editing                        │
│  └── Repo understanding via tree-sitter (in mem block)              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Cross-References

**Specification:** [spec.md](spec.md) - Complete API details
**Parent:** [Main Roadmap](../roadmap/README.md)
**Related:** [Testing Architecture](../development/testing-architecture.md)
