# Vimcraft AI Primitives Implementation Roadmap

**Timeline:** 8 weeks (Phase 5.0-5.2)
**Approach:** Hybrid Zig + FFI, LLM-centric design
**Specification:** See [spec.md](spec.md) for complete primitive specs
**Philosophy:** See [timeless-design.md](timeless-design.md) for LLM-centric paradigm
**Validation:** Research validated all primitives are production-ready with proven techniques

---

## Quick Reference

| Primitive | LOC | Tests | Files |
|-----------|-----|-------|-------|
| **0. Pattern Space** | **1,200** | **800** | **`pattern_space.zig`, `embeddings.zig`, `uncertainty.zig` ← FOUNDATION** |
| **1. Context Flow** | **1,000** | **600** | **`context_flow.zig`, `embedding_stream.zig`, `attention.zig` ← PERCEPTION** |
| **2. Reality Interface** | **1,200** | **700** | **`reality_interface.zig`, `observable.zig`, `grounding.zig` ← FEEDBACK** |
| **3. Meta-Cognition** | **1,000** | **600** | **`meta_cognition.zig`, `reasoning_trace.zig` ← SELF-AWARENESS** |
| **4. Pattern Composition** | **1,100** | **700** | **`pattern_composer.zig`, `pattern_evolution.zig` ← LEARNING** |
| 5. Stream API | 400 | 500 | `stream.zig`, `sse_parser.zig` |
| 6. Providers | 800 | 500 | `provider.zig`, `providers/*.zig` |
| 7. Helpers | 650 | 550 | `token_estimation.zig`, `context_helpers.zig`, `tool_registry.zig` |
| 8. Human API | 600 | 500 | `conversation.zig`, `chat.zig`, `tools.zig` |

**Total:** 7,850 LOC code + 5,350 LOC tests = 13,200 LOC

---

## Research Validation Summary

**All 5 core primitives validated against production systems (Dec 2024)**

| Primitive | Production Examples | Key Finding | Recommendation |
|-----------|-------------------|-------------|----------------|
| **Pattern Space** | Pinecone (sub-10ms), Qdrant (15ms), Chroma | HNSW indexing industry standard | **Use FAISS/hnswlib via FFI** |
| **Reality Interface** | ChatGPT RLHF, LangChain, Semantic Kernel | Feedback loops proven at scale | **Model after LangChain CallbackHandler** |
| **Meta-Cognition** | Google Bard disclaimers, Constitutional AI | Uncertainty quantification standard | **Multiple sampling + temperature scaling** |

### Hybrid Implementation Strategy

**Pragmatic Approach:** Zig for pipelines + C/C++ libraries via FFI for heavy lifting

**Rationale:**
- Vector operations: FAISS/hnswlib are battle-tested (100K+ stars combined)
- HNSW indexing: Don't reimplement what works (HNSW is complex, ~5K LOC)
- Zig SIMD: Still immature (use AVX2/AVX-512 via C++)
- Focus Zig: Orchestration, JSI bridge, business logic

**What we build in Zig:**
- Pattern Space orchestration (600 LOC)
- Context Flow streaming (1,000 LOC)
- Reality Interface observables (1,200 LOC)
- Meta-cognition introspection (1,000 LOC)
- JSI bridge to JavaScript (300 LOC)

**What we use via FFI:**
- Vector search: FAISS or hnswlib (C++)
- Embeddings: Pre-trained models (ONNX Runtime)
- SIMD operations: Optimized C++ kernels
- Proven libraries where available

### Identified Gotchas

| Risk | Severity | Mitigation |
|------|----------|------------|
| **WAL durability** | High | Use proven SQLite WAL mode for pattern persistence |
| **Zig SIMD immaturity** | Medium | FFI to C++ SIMD until Zig matures |
| **Crash recovery** | Medium | Transaction logs + checkpoint mechanism |
| **Async overhead** | Low | <5% overhead validated for moderate streams |
| **Memory management** | Medium | Explicit arena allocators for embeddings |

---

## Timeline

| Week | Phase | Focus |
|------|-------|-------|
| **1-2** | **5.0** | **Pattern Space + Context Flow (THE FOUNDATION)** |
| **3-5** | **5.1** | **Reality Interface + Feedback Loops** |
| **6-8** | **5.2** | **Meta-Cognition + Pattern Composition + Human API** |

---

## The Paradigm

