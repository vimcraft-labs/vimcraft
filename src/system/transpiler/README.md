# TypeScript Transpiler & Bytecode Compiler

**Status**: ✅ Complete (November 2025)

Unified TypeScript module loading system for Vimcraft. Handles single files and multi-file plugins with automatic caching and invalidation.

## Architecture

### Pipeline

```
TypeScript/JavaScript Source
         ↓
    esbuild Transform/Build API
    (TypeScript → JavaScript)
         ↓
    hermesc Compiler
    (JavaScript → HBC Bytecode)
         ↓
    Cache Storage
    (~/.cache/vimcraft/bytecode/{hash}.hbc)
         ↓
    Hermes Runtime Execution
```

### Performance (Measured)

| Operation | Before (SHA256) | After (WyHash) | Notes |
|-----------|-----------------|----------------|-------|
| **Cold Load** | 19.92ms | 20-24ms | TypeScript → JS → HBC → Cache |
| **Hot Load** | 0.31ms | **0.20ms** | Read from cache (35% faster!) |
| **Speedup** | 64x | **100x** | Cache vs rebuild (55% improvement!) |

### Design Principles

1. **Always Cache** - No conditionals, consistent behavior
2. **Automatic Invalidation** - SHA256(path + mtime) cache keys
3. **Unified API** - One function for single files AND directories
4. **Fast Hot Paths** - <1ms cache reads, <50ms cold builds

## Components

### 1. Cache Management (`cache.zig`)

Handles bytecode caching with automatic invalidation.

```zig
pub fn computeCacheKey(allocator, path) ![]const u8
pub fn getCachePath(allocator, config, source_path) ![]const u8
pub fn isCacheFresh(source_path, cache_path) bool
pub fn loadFromCache(allocator, cache_path) ![]const u8
pub fn saveToCache(cache_path, bytecode) !void
pub const CacheStats = struct { hits, misses, total_bytes_cached }
```

**Cache Key Strategy**:
- `WyHash(path)` → 16-char hex string (6x faster than SHA256!)
- Automatic invalidation via mtime comparison (not in hash)
- One cache file per source path
- Directory: `~/.cache/vimcraft/bytecode/`

**Why WyHash over SHA256**:
- ✅ **6x faster**: 0.1µs vs 0.6µs per hash
- ✅ **Simpler**: Hash only path, check mtime separately
- ✅ **One cache file**: No proliferation when file changes
- ✅ **Negligible collision risk**: 64-bit hash, < 1 in billion for < 1M files

### 2. esbuild Wrapper (`esbuild.zig`)

TypeScript/JavaScript transpilation via C shared library.

```zig
pub fn transpile(allocator, source, loader) ![]const u8
pub fn build(allocator, entry_point) ![]const u8
```

**Implementation**:
- C shared library: `vendor/esbuild-wrapper/libesbuild_darwin_arm64.dylib` (6.7MB)
- In-process execution (~100x faster than child process)
- Loaders: `ts`, `tsx`, `js`, `jsx`
- Target: ES2020, CommonJS format

### 3. Hermes Compiler (`hermes.zig`)

JavaScript to Hermes bytecode compilation.

```zig
pub fn compile(allocator, source) ![]const u8
```

**Implementation**:
- Shells out to `vendor/hermes/build/bin/hermesc`
- Flags: `-emit-binary -commonjs -O`
- Output: HBC bytecode (optimized)

### 4. Unified Loader (`loader.zig`)

Single entry point for all module loading.

```zig
pub fn loadModule(allocator, config, path) ![]const u8
```

**Features**:
- Single files: Transpile → Compile → Cache
- Directories: Bundle → Compile → Cache
- Automatic cache management
- `~` expansion for home directory
- Performance statistics tracking

## Usage

### Basic Usage

```zig
const loader = @import("system/transpiler/loader.zig");
const cache = @import("system/transpiler/cache.zig");

// Setup
var stats = cache.CacheStats{};
const config = loader.LoaderConfig{
    .cache_dir = try cache.getDefaultCacheDir(allocator),
    .enable_cache = true,
    .stats = &stats,
};

// Load TypeScript file
const bytecode = try loader.loadModule(allocator, config, "~/.config/vimcraft/index.ts");
defer allocator.free(bytecode);

// Execute in Hermes runtime
try hermes_runtime.evaluateBytecode(bytecode);

// Check performance
std.log.info("Cache stats: {}", .{stats});
```

### Multi-File Plugins

```zig
// Load plugin directory (automatically bundles all imports)
const bytecode = try loader.loadModule(allocator, config, "~/.config/vimcraft/plugins/my-plugin/index.ts");
defer allocator.free(bytecode);
```

### Cache Disabled (Debugging)

```zig
const config = loader.LoaderConfig{
    .cache_dir = "/tmp/vimcraft-cache",
    .enable_cache = false, // Rebuild every time
    .stats = &stats,
};
```

## Build Configuration

### Dependencies

1. **esbuild C wrapper**:
   ```bash
   cd vendor/esbuild-wrapper
   go build -buildmode=c-shared -o libesbuild_darwin_arm64.dylib esbuild_c.go
   ```

2. **Hermes compiler**:
   ```bash
   cd vendor/hermes && mkdir build && cd build
   cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -GNinja
   ninja hermesc
   ```

### build.zig Integration

```zig
// Link esbuild shared library
exe.addLibraryPath(b.path("vendor/esbuild-wrapper"));
exe.linkSystemLibrary("esbuild_darwin_arm64");

// Runtime library path
// DYLD_LIBRARY_PATH=vendor/esbuild-wrapper:vendor/hermes/build/bin
```

## Testing

### Unit Tests

