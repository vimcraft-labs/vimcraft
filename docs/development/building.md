# Building OpenVim

Build system and development setup.

---

## Requirements

- **Zig**: 0.13+ (ziglang.org)
- **Git**: For submodules
- **C++ Compiler**: clang++ (for Hermes)
- **Node.js**: Optional (for TypeScript)

---

## Build Commands

### Standard Build

```bash
zig build
```

Binary: `./zig-out/bin/vimcraft`

### Development Build

```bash
zig build -Doptimize=Debug
```

### Run Tests

```bash
zig build test
```

---

## Hybrid Build System

OpenVim uses a hybrid build due to Zig linker limitations with C++ code:

1. Zig compiles to `.o` object files
2. clang++ performs final linking

See [CLAUDE.md](../../CLAUDE.md#hybrid-build-system) for details.

---

## Building Hermes

If `vendor/hermes/build/` doesn't exist:

```bash
cd vendor/hermes
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel \
         -DHERMES_ENABLE_DEBUGGER=OFF \
         -GNinja
ninja hermes hermesc
```

---

## Troubleshooting

### Submodule not initialized

```bash
git submodule update --init
```

### Zig version too old

Upgrade to Zig 0.13+