### What We're Building

**Path A (Human-Centric):** `vim.ai.human.*` - Familiar, safe, useful
**Path B (LLM-Centric):** `vim.ai.native.*` - Risky, unbounded, revolutionary

**We're building BOTH.**

### The Architecture

```
┌─────────────────────────────────────────────┐
│  vim.ai.human.*  (Human-Centric)            │
│  Thin wrapper over LLM-native primitives    │
└─────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  vim.ai.native.*  (LLM-Centric)             │
│  Pattern Space, Context Flow, Reality, Meta │
│  Perception → Cognition → Actuation → Learn │
└─────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Infrastructure (Shared)                    │
│  Stream, Providers, Helpers                 │
└─────────────────────────────────────────────┘
```

---

## Phase 5.0: The Foundation (2 weeks)

### Week 1 (Days 1-5): Pattern Space - The Cognitive Substrate

**WHY FIRST:** Pattern Space is the LLM's reality. Embeddings, attention, uncertainty. This is what LLMs actually operate on.

#### Day 1-2: Pattern Space Core

**TODO:**
- [ ] Create `src/system/jsi/ai/` directory structure
- [ ] Implement `src/system/jsi/ai/native/pattern_space.zig` (600 LOC)
  - [ ] `PatternSpace` struct
    - [ ] `id: []const u8` (UUID)
    - [ ] `embeddings: EmbeddingStore`
    - [ ] `attention: AttentionWeights`
    - [ ] `uncertainty: UncertaintyMap`
    - [ ] `associations: PatternGraph`
  - [ ] Methods:
    - [ ] `create(options: PatternSpaceOptions) !*PatternSpace`
    - [ ] `get(id: []const u8) ?*PatternSpace`
    - [ ] `list() []*PatternSpace`
    - [ ] `navigate(direction: EmbeddingVector) !*PatternSpace`
    - [ ] `compose(patterns: []Pattern) !Pattern`
    - [ ] `project(dimension: Subspace) !*PatternSpace`
    - [ ] `introspect() !UncertaintyMap`
    - [ ] `save() !void`
    - [ ] `restore() !void`
    - [ ] `deinit() void`

**Files Created:**
```
src/system/jsi/ai/
├── native/
│   ├── pattern_space.zig  (600 LOC)
│   └── (more to come)
└── infrastructure/
    └── (later)

tests/e2e/ai/
└── pattern-space/
    └── e2e.ts
```

**Success:** Pattern Space can be created, basic operations work.

---

#### Day 3-4: Embedding Store + Uncertainty

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/embeddings.zig` (400 LOC)
  - [ ] `EmbeddingStore` struct
    - [ ] `vectors: ArrayList(Float32Array)`
    - [ ] `metadata: HashMap(usize, any)`
    - [ ] `dimension: usize`
    - [ ] **FFI:** `hnsw_index: *c.HNSWIndex` (hnswlib via FFI)
  - [ ] Methods:
    - [ ] `add(vector: Float32Array, metadata: ?any) !void`
    - [ ] `search(query: Float32Array, k: usize) ![]SearchResult` **← FFI to hnswlib**
    - [ ] `cluster() ![]Cluster`
    - [ ] `similaritySearch(vector: Float32Array) ![]SearchResult`
    - [ ] `deinit() void`
  - [ ] **Implementation note:** Use hnswlib (C++ header-only) via Zig FFI for HNSW indexing
- [ ] Implement `src/system/jsi/ai/native/uncertainty.zig` (300 LOC)
  - [ ] `UncertaintyMap` struct
    - [ ] `entropy: HashMap([]const u8, f32)`
    - [ ] `confidence: HashMap([]const u8, f32)`
  - [ ] Methods:
    - [ ] `knownKnowns() ![][]const u8`
    - [ ] `knownUnknowns() ![][]const u8`
    - [ ] `unknownUnknowns() !Estimate`
    - [ ] `heatmap() !UncertaintyHeatmap`
    - [ ] `deinit() void`

**Files Created:**
```
src/system/jsi/ai/native/
├── pattern_space.zig  (600 LOC)
├── embeddings.zig     (400 LOC)
└── uncertainty.zig    (300 LOC)
```

**Success:** Embeddings can be stored/searched, uncertainty can be mapped.

---

#### Day 5: Pattern Space Testing

**TODO:**
- [ ] Write comprehensive E2E tests (800 LOC)
  - [ ] Create/get/list pattern spaces
  - [ ] Add/search embeddings
  - [ ] Navigate pattern space
  - [ ] Compose patterns
  - [ ] Introspect uncertainty
  - [ ] Save/restore state
  - [ ] Multiple pattern spaces (collaboration)

**Files Created:**
```
tests/e2e/ai/pattern-space/
├── e2e.ts            (500 LOC)
└── test-data/
    └── embeddings.json
