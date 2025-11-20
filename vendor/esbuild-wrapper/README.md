# esbuild C Wrapper for Vimcraft

This directory contains a Go-based C wrapper around esbuild's Transform API, built using `go build -buildmode=c-shared`.

## Why This Approach?

Instead of spawning esbuild as a child process (slow), we compile esbuild into a C-compatible shared library (.dylib/.so) and link it directly into Vimcraft. This provides:

- ✅ **In-process execution** (~100x faster than child process spawn)
- ✅ **Direct C FFI** (same pattern as libuv)
- ✅ **Small size** (6.7MB vs 10MB standalone binary)
- ✅ **Zero serialization overhead** (no stdin/stdout JSON marshalling)

## Architecture

```
JavaScript (require("./foo.ts"))
    ↓
Zig (src/system/transpiler/esbuild.zig)
    ↓
C FFI (libesbuild_darwin_arm64.dylib)
    ↓
Go (vendor/esbuild-wrapper/esbuild_c.go)
    ↓
esbuild (github.com/evanw/esbuild/pkg/api)
```

## Build Instructions

### Prerequisites

- Go 1.21+ (`brew install go` or https://go.dev/dl/)
- Platform: macOS, Linux, or Windows

### Build for Current Platform

```bash
cd vendor/esbuild-wrapper
./build.sh
```

This generates:
- `libesbuild_darwin_arm64.dylib` (macOS ARM64)
- `libesbuild_darwin_arm64.h` (auto-generated C header)

### Cross-Compilation

```bash
# macOS ARM64
GOOS=darwin GOARCH=arm64 go build -buildmode=c-shared -o libesbuild_darwin_arm64.dylib esbuild_c.go

# macOS x86_64
GOOS=darwin GOARCH=amd64 go build -buildmode=c-shared -o libesbuild_darwin_x64.dylib esbuild_c.go

# Linux x86_64
GOOS=linux GOARCH=amd64 go build -buildmode=c-shared -o libesbuild_linux_x64.so esbuild_c.go

# Linux ARM64
GOOS=linux GOARCH=arm64 go build -buildmode=c-shared -o libesbuild_linux_arm64.so esbuild_c.go

# Windows x86_64
GOOS=windows GOARCH=amd64 go build -buildmode=c-shared -o libesbuild_win32_x64.dll esbuild_c.go
```

## C API

The wrapper exposes a single function:

```c
extern char* esbuild_transform(char* source, int source_len, char* loader);
```

**Parameters:**
- `source`: TypeScript/JavaScript source code
- `source_len`: Length of source in bytes
- `loader`: File type ("ts", "tsx", "js", "jsx")

**Returns:**
- Transpiled JavaScript code as C string (caller must free())
- Error message if transpilation failed

## Zig Wrapper

See `src/system/transpiler/esbuild.zig` for type-safe Zig API:

```zig
const result = try transpile(allocator, source, "ts");
defer allocator.free(result);
```

## Testing

```bash
# Run Zig tests
DYLD_LIBRARY_PATH=vendor/esbuild-wrapper zig test src/system/transpiler/esbuild.zig \
    -I vendor/esbuild-wrapper \
    -L vendor/esbuild-wrapper \
    -lesbuild_darwin_arm64
```

## Size Comparison

| Approach | Size | Performance |
|----------|------|-------------|
| Standalone binary + child process | 10MB | Baseline (spawn overhead) |
| C shared library (this) | 6.7MB | ~100x faster (in-process) |
| SWC static library (blocked) | ~7MB | Similar (if it compiled) |

## esbuild Configuration

The wrapper is configured for Vimcraft's use case:

- **Target**: ES2020 (modern JavaScript, works with Hermes)
- **Format**: CommonJS (matches Vimcraft's `require()` system)
- **Minify**: Disabled (preserves readability for debugging)
- **Sourcemap**: None (can be enabled if needed)

These options can be customized in `esbuild_c.go` if needed.

## Memory Management

**Critical**: The caller (Zig) MUST free the returned C string:

```zig
const result_ptr = c.esbuild_transform(...);
defer std.c.free(result_ptr); // REQUIRED!
```

Go allocates with `C.CString()` which uses `malloc()`, so standard `free()` works.

## Why Not Official esbuild?

The esbuild author explicitly rejected adding cgo to keep the build process simple (see [evanw/esbuild#248](https://github.com/evanw/esbuild/issues/248)). This wrapper is a **vendor-specific integration** - we maintain our own thin wrapper to enable direct linking.

## Future Optimizations

- [ ] Add caching layer (HashMap: `source_hash → transpiled_code`)
- [ ] Support source maps (currently disabled)
- [ ] Add platform detection for multi-platform builds
- [ ] Investigate `-buildmode=c-archive` for static linking (eliminate .dylib)
