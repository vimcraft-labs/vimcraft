# Vimcraft AI Primitives - Visual Architecture

This document contains visual diagrams explaining the architecture and relationships between AI primitives.

**Last Updated:** 2025-01-04
**Related:** [AI Spec](../ai/spec.md) | [AI Roadmap](../ai/roadmap.md)

---

## Table of Contents

1. [The Central Entity Pattern](#1-the-central-entity-pattern)
2. [The 8 Primitives Hierarchy](#2-the-8-primitives-hierarchy)
3. [Multi-Agent Workflow](#3-multi-agent-workflow-the-power-of-conversation)
4. [Full System Architecture](#4-full-system-architecture)
5. [Data Flow](#5-data-flow-from-user-input-to-ai-response)
6. [Conversation State Machine](#6-conversation-state-machine)
7. [Comparison: Without vs With Conversation](#7-comparison-without-vs-with-conversation)
8. [The Full Dependency Graph](#8-the-full-dependency-graph)

---

## 1. The Central Entity Pattern

**Key Insight:** AI primitives follow the same pattern as editor primitives - a central entity enables collaboration.

```
┌─────────────────────────────────────────────────────────────────┐
│                    EDITING (Current)                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                        Buffer (text)                            │
│                            ▲                                    │
│                            │                                    │
│              ┌─────────────┼─────────────┐                     │
│              │             │             │                     │
│         Plugin A       Plugin B      Plugin C                  │
│      (Syntax HL)    (LSP Diag)    (Git Signs)                 │
│                                                                 │
│  All plugins share Buffer → Collaborate without knowing        │
│                             each other                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    AI (New Pattern)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                   Conversation (AI state)                       │
│                            ▲                                    │
│                            │                                    │
│              ┌─────────────┼─────────────┐                     │
│              │             │             │                     │
│         Plugin A       Plugin B      Plugin C                  │
│      (Reviewer)   (Test Gen)     (Docs Writer)                │
│                                                                 │
│  All plugins share Conversation → Multi-agent workflows!       │
└─────────────────────────────────────────────────────────────────┘
```

**Why This Matters:**
- **Without central entity:** Each plugin maintains its own state, no collaboration
- **With central entity:** Plugins naturally compose into multi-agent workflows

---

## 2. The 8 Primitives Hierarchy

**Structure:** Conversation is the foundation, other primitives build on it.

```
                    ┌──────────────────────────────┐
                    │   0. CONVERSATION            │
                    │   (THE BACKBONE)             │
                    │                              │
                    │   • Shared state             │
                    │   • Message history          │
                    │   • Persistence              │
                    │   • Navigation               │
                    └──────────┬───────────────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
       ┌────────────┐  ┌────────────┐  ┌────────────┐
       │ 1. Stream  │  │ 3. Provider│  │ 6. Context │
       │            │  │ Abstraction│  │  Helpers   │
       │ • SSE      │  │            │  │            │
       │ • Events   │  │ • Anthropic│  │ • buffer() │
       │ • Async    │  │ • OpenAI   │  │ • symbols()│
       └─────┬──────┘  │ • Ollama   │  └────────────┘
             │         └────────────┘
             │
             ▼
    ┌─────────────────┐
    │ 2. Tool Call    │
    │    Parser       │
    │                 │
    │ • JSON recon    │
    │ • 66+ tests     │
    └─────────────────┘

    Supporting Helpers:
    ┌──────────────┬──────────────┬──────────────┐
    │ 4. Token Est │ 5. Msg Format│ 7. Tool Reg  │
    └──────────────┴──────────────┴──────────────┘
```

**LOC Distribution:**
- **Conversation (600 LOC):** The foundation
- **Stream + Parser (850 LOC):** The complex parts
- **Providers (550 LOC):** Multi-provider support
- **Helpers (600 LOC):** User convenience

---

## 3. Multi-Agent Workflow (The Power of Conversation)

**Scenario:** Three independent plugins collaborate to improve code.

```
Time ──────────────────────────────────────────────────▶

                Conversation "code-improvement"
                ┌─────────────────────────────────┐
                │ id: "abc123"                    │
                │ provider: "anthropic"           │
                │ messages: []                    │
                └────────────┬────────────────────┘
                             │
Step 1:                      │
Plugin A                     │
(Reviewer)  ─────────────────┼──▶ Append:
                             │   "Review this code"
                             │       ↓
                             │   AI Response:
                             │   "Found 3 issues..."
                             ▼
                ┌─────────────────────────────────┐
                │ messages: [                     │
                │   {user: "Review..."},          │
                │   {assistant: "Found 3..."}     │
                │ ]                               │
                └────────────┬────────────────────┘
                             │
Step 2:                      │
Plugin B                     │
(Test Gen)  ─────────────────┼──▶ Append:
                             │   "Generate tests for issues"
                             │       ↓
                             │   AI sees FULL history!
                             │   AI Response:
                             │   "Here are 5 tests..."
                             ▼
                ┌─────────────────────────────────┐
                │ messages: [                     │
                │   {user: "Review..."},          │
                │   {assistant: "Found 3..."},    │
                │   {user: "Generate tests..."},  │
                │   {assistant: "Here are 5..."}  │
                │ ]                               │
                └────────────┬────────────────────┘
                             │
Step 3:                      │
Plugin C                     │
(Docs)      ─────────────────┼──▶ Append:
                             │   "Write docs for issues"
                             │       ↓
                             │   AI sees EVERYTHING!
                             ▼
                ┌─────────────────────────────────┐
                │ messages: [... full history]    │
                └─────────────────────────────────┘

Key: Plugins collaborate WITHOUT knowing about each other!
     The Conversation is the shared medium.
```

**What This Enables:**
- Plugin A reviews code
- Plugin B generates tests based on review (sees Plugin A's conversation)
- Plugin C writes docs based on review + tests (sees A + B)
- **No explicit coordination needed** - Conversation is the coordination medium

---

## 4. Full System Architecture

**The complete stack showing how everything connects.**

```
┌────────────────────────────────────────────────────────────────┐
│                      USER PLUGINS                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐          │
│  │   Plugin A   │ │   Plugin B   │ │   Plugin C   │          │
│  │  (Reviewer)  │ │ (Test Gen)   │ │ (Docs Write) │          │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘          │
│         │                │                │                    │
│         └────────────────┼────────────────┘                    │
│                          │                                     │
│                          │ Create/Get/Use                      │
│                          ▼                                     │
│         ┌────────────────────────────────┐                    │
│         │    vim.ai.conversations.*      │                    │
│         │         (THE BACKBONE)         │                    │
│         └────────────────┬───────────────┘                    │
└──────────────────────────┼────────────────────────────────────┘
                           │
                           │ Uses
                           ▼
┌────────────────────────────────────────────────────────────────┐
│                  PRIMITIVES LAYER                              │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Conversation (Primitive 0)                          │    │
│  │  • State: messages[], provider, metadata            │    │
│  │  • Ops: append(), compress(), fork(), tokens()      │    │
│  │  • Storage: ~/.config/vimcraft/conversations/       │    │
│  └───────────────────────┬──────────────────────────────┘    │
│                          │                                    │
│                          │ Powers                             │
│                          ▼                                    │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │  1. Stream    │  │  3. Provider  │  │  6. Context   │   │
│  │     API       │  │  Abstraction  │  │    Helpers    │   │
│  │               │  │               │  │               │   │
│  │  Uses conv ───┼─▶│  Reads conv  │  │  Injects ctx  │   │
│  │  to track     │  │  provider     │  │  into conv    │   │
│  │  messages     │  │               │  │               │   │
│  └───────┬───────┘  └───────────────┘  └───────────────┘   │
│          │                                                   │
│          ▼                                                   │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │  2. Tool Call │  │  4. Token Est │  │  7. Tool Reg  │   │
│  │     Parser    │  │  5. Msg Format│  │               │   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
│                                                              │
└──────────────────────────┬───────────────────────────────────┘
                           │
                           │ Built on
                           ▼
┌────────────────────────────────────────────────────────────────┐
│              EXISTING VIMCRAFT PRIMITIVES                      │
│  • vim.buffer.* (text operations)                             │
│  • vim.ui.* (user interface)                                  │
│  • vim.fs.* (file system)                                     │
│  • Tree-sitter (symbols)                                      │
│  • LSP (diagnostics)                                          │
└────────────────────────────────────────────────────────────────┘
```

**Layers:**
1. **User Plugins:** Compose workflows from primitives
2. **Primitives Layer:** The 8 core primitives (Conversation at the center)
3. **Foundation:** Existing Vimcraft APIs

---

## 5. Data Flow: From User Input to AI Response

**Complete flow showing how data moves through the system.**

```
User types:           Plugin A calls:
<leader>ar           ┌─────────────────────────────────┐
    │                │ const conv =                    │
    │                │   vim.ai.conversations.create({ │
    │                │     name: 'improve-code'        │
    │                │   });                           │
    │                └─────────────┬───────────────────┘
    │                              │
    ▼                              ▼
┌────────────────┐     ┌─────────────────────────┐
│ Conversation   │◀────│ 0. Create Conversation  │
│ Created        │     │    600 LOC              │
│                │     └─────────────────────────┘
│ id: "abc123"   │
│ messages: []   │
└───────┬────────┘
        │
        │ Plugin calls vim.ai.stream({ conversation: conv })
        ▼
┌────────────────────────────────────────────────────────┐
│ 1. Stream API                                          │
│    350 LOC                                             │
│                                                        │
│    ┌──────────────────────────────────────┐          │
│    │ Read conv.provider → "anthropic"     │          │
│    │ Read conv.messages → [...]           │          │
│    └──────────┬───────────────────────────┘          │
│               │                                        │
│               ▼                                        │
│    ┌──────────────────────────────────────┐          │
│    │ 3. Provider Abstraction              │          │
│    │    550 LOC                            │          │
│    │    → AnthropicClient                 │          │
│    └──────────┬───────────────────────────┘          │
└───────────────┼────────────────────────────────────────┘
                │
                │ HTTP POST
                ▼
    ┌───────────────────────┐
    │   Anthropic API       │
    │   api.anthropic.com   │
    └───────────┬───────────┘
                │
                │ SSE Stream
                ▼
┌────────────────────────────────────────────────────────┐
│ Stream API receives fragments:                        │
│                                                        │
│ Event 1: '{"id":"call_1","name":"read_file","args":{' │
│ Event 2: '"path":"/tmp/foo.js","encoding":'           │
│ Event 3: '"utf-8"}}'                                  │
│                                                        │
│               │                                        │
│               ▼                                        │
│    ┌──────────────────────────────────────┐          │
│    │ 2. Tool Call Parser                  │          │
│    │    500 LOC                            │          │
│    │                                       │          │
│    │ Reassembles fragments into:          │          │
│    │ { id: "call_1",                      │          │
│    │   name: "read_file",                 │          │
│    │   args: { path: "/tmp/foo.js",       │          │
│    │           encoding: "utf-8" } }      │          │
│    └──────────┬───────────────────────────┘          │
└───────────────┼────────────────────────────────────────┘
                │
                │ Emits complete tool_call event
                ▼
┌────────────────────────────────────────┐
│ Plugin receives event                  │
│                                        │
│ if (event.type === 'tool_call') {     │
│   const result = await                │
│     readFileTool.execute(event.args); │
│ }                                      │
└────────────────┬───────────────────────┘
                 │
                 │ Result sent back
                 ▼
┌────────────────────────────────────────┐
│ Conversation Updated                   │
│                                        │
│ messages: [                            │
│   {user: "Review code"},              │
│   {assistant: "..."},                 │
│   {tool_use: "read_file"},            │
│   {tool_result: "content..."}         │
│ ]                                      │
└────────────────────────────────────────┘
```

**Key Points:**
- Conversation is created first (central state)
- Stream API reads from Conversation
- Provider abstraction translates to provider-specific format
- Tool Call Parser reassembles fragmented JSON
- Conversation is automatically updated with results

---

## 6. Conversation State Machine

**Conversation lifecycle and operations.**

```
                    ┌─────────────┐
                    │   CREATE    │
                    │             │
                    │ conversations│
                    │   .create() │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   ACTIVE    │
                    │             │
                    │ • append()  │
                    │ • stream()  │
                    │ • tokens()  │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ COMPRESS │    │   FORK   │    │  SWITCH  │
    │          │    │          │    │ PROVIDER │
    │ .compress│    │  .fork() │    │          │
    │ ()       │    │          │    │ .provider│
    └────┬─────┘    └────┬─────┘    │  = ...   │
         │               │           └────┬─────┘
         │               │                │
         └───────────────┼────────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   PERSIST    │
                  │              │
                  │ Auto-save to │
                  │ ~/.config/   │
                  │ vimcraft/    │
                  │ conversations│
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   RESTORE    │
                  │              │
                  │ Load on      │
                  │ restart      │
                  └──────────────┘
```

**Operations:**
- **create():** Initialize new conversation
- **append():** Add message to history
- **compress():** Reduce token count (keep recent messages)
- **fork():** Branch conversation from a point
- **tokens():** Calculate total tokens
- **Persistence:** Auto-save on changes, restore on restart

---

## 7. Comparison: Without vs With Conversation

**The fundamental difference in approach.**

```
┌─────────────────────────────────────────────────────────────┐
│           WITHOUT CONVERSATION (Old Approach)               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Plugin A:               Plugin B:               Plugin C:  │
│  ┌──────────┐           ┌──────────┐           ┌──────────┐│
│  │ history: │           │ history: │           │ history: ││
│  │ []       │           │ []       │           │ []       ││
│  └──────────┘           └──────────┘           └──────────┘│
│       │                      │                      │       │
│       ▼                      ▼                      ▼       │
│  Reviews code          Generates tests        Writes docs  │
│                                                             │
│  PROBLEM: Each plugin has its own state!                   │
│           No collaboration possible!                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│            WITH CONVERSATION (New Approach)                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                  ┌─────────────────────┐                    │
│                  │   Conversation      │                    │
│                  │   "improve-code"    │                    │
│                  │                     │                    │
│                  │ messages: [...]     │                    │
│                  └──────────┬──────────┘                    │
│                             │                               │
│              ┌──────────────┼──────────────┐               │
│              │              │              │               │
│         Plugin A       Plugin B       Plugin C             │
│         Reviews        Tests          Docs                 │
│              │              │              │               │
│              └──────────────┼──────────────┘               │
│                             │                               │
│                    ALL share state!                         │
│                                                             │
│  SOLUTION: Conversation is the shared medium!              │
│            Multi-agent workflows just work!                │
└─────────────────────────────────────────────────────────────┘
```

**Impact:**
- **Without:** Each plugin isolated, manual coordination needed
- **With:** Plugins compose naturally, zero coordination overhead

---

## 8. The Full Dependency Graph

**How primitives depend on each other.**

```
                    ┌──────────────────────┐
                    │   USER PLUGINS       │
                    │   (Infinite)         │
                    └──────────┬───────────┘
                               │
                               │ depends on
                               ▼
         ┌─────────────────────────────────────┐
         │  PRIMITIVE 0: Conversation          │
         │  (THE BACKBONE)                     │
         │                                     │
         │  Dependencies: None                 │
         │  Used by: All other primitives      │
         └──────────┬──────────────────────────┘
                    │
         ┌──────────┼──────────┐
         │          │          │
         ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐
    │ Stream │ │Provider│ │Context │
    │        │ │        │ │        │
    │ Deps:  │ │ Deps:  │ │ Deps:  │
    │ • Conv │ │ • Conv │ │ • Editor│
    │ • SSE  │ │        │ │ • Conv │
    └───┬────┘ └────────┘ └────────┘
        │
        │ depends on
        ▼
    ┌────────┐
    │ Parser │
    │        │
    │ Deps:  │
    │ None   │
    │ (Pure) │
    └────────┘

    ┌────────┐ ┌────────┐ ┌────────┐
    │ Token  │ │ Format │ │ Tools  │
    │ Est    │ │        │ │        │
    │        │ │        │ │        │
    │ Deps:  │ │ Deps:  │ │ Deps:  │
    │ • Conv │ │ None   │ │ None   │
    └────────┘ └────────┘ └────────┘
```

**Dependency Analysis:**
- **Conversation:** No dependencies (foundation)
- **Stream API:** Depends on Conversation + SSE Parser
- **Provider Abstraction:** Depends on Conversation
- **Context Helpers:** Depends on Editor APIs + Conversation
- **Tool Call Parser:** Pure (no dependencies)
- **Helpers:** Minimal dependencies

**Implementation Order:**
1. Conversation (the foundation)
2. Pure primitives (Parser, Format, Tools)
3. Primitives that depend on Conversation (Stream, Provider, Context)

---

## Summary

**Key Architectural Principles:**

1. **Conversation is the central entity** - Just like Buffer for editing
2. **Multi-plugin collaboration is automatic** - Shared state enables composition
3. **Clear dependency hierarchy** - Conversation at the foundation
4. **Users compose workflows** - Primitives are building blocks, not solutions
5. **Persistence across sessions** - Conversations survive restarts

**Visual Relationships:**
- **1-2:** Show the conceptual foundation (central entity + hierarchy)
- **3-4:** Show how it works in practice (multi-agent + architecture)
- **5-6:** Show implementation details (data flow + state machine)
- **7-8:** Show the impact (comparison + dependencies)

**Next Steps:**
- Implement Conversation first (Phase 5.0)
- Build other primitives on top
- Enable users to compose multi-agent workflows