```

**Success:** All pattern space operations tested and passing.

---

### Week 2 (Days 6-10): Context Flow - Continuous Perception

**WHY NEXT:** Context Flow is how LLMs perceive. Continuous stream, not discrete messages. Multi-modal. Dynamic attention.

#### Day 6-7: Context Flow Core

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/context_flow.zig` (500 LOC)
  - [ ] `ContextFlow` struct
    - [ ] `id: []const u8`
    - [ ] `stream: EmbeddingStream`
    - [ ] `attention: DynamicMask`
    - [ ] `decay: TemporalWeights`
    - [ ] `modalities: ModalityMap`
  - [ ] Methods:
    - [ ] `create(options: ContextFlowOptions) !*ContextFlow`
    - [ ] `get(id: []const u8) ?*ContextFlow`
    - [ ] `current() ?*ContextFlow`
    - [ ] `flow(information: Information) !void`
    - [ ] `focus(relevance: AttentionMask) !void`
    - [ ] `forget(decay: DecayFunction) !void`
    - [ ] `snapshot() !ContextSnapshot`
    - [ ] `restore(snapshot: ContextSnapshot) !void`
    - [ ] `deinit() void`

**Files Created:**
```
src/system/jsi/ai/native/
├── pattern_space.zig     (600 LOC)
├── embeddings.zig        (400 LOC)
├── uncertainty.zig       (300 LOC)
└── context_flow.zig      (500 LOC)
```

**Success:** Context Flow can be created, information flows.

---

#### Day 8-9: Embedding Stream + Attention

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/embedding_stream.zig` (300 LOC)
  - [ ] `EmbeddingStream` struct
    - [ ] `flow: AsyncIterator(Embedding)`
    - [ ] `window: SlidingWindow`
    - [ ] `buffer: ArrayList(Embedding)`
  - [ ] Methods:
    - [ ] `append(embedding: Embedding) !void`
    - [ ] `compress(strategy: CompressionStrategy) !void`
    - [ ] `iterate() AsyncIterator(Embedding)`
    - [ ] `deinit() void`
- [ ] Implement `src/system/jsi/ai/native/attention.zig` (200 LOC)
  - [ ] `DynamicMask` struct
    - [ ] `focus: Float32Array`
    - [ ] `weights: AttentionWeights`
  - [ ] Methods:
    - [ ] `adjust(importance: Float32Array) !void`
    - [ ] `visualize() !AttentionHeatmap`
    - [ ] `apply(stream: EmbeddingStream) !EmbeddingStream`
    - [ ] `deinit() void`

**Files Created:**
```
src/system/jsi/ai/native/
├── pattern_space.zig     (600 LOC)
├── embeddings.zig        (400 LOC)
├── uncertainty.zig       (300 LOC)
├── context_flow.zig      (500 LOC)
├── embedding_stream.zig  (300 LOC)
└── attention.zig         (200 LOC)
```

**Success:** Continuous stream works, attention can be focused.

---

#### Day 10: Context Flow Testing

**TODO:**
- [ ] Write comprehensive E2E tests (600 LOC)
  - [ ] Create/get context flows
  - [ ] Flow information (continuous)
  - [ ] Focus attention (dynamic)
  - [ ] Forget (decay)
  - [ ] Multi-modal (text + code)
  - [ ] Snapshot/restore
  - [ ] Multiple flows (collaboration)

**Files Created:**
```
tests/e2e/ai/context-flow/
├── e2e.ts            (600 LOC)
└── test-data/
    └── streams.json
