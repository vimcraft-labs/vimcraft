# Vimcraft AI Specification

**Status:** Design Phase
**Architecture:** Native Zig + JSI exposure
**Last Updated:** December 2025

---

## Design Philosophy

**Simple surface. Rich internals. Timeless design.**

Informed by research into MemGPT, Aider, and production AI tools. The key insight: most production tools succeed with simple primitives. Complexity should be invisible.

| Principle | Application |
|-----------|-------------|
| **YAGNI** | 3 primitives, not 7 |
| **Proven patterns** | MemGPT core (mem + chat), Aider simplicity |
| **Invisible power** | Rich interaction data, auto-managed |
| **Extensible** | MCP, vectors can be added later |

---

## The 3 Primitives

```
┌─────────────────────────────────────────────────────────────────┐
│                        LLM Context Window                        │
│                                                                   │
│   ┌───────────────────────────────────────────────────────────┐ │
│   │  System Prompt + vim.ai.mem                                │ │
│   │  [persona] You are a helpful coding assistant...          │ │
│   │  [user] Prefers async/await, uses TypeScript, 2-space     │ │
│   │  [project] React + Next.js, Tailwind CSS                  │ │
│   └───────────────────────────────────────────────────────────┘ │
│                                                                   │
│   ┌───────────────────────────────────────────────────────────┐ │
│   │  vim.ai.chat                                               │ │
│   │  [user] Fix the auth bug                                   │ │
│   │  [assistant] I'll check the middleware...                  │ │
│   │  [user] Also add tests                                     │ │
│   │  [assistant] Sure, I'll write tests for...                │ │
│   └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        vim.ai.llm                                │
│                     (SDK / API call)                             │
└─────────────────────────────────────────────────────────────────┘
```

---

### 1. `vim.ai.mem` - Dynamic Memory Blocks (THE DIFFERENTIATOR)

While `chat` and `llm` are standard (like Claude CLI, Codex), **`mem` is where the magic happens**.

```
┌─────────────────────────────────────────────────────────────────┐
│                      vim.ai.mem                                  │
│                                                                   │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│   │   Static    │  │  Learned    │  │      Auto-generated     │ │
│   │             │  │             │  │                         │ │
│   │  persona    │  │  user       │  │  repo (tree-sitter)     │ │
│   │             │  │  patterns   │  │  context (current file) │ │
│   └─────────────┘  └─────────────┘  └─────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              Temperature (context budget)                │   │
│   │                                                          │   │
│   │  Decides how much of each block goes into ai.chat       │   │
│   │  Based on: relevance, token budget, recency             │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

```typescript
namespace vim.ai.mem {
  // Block operations
  get(block: string): string | null;
  set(block: string, content: string): boolean;
  append(block: string, content: string): boolean;
  delete(block: string): boolean;
  list(): string[];

  // Temperature: how much of each block to include (0.0 - 1.0)
  temperature(block: string): number;
  setTemperature(block: string, temp: number): boolean;

  // File sync (for AI.md)
  loadFile(block: string, path: string): boolean;  // Load file into block
  watchFile(block: string, path: string): boolean; // Auto-sync on change

  // Auto-refresh a block (e.g., repo map)
  refresh(block: string): Promise<void>;

  // Token counts
  tokens(block?: string): number;  // specific or total
  budget(): number;                // max tokens for mem
  setBudget(tokens: number): void;
}
```

**Block Types:**

| Block | Type | Updated By | Temperature |
|-------|------|------------|-------------|
| `persona` | Static | User/LLM | 1.0 (always full) |
| `user` | Learned | LLM observes preferences | 0.8 (high priority) |
| `project` | File-synced | AI.md file | 0.7 |
| `repo` | Auto-generated | Tree-sitter analysis | 0.3-0.6 (summarized) |
| `context` | Auto-generated | Current file, selection | 1.0 (always current) |
| `patterns` | Learned | Background pattern detection | 0.5 |

**AI.md vs CLAUDE.md:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    CLAUDE.md (Claude Code)                       │
│                                                                   │
│   - Always fully included in system prompt                       │
│   - Static: entire file dumped at conversation start             │
│   - Wastes tokens on irrelevant sections                         │
│   - Cannot be compressed or summarized                           │
│   - LLM cannot update it                                         │
└─────────────────────────────────────────────────────────────────┘

                              vs

┌─────────────────────────────────────────────────────────────────┐
│                    AI.md (Vimcraft)                              │
│                                                                   │
│   - Lives in vim.ai.mem as `project` block                       │
│   - Dynamic: temperature controls inclusion                       │
│   - Compressed when context is tight                             │
│   - LLM can append learned project knowledge                     │
│   - Auto-syncs when file changes                                 │
└─────────────────────────────────────────────────────────────────┘
```

**How AI.md Works:**

