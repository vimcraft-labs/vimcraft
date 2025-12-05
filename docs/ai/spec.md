# Vimcraft AI Specification

**Status:** Implementation Phase
**Architecture:** Native Zig + JSI exposure

---

## Core Architecture

All AI primitives are implemented in Zig and exposed to JavaScript via JSI.

```
┌─────────────────────────────────────────────────────────────┐
│                   JavaScript (Plugin)                        │
│                                                              │
│   vim.ai.memory.*        vim.ai.conversation.*              │
│   vim.ai.prompt.*                                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      JSI Bridge                              │
│                   ai_sdk_api.zig                            │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│   memory.zig    │ │ conversation.zig│ │    prompt.zig       │
│                 │ │                 │ │                     │
│  LMDB + usearch │ │  Read-only view │ │  HTTP + Providers   │
│  (the truth)    │ │  (projection)   │ │  (communication)    │
└─────────────────┘ └─────────────────┘ └─────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   ~/.config/vimcraft/ai/                     │
│   ├── vectors.usearch    # Embeddings (HNSW)                │
│   └── data/              # LMDB (key-value)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## The 3 Primitives

### 1. `vim.ai.memory` - Vector-native AI State

The source of truth. LLM-native storage using embeddings and graph relationships.

```typescript
namespace vim.ai.memory {
  // Insert
  add(content: string, embedding?: number[], tags?: string[]): string;  // returns id

  // Query
  search(query: string, k?: number): MemoryItem[];           // semantic search
  searchByEmbedding(embedding: number[], k?: number): MemoryItem[];
  get(id: string): MemoryItem | null;
  findByTag(tag: string): MemoryItem[];

  // Edit
  update(id: string, content: string, embedding?: number[]): boolean;
  delete(id: string): boolean;
  addEdge(from: string, relation: string, to: string): boolean;

  // Graph traversal
  outgoing(id: string, relation?: string): Edge[];
  incoming(id: string, relation?: string): Edge[];
}

type MemoryItem = {
  id: string;
  content: string;
  embedding: number[];
  tags: string[];
  timestamp: number;
  similarity?: number;  // when from search
};

type Edge = {
  from: string;
  relation: string;
  to: string;
  metadata?: any;
};
```

**Implementation:** LMDB for content/metadata, usearch for vector similarity.

---

### 2. `vim.ai.conversation` - Human-readable Projection

Read-only view of memory, projected into familiar conversation format. Maps directly to LLM context window.

```typescript
namespace vim.ai.conversation {
  // List conversations (projected from memory graph)
  list(): ConversationSummary[];

  // Get conversation messages (projected from memory)
  get(id: string): Message[];

  // Get as context window (ready for LLM)
  toContext(id: string, maxTokens?: number): Message[];

  // Current active conversation
  current(): string | null;
  setCurrent(id: string): void;
}

type ConversationSummary = {
  id: string;
  title: string;
  messageCount: number;
  lastActivity: number;
};

type Message = {
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: number;
};
```

**Key insight:** Conversations don't store data. They project from `vim.ai.memory`.

When you call `vim.ai.conversation.get("conv-123")`:
1. Queries memory for items with edge `conversation:conv-123`
2. Projects into Message[] format
3. Returns read-only view

---

### 3. `vim.ai.prompt` - Universal LLM Interface

SDK to communicate with any LLM backend. Native Zig HTTP with provider adapters.

```typescript
namespace vim.ai.prompt {
  // Configure provider
  configure(config: ProviderConfig): boolean;

  // Send prompt (auto-persists to memory)
  send(request: PromptRequest): Promise<PromptResponse>;

  // Stream response
  stream(request: PromptRequest): AsyncIterator<StreamChunk>;

  // Get last error
  getLastError(): string | null;
}

type ProviderConfig = {
  provider: 'openai' | 'anthropic' | 'ollama' | 'custom';
  apiKey?: string;
  baseUrl?: string;
  model?: string;
};

type PromptRequest = {
  conversation?: string;           // conversation id (optional)
  message: string;                 // user message
  systemPrompt?: string;           // override system prompt
  contextFromMemory?: boolean;     // auto-retrieve relevant context
  maxTokens?: number;
  temperature?: number;
};

type PromptResponse = {
  content: string;
  model: string;
  usage: { promptTokens: number; completionTokens: number };
  memoryId: string;                // ID in memory (auto-persisted)
};

type StreamChunk = {
  content: string;
  done: boolean;
};
```

**Data flow:**
1. JS calls `vim.ai.prompt.send({ message: "Fix the bug" })`
2. Zig retrieves context from memory (if enabled)
3. Zig builds request via provider adapter
4. Zig makes HTTP call (libuv async)
5. Zig persists response to memory
6. Zig returns result to JS

---

## Data Flow Example

```
User: "Fix the auth bug"
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ vim.ai.prompt.send({ message: "Fix the auth bug" })        │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ prompt.zig:                                                  │
│   1. Query memory for similar context (semantic search)     │
│   2. Build prompt with retrieved context                    │
│   3. Format for provider (OpenAI/Anthropic/Ollama)         │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ fetch_api.zig: HTTP POST to LLM API (async via libuv)      │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ On response:                                                 │
│   1. Parse response                                         │
│   2. Store in memory (user msg + assistant response)        │
│   3. Add conversation edge                                  │
│   4. Compute embedding (optional)                           │
│   5. Return to JS                                           │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ vim.ai.conversation.get("conv-123")                         │
│   → Projects stored memory into Message[] for display       │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
src/system/ai/
├── memory.zig              # vim.ai.memory implementation
├── conversation.zig        # vim.ai.conversation (projection)
├── prompt.zig              # vim.ai.prompt (LLM communication)
├── storage/
│   ├── lmdb.zig           # Key-value storage
│   └── vectors.zig        # usearch/HNSW bindings
└── providers/
    └── provider.zig       # Provider abstraction

src/system/jsi/
└── ai_sdk_api.zig         # JSI bindings for all 3 primitives
```

---

## Storage Schema

```
MEMORY ITEMS
────────────────────────────────────────────────────────
mem:{id}                        → {content, embedding, tags, timestamp}
idx:tag:{tag}:{id}              → "" (tag index)
vec:{id}                        → {vector_key} (usearch reference)

EDGES (Graph)
────────────────────────────────────────────────────────
edge:{from}:{relation}:{to}     → {metadata}
redge:{to}:{relation}:{from}    → "" (reverse index)

CONVERSATIONS (via edges)
────────────────────────────────────────────────────────
edge:{mem_id}:conversation:{conv_id}  → {order: n}
conv:{conv_id}                        → {title, created, lastActivity}
```

---

## Implementation Status

| Primitive | Zig Implementation | JSI Binding | Status |
|-----------|-------------------|-------------|--------|
| `vim.ai.memory` | `memory.zig` | `ai_sdk_api.zig` | 🚧 Partial |
| `vim.ai.conversation` | `conversation.zig` | `ai_sdk_api.zig` | 📅 Planned |
| `vim.ai.prompt` | `prompt.zig` | `ai_sdk_api.zig` | 📅 Planned |

**Existing infrastructure:**
- ✅ LMDB bindings (`storage/lmdb.zig`)
- ✅ usearch bindings (`storage/vectors.zig`)
- ✅ Provider abstraction (`providers/provider.zig`)
- ✅ Async HTTP (`fetch_api.zig`)

---

## Key Principles

1. **Memory is truth** - All AI state lives in `vim.ai.memory`
2. **Conversations are projections** - Read-only views, not separate storage
3. **Zig owns the data** - No state management in JavaScript
4. **Native performance** - Zero-copy, memory-mapped, async I/O