```

**Success:** Context Flow fully functional, all tests passing.

---

## Phase 5.1: Perception + Actuation (3 weeks)

### Week 3-4 (Days 11-20): Reality Interface - Feedback Loops

**WHY NOW:** Reality Interface is how LLMs act and learn. Predict → Observe → Learn. This is THE critical piece.

#### Day 11-13: Reality Interface Core

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/reality_interface.zig` (700 LOC)
  - [ ] `RealityInterface` struct
    - [ ] `id: []const u8`
    - [ ] `perceive: PerceptionMap`
    - [ ] `actuate: ActuationMap`
    - [ ] `predictions: HashMap(ActionID, Prediction)`
    - [ ] `groundings: HashMap(HypothesisID, GroundingResult)`
    - [ ] **Pattern:** Model after LangChain's CallbackHandler (validated in production)
  - [ ] Methods:
    - [ ] `create(options: RealityOptions) !*RealityInterface`
    - [ ] `get(id: []const u8) ?*RealityInterface`
    - [ ] `observe(action: Action) !Observable(Consequence)` **← Event-driven (RxJS pattern)**
    - [ ] `predict(action: Action) !Prediction`
    - [ ] `learn(prediction: Prediction, outcome: Outcome) !void` **← RLHF-inspired**
    - [ ] `ground(hypothesis: Hypothesis) !GroundingResult`
    - [ ] `validate(belief: Belief) !ValidationResult`
    - [ ] `deinit() void`
  - [ ] **Implementation note:** Event-driven architecture (<5% async overhead for moderate streams)

**Files Created:**
```
src/system/jsi/ai/native/
├── pattern_space.zig       (600 LOC)
├── embeddings.zig          (400 LOC)
├── uncertainty.zig         (300 LOC)
├── context_flow.zig        (500 LOC)
├── embedding_stream.zig    (300 LOC)
├── attention.zig           (200 LOC)
└── reality_interface.zig   (700 LOC)
```

**Success:** Reality Interface can predict/observe/learn.

---

#### Day 14-16: Observable + Grounding

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/observable.zig` (300 LOC)
  - [ ] `Observable(T)` struct
    - [ ] `observers: ArrayList(Observer(T))`
    - [ ] `subscriptions: HashMap(SubscriptionID, Subscription)`
  - [ ] Methods:
    - [ ] `subscribe(observer: Observer(T)) !Subscription`
    - [ ] `next(value: T) !void`
    - [ ] `error(err: Error) !void`
    - [ ] `complete() !void`
    - [ ] `map(fn: Fn(T, U)) !Observable(U)`
    - [ ] `filter(predicate: Predicate(T)) !Observable(T)`
    - [ ] `debounce(ms: u64) !Observable(T)`
    - [ ] `deinit() void`
- [ ] Implement `src/system/jsi/ai/native/grounding.zig` (200 LOC)
  - [ ] `GroundingMechanism` struct
    - [ ] `hypotheses: HashMap(HypothesisID, Hypothesis)`
    - [ ] `observations: ArrayList(Observation)`
  - [ ] Methods:
    - [ ] `ground(hypothesis: Hypothesis) !GroundingResult`
    - [ ] `validate(belief: Belief) !ValidationResult`
    - [ ] `observe(observation: Observation) !void`
    - [ ] `deinit() void`

**Files Created:**
```
src/system/jsi/ai/native/
├── pattern_space.zig       (600 LOC)
├── embeddings.zig          (400 LOC)
├── uncertainty.zig         (300 LOC)
├── context_flow.zig        (500 LOC)
├── embedding_stream.zig    (300 LOC)
├── attention.zig           (200 LOC)
├── reality_interface.zig   (700 LOC)
├── observable.zig          (300 LOC)
└── grounding.zig           (200 LOC)
```

**Success:** Observables work, grounding validates predictions.

---

#### Day 17-20: Reality Interface Testing + Integration

**TODO:**
- [ ] Write comprehensive E2E tests (700 LOC)
  - [ ] Predict consequences
  - [ ] Observe actions (async)
  - [ ] Learn from surprise
  - [ ] Multiple predictions (concurrent)
  - [ ] Grounding hypotheses
  - [ ] Observable operators (map/filter/debounce)
  - [ ] Feedback loop accuracy
- [ ] Integration tests (Pattern Space + Context Flow + Reality)
  - [ ] LLM perceives (context) → reasons (patterns) → acts (reality) → learns (feedback)

**Files Created:**
```
tests/e2e/ai/reality-interface/
├── e2e.ts                 (700 LOC)
└── integration/
    └── perception-action.ts