```
~/.config/vimcraft/AI.md (or project root)
  ↓
Auto-loaded into mem.project block
  ↓
Temperature 0.7 → 70% included by default
  ↓
When context tight → summarized/compressed
  ↓
LLM learns patterns → appends to block
  ↓
Next session: richer project understanding
```

The key insight: project instructions should be **dynamic context**, not **static overhead**.

**How Temperature Works:**

```
Token budget: 4000 tokens for mem

Block contents:
  persona:  500 tokens  × temp 1.0 = 500 included
  user:     300 tokens  × temp 0.8 = 240 included
  project:  400 tokens  × temp 0.7 = 280 included
  repo:    2000 tokens  × temp 0.4 = 800 included (summarized)
  context:  800 tokens  × temp 1.0 = 800 included
  patterns: 600 tokens  × temp 0.5 = 300 included
                                    ─────
                              Total: 2920 tokens → fits budget
```

When over budget, lower-temperature blocks get compressed first.

**Auto-generated Blocks:**

| Block | Source | Like |
|-------|--------|------|
| `repo` | Tree-sitter code map | Aider's RepoMap |
| `context` | Current buffer, selection, cursor | IDE context |
| `patterns` | Observed user behaviors | Voyager learning |

**The Self-Editing Loop (MemGPT):**
```
User: "I prefer tabs over spaces"
  ↓
LLM calls: mem_append("user", "Prefers tabs")
  ↓
Future prompts include this (at user block's temperature)
```

**Characteristics:**
- Dynamic blocks (some static, some auto-updated)
- Temperature controls inclusion
- Tree-sitter integration for repo understanding
- Background learning for patterns
- All invisible to user, but configurable via API

---

### 2. `vim.ai.chat` - Conversation History (Standard)

Standard conversation log, like any CLI. The "normal" part - insert messages, compress when long.

```typescript
namespace vim.ai.chat {
  // Get messages
  messages(limit?: number): Message[];

  // Add a message
  add(role: Role, content: string): void;

  // Clear conversation
  clear(): void;

  // Get/set current session
  session(): string;
  setSession(id: string): void;

  // List all sessions
  sessions(): SessionSummary[];

  // Summarize old messages (auto-called, but exposed)
  summarize(): void;

  // Token count
  tokens(): number;
}

type Role = 'user' | 'assistant' | 'system';

type Message = {
  role: Role;
  content: string;
  timestamp: number;
};

type SessionSummary = {
  id: string;
  title: string;
  messageCount: number;
  lastActivity: number;
};
```

**Auto-summarization (like Aider):**
```
When chat gets too long:
  1. Keep recent messages intact
  2. Summarize older messages
  3. Replace old messages with summary

User sees: Continuous conversation
Behind scenes: Compressed history
```

**Characteristics:**
- Large (~10K tokens before summarization)
- Session-based (multiple conversations)
- Auto-summarizes when context limit approached
- Persisted per session

---

### 3. `vim.ai.llm` - SDK / API Call

Pure communication layer. No state management.

```typescript
namespace vim.ai.llm {
  // Configure provider
  configure(config: ProviderConfig): boolean;

  // Send message (uses mem + chat automatically)
  send(request: SendRequest): Promise<SendResponse>;

  // Stream response
  stream(request: SendRequest): AsyncIterator<StreamChunk>;

  // Get last error
  error(): string | null;
}

type ProviderConfig = {
  provider: 'anthropic' | 'openai' | 'ollama' | 'custom';
  apiKey?: string;
  baseUrl?: string;
  model?: string;
};

type SendRequest = {
  message: string;              // User message

  // Options (all have smart defaults)
  includeMem?: boolean;         // Include mem blocks (default: true)
  includeChat?: boolean;        // Include chat history (default: true)
  systemPrompt?: string;        // Override system prompt
  maxTokens?: number;
  temperature?: number;
};

type SendResponse = {
  content: string;
  model: string;
  usage: { prompt: number; completion: number };
};

type StreamChunk = {
  content: string;
  done: boolean;
};
```

**Built-in memory tools (auto-registered):**

When calling `vim.ai.llm.send()`, these tools are available to the LLM:

| Tool | Purpose |
|------|---------|
| `mem_get` | Read a memory block |
| `mem_set` | Replace a memory block |
| `mem_append` | Add to a memory block |

The LLM can call these to update memory based on conversation.

---

## Data Flow

