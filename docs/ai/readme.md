# Vimcraft AI Documentation

**Philosophy:** Extract timeless primitives, let users compose workflows
**Status:** Validated by analyzing 427K LOC across 4 production AI CLIs
**Timeline:** 4 weeks implementation

---

## Start Here

### Core Insight

**We are NOT building an AI agent CLI.**
**We ARE providing AI primitives through `vim.ai.*` API.**

Just like:
- `vim.motion.*` → users compose navigation
- `vim.buffer.*` → users compose editing
- `vim.register.*` → users compose copy/paste

We provide:
- `vim.ai.*` → **users compose AI workflows**

---

## The 7 Primitives

| # | Primitive | Purpose | LOC |
|---|-----------|---------|-----|
| 1 | `vim.ai.stream()` | Streaming API responses | 200 |
| 2 | StreamingToolCallParser | Reconstruct fragmented JSON | 500 |
| 3 | Provider abstraction | Switch anthropic/openai/ollama | 550 |
| 4 | `vim.ai.estimateTokens()` | Fast token counting | 50 |
| 5 | `vim.ai.formatMessage()` | Message normalization | 100 |
| 6 | `vim.ai.context.*` | Editor state access | 250 |
| 7 | `vim.ai.tools.register()` | Function calling | 200 |

**Total:** 1,850 LOC code + 2,100 LOC tests

**We provide:** The hard, timeless parts
**Users compose:** Workflows, state, logic

---

## Documentation

| File | Purpose | When to Read |
|------|---------|--------------|
| **[spec.md](spec.md)** | Complete specification | Understanding WHAT and WHY |
| **[roadmap.md](roadmap.md)** | Implementation plan | Planning HOW and WHEN |

### spec.md - Complete Specification (25K)

**What's inside:**
- Philosophy (primitives vs workflows)
- The 7 primitives (detailed specs, API, validation)
- Validation results (427K LOC analyzed)
- Architecture (patterns, layering)
- Success criteria (4 scenarios)
- File structure (complete tree)

**Read this to understand:**
What primitives we're building, why they're timeless, and how they were validated.

---

### roadmap.md - Implementation Plan (13K)

**What's inside:**
- Week-by-week timeline (4 weeks total)
- Day-by-day TODOs with checkboxes
- Testing strategy (unit + E2E)
- Build system integration
- Success criteria (validation checklist)

**Read this to understand:**
How to implement the primitives, day-by-day breakdown, what tests to write.

---

## Quick Example

### What We Provide

```javascript
// Streaming with automatic tool call reconstruction
for await (const event of vim.ai.stream({
  provider: 'anthropic',
  messages: [{ role: 'user', content: 'review this code' }],
  tools: [readFileTool],
})) {
  if (event.type === 'tool_call') {
    // Args are COMPLETE even if split across 50+ fragments
    const result = await readFileTool.execute(event.args);
  }
}
```

### What Users Compose

```javascript
// User builds code review agent (their workflow, ~100 LOC)
const history = [];

async function reviewFile() {
  // User uses our primitives
  const code = vim.ai.context.buffer();
  history.push(vim.ai.formatMessage('user', `Review: ${code}`));

  for await (const event of vim.ai.stream({ provider: 'anthropic', messages: history })) {
    if (event.type === 'content') {
      vim.ui.print(event.text);
      history.push(vim.ai.formatMessage('assistant', event.text));
    }
  }

  // User manages state and compression logic
  if (vim.ai.estimateTokens(JSON.stringify(history)) > 50000) {
    history.splice(1, history.length - 10);
  }
}
```

**Primitives + User Logic = Custom Workflows**

---

## Validation Summary

**4 Production CLIs Analyzed:**

| CLI | LOC | Key Finding |
|-----|-----|-------------|
| Claude Code | 11K | Simple async/await validates |
| Gemini CLI | 231K | Compression critical (not deferrable) |
| Codex | 182K | SQ/EQ can be skipped, history normalization synchronous |
| Qwen Code | 3K + 6K tests | Test-to-code ratio 1.8:1, parser needs 66+ tests |

**Verdict:**
✅ Architecture validated
✅ Primitives-first approach confirmed
✅ Timeline adjusted (3.5 → 4 weeks)

---

## Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| 5.1 | 2.5 weeks | Core primitives + StreamingToolCallParser |
| 5.2 | 1.5 weeks | Multi-provider + helpers |
| **Total** | **4 weeks** | All 7 primitives |

**See [roadmap.md](roadmap.md) for day-by-day breakdown.**

---

## Success Criteria

Phase 5 ships when all 4 work:

1. **Streaming with tool calls** - 500+ byte args split across 10+ events reassemble
2. **Provider switching** - Same code works with anthropic/openai/ollama
3. **Context gathering** - Zero-copy access to buffer/symbols/diagnostics
4. **Users compose workflows** - Primitives combine naturally into working apps

---

## Cross-References

**Parent:** [Main Roadmap](../roadmap/README.md)
**Related:** [Testing Architecture](../development/testing-architecture.md)
**Historical:** [Research Analysis](historical/research.md)
