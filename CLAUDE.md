# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Quick Navigation

**Critical Workflows**:
- [Debug Protocol](#debug-protocol--verification-system) - LLM-optimized JSON testing (see [docs/development/debug-protocol.md](docs/development/debug-protocol.md))
- [Logging Architecture](#logging-architecture) - Use `editor.logger`, not `std.debug.print`
- [Debugging Principles](#debugging-principles) - 7 proven principles for efficient bug fixing
- [Build Commands](#build-commands) - How to build and run

**Project Info**: [Overview](#project-overview) · [Architecture](#architecture) · [Key Files](#key-files) · [Navigation](#navigation-commands) · [Roadmap](#roadmap)

**Documentation**: All docs in `docs/` - see [docs/README.md](docs/README.md) for navigation. Follow structure: add to correct category, update category README, link from main index.

---

## Project Overview

**OpenVim** - Neovim-compatible editor in Zig with Hermes JavaScript engine for plugins via JSI (zero-copy bidirectional communication).

**Status**: Phase 1+2 Complete ✅
- Text display and file loading
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert/Visual)
- Terminal rendering (ANSI codes)
- Hermes+JSI demos working (not yet in main editor)

**Reference Codebases**: `../neovim` (API compatibility), `../helix` (design patterns), `../ghostty` (Zig best practices)

## Debug Protocol & Verification System

**Critical**: OpenVim uses Zig-based debug protocol for LLM-driven development with structured JSON communication.

### Background Mode (REQUIRED for Multi-Command Debugging)

**❌ WRONG** (one-shot mode wastes 67% on startup):
```bash
echo '{"cmd":"get_state","id":"1"}' | ./zig-out/bin/openvim --debug-protocol  # 195ms (130ms startup!)
```

**✅ CORRECT** (background mode - 10x faster):
```bash
./zig-out/bin/openvim --debug-protocol &
OPENVIM_PID=$!
echo '{"cmd":"get_state","id":"1"}'        # 65ms (no startup overhead)
echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'  # 65ms
kill $OPENVIM_PID
```

**Rule**: ALWAYS use background mode for 2+ commands. Startup cost amortized → 2.5x faster for 10 commands.

### Core Features

**Architecture**: JSON-RPC over stdin/stdout (MCP-style) → Deep introspection, fast iteration, deterministic results

**Key Commands**:
- `get_state` - Full editor snapshot (mode, cursor, buffer, visual, registers)
- `execute_keys "viw"` - Simulate keystrokes
- `get_layers` - Layer state inspection
- `get_logs {"level":"info","max_bytes":4096}` - Query logs (size-limited for LLM context)

**Status**: Background mode ready ✅, JSON parser robust ✅, 8 layers tracked ✅. See [docs/development/debug-protocol.md](docs/development/debug-protocol.md) for complete spec.

### When and How to Use Debug Protocol

**Decision Checklist** (use debug protocol when):
- [ ] Debugging crashes or panics → ALWAYS use to get exact line numbers
- [ ] Investigating rendering bugs → Use to inspect layer state at each stage
- [ ] Verifying multi-step operations → Use to check state after each step
- [ ] Testing new features → Use to verify correctness systematically
- [ ] User reports "X doesn't work" → Use to reproduce and inspect state

**Workflow Template for Bugs**:
```bash
# 1. Start in background mode (CRITICAL for multi-command debugging)
./zig-out/bin/openvim --debug-protocol &
PID=$!

# 2. Load test case
echo '{"cmd":"load_file","args":{"path":"/tmp/test.txt"},"id":"1"}'

# 3. Execute operation that triggers bug
echo '{"cmd":"execute_keys","args":{"keys":"viw"},"id":"2"}'

# 4. Inspect state at each pipeline stage
echo '{"cmd":"get_state","id":"3"}'        # Overall state
echo '{"cmd":"get_layers","id":"4"}'       # Layer composition
echo '{"cmd":"get_logs","args":{"level":"debug","max_bytes":4096},"id":"5"}'  # Debug logs

# 5. Analyze results, implement fix, repeat
kill $PID
```

**Common Debugging Scenarios**:

| Symptom | Debug Protocol Workflow |
|---------|------------------------|
| **Crash/Panic** | Run with `--debug-protocol` to get stack trace with exact line numbers |
| **No text rendered** | `get_layers` → check buffer layer has text → `get_logs` → check compositor blending |
| **Wrong colors** | `get_state` → inspect fg/bg values → `get_layers` → check layer colors |
| **Command doesn't work** | `execute_keys` → `get_state` → verify mode/cursor changed as expected |
| **Performance issue** | Check `duration_ns` in responses → identify slow commands |

**Key Principle**: For ANY bug investigation with 2+ debug commands, ALWAYS use background mode (not one-shot).

## Logging Architecture

**Core→Backend design**: ALL logging through `editor.logger` (or `editor_ctx.logger` in headless).

**Principle**: Single Source of Truth
- ✅ `editor.logger.debug("Cursor at row={} col={}", .{row, col})`
- ✅ `editor.logger.info("LAYER[cursor]: dirty={} cells={}", .{dirty, count})`
- ✅ Log transformations: `"Blend: {u}+{u}→{u}", .{src.char, dst.char, result.char}`
- ❌ NO `std.debug.print()` (bypasses logging system)
- ❌ NO unstructured output

**Backends**:
- Terminal mode (`--debug`): Chrome DevTools Console via CDP
- Headless mode (`--debug-protocol`): `get_logs` command with size limits
- Ring buffer (1000 entries, FIFO)

**When to Log**: State transitions, user actions, errors, transformations. AVOID hot loops, trivial getters.

## Debugging Principles

**7 Proven Principles** (from cursorline bug fix):

1. **Simplest Test Case** - Single file, minimal content (not full app)
2. **Trust User Reports** - Don't over-theorize, believe symptom descriptions
3. **Check Data Flow** - Trace through pipeline: Buffer→Compositor→Diff→Terminal
4. **Type Conversions** - Red flag for data loss (early returns, optional handling)
5. **Log Transformations** - Show before→after, not just final state
6. **Targeted Tests** - Verify fix + edge cases + no side effects
7. **Follow Breadcrumbs** - User reports contain critical clues

**Mandatory Workflow for Crashes**:
```
1. REPRODUCE with debug protocol (get exact stack trace)
2. READ error output (don't guess - read the panic message)
3. ZONE scope (narrow to exact function/line, not "somewhere in X")
4. IMPLEMENT fix (single targeted fix, not shotgun approach)
5. VERIFY with debug protocol (test passes = bug fixed)
6. ITERATE if needed (but should fix in 1-2 iterations max)
```

**Rendering Bug Investigation Workflow**:
```bash
# Use debug protocol to inspect each pipeline stage
./zig-out/bin/openvim --debug-protocol &

# 1. Verify source data (Buffer layer)
echo '{"cmd":"get_state","id":"1"}'  # Check buffer content

# 2. Check layer composition (Compositor)
echo '{"cmd":"get_layers","id":"2"}'  # Are layers enabled/dirty?

# 3. Query debug logs (transformations)
echo '{"cmd":"get_logs","args":{"max_bytes":4096},"id":"3"}'  # Check blend/diff logs

# 4. Identify WHERE data is lost (Buffer→Compositor→Diff→Terminal)
# Bug is in the stage where data exists before but not after
```

**Common Bug Patterns** (recognize and fix fast):
- Early return optimization → Skips validation (check opacity >= 1.0 returns)
- Type conversion → Loses data (@intFromFloat with NaN/Infinity)
- Null handling → Assumes non-null when optional (check .? usage)
- Dirty tracking → Changes not marked, diff misses them

**Add Debug Logs When Investigating** (make data flow visible):
```zig
// Log transformations (CRITICAL for tracing bugs)
editor.logger.debug("TRANSFORM[{s}]: before={} after={}", .{component, before, after});
editor.logger.debug("LAYER[{s}]: enabled={} dirty={} cells={}", .{name, enabled, dirty, count});
editor.logger.debug("BLEND: src={u} dst={u} result={u}", .{src.char, dst.char, result.char});
```

**Success Metrics**: Fix in 1-2 iterations (not 5-10), root cause identified (not guessed), verified with debug protocol.

## Architecture

### Current (Phase 1+2)

```
openvim/
├── src/
│   ├── main.zig              # Entry point, event loop
│   ├── buffer/buffer.zig     # Text storage (ArrayList-based)
│   ├── display/display.zig   # Terminal rendering (ANSI codes)
│   ├── mode/mode.zig         # Mode state machine
│   ├── movement/movement.zig # Vim movement primitives
│   ├── core/log.zig          # Unified logging (ring buffer)
│   ├── debug/                # Debug protocol (JSON-RPC)
│   │   ├── protocol.zig      # Command/Response types
│   │   ├── server.zig        # Debug server
│   │   └── state.zig         # EditorState serialization
│   └── jsi/                  # Hermes C++ wrapper (Phase 4)
├── examples/                 # Hermes+JSI demos
├── vendor/                   # Git submodules (hermes, ghostty, neovim)
└── build.zig                 # Zig build system
```

### Three-Layer Vision

1. **Editor Core (Zig)** - Buffer management, rendering, input handling
2. **JSI Bridge (C++)** - Zero-copy interface between Zig and JavaScript (~13x faster than FFI)
3. **Plugin Layer (JavaScript)** - Extensions, LSP, configs via Hermes bytecode

### Hybrid Build System

**Critical**: Zig linker bug (C++ exception metadata in `__eh_frame`) requires hybrid build:
1. Zig compiles to `.o` object files (`zig build-obj`)
2. `clang++` performs final linking with Hermes libraries

This is the **proper solution**, not a workaround.

## Build Commands

### Main Editor

```bash
zig build                          # Build
./zig-out/bin/openvim <filename>   # Run
zig build test                     # Test
zig fmt src/                       # Format (4 spaces)
```

### Hermes+JSI Demos

```bash
make -f Makefile.hermes all      # Build demos
make -f Makefile.hermes test-zig # Run Zig→JS demo
make -f Makefile.hermes test-jsi # Run JS→Zig demo
```

### Bytecode

```bash
./hermesc -emit-binary -out output.hbc input.js  # Compile to .hbc
```

## Key Files

**Integration**: `src/jsi/hermes_c_api.{h,cpp}`, `Makefile.hermes`
**Core**: `src/{main,buffer,display,mode,movement}.zig`
**Debug**: `src/debug/{protocol,server,state}.zig`, `src/core/log.zig`
**Demos**: `examples/test_{zig_hermes,jsi_bridge}.zig`
**Config**: `build.zig` (linker bug note at lines 68-78)

## Navigation Commands

**Character**: `h/j/k/l` · **Line**: `0/$^` · **Word**: `w/b/e`
**File**: `gg/G/Ctrl+D/Ctrl+U` · **Mode**: `i/a/I/A/ESC/q`

See Phase 1+2 complete list in original docs.

## Development Workflow

### Adding Host Functions (Zig callable from JS)

```zig
// 1. Define with C calling convention
export fn my_function(runtime: ?*c.OVHermesRuntime, context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue, arg_count: usize) callconv(.C) ?*c.OVHermesValue {
    // Implementation
}

// 2. Register
c.hermes_register_host_function(runtime, "myFunction", my_function, null);

// 3. JavaScript calls: myFunction(arg1, arg2)
```

### Testing Changes

Test both directions: Zig→JS and JS→Zig. Use `make -f Makefile.hermes test-zig` as smoke test.

### Building Hermes

If `vendor/hermes/build/` missing:
```bash
cd vendor/hermes && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -DHERMES_ENABLE_DEBUGGER=OFF -GNinja
ninja hermes hermesc  # ~287MB, gitignored
```

## Common Issues

**Terminal stuck after crash**: `reset` or `stty sane`
**"posix not found"**: Upgrade to Zig 0.13+ (`std.os.*` → `std.posix.*`)
**Submodule missing**: `git submodule update --init`
**Hermes dylib error**: Set `DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi` (Makefile handles this)

## Important Technical Details

**Hermes Submodule**: Pinned to ef620c2 (v0.12.0), use `git submodule update --init`
**Name Collisions**: All C types use `OV` prefix (`OVHermesRuntime`, `OVHermesValue`)
**Zig Formatting**: 4 spaces for indentation (`zig fmt src/`)
**Runtime Path (macOS)**: `DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi`

## Roadmap

**Phase 1+2** ✅ Text Display & Navigation (COMPLETE)
**Phase 3** 🚧 Text Editing (Next: insert/delete/change/yank/paste, visual mode, undo/redo)
**Phase 4** 📅 Plugin System (Hermes+JSI integration, plugin loader, event hooks, config file)
**Phase 5** 📅 Advanced Features (Tree-sitter, LSP, search/replace, splits, tabs, macros)
**Phase 6** 📅 Performance (Rope data structure, incremental rendering, large files)
**Phase 7** 📅 Neovim Compatibility (Ex commands, options, API layer)

See [docs/roadmap/](docs/roadmap/) for detailed implementation plans.

## Documentation Maintenance

**Rule**: Documentation is first-class - update alongside code.

**When to Update**:
- New feature → API docs + guides
- Architecture change → Architecture docs + CLAUDE.md
- Bug fix → Troubleshooting (if user-facing)
- Roadmap item → Phase status

**Checklist Before Completion**:
- [ ] APIs documented in `docs/api/`
- [ ] Architecture changes in `docs/architecture/`
- [ ] Status updated in `docs/roadmap/`
- [ ] Entry points updated (`docs/README.md`)
- [ ] Links tested

**Quick Wins**: Fix broken links daily, add cross-references, update status markers (✅/🚧/📅).

**Remember**: Well-documented project = joy to work on. Poor docs = eternal debt.

---

**For complete details**: See [docs/README.md](docs/README.md) for full documentation navigation.
