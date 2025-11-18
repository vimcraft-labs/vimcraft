# vim.filetype API

Filetype detection API compatible with Neovim's `vim.filetype` namespace.

## Overview

The `vim.filetype` API provides comprehensive filetype detection using Neovim's database of 1,437+ compile-time mappings. Detection uses a four-tier system for maximum accuracy and performance.

**Status**: ✅ Complete (Phase 3 - Tree-sitter Integration)

## API Reference

### vim.filetype.match(opts)

Detects filetype from filename or buffer content.

**Parameters**:
- `opts` (object) - Detection options
  - `opts.filename` (string) - File path to detect
  - `opts.buf` (number) - Buffer number (0 for current buffer)

**Returns**:
- `string` - Detected filetype (e.g., "rust", "javascript")
- `null` - Unknown filetype or invalid input

**Examples**:

```javascript
// Extension-based detection (Tier 1 - O(1) lookup)
vim.filetype.match({ filename: "main.rs" })        // "rust"
vim.filetype.match({ filename: "app.js" })         // "javascript"
vim.filetype.match({ filename: "build.zig" })      // "zig"

// Exact filename detection (Tier 2 - O(1) lookup)
vim.filetype.match({ filename: "Makefile" })       // "make"
vim.filetype.match({ filename: "Dockerfile" })     // "dockerfile"
vim.filetype.match({ filename: "Cargo.toml" })     // "toml"

// Paths with directories (basename extracted automatically)
vim.filetype.match({ filename: "/path/to/main.rs" })  // "rust"
vim.filetype.match({ filename: "src/lib.zig" })       // "zig"

// Current buffer detection (uses filepath + shebang if available)
vim.filetype.match({ buf: 0 })  // detects filetype for current buffer

// Unknown filetypes return null
vim.filetype.match({ filename: "unknown.xyz" })  // null
vim.filetype.match({ filename: "" })             // null
```

## Detection Tiers

The filetype detector uses a four-tier system (same as Neovim):

### Tier 1: Extension Lookup (O(1))
- Uses compile-time `StaticStringMap` with 1,066 extension mappings
- Extracted from Neovim's `runtime/lua/vim/filetype.lua`
- Examples: `.rs` → `rust`, `.js` → `javascript`, `.zig` → `zig`

### Tier 2: Exact Filename Lookup (O(1))
- Uses compile-time `StaticStringMap` with 371 filename mappings
- Handles special files like `Makefile`, `Dockerfile`, `.gitignore`
- Examples: `Makefile` → `make`, `.bashrc` → `sh`

### Tier 3: Glob Pattern Matching
- Custom glob patterns for advanced matching
- Examples: `*.config.js` → `javascript`, `*.test.js` → `javascript`

### Tier 4: Shebang Detection
- Parses first line for interpreter (e.g., `#!/usr/bin/env node`)
- Supports patterns: `/usr/bin/env <interpreter>`, `/usr/bin/<interpreter>`
- Examples: `#!/usr/bin/env node` → `javascript`, `#!/usr/bin/python3` → `python`

## Implementation Details

### Architecture

```
JavaScript                          Zig (Native)
-----------                         ------------
vim.filetype.match(opts)  →  JSI  → vim_filetype_match()
                                    ↓
                              editor.ts_loader.detectFiletype()
                                    ↓
                              filetype_data.zig (compile-time)
```

### Performance

- **Tier 1 (Extension)**: O(1) hash lookup, ~5-10ns
- **Tier 2 (Filename)**: O(1) hash lookup, ~5-10ns
- **Tier 3 (Glob)**: O(n) pattern matching, ~100-500ns
- **Tier 4 (Shebang)**: O(1) hash lookup after parsing, ~50-100ns

All mappings are compile-time initialized (`std.StaticStringMap.initComptime()`), resulting in zero runtime allocation and maximum performance.

### Data Source

All filetype mappings are automatically extracted from Neovim's source at build time:

- **Source**: `vendor/neovim/runtime/lua/vim/filetype.lua`
- **Generator**: `scripts/generate_filetype_data.zig`
- **Output**: `.zig-cache/*/filetype_data.zig` (compile-time data)
- **Regeneration**: Automatic when Neovim submodule updates

See [CLAUDE.md](../../CLAUDE.md#filetype-data-generation-compile-time) for build system details.

## Coverage

### Supported Languages (1,437+ mappings)

**Systems Languages**:
- C, C++, Rust, Zig, Go, D, Nim, Odin

**Scripting Languages**:
- JavaScript, TypeScript, Python, Ruby, Lua, Perl, PHP

**Web Technologies**:
- HTML, CSS, SCSS, LESS, JSON, YAML, TOML, XML

**Configuration Files**:
- Makefile, Dockerfile, .gitignore, .bashrc, Cargo.toml

**And 100+ more languages** - See `filetype_data.zig` for complete list

## Neovim Compatibility

**Compatible**:
- ✅ `vim.filetype.match({ filename: "..." })` - Exact API match
- ✅ `vim.filetype.match({ buf: 0 })` - Buffer detection
- ✅ Extension detection (Tier 1)
- ✅ Exact filename detection (Tier 2)
- ✅ Shebang detection (Tier 4)

**Not Yet Implemented**:
- ❌ `vim.filetype.match({ contents: [...] })` - Content-based detection
- ❌ `vim.filetype.add()` - Runtime filetype registration
- ❌ Lua pattern matching (uses glob patterns instead)

## Use Cases

### Syntax Highlighting

```javascript
// Auto-detect and set filetype for tree-sitter
const filetype = vim.filetype.match({ buf: 0 });
if (filetype) {
    vim.bo.filetype = filetype;
    console.log(`Detected filetype: ${filetype}`);
}
```

### Custom File Handlers

```javascript
// Route files to custom handlers based on filetype
function handleFile(filename) {
    const ft = vim.filetype.match({ filename });

    if (ft === "rust") {
        // Enable Rust-specific features
        setupRustAnalyzer();
    } else if (ft === "javascript" || ft === "typescript") {
        // Enable JS/TS features
        setupTSServer();
    }
}
```

### Build System Integration

```javascript
// Detect build files
const isBuildFile = (filename) => {
    const ft = vim.filetype.match({ filename });
    return ft === "make" || ft === "cmake" ||
           filename.includes("build.zig") ||
           filename.includes("Cargo.toml");
};
```

## Testing

See `examples/filetype-demo.js` for comprehensive test examples.

Run the demo:
```bash
./zig-out/bin/vimcraft examples/filetype-demo.js
# (Note: Requires config loading support - coming in Phase 4)
```

## Related APIs

- `vim.bo.filetype` - Buffer-local filetype option (read/write)
- `vim.treesitter.language` - Tree-sitter language registration
- `vim.api.buf_get_name()` - Get buffer filename (future API)

## References

- Neovim source: `runtime/lua/vim/filetype.lua`
- Implementation: `src/system/jsi/filetype_api.zig`
- Loader: `src/editor/treesitter/loader.zig`
- Generated data: `.zig-cache/*/filetype_data.zig`

---

**Last Updated**: January 2025 (Phase 3 - Tree-sitter Integration)
