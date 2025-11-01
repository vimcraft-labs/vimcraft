# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenVim is a Vim-inspired text editor written in Zig that uses Hermes JavaScript engine for plugin support via JSI (JavaScript Interface). The core innovation is enabling zero-copy bidirectional communication between Zig (editor core) and JavaScript (plugins).

**Status**: Core integration working - Zig executes JavaScript and JavaScript calls Zig functions.

## Reference Codebases

Three local forks provide reference implementations:

- `../neovim` - Maintain compatibility with Neovim APIs and plugin ecosystem
- `../helix` - High-quality Vim/Neovim fork for design patterns and implementation reference
- `../ghostty` - High-quality Zig terminal project for Zig best practices and terminal handling

## Architecture

### Three-Layer Design

1. **Hermes C++ Engine** (`vendor/hermes/`) - Facebook's JavaScript engine (v0.12.0), managed as git submodule
2. **C API Wrapper** (`src/jsi/hermes_c_api.{h,cpp}`) - Exposes Hermes C++ APIs to C using opaque pointers (OVHermesRuntime, OVHermesValue)
3. **Zig Integration** (`src/*.zig`) - Zig code imports C API via `@cImport` and `@cInclude`

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

### Hermes Integration (Primary Workflow)

```bash
# Build everything (Zig + Hermes integration)
make -f Makefile.hermes all

# Run Zig executing JavaScript demo
make -f Makefile.hermes test-zig

# Run JSI bridge demo (JS calling Zig)
make -f Makefile.hermes test-jsi

# Clean all build artifacts
make -f Makefile.hermes clean

# See available targets
make -f Makefile.hermes help
```

### Zig-Only Builds

```bash
# Build main editor (when src/main.zig exists)
zig build

# Run tests
zig build test

# Format code (use Zig convention: 4 spaces)
zig fmt src/
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

### Demos

- `src/test_zig_hermes.zig` - Shows Zig loading and executing JavaScript bytecode
- `src/test_jsi_bridge.zig` - Shows JavaScript calling Zig functions with zero-copy

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

### "Library not loaded: @rpath/libjsi.dylib"

Set `DYLD_LIBRARY_PATH` to include both Hermes directories:
```bash
DYLD_LIBRARY_PATH=vendor/hermes/build/API/hermes:vendor/hermes/build/jsi
```

### Zig Linker Crash

Don't use `zig build` for Hermes integration. Use `make -f Makefile.hermes` instead. See Architecture section for why.

### Submodule Not Initialized

```bash
git submodule update --init
```

## Project Goals

The end goal is a Vim-like editor where:
- Core editor (buffers, windows, rendering) written in Zig
- Plugins and configuration written in JavaScript/TypeScript
- Zero-copy JSI bridge for high performance
- Hermes bytecode for fast startup and small memory footprint
