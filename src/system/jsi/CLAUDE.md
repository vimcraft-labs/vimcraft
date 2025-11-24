# JSI System

Domain-specific guidance for Hermes JavaScript engine integration via JSI.

## Overview

Zero-copy bidirectional communication between Zig and JavaScript using React Native-inspired HostObject pattern (3-5x faster than FFI).

## ⚠️ Sacred Files

| File | Why Sacred | Modification Risk |
|------|------------|-------------------|
| `hermes_c_api.cpp:45-89` | HostObject implementation | Crashes all plugins |
| `hermes_c_api.h:30-75` | C API signatures | ABI breaks, undefined symbols |
| `runtime.js:1-50` | Proxy setup for DevTools | Breaks Chrome debugging |

## Key Files

| Component | File:Line | Purpose |
|-----------|-----------|---------|
| **C++ Bridge** | `hermes_c_api.cpp:45` | JSI↔Zig bridge, exceptions |
| **C Header** | `hermes_c_api.h:30` | C API declarations |
| **JS Runtime** | `runtime.js:1` | Proxy wrappers, DevTools |
| **Main API** | `jsi_api.zig:89` | Registration coordinator |
| **Motion** | `motion_api.zig:234` | 13 cursor movements |
| **Config** | `config_api.zig:567` | vim.opt/optLocal/optGlobal/bo |
| **Window** | `api_window.zig:123` | Window management |
| **Buffer** | `api_buffer.zig:89` | Zero-copy ArrayBuffer |
| **Layer** | `layer_api.zig:156` | Virtual text rendering |
| **Filetype** | `filetype_api.zig:67` | go-enry detection |
| **E2E** | `e2e_api.zig:345` | Testing framework |
| **Timer** | `timer_api.zig:78` | setTimeout/setInterval |

## Decision Tree

```
Adding JavaScript API?
├── Motion primitive → motion_api.zig
├── Option/setting → config_api.zig
├── Window operation → api_window.zig
├── Buffer access → api_buffer.zig
├── Testing helper → e2e_api.zig
└── New category → Create new *_api.zig

Implementing HostObject?
├── Define getter → Use StaticStringMap for O(1)
├── Add setter → Optional, for writable props
├── Add enumerator → Optional, for DevTools
└── Register → Add to jsi_api.zig

Performance issue?
├── Hot loop → Cache property values
├── Large data → Use ArrayBuffer
├── Many calls → Batch operations
└── Slow dispatch → Check StaticStringMap
```

## Architecture Flow

```
JavaScript Plugin
    ↓
Proxy (runtime.js)
    ↓
C++ HostObject (hermes_c_api.cpp)
    ↓
Zig Getter (O(1) StaticStringMap)
    ↓
Editor Core
```

## HostObject APIs (12 objects)

| API | Objects | Methods/Props | Use Case |
|-----|---------|---------------|----------|
| **Motion** | vim.motion | 13 primitives | Cursor animation |
| **Config** | vim.opt, optLocal, optGlobal, bo | 80+ options | Settings |
| **Window** | vim.window | split, close, focus | Layout |
| **Buffer** | vim.buffer | getContent (ArrayBuffer) | Zero-copy |
| **Layer** | vim.layer | set, clear, 9 methods | Virtual text |
| **Filetype** | vim.filetype | match (697 languages) | Detection |
| **E2E** | vim.e2e, e2e.pty | Testing framework | Tests |
| **Keymap** | vim.keymap | set, del | Mappings |
| **Cursor** | vim.cursor | get/setPosition | Position |
| **Timer** | setTimeout | Timer functions | Async |
| **Autocmd** | vim.autocmd | Event handlers | Events |
| **Console** | console | log, error | Debug |

## Common Tasks

| Task | Steps | Location |
|------|-------|----------|
| **Add method** | PropertyMap → Implement → js_state_dirty | `*_api.zig` |
| **Debug JSI** | Log calls → Track timing → Profile | `editor.logger` |
| **New API** | Create file → Getter → Register | See pattern below |
| **TypeScript** | Update vim.d.ts → Test completion | `vim.d.ts` |

