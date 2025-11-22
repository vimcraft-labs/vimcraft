# TypeScript Plugin Development Toolchain

**Status**: Design Phase (January 2025)
**Goal**: Production-ready TypeScript development experience for Vimcraft plugins

---

## Overview

Vimcraft's TypeScript toolchain provides a **Bun-like development experience** for plugin authors with zero-config setup, type safety, and fast iteration cycles.

### Design Principles

1. **Zero-Config by Default** - Works out-of-box after `vimcraft` first run
2. **Type-First** - Full IntelliSense for `vim.*` API via `@vimcraft/types`
3. **Fast Iteration** - `vimc run plugin.ts` executes instantly (no build step visible)
4. **Package Management** - Simple install/uninstall like `npm` but Vimcraft-native
5. **Developer Experience** - Match quality of VS Code + TypeScript

---

## Architecture

### Directory Structure

```
~/.config/vimcraft/
├── index.ts                          # User config (auto-transpiled on load)
├── tsconfig.json                    # TypeScript compiler options (auto-generated)
├── @vimcraft/                       # Vimcraft official packages
│   └── types/                       # @vimcraft/types package
│       ├── package.json             # Package metadata
│       └── index.d.ts               # Vim API type definitions
├── plugins/                         # User-installed plugins
│   ├── smear-cursor/                # Example: npm-style package
│   │   ├── package.json
│   │   ├── index.ts
│   │   └── node_modules/ -> ../../node_modules  # Symlink to shared deps
│   └── gruvbox-theme/
│       ├── package.json
│       └── index.ts
├── node_modules/                    # Shared dependencies (optional)
│   └── @types/                      # Additional type definitions
└── .vimcraft/                       # Internal metadata (gitignored)
    ├── cache/                       # Bytecode cache (~/.cache/vimcraft/bytecode)
    ├── installed.json               # Installed packages registry
    └── lock.json                    # Dependency lock file
```

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Plugin Developer                          │
│  (writes TypeScript, gets full IntelliSense)                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      vimc CLI Tool                           │
│  - vimc init           (setup ~/.config/vimcraft)            │
│  - vimc run script.ts  (execute with vim.* globals)          │
│  - vimc install pkg    (install to plugins/)                 │
│  - vimc uninstall pkg  (remove from plugins/)                │
│  - vimc list           (show installed plugins)              │
│  - vimc types          (regenerate @vimcraft/types)          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              TypeScript Transpiler (esbuild)                 │
│  - TypeScript → JavaScript (instant)                         │
│  - Source maps (for debugging)                               │
│  - Tree-shaking (dead code elimination)                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│            Hermes Bytecode Compiler (hermesc)                │
│  - JavaScript → HBC bytecode                                 │
│  - WyHash-based caching                                      │
│  - Cache hit: ~0.3ms, miss: ~2.5ms                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Vimcraft Runtime                            │
│  - Hermes JS engine                                          │
│  - JSI bridge (vim.* globals)                                │
│  - require() for plugin composition                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Features

### 1. Auto-Initialization (`vimc init`)

**When it runs**:
- Automatically on first `vimcraft` launch (if `~/.config/vimcraft/` doesn't exist)
- Manually via `vimc init --force` (recreates setup)

**What it creates**:

#### `~/.config/vimcraft/tsconfig.json`
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "lib": ["ES2020"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "types": ["@vimcraft/types"],
    "baseUrl": ".",
    "paths": {
      "@vimcraft/types": ["@vimcraft/types"]
    }
  },
  "include": [
    "index.ts",
    "plugins/**/*.ts"
  ],
  "exclude": [
    "node_modules",
    ".vimcraft"
  ]
}
```

**Key Settings**:
- `target: ES2020` - Modern JavaScript (Hermes supports ES2015+)
- `module: CommonJS` - For `require()` compatibility
- `types: ["@vimcraft/types"]` - Auto-import Vim API types
- `strict: true` - Maximum type safety

#### `~/.config/vimcraft/index.ts` (if doesn't exist)
```typescript
// Vimcraft Configuration
// This file is auto-loaded on startup

// Example: Set color scheme
vim.opt.number = true;
vim.opt.relativenumber = true;

// Example: Custom key mapping (Phase 4)
// vim.keymap.set('n', '<leader>w', () => {
//   console.log('Custom mapping!');
// });

