# Vimcraft: Infrastructure Platform for AI Coding Tools

## Executive Summary

Vimcraft is not just another code editor – it's an **open infrastructure platform** designed from the ground up to be the runtime foundation for next-generation AI coding tools.

Instead of competing with tools like Claude Code CLI, Cursor, or Windsurf, Vimcraft provides the **bare-metal primitives and orchestration layer** that these tools need to operate efficiently, allowing them to focus purely on AI/agent innovation while Vimcraft handles:

- Code analysis & indexing
- Terminal rendering & cross-platform support
- Subprocess execution & testing
- Memory & state management
- Tool use & MCP integration
- Real-time event streaming

**Key Insight**: Every AI coding tool is rebuilding the same infrastructure. Vimcraft provides it once, properly, and openly.

---

## The Problem: AI Tools Reinventing Infrastructure

Current AI coding tools face common challenges:

### Claude Code CLI
- Limited to terminal stdout/stderr rendering
- Each platform needs separate implementation
- File I/O, subprocess handling, codebase indexing all custom-built
- Hard to extend with plugins or custom tools

### Cursor
- Tightly coupled AI logic with editor
- Proprietary, closed ecosystem
- Difficult for other AI providers to integrate

### VSCode Extensions
- Extension API not designed for agentic workflows
- Performance constraints
- Heavy runtime overhead

**Common pain point**: Every tool rebuilds codebase analysis, memory management, tool orchestration, and terminal UI from scratch.

---

## The Solution: Vimcraft as Infrastructure

Vimcraft provides a **three-layer architecture**:

### Layer 1: Bare-Metal Primitives
Minimal, powerful APIs that AI tools compose:

```typescript
// Codebase operations
codebase.files(): Promise<FileInfo[]>
codebase.readFile(path): Promise<string>
codebase.watch(globs): AsyncIterable<FileChangeEvent>

// AST & analysis
ast.parse(file, language): Promise<AST>
ast.query(language, selector): Promise<ASTNode[]>

// Memory & persistence
memory.store(key, value, options?): Promise<void>
memory.get(key): Promise<any>

// Tool use (MCP compatible)
tools.register(toolDef: MCPToolDef): void
tools.call(toolName, args): Promise<ToolResult>

// Workspace & execution
workspace.rootPath(): string
terminal.exec(command, options?): Promise<ExecResult>

// Real-time events
events.on(eventType, callback): Unsubscribe

// Rendering (optional)
render.panel(id, options): Panel
render.progress(label, total?): ProgressBar

// Code modification
patch.create(file, changes): Patch
patch.apply(patch, options?): Promise<ApplyResult>
```

### Layer 2: Agentic Orchestration
Framework for defining AI agent lifecycles:

```typescript
agent.definePhases({
  "understand": async (ctx) => { /* analyze codebase */ },
  "plan": async (ctx) => { /* generate approach */ },
  "edit": async (ctx) => { /* apply changes */ },
  "test": async (ctx) => { /* run tests */ },
  "refine": async (ctx) => { /* iterate */ },
})

agent.run(prompt, context): AsyncIterable<AgentEvent>
```

### Layer 3: Plugin Ecosystem
Community-built AI agents and tools.

---

## Core Design Principles

### 1. **Non-Opinionated by Design**
Vimcraft doesn't decide:
- How to index codebases (AI tool decides strategy)
- Which LLM to use (bring your own)
- What tools to expose (MCP compatible, extensible)
- UI layout (optional rendering, terminal-first)

### 2. **Infrastructure, Not Application**
Think of Vimcraft as:
- **React Native for AI editors**: Write once, deploy everywhere
- **Docker for AI coding tools**: Standard runtime, pluggable components
- **Kubernetes for agents**: Orchestration without opinion

### 3. **Claude Code Friendly**
Specifically designed so Claude Code team can port their CLI to Vimcraft plugin **effortlessly**:

```typescript
// @vimcraft/claude-code plugin
export const ClaudeCodePlugin = {
  phases: {
    "understand": async (ctx) => {
      // Reuse existing Claude Code indexing logic
      const files = await codebase.files()
      const ast = await Promise.all(files.map(f => ast.parse(f)))
      await memory.store("context", buildContext(ast))
    },
    "edit": async (ctx) => {
      // Call Claude API with context
      const response = await claudeAPI.call(ctx.prompt, ctx.memory)
      await patch.apply(response.patch)
    },
    // ... rest of agent loop
  }
}
```

**Benefits for Claude Code team:**
- No need to maintain file I/O, subprocess, rendering logic
- Focus 100% on AI/agent innovation
- Automatic cross-platform support
- Better UX out of the box (panels, progress bars)
- Inherit Vimcraft plugin ecosystem

---

## Technical Stack

### Core Engine
- **Language**: Zig (performance, safety, C interop)
- **JavaScript Runtime**: Hermes + JSI (zero-copy bridge from React Native)
- **AST Parsing**: Tree-sitter (incremental, fast)
- **Terminal Rendering**: GPU-accelerated, cross-platform

### Plugin Development
- **Language**: TypeScript/JavaScript (familiar to all developers)
- **API**: Fully typed, well-documented
- **Debugging**: Chrome DevTools integration
- **Hot Reload**: Changes apply instantly

### MCP Integration
Full support for Model Context Protocol:
- Tools registration
- Resource exposure
- Prompts/templates
- Sampling

---

## The Five-Phase Agent Loop

Vimcraft provides structure for the canonical AI coding workflow:

```
User Intent (natural language or selection)
    ↓
[UNDERSTAND] Phase
  - Read context (open files, cursor position, selection)
  - Parse AST, build code graph
  - Load memory blocks (previous context, user preferences)
  - Result: Rich understanding of task
    ↓
[PLAN] Phase
  - Generate approach (which files to edit, strategy)
  - Validate feasibility
  - Get user confirmation if needed
    ↓
[EDIT] Phase
  - Generate code changes (patches)
  - Preview diff
  - Apply with undo tracking
    ↓
[TEST] Phase
  - Run tests, linters, type-checkers
  - Capture results
  - Parse pass/fail
    ↓
[REFLECT] Phase
  - Analyze results
  - Update memory (learned patterns, user feedback)
  - Propose next action or finish
    ↓
[ITERATE]
  - User approves, modifies, or requests changes
  - Loop back to appropriate phase
```

**Key insight**: Every AI coding tool follows this loop. Vimcraft makes it first-class.

---

## Positioning & Go-to-Market

### Strategic Narrative

**Not**: "Vimcraft is a better Neovim with AI"  
**But**: "Vimcraft is the infrastructure platform for AI coding tools"

**Not**: "We compete with Cursor"  
**But**: "We provide the runtime that Cursor, Claude Code, and others need"

### Target Partnerships

1. **Anthropic / Claude Code**
   - Port Claude Code CLI to Vimcraft plugin
   - Better UX, multiplatform support
   - Focus on AI innovation, not infrastructure

2. **AI Model Providers**
   - OpenAI, Cohere, Mistral, local models
   - Vimcraft as reference implementation for coding agents

3. **Plugin Developers**
   - Open ecosystem for custom AI agents
   - Reward early contributors (token/bounty program)

### Funding Strategy

**Phase 1 (0-6 months)**: Build core + demonstrate Claude Code integration
- Target: Seed $500K-$1.5M
- Approach: Direct VC (a16z, Founders Fund) or YC W26

**Phase 2 (6-12 months)**: Launch marketplace, 100+ plugins
- Target: Series A $5-15M
- Metrics: 50K users, strategic partnerships (Anthropic?)

---

## Competitive Advantages

### vs Cursor
- **Cursor**: Closed, single AI provider
- **Vimcraft**: Open infrastructure, any AI tool