## Implementation Pattern

### 1. Define Getter (O(1) dispatch)
```zig
// my_api.zig:45
pub export fn myApiHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(...).initComptime(.{
        .{ "method1", method1Impl },
        .{ "method2", method2Impl },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}
```

### 2. Implement Methods
```zig
fn method1Impl(...) callconv(.c) ?*c.OVHermesValue {
    const ctx = @as(*Context, @ptrCast(@alignCast(context)));

    // Modify editor state
    ctx.editor.js_state_dirty = true;  // MANDATORY for re-render

    return c.hermes_create_undefined(runtime);
}
```

### 3. Register HostObject
```zig
// jsi_api.zig:89
c.hermes_register_host_object(
    runtime, "myApi",
    myApiHostObjectGet,
    null,  // setter (optional)
    null,  // enumerator (optional)
    @ptrCast(context),
);
```

### 4. Add Proxy Wrapper
```javascript
// runtime.js
vim.myApi = new Proxy(
    { get [Symbol.toStringTag]() { return 'vim.myApi'; } },
    {
        get(target, prop) {
            if (prop === Symbol.toStringTag) return 'vim.myApi';
            if (typeof prop === 'symbol') return undefined;
            return myApiHostObject[prop];
        }
    }
);
```

## Performance Optimization

| Metric | Value | Comparison |
|--------|-------|------------|
| Property access | 168 ns/call | 3-5x faster than FFI |
| Throughput | 6M ops/sec | React Native level |
| O(1) dispatch | StaticStringMap | Compile-time perfect hash |

### Best Practices

| ❌ Bad | ✅ Good | Why |
|--------|---------|-----|
| 1000 JSI calls in loop | Cache property value | 1000x overhead |
| String for large data | Use ArrayBuffer | Zero-copy |
| Dynamic dispatch | StaticStringMap | O(1) vs O(n) |
| Forget js_state_dirty | Set after state change | No re-render |

## Troubleshooting

| Problem | Likely Cause | Fix | Reference |
|---------|--------------|-----|-----------|
| Function undefined | Not registered | Check jsi_api.zig:89 | `hermes_c_api.cpp:45` |
| Wrong convention | `.C` instead of `.c` | Use `.c` (Zig 0.13+) | Calling convention |
| Not visible | Missing `pub export` | Use `pub export fn` | Function visibility |
| Cast fails | Alignment issue | Check @alignCast | `context` casting |
| No re-render | No dirty flag | Set js_state_dirty | `editor.js_state_dirty` |

## Testing

### Unit Tests
```zig
// Test StaticStringMap dispatch
test "property lookup" {
    const map = PropertyMap;
    try std.testing.expect(map.get("left") != null);
}
```

### E2E Tests
```typescript
// Test from JavaScript side
vim.e2e.test("vim.opt works", () => {
    vim.opt.number = true;
    vim.e2e.assert.equal(vim.opt.number, true);
});
```

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Symbol handling | DevTools broken | Return undefined for symbols |
| Memory lifetime | ArrayBuffer invalid | Note buffer modifications |
| Hot loops | Slow performance | Cache JSI values |
| Missing dirty flag | No visual update | Set js_state_dirty |

## Future Work

| Feature | Phase | Complexity | Benefit |
|---------|-------|------------|---------|
| WebAssembly bridge | 5 | High | WASM plugins |
| Source maps | 5 | Medium | Better debugging |
| Hot reload | 6 | High | Instant updates |
| Profiling API | 6 | Low | Performance insights |

## Cross-References

**Parent**: [Main CLAUDE.md](../../../CLAUDE.md)
**Related**: [Editor Core](../../editor/CLAUDE.md) · [E2E Testing](../../../tests/e2e/CLAUDE.md)
**Docs**: [JSI Architecture](../../../docs/architecture/jsi-hostobject-architecture.md) · [API Reference](../../../docs/api/vim-api-reference.md)