// Example: Load plugin
// const smearCursor = require('@vimcraft/smear-cursor');
// smearCursor.setup({ speed: 0.3 });
```

#### `~/.config/vimcraft/@vimcraft/types/` (copy from source)
- Copies from `src/system/jsi/@vimcraft/types/` (source of truth)
- `package.json` with version
- `index.d.ts` with all vim.* type definitions

**Implementation**: `src/tools/vimc/init.zig` (new file)

---

### 2. Plugin Execution (`vimc run`)

**Usage**:
```bash
vimc run my-plugin.ts              # Execute plugin with vim.* globals
vimc run my-plugin.ts --debug      # Enable Chrome DevTools debugging
vimc run my-plugin.ts --no-cache   # Force re-transpile (skip cache)
```

**What it does**:
1. Transpile TypeScript → JavaScript (esbuild)
2. Wrap with `runtime.js` (inject vim.* globals)
3. Compile to Hermes bytecode (hermesc)
4. Execute in Hermes runtime
5. Print output to stdout

**Example**:
```typescript
// test-plugin.ts
console.log('Cursor position:', vim.getCursor());
vim.opt.number = true;
console.log('Line numbers:', vim.opt.number);
```

```bash
$ vimc run test-plugin.ts
Cursor position: { row: 0, col: 0 }
Line numbers: true
```

**Implementation**: `src/tools/vimc/run.zig`

**Key Features**:
- ✅ Full vim.* API available (motion, opt, layer, etc.)
- ✅ `require()` works (can load other modules)
- ✅ `console.log()` outputs to terminal
- ✅ Source maps for debugging (line numbers in errors)
- ✅ Fast iteration (cache hit = 0.3ms)

---

### 3. Package Management (`vimc install/uninstall`)

**Goal**: npm-like workflow, but Vimcraft-native (no npm/bun/node required)

#### Install from Git Repository

```bash
vimc install https://github.com/user/vimcraft-smear-cursor.git
# Clones to ~/.config/vimcraft/plugins/vimcraft-smear-cursor/
# Parses package.json for dependencies
# Installs dependencies recursively
# Adds entry to ~/.config/vimcraft/.vimcraft/installed.json
```

#### Install from Local Directory

```bash
vimc install ~/my-plugins/gruvbox-theme
# Symlinks to ~/.config/vimcraft/plugins/gruvbox-theme
# (useful for plugin development)
```

#### Uninstall

```bash
vimc uninstall vimcraft-smear-cursor
# Removes ~/.config/vimcraft/plugins/vimcraft-smear-cursor/
# Updates installed.json
```

#### List Installed Plugins

```bash
vimc list
# Installed Plugins:
#   - vimcraft-smear-cursor@0.1.0 (https://github.com/user/vimcraft-smear-cursor.git)
#   - gruvbox-theme@1.0.0 (local: ~/my-plugins/gruvbox-theme)
```

**Implementation**: `src/tools/vimc/package.zig`

**Registry Format** (`~/.config/vimcraft/.vimcraft/installed.json`):
```json
{
  "plugins": [
    {
      "name": "vimcraft-smear-cursor",
      "version": "0.1.0",
      "source": "https://github.com/user/vimcraft-smear-cursor.git",
      "installed_at": "2025-01-20T10:30:00Z"
    },
    {
      "name": "gruvbox-theme",
      "version": "1.0.0",
      "source": "local:~/my-plugins/gruvbox-theme",
      "installed_at": "2025-01-20T11:00:00Z"
    }
  ]
}
```

---

### 4. Type Definitions (`vimc types`)

**Usage**:
```bash
vimc types                # Regenerate @vimcraft/types from source
vimc types --check        # Verify types are up-to-date
```

**What it does**:
1. Reads JSI API definitions from source (`src/system/jsi/*_api.zig`)
2. Generates TypeScript definitions (`index.d.ts`)
3. Writes to `~/.config/vimcraft/@vimcraft/types/`
4. Bumps version in `package.json`

**Auto-Generation** (future):
- Parse Zig host function signatures
- Extract parameter types, return types
- Generate TypeScript interface definitions
- No manual sync needed (source of truth = Zig code)

**Manual Approach** (Phase 4):
- Manually maintain `src/system/jsi/@vimcraft/types/index.d.ts`
- Copy to `~/.config/vimcraft/@vimcraft/types/` on `vimc init`
- Update version when API changes

**Implementation**: `src/tools/vimc/types.zig`

---

## Development Workflow

### Plugin Author Experience

**Step 1: Initialize Development Environment**
```bash
cd ~/my-vimcraft-plugins
vimc init  # Creates tsconfig.json, types/
```

**Step 2: Create Plugin**
```bash
mkdir smear-cursor
cd smear-cursor
cat > package.json << EOF
{
  "name": "vimcraft-smear-cursor",
  "version": "0.1.0",
  "main": "index.ts"
}
EOF

cat > index.ts << EOF
// Smear cursor plugin for Vimcraft
export function setup(opts: { speed?: number } = {}) {
  const speed = opts.speed ?? 0.5;

  vim.requestAnimationFrame((t) => {
    const cursor = vim.getCursor();
    // Implement smear animation
    console.log('Cursor at:', cursor);
  });
}
EOF
```

**Step 3: Test Plugin Locally**
```bash
vimc run index.ts  # Quick test
# Cursor at: { row: 0, col: 0 }
```

**Step 4: Install Plugin to Vimcraft**
```bash
vimc install ~/my-vimcraft-plugins/smear-cursor
# Plugin installed: vimcraft-smear-cursor@0.1.0
```

**Step 5: Use in index.ts**
```typescript
// ~/.config/vimcraft/index.ts
const smearCursor = require('vimcraft-smear-cursor');
smearCursor.setup({ speed: 0.3 });
```

**Step 6: Publish (future - Phase 5)**
```bash
vimc publish  # Pushes to Vimcraft registry
```

---

## TypeScript Integration

### VS Code Setup

**Automatic** (if using `vimc init`):
1. VS Code detects `tsconfig.json`
2. Loads `@vimcraft/types` from `~/.config/vimcraft/`
3. Provides IntelliSense for `vim.*` API

**IntelliSense Example**:
```typescript
vim.opt.  // <- Autocomplete shows: number, relativenumber, cursorline, ...
vim.motion.  // <- Autocomplete shows: left, right, up, down, wordForward, ...
vim.layer.  // <- Autocomplete shows: create, setText, clear, setEnabled, ...
```

### Error Checking

**Type Errors**:
```typescript
vim.opt.number = "yes";  // ❌ Error: Type 'string' is not assignable to type 'boolean'
vim.motion.invalid();    // ❌ Error: Property 'invalid' does not exist on type 'motion'
```

**Runtime Errors**:
```bash
$ vimc run bad-plugin.ts
[ERROR] TypeError: vim.motion.invalid is not a function
  at bad-plugin.ts:3:5
```

---

## Implementation Plan

### Phase 4.1: Core Infrastructure (NEXT - 1 week)

**Files to Create**:
- [ ] `src/tools/vimc/main.zig` - CLI entry point
- [ ] `src/tools/vimc/init.zig` - `vimc init` command
- [ ] `src/tools/vimc/run.zig` - `vimc run` command
- [ ] `src/tools/vimc/package.zig` - Package manager
- [ ] `src/tools/vimc/types.zig` - Type generator
- [ ] `src/system/jsi/@vimcraft/types/index.d.ts` - Source of truth for types

**Tasks**:
1. ✅ TypeScript transpiler working (esbuild integration done)
2. ✅ Bytecode caching working (WyHash-based)
3. 🚧 Build `vimc` CLI tool
4. 🚧 Implement `vimc init` (copy types, generate tsconfig.json)
5. 🚧 Implement `vimc run` (execute with vim.* globals)
6. 🚧 Test workflow: `vimc init` → write plugin → `vimc run`

### Phase 4.2: Package Management (2-3 weeks)

**Tasks**:
1. 🚧 Implement `vimc install <git-url>`
2. 🚧 Implement `vimc uninstall <plugin>`
3. 🚧 Implement `vimc list`
4. 🚧 Dependency resolution (parse package.json)
5. 🚧 Lock file generation (installed.json)

### Phase 4.3: Type Generation (1 week)

**Tasks**:
1. 🚧 Implement `vimc types` (copy from source)
2. 🚧 Manual type maintenance workflow
3. 📅 Auto-generation from Zig (Phase 5 - requires Zig AST parsing)

### Phase 4.4: Developer Experience (1 week)

**Tasks**:
1. 🚧 Source map support (error line numbers)
2. 🚧 Watch mode (`vimc run --watch`)
3. 🚧 Plugin scaffolding (`vimc new my-plugin`)
4. 🚧 Documentation generator (`vimc docs`)

---

## Comparison with Other Ecosystems

| Feature | Vimcraft (vimc) | npm | Bun | Neovim (Lua) |
|---------|-----------------|-----|-----|--------------|
| **TypeScript** | ✅ First-class | ⚠️ via tsc | ✅ Native | ❌ Lua only |
| **Zero-config** | ✅ `vimc init` | ❌ Requires setup | ✅ Zero-config | ⚠️ Manual |
| **Package Manager** | ✅ Built-in | ✅ npm | ✅ Built-in | ⚠️ External (packer, lazy) |
| **Type Definitions** | ✅ Auto-bundled | ⚠️ Manual (@types) | ✅ Auto-bundled | ❌ No types |
| **Fast Execution** | ✅ Bytecode cache | ⚠️ Slow (Node.js) | ✅ Fast (JSC) | ✅ LuaJIT |
| **Plugin Registry** | 📅 Phase 5 | ✅ npmjs.com | ✅ npm registry | ⚠️ GitHub only |
| **IntelliSense** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Limited |

**Key Insight**: Vimcraft matches **Bun's developer experience** while maintaining **Neovim's simplicity**.

---

## Security Considerations

### Plugin Sandboxing (Phase 5)

**Threat Model**:
- Malicious plugins can access filesystem
- Malicious plugins can execute arbitrary code
- Malicious plugins can steal credentials

**Mitigation**:
1. **Permission System** (like Deno):
   ```typescript
   // Plugin declares required permissions in package.json
   {
     "permissions": {
       "read": ["~/.config/vimcraft/"],
       "write": ["~/.local/share/vimcraft/"],
       "network": false
     }
   }
   ```

2. **JSI Access Control**:
   - Plugins run in restricted Hermes context
   - Can only access vim.* APIs (no fs, no process, no network)
   - `require()` only loads from `~/.config/vimcraft/plugins/`

3. **Code Signing** (Phase 6):
   - Official plugins signed by Vimcraft
   - Third-party plugins show security warning

---

## Migration Path from Neovim

### For Plugin Authors

**Neovim Lua**:
```lua
-- Neovim plugin
local M = {}

function M.setup(opts)
  vim.opt.number = true
  vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
      print("Cursor moved!")
    end
  })
end

return M
```

**Vimcraft TypeScript**:
```typescript
// Vimcraft plugin
export function setup(opts: { speed?: number } = {}) {
  vim.opt.number = true;
  vim.on("CursorMoved", () => {
    console.log("Cursor moved!");
  });
}
```

**Key Differences**:
- `vim.api.*` → `vim.*` (simpler namespace)
- `vim.fn.*` → `vim.motion.*` (organized by domain)
- `nvim_create_autocmd` → `vim.on` (event emitter pattern)
- Lua tables → TypeScript objects (type-safe)

---

## Future Enhancements

### Phase 5: Advanced Features

- [ ] **Plugin Registry** (vimcraft.dev/plugins)
- [ ] **Auto-Updates** (`vimc update`)
- [ ] **Dependency Lock Files** (lock.json)
- [ ] **Workspace Support** (multi-project tsconfig)
- [ ] **Hot Reload** (live config updates without restart)

### Phase 6: Ecosystem

- [ ] **Plugin Marketplace** (web UI for browsing)
- [ ] **Plugin Templates** (`vimc new --template smear-cursor`)
- [ ] **CI/CD Integration** (GitHub Actions for plugin testing)
- [ ] **Documentation Generator** (auto-generate docs from TSDoc)
- [ ] **LSP Integration** (vim-language-server for Vimcraft config)

---

## Success Metrics

**Developer Satisfaction**:
- ✅ Zero-config setup (<30 seconds from `vimc init` to first plugin)
- ✅ Full IntelliSense in VS Code
- ✅ Fast iteration cycle (<1 second from save to test)
- ✅ npm-like package management (familiar workflow)

**Performance**:
- ✅ Cache hit: <1ms (bytecode load)
- ✅ Cache miss: <5ms (transpile + compile + cache)
- ✅ Plugin load time: <10ms (startup cost)

**Ecosystem Health** (Phase 5+):
- 📅 100+ plugins in registry (6 months)
- 📅 10+ official plugins (@vimcraft/*)
- 📅 5+ community plugins with >100 downloads

---

## References

- **esbuild**: https://esbuild.github.io/ (TypeScript transpiler)
- **Hermes**: https://hermesengine.dev/ (JavaScript engine)
- **Bun**: https://bun.sh/ (inspiration for developer experience)
- **Deno**: https://deno.land/ (inspiration for permissions system)
- **Neovim**: https://neovim.io/ (API compatibility target)

---

**Status**: Design complete, ready for implementation
**Next Step**: Build `vimc` CLI tool (Phase 4.1)