### vs VSCode
- **VSCode**: Editor with extensions
- **Vimcraft**: AI-agent runtime that happens to be editor-capable

### vs Neovim
- **Neovim**: Vim with Lua plugins
- **Vimcraft**: Infrastructure platform with TypeScript plugins + AI primitives

### vs Claude Code CLI
- **Claude Code**: Standalone tool, limited rendering
- **Vimcraft**: Platform Claude Code can plug into for better UX

---

## Why This Matters

### For AI Tool Builders
- Stop reinventing infrastructure
- Focus on AI innovation
- Instant multiplatform support
- Rich plugin ecosystem

### For Developers
- Best-of-breed AI tools in one platform
- Compose multiple agents
- Extensible, hackable
- Not locked to one vendor

### For Investors
- Infrastructure play, not just another editor
- Network effects through plugin marketplace
- Strategic partnerships with AI leaders
- Defensible moat (platform effects)

---

## Technical Differentiation

### 1. Zero-Copy JSI Bridge
Unlike Node.js or Python embedding, Vimcraft uses Hermes JSI:
- Direct native ↔ JavaScript calls (no serialization)
- Synchronous execution
- Pointer-based parameters
- React Native battle-tested

### 2. Incremental AST Parsing
Tree-sitter integration:
- Parse changes only (not full file)
- Query language for semantic search
- Language-agnostic

### 3. Built-in MCP Support
Not bolted on – designed from start:
- Tools, resources, prompts first-class
- Standard protocol for AI tool interop

### 4. Plugin Hot Reload
Changes apply instantly:
- No restart needed
- Chrome DevTools debugging
- Fast iteration cycle

---

## Roadmap

### Phase 1: Core Infrastructure (Months 0-3)
- [ ] Finalize bare-metal API (codebase, ast, memory, tools, terminal)
- [ ] Implement agentic lifecycle orchestrator
- [ ] MCP integration
- [ ] TypeScript SDK with full types

### Phase 2: Claude Code Integration (Months 3-6)
- [ ] Port Claude Code CLI logic to Vimcraft plugin
- [ ] Demo: Same Claude Code experience, better UX
- [ ] Document integration guide
- [ ] Approach Anthropic for partnership

### Phase 3: Plugin Ecosystem (Months 6-12)
- [ ] Launch plugin marketplace
- [ ] Port top 20 Neovim plugins
- [ ] Bounty program for plugin authors
- [ ] 100+ plugins milestone

### Phase 4: Strategic Partnerships (Months 12-18)
- [ ] Anthropic/Claude partnership
- [ ] OpenAI integration (Codex, GPT agents)
- [ ] Series A funding
- [ ] 50K+ users, $500K+ MRR

---

## Call to Action

### For Claude Code Team

Imagine Claude Code with:
- Rich panel UI instead of stdout
- Cross-platform support out of the box
- No infrastructure maintenance
- Plugin ecosystem synergy
- Better developer experience

**Proposal**: Port Claude Code CLI to Vimcraft plugin. We provide infrastructure, you focus on AI excellence.

### For Plugin Developers

Build the future of AI coding tools:
- TypeScript (not Lua)
- Full access to AI primitives
- Chrome debugging
- Hot reload
- Marketplace monetization

### For Investors

This is not "another editor" – this is **infrastructure for the AI coding era**.

- Market: Every developer (100M+)
- Timing: AI coding tools exploding now
- Moat: Platform effects + plugin ecosystem
- Team: Strong technical founder, proven execution

---

## Contact & Next Steps

**Website**: vimcraft.com  
**GitHub**: github.com/vimcraft-labs/vimcraft  
**Documentation**: docs.vimcraft.com (coming soon)

**Immediate priorities**:
1. Finalize bare-metal API spec
2. Build Claude Code integration demo
3. Approach Anthropic for partnership discussion
4. Seed funding conversations

---

*Last updated: November 2025*
*Version: 0.1 (Developer Preview)*