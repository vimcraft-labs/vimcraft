# CLAUDE.md

Guidance for Claude Code when working with the Vimcraft editor codebase.

## ⚠️ SACRED FILES - DO NOT MODIFY WITHOUT EXPLICIT APPROVAL

| File | Why Sacred | Modification Risk | Key Functions |
|------|------------|-------------------|---------------|
| `build.zig` | Hybrid build system with C++ linking | Breaks Hermes linking, C++ exceptions | Lines 289-299: enry setup |
| `src/system/jsi/hermes_c_api.cpp` | C++ JSI bridge, exception handling | Crashes editor, breaks all JS plugins | Lines 45-89: HostObject impl |
| `src/system/jsi/hermes_c_api.h` | C API declarations | ABI breaks, undefined symbols | Lines 30-75: Function signatures |
| `src/main.zig:690-743` | Main event loop with throttling | Freezes editor, loses input | Event batching logic |
| `vendor/hermes/` | Prebuilt Hermes binaries | 287MB rebuild, version conflicts | DO NOT TOUCH |

## ⚠️ CRITICAL: Performance Safeguards

newly-added!

**Benchmarks act as safeguards on critical paths. If thresholds are exceeded, builds fail.**

Incident: O(n) API call in render loop caused 10x slowdown. Benchmarks prevent regressions.

| Critical Path | Threshold | Tests |
|---------------|-----------|-------|
| Frame render | <8ms single, <5ms avg | 3 tests |
| Navigation (j/k/h/l) | <3ms single, <150ms for 50 | 9 tests |
| O(n) scaling | ratio ≤15x (detects O(n²)) | 3 tests |
| Mode switching | <3ms single, <200ms for 100 | 3 tests |
| Stress (mixed, diagonal, word) | <400ms for 100 ops | 4 tests |
| PTY overhead | <30% | 1 test |

**Run**: `vimc test tests/e2e/perf-critical` — 23 tests, real PTY + Hermes + full stack.

## Overview

| Component | Status | Description |
|-----------|--------|-------------|
| **Project** | Phase 4 🚧 | Neovim-compatible editor in Zig + Hermes JS |
| **Architecture** | 3-layer | Editor Core (Zig) ↔ JSI Bridge (C++) ↔ Plugins (JS) |
| **Performance** | 3-5x faster | Zero-copy JSI HostObjects vs traditional FFI |
| **Testing** | 2-level | Unit tests (Zig) + E2E tests (TypeScript) |

## Development Philosophy

**Correctness over speed. Root causes over shortcuts. Proper engineering over quick fixes.**

This is a personal project with no commercial deadlines. We have the luxury of time to do things right:

| Principle | In Practice |
|-----------|-------------|
| **Find the root cause** | Never mask symptoms with workarounds. If rendering flickers, understand WHY before fixing. |
| **No band-aid fixes** | A fix that "works" but bypasses proper handling is not acceptable. |
| **Take the time needed** | Spend a week understanding a system rather than an hour patching around it. |
| **Correct > Working** | Code that works incorrectly will cause harder bugs later. Get it right the first time. |

When facing a problem: investigate fully, understand the underlying system, then implement the proper solution. If you find yourself thinking "this is a hack but it works" - stop and reconsider.

## Quick Navigation

| Domain | CLAUDE.md Location | Primary Purpose |
|--------|-------------------|-----------------|
| Editor Core | [`src/editor/CLAUDE.md`](src/editor/CLAUDE.md) | Buffer, registers, text ops |
| Terminal | [`src/backends/terminal/CLAUDE.md`](src/backends/terminal/CLAUDE.md) | Rendering, ANSI codes |
| JSI System | [`src/system/jsi/CLAUDE.md`](src/system/jsi/CLAUDE.md) | Hermes, HostObject APIs |
| E2E Testing | [`tests/e2e/CLAUDE.md`](tests/e2e/CLAUDE.md) | Test framework, PTY capture |
| Documentation | [`docs/CLAUDE.md`](docs/CLAUDE.md) | Doc structure, maintenance |

## Decision Tree: Where to Make Changes

```
Adding new Vim command?
├── Pure movement → src/movement/movement.zig:127
├── Buffer modification → src/editor/buffer/edit.zig:45
├── Visual mode op → src/editor/buffer/visual_ops.zig:89
└── Needs JS exposure → src/system/jsi/motion_api.zig:234

Adding new vim.* API?
├── Motion primitive → src/system/jsi/motion_api.zig:234
├── Option (vim.opt) → src/system/jsi/config_api.zig:567
├── Window management → src/system/jsi/api_window.zig:123
└── Buffer access → src/system/jsi/api_buffer.zig:89

Fixing rendering bug?
├── Cursor flicker → src/backends/terminal/display/display.zig:478
├── Color bleeding → src/backends/terminal/display/output_renderer.zig:84
├── Layer blending → src/backends/terminal/display/compositor.zig:341
└── Window borders → src/backends/terminal/display/window_renderer.zig:67

Writing tests?
├── Pure logic → tests/unit/*.zig (zig build test)
├── User workflow → tests/e2e/*/e2e.ts (vimc test)
├── Terminal output → tests/e2e/rendering/ (vim.e2e.pty.*)
└── JS API behavior → tests/e2e/api/*/ (vim.e2e.assert.*)
```

