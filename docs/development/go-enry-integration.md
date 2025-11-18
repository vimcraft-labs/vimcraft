# go-enry Integration Guide

Complete guide to Vimcraft's go-enry integration for GitHub Linguist-based language detection (697 languages).

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Building go-enry](#building-go-enry)
- [Deployment](#deployment)
- [Error Handling](#error-handling)
- [Platform-Specific Details](#platform-specific-details)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Overview

**go-enry** is a Go port of GitHub Linguist's language detection library. Vimcraft uses go-enry via C FFI to provide comprehensive filetype detection supporting:

- **697 languages** (vs 12 in custom implementation)
- **Extension matching** (with ambiguity detection)
- **Exact filename matching** (e.g., Makefile, .gitignore)
- **Shebang detection** (#!/usr/bin/env python3)
- **Modeline parsing** (Vim and Emacs)
- **Content heuristics** (regexp-based disambiguation)
- **Bayesian classifier** (last resort for ambiguous cases)

### Files

```
src/system/enry/
├── c_api.zig          # C FFI layer (GoString, GoSlice, extern functions)
├── enry.zig           # High-level Zig wrapper
vendor/go-enry/
├── .shared/
│   ├── darwin/        # macOS universal binary (arm64 + x86_64)
│   ├── linux/         # Linux amd64 binary
│   └── windows/       # Windows amd64 binary
└── shared/enry.go     # Go source (builds to C shared library)
scripts/
└── build-enry.sh      # Cross-platform build automation
```

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────┐
│  Zig Application Layer                      │
│  (loader.zig: detectFiletype)              │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│  Zig Wrapper Layer (enry.zig)              │
│  - detectLanguage()                         │
│  - detectByExtension()                      │
│  - detectByFilename()                       │
│  - detectByShebang()                        │
│  - detectByModeline()                       │
│  - detectByContent()                        │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│  C FFI Layer (c_api.zig)                   │
│  - GoString, GoSlice types                  │
│  - makeGoString(), makeGoSlice()            │
│  - goStringToZig() (with validation)        │
│  - extern "c" fn GetLanguage()              │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│  Go Shared Library (libenry.dylib/.so/.dll)│
│  - GetLanguage()                            │
│  - GetLanguageByExtension()                 │
│  - GetLanguageByFilename()                  │
│  - GetLanguageByShebang()                   │
│  - GetLanguageByModeline()                  │
│  - GetLanguageByContent()                   │
└─────────────────────────────────────────────┘
```

### Memory Management

**Arena Allocator Pattern** (prevents memory leaks):

```zig
pub const Loader = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator, // Batch allocation/deallocation

    pub fn init(allocator: std.mem.Allocator) !Loader {
        return Loader{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Loader) void {
        self.arena.deinit(); // Frees ALL go-enry allocations at once
    }

    pub fn detectFiletype(self: *Loader, path: []const u8, first_line: ?[]const u8) ?[]const u8 {
        const arena_allocator = self.arena.allocator();
        const lang = enry.detectLanguage(arena_allocator, path, first_line) catch |err| {
            std.log.debug("go-enry failed for '{s}': {}", .{ path, err });
            return null;
        };
        return lang; // No need to free - arena handles cleanup
    }
};
```

**Key Benefits**:
- Single `deinit()` call frees all allocations
- No per-string cleanup required
- Prevents memory leaks even on error paths
- Efficient batch allocation/deallocation

## Building go-enry

### Prerequisites

- **Go 1.18+** (for CGO and generics support)
- **Zig 0.13+** (for build system)
- **Platform-specific tools**:
  - macOS: `lipo`, `install_name_tool` (included in Xcode Command Line Tools)
  - Linux: GCC/Clang with CGO support
  - Windows: MinGW-w64 or MSVC with CGO support

### Quick Build (Automated)

```bash
# Auto-detect platform
./scripts/build-enry.sh

# Or specify platform explicitly
./scripts/build-enry.sh darwin   # macOS (universal binary)
./scripts/build-enry.sh linux    # Linux (amd64)
./scripts/build-enry.sh windows  # Windows (amd64)
```

The script will:
1. Validate Go installation and version
2. Build architecture-specific binaries
3. Create universal binary (macOS only)
4. Fix install names for proper dynamic linking
5. Verify binary format and architectures

### Manual Build (Advanced)

**macOS (universal binary)**:

```bash
cd vendor/go-enry

# Build arm64 binary
CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
    go build -mod=mod -buildmode=c-shared \
    -o .shared/darwin/libenry.dylib.arm64 \
    ./shared/enry.go

# Build amd64 binary
CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
    go build -mod=mod -buildmode=c-shared \
    -o .shared/darwin/libenry.dylib.amd64 \
    ./shared/enry.go

# Create universal binary
lipo -create \
    .shared/darwin/libenry.dylib.arm64 \
    .shared/darwin/libenry.dylib.amd64 \
    -output .shared/darwin/libenry.dylib

# Fix install names (use @rpath prefix for RPATH support)
install_name_tool -id "@rpath/libenry.dylib" .shared/darwin/libenry.dylib

# Verify
lipo -info .shared/darwin/libenry.dylib
# Should show: Architectures in the fat file: libenry.dylib are: x86_64 arm64
```

**Linux (amd64)**:

```bash
cd vendor/go-enry

CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    go build -mod=mod -buildmode=c-shared \
    -o .shared/linux/libenry.so \
    ./shared/enry.go

# Verify
file .shared/linux/libenry.so
# Should show: ELF 64-bit LSB shared object, x86-64
```

**Windows (amd64)**:

```bash
cd vendor/go-enry

CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
    go build -mod=mod -buildmode=c-shared \
    -o .shared/windows/libenry.dll \
    ./shared/enry.go
```

## Deployment

### Local Development

**macOS**:

```bash
# Build go-enry
./scripts/build-enry.sh

# Build Vimcraft (automatically links to vendor/go-enry/.shared/darwin)
zig build

# Run tests (DYLD_LIBRARY_PATH needed for test binaries)
DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin zig build test

# Run editor (RPATH configured, no environment variable needed)
./zig-out/bin/vimcraft file.rs
```

**Linux**:

```bash
# Build go-enry
./scripts/build-enry.sh linux

# Build Vimcraft
zig build

# Run tests
LD_LIBRARY_PATH=vendor/go-enry/.shared/linux zig build test

# Run editor (RPATH configured)
./zig-out/bin/vimcraft file.py
```

### CI/CD (GitHub Actions)

**Example workflow**:

```yaml
name: Build

on: [push, pull_request]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.13.0

      - name: Build go-enry
        run: ./scripts/build-enry.sh

      - name: Build Vimcraft
        run: zig build

      - name: Run tests (macOS)
        if: runner.os == 'macOS'
        run: DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin zig build test

      - name: Run tests (Linux)
        if: runner.os == 'Linux'
        run: LD_LIBRARY_PATH=vendor/go-enry/.shared/linux zig build test
```

### Production Distribution

**Approach 1: Bundle Shared Library**

Package the platform-specific shared library with the executable:

```
vimcraft-macos/
├── bin/vimcraft
└── lib/libenry.dylib

vimcraft-linux/
├── bin/vimcraft
└── lib/libenry.so
```

Update RPATH at install time:
```bash
# macOS
install_name_tool -add_rpath @executable_path/../lib vimcraft

# Linux
patchelf --set-rpath '$ORIGIN/../lib' vimcraft
```

**Approach 2: Static Linking (Future)**

For truly portable binaries, static linking would be ideal but requires:
- Building Go with `-buildmode=c-archive` instead of `c-shared`
- Linking resulting `.a` file into Zig binary
- Handling Go runtime initialization

This is more complex and not currently implemented.

## Error Handling

### Error Types

go-enry integration defines three error types in `c_api.zig:6-13`:

```zig
pub const EnryError = error{
    /// Integer overflow when converting between Zig and Go sizes
    IntegerOverflow,
    /// Invalid input (null pointer with non-zero length)
    InvalidInput,
    /// Allocation failure when copying Go string to Zig
    OutOfMemory,
};
```

### Error Propagation

All enry functions propagate errors properly:

```zig
pub fn detectLanguage(
    allocator: std.mem.Allocator,
    filename: []const u8,
    content: ?[]const u8,
) EnryError!?[]const u8 {
    // Validates input sizes before @intCast
    const go_filename = try makeGoString(filename);
    const go_content = if (content) |c|
        try makeGoSlice(c)
    else
        GoSlice{ .data = null, .len = 0, .cap = 0 };

    const result = GetLanguage(go_filename, go_content);

    // Validates result before allocation
    return goStringToZig(allocator, result);
}
```

### Error Handling in Application Code

`loader.zig:127-131` catches all errors and logs them:

```zig
const lang = enry.detectLanguage(arena_allocator, path, first_line) catch |err| {
    // Log error for debugging
    std.log.debug("go-enry detectLanguage failed for '{s}': {}", .{ path, err });
    return null; // Treat all errors as "language not detected"
};
```

**Rationale**: Any error (OutOfMemory, IntegerOverflow, InvalidInput) means we can't detect the language, so returning `null` is appropriate. Errors are logged for debugging but don't crash the application.

### Input Validation

All C FFI helpers validate inputs before conversion:

**makeGoString** (c_api.zig:55-64):
```zig
pub fn makeGoString(s: []const u8) EnryError!GoString {
    if (s.len > std.math.maxInt(isize)) {
        return EnryError.IntegerOverflow;
    }
    return GoString{ .p = s.ptr, .n = @intCast(s.len) };
}
```

**goStringToZig** (c_api.zig:89-109):
```zig
pub fn goStringToZig(allocator: std.mem.Allocator, gs: GoString) EnryError!?[]const u8 {
    if (gs.n <= 0) return null;

    if (gs.p == null) {
        return EnryError.InvalidInput;
    }

    if (gs.n < 0 or gs.n > std.math.maxInt(usize)) {
        return EnryError.IntegerOverflow;
    }

    const len: usize = @intCast(gs.n);
    const str = allocator.alloc(u8, len) catch return EnryError.OutOfMemory;
    @memcpy(str, gs.p[0..len]);

    return str;
}
```

## Platform-Specific Details

### macOS

**Universal Binary**: Supports both Apple Silicon (arm64) and Intel (x86_64) in a single dylib.

**Size**: ~21MB (10MB per architecture + header)

**Dynamic Linking**:
- Build system sets RPATH via `build.zig:313`
- No `DYLD_LIBRARY_PATH` needed for production binaries
- Test binaries require `DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin`

**Install Names** (CRITICAL):
- Must use `install_name_tool -id "@rpath/libenry.dylib"` after lipo
- The `@rpath/` prefix tells dyld to search RPATH directories
- Without `@rpath/`, dyld only searches system paths and current directory
- Without any install_name_tool call, dyld looks for `libenry.dylib.arm64` and fails

### Linux

**Architecture**: amd64 only (arm64 support possible but not implemented)

**Size**: ~11MB

**Dynamic Linking**:
- RPATH set via build.zig
- Test binaries require `LD_LIBRARY_PATH=vendor/go-enry/.shared/linux`

**Distribution**: Package `.so` file alongside executable or use system library paths

### Windows

**Architecture**: amd64 only

**Size**: ~10MB

**Dynamic Linking**:
- Windows searches current directory, then PATH
- Place `libenry.dll` in same directory as `vimcraft.exe`
- Or add to PATH

## Testing

### Running Tests

```bash
# macOS
DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin zig build test

# Linux
LD_LIBRARY_PATH=vendor/go-enry/.shared/linux zig build test

# Check specific test file
DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin zig test src/editor/treesitter/loader.zig
```

### Test Coverage

**loader.zig** contains 28 comprehensive tests covering:

1. **Basic Detection** (6 tests):
   - Extension-based detection (.rs, .js, .py, .zig, .go)
   - Exact filename matching (.Rprofile, Makefile)
   - Glob pattern matching (*.config.js)

2. **Shebang Detection** (4 tests):
   - JavaScript shebangs (node, nodejs)
   - Python shebangs (python, python3, python2)
   - Shebangs with arguments
   - Various shell shebangs (bash, zsh, sh)

3. **Content-Based Detection** (3 tests):
   - Disambiguate .h files (C vs C++ vs Objective-C)
   - Disambiguate .m files (Objective-C vs MATLAB)
   - Disambiguate .rs files (Rust vs RenderScript)

4. **Modeline Detection** (2 tests):
   - Vim modelines (ft=python, syntax=javascript)
   - Emacs modelines (mode: python)

5. **Edge Cases** (5 tests):
   - Empty files
   - Files with no extension but shebang
   - Multiple detection strategies combined
   - Unknown filetypes
   - Paths with directories

6. **Pattern Matching** (2 tests):
   - GlobPattern exact match
   - GlobPattern wildcard match

### Expected Results

- **188/190 tests passed** (as of November 2025)
- 1 skipped test (unrelated to go-enry)
- 1 failing test: `cursorline_test` (pre-existing, unrelated to go-enry)

All go-enry-specific tests pass successfully.

## Troubleshooting

### Build Issues

**Error: "Go is not installed"**

```bash
# Install Go from https://golang.org/dl/
brew install go  # macOS
sudo apt install golang-go  # Ubuntu/Debian
```

**Error: "Go version too old"**

go-enry requires Go 1.18+ for generics support:

```bash
go version  # Check current version
# Upgrade via system package manager or download from golang.org
```

**Error: "lipo: can't open input file"**

The arm64 or amd64 build failed. Check Go and CGO are properly configured:

```bash
go env CGO_ENABLED  # Should be "1"
```

### Runtime Issues

**Error: "Library not loaded: libenry.dylib"**

**Root Cause**: The dylib's install name is missing the `@rpath/` prefix, so dyld doesn't search RPATH directories.

**Solution 1** (fix the dylib - RECOMMENDED):

```bash
# Check current install name
otool -L vendor/go-enry/.shared/darwin/libenry.dylib | head -3
# Should show: @rpath/libenry.dylib

# If it shows just "libenry.dylib", fix it:
install_name_tool -id "@rpath/libenry.dylib" vendor/go-enry/.shared/darwin/libenry.dylib

# Rebuild executable
zig build

# Verify fix
./zig-out/bin/vimc --version  # Should work without DYLD_LIBRARY_PATH
```

**Solution 2** (workaround for development):

```bash
# macOS
export DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin

# Linux
export LD_LIBRARY_PATH=vendor/go-enry/.shared/linux
```

**Solution 3** (production deployment - copy dylib to app bundle):

```bash
# macOS
install_name_tool -add_rpath @executable_path/../lib vimcraft

# Linux
patchelf --set-rpath '$ORIGIN/../lib' vimcraft
```

**Error: "invalid cpu architecture: x86_64" (macOS)**

You built a single-architecture binary instead of universal. Rebuild with:

```bash
./scripts/build-enry.sh darwin
lipo -info vendor/go-enry/.shared/darwin/libenry.dylib
# Should show: x86_64 arm64
```

**Error: "Language detection returning null for known files"**

Enable debug logging to diagnose:

```bash
# Set Zig log level
export ZIG_LOG_LEVEL=debug
./zig-out/bin/vimcraft file.py
# Check for "go-enry detectLanguage failed" messages
```

### Test Issues

**Error: "dyld: Library not loaded" during tests**

Tests need explicit library path:

```bash
# WRONG (will fail)
zig build test

# CORRECT
DYLD_LIBRARY_PATH=vendor/go-enry/.shared/darwin zig build test
```

**Error: "Expected 'Python', found 'python'"**

go-enry returns capitalized language names. Update test assertions:

```zig
// WRONG
try std.testing.expectEqualStrings("python", filetype.?);

// CORRECT
try std.testing.expectEqualStrings("Python", filetype.?);
```

## References

- **go-enry repository**: https://github.com/go-enry/go-enry
- **GitHub Linguist**: https://github.com/github/linguist
- **Vimcraft source**:
  - `src/system/enry/enry.zig` - High-level API
  - `src/system/enry/c_api.zig` - C FFI layer
  - `src/editor/treesitter/loader.zig` - Usage example
  - `scripts/build-enry.sh` - Build automation

## Contributing

When modifying go-enry integration:

1. Update error handling if adding new extern functions
2. Add validation for all @intCast operations
3. Write comprehensive tests (see loader.zig for examples)
4. Update this documentation if changing build process
5. Test on all platforms (macOS, Linux, Windows if possible)

### Code Review Checklist

- [ ] All extern functions have corresponding Zig wrappers
- [ ] Input validation before @intCast (check bounds)
- [ ] Proper error propagation (no silent failures)
- [ ] Memory management uses arena allocator
- [ ] Platform-specific paths in build.zig
- [ ] Tests pass on macOS and Linux
- [ ] Documentation updated
