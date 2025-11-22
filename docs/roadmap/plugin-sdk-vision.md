# Vimcraft Plugin SDK Vision

**Status**: 📅 Future (Phase 5-6)
**Foundation**: Phase 4 (HostObject architecture)
**Target Date**: Q2 2025

## Vision Statement

Enable third-party developers to extend Vimcraft with **native-performance plugins** written in any language (C, Rust, Zig, Wasm), using the same zero-copy JSI interface that powers Vimcraft's internal APIs.

## Why Native Plugins?

### JavaScript is Slow for Some Tasks

**Example**: FZF fuzzy finder

```javascript
// Pure JavaScript (SLOW - 500ms for 10,000 files)
function fuzzyfind(pattern, files) {
    return files
        .map(f => ({ file: f, score: fuzzyScore(f, pattern) }))
        .filter(x => x.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, 100);
}
```

vs

```c
// Native C with fzf algorithm (FAST - 5ms for 10,000 files)
fzf_result_t* fzf_search(const char* pattern, const char** files, size_t count) {
    // Highly optimized C implementation (100x faster)
}
```

### Use Cases for Native Plugins

1. **Performance-Critical**:
   - Fuzzy finders (fzf, telescope)
   - Syntax highlighting (tree-sitter parsers)
   - Code search (ripgrep integration)

2. **System Integration**:
   - Git operations (libgit2)
   - Database connectors (SQLite, PostgreSQL)
   - System APIs (file watching, clipboard)

3. **Existing Libraries**:
   - Leverage mature C libraries (curl, openssl)
   - Avoid rewriting in JavaScript
   - Preserve performance characteristics

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  JavaScript Plugin Layer                    │
│  User's index.js → vim.plugins.fzf.find() → Native Code     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Vimcraft Plugin SDK (C API)                    │
│ vimcraft_host_object_new(), vimcraft_register_host_object() │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
    C Plugin            Rust Plugin         Wasm Plugin
    (fzf-native)        (ripgrep-rs)        (tree-sitter)
    .so / .dylib        .so / .dylib        .wasm
```

## Plugin Types

### 1. Native Shared Libraries (C/Rust/Zig)

**Characteristics**:
- ✅ Maximum performance (no overhead)
- ✅ Full system access
- ✅ Can link any C library
- ❌ Platform-specific (.so on Linux, .dylib on macOS, .dll on Windows)
- ❌ Security risk (no sandboxing)

**Example**: fzf-native, ripgrep, libgit2 bindings

### 2. Wasm Modules

**Characteristics**:
- ✅ Portable (works on all platforms)
- ✅ Sandboxed (safe execution)
- ✅ Near-native performance
- ❌ Limited system access (no direct file I/O)
- ❌ Requires Wasm runtime

**Example**: Tree-sitter parsers, syntax highlighters

### 3. Hybrid (Native + JavaScript)

**Characteristics**:
- ✅ Performance-critical code in native, logic in JavaScript
- ✅ Easier to develop (JavaScript is more ergonomic)
- ✅ Best of both worlds

**Example**: LSP client (protocol handling in JS, parsing in native)

## C Plugin API Design

### Core API (include/vimcraft/plugin_api.h)

```c
#ifndef VIMCRAFT_PLUGIN_API_H
#define VIMCRAFT_PLUGIN_API_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

// Opaque types
typedef struct VimcraftRuntime VimcraftRuntime;
typedef struct VimcraftValue VimcraftValue;
typedef struct VimcraftHostObject VimcraftHostObject;

// Host function signature (same as JSI)
typedef VimcraftValue* (*VimcraftHostFunction)(
    VimcraftRuntime* runtime,
    void* context,
    VimcraftValue** args,
    size_t arg_count
);

// === HostObject API ===

// Create new HostObject with given name
VimcraftHostObject* vimcraft_host_object_new(const char* name);

// Add method to HostObject
void vimcraft_host_object_add_method(
    VimcraftHostObject* obj,
    const char* name,
    VimcraftHostFunction fn,
    void* context
);

// Add property getter/setter
void vimcraft_host_object_add_property(
    VimcraftHostObject* obj,
    const char* name,
    VimcraftHostFunction getter,
    VimcraftHostFunction setter // NULL for read-only
);

