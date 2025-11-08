# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Table of Contents

**Critical Workflows** (read these first):
- [LLM-Driven Debugging Workflow](#llm-driven-debugging-workflow-critical-study-case) - **MOST IMPORTANT**: Proven systematic approach for bug fixing
- [Debug Protocol & Verification System](#debug-protocol--verification-system-critical) - LLM-optimized testing framework
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

### Architecture Overview

```
OpenVim (--debug-protocol) ←→ ovdb (OpenVim Debugger) ←→ Claude (LLM)
     ↓ JSON State                    ↓ Structured                ↓ Parse
   Expose internals            Query/Assert/Verify        Understand & Iterate
```

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

**2. ovdb - OpenVim Debugger** (`tools/ovdb/`)
- Zig CLI tool for debugging OpenVim
- Interactive REPL mode
- Script execution (.ovdb files)
- Assertion framework
- LLM-friendly output (JSON + human-readable)

**3. Debug Protocol** (JSON over Unix socket/stdin)
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
# 1. Claude implements visual mode feature

# 2. Claude writes test script (test_visual.ovdb)
load_file /tmp/test.txt
execute_keys viw
assert_visual_mode char
assert_cursor 0 3
execute_keys y
assert_register " "Hel"

# 3. Claude runs verification
$ ./ovdb run test_visual.ovdb --format=json

# 4. Claude parses JSON result
{
  "status": "pass",
  "passed": 5,
  "failed": 0,
  "tests": [
    {"name": "execute_keys", "status": "pass"},
    {"name": "assert_visual_mode", "status": "pass"},
    ...
  ]
}

# 5. If failure, Claude gets exact error with diff:
{
  "status": "fail",
  "tests": [{
    "name": "assert_register",
    "expected": "Hel",
    "actual": "Hello",
    "diff": "+ lo"  // Clear, actionable
  }]
}

# 6. Claude fixes and re-runs (fast iteration!)
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

**Phase 3 (Current)**:
- ✅ Debug protocol designed ([docs/development/debug-protocol.md](docs/development/debug-protocol.md))
- 🚧 Implementing `src/debug/protocol.zig` (Command/Response types)
- 🚧 Implementing `src/debug/state.zig` (EditorState serialization)
- 🚧 Implementing `tools/ovdb/` (Debugger CLI)
- 📅 Integration tests using ovdb (.ovdb scripts)

**Benefits Realized**:
- Claude can verify implementations in seconds (not minutes)
- Clear, structured failure messages (no ambiguity)
- Deep introspection (understand editor state fully)
- Fast iteration (no process spawning overhead)
- Deterministic testing (reproducible results)

### Documentation

- **Protocol Spec**: [docs/development/debug-protocol.md](docs/development/debug-protocol.md)
- **Usage Guide**: [docs/development/ovdb-usage.md](docs/development/ovdb-usage.md) (TODO)
- **Test Scripts**: `tests/*.ovdb` (integration tests)

### When to Use ovdb

**During Development**:
- Implementing new feature → Write .ovdb test first (TDD)
- Feature complete → Run ovdb to verify
- Bug found → Write .ovdb to reproduce → Fix → Verify

**For Claude**:
- After every feature implementation → Run verification
- Before committing → Full regression suite
- On failure → Parse JSON, understand exact issue, fix

**Example Usage**:
```bash
# Interactive debugging
$ ./ovdb connect /tmp/openvim-debug.sock
ovdb> get_state
ovdb> execute_keys viw
ovdb> get_visual
ovdb> quit

# Script execution (for Claude)
$ ./ovdb run test_visual.ovdb --format=json > result.json
$ cat result.json  # Claude parses this
```

### Critical Principle

**"Natural Like Home" for LLM**:
- JSON everywhere (easy parsing)
- Structured data (no string parsing)
- Clear pass/fail (boolean logic)
- Exact diffs (actionable fixes)
- Fast feedback (<100ms typical)
- Deterministic (reproducible)

This debug system is **optimized for LLM cognition**, not human debugging. It provides the structured, deterministic feedback that LLMs need for efficient development iteration.

## LLM-Driven Debugging Workflow (CRITICAL STUDY CASE!)

**IMPORTANT**: This workflow was proven highly effective during the Smear Cursor crash fix (2025-11-08). It demonstrates the power of using Debug Backend for iterative bug fixing.

### The Proven Workflow

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