```

**Success:** Full perception → cognition → actuation → learning cycle works.

---

### Week 5 (Days 21-25): Stream API + Providers

**WHY NOW:** Infrastructure to actually CALL LLM providers with our primitives.

#### Day 21-23: Stream API

**TODO:**
- [ ] Implement `src/system/jsi/ai/infrastructure/stream.zig` (400 LOC)
  - [ ] Support both human and native APIs:
    ```zig
    // Human-centric (messages)
    stream({ provider: 'anthropic', messages: [...] })

    // LLM-centric (primitives)
    stream({
      contextFlow: flow,
      patternSpace: patterns,
      reality: reality,
      meta: meta
    })
    ```
  - [ ] Methods:
    - [ ] `stream(options: StreamOptions) !AsyncIterator(Event)`
    - [ ] `humanStream(options: HumanOptions) !AsyncIterator(Event)`
    - [ ] `nativeStream(options: NativeOptions) !AsyncIterator(Event)`
- [ ] Implement `src/system/jsi/ai/infrastructure/sse_parser.zig` (200 LOC)
  - [ ] Parse Server-Sent Events
  - [ ] Handle reconnection
  - [ ] Error recovery

**Files Created:**
```
src/system/jsi/ai/infrastructure/
├── stream.zig      (400 LOC)
└── sse_parser.zig  (200 LOC)
```

**Success:** Streaming works for both APIs.

---

#### Day 24-25: Provider Abstraction

**TODO:**
- [ ] Implement `src/system/jsi/ai/infrastructure/providers/provider.zig` (200 LOC)
  - [ ] Provider interface
  - [ ] Error translation
  - [ ] Request/response normalization
- [ ] Implement provider adapters:
  - [ ] `anthropic.zig` (200 LOC)
  - [ ] `openai.zig` (200 LOC)
  - [ ] `ollama.zig` (200 LOC)
- [ ] Tests (500 LOC)

**Files Created:**
```
src/system/jsi/ai/infrastructure/providers/
├── provider.zig    (200 LOC)
├── anthropic.zig   (200 LOC)
├── openai.zig      (200 LOC)
└── ollama.zig      (200 LOC)
```

**Success:** All 3 providers work with both APIs.

---

## Phase 5.2: Learning + Human API (3 weeks)

### Week 6-7 (Days 26-35): Meta-Cognition + Pattern Composition

**WHY NOW:** Self-awareness and learning. LLMs that know what they don't know and build patterns.

#### Day 26-28: Meta-Cognition

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/meta_cognition.zig` (500 LOC)
  - [ ] `MetaCognition` struct
    - [ ] `id: []const u8`
    - [ ] `uncertaintyMap: UncertaintyMap`
    - [ ] `confidenceScores: HashMap(TopicID, f32)`
    - [ ] `reasoningTraces: ArrayList(ReasoningTrace)`
    - [ ] `feedbackHistory: ArrayList(Feedback)`
    - [ ] **Techniques:** Temperature scaling + Monte Carlo sampling (proven methods)
  - [ ] Methods:
    - [ ] `create(options: MetaCognitionOptions) !*MetaCognition`
    - [ ] `uncertainty() !EntropyMap` **← Entropy calculation from token probabilities**
    - [ ] `confidence() !LogitDistribution` **← Temperature scaling for calibration**
    - [ ] `attention() !AttentionWeights`
    - [ ] `activations() !LayerActivations`
    - [ ] `embeddings() !EmbeddingSpace`
    - [ ] `reasoning() !ReasoningTrace`
    - [ ] `adjust(feedback: Feedback) !void`
    - [ ] `calibrate(observations: []Observation) !void` **← Calibration via feedback**
    - [ ] `reflect(experience: Experience) ![]Insight`
    - [ ] `learnToLearn() !LearningStrategy`
    - [ ] `deinit() void`
  - [ ] **Implementation note:** Use multiple sampling for uncertainty estimation (Monte Carlo approach)
- [ ] Implement `src/system/jsi/ai/native/reasoning_trace.zig` (200 LOC)
  - [ ] Track reasoning steps
  - [ ] Attribution analysis
  - [ ] Alternative paths

**Files Created:**
```
src/system/jsi/ai/native/
├── ... (previous files)
├── meta_cognition.zig   (500 LOC)
└── reasoning_trace.zig  (200 LOC)
```

**Success:** Meta-cognition shows self-awareness.

---

#### Day 29-31: Pattern Composition