// Register HostObject in JavaScript namespace
void vimcraft_register_host_object(
    VimcraftRuntime* rt,
    VimcraftHostObject* obj
);

// === Value API ===

// Type checking
bool vimcraft_value_is_string(VimcraftValue* val);
bool vimcraft_value_is_number(VimcraftValue* val);
bool vimcraft_value_is_boolean(VimcraftValue* val);
bool vimcraft_value_is_array(VimcraftValue* val);
bool vimcraft_value_is_object(VimcraftValue* val);

// String operations
const char* vimcraft_value_get_string(VimcraftRuntime* rt, VimcraftValue* val, size_t* len);
VimcraftValue* vimcraft_string_create(VimcraftRuntime* rt, const char* str, size_t len);

// Number operations
double vimcraft_value_get_number(VimcraftValue* val);
VimcraftValue* vimcraft_number_create(VimcraftRuntime* rt, double num);

// Boolean operations
bool vimcraft_value_get_boolean(VimcraftValue* val);
VimcraftValue* vimcraft_boolean_create(VimcraftRuntime* rt, bool val);

// Array operations
size_t vimcraft_array_get_length(VimcraftRuntime* rt, VimcraftValue* arr);
VimcraftValue* vimcraft_array_get(VimcraftRuntime* rt, VimcraftValue* arr, size_t index);
void vimcraft_array_set(VimcraftRuntime* rt, VimcraftValue* arr, size_t index, VimcraftValue* val);
VimcraftValue* vimcraft_array_create(VimcraftRuntime* rt, size_t length);

// Object operations
VimcraftValue* vimcraft_object_get_property(VimcraftRuntime* rt, VimcraftValue* obj, const char* key);
void vimcraft_object_set_property(VimcraftRuntime* rt, VimcraftValue* obj, const char* key, VimcraftValue* val);

// ArrayBuffer (zero-copy)
uint8_t* vimcraft_arraybuffer_data(VimcraftRuntime* rt, VimcraftValue* ab);
size_t vimcraft_arraybuffer_size(VimcraftRuntime* rt, VimcraftValue* ab);
VimcraftValue* vimcraft_arraybuffer_create(VimcraftRuntime* rt, uint8_t* data, size_t size);

// Error handling
VimcraftValue* vimcraft_error_create(VimcraftRuntime* rt, const char* message);

// === Plugin Entry Point ===

// Must be exported by plugin .so/.dylib
void vimcraft_plugin_init(VimcraftRuntime* rt);

#endif // VIMCRAFT_PLUGIN_API_H
```

## Example Plugins

### Example 1: fzf-native (C Plugin)

```c
// plugins/fzf-native/src/main.c

#include <vimcraft/plugin_api.h>
#include <fzf/fzf.h>  // External fzf library

static VimcraftValue* fzf_find(
    VimcraftRuntime* rt,
    void* ctx,
    VimcraftValue** args,
    size_t argc
) {
    // Validate arguments
    if (argc < 1 || !vimcraft_value_is_string(args[0])) {
        return vimcraft_error_create(rt, "fzf.find: pattern must be a string");
    }

    // Extract pattern
    size_t pattern_len;
    const char* pattern = vimcraft_value_get_string(rt, args[0], &pattern_len);

    // Get current directory files (1000 files)
    const char** files = get_directory_files(".", &file_count);

    // Run fzf algorithm (C implementation, 5ms for 10,000 files)
    fzf_result_t* results = fzf_search(pattern, files, file_count);

    // Convert to JavaScript array
    VimcraftValue* arr = vimcraft_array_create(rt, results->count);
    for (size_t i = 0; i < results->count; i++) {
        VimcraftValue* str = vimcraft_string_create(rt, results->items[i], strlen(results->items[i]));
        vimcraft_array_set(rt, arr, i, str);
    }

    fzf_result_free(results);
    return arr;
}

static VimcraftValue* fzf_grep(
    VimcraftRuntime* rt,
    void* ctx,
    VimcraftValue** args,
    size_t argc
) {
    // Similar to find, but uses ripgrep for content search
    // ...
}