```bash
# Cache management
zig test src/system/transpiler/cache.zig

# esbuild transpilation
DYLD_LIBRARY_PATH=vendor/esbuild-wrapper \
  zig test src/system/transpiler/esbuild.zig \
  -I vendor/esbuild-wrapper -L vendor/esbuild-wrapper -lesbuild_darwin_arm64

# Hermes compilation
zig test src/system/transpiler/hermes.zig

# Unified loader
DYLD_LIBRARY_PATH=vendor/esbuild-wrapper \
  zig test src/system/transpiler/loader.zig \
  -I vendor/esbuild-wrapper -L vendor/esbuild-wrapper -lesbuild_darwin_arm64
```

### Integration Tests

```bash
# End-to-end pipeline (15 tests)
DYLD_LIBRARY_PATH=vendor/esbuild-wrapper \
  zig test src/system/transpiler/integration_test.zig \
  -I vendor/esbuild-wrapper -L vendor/esbuild-wrapper -lesbuild_darwin_arm64
```

**Test Coverage**:
- ✅ Cache key computation (SHA256 + mtime)
- ✅ Cache freshness validation
- ✅ Cache save/load
- ✅ Cache statistics tracking
- ✅ TypeScript transpilation (ts, tsx, jsx)
- ✅ Hermes compilation
- ✅ Single file loading
- ✅ Multi-file bundling
- ✅ Cache invalidation (file modification)
- ✅ Cache disabled mode
- ✅ End-to-end pipeline
- ✅ Performance validation

## Performance Benchmarks

See individual benchmark files for detailed results:

- `transpile_benchmark.zig` - Small file transpilation (0.3-1ms)
- `large_file_benchmark.zig` - Large file handling (1KB-10MB)
- `multi_file_benchmark.zig` - Many small files (10-5000 files)
- `cache_overhead_benchmark.zig` - Cache vs in-memory (5x speedup)

### Key Findings

1. **Small files (<2KB)**: Transpile in 0.3-1ms
2. **Large files (10MB)**: Transpile in 194ms (caching essential!)
3. **Many files (5000)**: Bundle in ~50ms (300x faster than individual transpilation)
4. **Cache overhead**: Even for small files, caching is 5x faster

## File Structure

```
src/system/transpiler/
├── README.md                          # This file
├── cache.zig                          # Cache management (280 lines)
├── esbuild.zig                        # esbuild wrapper (193 lines)
├── hermes.zig                         # Hermes compiler wrapper (162 lines)
├── loader.zig                         # Unified loader (315 lines)
├── integration_test.zig               # End-to-end tests (280 lines)
├── transpile_benchmark.zig            # Small file benchmarks
├── large_file_benchmark.zig           # Large file benchmarks
├── multi_file_benchmark.zig           # Many file benchmarks
└── cache_overhead_benchmark.zig       # Cache performance validation

vendor/esbuild-wrapper/
├── esbuild_c.go                       # Go → C FFI (105 lines)
├── libesbuild_darwin_arm64.h          # C API header (auto-generated)
└── libesbuild_darwin_arm64.dylib      # Shared library (6.7MB)

vendor/hermes/build/bin/
└── hermesc                            # Hermes compiler (2.3MB)
```

## Integration Roadmap

### Phase 1: Basic Integration (Next)

1. **Update `module_api.zig`**:
   ```zig
   pub export fn require(runtime: ?*c.OVHermesRuntime, ...) callconv(.C) ?*c.OVHermesValue {
       const path = ... // Extract path from args
       const bytecode = try loader.loadModule(allocator, config, path);
       defer allocator.free(bytecode);
       return c.hermes_evaluate_bytecode(runtime, bytecode.ptr, bytecode.len);
   }
   ```

2. **Initialize cache on startup**:
   ```zig
   // In main.zig or editor init
   try cache.initCacheDir(cache_dir);
   ```

3. **Test with real plugins**:
   ```typescript
   // ~/.config/vimcraft/index.ts
   const smearCursor = require('~/.config/vimcraft/plugins/smear-cursor');
   smearCursor.setup({ enabled: true });
   ```

### Phase 2: Advanced Features (Future)

1. **Source maps**: Link compiled bytecode to original TypeScript
2. **Watch mode**: Auto-reload on file changes
3. **Cache cleanup**: Remove stale cache entries
4. **Compression**: Compress cached bytecode (gzip/zstd)
5. **Multi-platform**: Linux/Windows support for esbuild wrapper

## Troubleshooting

### "esbuild library not found"

```bash
# Ensure library path is set
export DYLD_LIBRARY_PATH=vendor/esbuild-wrapper:$DYLD_LIBRARY_PATH

# Verify library exists
ls -lh vendor/esbuild-wrapper/libesbuild_darwin_arm64.dylib
```

### "hermesc not found"

```bash
# Build Hermes if missing
cd vendor/hermes && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -GNinja
ninja hermesc

# Verify compiler exists
vendor/hermes/build/bin/hermesc --version
```

### Cache invalidation not working

```bash
# Clear cache manually
rm -rf ~/.cache/vimcraft/bytecode/*

# Check file mtimes
stat -f "%Sm %N" /path/to/source.ts
stat -f "%Sm %N" ~/.cache/vimcraft/bytecode/*.hbc
```

### Memory leaks in tests

```bash
# Run with memory leak detection
zig test src/system/transpiler/loader.zig \
  --test-filter "load single" \
  -fsanitize=memory
```

## References

- **esbuild**: https://esbuild.github.io/
- **Hermes**: https://hermesengine.dev/
- **Vimcraft**: See main project README.md
- **Performance Benchmarks**: See individual `*_benchmark.zig` files

## License

Same as Vimcraft (see project root).