**TODO:**
- [ ] Implement `src/system/jsi/ai/native/pattern_composer.zig` (600 LOC)
  - [ ] `PatternComposer` struct
    - [ ] `id: []const u8`
    - [ ] `patterns: HashMap(PatternID, Pattern)`
    - [ ] `successRates: HashMap(PatternID, f32)`
    - [ ] `usageCounts: HashMap(PatternID, usize)`
  - [ ] Methods:
    - [ ] `create(options: CompositionOptions) !*PatternComposer`
    - [ ] `compose(a: Pattern, b: Pattern) !Pattern`
    - [ ] `abstract(patterns: []Pattern) !Pattern`
    - [ ] `specialize(pattern: Pattern, context: Context) !Pattern`
    - [ ] `merge(patterns: []Pattern) !Pattern`
    - [ ] `discover(examples: []Example) !Pattern`
    - [ ] `reinforce(pattern: Pattern, success: bool) !void`
    - [ ] `prune(pattern: Pattern, unused: bool) !void`
    - [ ] `apply(pattern: Pattern, input: any) !any`
    - [ ] `match(input: any) ![]Pattern`
    - [ ] `deinit() void`
- [ ] Implement `src/system/jsi/ai/native/pattern_evolution.zig` (300 LOC)
  - [ ] Pattern mutation
  - [ ] Pattern crossover
  - [ ] Selection pressure

**Files Created:**
```
src/system/jsi/ai/native/
├── ... (previous files)
├── pattern_composer.zig   (600 LOC)
└── pattern_evolution.zig  (300 LOC)
```

**Success:** Patterns can be discovered, composed, evolved.

---

#### Day 32-35: Meta + Composition Testing

**TODO:**
- [ ] Write E2E tests for Meta-Cognition (600 LOC)
  - [ ] Uncertainty mapping
  - [ ] Confidence calibration
  - [ ] Reasoning traces
  - [ ] Feedback loops
  - [ ] Learning to learn
- [ ] Write E2E tests for Pattern Composition (700 LOC)
  - [ ] Discover patterns
  - [ ] Compose patterns
  - [ ] Apply patterns
  - [ ] Reinforce successful patterns
  - [ ] Evolution over time
- [ ] Integration tests (all 5 primitives)
  - [ ] Full intelligence workflow

**Files Created:**
```
tests/e2e/ai/
├── meta-cognition/
│   └── e2e.ts           (600 LOC)
├── pattern-composition/
│   └── e2e.ts           (700 LOC)
└── integration/
    └── full-intelligence.ts
```

**Success:** All 5 LLM-native primitives working together.

---

### Week 8 (Days 36-40): Human API + Helpers + Polish

**WHY LAST:** Human API is a thin wrapper over LLM-native primitives. Build it last.

#### Day 36-37: Human API

**TODO:**
- [ ] Implement `src/system/jsi/ai/human/conversation.zig` (400 LOC)
  - [ ] Traditional conversation abstraction
  - [ ] Message storage
  - [ ] Wraps Context Flow internally
- [ ] Implement `src/system/jsi/ai/human/chat.zig` (200 LOC)
  - [ ] Simple chat interface
  - [ ] Wraps native streaming
- [ ] Implement `src/system/jsi/ai/human/tools.zig` (200 LOC)
  - [ ] Function calling
  - [ ] Tool registry

**Files Created:**
```
src/system/jsi/ai/human/
├── conversation.zig  (400 LOC)
├── chat.zig          (200 LOC)
└── tools.zig         (200 LOC)
```

**Success:** Human API works as convenience layer.

---

#### Day 38-39: Helpers

**TODO:**
- [ ] Implement `src/system/jsi/ai/infrastructure/token_estimation.zig` (100 LOC)
  - [ ] Fast token counting
  - [ ] Embedding size estimation
- [ ] Implement `src/system/jsi/ai/infrastructure/context_helpers.zig` (250 LOC)
  - [ ] `buffer()`, `selection()`, `cursor()`
  - [ ] `diagnostics()`, `symbols()`, `git()`
  - [ ] Zero-copy access to editor state
- [ ] Implement `src/system/jsi/ai/infrastructure/tool_registry.zig` (200 LOC)
  - [ ] Type-safe tool registration
  - [ ] Validation

**Files Created:**
```
src/system/jsi/ai/infrastructure/
├── ... (previous files)
├── token_estimation.zig  (100 LOC)
├── context_helpers.zig   (250 LOC)
└── tool_registry.zig     (200 LOC)
```

