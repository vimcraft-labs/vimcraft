# Phase 4: vim.opt Design Document

## Overview

Implement a full Neovim-compatible options system with 80+ options.

## Architecture

### 1. Options Manager (Zig)

**File**: `src/editor/config/options.zig`

```zig
pub const OptionType = enum {
    boolean,
    number,
    string,
};

pub const OptionValue = union(OptionType) {
    boolean: bool,
    number: i64,
    string: []const u8,
};

pub const OptionMeta = struct {
    name: []const u8,
    short_name: ?[]const u8,  // 'nu' for 'number'
    type: OptionType,
    default: OptionValue,
    scope: enum { global, buffer, window },
};

pub const OptionsManager = struct {
    allocator: std.mem.Allocator,
    options: std.StringHashMap(OptionValue),

    pub fn init(allocator: std.mem.Allocator) OptionsManager;
    pub fn deinit(self: *OptionsManager) void;

    pub fn set(self: *OptionsManager, name: []const u8, value: OptionValue) !void;
    pub fn get(self: *OptionsManager, name: []const u8) ?OptionValue;
    pub fn reset(self: *OptionsManager, name: []const u8) !void;
};
```

### 2. Option Definitions

**File**: `src/editor/config/option_defs.zig`

Pre-defined metadata for all options:

```zig
pub const OPTIONS = [_]OptionMeta{
    .{ .name = "number", .short_name = "nu", .type = .boolean, .default = .{ .boolean = false }, .scope = .buffer },
    .{ .name = "relativenumber", .short_name = "rnu", .type = .boolean, .default = .{ .boolean = false }, .scope = .buffer },
    .{ .name = "cursorline", .short_name = "cul", .type = .boolean, .default = .{ .boolean = false }, .scope = .window },
    .{ .name = "tabstop", .short_name = "ts", .type = .number, .default = .{ .number = 8 }, .scope = .buffer },
    // ... 80+ more options
};
```

### 3. JavaScript Proxy (vim.opt)

**File**: `src/system/jsi/runtime.js`

Dynamic proxy that handles any option:

```javascript
globalThis.vim = {
  opt: new Proxy({}, {
    get(target, prop) {
      // Call native getOption(prop)
      return __nativeGetOption(prop);
    },
    set(target, prop, value) {
      // Call native setOption(prop, value)
      __nativeSetOption(prop, value);
      return true;
    }
  }),

  // opt_local and opt_global for buffer/window scopes
  opt_local: new Proxy({}, { /* buffer-local options */ }),
  opt_global: new Proxy({}, { /* global options */ }),
};
```

### 4. JSI Bridge Functions

**File**: `src/system/jsi/config_api.zig`

```zig
export fn getOption(runtime: *Runtime, args: [*c]?*Value, count: usize) *Value {
    // 1. Extract option name from args[0]
    // 2. Look up in OptionsManager
    // 3. Convert OptionValue -> Hermes Value
    // 4. Return to JavaScript
}

export fn setOption(runtime: *Runtime, args: [*c]?*Value, count: usize) *Value {
    // 1. Extract name and value from args
    // 2. Convert Hermes Value -> OptionValue
    // 3. Store in OptionsManager
    // 4. Apply side effects (cursorline -> Display, etc.)
}
```

## Priority Options (Week 1-2)

### Display Options
- `number` / `nu` - Show line numbers
- `relativenumber` / `rnu` - Relative line numbers
- `cursorline` / `cul` - Highlight cursor line
- `signcolumn` / `scl` - Show sign column ("yes", "no", "auto")
- `colorcolumn` / `cc` - Highlight column

### Editing Options
- `tabstop` / `ts` - Tab width
- `shiftwidth` / `sw` - Indent width
- `expandtab` / `et` - Use spaces instead of tabs
- `autoindent` / `ai` - Copy indent from previous line
- `smartindent` / `si` - Smart autoindenting

### Behavior Options
- `mouse` - Enable mouse ("a" for all modes)
- `clipboard` - System clipboard integration
- `undolevels` / `ul` - Maximum undo levels
- `timeout` / `to` - Timeout for mappings
- `timeoutlen` / `tm` - Mapping timeout milliseconds

## Implementation Steps

### Step 1: Options Manager (Day 1-2)
1. Create `options.zig` with OptionsManager struct
2. Implement get/set/reset methods
3. Add unit tests for option storage

### Step 2: Option Definitions (Day 2-3)
1. Create `option_defs.zig` with 20 most common options
2. Add metadata (type, default, scope)
3. Document each option

### Step 3: JSI Bridge (Day 3-4)
1. Implement `getOption` and `setOption` native functions
2. Handle type conversions (bool, number, string)
3. Register with Hermes runtime

### Step 4: JavaScript Proxy (Day 4-5)
1. Replace hardcoded vim.opt with Proxy
2. Support both camelCase and lowercase
3. Add vim.opt_local and vim.opt_global

### Step 5: Integration (Day 5-6)
1. Wire OptionsManager into Editor
2. Apply side effects (e.g., cursorline -> Display)
3. Test with real config files

### Step 6: Documentation (Day 6-7)
1. Document all options in docs/api/options.md
2. Add examples to docs/examples/
3. Update CLAUDE.md

## Testing Strategy

### Unit Tests (Zig)
```zig
test "OptionsManager: set/get boolean" {
    var mgr = OptionsManager.init(allocator);
    defer mgr.deinit();

    try mgr.set("number", .{ .boolean = true });
    const value = mgr.get("number").?;
    try std.testing.expect(value.boolean == true);
}
```

### Integration Tests (JavaScript)
```javascript
// Test via debug protocol
vim.opt.number = true;
vim.opt.relativenumber = false;
vim.opt.tabstop = 4;

assert(vim.opt.number === true);
assert(vim.opt.tabstop === 4);
```

## Success Criteria

- ✅ 20+ options implemented (Phase 4 Week 1-2)
- ✅ vim.opt Proxy works for all options
- ✅ Type conversions work (bool, number, string)
- ✅ Side effects apply (cursorline updates display)
- ✅ Both camelCase and lowercase supported
- ✅ Unit tests pass
- ✅ Integration tests pass

## Future Enhancements (Phase 4 Week 3+)

- Buffer-local options (vim.opt_local)
- Window-local options (vim.wo)
- Option watchers (callbacks on change)
- :set command support
- Option completion in command mode
