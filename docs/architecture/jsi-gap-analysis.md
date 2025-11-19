# JSI Architecture Gap Analysis: React Native vs Vimcraft

**Date**: January 2025
**Purpose**: Identify critical JSI features from React Native that Vimcraft might need for Phase 4-7

## Executive Summary

**Status**: ✅ Core JSI features complete, 🚧 **3 critical gaps** for Phase 4, 📅 Several nice-to-haves for Phase 5+

**Critical gaps** (needed for Phase 4):
1. ❌ **Event emitters** (Native → JS events) - NEEDED for autocommands
2. ❌ **Module system** (require/import) - NEEDED for plugin loading
3. ⚠️ **Error throwing** (JS exceptions from C++) - Would improve error handling

**Assessment**: Current implementation is solid for basic JSI, but **event emitters and module loading are blockers for Phase 4 autocommands and plugin system**.

---

## Comparison Matrix

| Feature | React Native JSI | Vimcraft JSI | Phase 4 Need | Priority |
|---------|-----------------|--------------|--------------|----------|
| **Core Infrastructure** |
| HostObject (zero-copy) | ✅ | ✅ | ✅ | - |
| HostFunction | ✅ | ✅ | ✅ | - |
| External ArrayBuffer | ✅ | ✅ | ✅ | - |
| Value conversion | ✅ | ✅ | ✅ | - |
| Version tracking | ✅ | ✅ | ✅ | - |
| **Error Handling** |
| Exception detection | ✅ | ✅ | ✅ | - |
| Exception messages | ✅ | ✅ | ✅ | - |
| Throw JS exceptions from C++ | ✅ | ❌ | ⚠️ | **HIGH** |
| Error boundaries | ✅ | ❌ | ✅ | **HIGH** |
| Stack traces | ✅ | ⚠️ | ⚠️ | Medium |
| **Event System** |
| Event emitters (Native → JS) | ✅ | ❌ | ✅ | **CRITICAL** |
| Event listeners | ✅ | ❌ | ✅ | **CRITICAL** |
| Custom events | ✅ | ❌ | ✅ | **CRITICAL** |
| **Module System** |
| require() / import | ✅ | ❌ | ✅ | **CRITICAL** |
| Module caching | ✅ | ❌ | ✅ | **HIGH** |
| Circular dependency handling | ✅ | ❌ | ⚠️ | Medium |
| **Async Operations** |
| Promises | ✅ | ⚠️ | ⚠️ | Medium |
| setTimeout/setInterval | ✅ | ✅ | ✅ | - |
| Microtask queue | ✅ | ❌ | ⚠️ | Low |
| **Memory Management** |
| Finalizers (ArrayBuffer) | ✅ | ✅ | ✅ | - |
| WeakRef | ✅ | ❌ | ❌ | Low |
| FinalizationRegistry | ✅ | ❌ | ❌ | Low |
| Memory pressure handling | ✅ | ❌ | ❌ | Low |
| **Performance** |
| TurboModules (lazy loading) | ✅ | ❌ | ⚠️ | Medium |
| Bytecode compilation | ✅ | ✅ | ✅ | - |
| Performance monitoring | ✅ | ❌ | ❌ | Low |
| **Debugging** |
| Chrome DevTools Protocol | ✅ | ✅ | ✅ | - |
| Breakpoints | ✅ | ⚠️ | ❌ | Low |
| Source maps | ✅ | ❌ | ❌ | Low |
| **Threading** |
| JavaScript thread | ✅ | ✅ | ✅ | - |
| Native threads | ✅ | ❌ | ❌ | Low |
| Thread-safe calls | ✅ | N/A | ❌ | Low |

**Legend**:
- ✅ Implemented and working
- ⚠️ Partially implemented or basic support
- ❌ Not implemented
- N/A Not applicable for Vimcraft

---

## CRITICAL Gaps (Blockers for Phase 4)

### 1. Event Emitters (Native → JS) ⭐⭐⭐

**What it is**: Mechanism for native code to trigger JavaScript callbacks asynchronously.

**Why React Native has it**:
- Native events (touch, gestures, sensors)
- Lifecycle events (app state changes)
- Asynchronous notifications
- Push-based updates