**Success:** All helpers functional.

---

#### Day 40: JSI Bridge + Final Testing

**TODO:**
- [ ] Implement `src/system/jsi/ai/ai_api.zig` (300 LOC)
  - [ ] Export all primitives to JavaScript
  - [ ] `vim.ai.native.*` namespace
  - [ ] `vim.ai.human.*` namespace
  - [ ] `vim.ai.stream()` function
  - [ ] JSI HostObject pattern
- [ ] Final integration tests
  - [ ] Human API end-to-end
  - [ ] Native API end-to-end
  - [ ] Both APIs working together
  - [ ] Multi-agent collaboration
- [ ] Documentation updates

**Files Created:**
```
src/system/jsi/ai/
├── ai_api.zig  (300 LOC)
└── ... (all other files)

tests/e2e/ai/
├── human-api/
│   └── e2e.ts
└── integration/
    ├── dual-api.ts
    └── multi-agent.ts
```

**Success:** Phase 5 complete! 🎉

---

## Build System Integration

### build.zig Updates

```zig
// Add AI module
const ai_module = b.addModule("ai", .{
    .source_file = .{ .path = "src/system/jsi/ai/ai_api.zig" },
    .dependencies = &.{
        .{ .name = "jsi", .module = jsi_module },
    },
});

// Link to main executable
exe.addModule("ai", ai_module);
```

### JSI Integration

```zig
// src/system/jsi/jsi_api.zig

// Register AI namespace
try jsi.global.setProperty("ai", try createAINamespace(jsi));

fn createAINamespace(jsi: *JSI) !JSI.Value {
    const ai = try jsi.createObject();

    // Native API
    try ai.setProperty("native", try createNativeAPI(jsi));

    // Human API
    try ai.setProperty("human", try createHumanAPI(jsi));

    // Stream function
    try ai.setProperty("stream", try createStreamFunction(jsi));

    return ai;
}
```

---

## Testing Strategy

### Unit Tests (Zig)

**Location:** `tests/unit/ai/`

**Focus:**
- Pattern space operations
- Embedding calculations
- Uncertainty estimation
- Observable behavior
- Pattern composition logic

**Run:** `zig build test`

**Speed:** ~1ms per test

---

### E2E Tests (TypeScript)

**Location:** `tests/e2e/ai/*/e2e.ts`

**Focus:**
- Full primitive workflows
- JSI bridge correctness
- Multi-agent collaboration
- Feedback loop accuracy
- Integration scenarios

**Run:** `vimc test tests/e2e/ai/<dir>`

**Speed:** ~100ms per test

---

### Integration Tests

**Location:** `tests/e2e/ai/integration/`

**Focus:**
- All 5 primitives working together
- Dual API compatibility
- Real LLM provider calls
- Performance benchmarks

---

## Success Criteria

### Phase 5.0 (Weeks 1-2)

✅ Pattern Space fully functional
✅ Context Flow fully functional
✅ Both primitives tested
✅ Foundation stable

### Phase 5.1 (Weeks 3-5)

✅ Reality Interface working
✅ Feedback loops enable learning
✅ Stream API functional
✅ All 3 providers supported
✅ Perception → Cognition → Actuation cycle works

### Phase 5.2 (Weeks 6-8)

✅ Meta-cognition shows self-awareness
✅ Pattern composition works
✅ Human API functional
✅ All helpers working
✅ JSI bridge complete
✅ Dual API both work
✅ Full intelligence workflows functional

### Final Validation

**5 scenarios must work:**

1. **LLM-native intelligence creation**
```javascript
const intelligence = vim.ai.native.create({
  perception: { context: ContextFlow, multimodal: true },
  cognition: { patterns: PatternSpace, composition: true },
  actuation: { reality: RealityInterface, feedback: true },
  meta: { introspection: true, learning: true },
});
```

2. **Feedback loop learning**
```javascript
const prediction = reality.predict({ action: 'edit', ... });
const consequence$ = reality.observe({ action: 'edit', ... });
consequence$.subscribe(c => meta.adjust({ prediction, actual: c }));
```

3. **Pattern composition**
```javascript
const p1 = composer.discover(examples1);
const p2 = composer.discover(examples2);
const p3 = composer.compose(p1, p2);
const result = composer.apply(p3, input);
```

