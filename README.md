# OpenVim - Zig + Hermes+JSI Core

**Status**: ✅ Zig executes JavaScript via Hermes + JSI bridge working

## Structure

```
openvim/
├── src/jsi/
│   ├── hermes_c_api.h           # C API header
│   ├── hermes_c_api.cpp         # C++ wrapper for Hermes
│   ├── hermes.zig               # Zig bindings (optional)
│   ├── test_zig_hermes.zig      # Demo: Zig runs JS
│   └── test_jsi_bridge.zig      # Demo: JS calls Zig (JSI)
├── vendor/hermes/           # Hermes JavaScript engine
├── Makefile.hermes              # Build system
├── build.zig                    # Zig build config
└── test_hermes.c                # C test (reference)
```

## Build & Test

```bash
# Build everything
make -f Makefile.hermes all

# Test: Zig runs JavaScript
make -f Makefile.hermes test-zig

# Clean
make -f Makefile.hermes clean
```

## Core Flow

### 1. Zig Executes JavaScript (.hbc)

```zig
// src/test_zig_hermes.zig
const runtime = c.hermes_runtime_create();
const bytecode = try file.readToEndAlloc(..., "/tmp/test.hbc");
const result = c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);
// Result: JavaScript executed!
```

### 2. JSI Bridge (JS calls Zig)

```zig
// src/test_jsi_bridge.zig
export fn zig_add_numbers(...) { /* Zig function */ }

// Register for JavaScript
c.hermes_register_host_function(runtime, "zigAdd", zig_add_numbers, null);

// JavaScript calls Zig: zigAdd(10, 20) → Zig executes → returns 30
```

## Key Files

- `hermes_c_api.h/cpp` - Bridge between Zig and Hermes C++
- `test_zig_hermes.zig` - Demonstrates Zig executing JavaScript
- `test_jsi_bridge.zig` - Demonstrates JavaScript calling Zig (zero-copy!)
- `Makefile.hermes` - Hybrid build (Zig→.o, clang++ links)

## That's It!

This is the minimal core. Everything works.