**Why Vimcraft needs it for Phase 4**:
```javascript
// NEEDED for autocommands (Phase 4)
vim.on('BufEnter', (bufnr) => {
    console.log('Entered buffer', bufnr);
});

vim.on('InsertLeave', () => {
    // Trigger LSP formatting
});

vim.on('TextChanged', () => {
    // Trigger incremental parsing
});
```

**Current workaround**: NONE - This is a blocker for autocommands!

**Implementation needed**:
- Event emitter infrastructure in Zig
- Registration mechanism (`vim.on(event, callback)`)
- Event firing from native code
- Callback storage and invocation

**Effort**: 3-5 days
**Priority**: **CRITICAL** (blocker for Phase 4 autocommands)

**React Native pattern**:
```cpp
// React Native example
auto eventEmitter = getEventEmitter();
eventEmitter->dispatchEvent("onChange", eventPayload);
```

**Vimcraft needs**:
```zig
// Proposed Vimcraft API
pub fn triggerAutocommand(self: *Editor, event: []const u8, args: anytype) !void {
    // Call registered JS callbacks for this event
    const callbacks = self.autocmd_callbacks.get(event);
    for (callbacks.items) |callback| {
        try self.jsi.callFunction(callback, args);
    }
}
```

---

### 2. Module System (require/import) ⭐⭐⭐

**What it is**: JavaScript module loading and caching system.

**Why React Native has it**:
- Load components on demand
- Organize code into modules
- Handle dependencies
- Enable npm packages

**Why Vimcraft needs it for Phase 4**:
```javascript
// NEEDED for plugin system (Phase 4)
// User's ~/.config/openvim/init.js
const lsp = require('./plugins/lsp');
const treesitter = require('./plugins/treesitter');
const statusline = require('./plugins/statusline');

lsp.setup({ ... });
treesitter.setup({ ... });
```

**Current limitation**: Single monolithic config file - plugins can't be split into modules.