// Plugin entry point
void vimcraft_plugin_init(VimcraftRuntime* rt) {
    VimcraftHostObject* fzf = vimcraft_host_object_new("fzf");
    vimcraft_host_object_add_method(fzf, "find", fzf_find, NULL);
    vimcraft_host_object_add_method(fzf, "grep", fzf_grep, NULL);
    vimcraft_register_host_object(rt, fzf);

    // Now JavaScript can call: vim.plugins.fzf.find("*.zig")
}
```

**Build**:
```bash
# plugins/fzf-native/Makefile
fzf-native.so: src/main.c
    clang -shared -fPIC \
        -I../../include \
        -lfzf \
        -o fzf-native.so \
        src/main.c

install:
    cp fzf-native.so ~/.vimcraft/plugins/
```

### Example 2: tree-sitter (Wasm Plugin)

```rust
// plugins/tree-sitter-zig/src/lib.rs

use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct TreeSitterZig {
    parser: tree_sitter::Parser,
}

#[wasm_bindgen]
impl TreeSitterZig {
    #[wasm_bindgen(constructor)]
    pub fn new() -> TreeSitterZig {
        let mut parser = tree_sitter::Parser::new();
        parser.set_language(tree_sitter_zig::language()).unwrap();
        TreeSitterZig { parser }
    }

    #[wasm_bindgen]
    pub fn parse(&mut self, source: &str) -> String {
        let tree = self.parser.parse(source, None).unwrap();
        tree.root_node().to_sexp()
    }

    #[wasm_bindgen]
    pub fn highlight(&self, source: &str) -> Vec<u8> {
        // Return syntax highlighting tokens as ArrayBuffer
        // ...
    }
}
```

**Build**:
```bash
wasm-pack build --target web
# Produces: tree-sitter-zig.wasm
```

**JavaScript Bridge**:
```javascript
// plugins/tree-sitter-zig/index.js
import init, { TreeSitterZig } from './tree-sitter-zig.wasm';

export async function load() {
    await init();
    const parser = new TreeSitterZig();

    vim.treesitter.register('zig', {
        parse: (source) => parser.parse(source),
        highlight: (source) => parser.highlight(source),
    });
}
```

## User Experience

### Plugin Installation

```bash
# Install from registry
vimcraft plugin install fzf-native

# Install from local path
vimcraft plugin install --path ~/dev/my-plugin

# Install from git
vimcraft plugin install https://github.com/user/plugin.git
```

### Plugin Usage (JavaScript)

```javascript
// ~/.config/vimcraft/index.ts

// Load native plugin
await vim.plugins.load('fzf-native', {
    path: '~/.vimcraft/plugins/fzf-native.so'
});

// Use it
vim.keymap.set('n', '<leader>f', async () => {
    const files = await vim.plugins.fzf.find({
        cwd: vim.fn.getcwd(),
        pattern: '*',
        maxResults: 100
    });

    if (files.length > 0) {
        vim.cmd(`edit ${files[0]}`);
    }
});

// Load Wasm plugin
await vim.plugins.load('tree-sitter-zig', {
    type: 'wasm',
    path: '~/.vimcraft/plugins/tree-sitter-zig.wasm'
});