```
vim.ai.llm.send({ message: "Remember I use TypeScript" })
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Build prompt:                                                    │
│   1. System prompt + vim.ai.mem blocks                          │
│   2. vim.ai.chat messages                                        │
│   3. Memory tool definitions                                     │
│   4. User message                                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LLM API call (Anthropic/OpenAI/Ollama)                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Handle response:                                                 │
│   1. If tool call → execute (e.g., mem_append)                  │
│   2. Add user message to chat                                    │
│   3. Add assistant response to chat                              │
│   4. Return response                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   JavaScript (Plugin Layer)                      │
│                                                                   │
│         vim.ai.mem          vim.ai.chat          vim.ai.llm     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      JSI Bridge                                  │
│                   ai_api.zig                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
┌───────────────────┐ ┌─────────────┐ ┌─────────────────────────┐
│     mem.zig       │ │  chat.zig   │ │       llm.zig           │
│                   │ │             │ │                         │
│  Block storage    │ │  Messages   │ │  HTTP client            │
│  (JSON file)      │ │  Sessions   │ │  Provider adapters      │
│                   │ │  Summarizer │ │  Tool dispatch          │
└───────────────────┘ └─────────────┘ └─────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Storage                                        │
│                                                                   │
│   ~/.config/vimcraft/                                           │
│   ├── AI.md                 # Global project instructions        │
│   └── ai/                                                        │
│       ├── mem.json          # Memory blocks (cached)            │
│       └── chat/             # Session histories                  │
│           ├── session-001.json                                   │
│           └── session-002.json                                   │
│                                                                   │
│   <project-root>/                                                │
│   └── AI.md                 # Project-specific (overrides)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Storage Schema

### Memory (`mem.json`)
```json
{
  "blocks": {
    "persona": {
      "content": "You are a helpful coding assistant who writes clean, tested code.",
      "temperature": 1.0,
      "source": "manual"
    },
    "user": {
      "content": "Prefers TypeScript\nUses async/await\nLikes 2-space indentation",
      "temperature": 0.8,
      "source": "learned"
    },
    "project": {
      "content": "# Vimcraft\n\nZig editor with Hermes JS...",
      "temperature": 0.7,
      "source": "file",
      "file": "/Users/le/vimcraft/editor/AI.md",
      "lastSync": 1701792000
    }
  },
  "budget": 4000
}
```

### AI.md (Project Instructions)
```markdown
# Project Name

Brief description of the project.

## Architecture
- Key component 1
- Key component 2

## Conventions
- Coding style preferences
- Testing approach

## Important Notes
- Critical information for AI to know
```

**Auto-sync behavior:**
- On editor start: load AI.md into `project` block
- On file change: re-sync (if `watchFile` enabled)
- LLM can append learned patterns to block
- Cached in mem.json for faster startup

### Chat Session (`chat/session-001.json`)
```json
{
  "id": "session-001",
  "title": "Auth bug fix",
  "created": 1701792000,
  "messages": [
    { "role": "user", "content": "Fix the auth bug", "timestamp": 1701792000 },
    { "role": "assistant", "content": "I'll check...", "timestamp": 1701792005 }
  ]
}
```

---

## Implementation Status

| Primitive | Zig Implementation | JSI Binding | Status |
|-----------|-------------------|-------------|--------|
| `vim.ai.mem` | `mem.zig` | `ai_api.zig` | 📅 Planned |
| `vim.ai.chat` | `chat.zig` | `ai_api.zig` | 📅 Planned |
| `vim.ai.llm` | `llm.zig` | `ai_api.zig` | 📅 Planned |

**Existing infrastructure:**
- ✅ Provider abstraction (`providers/provider.zig`)
- ✅ Async HTTP (`fetch_api.zig`)
- ✅ LMDB bindings (can use for chat if needed)

---

## Future Extensions

When proven necessary, these can be added:

| Extension | What | When |
|-----------|------|------|
| **vim.ai.mcp** | External tools via MCP | When tool integrations needed |
| **vim.ai.archive** | Long-term vector memory | When cross-session search needed |
| **Local embeddings** | Fast pattern detection | For JIT-style optimization |

These are NOT in v1. Start simple, extend when needed.

---

## Design Principles

| Principle | Rationale |
|-----------|-----------|
| **3 primitives** | Minimum viable MemGPT |
| **LLM edits memory** | Self-editing loop, not pre-configuration |
| **Auto-summarize** | Conversation scales infinitely |
| **Session-based chat** | Multiple conversations, easy management |
| **Zig owns data** | Native performance, no JS state |

---

## Research References

| Source | Key Insight | Applied |
|--------|-------------|---------|
| **MemGPT/Letta** | Core memory + self-editing loop | `vim.ai.mem` |
| **Aider** | Conversation history + auto-summarize | `vim.ai.chat` |
| **Production tools** | Simple beats complex | 3 primitives, not 7 |

---

## File Structure

```
src/system/ai/
├── mem.zig                 # Memory block storage
├── chat.zig                # Conversation management
├── llm.zig                 # LLM communication
└── providers/
    ├── provider.zig        # Provider abstraction
    ├── anthropic.zig       # Claude API
    ├── openai.zig          # OpenAI API
    └── ollama.zig          # Local models

src/system/jsi/
└── ai_api.zig              # JSI bindings for all 3 primitives

~/.config/vimcraft/ai/
├── mem.json                # Memory blocks
└── chat/                   # Session histories
```
