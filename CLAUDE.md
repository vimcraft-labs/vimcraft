# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenVim is a Neovim-compatible text editor written in Zig with Hermes JavaScript engine for plugin support via JSI (JavaScript Interface). The core innovation is enabling zero-copy bidirectional communication between Zig (editor core) and JavaScript (plugins).

**Current Status**: Phase 1+2 Complete ✅
- Text display and file loading working
- Full Vim navigation (hjkl, w/b/e, gg/G, 0/$, Ctrl+D/U)
- Mode system (Normal/Insert/Visual)
- Terminal rendering with ANSI codes
- Hermes+JSI integration (demos working, not yet in main editor)

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
