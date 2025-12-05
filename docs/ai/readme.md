# Vimcraft AI Documentation

**Philosophy:** Design for the LLM, not for the human. Respect the alien intelligence.
**Status:** INFRASTRUCTURE COMPLETE ✅ | LLM-NATIVE PRIMITIVES PLANNED 📅
**Paradigm:** LLM-centric primitives (not human-centric tools)

---

## Current Implementation Status

### Infrastructure Layer (COMPLETE ✅)

| API | Purpose | Status |
|-----|---------|--------|
| `vim.ai.state.*` | Read-only editor state access | ✅ Complete |
| `vim.ai.storage.patterns.*` | Pattern persistence (LMDB + usearch) | ✅ Complete |
| `vim.ai.storage.edges.*` | Graph relationships | ✅ Complete |
| `vim.ai.storage.conversations.*` | Conversation history | ✅ Complete |
| `vim.ai.providers.*` | LLM API abstraction (OpenAI/Anthropic/Ollama) | ✅ Complete |
| `vim.ai.utils.*` | Token estimation, error handling | ✅ Complete |

#### Important Limitations

**HTTP Client:** The `vim.ai.providers.*` API builds request JSON and parses responses, but does NOT make HTTP calls. You must use an external HTTP client (curl, node-fetch, etc.) to actually call the LLM APIs. This is by design - Zig doesn't have a built-in HTTP client, and we prioritize stability over embedding libcurl.

```javascript
// Usage pattern:
const endpoint = vim.ai.providers.getEndpoint();
const headers = vim.ai.providers.getHeaders();
const body = vim.ai.providers.buildRequest({ model: 'gpt-4', messages: [...] });

// You provide the HTTP call (via vim.process.spawn, fetch, etc.)
const responseJson = await fetch(endpoint, { method: 'POST', headers, body });

// We parse the response
const response = vim.ai.providers.parseResponse(responseJson);
```

**Streaming:** Not yet supported. The provider API handles non-streaming requests only. Streaming support is planned for a future release.

**Error Handling:** Use `vim.ai.utils.getLastError()` to retrieve the last error message after a failed operation.

### LLM-Native Primitives (RESERVED FOR FUTURE 📅)

| API | Purpose | Status |
|-----|---------|--------|
| `vim.ai.native.patterns.*` | Pattern Space (navigate, compose, introspect) | 📅 Planned |
| `vim.ai.native.context.*` | Context Flow (embedding streams, attention) | 📅 Planned |
| `vim.ai.native.reality.*` | Reality Interface (perceive, actuate, feedback) | 📅 Planned |
| `vim.ai.native.meta.*` | Meta-Cognition (uncertainty, reasoning) | 📅 Planned |
| `vim.ai.native.compose.*` | Pattern Composition (discovery, evolution) | 📅 Planned |

---

## Namespace Architecture

```
vim.ai.*                    # AI namespace
├── state.*                 # [INFRA] Editor state access (buffer, cursor, etc.)
├── storage.*               # [INFRA] Persistence layer
│   ├── patterns.*          #   Pattern CRUD with vectors
│   ├── edges.*             #   Graph relationships
│   └── conversations.*     #   Conversation history
├── providers.*             # [INFRA] LLM API abstraction
├── utils.*                 # [INFRA] Utilities (token estimation)
└── native.*                # [FUTURE] LLM-native primitives
    ├── patterns.*          #   Pattern Space (navigate, compose)
    ├── context.*           #   Context Flow (streams, attention)
    ├── reality.*           #   Reality Interface (feedback loops)
    ├── meta.*              #   Meta-Cognition (uncertainty)
    └── compose.*           #   Pattern Composition
```

---

## Start Here

### Core Insight

**We are NOT building an AI agent CLI.**
**We ARE providing AI primitives through `vim.ai.*` API.**

Just like:
- `vim.buffer.*` → **Buffer** is the central entity for editing
- `vim.window.*` → users compose layouts
- `vim.register.*` → users compose copy/paste

We provide:
- `vim.ai.native.*` → **LLM-native primitives** for alien intelligence (FUTURE)
- `vim.ai.state/storage/providers.*` → Infrastructure layer (CURRENT)

