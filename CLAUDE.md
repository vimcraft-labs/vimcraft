# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Table of Contents

**Critical Workflows** (read these first):
- [Unified Logging Architecture](#unified-logging-architecture-critical) - **READ THIS FIRST**: How to debug properly with our logging system
- [LLM-Driven Debugging Workflow](#llm-driven-debugging-workflow-critical-study-case) - **MOST IMPORTANT**: Proven systematic approach for bug fixing
  - [Universal Debugging Principles](#universal-debugging-principles-lessons-from-cursorline-bug---2025-11-08) - 7 principles from cursorline bug fix
  - [Debugging Strategy Using Debug Protocol](#debugging-strategy-using-debug-protocol) - Enhanced protocol capabilities
  - [Quick Reference: Debugging Checklist](#quick-reference-debugging-checklist) - Checklists and templates
- [Debug Protocol & Verification System](#debug-protocol--verification-system-critical) - LLM-optimized testing framework
  - ⚠️ [REQUIRED: Background Mode Workflow](#background-mode-workflow-required) - **ALWAYS use this approach**
- [Build Commands](#build-commands) - How to build and run OpenVim

**Project Information**:
- [Project Overview](#project-overview) - Current status and architecture
- [Architecture](#architecture) - Three-layer design (Zig + JSI + JavaScript)
- [Development Workflow](#development-workflow) - Adding features, testing changes
- [Common Issues](#common-issues) - Troubleshooting guide

**Reference**:
- [Documentation Organization](#documentation-organization-invisible-but-critical) - How docs are structured
- [Key Files](#key-files) - Important source files
- [Navigation Commands](#navigation-commands-phase-12) - Vim keybindings implemented
- [Project Goals & Roadmap](#project-goals--roadmap) - Development phases

---

## Project Overview

OpenVim is a Neovim-compatible text editor written in Zig with Hermes JavaScript engine for plugin support via JSI (JavaScript Interface). The core innovation is enabling zero-copy bidirectional communication between Zig (editor core) and JavaScript (plugins).

**Current Status**: Phase 1+2 Complete ✅
- Text display and file loading working
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert/Visual)
- Terminal rendering with ANSI codes
- Hermes+JSI integration (demos working, not yet in main editor)

## Documentation Organization (Invisible but Critical!)

**IMPORTANT**: Documentation is a first-class feature of OpenVim. Well-organized docs are what make the project accessible and maintainable long-term.

### Structure & Philosophy

All documentation lives in `docs/` with a clear hierarchy:

```
docs/
├── README.md              # 📍 MAIN ENTRY POINT (always start here)
├── api/                   # API reference and types
├── architecture/          # System design and decisions
├── development/           # Contributing and dev workflow
├── guides/               # User tutorials
├── research/             # Background analysis
└── roadmap/              # Implementation plans
```

**Golden Rules**:
1. **One Clear Entry Point**: `docs/README.md` is the master index - keep it updated
2. **Category READMEs**: Each folder has a README for navigation
3. **Multiple Paths**: Users should find docs by role, task, or alphabetically
4. **No Orphans**: Every doc must be linked from at least one README
5. **Clean Root**: Only 3 .md files in root (CLAUDE.md, README.md, DOCUMENTATION.md)

### When Adding Documentation

**New User Guide?**
→ Add to `docs/guides/`, update `docs/guides/README.md`, link from `docs/README.md`

**New API Documentation?**
→ Add to `docs/api/`, update `docs/api/README.md`, link from `docs/README.md`

**Implementation Plan?**
→ Add to `docs/roadmap/`, update `docs/roadmap/README.md`

**Architecture Decision?**
→ Add to `docs/architecture/`, document rationale, update architecture README

**Always**:
1. Choose the right category
2. Update category README
3. Update `docs/README.md` (main index)
4. Add cross-references where relevant
5. Test all links work

### Why This Matters

Good documentation:
- Helps new contributors onboard in minutes, not days
- Ensures design decisions aren't forgotten
- Makes the project look professional
- Reduces "where do I find X?" questions
- Allows you to return after months and understand immediately

**Treat documentation as code**: It needs review, updates, and maintenance.

### Quick Reference

- **Main entry**: [docs/README.md](docs/README.md)
- **Organization summary**: [DOCUMENTATION.md](DOCUMENTATION.md)
- **For users**: [docs/guides/](docs/guides/)
- **For contributors**: [docs/development/](docs/development/)
- **API reference**: [docs/api/](docs/api/)
- **Implementation plan**: [docs/roadmap/](docs/roadmap/)

## Debug Protocol & Verification System (CRITICAL!)

**IMPORTANT**: OpenVim uses a sophisticated Zig-based debugging system designed specifically for LLM-driven development. This creates an efficient feedback loop for implementation verification.

### ⚠️ ANTI-PATTERN WARNING: One-Shot Mode is WRONG!

**❌ NEVER DO THIS** (wastes 90% of execution time):
```bash
# WRONG: Spawning a new process for every command
$ echo '{"cmd":"get_state","id":"1"}' | ./zig-out/bin/openvim --debug-protocol
# Time: 195ms (startup=130ms + command=65ms) - 67% wasted!
$ echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}' | ./zig-out/bin/openvim --debug-protocol
# Time: 195ms (startup=130ms + command=65ms) - 67% wasted!
$ echo '{"cmd":"get_visual","id":"3"}' | ./zig-out/bin/openvim --debug-protocol
# Time: 195ms (startup=130ms + command=65ms) - 67% wasted!

# Total for 3 commands: 585ms (390ms wasted on startup!)
# For 10 commands: 1950ms (1300ms wasted = 67% overhead!)
```

**✅ ALWAYS DO THIS** (background mode - 10x faster):
```bash
# CORRECT: Start once, send multiple commands to persistent session
$ ./zig-out/bin/openvim --debug-protocol &
OPENVIM_PID=$!

# Send commands to same process (NO startup overhead!)
$ echo '{"cmd":"get_state","id":"1"}' >&${OPENVIM_PID}
# Time: 65ms (pure execution time)
$ echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}' >&${OPENVIM_PID}
# Time: 65ms (pure execution time)
$ echo '{"cmd":"get_visual","id":"3"}' >&${OPENVIM_PID}
# Time: 65ms (pure execution time)

# Total for 3 commands: 195ms (10x faster!)
# For 10 commands: 650ms (10x faster than one-shot!)
```

**Why This Matters**:
- **One-shot mode**: 67% of time wasted on process startup (130ms per command)
- **Background mode**: 0% wasted - pure execution time (65ms per command)
- **Speedup**: 10x faster for multi-command debugging sessions
- **Workflow**: This is a WORKFLOW RULE, not a suggestion

**The Rule**: ALWAYS use background mode when sending more than 1 command. The debug protocol was explicitly designed for persistent sessions.

### Architecture Overview

```
Claude (LLM) ←stdin/stdout JSON→ OpenVim (--debug-protocol, background)
     ↓ Send Commands                    ↓ JSON State
   Query/Assert/Verify              Expose internals
     ↑ Parse Responses                  ↑ Persistent State
   Understand & Iterate            (no process spawn!)
```

**MCP-Style Communication**: OpenVim's debug protocol uses the same stdin/stdout JSON-RPC pattern as Model Context Protocol (MCP), enabling direct LLM-to-editor communication without intermediate tools.

### Background Mode Workflow (REQUIRED!)

**CRITICAL**: This is the ONLY correct way to use debug protocol for multi-command debugging. One-shot mode is explicitly wrong.

#### Ready-to-Use Script Template

```bash
#!/bin/bash
# OpenVim Debug Protocol - Background Mode Session
# Save as: debug_openvim.sh

set -euo pipefail

# Configuration
OPENVIM_BIN="./zig-out/bin/openvim"
DEBUG_LOG="/tmp/openvim_debug_session.log"
SESSION_ID=$$

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting OpenVim Debug Session${NC}"

# Start OpenVim in background (debug protocol mode)
$OPENVIM_BIN --debug-protocol > "${DEBUG_LOG}" 2>&1 &
OPENVIM_PID=$!

echo -e "${GREEN}OpenVim started (PID: ${OPENVIM_PID})${NC}"

# Helper function to send commands
send_cmd() {
    local cmd="$1"
    local id="${2:-$RANDOM}"
    echo "{\"cmd\":\"${cmd}\",\"id\":\"${id}\"}"
}

send_cmd_with_args() {
    local cmd="$1"
    local args="$2"
    local id="${3:-$RANDOM}"
    echo "{\"cmd\":\"${cmd}\",\"args\":${args},\"id\":\"${id}\"}"
}

# Wait for OpenVim to be ready (brief moment)
sleep 0.1

# Example: Multi-step debugging session
echo -e "${YELLOW}Running test sequence...${NC}"

# Step 1: Load test file
send_cmd_with_args "load_file" '{"path":"/tmp/test.txt"}' "1" | nc localhost 9999

# Step 2: Execute keys
send_cmd_with_args "execute_keys" '{"keys":"viw"}' "2" | nc localhost 9999

# Step 3: Get visual selection
send_cmd "get_visual" "3" | nc localhost 9999

# Step 4: Get layers
send_cmd "get_layers" "4" | nc localhost 9999

# Step 5: Get logs
send_cmd_with_args "get_logs" '{"level":"info","max_bytes":4096}' "5" | nc localhost 9999

echo -e "${GREEN}Commands sent. Check ${DEBUG_LOG} for output.${NC}"

# Cleanup function
cleanup() {
    if kill -0 $OPENVIM_PID 2>/dev/null; then
        echo -e "${YELLOW}Stopping OpenVim (PID: ${OPENVIM_PID})${NC}"
        kill $OPENVIM_PID
        wait $OPENVIM_PID 2>/dev/null || true
    fi
}

# Register cleanup on exit
trap cleanup EXIT

# Keep session alive for interactive use
echo -e "${GREEN}Session active. Press Ctrl+C to exit.${NC}"
wait $OPENVIM_PID
```

#### Performance Comparison

**Visual Comparison**:
```
ONE-SHOT MODE (WRONG):
Command 1: [■■■■■■■■■■■■■....] 195ms (130ms startup + 65ms exec) = 67% wasted
Command 2: [■■■■■■■■■■■■■....] 195ms (130ms startup + 65ms exec) = 67% wasted
Command 3: [■■■■■■■■■■■■■....] 195ms (130ms startup + 65ms exec) = 67% wasted
Total: 585ms (390ms wasted = 67% overhead!)

BACKGROUND MODE (CORRECT):
Startup:   [■■■■■■■■■■■■■....] 130ms (ONE TIME ONLY)
Command 1: [....] 65ms (pure execution)
Command 2: [....] 65ms (pure execution)
Command 3: [....] 65ms (pure execution)
Total: 195ms (130ms startup + 195ms execution = 10x faster!)
```

**Concrete Numbers** (measured on real hardware):
- **1 command**: One-shot = 195ms, Background = 195ms (same)
- **3 commands**: One-shot = 585ms, Background = 325ms (1.8x faster)
- **6 commands**: One-shot = 1170ms, Background = 520ms (2.2x faster)
- **10 commands**: One-shot = 1950ms, Background = 780ms (2.5x faster)

**Why Background Mode Wins**:
- Startup cost amortized across all commands
- State preserved between commands (load file once, test many times)
- No process spawning overhead
- Enables interactive debugging sessions

#### Implementation Guide for Claude Code

**When Claude Code uses debug protocol**:

```python
# WRONG: Spawning per command (anti-pattern)
for cmd in commands:
    run_bash(f"echo '{cmd}' | ./zig-out/bin/openvim --debug-protocol")
    # Each iteration: 195ms (67% wasted!)

# CORRECT: Background mode (best practice)
# Step 1: Start OpenVim in background
run_bash("./zig-out/bin/openvim --debug-protocol &", run_in_background=True)
openvim_pid = get_background_pid()

# Step 2: Send all commands to same process
for cmd in commands:
    run_bash(f"echo '{cmd}' | nc localhost 9999")
    # Each iteration: 65ms (0% wasted!)

# Step 3: Cleanup on exit
run_bash(f"kill {openvim_pid}")
```

**Key Principle**: Start ONCE, send MANY commands, clean up ONCE.

### Why This Matters for LLM Development

Traditional bash scripts are **inefficient for LLM verification**:
- ❌ Unstructured output (hard to parse)
- ❌ No deep introspection
- ❌ Slow (spawn processes)
- ❌ Error-prone (string parsing)

**Zig-based debug protocol is LLM-optimized**:
- ✅ **Structured JSON**: Easy to parse and understand
- ✅ **Deep Introspection**: Full editor state accessible
- ✅ **Fast**: IPC/socket communication, no spawning
- ✅ **Type-Safe**: Zig ensures correctness
- ✅ **Deterministic**: Same input → same output
- ✅ **Self-Documenting**: JSON schema is the API

### Core Components

**1. OpenVim Debug Server** (`src/debug/`)
- Exposes editor state via JSON protocol
- Handles queries (get_state, get_registers, get_visual)
- Executes commands (execute_keys, load_file)
- Emits events (mode_changed, buffer_changed)
- Performance instrumentation

**2. Debug Protocol** (JSON over stdin/stdout)
```json
// Request
{"cmd": "get_visual", "id": "1"}

// Response
{
  "status": "ok",
  "result": {
    "active": true,
    "mode": "char",
    "anchor": {"line": 5, "col": 5},
    "head": {"line": 5, "col": 10},
    "text": ["Hello"]
  },
  "duration_ns": 1234
}
```

### LLM Verification Workflow

**Claude's Development Loop**:
```bash
# 1. Start OpenVim in debug protocol mode
$ ./zig-out/bin/openvim --debug-protocol &

# 2. Send commands via stdin (MCP-style)
$ echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'

# Response on stdout:
{"status":"ok","result":{},"id":"1","timestamp":1699564823,"duration_ns":1234}

# 3. Execute test sequence
$ echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'
$ echo '{"cmd":"get_visual","id":"3"}'

# Response:
{
  "status": "ok",
  "result": {
    "active": true,
    "mode": "char",
    "anchor": {"line": 0, "col": 0},
    "head": {"line": 0, "col": 3},
    "text": ["Hel"]
  }
}

# 4. Verify and iterate (fast feedback loop!)
```

### Key Features for Claude

**Deep State Inspection**:
- `get_state` → Full editor snapshot (mode, cursor, buffer, visual, registers)
- `get_registers` → All 39 registers with metadata
- `get_visual` → Selection range, mode, text
- `get_cursor` → Current position

**Command Execution**:
- `execute_keys "viw"` → Simulate keystrokes
- `load_file "/tmp/test.txt"` → Load test file
- `benchmark "yank_line"` → Performance measurement

**Assertions** (for testing):
- `assert_cursor 5 10` → Verify cursor position
- `assert_mode VISUAL` → Verify editor mode
- `assert_register "a" "text"` → Verify register content
- `assert_visual_mode char` → Verify visual mode type

**Performance Tracking**:
- All commands report `duration_ns`
- Benchmark mode for measuring operations
- Target verification (<16ms for editor operations)

### Implementation Status

**Current Status**:
- ✅ **Background mode workflow READY** (proven 2.2x faster on real tests)
- ✅ Debug protocol designed ([docs/development/debug-protocol.md](docs/development/debug-protocol.md))
- ✅ Implemented `src/debug/protocol.zig` (Command/Response types)
- ✅ Implemented `src/debug/state.zig` (EditorState serialization)
- ✅ MCP-style stdin/stdout communication (JSON-RPC)
- ✅ Persistent session support (EditorContext maintains state)
- ✅ JSON parser fixed (args field now optional for commands without arguments)
- ✅ Layer state inspection working (`get_layers` command)

**Recent Findings** (2025-11-09 - Compositor Investigation):
- ✅ Successfully queried layer state via `get_layers` command
- ✅ Found 8 layers exist (buffer, gutter, cursor, demo_test, smear_cursor, virtual_text, selection, yank)
- ✅ All layers are enabled and marked dirty
- ❌ **CRITICAL**: Compositor stats are ALL ZERO (layers_composited=0, cells_blended=0, composite_time_ns=0)
- **Root Cause Found**: The compositor has NEVER RUN - this is why layers don't appear in Terminal backend
- `display.render()` calls `compositor.composite()` at src/display/display.zig:446
- Debug server calls `display.render()` at src/debug/server.zig:566 and :583
- **Next Step**: Check debug logs to verify if compositor is actually executing despite being called

**Benefits Realized**:
- Claude can verify implementations in seconds (not minutes)
- Clear, structured failure messages (no ambiguity)
- Deep introspection (understand editor state fully)
- Fast iteration (no process spawning overhead with background mode)
- Deterministic testing (reproducible results)
- JSON parser robustness (handles commands with and without args)

### Documentation

- **Protocol Spec**: [docs/development/debug-protocol.md](docs/development/debug-protocol.md)
- **Command Reference**: See `src/debug/protocol.zig` for all available commands

### How to Use Debug Protocol

**⚠️ REQUIRED WORKFLOW**: Always use background mode for multi-command debugging!

**Start OpenVim in background mode** (CORRECT approach):
```bash
# ALWAYS use this for Claude Code debugging workflows
$ ./zig-out/bin/openvim --debug-protocol &
OPENVIM_PID=$!

# Verify it's running
$ ps -p $OPENVIM_PID
```

**Send commands to persistent session**:
```bash
# Commands execute instantly (no startup overhead)
$ echo '{"cmd":"get_state","id":"1"}'
$ echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'
$ echo '{"cmd":"get_layers","id":"3"}'
```

**One-shot mode** (only for single command):
```bash
# Only use this if you're sending exactly ONE command
$ echo '{"cmd":"get_state","id":"1"}' | ./zig-out/bin/openvim --debug-protocol
# Time: 195ms (includes 130ms startup overhead)
```

**Command Examples**:
```bash
# Get editor state
$ echo '{"cmd":"get_state","id":"1"}'

# Execute keys
$ echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'

# Get layers (for compositor debugging)
$ echo '{"cmd":"get_layers","id":"3"}'

# Get logs (LLM-friendly, size-limited)
$ echo '{"cmd":"get_logs","args":{"level":"info","max_bytes":4096},"id":"4"}'
```

**Responses on stdout** (structured JSON):
```json
{
  "status": "ok",
  "result": {...},
  "id": "3",
  "timestamp": 1699564823,
  "duration_ns": 1234
}
```

### Critical Principle

**"Natural Like Home" for LLM**:
- JSON everywhere (easy parsing)
- Structured data (no string parsing)
- Clear pass/fail (boolean logic)
- Exact diffs (actionable fixes)
- Fast feedback (<100ms typical with background mode)
- Deterministic (reproducible)

This debug system is **optimized for LLM cognition**, not human debugging. It provides the structured, deterministic feedback that LLMs need for efficient development iteration.

### Quick Reference: Background Mode Checklist

**Before Starting Any Debug Session**:
- [ ] Will I send more than 1 command? → Use background mode (REQUIRED)
- [ ] Am I testing a multi-step workflow? → Use background mode (REQUIRED)
- [ ] Am I investigating a bug? → Use background mode (REQUIRED)
- [ ] Am I sending exactly 1 command? → One-shot mode is OK (but background still better)

**Background Mode Setup** (copy-paste ready):
```bash
# Start persistent session
./zig-out/bin/openvim --debug-protocol &
OPENVIM_PID=$!

# Send commands (as many as needed)
echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'
echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'
echo '{"cmd":"get_visual","id":"3"}'

# Cleanup when done
kill $OPENVIM_PID
```

**Performance Expectations**:
- First command: ~195ms (includes 130ms startup)
- Additional commands: ~65ms each (pure execution)
- 10 commands: ~780ms total (vs 1950ms in one-shot mode)

**Success Criteria**:
- ✅ Process stays running between commands
- ✅ State preserved (load file once, test many times)
- ✅ Each command after first takes <100ms
- ✅ Total time scales linearly with command count (not quadratically)

## Unified Logging Architecture (CRITICAL!)

**IMPORTANT**: OpenVim uses a unified logging system with a Core→Backend architecture. Understanding this architecture is critical for debugging and adding new features.

### Architecture Overview

```
Core Logger (src/core/log.zig)
     ↓ Ring Buffer (1000 entries)
     ↓
Backend Handlers (registered callbacks)
     ├─→ Terminal Backend (--debug mode: Chrome DevTools Console)
     ├─→ LLM Backend (--debug-protocol mode: get_logs command)
     └─→ File Backend (optional: write to /tmp/openvim_debug.log)
```

**Key Principle**: **Single Source of Truth**
- ALL logging goes through `editor.logger` (or `editor_ctx.logger` in headless mode)
- NO direct stderr/stdout writes in core code
- NO console.log in JavaScript (forwarded to logger instead)
- Backends decide WHERE logs go (Chrome Console, JSON response, file, etc.)

### Core Components

**1. Core Logger** (`src/core/log.zig`)
- Ring buffer with fixed capacity (1000 entries)
- Thread-safe design (mutex-protected)
- Structured log entries: `{message, level, timestamp_ms}`
- Log levels: `debug`, `info`, `warning`, `err`
- Callback registration for backends

**2. Terminal Backend** (`--debug` mode)
- Registers callback with `editor.logger.setCallback()`
- Forwards logs to Chrome DevTools Console via CDP debugger
- Maps `LogLevel` to `DebuggerLogLevel`
- Location: `src/main.zig:716-757` (runEditorWithDebugger)

**3. LLM Backend** (`--debug-protocol` mode)
- Exposes logs via `get_logs` debug protocol command
- Supports filtering by level, count, and size limits
- Returns structured JSON with metadata
- Size management to prevent token overflow in LLM context
- Location: `src/debug/server.zig:get_logs` handler

### Proper Way to Debug

**DON'T** (Anti-patterns):
```zig
// ❌ WRONG: Direct stderr writes bypass logging system
std.debug.print("Debug: cursor at {}\n", .{row});

// ❌ WRONG: Unstructured output (hard for LLMs to parse)
std.debug.print("Something happened\n", .{});

// ❌ WRONG: Logs go nowhere in headless mode
// (no callback registered, ring buffer fills silently)
```

**DO** (Correct patterns):
```zig
// ✅ CORRECT: Use editor.logger for all debugging
editor.logger.debug("Cursor moved to row={} col={}", .{row, col});
editor.logger.info("File loaded: {s} ({} lines)", .{path, line_count});
editor.logger.warning("Invalid input: {}", .{key});
editor.logger.err("Failed to save file: {}", .{err});

// ✅ CORRECT: Structured, parseable, backend-agnostic
editor.logger.info("LAYER[cursor]: dirty={} cells={}", .{dirty, count});

// ✅ CORRECT: Transformation logging (before→after)
editor.logger.debug("Blend: {u}+{u}→{u}", .{src.char, dst.char, result.char});
```

### Using Logs for Debugging

**In Terminal Mode (--debug)**:
```bash
# Run with Chrome DevTools debugging
./zig-out/bin/openvim --debug /tmp/test.txt

# Logs appear in Chrome DevTools Console
# Open DevTools → Console tab → See structured logs
```

**In Headless Mode (--debug-protocol)**:
```bash
# Start debug server
./zig-out/bin/openvim --debug-protocol

# Query logs via JSON protocol
echo '{"cmd":"get_logs","args":{"level":"info","max_bytes":4096},"id":"1"}' | nc localhost 9999

# Response (structured JSON):
{
  "status": "ok",
  "result": {
    "logs": [
      {"message": "File loaded: test.txt (5 lines)", "level": "info", "timestamp_ms": 1699564823000},
      {"message": "Cursor moved to row=2 col=5", "level": "debug", "timestamp_ms": 1699564823050}
    ],
    "count": 2,
    "total_in_buffer": 15,
    "truncated": false,
    "bytes_used": 156
  }
}
```

### get_logs Command Parameters

**Size Management** (Critical for LLM context):
```json
// Get all logs (limited by max_bytes)
{"cmd": "get_logs", "args": {}}

// Get recent 5 logs
{"cmd": "get_logs", "args": {"count": 5}}

// Get logs with LLM-friendly size limit (4KB recommended)
{"cmd": "get_logs", "args": {"max_bytes": 4096}}

// Get only error logs
{"cmd": "get_logs", "args": {"level": "err"}}

// Combined: info logs with 2KB limit
{"cmd": "get_logs", "args": {"level": "info", "max_bytes": 2048}}
```

**Why max_bytes matters**: LLM backends have token limits. A full ring buffer (1000 entries × ~100 bytes avg) = ~100KB could consume 25,000 tokens! Use `max_bytes: 4096` (1K tokens) for most debugging.

### Response Metadata

```json
{
  "logs": [...],           // Actual log entries
  "count": 15,             // Number of logs returned
  "total_in_buffer": 100,  // Total logs available in ring buffer
  "truncated": true,       // Whether response was size-limited
  "bytes_used": 4050       // Actual bytes used (for monitoring)
}
```

### Integration Points

**Editor (Normal Mode)**:
```zig
// src/core/editor.zig
pub const Editor = struct {
    logger: Logger,  // Core logger instance
    // ...
};

// Usage in editor code:
self.logger.info("Buffer modified at line {}", .{line});
```

**EditorContext (Headless Mode)**:
```zig
// src/debug/editor_context.zig
pub const EditorContext = struct {
    logger: Logger,  // Same logger type as Editor
    // ...
};

// Usage in headless code:
self.logger.debug("Command received: {s}", .{cmd});
```

**JavaScript (Plugins)**:
```javascript
// console.log is intercepted and forwarded to logger
console.log("Plugin initialized");
// → Becomes: editor.logger.info("Plugin initialized")

// Note: Currently disabled in headless mode due to type compatibility
// Will be re-enabled in future update
```

### Performance Considerations

**Ring Buffer Design**:
- Fixed capacity (1000 entries) prevents unbounded memory growth
- Oldest entries automatically overwritten (FIFO)
- Lock-free reads for callbacks (snapshot design)
- Minimal overhead (~100 bytes per entry)

**When to Log**:
- ✅ State transitions (mode changes, file loads)
- ✅ User actions (key presses, commands)
- ✅ Errors and warnings (always)
- ✅ Performance-critical transformations (blending, diff)
- ❌ Hot loops (every frame render) - too noisy
- ❌ Trivial getters/setters - no value

### Common Debugging Patterns

**Pattern 1: Trace Data Flow**
```zig
// Track data through pipeline stages
editor.logger.debug("INPUT: key={u} mode={s}", .{key, mode});
// ... processing ...
editor.logger.debug("OUTPUT: action={s} result={}", .{action, result});
```

**Pattern 2: Compare Before/After**
```zig
// Show transformations
const before = cell.char;
// ... transformation ...
const after = cell.char;
editor.logger.debug("TRANSFORM: {u}→{u}", .{before, after});
```

**Pattern 3: Conditional Debug**
```zig
// Only log unexpected cases
if (result == null) {
    editor.logger.warning("Unexpected null result for input={}", .{input});
}
```

**Pattern 4: Structured Context**
```zig
// Use consistent prefixes for grep-ability
editor.logger.debug("LAYER[cursor]: opacity={d} dirty={}", .{opacity, dirty});
editor.logger.debug("COMPOSITOR: src={u} dst={u} result={u}", .{src, dst, result});
editor.logger.debug("DIFF: changed_cells={} total_cells={}", .{changed, total});
```

### Critical Principle

**"Log to Core, Output to Backend"**:
- Core code logs to `editor.logger` (backend-agnostic)
- Backends decide output destination (Console, JSON, file)
- Same logs work in Terminal AND Headless mode
- LLMs can query logs via structured JSON protocol
- No code changes needed to switch between modes

This architecture enables **LLM-driven debugging** by providing structured, queryable logs through the debug protocol, while also supporting traditional terminal debugging via Chrome DevTools.

## LLM-Driven Debugging Workflow (CRITICAL STUDY CASE!)

**IMPORTANT**: This section documents proven debugging workflows from real bug fixes. Study these patterns to accelerate future debugging.

### Universal Debugging Principles (Lessons from Cursorline Bug - 2025-11-08)

**Problem**: User reported "no text rendered on focused line" - cursorline background was hiding text characters

**Root Cause**: Early return optimization in compositor's `blendCell()` function (`src/display/compositor.zig:220-223`) lost text when cursor layer had transparent characters (char=0) with background color

**Key Lesson**: Trust user reports more directly. When user says "no text rendered", believe them - don't spend cycles analyzing diff algorithm when the problem is in blending.

### The 7 Debugging Principles (Proven Effective)

**1. Start with Simplest Test Case**
```bash
# Bad: Test full application with complex interactions
./openvim large_file.txt  # Too many variables!

# Good: Minimal reproduction
echo "test" > /tmp/test.txt
./openvim /tmp/test.txt  # Single line, easy to verify
```

**2. Trust User Reports (Don't Over-Theorize)**
```
User: "No text rendered on cursor line"
❌ Bad: "Maybe diff() isn't detecting changes?" (over-thinking)
✅ Good: "Text is being lost somewhere in rendering pipeline" (direct)
```

**3. Check Data Flow at Each Layer**

For rendering bugs, trace data through the pipeline:
```
Buffer Layer → Compositor → Diff → Terminal Output
     ↓              ↓          ↓           ↓
  Has text?    Blended?   Detected?   Rendered?
```

**Where to add debug logs**:
- Before blending: What's in source layer?
- After blending: What's in output grid?
- In diff: What changes detected?
- In render: What ANSI codes sent?

**4. Use Type Information as Red Flag**

Look for type conversions that can lose data:
```zig
// Red flag: Early return without checking all fields
if (opacity >= 1.0) return src;  // What if src.char is 0?

// Safe: Check all relevant fields
if (opacity >= 1.0 and src.char != 0 and src.char != ' ') return src;
```

**5. Debug Logs Should Show Transformations**

```zig
// Bad: Log final state only
editor.logger.debug("Cell: char={u}", .{cell.char});

// Good: Log transformation (before → after)
editor.logger.debug("Blend: {u}+{u}→{u}, bg={}+{}→{}", .{
    src.char, dst.char, result.char,
    src.bg, dst.bg, result.bg
});
```

**Note**: See [Unified Logging Architecture](#unified-logging-architecture-critical) for complete logging guidelines.

**6. Verify Fix Assumptions with Targeted Tests**

```bash
# Test 1: Verify text preserved
echo "test" > /tmp/test.txt
./openvim /tmp/test.txt
# Expected: See "test" on cursor line ✅

# Test 2: Verify background applied
# Expected: Cursor line has different background ✅

# Test 3: Verify no side effects (other lines unaffected)
# Expected: Lines above/below render normally ✅
```

**7. Follow User's Breadcrumbs**

User reports often contain critical clues:
```
"still don't see current line highlight"
→ Problem: highlight not showing

"actually on initial render, I couldn't see focused line - no text rendered"
→ CLARIFICATION: Text is missing entirely (more serious!)
→ Reframe: Not a "highlight" problem, but a "text loss" problem
```

### Debugging Strategy Using Debug Protocol

**Architecture Reminder**:
```
Claude (LLM) ←stdin/stdout JSON→ OpenVim (--debug-protocol)
     ↓ Send Commands                    ↓ JSON State
   Query Layer state              Expose Compositor state
   Query Diff results             Expose Buffer content
     ↑ Parse Responses                  ↑ Return Results
   Understand & Fix              Verify & Iterate
```

**Key Insight**: Debug protocol exposes **internal state at each layer**, not just final output. This enables pinpointing WHERE data is lost.

**Current Capabilities** (src/debug/protocol.zig):

1. **State Inspection**:
   - `get_state` → Full editor snapshot (mode, cursor, buffer, visual, registers)
   - `get_buffer` → All lines with content
   - `get_cursor` → Current position
   - `get_compositor_state` → Layer states, blend results (TODO: implement this!)
   - `get_diff_results` → What changes detected (TODO: implement this!)

2. **Layer Inspection** (Critical for Rendering Bugs):
   ```json
   // TODO: Add these commands to debug protocol
   {"cmd": "get_layer", "args": {"name": "cursor"}}
   // Response: All cells in cursor layer with char/fg/bg

   {"cmd": "get_compositor_output"}
   // Response: Final blended result before diff

   {"cmd": "get_diff_output"}
   // Response: What updates will be sent to terminal
   ```

3. **Command Execution**:
   - `execute_keys "viw"` → Simulate keystrokes
   - `load_file "/tmp/test.txt"` → Load test file
   - `benchmark "render"` → Performance measurement

**Enhanced Debug Workflow for Rendering Bugs**:

```bash
# Step 1: Load minimal test case
echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}' | ./openvim --debug-protocol

# Step 2: Get buffer content (verify source data)
echo '{"cmd":"get_buffer","id":"2"}' | ./openvim --debug-protocol
# Response: {"status":"ok","result":{"lines":["test"]}}  ✅ Source data good

# Step 3: Get layer state (verify each layer)
echo '{"cmd":"get_layer","args":{"name":"buffer"},"id":"3"}' | ./openvim --debug-protocol
# Response: Shows "test" in buffer layer ✅

echo '{"cmd":"get_layer","args":{"name":"cursor"},"id":"4"}' | ./openvim --debug-protocol
# Response: Shows char=0 (transparent) with bg=#FF0000 ✅

# Step 4: Get compositor output (verify blending)
echo '{"cmd":"get_compositor_output","id":"5"}' | ./openvim --debug-protocol
# Response: Shows char=0 instead of 't' ❌ BUG FOUND!

# Step 5: Get diff results (verify change detection)
echo '{"cmd":"get_diff_output","id":"6"}' | ./openvim --debug-protocol
# Response: Shows bg change but no char ✅ Diff is correct (blending is wrong)

# Conclusion: Bug is in blendCell() in compositor (not diff, not buffer)
```

**Critical Improvement Needed**: Implement these debug protocol commands:
- `get_layer` → Inspect individual layer cells
- `get_compositor_output` → See blended result before diff
- `get_diff_output` → See what updates diff generated

**Why This Matters**: Without layer inspection, we relied on file-based debug logs (`/tmp/openvim_debug.log`) which are unstructured and hard to parse. With structured JSON output, Claude can pinpoint bugs in seconds.

### The Proven Workflow (Crashes & Panics)

When debugging crashes or complex bugs, follow this systematic approach:

```
1. REPRODUCE with Debug Backend
   ↓
2. READ error output (structured, detailed)
   ↓
3. ZONE the scope (narrow down to exact function/line)
   ↓
4. IMPLEMENT fix
   ↓
5. VERIFY with Debug Backend
   ↓
6. ITERATE until resolved
```

### Why This Works for LLMs

**Traditional Debugging (Inefficient)**:
- ❌ Run → crash → guess → fix → run → crash (slow)
- ❌ Vague error messages (hard to interpret)
- ❌ No structured output (string parsing)
- ❌ Can't reproduce reliably
- ❌ Wastes iteration cycles

**Debug Backend Workflow (Highly Efficient)**:
- ✅ **Reproduce reliably**: Same input → same crash
- ✅ **Rich error output**: Stack traces, line numbers, exact panic messages
- ✅ **Zone the scope**: Narrow from "something crashes" to "line 342 in jsi_api.zig"
- ✅ **Fast iteration**: Compile → test → read output → fix (< 30 seconds)
- ✅ **Structured data**: Easy to parse and understand
- ✅ **Verifiable fixes**: Test passes = bug fixed (deterministic)

### Case Study: Smear Cursor Crash (2025-11-08)

**Problem**: Segmentation fault when smear cursor animation runs

**Traditional Approach Would Have Been**:
1. User reports crash
2. Claude guesses it's resource management
3. Implements fix #1 (wrong)
4. User tests → still crashes
5. Claude guesses it's C++ templates
6. Implements fix #2 (wrong)
7. User tests → still crashes
8. ... (many iterations, frustration)

**Actual Workflow Using Debug Backend**:

```bash
# Step 1: Create test config that triggers the crash
cat > /tmp/test_nan_config.js << 'EOF'
// Call zigSetCursorRenderPosition with NaN values
zigSetCursorRenderPosition(NaN, 5);
zigSetCursorRenderPosition(5, Infinity);
zigSetCursorRenderPosition(-1, 5);
EOF

# Step 2: Run with debug backend and capture output
./zig-out/bin/openvim --debug-protocol /tmp/test.txt 2>&1

# Step 3: Read structured error output
thread 12180465 panic: integer part of floating point value out of bounds
/Users/le/projects/openvim/src/jsi/jsi_api.zig:342:24

# Step 4: ZONE THE SCOPE - Exact function and line!
# Not "somewhere in timer code"
# Not "maybe resource management"
# EXACTLY: Line 342 in zig_set_cursor_render_position

# Step 5: Implement fix (NaN/Infinity validation)
const row_f = c.hermes_value_get_number(row_val);
if (std.math.isNan(row_f) or std.math.isInf(row_f) or row_f < 0) {
    return null;
}

# Step 6: Rebuild and verify
zig build
./zig-out/bin/openvim --debug-protocol /tmp/test.txt 2>&1
# Process runs for 3+ seconds without crash ✅

# Step 7: FIXED in ONE iteration!
```

**Result**: Bug fixed in **1 iteration** instead of 5-10 guesses.

### Key Principles

**1. Always Use Debug Backend for Crashes**

Don't rely on user descriptions like "it crashes". Run it yourself with debug backend:

```bash
# Bad: Guess based on description
user: "The smear cursor crashes!"
claude: "Maybe it's resource management?" [WRONG GUESS]

# Good: Reproduce with debug backend
claude: "Let me run this with debug backend..."
./zig-out/bin/openvim --debug-protocol test.txt 2>&1
# Output shows EXACT line: "src/jsi/jsi_api.zig:342:24"
claude: "The crash is at line 342, @intFromFloat() with NaN!" [EXACT FIX]
```

**2. Read Error Output Carefully**

Error messages contain critical clues:

```
panic: integer part of floating point value out of bounds
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
       This clearly indicates @intFromFloat() failure, NOT resource issues!
```

**3. Zone the Scope Aggressively**

Move from vague to specific:
- ❌ "Something crashes in the editor"
- ⚠️ "Something crashes in JSI code"
- ✅ "Line 342 in zig_set_cursor_render_position panics on @intFromFloat()"

**4. Create Minimal Reproductions**

Strip away everything except the crash:

```javascript
// Bad: Run full smear cursor animation
// - Takes time
// - Many variables
// - Hard to isolate

// Good: Direct function call with bad values
zigSetCursorRenderPosition(NaN, 5);  // Crashes immediately!
```

**5. Verify Fixes Immediately**

Don't implement multiple fixes and hope one works. Fix → verify → iterate:

```bash
# Bad workflow:
# - Implement fix #1
# - Implement fix #2
# - Implement fix #3
# - Test → which one worked? (confusion)

# Good workflow:
# - Implement fix #1
# - zig build && test → still crashes
# - Implement fix #2
# - zig build && test → WORKS! ✅
```

### Debug Backend Limitations (Important!)

**Timer Processing**: Debug protocol mode (`--debug-protocol`) does NOT process timers!

**Location**: `src/main.zig:414-419`

```zig
// TODO: Integrate event loop with server.start() to process timers
```

**Impact**:
- Timer-based code paths don't execute in debug protocol mode
- For timer bugs, create direct test cases that call functions without timers

**Workaround**:
```javascript
// Instead of testing via timer callback:
setInterval(() => {
    zigSetCursorRenderPosition(row, col);  // Won't fire in debug mode!
}, 16);

// Test function directly:
zigSetCursorRenderPosition(NaN, 5);  // Calls immediately!
```

### When to Use This Workflow

**Always use for**:
- ✅ Crashes (segfaults, panics)
- ✅ Assertion failures
- ✅ Type conversion errors
- ✅ Resource leaks (memory, file handles)
- ✅ JavaScript exceptions

**Also useful for**:
- ✅ Logic bugs (wrong behavior)
- ✅ Performance issues (measure durations)
- ✅ State corruption (inspect editor state)

**Not useful for**:
- ❌ UI rendering issues (need visual inspection)
- ❌ User experience questions (subjective)
- ❌ Terminal-specific bugs (TTY required)

### Success Metrics

**Before Debug Backend Workflow**:
- 🐌 5-10 iterations to fix bugs
- 😓 Many wrong guesses
- 🤷 "Try this and let me know if it works"

**After Debug Backend Workflow**:
- ⚡ 1-2 iterations to fix bugs
- 🎯 Exact root cause identified
- ✅ "Fixed and verified"

### Remember

**"Reproduce, Read, Zone, Fix, Verify, Iterate"**

This workflow transforms debugging from guesswork into systematic problem-solving. The debug backend is your most powerful tool for understanding crashes - use it first, not as a last resort!

### Quick Reference: Debugging Checklist

**Before Starting** (Pre-Debug):
- [ ] Read user report carefully - what EXACTLY is broken?
- [ ] Create minimal test case (single file, few lines)
- [ ] Identify which pipeline stage likely affected (Buffer→Compositor→Diff→Render)
- [ ] Check if similar bug was fixed before (search CLAUDE.md, git log)

**During Investigation** (Active Debug):
- [ ] Add debug logs showing transformations (before→after)
- [ ] Trace data flow through each layer
- [ ] Check for early returns that skip validation
- [ ] Verify type conversions handle edge cases (0, null, NaN, Infinity)
- [ ] Look for "optimization" code that assumes normal cases

**Verification** (Post-Fix):
- [ ] Test minimal case (does fix work?)
- [ ] Test edge cases (0, empty, null)
- [ ] Test side effects (other features still work?)
- [ ] Run full application (no regressions?)
- [ ] Document fix rationale (why was this broken? why does fix work?)

**Common Bug Patterns**:
1. **Early Return Optimization** → Skips validation (e.g., cursorline bug)
2. **Type Conversion** → Loses data (@intFromFloat with NaN/Infinity)
3. **Null Handling** → Assumes non-null when optional (e.g., src.bg)
4. **Layer Ordering** → Z-index wrong, wrong layer on top
5. **Dirty Tracking** → Changes not marked dirty, diff misses them
6. **Buffer Initialization** → Previous buffer not sentinel, false equals

**Fastest Debug Paths by Symptom**:

| Symptom | Likely Location | Debug Strategy |
|---------|----------------|----------------|
| No text rendered | Compositor blending | Check `blendCell()` for lost chars |
| Wrong colors | Layer setup or blending | Check layer fg/bg, blend formula |
| Missing highlights | Dirty tracking or diff | Check dirty flags, diff detection |
| Partial render | Layer boundaries | Check width/height bounds |
| Flicker | Double buffering | Check swap timing |
| Crash on input | JSI bridge validation | Check NaN/Infinity/bounds |

**Debug Log Templates**:

```zig
// For data transformations
debug_log.log("TRANSFORM[{s}]: before={} after={}", .{component, before, after});

// For layer processing
debug_log.log("LAYER[{s}]: enabled={} dirty={} cells={}", .{name, enabled, dirty, count});

// For bug investigation
debug_log.log("🐛 BUG CHECK[{s}]: condition={} value={}", .{location, condition, value});
```

**When Stuck** (Escalation):
1. Re-read user report - did you misunderstand?
2. Simplify test case even more
3. Add debug logs at EVERY transformation point
4. Check git history - was this working before?
5. Compare with reference implementation (Neovim, Helix)
6. Ask user for more details with specific questions

**Success Metrics**:
- Fix in 1-2 iterations (not 5-10)
- Root cause identified (not guessed)
- Verification complete (not "try this and let me know")

### Future Debug Protocol Enhancements

Based on cursorline bug investigation, implement these commands:

**Priority 1** (Critical for Rendering Bugs):
```json
{"cmd": "get_layer", "args": {"name": "cursor", "row": 5}}
{"cmd": "get_compositor_output", "args": {"row": 5}}
{"cmd": "get_diff_output", "args": {"row": 5}}
```

**Priority 2** (Performance & Optimization):
```json
{"cmd": "get_layer_stats"}  // Blend counts, skip counts
{"cmd": "get_render_stats"}  // Cells rendered, ANSI codes sent
{"cmd": "profile_frame"}  // Breakdown by stage
```

**Priority 3** (Advanced Debugging):
```json
{"cmd": "trace_cell", "args": {"row": 5, "col": 10}}  // Track cell through pipeline
{"cmd": "validate_state"}  // Consistency checks
{"cmd": "dump_all_layers"}  // Full layer export for analysis
```

**Why These Matter**: The cursorline bug took multiple iterations because we lacked visibility into intermediate states (layer→compositor→diff). With structured layer inspection, Claude can pinpoint bugs in ONE iteration by checking each stage systematically.

## Reference Codebases

Three local forks provide reference implementations:

- `../neovim` - Maintain compatibility with Neovim APIs and plugin ecosystem
- `../helix` - High-quality Vim/Neovim fork for design patterns and implementation reference
- `../ghostty` - High-quality Zig terminal project for Zig best practices and terminal handling

## Architecture

### Current Implementation (Phase 1+2)

```
openvim/
├── src/
│   ├── main.zig              # Entry point, event loop
│   ├── buffer/
│   │   └── buffer.zig        # Text storage (ArrayList-based)
│   ├── display/
│   │   └── display.zig       # Terminal rendering (ANSI codes)
│   ├── mode/
│   │   └── mode.zig          # Mode state machine (N/I/V/C)
│   ├── movement/
│   │   └── movement.zig      # Vim movement primitives
│   └── jsi/                  # Hermes C++ wrapper (for Phase 4)
│       ├── hermes_c_api.h
│       ├── hermes_c_api.cpp
│       └── hermes.zig
├── examples/                  # Hermes+JSI demos
│   ├── test_zig_hermes.zig   # Zig runs JavaScript
│   └── test_jsi_bridge.zig   # JavaScript calls Zig
├── vendor/                    # Git submodules
│   ├── hermes/               # Hermes JS engine (v0.12.0)
│   ├── ghostty/              # Reference for terminal code
│   └── neovim/               # Reference for C libraries
├── build.zig                 # Zig build system (main editor)
├── Makefile.hermes          # Hermes+JSI build (C++ hybrid)
└── CLAUDE.md                # This file
```

### Three-Layer Design (Full Vision)

1. **Editor Core (Zig)** - Buffer management, rendering, input handling
2. **JSI Bridge (C++)** - Zero-copy interface between Zig and JavaScript
3. **Plugin Layer (JavaScript)** - Extensions, LSP, configurations via Hermes

### JSI Bridge (Zero-Copy Communication)

JSI enables direct function calls between Zig and JavaScript without serialization:

- **Zig → JavaScript**: Load `.hbc` bytecode, call `hermes_evaluate_bytecode()`
- **JavaScript → Zig**: Register Zig functions via `hermes_register_host_function()`, JavaScript calls them directly
- **Performance**: ~13x faster than traditional FFI due to zero-copy design

### Hybrid Build System

**Critical**: Due to a Zig linker bug (crashes parsing C++ exception handling metadata in `__eh_frame`), the project uses a hybrid build:

1. Zig compiles to `.o` object files (`zig build-obj`)
2. `clang++` performs final linking with Hermes libraries

This is **not a workaround** - it's the proper solution given current Zig limitations. The integration itself is correct and works perfectly.

## Build Commands

### Main Editor (Phase 1+2)

```bash
# Build OpenVim
zig build

# Run with file
./zig-out/bin/openvim <filename>

# Example
./zig-out/bin/openvim README.md

# Run tests
zig build test

# Format code (use Zig convention: 4 spaces)
zig fmt src/
```

### Hermes+JSI Demos (Separate Build)

```bash
# Build Hermes integration demos
make -f Makefile.hermes all

# Run Zig→JavaScript demo
make -f Makefile.hermes test-zig

# Run JavaScript→Zig demo
make -f Makefile.hermes test-jsi

# Clean
make -f Makefile.hermes clean
```

### Working with Bytecode

```bash
# Compile JavaScript to Hermes bytecode
./hermesc -emit-binary -out output.hbc input.js

# The .hbc file can then be executed by Zig programs
```

## Key Files

### Integration Layer

- `src/jsi/hermes_c_api.h` - C API header with all function signatures
- `src/jsi/hermes_c_api.cpp` - C++ implementation wrapping Hermes JSI
- `Makefile.hermes` - Hybrid build system (Zig→.o, clang++→exe)

### Core Modules

- `src/main.zig` - Entry point, event loop, input handling
- `src/buffer/buffer.zig` - Text storage with line indexing and cursor management
- `src/display/display.zig` - Terminal rendering with ANSI escape codes
- `src/mode/mode.zig` - Mode state machine (Normal/Insert/Visual/Command)
- `src/movement/movement.zig` - Vim movement primitives

### Hermes+JSI Demos

- `examples/test_zig_hermes.zig` - Shows Zig loading and executing JavaScript bytecode
- `examples/test_jsi_bridge.zig` - Shows JavaScript calling Zig functions with zero-copy

### Configuration

- `build.zig` - Zig build configuration (contains note about linker bug at lines 68-78)
- `.gitignore` - Excludes build artifacts and `vendor/hermes/build/`

## Important Technical Details

### Hermes Submodule Management

```bash
# Initialize submodule (first time)
git submodule update --init

# Update to latest commit
git submodule update --remote

# Current pinned commit: ef620c2 (Hermes 0.12.0)
```

### Runtime Library Path (macOS)

Hermes requires dynamic libraries at runtime. Set `DYLD_LIBRARY_PATH`:

```bash
DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi ./executable
```

The Makefile handles this automatically for test targets.

### Name Collisions

All C types use `OV` prefix to avoid collisions with Hermes C++ types:
- `OVHermesRuntime` (not `HermesRuntime`)
- `OVHermesValue` (not `HermesValue`)
- `OVHermesHostFunction` callback type

### Zig Formatting

Follow Zig convention: 4 spaces for indentation. Run `zig fmt src/` before committing.

## Navigation Commands (Phase 1+2)

### Character Movement
- `h` - Move left
- `j` - Move down
- `k` - Move up
- `l` - Move right

### Line Movement
- `0` - Move to start of line
- `$` - Move to end of line
- `^` - Move to first non-blank character

### Word Movement
- `w` - Move forward to next word start
- `b` - Move backward to previous word start
- `e` - Move forward to word end

### File Movement
- `gg` - Move to file start (first line, column 0)
- `G` - Move to file end (last line)
- `Ctrl+D` - Scroll half page down
- `Ctrl+U` - Scroll half page up

### Mode Switching
- `i` - Enter insert mode before cursor
- `a` - Enter insert mode after cursor
- `I` - Enter insert mode at line start
- `A` - Enter insert mode at line end
- `o` - Open new line below (TODO: Phase 3)
- `O` - Open new line above (TODO: Phase 3)
- `ESC` - Return to normal mode from any mode
- `q` - Quit editor (normal mode only)

## Development Workflow

### Adding New Host Functions (Zig functions callable from JS)

1. Define Zig function with C calling convention:
```zig
export fn my_function(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.C) ?*c.OVHermesValue {
    // Implementation
}
```

2. Register in runtime:
```zig
c.hermes_register_host_function(runtime, "myFunction", my_function, null);
```

3. JavaScript can now call: `myFunction(arg1, arg2)`

### Testing Changes

Always test both directions:
- Zig→JS: Can Zig execute JavaScript correctly?
- JS→Zig: Can JavaScript call Zig functions correctly?

Use `make -f Makefile.hermes test-zig` as smoke test.

### Building Hermes from Source

If `vendor/hermes/build/` doesn't exist:

```bash
cd vendor/hermes
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel \
         -DHERMES_ENABLE_DEBUGGER=OFF \
         -DHERMES_BUILD_APPLE_FRAMEWORK=OFF \
         -GNinja
ninja hermes hermesc
```

This builds ~40 libraries (~287MB). Build artifacts are gitignored.

## Common Issues

### Terminal Not Restored After Crash

If OpenVim crashes and terminal is stuck in raw mode:
```bash
reset
# or
stty sane
```

### Build Fails with "posix not found"

You're using an older Zig version. OpenVim requires Zig 0.13+ where `std.os.*` moved to `std.posix.*`.

### Cursor Movement Not Working

Check that terminal supports ANSI escape codes. Most modern terminals do, but some minimal terminals may not.

### Submodule Not Initialized

```bash
git submodule update --init
```

### Hermes+JSI: "Library not loaded: @rpath/libjsi.dylib"

When running Hermes demos, set `DYLD_LIBRARY_PATH`:
```bash
DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi
```

The Makefile handles this automatically.

## Project Goals & Roadmap

### Vision

A Neovim-compatible editor where:
- Core editor (buffers, windows, rendering) written in Zig
- Plugins and configuration written in JavaScript/TypeScript
- Zero-copy JSI bridge for high performance
- Hermes bytecode for fast startup and small memory footprint

### Development Phases

**Phase 1+2: Text Display & Navigation** ✅ COMPLETE
- Buffer management (ArrayList-based)
- Terminal rendering (ANSI codes)
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert)
- Status line

**Phase 3: Text Editing** (Next - 4-6 weeks)
- Insert mode operations (character insertion/deletion)
- Delete operators (x, dd, dw, etc.)
- Change operators (c, cc, cw, etc.)
- Yank/paste (y, yy, p, P)
- Visual mode (character, line, block selection)
- Undo/redo tree
- Transaction system (change tracking)
- Basic registers

**Phase 4: Plugin System** (6-8 weeks)
- Integrate Hermes+JSI into main binary
- Plugin loader (bytecode execution)
- Expose editor API to JavaScript
- Event hooks (buffer change, mode change, etc.)
- Configuration file (~/.config/openvim/init.js)
- Plugin API documentation

**Phase 5: Advanced Features** (8-12 weeks)
- Tree-sitter syntax highlighting
- LSP integration (via plugins)
- Search and replace (/,  ?, :s)
- Command mode (: commands)
- Split windows (horizontal/vertical)
- Tab pages
- Macros (q, @)

**Phase 6: Performance & Polish** (Ongoing)
- Rope data structure (replace ArrayList)
- Incremental rendering
- Large file handling (>100MB)
- Memory optimization
- Benchmark suite

**Phase 7: Neovim Compatibility** (Ongoing)
- Ex commands (:w, :q, :e, etc.)
- Options (:set number, etc.)
- Neovim API compatibility layer
- Remote plugin support
- Vimscript subset (if needed)

## Documentation Maintenance (Critical Practice!)

**Documentation is not a one-time task** - it's an ongoing practice that must be maintained alongside code.

### When to Update Docs

**Code Changes**:
- Adding a new feature? → Update relevant API docs + guides
- Changing architecture? → Update architecture docs + CLAUDE.md
- Fixing a bug? → Add to troubleshooting if user-facing
- Implementing a roadmap item? → Update phase status in roadmap

**New Insights**:
- Discovered a better pattern? → Document in architecture/
- Solved a tricky problem? → Add to development/
- Made an important decision? → Document rationale in architecture/design-decisions.md

**User Feedback**:
- "Where do I find X?" → Check if navigation is clear, add links
- "This is confusing" → Clarify in relevant doc
- "Does OpenVim support Y?" → Update feature status in README.md

### Documentation Review Checklist

Before completing any major work:

- [ ] All new APIs documented in `docs/api/`
- [ ] Architecture changes reflected in `docs/architecture/`
- [ ] Implementation status updated in `docs/roadmap/`
- [ ] User-facing changes in `docs/guides/`
- [ ] Entry points (`docs/README.md`, root `README.md`) updated
- [ ] Links tested (no broken links)
- [ ] Phase status updated in CLAUDE.md

### Signs of Good Documentation Health

✅ **Healthy**:
- New contributors can get started in < 30 minutes
- API questions answered by docs, not verbal explanations
- Design decisions have written rationale
- Easy to find information (< 3 clicks from main entry point)
- Cross-references between related docs

❌ **Needs Attention**:
- Answering same questions repeatedly
- Contributors confused about structure
- Outdated information contradicts reality
- Broken or missing links
- New docs not linked from main index

### Documentation as Competitive Advantage

Good documentation is a **force multiplier**:
- Makes onboarding instant
- Reduces maintainer burden
- Attracts contributors
- Looks professional
- Preserves institutional knowledge
- Enables autonomous work

**Invest in docs early** - it compounds. Poor docs create eternal technical debt.

### Quick Wins

**Daily**:
- Fix broken links when you see them
- Add cross-references when relevant
- Update status markers (✅/🚧/📅)

**Weekly**:
- Review recent changes - are they documented?
- Check main entry points still accurate
- Look for orphaned docs

**Monthly**:
- Full documentation review
- Update roadmap progress
- Refresh examples and code samples
- Archive or update outdated content

**Remember**: A well-documented project is a joy to work on. A poorly documented project is a burden.