**Implementation needed**:
- `require()` function implementation
- Module caching (don't reload twice)
- Relative path resolution (`./`, `../`)
- Module search paths (`node_modules` style)

**Effort**: 2-4 days
**Priority**: **CRITICAL** (blocker for multi-file plugins)

**React Native pattern**:
```javascript
// CommonJS module loading
const myModule = require('./myModule');
```

**Vimcraft needs**:
```zig
// Proposed implementation
pub fn require(runtime: *Runtime, module_path: []const u8) !*Value {
    // Check cache first
    if (runtime.module_cache.get(module_path)) |cached| {
        return cached;
    }

    // Load and evaluate module
    const module_code = try std.fs.cwd().readFileAlloc(alloc, module_path, 1024 * 1024);
    const result = try runtime.evaluateModule(module_code, module_path);

    // Cache for future requires
    try runtime.module_cache.put(module_path, result);
    return result;
}
```

---

### 3. Error Throwing (JS Exceptions from C++) ⭐⭐

**What it is**: Ability for host functions to throw JavaScript exceptions that calling code can catch.

**Why React Native has it**:
- Proper error handling in JS code
- Stack traces preserved
- try/catch works across native boundary

**Why Vimcraft needs it**:
```javascript
// Currently: Returns null on error (SILENT FAILURE!)
const line = vim.buffer.getLineContent(9999);  // Out of range
if (line === null) {  // User must remember to check!
    console.log("Line not found");
}

// BETTER: Throw exception (idiomatic JavaScript)
try {
    const line = vim.buffer.getLineContent(9999);
} catch (error) {
    console.log("Error:", error.message);  // "Line index out of range"
}
```

**Current workaround**: Return `null`, JavaScript must check manually (easy to forget!).

**Implementation needed**:
- C++ exception throwing via JSI
- Map Zig errors to JS exceptions
- Error message formatting
- Stack trace preservation

**Effort**: 1-2 days
**Priority**: **HIGH** (improves safety, not strictly required)

**React Native pattern**:
```cpp
// React Native example
if (index >= buffer.size()) {
    throw jsi::JSError(runtime, "Index out of range");
}
```

**Vimcraft needs**:
```zig
// Proposed pattern
pub export fn getLineContent(...) ?*c.OVHermesValue {
    const line_num = @as(usize, @intFromFloat(c.hermes_value_get_number(args[0])));

    if (line_num >= buffer.lineCount()) {
        // NEW: Throw JS exception instead of returning null
        c.hermes_throw_error(rt, "Line index out of range");
        return null;
    }

    const line = buffer.getLine(line_num);
    // ... rest of function
}
```

---

## HIGH Priority Gaps (Significant improvements)

### 4. Error Boundaries (Crash Isolation) ⭐⭐

**What it is**: Catch JavaScript errors without crashing entire application.

**Why React Native has it**:
- One component crash doesn't kill app
- Graceful degradation
- Error reporting

**Why Vimcraft needs it**:
```javascript
// Without error boundaries:
// One plugin crash → entire editor crashes

// With error boundaries:
try {
    pluginManager.loadPlugin('broken-plugin');
} catch (error) {
    console.error("Plugin failed to load:", error);
    // Editor continues running!
}
```

**Implementation needed**:
- Global try/catch around JS execution
- Error callback registration
- Graceful error recovery

**Effort**: 1-2 days
**Priority**: **HIGH** (plugin safety)

---

### 5. Module Caching ⭐⭐

**What it is**: Cache loaded modules to avoid re-evaluation.

**Why needed**: `require('./same-module')` called 100 times should only load once.

**Implementation**: Hash map of path → module exports.

**Effort**: Part of module system (included in item #2)
**Priority**: **HIGH** (performance)

---

## MEDIUM Priority Gaps (Nice-to-have for Phase 5+)

### 6. TurboModules (Lazy Loading)

**What it is**: Load modules only when first accessed.

**Why React Native has it**: Faster startup, lower memory footprint.

**Why Vimcraft might want it (Phase 5+)**: Don't load tree-sitter/LSP until first used.

**Effort**: 2-3 days
**Priority**: Medium (startup optimization)

---

### 7. Promises (Full Support)

**What it is**: Native Promise implementation for async operations.

**Current status**: JavaScript Promises work (Hermes supports them), but we don't create Promises from native code.

**Why might need**: LSP async operations, tree-sitter parsing.

**Implementation**: Hermes has Promise support, we just need to create them from C++.

**Effort**: 1-2 days
**Priority**: Medium (Phase 5 LSP)

---

### 8. Stack Traces (Enhanced)

**What it is**: Full stack traces with source locations.

**Current status**: Basic stack traces from Hermes.

**Enhancement needed**: Source maps, better formatting.

**Effort**: 2-3 days
**Priority**: Medium (debugging)

---

## LOW Priority Gaps (Phase 6+ or optional)

### 9. WeakRef / FinalizationRegistry

**What it is**: Advanced memory management APIs.

**Use case**: Caches that don't prevent garbage collection.

**Need**: Low (manual memory management works)

---

### 10. Memory Pressure Handling

**What it is**: Respond to low memory warnings.

**Use case**: Large files (>100MB), release caches.

**Need**: Low (Phase 6 optimization)

---

### 11. Performance Monitoring

**What it is**: Trace events, frame timing, bundle analysis.

**Use case**: Profiling plugin performance.

**Need**: Low (debugging tool)

---

### 12. Threading (Native Threads)

**What it is**: Background threads for expensive operations.

**Use case**: Tree-sitter parsing on background thread.

**Need**: Low (Vimcraft is single-threaded TUI)

---

## Implementation Roadmap

### Phase 4 Requirements (CRITICAL)

**Must implement before Phase 4**:

1. **Event Emitters** (3-5 days)
   - Core emitter infrastructure
   - `vim.on(event, callback)` registration
   - Event firing from Zig
   - Needed for: Autocommands, user events

2. **Module System** (2-4 days)
   - `require()` function
   - Module caching
   - Path resolution
   - Needed for: Multi-file plugins, code organization

3. **Error Throwing** (1-2 days) - OPTIONAL but highly recommended
   - Throw JS exceptions from host functions
   - Better error messages
   - try/catch support

**Total effort**: 6-11 days (or 7-13 with error throwing)

**Critical for**:
- vim.opt implementation ⚠️ (optional, better errors)
- vim.keymap.set/del ✅ (current impl works)
- Autocommands 🚨 (BLOCKER - needs events)
- Plugin loading 🚨 (BLOCKER - needs require)
- User commands ⚠️ (optional, better errors)

---

### Phase 5+ Enhancements (Nice-to-have)

4. **Error Boundaries** (1-2 days) - Plugin crash isolation
5. **TurboModules** (2-3 days) - Lazy loading
6. **Promises** (1-2 days) - LSP async operations
7. **Stack Traces** (2-3 days) - Enhanced debugging

**Total effort**: 6-10 days

---

## Recommendations

### MUST DO (Before Phase 4)

✅ **Implement Event Emitters** - Absolute requirement for autocommands
✅ **Implement Module System** - Absolute requirement for plugin architecture
⚠️ **Consider Error Throwing** - Significantly improves developer experience

**Justification**: Without event emitters and module loading, Phase 4 plugin system is severely limited. Autocommands won't work, plugins must be monolithic.

### SHOULD DO (During Phase 4)

✅ **Error Boundaries** - Plugin safety (prevent one crash from killing editor)

### CAN DEFER (Phase 5+)

📅 TurboModules, Promises, Stack Traces, WeakRef, Performance Monitoring

---

## What Vimcraft Got Right ✅

**Excellent architecture decisions**:
1. ✅ HostObject over HostFunction (React Native best practice)
2. ✅ External ArrayBuffer (zero-copy bulk data)
3. ✅ Version tracking (Neovim-compatible changedtick)
4. ✅ Chrome DevTools Protocol integration
5. ✅ Bytecode compilation support
6. ✅ Clean C API wrapper (Zig-friendly)
7. ✅ StaticStringMap for O(1) dispatch

**These are solid foundations** - the gaps are additive features, not architectural flaws.

---

## Conclusion

**Status**: Vimcraft's JSI implementation is **architecturally sound** but missing **2 critical features** for Phase 4:

1. 🚨 **Event Emitters** - BLOCKER for autocommands
2. 🚨 **Module System** - BLOCKER for multi-file plugins

**Recommendation**: **Implement these 2 features (6-9 days effort) before proceeding with Phase 4**. Without them, Phase 4 plugin system will be severely limited.

**Error throwing** is highly recommended (adds 1-2 days) for better developer experience, but not strictly required.

**Total investment**: 7-11 days to unblock Phase 4 completely.

---

## Next Steps

### 1. Implement Event Emitters (Days 1-5)

**Design**:
```zig
// Event emitter infrastructure
pub const EventEmitter = struct {
    callbacks: std.StringHashMap(std.ArrayList(*c.OVHermesValue)),
    runtime: *c.OVHermesRuntime,

    pub fn on(self: *Self, event: []const u8, callback: *c.OVHermesValue) !void {
        // Store callback for this event
    }

    pub fn emit(self: *Self, event: []const u8, args: []const *c.OVHermesValue) !void {
        // Call all registered callbacks
    }
};
```

**JavaScript API**:
```javascript
vim.on('BufEnter', (bufnr) => { ... });
vim.emit('CustomEvent', arg1, arg2);
```

### 2. Implement Module System (Days 6-9)

**Design**:
```zig
pub const ModuleLoader = struct {
    cache: std.StringHashMap(*c.OVHermesValue),
    search_paths: std.ArrayList([]const u8),

    pub fn require(self: *Self, path: []const u8) !*c.OVHermesValue {
        // Check cache, load if not found
    }
};
```

**JavaScript API**:
```javascript
const myPlugin = require('./plugins/my-plugin');
const helper = require('./lib/helper');
```

### 3. (Optional) Implement Error Throwing (Days 10-11)

**Design**:
```cpp
// C++ wrapper for throwing JS errors
void hermes_throw_error(OVHermesRuntime* runtime, const char* message) {
    auto rt = reinterpret_cast<Runtime*>(runtime);
    throw jsi::JSError(*rt, message);
}
```

**Usage**:
```zig
if (error) {
    c.hermes_throw_error(runtime, "Something went wrong");
    return null;
}
```

---

**Ready to proceed?** These features are essential for Phase 4 success.