## Key Entry Points

| Purpose | File:Line | Description |
|---------|-----------|-------------|
| **Main Loop** | `src/main.zig:690` | Event loop with render throttling |
| **Editor Core** | `src/editor/editor.zig:127` | Command coordinator |
| **Buffer Ops** | `src/editor/buffer/buffer.zig:234` | Text modifications |
| **Rendering** | `src/backends/terminal/display/display.zig:426` | Render pipeline |
| **JSI Bridge** | `src/system/jsi/jsi_api.zig:89` | API registration |
| **Compositor** | `src/backends/terminal/display/compositor.zig:341` | Layer blending |
| **Movement** | `src/movement/movement.zig:127` | Vim motions |

## Common Tasks

| Task | Command/Location | Notes |
|------|-----------------|-------|
| Build editor | `zig build` | Hybrid build via clang++ |
| Run tests | `zig build test` | Unit tests only (~100ms) |
| E2E test | `vimc test tests/e2e/<dir>` | Full stack (~100ms/test) |
| Build Hermes demos | `make -f Makefile.hermes all` | JSI examples |
| Debug rendering | `vim.e2e.pty.*` API | Capture ANSI codes |
| Add JS API | `src/system/jsi/*_api.zig` | HostObject pattern |
| Profile blending | `compositor.zig:333` | Metrics tracked |

## Troubleshooting Matrix

| Problem | Likely Cause | Fix | Reference |
|---------|--------------|-----|-----------|
| Linking fails | Hermes not built | `cd vendor/hermes && cmake ...` | build.zig:289 |
| JS function undefined | Missing registration | Check `jsi_api.zig:89` | hermes_c_api.cpp:45 |
| Test hangs | Process not killed | Add `defer pty.kill()` | tests/e2e/CLAUDE.md |
| Cursor flickers | Redundant codes | Check `display.zig:478` | [Bug fix](docs/bugfixes/cursor-flickering-fix.md) |
| Slow rendering | No fast-path | Check `compositor.zig:341` | 95% cells hit fast-path |
| Memory leak | Missing defer | Add cleanup in buffer ops | buffer.zig:234 |
| Visual mode broken | Transaction missing | Wrap in start/endTransaction | visual_ops.zig:89 |

## Rendering Debug Tools

Tools for debugging the multi-layer rendering pipeline. Use in E2E tests.

| Tool | Purpose | Example |
|------|---------|---------|
| `vim.e2e.getLayers()` | Layer metadata (id, name, zIndex, enabled, dirty) | `const layers = vim.e2e.getLayers()` |
| `vim.e2e.getLayerCells(name)` | **All cells from a specific layer** | `vim.e2e.getLayerCells("selection")` |
| `vim.e2e.pty.getOutput()` | Raw ANSI escape codes | Capture terminal output |
| `vim.e2e.pty.getFrames()` | Frame-by-frame animation capture | Animation debugging |
| `get_render_stats` | Timing, cursor codes, compositor stats | Debug protocol |

### Layer Names

| Layer | Z-Index | Contents |
|-------|---------|----------|
| `base` | 0 | Buffer text content |
| `gutter` | 100 | Line numbers, signs |
| `cursor` | 200 | Cursorline highlight |
| `float` | 250 | Floating windows |
| `virtual_text` | 300 | Plugin overlays (extmarks) |
| `selection` | 400 | Visual mode highlight |
| `yank` | 450 | Yank flash animation |
| `search` | 500 | Search match highlights |

### Debug Example

```typescript
// Debug: "Why is selection highlight wrong at row 5?"
vim.e2e.keys("Vjjj");  // Enter visual line mode
vim.e2e.pty.render();

// Check what the selection layer contains
const cells = vim.e2e.getLayerCells("selection");
const row5 = cells.filter(c => c.row === 5);
console.log("Selection at row 5:", row5);
// → [{ row: 5, col: 4, bg: { r: 80, g: 80, b: 80 } }, ...]
```

## Critical Workflows

### Test-Driven Development (TDD) - MANDATORY

| Step | Action | Location |
|------|--------|----------|
| 1 | Write FAILING test first | `tests/e2e/*/e2e.ts` |
| 2 | Verify test fails | `vimc test <dir>` |
| 3 | Implement minimum code | Relevant `*.zig` file |
| 4 | Verify test passes | `vimc test <dir>` |
| 5 | Refactor if needed | Keep tests passing |