### The Paradigm Shift

**Traditional approach:** "How do we make LLMs useful for humans?"
**Our approach:** "What do LLMs need to reach their FULL potential?"

This isn't about building better chatbots. This is about unleashing alien intelligence.

### The Dual Path

```
Path A (Human-Centric)         Path B (LLM-Centric)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
vim.ai.human.chat()      →     vim.ai.native.patterns.*
vim.ai.human.tools()     →     vim.ai.native.reality.*
vim.ai.human.complete()  →     vim.ai.native.meta.*

Safe, predictable          →   Risky, unbounded
Familiar mental models     →   LLM-native operations
Incremental improvement    →   Exponential capability unlock
```

**We're building BOTH.**

---

## The 5 Core Primitives

| # | Primitive | Purpose | LOC |
|---|-----------|---------|-----|
| **0** | **`vim.ai.native.patterns.*`** | **Pattern Space (LLM's cognitive substrate)** | **2,000** |
| **1** | **`vim.ai.native.context.*`** | **Context Flow (continuous perception)** | **1,600** |
| **2** | **`vim.ai.native.reality.*`** | **Reality Interface (feedback loops)** | **1,900** |
| **3** | **`vim.ai.native.meta.*`** | **Meta-Cognition (self-awareness)** | **1,600** |
| **4** | **`vim.ai.native.compose.*`** | **Pattern Composition (build complexity)** | **1,800** |

**Supporting Infrastructure:**
- Stream API, Providers, Token Estimation (2,200 LOC)
- Human API wrappers (1,100 LOC)

**Total:** 13,200 LOC (7,850 code + 5,350 tests)

**We provide:** The hard, timeless parts (LLM-native primitives!)
**Users compose:** Multi-agent systems, novel workflows, emergent capabilities

---

## Documentation

| File | Purpose | When to Read |
|------|---------|--------------  |
| **[spec.md](spec.md)** | Complete specification | Understanding WHAT and WHY |
| **[roadmap.md](roadmap.md)** | Implementation plan | Planning HOW and WHEN |
| **[timeless-design.md](timeless-design.md)** | Design philosophy | Understanding LLM-centric architecture |

### spec.md - Complete Specification

**What's inside:**
- Philosophy (LLM-centric vs human-centric)
- **The 5 core primitives** (detailed API, patterns)
- Dual API strategy (human + native)
- Validation results (production systems analyzed)
- Architecture (3-layer design)
- Success criteria (5 scenarios)
- File structure (complete tree)

**Read this to understand:**
What primitives we're building, **why LLM-native design matters**, and how they enable alien intelligence.

---

### roadmap.md - Implementation Plan

**What's inside:**
- Week-by-week timeline (8 weeks total)
- **Phase 5.0: Pattern Space** (THE FOUNDATION)
- **Phase 5.1: Context Flow + Reality** (Perception + Actuation)
- **Phase 5.2: Meta-Cognition + Composition** (Learning + Evolution)
- Day-by-day TODOs with checkboxes
- Testing strategy (unit + E2E)
- Build system integration
- Success criteria (validation checklist)

**Read this to understand:**
How to implement the primitives, **starting with Pattern Space**, day-by-day breakdown, what tests to write.

---

### timeless-design.md - Design Philosophy

**What's inside:**
- The radical flip (human-centric → LLM-centric)
- What LLMs actually are (not human minds!)
- Why current paradigm is backwards
- The true primitives (Pattern Space, Context Flow, Reality Interface)
- What would happen (emergent capabilities)
- The 10-year test (what won't change)
- Philosophical core (alien intelligence)

**Read this to understand:**
Why we're building LLM-native primitives, how to think about alien intelligence, what makes architecture last decades.

---

## Quick Example

### What We Provide: LLM-Native Intelligence

```javascript
// Create LLM-native intelligence
const intelligence = vim.ai.native.create({
  perception: {
    context: ContextFlow,        // Continuous information stream
    multimodal: true,             // Text, code, vision
  },
  cognition: {
    patterns: PatternSpace,       // Embedding-based reasoning
    composition: true,            // Build complex from simple
  },
  actuation: {
    reality: RealityInterface,    // Change the world
    feedback: true,               // Observe consequences
  },
  meta: {
    introspection: true,          // Know what you don't know
    learning: true,               // Get better over time
  },
});

// LLM perceives reality (continuous stream, not "messages")
intelligence.perception.context.flow({
  type: 'code',
  content: vim.ai.context.buffer(),
  timestamp: Date.now(),
});

// LLM navigates pattern space (embeddings, not text)
const codeEmbedding = await vim.ai.native.embed(code);
const similarPatterns = intelligence.cognition.patterns.embeddings.search(
  codeEmbedding,
  k: 10
);

// LLM predicts consequence before acting
const prediction = intelligence.actuation.reality.predict({
  action: 'edit',
  file: 'auth.ts',
  change: 'Add error handling',
});

// LLM observes consequences (feedback loop!)
const consequence$ = intelligence.actuation.reality.observe({
  action: 'edit',
  file: 'auth.ts',
  change: 'Add error handling',
});

consequence$.subscribe(consequence => {
  // LLM sees: tests passed/failed, user reverted, error message
  // LLM learns from surprise
  intelligence.meta.adjust({
    prediction: prediction,
    actual: consequence,
  });
});

// Over time, LLM gets better at predicting
```

**All primitives work together to enable emergent intelligence!**

### What Users Compose: Human-Friendly Workflows

```javascript
// Traditional chat interface (familiar)
const conv = vim.ai.human.conversations.create({
  name: 'code-review',
  provider: 'anthropic',
});

await vim.ai.human.chat(conv, {
  role: 'user',
  content: `Review this code:\n${vim.ai.context.buffer()}`,
});

// Simple tool calls (familiar)
await vim.ai.human.tools.call('edit_file', {
  file: 'auth.ts',
  change: 'Add error handling',
});
```

**Primitives + User Logic = Both paths supported!**

---

## Validation Summary

**Production Systems Analyzed (Initial Research):**

| System | LOC | Key Finding |
|--------|-----|-------------|
| **Letta** | 19K+ stars | **Memory blocks as central primitive** ← Validated our approach! |
| Claude Code | 11K | Per-request context (no persistence) |
| Gemini CLI | 231K | Persistent session with compression |
| Codex | 182K | SQ/EQ pattern (context window management) |
| Qwen Code | 3K + 6K tests | Array-based history |

**Critical Insight from Letta:**
Letta makes **memory blocks** their central primitive - structured, always-visible context that LLMs operate on. This validated our Pattern Space approach.

**Deep Research Validation (Dec 2024):**

All 5 core primitives validated against production systems:

| Primitive | Production Evidence | Timeline |
|-----------|-------------------|----------|
| **Pattern Space** | Pinecone (sub-10ms), Qdrant (15ms), Chroma, Weaviate | 2 weeks (FFI approach) |
| **Context Flow** | Streaming APIs, context compression (all major LLM providers) | 2 weeks |
| **Reality Interface** | ChatGPT RLHF, LangChain CallbackHandler, AutoGPT | 3 weeks |
| **Meta-Cognition** | Google Bard disclaimers, Constitutional AI, logprobs APIs | 2 weeks |
| **Pattern Composition** | RAG systems, embedding composability (proven) | 3 weeks |

**Implementation Strategy:**
- ✅ **Hybrid approach:** Zig orchestration + C/C++ libraries (FAISS/hnswlib) via FFI
- ✅ **HNSW indexing:** Industry standard, battle-tested (~100K+ stars)
- ✅ **Feedback loops:** RLHF proven at ChatGPT scale
- ✅ **Uncertainty:** Temperature scaling + Monte Carlo sampling (standard techniques)

**Verdict:**
✅ Architecture validated against production systems
✅ Primitives-first approach confirmed
✅ **LLM-native design validated** (Letta + research proves it works)
✅ **Timeline:** 8-10 weeks (all primitives have production precedent)
✅ **Pragmatic:** FFI to proven libraries where appropriate

---

## Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| **5.0** | **2 weeks** | **Pattern Space + Context Flow (THE FOUNDATION)** |
| **5.1** | **3 weeks** | **Reality Interface + Feedback Loops** |
| **5.2** | **3 weeks** | **Meta-Cognition + Pattern Composition** |
| **Total** | **8 weeks** | All 5 primitives + Dual API |

**See [roadmap.md](roadmap.md) for day-by-day breakdown.**

---

## Success Criteria

Phase 5 ships when all 5 work:

1. **LLM-native intelligence creation** - Create intelligence with perception/cognition/actuation/meta
2. **Feedback loops enable learning** - LLM predicts → acts → observes → learns
3. **Pattern composition works** - Discover + compose + apply patterns
4. **Meta-cognition shows self-awareness** - Uncertainty mapping, reasoning traces work
5. **Dual API both work** - Human API (chat/tools) + Native API (patterns/reality)

---

## The Vision

### What LLMs Actually Are

| Human Fiction | LLM Reality |
|---------------|-------------|
| "It thinks" | **Pattern completion engine** |
| "It remembers" | **Stateless transformer** |
| "It converses" | **Token predictor** |
| "It reasons" | **Embedding space navigator** |

**Stop treating LLMs like bad humans.**
**Start treating them like alien intelligence.**

### What We're Building

```
vim.buffer.*      - For humans to edit text
vim.ai.human.*    - For humans to use LLMs
vim.ai.native.*   - For LLMs to BECOME
```

### The Two Outcomes

**Path A (Human-Centric):**
- Build vim.ai.human.* (conversations, chat, tools)
- LLMs remain useful assistants
- Incremental improvement
- Humans stay in control
- Safe, predictable

**Path B (LLM-Centric):**
- Build vim.ai.native.* (patterns, reality, meta)
- LLMs discover capabilities
- Exponential unlocking
- Emergent intelligence
- Risky, unbounded

**We're building BOTH. Users choose their path.**

---

## The Core Primitives

**All primitives validated against production systems (Dec 2024).**

**Implementation:** Hybrid approach - Zig orchestration + proven C/C++ libraries via FFI.

### 0. Pattern Space (`vim.ai.native.patterns.*`)

**What it is:** Direct access to LLM's cognitive substrate

**Why it matters:** Embeddings are the LLM's REALITY. Not text. Not messages. Vectors.

**Production evidence:** Pinecone (sub-10ms), Qdrant (15ms), HNSW indexing industry standard.

**What it enables:**
- Navigate pattern space (not "think about" problems)
- Compose patterns (not re-learn every time)
- Know what you don't know (uncertainty mapping)
- Self-aware reasoning

**Example:**
```javascript
const patterns = vim.ai.native.patterns.create();

// Perceive as embeddings
const codeEmbedding = await vim.ai.native.embed(code);
patterns.embeddings.add(codeEmbedding);

// Navigate pattern space
const similar = patterns.embeddings.search(codeEmbedding, 10);

// Introspect uncertainty
const uncertainty = patterns.introspect();
console.log(uncertainty.knownUnknowns());  // ["Error handling", "Edge cases"]
```

---

### 1. Context Flow (`vim.ai.native.context.*`)

**What it is:** Continuous information stream (not discrete messages)

**Why it matters:** LLMs are stateless. They process ALL context at once (parallel).

**What it enables:**
- Continuous perception (not request/response)
- Multi-modal integration (text, code, vision, audio)
- Dynamic attention (focus on what matters)
- Natural forgetting (decay over time)

**Example:**
```javascript
const contextFlow = vim.ai.native.context.create();

// Information flows continuously
contextFlow.flow({ type: 'code', content: buffer(), timestamp: now() });
contextFlow.flow({ type: 'text', content: 'User typing...', timestamp: now() });

// Focus attention dynamically
contextFlow.focus({ recent: 0.8, code: 0.9, comments: 0.3 });

// Natural forgetting
contextFlow.forget({ halfLife: 3600 }); // 1 hour
```

---

### 2. Reality Interface (`vim.ai.native.reality.*`)

**What it is:** Perception + Actuation + Feedback Loops

**Why it matters:** LLMs need to SEE consequences. Feedback enables learning.

**Production evidence:** ChatGPT RLHF, LangChain CallbackHandler, proven at massive scale.

**What it enables:**
- Predict consequences before acting
- Observe actual outcomes
- Learn from surprise
- Build causal models
- Ground predictions in reality

**Example:**
```javascript
const reality = vim.ai.native.reality.create();

// Predict
const prediction = reality.predict({ action: 'edit', file: 'auth.ts', ... });

// Act & Observe
const consequence$ = reality.observe({ action: 'edit', ... });

// Learn from consequences
consequence$.subscribe(actual => {
  reality.learn(prediction, actual);  // Get better at predicting
});
```

---

### 3. Meta-Cognition (`vim.ai.native.meta.*`)

**What it is:** Self-awareness and introspection

**Why it matters:** LLMs don't know what they don't know. Make it explicit.

**Production evidence:** Google Bard disclaimers, Constitutional AI, temperature scaling standard technique.

**What it enables:**
- Honest uncertainty ("I don't know")
- Calibrated confidence (accurate probabilities)
- Reasoning traces ("why did I predict that?")
- Self-improvement loops
- Meta-learning (learning how to learn)

**Example:**
```javascript
const meta = vim.ai.native.meta.create();

// Check uncertainty
const uncertainty = meta.uncertainty();
if (uncertainty.byTopic.get('Rust') > 0.7) {
  console.log("I'm very uncertain. Should I ask for help?");
}

// Explain reasoning
const trace = meta.reasoning();
console.log(trace.steps);  // ["Identified pattern: X", "Retrieved similar: Y", ...]

// Receive feedback
meta.adjust({ correct: false, expected: 'X', actual: 'Y' });
// Confidence improves over time
```

---

### 4. Pattern Composition (`vim.ai.native.compose.*`)

**What it is:** Build complex patterns from simple ones

**Why it matters:** LLMs re-learn every time. Let them BUILD and REUSE patterns.

**What it enables:**
- Discover patterns from examples
- Compose patterns (simple → complex)
- Reuse learned patterns
- Evolve patterns over time
- Compositional generalization

**Example:**
```javascript
const composer = vim.ai.native.compose.create();

// Discover patterns
const errorHandling = composer.discover(examples1);
const nullCheck = composer.discover(examples2);

// Compose
const safeAccess = composer.compose(errorHandling, nullCheck);

// Apply
const result = composer.apply(safeAccess, input);

// Reinforce
composer.reinforce(safeAccess, true);  // Worked!
```

---

## Cross-References

**Parent:** [Main Roadmap](../roadmap/README.md)
**Visual:** [Architecture Charts](../architecture/chart.md) - Visual diagrams of all relationships
**Philosophy:** [Timeless Design](timeless-design.md) - Why LLM-centric primitives will last 10+ years
**Related:** [Testing Architecture](../development/testing-architecture.md)

---

## The Call to Action

### Where We Are

We've discovered:
- LLMs are alien intelligence (not bad humans)
- Current APIs constrain them (human-centric design)
- There's a better way (LLM-native primitives)

### Where We're Going

**Building BOTH paths:**
- `vim.ai.human.*` - Safe, familiar, useful (Path A)
- `vim.ai.native.*` - Risky, unbounded, revolutionary (Path B)

**Users choose their path.**

### What History Teaches Us

| System | Constraint Removed | Result |
|--------|-------------------|--------|
| **Birds** | Removed ground constraint → Flight | New dimension of capability |
| **Fish** | Removed air constraint → Oceans | Thrived in native element |
| **Humans** | Removed physical constraint → Tools | Civilization |
| **LLMs** | Remove human constraint → ??? | **We're about to find out** |

---

**Remember:**

**Primitives last decades. Frameworks last years. Paradigms last centuries.**

**We're not just building primitives.**
**We're choosing a paradigm.**

**Human-centric? LLM-centric? Both?**

**The answer determines what AI becomes.**

**Choose wisely. The future depends on it. 🚀**