// Use it
vim.api.set_highlight_provider('zig', vim.plugins.treesitter.zig);
```

## Security Model

### Native Plugins (.so/.dylib)

**Trust Model**: Full trust (same as running any binary)

**Risks**:
- Can read/write any file
- Can make network requests
- Can execute arbitrary code

**Mitigation**:
- Require explicit user confirmation on first load
- Show plugin permissions before loading
- Warn if plugin is not signed

### Wasm Plugins

**Trust Model**: Sandboxed execution (WASI capabilities)

**Permissions**:
- File I/O: Limited to explicitly granted directories
- Network: Limited to explicitly granted hosts
- System calls: None (pure computation)

**Benefits**:
- Safe to run untrusted code
- Portable across platforms
- Performance isolation

## Plugin Discovery

### Plugin Registry

```json
// ~/.vimcraft/plugins/registry.json
{
    "plugins": {
        "fzf-native": {
            "name": "fzf-native",
            "version": "1.0.0",
            "author": "vimcraft-community",
            "description": "Native fzf fuzzy finder",
            "type": "native",
            "platforms": {
                "darwin": "fzf-native-darwin.dylib",
                "linux": "fzf-native-linux.so",
                "windows": "fzf-native-windows.dll"
            },
            "dependencies": [],
            "homepage": "https://github.com/vimcraft/fzf-native"
        },
        "tree-sitter-zig": {
            "name": "tree-sitter-zig",
            "version": "0.2.0",
            "author": "ziglang-community",
            "description": "Tree-sitter Zig parser",
            "type": "wasm",
            "file": "tree-sitter-zig.wasm",
            "dependencies": [],
            "homepage": "https://github.com/tree-sitter/tree-sitter-zig"
        }
    }
}
```

### Plugin Manifest

```json
// plugins/fzf-native/vimcraft-plugin.json
{
    "name": "fzf-native",
    "version": "1.0.0",
    "apiVersion": "1.0",
    "type": "native",
    "entry": "vimcraft_plugin_init",
    "dependencies": {
        "system": ["libfzf >= 1.0"]
    },
    "permissions": [
        "fs.read",
        "fs.watch"
    ],
    "exports": {
        "vim.plugins.fzf": {
            "find": "Fuzzy find files in directory",
            "grep": "Search file contents"
        }
    }
}
```

## Implementation Timeline

### Phase 5: Native Plugin Support (4-6 weeks)

**Week 1-2**: C API Implementation
- Implement `vimcraft_host_object_*` functions in `src/system/jsi/plugin_sdk.zig`
- Expose HostObjectBuilder to C via ABI-stable interface
- Add `dlopen`/`dlsym` for loading .so/.dylib

**Week 3-4**: Plugin Loader
- Implement `vim.plugins.load()` in JavaScript
- Add plugin registry system
- Plugin sandboxing (permissions, resource limits)

**Week 5**: Example Plugins
- Port fzf-native as reference implementation
- Document plugin development workflow

**Week 6**: Testing & Documentation
- Unit tests for plugin API
- Integration tests with example plugins
- Plugin development guide

### Phase 6: Wasm Plugin Support (3-4 weeks)

**Week 1-2**: Wasm Runtime Integration
- Integrate wasmtime or wasmer
- WASI capabilities system
- Wasm ↔ JSI bridge

**Week 3**: Tree-sitter Integration
- Port tree-sitter parsers to Wasm
- Syntax highlighting via Wasm

**Week 4**: Testing & Documentation
- Wasm plugin examples
- Performance benchmarks

## Success Metrics

- ✅ 10+ community plugins within 3 months
- ✅ Native plugins 10-100x faster than pure JavaScript equivalents
- ✅ Wasm plugins work on all platforms (Linux, macOS, Windows)
- ✅ Zero security incidents with sandboxed plugins
- ✅ Plugin API stable for 12+ months (no breaking changes)

## Future Enhancements

1. **Hot Reloading**: Reload plugins without restarting Vimcraft
2. **Plugin Marketplace**: Web UI for discovering/installing plugins
3. **Auto-Update**: Background updates for installed plugins
4. **Plugin Analytics**: Telemetry for plugin performance/crashes
5. **Multi-Language Bindings**: Python, Ruby, Lua bindings via FFI

## References

- React Native TurboModules: https://reactnative.dev/docs/next/the-new-architecture/pillars-turbomodules
- Neovim plugin system: https://neovim.io/doc/user/lua.html
- V8 embedder's guide: https://v8.dev/docs/embed
- WebAssembly: https://webassembly.org/
- WASI: https://wasi.dev/

## Conclusion

The Plugin SDK transforms Vimcraft from a closed system into an **extensible platform**. By providing zero-copy JSI interfaces to third-party developers, we enable:

- **100x performance** for critical operations (fzf, ripgrep, tree-sitter)
- **Ecosystem growth** through community plugins
- **Innovation** without modifying Vimcraft core

The HostObject architecture (Phase 4) lays the foundation for this vision. Phase 5-6 will expose this power to the world.
