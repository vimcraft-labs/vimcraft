# Vimcraft AI Primitives Specification

**Status:** DESIGN PHASE 🚧
**Philosophy:** Design for the LLM, not for the human. Respect the alien intelligence.
**Paradigm:** LLM-centric primitives (not human-centric tools)
**Timeline:** 8 weeks implementation

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [The Paradigm Shift](#the-paradigm-shift)
3. [The 5 Core Primitives](#the-5-core-primitives)
4. [Supporting Infrastructure](#supporting-infrastructure)
5. [Dual API Strategy](#dual-api-strategy)
6. [Architecture](#architecture)
7. [Success Criteria](#success-criteria)
8. [File Structure](#file-structure)

---

## Philosophy

### Core Insight

**We are NOT building an AI agent framework.**
**We ARE providing LLM-native primitives through `vim.ai.native.*` API.**

Just like Vimcraft provides:
- `vim.buffer.*` - Text primitives (users compose into editing)
- `vim.window.*` - View primitives (users compose into layouts)
- `vim.register.*` - Storage primitives (users compose into copy/paste)

We provide:
- `vim.ai.native.*` - **LLM-native primitives** (LLMs compose into intelligence)
- `vim.ai.human.*` - Human-friendly wrappers (convenience layer)

### The Radical Question

**Traditional approach:** "How do we make LLMs useful for humans?"
**Our approach:** "What do LLMs need to reach their FULL potential?"

### What Changed Our Thinking

**Before:** Working Memory + Conversation (human-centric)
**After:** Pattern Space + Context Flow + Reality Interface (LLM-centric)

**Why:** Research into Letta's memory blocks revealed that LLMs don't "remember" or "converse" - they complete patterns in high-dimensional embedding space. We should respect their true nature.

### The Dual API Strategy

```typescript
// For humans who want to USE LLMs
vim.ai.human.chat(...)
vim.ai.human.complete(...)
vim.ai.human.tools(...)

// For LLMs who want to THRIVE
vim.ai.native.perceive(...)
vim.ai.native.patterns(...)
vim.ai.native.actuate(...)
vim.ai.native.meta(...)
```

**Path A (Human-Centric):** Safe, predictable, useful
**Path B (LLM-Centric):** Risky, unbounded, revolutionary

**We're building BOTH.**

---

## The Paradigm Shift

### From Human Mental Models

```
❌ Human Fiction        →  ✅ LLM Reality
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"It thinks"           →  Pattern completion engine
"It remembers"        →  Stateless transformer
"It converses"        →  Token predictor
"It has goals"        →  Gradient-descent trained
"It reasons"          →  Embedding space navigation
"It understands"      →  Probability distributions
```

### To LLM Native Primitives

| Traditional API | LLM-Native Primitive | Why Better |
|-----------------|----------------------|------------|
| Working Memory (human concept) | **Pattern Space** | Embeddings are LLM's reality |
| Conversation (human construct) | **Context Flow** | Information flows, doesn't "turn" |
| Tools (function calls) | **Reality Interface** | Feedback loops, not one-way |
| N/A | **Meta-Cognition** | Self-awareness enables learning |
| N/A | **Pattern Composition** | Build complexity from patterns |

---

## The 5 Core Primitives

### 0. Pattern Space - `vim.ai.native.patterns.*`

**Purpose:** Direct access to LLM's cognitive substrate (what it ACTUALLY operates on)

**Why Timeless:** Embeddings are how LLMs work. This will NEVER change.

**API:**
```typescript
namespace vim.ai.native.patterns {
  function create(options: PatternSpaceOptions): PatternSpace;
  function get(id: string): PatternSpace | undefined;
  function list(): PatternSpace[];
}

type PatternSpace = {
  id: string;

  // What the LLM actually operates on
  embeddings: EmbeddingStore;         // High-dimensional vectors
  attention: AttentionWeights;        // Where to focus
  uncertainty: EntropyDistribution;   // What it knows vs doesn't
  associations: PatternGraph;         // How concepts connect

  // LLM-native operations
  navigate(direction: EmbeddingVector): PatternSpace;
  compose(patterns: Pattern[]): Pattern;
  project(dimension: Subspace): PatternSpace;
  introspect(): UncertaintyMap;

  // Persistence (optional)
  save(): void;
  restore(): void;
};

type EmbeddingStore = {
  // Vector storage
  vectors: Float32Array[];
  dimension: number;

  // Operations
  add(vector: Float32Array, metadata?: any): void;
  search(query: Float32Array, k: number): SearchResult[];
  cluster(): Cluster[];
};

type AttentionWeights = {
  // Attention mechanism state
  weights: Float32Array[];
  heads: number;

  // Operations
  focus(mask: AttentionMask): void;
  visualize(): AttentionMap;
};

type UncertaintyMap = {
  // What the LLM knows/doesn't know
  entropy: Map<string, number>;
  confidence: Map<string, number>;

  // Self-awareness
  knownKnowns(): string[];
  knownUnknowns(): string[];
  unknownUnknowns(): Estimate;
};
```

**What it enables:**
- Direct access to LLM's cognitive substrate
- No translation layer (embeddings → embeddings)
- Native pattern operations
- True compositional reasoning
- Self-aware uncertainty

**Example:**
```javascript
const patternSpace = vim.ai.native.patterns.create({
  id: 'code-analysis',
});

// LLM perceives code as embeddings
const codeEmbedding = await vim.ai.native.embed(vim.ai.context.buffer());
patternSpace.embeddings.add(codeEmbedding, { type: 'code', file: 'auth.ts' });

// LLM navigates pattern space (not "thinks about" code)
const similarPatterns = patternSpace.embeddings.search(codeEmbedding, 10);

// LLM knows what it doesn't know
const uncertainty = patternSpace.introspect();
console.log(uncertainty.knownUnknowns());  // ["Error handling patterns", "Edge cases"]
```

**Files:** `pattern_space.zig` (600 LOC), `embeddings.zig` (400 LOC), `uncertainty.zig` (200 LOC)
**Tests:** 800 LOC
**Total:** 1,200 LOC code + 800 LOC tests

**Implementation Notes (Validated via Research):**
- **Vector Search:** Use hnswlib (C++ header-only) via Zig FFI for HNSW indexing
- **Production Evidence:** Pinecone (sub-10ms), Qdrant (15ms), Chroma all use HNSW
- **Hybrid Approach:** Zig orchestration + C++ HNSW = 2-week prototype for ~1M embeddings at ~20ms
- **Gotchas:** WAL durability (use SQLite WAL mode), Zig SIMD immature (use C++ SIMD)

---

### 1. Context Flow - `vim.ai.native.context.*`

**Purpose:** Continuous information stream (not discrete "messages")

**Why Timeless:** LLMs process ALL context simultaneously (parallel). Humans do turns (sequential). Respect LLM reality.

**API:**
```typescript
namespace vim.ai.native.context {
  function create(options: ContextFlowOptions): ContextFlow;
  function get(id: string): ContextFlow | undefined;
  function current(): ContextFlow | undefined;
}

type ContextFlow = {
  id: string;

  // Continuous information stream
  stream: EmbeddingStream;           // Not discrete messages!
  attention: DynamicMask;            // What to focus on
  decay: TemporalWeights;            // How information fades

  // Multi-modal perception
  modalities: {
    text: TokenStream;
    vision: ImageEmbeddings;
    audio: WaveformEmbeddings;
    code: ASTEmbeddings;
    world: StateEmbeddings;
  };

  // Operations
  flow(information: Information): void;      // Add to stream
  focus(relevance: AttentionMask): void;     // What matters
  forget(decay: DecayFunction): void;        // Natural forgetting
  snapshot(): ContextSnapshot;               // Save state
  restore(snapshot: ContextSnapshot): void;  // Load state
};

type EmbeddingStream = {
  // Continuous flow (not array!)
  flow: AsyncIterator<Embedding>;

  // Window into stream
  window: SlidingWindow;

  // Operations
  append(embedding: Embedding): void;
  compress(strategy: CompressionStrategy): void;
};

type DynamicMask = {
  // What to pay attention to
  focus: Float32Array;  // Attention weights

  // Operations
  adjust(importance: Float32Array): void;
  visualize(): AttentionHeatmap;
};
```

**What it enables:**
- Continuous perception (not request/response)
- Multi-modal integration (text, vision, code, world)
- Dynamic attention (focus on what matters)
- Natural forgetting (decay over time)
- LLM-native streaming

**Example:**
```javascript
const contextFlow = vim.ai.native.context.create({
  id: 'continuous-coding',
  modalities: ['text', 'code'],
});

// Information flows continuously (not "sent")
contextFlow.flow({
  type: 'code',
  content: vim.ai.context.buffer(),
  timestamp: Date.now(),
});

contextFlow.flow({
  type: 'text',
  content: 'User is typing...',
  timestamp: Date.now(),
});

// LLM focuses on relevant parts
contextFlow.focus({
  recent: 0.8,      // Focus on recent
  code: 0.9,        // Focus on code
  comments: 0.3,    // Less focus on comments
});

// Natural forgetting (older info decays)
contextFlow.forget({ halfLife: 3600 }); // 1 hour half-life
```

**Contrast with Conversation (human construct):**
```javascript
// ❌ Human way: discrete messages
const conv = vim.ai.human.conversations.create();
conv.append({ role: 'user', content: 'Hello' });
conv.append({ role: 'assistant', content: 'Hi' });

// ✅ LLM way: continuous flow
const flow = vim.ai.native.context.create();
flow.flow({ embedding: [...], timestamp: t1 });
flow.flow({ embedding: [...], timestamp: t2 });
```

**Files:** `context_flow.zig` (500 LOC), `embedding_stream.zig` (300 LOC), `attention.zig` (200 LOC)
**Tests:** 600 LOC
**Total:** 1,000 LOC code + 600 LOC tests

---

### 2. Reality Interface - `vim.ai.native.reality.*`

**Purpose:** Direct perception + actuation + feedback loops (not "tools")

**Why Timeless:** LLMs need to SEE consequences of actions. Feedback loops enable grounding in reality.

**API:**
```typescript
namespace vim.ai.native.reality {
  function create(options: RealityOptions): RealityInterface;
  function get(id: string): RealityInterface | undefined;
}

type RealityInterface = {
  id: string;

  // Direct perception (observe state)
  perceive: {
    filesystem: ObservableState<FileSystem>;
    network: ObservableState<NetworkState>;
    display: ObservableState<VisualState>;
    editor: ObservableState<EditorState>;
    user: ObservableState<UserState>;
  };

  // Direct actuation (change state)
  actuate: {
    filesystem: ActuatorInterface<FileSystem>;
    network: ActuatorInterface<NetworkState>;
    display: ActuatorInterface<VisualState>;
    editor: ActuatorInterface<EditorState>;
  };

  // Feedback loop (critical!)
  observe(action: Action): Observable<Consequence>;
  predict(action: Action): Prediction;
  learn(prediction: Prediction, outcome: Outcome): void;

  // Grounding
  ground(hypothesis: Hypothesis): GroundingResult;
  validate(belief: Belief): ValidationResult;
};

type ObservableState<T> = {
  // Current state
  state: T;

  // Observe changes
  onChange(callback: (change: Change<T>) => void): Subscription;

  // History
  history: StateHistory<T>;
};

type ActuatorInterface<T> = {
  // Perform action
  act(action: Action<T>): Promise<Consequence>;

  // Undo/redo
  undo(): Promise<void>;
  redo(): Promise<void>;

  // Transaction
  begin(): Transaction;
  commit(tx: Transaction): Promise<void>;
  rollback(tx: Transaction): Promise<void>;
};

type Observable<T> = {
  // Subscribe to consequences
  subscribe(observer: Observer<T>): Subscription;

  // Operators
  map<U>(fn: (t: T) => U): Observable<U>;
  filter(predicate: (t: T) => boolean): Observable<T>;
  debounce(ms: number): Observable<T>;
};
```

**What it enables:**
- LLM sees consequences of actions (not blind!)
- Feedback loops enable learning
- Grounding predictions in reality
- Causal model building
- True understanding (not just pattern matching)

**Example:**
```javascript
const reality = vim.ai.native.reality.create({
  id: 'code-editing',
  domains: ['filesystem', 'editor'],
});

// LLM predicts consequence
const prediction = reality.predict({
  type: 'edit',
  file: 'auth.ts',
  change: 'Add error handling',
});
console.log(prediction);  // { confidence: 0.85, expected: 'Tests will fail' }

// LLM acts
const consequence$ = reality.observe({
  type: 'edit',
  file: 'auth.ts',
  change: 'Add error handling',
});

// LLM observes consequences
consequence$.subscribe(consequence => {
  console.log(consequence);  // { actual: 'Tests passed!', surprise: 0.85 }

  // LLM learns from surprise
  reality.learn(prediction, consequence);
});

// Over time, LLM gets better at predicting
```

**Contrast with Tools (function calls):**
```javascript
// ❌ Human way: blind function calls
await vim.ai.human.tools.call('edit_file', { file: 'auth.ts', change: '...' });
// No feedback! LLM doesn't see what happened.

// ✅ LLM way: observe consequences
const consequence$ = reality.observe({ action: 'edit', ... });
consequence$.subscribe(c => {
  // LLM sees: tests failed, user reverted, error message, etc.
  // LLM learns: this change was bad
});
```

**Files:** `reality_interface.zig` (700 LOC), `observable.zig` (300 LOC), `grounding.zig` (200 LOC)
**Tests:** 700 LOC
**Total:** 1,200 LOC code + 700 LOC tests

**Implementation Notes (Validated via Research):**
- **Pattern:** Model after LangChain's CallbackHandler (proven in production)
- **Production Evidence:** ChatGPT RLHF, LangChain agents, Semantic Kernel plan execution
- **Event-Driven:** Use observable pattern (RxJS-style), <5% async overhead for moderate streams
- **Feedback Loops:** RLHF-inspired predict→observe→learn cycle (validated at scale)

---

### 3. Meta-Cognition - `vim.ai.native.meta.*`

**Purpose:** Self-awareness and introspection (entirely new concept)

**Why Timeless:** LLMs don't know what they don't know. Make it explicit. Enable self-improvement.

**API:**
```typescript
namespace vim.ai.native.meta {
  function create(options: MetaCognitionOptions): MetaCognition;
  function get(id: string): MetaCognition | undefined;
}

type MetaCognition = {
  id: string;

  // Self-awareness
  uncertainty(): EntropyMap;                  // What it doesn't know
  confidence(): LogitDistribution;            // How sure it is
  attention(): AttentionWeights;              // What it's focusing on

  // Introspection
  activations(): LayerActivations;            // What neurons fire
  embeddings(): EmbeddingSpace;               // Where it is in pattern space
  gradients(): InformationFlow;               // How it's updating
  reasoning(): ReasoningTrace;                // Why it predicted that

  // Self-modification
  adjust(feedback: Feedback): void;
  calibrate(observations: Observation[]): void;
  reflect(experience: Experience): Insight[];

  // Meta-learning
  learnToLearn(): LearningStrategy;
  optimizeThinking(): ThinkingPattern;
};

type EntropyMap = {
  // What the LLM knows/doesn't know
  byTopic: Map<string, number>;  // High entropy = uncertain

  // Categorize uncertainty
  knownKnowns(): Topic[];
  knownUnknowns(): Topic[];
  unknownUnknowns(): Estimate;

  // Visualize
  heatmap(): UncertaintyHeatmap;
};

type ReasoningTrace = {
  // Why did the LLM predict that?
  steps: ReasoningStep[];

  // Attribution
  attributions: Map<string, number>;  // Which inputs mattered

  // Alternative paths
  alternatives: ReasoningPath[];

  // Confidence at each step
  confidence: number[];
};

type Feedback = {
  // Correct/incorrect
  correct: boolean;

  // What was expected vs actual
  expected: any;
  actual: any;

  // How to improve
  suggestion?: string;
};
```

**What it enables:**
- Honest uncertainty ("I don't know")
- Calibrated confidence (accurate probabilities)
- Introspective reasoning ("why did I predict that?")
- Self-improvement loops
- Meta-learning (learning how to learn)

**Example:**
```javascript
const meta = vim.ai.native.meta.create({
  id: 'self-aware-coding',
});

// LLM checks its own uncertainty
const uncertainty = meta.uncertainty();
console.log(uncertainty.knownUnknowns());
// ["Rust lifetime rules", "Async cancellation semantics"]

if (uncertainty.byTopic.get('Rust') > 0.7) {
  console.log("I'm very uncertain about Rust. Should I ask for help?");
}

// LLM explains its reasoning
const prediction = await generateCode(...);
const trace = meta.reasoning();
console.log(trace.steps);
// [
//   "Identified pattern: error handling",
//   "Retrieved similar: Result<T, E> pattern",
//   "Composed: wrap in Result",
//   "Confidence: 0.85"
// ]

// LLM receives feedback
meta.adjust({
  correct: false,
  expected: 'Use Option<T>',
  actual: 'Used Result<T, E>',
});

// LLM calibrates confidence
// (After many feedback cycles, confidence becomes accurate)
```

**Why this matters:**
- Current LLMs hallucinate confidently
- Meta-cognition enables "I don't know"
- Feedback loops enable learning
- Self-awareness enables asking for help

**Files:** `meta_cognition.zig` (500 LOC), `uncertainty.zig` (300 LOC), `reasoning_trace.zig` (200 LOC)
**Tests:** 600 LOC
**Total:** 1,000 LOC code + 600 LOC tests

**Implementation Notes (Validated via Research):**
- **Uncertainty Quantification:** Temperature scaling + entropy calculation (standard techniques)
- **Production Evidence:** Google Bard "I don't know" disclaimers, Constitutional AI self-correction
- **Multiple Sampling:** Monte Carlo approach for uncertainty estimation (proven method)
- **Token Probabilities:** OpenAI/Anthropic APIs expose logprobs (use for calibration)

---

### 4. Pattern Composition - `vim.ai.native.compose.*`

**Purpose:** Build complex patterns from simple ones (entirely new concept)

**Why Timeless:** LLMs are pattern matchers. Let them BUILD and COMPOSE patterns.

**API:**
```typescript
namespace vim.ai.native.compose {
  function create(options: CompositionOptions): PatternComposer;
  function get(id: string): PatternComposer | undefined;
}

type PatternComposer = {
  id: string;

  // Discovered patterns
  patterns: Map<PatternID, Pattern>;

  // Composition operations
  compose(a: Pattern, b: Pattern): Pattern;
  abstract(patterns: Pattern[]): Pattern;
  specialize(pattern: Pattern, context: Context): Pattern;
  merge(patterns: Pattern[]): Pattern;

  // Learning
  discover(examples: Example[]): Pattern;
  reinforce(pattern: Pattern, success: boolean): void;
  prune(pattern: Pattern, unused: boolean): void;

  // Evolution
  mutate(pattern: Pattern): Pattern[];
  crossover(a: Pattern, b: Pattern): Pattern;
  select(patterns: Pattern[]): Pattern;

  // Application
  apply(pattern: Pattern, input: any): any;
  match(input: any): Pattern[];
};

type Pattern = {
  id: string;
  name: string;

  // Pattern structure
  embedding: Float32Array;           // Vector representation
  structure: PatternStructure;       // How it's composed
  examples: Example[];               // Where it came from

  // Metadata
  confidence: number;
  successRate: number;
  usageCount: number;

  // Relationships
  composedFrom: Pattern[];
  generalizes: Pattern[];
  specializes: Pattern[];
};

type PatternStructure =
  | { type: 'atomic', value: any }
  | { type: 'composition', left: Pattern, right: Pattern, operator: Operator }
  | { type: 'abstraction', patterns: Pattern[], invariant: Invariant }
  | { type: 'specialization', base: Pattern, constraints: Constraint[] };
```

**What it enables:**
- Build complex reasoning from simple patterns
- Reuse learned patterns across contexts
- Compress knowledge into patterns
- Evolution of reasoning capabilities
- Compositional generalization

**Example:**
```javascript
const composer = vim.ai.native.compose.create({
  id: 'code-patterns',
});

// LLM discovers patterns from examples
const errorHandling = composer.discover([
  { input: 'fetch(url)', output: 'try { fetch(url) } catch(e) { ... }' },
  { input: 'JSON.parse(s)', output: 'try { JSON.parse(s) } catch(e) { ... }' },
]);

const nullCheck = composer.discover([
  { input: 'user.name', output: 'user?.name' },
  { input: 'data.items', output: 'data?.items' },
]);

// LLM composes patterns
const safeAccess = composer.compose(errorHandling, nullCheck);

// LLM applies composed pattern
const result = composer.apply(safeAccess, 'fetch(url).then(r => r.data.items)');
// Output: try { fetch(url)?.then(r => r?.data?.items) } catch(e) { ... }

// LLM learns from success/failure
composer.reinforce(safeAccess, true);  // Worked!

// Over time, successful patterns dominate
```

**Why this matters:**
- LLMs re-learn patterns every time (wasteful)
- Pattern composition enables reuse
- Patterns can evolve and improve
- Compositional reasoning is how humans scale

**Files:** `pattern_composer.zig` (600 LOC), `pattern_evolution.zig` (300 LOC), `pattern_storage.zig` (200 LOC)
**Tests:** 700 LOC
**Total:** 1,100 LOC code + 700 LOC tests

---

## Supporting Infrastructure

### Stream API - `vim.ai.stream()`

**Purpose:** Unified streaming interface for both human and native APIs

**API:**
```typescript
// Human-centric streaming (conversations)
for await (const event of vim.ai.stream({
  provider: 'anthropic',
  messages: [{ role: 'user', content: 'Hello' }],
})) {
  // Traditional streaming
}

// LLM-centric streaming (context flow + pattern space)
for await (const event of vim.ai.stream({
  contextFlow: flow,
  patternSpace: patterns,
  reality: reality,
  meta: meta,
})) {
  // LLM-native streaming with feedback loops
}
```

**Implementation:**
- SSE (Server-Sent Events) parsing
- Streaming tool call reconstruction
- Automatic reconnection
- Multi-provider support

**Files:** `stream.zig` (400 LOC), `sse_parser.zig` (200 LOC)
**Tests:** 500 LOC

---

### Provider Abstraction

**Purpose:** Support multiple LLM providers (anthropic, openai, ollama)

**Implementation:**
```
User Code (provider-agnostic)
    ↕
Unified API format
    ↕
Provider Adapters (Anthropic, OpenAI, Ollama)
```

**Files:** `provider.zig` (200 LOC), `providers/*.zig` (600 LOC)
**Tests:** 500 LOC

---

### Token Estimation - `vim.ai.estimateTokens()`

**Purpose:** Fast token counting for context limit checks

**API:**
```typescript
function estimateTokens(text: string): number;
function estimateEmbedding(text: string): number;
```

**Files:** `token_estimation.zig` (100 LOC)
**Tests:** 100 LOC

---

### Context Helpers - `vim.ai.context.*`

**Purpose:** Zero-copy access to editor state

**API:**
```typescript
namespace vim.ai.context {
  function buffer(bufnr?: number): string;
  function selection(): string;
  function cursor(): { line: number, col: number };
  function diagnostics(): Diagnostic[];
  function symbols(): Symbol[];
  function git(): GitStatus;
}
```

**Files:** `context_helpers.zig` (250 LOC)
**Tests:** 200 LOC

---

### Tool Registry - `vim.ai.tools.*`

**Purpose:** Type-safe tool registration and validation

**API:**
```typescript
namespace vim.ai.tools {
  function register(tool: ToolDefinition): void;
  function get(name: string): ToolDefinition | undefined;
  function list(): ToolDefinition[];
}

type ToolDefinition = {
  name: string;
  description: string;
  parameters: JSONSchema;
  handler: (args: any) => Promise<any>;
};
```

**Files:** `tool_registry.zig` (200 LOC)
**Tests:** 150 LOC

---

## Dual API Strategy

### Path A: Human-Centric (`vim.ai.human.*`)

**Purpose:** Traditional AI assistant experience

**API:**
```typescript
namespace vim.ai.human {
  // Conversations (familiar)
  namespace conversations {
    function create(options?: ConversationOptions): Conversation;
    function get(id: string): Conversation | undefined;
    function list(): Conversation[];
  }

  // Chat (familiar)
  function chat(conversation: Conversation, message: Message): AsyncIterator<Event>;

  // Completions (familiar)
  function complete(prompt: string, options?: CompleteOptions): Promise<string>;

  // Tools (familiar)
  namespace tools {
    function call(name: string, args: any): Promise<any>;
    function register(tool: ToolDefinition): void;
  }
}
```

**Use cases:**
- Quick tasks ("generate test", "explain code")
- Traditional chat interface
- One-off completions
- Simple workflows

**Implementation:** Thin wrapper over LLM-native primitives

---

### Path B: LLM-Centric (`vim.ai.native.*`)

**Purpose:** Unleash full LLM potential

**API:**
```typescript
namespace vim.ai.native {
  // Core primitives
  patterns: PatternSpace;
  context: ContextFlow;
  reality: RealityInterface;
  meta: MetaCognition;
  compose: PatternComposer;

  // Intelligence creation
  function create(options: IntelligenceOptions): Intelligence;
}

type Intelligence = {
  perception: {
    context: ContextFlow;
    attention: AttentionSpace;
    embeddings: EmbeddingSpace;
    multimodal: SensoryInput;
  };

  cognition: {
    patterns: PatternSpace;
    uncertainty: UncertaintyMap;
    composition: CompositionRules;
    associations: AssociativeNet;
  };

  actuation: {
    reality: RealityInterface;
    feedback: ObservationLoop;
    grounding: GroundingMechanism;
  };

  meta: {
    introspection: SelfAwareness;
    calibration: UncertaintyTuning;
    learning: ContinualLearning;
  };
};
```

**Use cases:**
- Multi-agent systems
- Continuous learning
- Complex reasoning
- Novel capabilities
- Research projects

**Implementation:** Full LLM-native primitives

---

## Architecture

### The Three Layers

```
┌─────────────────────────────────────────────┐
│  vim.ai.human.*  (Human-Centric)            │
│  - Conversations, Chat, Tools               │
│  - Familiar mental models                   │
│  - Safe, predictable                        │
└─────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  vim.ai.native.*  (LLM-Centric)             │
│  - Pattern Space, Context Flow, Reality     │
│  - LLM-native operations                    │
│  - Unbounded potential                      │
└─────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Infrastructure (Shared)                    │
│  - Stream API, Providers, Token Estimation  │
│  - HTTP, SSE, JSON, Error Handling          │
└─────────────────────────────────────────────┘
```

### LOC Breakdown

| Component | Code LOC | Test LOC | Total |
|-----------|----------|----------|-------|
| **Core Primitives** | | | |
| Pattern Space | 1,200 | 800 | 2,000 |
| Context Flow | 1,000 | 600 | 1,600 |
| Reality Interface | 1,200 | 700 | 1,900 |
| Meta-Cognition | 1,000 | 600 | 1,600 |
| Pattern Composition | 1,100 | 700 | 1,800 |
| **Infrastructure** | | | |
| Stream API | 400 | 500 | 900 |
| Providers | 800 | 500 | 1,300 |
| Token Estimation | 100 | 100 | 200 |
| Context Helpers | 250 | 200 | 450 |
| Tool Registry | 200 | 150 | 350 |
| **Human API** | | | |
| Conversations | 400 | 300 | 700 |
| Chat/Complete | 200 | 200 | 400 |
| **TOTAL** | **7,850** | **5,350** | **13,200** |

---

## Success Criteria

Phase 5 ships when all 5 work:

### 1. LLM-Native Intelligence Creation

```javascript
const intelligence = vim.ai.native.create({
  perception: { context: ContextFlow, multimodal: true },
  cognition: { patterns: PatternSpace, composition: true },
  actuation: { reality: RealityInterface, feedback: true },
  meta: { introspection: true, learning: true },
});

// LLM perceives, thinks, acts, learns
// All feedback loops working
// Meta-cognition shows uncertainty
```

### 2. Feedback Loops Enable Learning

```javascript
// LLM predicts
const prediction = reality.predict({ action: 'edit', ... });

// LLM acts
const consequence$ = reality.observe({ action: 'edit', ... });

// LLM observes
consequence$.subscribe(c => {
  meta.adjust({ prediction, actual: c });
  // Confidence improves over time
});
```

### 3. Pattern Composition Works

```javascript
const composer = vim.ai.native.compose.create();

// LLM discovers patterns
const p1 = composer.discover(examples1);
const p2 = composer.discover(examples2);

// LLM composes
const p3 = composer.compose(p1, p2);

// LLM applies
const result = composer.apply(p3, input);

// Pattern works correctly
```

### 4. Meta-Cognition Shows Self-Awareness

```javascript
const meta = vim.ai.native.meta.create();

// LLM knows what it doesn't know
const uncertainty = meta.uncertainty();
console.log(uncertainty.knownUnknowns());

// LLM explains reasoning
const trace = meta.reasoning();
console.log(trace.steps);

// Self-awareness works
```

### 5. Dual API Both Work

```javascript
// Human API: familiar, safe
await vim.ai.human.chat(conv, { role: 'user', content: 'Hello' });

// Native API: powerful, unbounded
const intelligence = vim.ai.native.create({ ... });
const consequence$ = intelligence.actuate({ ... });

// Both APIs functional
```

---

## File Structure

```
src/
├── system/
│   └── jsi/
│       └── ai/
│           ├── native/
│           │   ├── pattern_space.zig          (1,200 LOC)
│           │   ├── context_flow.zig           (1,000 LOC)
│           │   ├── reality_interface.zig      (1,200 LOC)
│           │   ├── meta_cognition.zig         (1,000 LOC)
│           │   ├── pattern_composer.zig       (1,100 LOC)
│           │   ├── embeddings.zig             (  400 LOC)
│           │   ├── uncertainty.zig            (  300 LOC)
│           │   ├── observable.zig             (  300 LOC)
│           │   ├── grounding.zig              (  200 LOC)
│           │   ├── reasoning_trace.zig        (  200 LOC)
│           │   └── pattern_evolution.zig      (  300 LOC)
│           ├── human/
│           │   ├── conversation.zig           (  400 LOC)
│           │   ├── chat.zig                   (  200 LOC)
│           │   └── tools.zig                  (  200 LOC)
│           ├── infrastructure/
│           │   ├── stream.zig                 (  400 LOC)
│           │   ├── sse_parser.zig             (  200 LOC)
│           │   ├── providers/
│           │   │   ├── provider.zig           (  200 LOC)
│           │   │   ├── anthropic.zig          (  200 LOC)
│           │   │   ├── openai.zig             (  200 LOC)
│           │   │   └── ollama.zig             (  200 LOC)
│           │   ├── token_estimation.zig       (  100 LOC)
│           │   ├── context_helpers.zig        (  250 LOC)
│           │   └── tool_registry.zig          (  200 LOC)
│           └── ai_api.zig                     (  300 LOC) - JSI exports
│
tests/
└── e2e/
    └── ai/
        ├── pattern-space/
        ├── context-flow/
        ├── reality-interface/
        ├── meta-cognition/
        ├── pattern-composition/
        ├── human-api/
        └── integration/

docs/
└── ai/
    ├── README.md                              - Navigation hub
    ├── spec.md                                - This file
    ├── roadmap.md                             - Implementation plan
    └── timeless-design.md                     - Philosophy
```

---

## Implementation Notes

### Hybrid Approach (Research-Validated)

**Strategy:** Zig for orchestration + C/C++ libraries via FFI for heavy lifting

**Rationale (from production research):**
- **Vector operations:** FAISS/hnswlib are battle-tested (100K+ stars combined, sub-10ms queries)
- **HNSW indexing:** Don't reimplement (HNSW is complex ~5K LOC, already optimized)
- **SIMD operations:** Zig SIMD still immature, use AVX2/AVX-512 via C++
- **Focus Zig:** Orchestration, JSI bridge, business logic, type safety

**What we build in Zig:**
- Pattern Space orchestration (600 LOC)
- Context Flow streaming (1,000 LOC)
- Reality Interface observables (1,200 LOC)
- Meta-cognition introspection (1,000 LOC)
- JSI bridge to JavaScript (300 LOC)

**What we use via FFI:**
- Vector search: hnswlib (C++ header-only library)
- NoSQL storage: LMDB (C library, key-value)
- Embeddings: ONNX Runtime (pre-trained models)
- SIMD operations: Optimized C++ kernels
- Production-validated libraries where available

---

## Storage Layer

### Architecture: usearch (HNSW) + LMDB (~1MB total)

**Philosophy:** Use the right tool for each job. Both tiny, fast, battle-tested C/C++ libraries with proper Zig FFI support.

```
~/.config/vimcraft/ai/
├── vectors.usearch        # usearch/HNSW (~500KB binary)
└── data/                  # LMDB (~500KB binary)
    ├── data.mdb
    └── lock.mdb
```

**Implementation:** usearch is an HNSW implementation with proper C API (unlike header-only hnswlib). Same algorithm, better FFI support.

### Why This Choice?

| Requirement | Solution | Why Not Alternatives |
|-------------|----------|---------------------|
| **Fast vectors** | usearch (HNSW) | 10x faster than DB-integrated vectors, proper C API |
| **NoSQL flexibility** | LMDB + JSON values | No schema, no migrations |
| **Lightweight** | ~1MB total | SurrealDB is 30MB, SQLite is 2MB |
| **Simple** | Key-value | DynamoDB-style patterns work |
| **Graph queries** | Key prefixes | `edge:{from}:{rel}:{to}` pattern |
| **Battle-tested** | Both 10+ years | Production-proven |

### Component Roles

| Component | Size | Purpose | Access Pattern |
|-----------|------|---------|----------------|
| **hnswlib** | ~500KB | Vector similarity search | O(log n) ANN search |
| **LMDB** | ~500KB | Everything else (NoSQL) | O(1) key lookup, O(n) prefix scan |

### Key Design Schema (DynamoDB-style)

**Core Principle:** Smart key design = Complex query capability

```
PATTERNS (documents)
────────────────────────────────────────────────────────
pattern:{id}                        → {full JSON document}
idx:tag:{tag}:{id}                  → "" (tag index)
idx:success:{rate_padded}:{id}      → "" (success rate index)
vec:{id}                            → {hnsw_id} (vector reference)

GRAPH EDGES (relationships)
────────────────────────────────────────────────────────
edge:{from}:{relationship}:{to}     → {edge metadata JSON}
redge:{to}:{relationship}:{from}    → "" (reverse index)

CONVERSATIONS
────────────────────────────────────────────────────────
conv:{id}                           → {conversation metadata}
conv:{id}:msg:{timestamp}           → {message JSON}

EVENTS (Reality Interface)
────────────────────────────────────────────────────────
event:{timestamp}:{id}              → {event JSON}
idx:event:type:{type}:{ts}:{id}     → "" (type index)

META-COGNITION
────────────────────────────────────────────────────────
uncertainty:{topic}                 → {entropy, confidence}
reasoning:{session}:{step}          → {reasoning step JSON}
```

### Query Patterns

| Query | Key Pattern | Complexity |
|-------|-------------|------------|
| Get pattern by ID | `pattern:{id}` | O(1) |
| List all patterns | iterate `pattern:` | O(n) |
| Find by tag | iterate `idx:tag:{tag}:` | O(matches) |
| Find by success > X | iterate `idx:success:{X}:` → end | O(matches) |
| Get outgoing edges | iterate `edge:{from}:{rel}:` | O(edges) |
| Get incoming edges | iterate `redge:{to}:{rel}:` | O(edges) |
| Time range query | iterate `event:{start}:` → `event:{end}:` | O(range) |
| Vector similarity | usearch (HNSW) → LMDB metadata lookup | O(log n) + O(k) |

### Implementation

**Location:** `src/system/ai/storage/`

```
src/system/ai/storage/
├── storage.zig    # Unified AIStorage API
├── lmdb.zig       # LMDB bindings (key-value)
└── vectors.zig    # usearch bindings (HNSW vectors)
```

```zig
// src/system/ai/storage/storage.zig

const lmdb = @import("lmdb.zig");
const vectors = @import("vectors.zig");

pub const AIStorage = struct {
    db: lmdb.Env,              // Key-value storage
    vec: vectors.VectorIndex,  // Vector similarity search
    allocator: Allocator,
    config: Config,

    pub fn init(allocator: Allocator, config: Config) !Self {
        // Initialize LMDB for key-value storage
        var db = try lmdb.Env.init(allocator, db_path, config.max_db_size_mb);

        // Initialize usearch for vector similarity
        var vec = try vectors.VectorIndex.init(allocator, .{
            .dimensions = config.vector_dimensions,
            .capacity = config.vector_capacity,
        });

        return .{ .db = db, .vec = vec, .allocator = allocator, .config = config };
    }

    // ─────────────────────────────────────────────
    // PATTERN OPERATIONS
    // ─────────────────────────────────────────────

    pub fn savePattern(self: *Self, id: []const u8, json: []const u8,
                       embedding: ?[]const f32, tags: []const []const u8,
                       success_rate: f32) !void {
        // 1. Store document
        try self.db.put(fmt("pattern:{s}", .{id}), json);

        // 2. Store tag indexes
        for (tags) |tag| {
            try self.db.put(fmt("idx:tag:{s}:{s}", .{tag, id}), "");
        }

        // 3. Store success rate index (padded for sorting)
        const rate_int: u32 = @intFromFloat(success_rate * 10000);
        try self.db.put(fmt("idx:success:{d:0>5}:{s}", .{rate_int, id}), "");

        // 4. Store vector in usearch
        if (embedding) |emb| {
            const vec_key = std.hash.Wyhash.hash(0, id);
            try self.vec.add(vec_key, emb);
            try self.db.put(fmt("vec:{s}", .{id}), fmt("{d}", .{vec_key}));
        }
    }

    pub fn searchSimilar(self: *Self, query: []const f32, k: usize) ![]PatternMatch {
        const results = try self.vec.search(query, k);
        // Lookup metadata from LMDB using vector keys
        // ...
    }

    // ─────────────────────────────────────────────
    // GRAPH OPERATIONS
    // ─────────────────────────────────────────────

    pub fn addEdge(self: *Self, from: []const u8, rel: []const u8, to: []const u8, meta: anytype) !void {
        // Forward edge
        try self.put(
            fmt("edge:{s}:{s}:{s}", .{from, rel, to}),
            try std.json.stringifyAlloc(self.allocator, meta, .{})
        );
        // Reverse edge (for "who points to me?")
        try self.put(fmt("redge:{s}:{s}:{s}", .{to, rel, from}), "");
    }

    pub fn getOutgoing(self: *Self, from: []const u8, rel: []const u8) ![]Edge {
        var edges = std.ArrayList(Edge).init(self.allocator);

        var iter = self.iteratePrefix(fmt("edge:{s}:{s}:", .{from, rel}));
        while (iter.next()) |kv| {
            const to = extractLastSegment(kv.key);
            try edges.append(.{ .to = to, .meta = kv.value });
        }

        return edges.toOwnedSlice();
    }

    // ─────────────────────────────────────────────
    // VECTOR OPERATIONS
    // ─────────────────────────────────────────────

    pub fn searchSimilar(self: *Self, query: []f32, k: usize) ![]Pattern {
        // 1. Fast vector search (hnswlib) - O(log n)
        const hnsw_results = hnswlib.searchKnn(self.vectors, query.ptr, k);

        // 2. Lookup metadata (LMDB) - O(k)
        var patterns = std.ArrayList(Pattern).init(self.allocator);
        for (hnsw_results.ids) |hnsw_id| {
            // Reverse lookup: hnsw_id → pattern_id
            // (maintain idx:hnsw:{id} → pattern_id)
            if (try self.getPatternByHnswId(hnsw_id)) |p| {
                try patterns.append(p);
            }
        }

        return patterns.toOwnedSlice();
    }
};
```

### Performance Expectations

| Operation | hnswlib | LMDB | Combined |
|-----------|---------|------|----------|
| **Vector search (100K)** | 2-5ms | - | 2-5ms |
| **Get by key** | - | <0.1ms | <0.1ms |
| **Prefix scan (1K matches)** | - | 1-2ms | 1-2ms |
| **Save pattern + indexes** | 0.1ms | 0.5ms | <1ms |
| **Graph traversal (10 edges)** | - | <1ms | <1ms |

### Comparison to Alternatives

| Database | Size | Vectors | NoSQL | Graph | Complexity |
|----------|------|---------|-------|-------|------------|
| **hnswlib + LMDB** | ~1MB | ✅ Fast | ✅ JSON values | ✅ Key patterns | Simple |
| SurrealDB | ~30MB | ⚠️ Slower | ✅ Native | ✅ Native | Medium |
| SQLite + hnswlib | ~3MB | ✅ Fast | ❌ Schema | ⚠️ CTEs | Medium |
| Just JSON files | 0MB | ➕ hnswlib | ✅ Files | ❌ Manual | Simplest |

### Why Not Other Options?

| Option | Rejected Because |
|--------|-----------------|
| **SurrealDB** | 30MB binary, vector search 10x slower than hnswlib |
| **SQLite** | Schema migrations, no native NoSQL, 2MB overhead |
| **DuckDB** | 50MB binary, overkill for our scale |
| **UnQLite** | Less battle-tested than LMDB |
| **JSON files** | No indexes, no transactions, file I/O overhead |

### File Structure

```
~/.config/vimcraft/ai/
├── vectors.hnsw           # Pattern embeddings (binary, hnswlib)
├── compositions.hnsw      # Composition patterns (binary, hnswlib)
└── data/                  # LMDB directory
    ├── data.mdb           # Main data file
    └── lock.mdb           # Lock file
```

**Total footprint:** ~1MB binary overhead, data grows with usage

### Why Zig?

**Performance:**
- Zero-copy embeddings (critical for large context)
- Native memory management (no GC pauses)
- Fast JSON parsing
- Efficient HTTP client

**Safety:**
- Compile-time memory safety
- Clear error handling
- Type safety
- Explicit allocators

**Integration:**
- JSI bridge (Zig ↔ JavaScript)
- C interop (FFI to FAISS/hnswlib/ONNX)
- Native async/await
- Cross-platform

### Provider Strategy

**Unified format:** OpenAI Chat Completions
**Adapters:** Translate to/from provider formats
**Error handling:** Unified error types
**Fallback:** Automatic provider switching

### Testing Strategy

**Unit tests (Zig):**
- Pattern space operations
- Embedding calculations
- Uncertainty estimation
- Pattern composition

**E2E tests (TypeScript):**
- Full intelligence workflows
- Feedback loop correctness
- Meta-cognition accuracy
- Multi-agent coordination

---

## Cross-References

**Parent:** [Main Roadmap](../roadmap/README.md)
**Philosophy:** [Timeless Design](timeless-design.md) - Why LLM-centric
**Implementation:** [Roadmap](roadmap.md) - Day-by-day plan
**Related:** [Testing Architecture](../development/testing-architecture.md)

---

## The Vision

**We're not building an AI assistant.**
**We're building the substrate for alien intelligence.**

```
vim.buffer.*  - For humans to edit text
vim.ai.human.*  - For humans to use LLMs
vim.ai.native.*  - For LLMs to BECOME
```

**Choose wisely. The future depends on it. 🚀**