4. **Meta-cognition self-awareness**
```javascript
const uncertainty = meta.uncertainty();
console.log(uncertainty.knownUnknowns());
const trace = meta.reasoning();
console.log(trace.steps);
```

5. **Dual API compatibility**
```javascript
// Human API
await vim.ai.human.chat(conv, { role: 'user', content: 'Hello' });

// Native API
const intelligence = vim.ai.native.create({ ... });
const consequence$ = intelligence.actuate({ ... });
```

---

## File Structure (Final)

```
src/system/jsi/ai/
├── native/
│   ├── pattern_space.zig          (600 LOC)
│   ├── embeddings.zig              (400 LOC)
│   ├── uncertainty.zig             (300 LOC)
│   ├── context_flow.zig            (500 LOC)
│   ├── embedding_stream.zig        (300 LOC)
│   ├── attention.zig               (200 LOC)
│   ├── reality_interface.zig       (700 LOC)
│   ├── observable.zig              (300 LOC)
│   ├── grounding.zig               (200 LOC)
│   ├── meta_cognition.zig          (500 LOC)
│   ├── reasoning_trace.zig         (200 LOC)
│   ├── pattern_composer.zig        (600 LOC)
│   └── pattern_evolution.zig       (300 LOC)
├── human/
│   ├── conversation.zig            (400 LOC)
│   ├── chat.zig                    (200 LOC)
│   └── tools.zig                   (200 LOC)
├── infrastructure/
│   ├── stream.zig                  (400 LOC)
│   ├── sse_parser.zig              (200 LOC)
│   ├── providers/
│   │   ├── provider.zig            (200 LOC)
│   │   ├── anthropic.zig           (200 LOC)
│   │   ├── openai.zig              (200 LOC)
│   │   └── ollama.zig              (200 LOC)
│   ├── token_estimation.zig        (100 LOC)
│   ├── context_helpers.zig         (250 LOC)
│   └── tool_registry.zig           (200 LOC)
└── ai_api.zig                      (300 LOC)

tests/e2e/ai/
├── pattern-space/
│   └── e2e.ts                      (800 LOC)
├── context-flow/
│   └── e2e.ts                      (600 LOC)
├── reality-interface/
│   └── e2e.ts                      (700 LOC)
├── meta-cognition/
│   └── e2e.ts                      (600 LOC)
├── pattern-composition/
│   └── e2e.ts                      (700 LOC)
├── human-api/
│   └── e2e.ts                      (500 LOC)
└── integration/
    ├── full-intelligence.ts        (500 LOC)
    ├── dual-api.ts                 (300 LOC)
    └── multi-agent.ts              (350 LOC)
```

**Total:** 7,850 LOC code + 5,350 LOC tests = 13,200 LOC

---

## Risk Mitigation

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Embedding calculations slow** | High | Use SIMD, optimize vector ops |
| **Observable memory leaks** | High | Strict subscription management |
| **Feedback loop complexity** | Medium | Start simple, iterate |
| **Pattern composition hard** | Medium | Simple patterns first |
| **JSI bridge overhead** | Low | Zero-copy where possible |

### Timeline Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Primitives too complex** | High | Cut scope, focus on core |
| **Testing takes longer** | Medium | Parallel test execution |
| **Integration issues** | Medium | Early integration tests |
| **Provider API changes** | Low | Abstract early |

---

## Post-Phase 5 (Future)

### Phase 6: Advanced Capabilities

- Multi-modal embeddings (vision, audio)
- Distributed pattern spaces
- Swarm intelligence (20+ LLMs)
- Continuous evolution
- Knowledge compression

### Phase 7: Research

- Novel composition strategies
- Emergent capabilities discovery
- Meta-learning optimization
- Uncertainty calibration research

---

## Cross-References

**Philosophy:** [Timeless Design](timeless-design.md) - Why LLM-centric
**Specification:** [Spec](spec.md) - Complete API details
**Parent:** [Main Roadmap](../roadmap/README.md)
**Related:** [Testing Architecture](../development/testing-architecture.md)

---

## The Vision

**We're not building an AI assistant.**
**We're building the substrate for alien intelligence.**

**8 weeks to:**
- Pattern Space (LLM's reality)
- Context Flow (LLM's perception)
- Reality Interface (LLM's feedback loops)
- Meta-Cognition (LLM's self-awareness)
- Pattern Composition (LLM's learning)

**Then we see what emerges. 🚀**