### Two-Level Testing

| Level | Type | Speed | Location | Run Command |
|-------|------|-------|----------|-------------|
| **Unit** | Pure Zig | ~1ms/test | `tests/unit/` | `zig build test` |
| **E2E** | Full stack + Hermes | ~100ms/test | `tests/e2e/` | `vimc test <dir>` |

### Logging Best Practices

| ✅ DO | ❌ DON'T | Why |
|-------|----------|-----|
| `editor.logger.debug()` | `std.debug.print()` | Bypasses log system |
| Log transformations | Log hot loops | Performance impact |
| Use structured format | Unstructured output | Hard to parse |
| Log state transitions | Log getters | Too verbose |

## Build Commands Reference

```bash
# Main Editor
zig build                          # Build editor
./zig-out/bin/vimcraft <file>     # Run editor
zig build test                     # Unit tests only
vimc test tests/e2e/<sandbox>     # E2E test sandbox
for d in tests/e2e/*/; do vimc test "$d"; done  # All E2E tests

# Hermes/JSI Demos
make -f Makefile.hermes all       # Build demos
make -f Makefile.hermes test-zig  # Zig→JS demo
make -f Makefile.hermes test-jsi  # JS→Zig demo

# Bytecode Compilation
./hermesc -emit-binary -out output.hbc input.js  # JS→Bytecode
```

## Performance Optimizations

| Category | Optimization | Impact | Location |
|----------|--------------|--------|----------|
| **Rendering** | Synchronized updates | 2x smoother | `display.zig:426` |
| **Rendering** | Cursor tracking | No flicker | `display.zig:478` |
| **Rendering** | Update sorting | 30-70% fewer moves | `output_renderer.zig:46` |
| **Compositor** | Fast-path blending | 1.8x speedup | `compositor.zig:341` |
| **Compositor** | Integer math | 3x vs float | `compositor.zig:380` |
| **JSI** | HostObject pattern | 3-5x vs FFI | `*_api.zig` files |
| **JSI** | O(1) dispatch | 168ns/call | `StaticStringMap` |
| **Main Loop** | Event batching | 10-100x fewer renders | `main.zig:690` |
| **Main Loop** | 60 FPS throttle | Plugin protection | `main.zig:126` |

## Architecture Highlights

| Component | Design Choice | Rationale |
|-----------|---------------|-----------|
| **Keymaps** | Helix-style immediate | JSI-friendly, no buffering |
| **Build** | Hybrid Zig+clang++ | C++ exceptions require clang++ |
| **Filetype** | go-enry (GitHub Linguist) | 697 languages, content-based |
| **Testing** | Fresh process per test | No Hermes module unloading |
| **Buffers** | Rope (tree-based) | O(log n) insert/delete, ref-counted |

## Roadmap Status

| Phase | Feature | Status | Timeline |
|-------|---------|--------|----------|
| **1-3** | Core editing | ✅ Complete | Released |
| **4** | Plugin system | ✅ Complete | Released |
| **5** | Tree-sitter, LSP | ✅ Complete | Released |
| **6** | Search | ✅ Complete | Dec 3, 2025 |
| **7** | Substitute | ✅ Complete | Dec 4, 2025 |
| **8** | Macros, Block Visual | 📅 Next | - |

## JavaScript API Pattern

```zig
// When JS modifies editor state:
self.editor.js_state_dirty = true;  // Triggers re-render
```

## Common Pitfalls

| Pitfall | Example | Fix |
|---------|---------|-----|
| Hot loops | 1000 JSI calls | Cache property values |
| Wrong convention | `.C` calling | Use `.c` (Zig 0.13+) |
| Missing visibility | `export fn` | Use `pub export fn` |
| State pollution | Reused E2E process | Fresh process per test |
| No transaction | Multi-step undo broken | Wrap in start/endTransaction |

## Reference Codebases

| Codebase | Path | Used For |
|----------|------|----------|
| Neovim | `../neovim` | API compatibility |
| Helix | `../helix` | Design patterns |
| Ghostty | `../ghostty` | Zig best practices |

## Cross-References

**Child Guides**: [Editor](src/editor/CLAUDE.md) · [Terminal](src/backends/terminal/CLAUDE.md) · [JSI](src/system/jsi/CLAUDE.md) · [E2E](tests/e2e/CLAUDE.md) · [Docs](docs/CLAUDE.md)

**Key Docs**: [Testing Architecture](docs/development/testing-architecture.md) · [JSI Design](docs/architecture/jsi-hostobject-architecture.md) · [API Reference](docs/api/vim-api-reference.md)

---

**For domain-specific details**: See child CLAUDE.md files in respective directories.
