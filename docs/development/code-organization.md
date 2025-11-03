# Code Organization

Project structure and module organization.

---

## Directory Structure

```
src/
├── main.zig              # Entry point
├── buffer/               # Text buffer
├── display/              # Rendering
├── mode/                 # Mode system
├── movement/             # Vim motions
├── jsi/                  # JSI bridge
├── api/                  # Public API (Phase 4)
├── config/               # Options (Phase 4)
└── event/                # Events (Phase 4)
```

---

## Module Responsibilities

### src/buffer/
Text storage and manipulation.

### src/display/
Terminal rendering with ANSI codes.

### src/jsi/
Zig ↔ JavaScript bridge.

### src/api/ (Phase 4)
Public API implementation (vim.api.*).

---

## Adding New Modules

1. Create directory: `src/myfeature/`
2. Add `myfeature.zig`
3. Update `build.zig`
4. Add tests
5. Document in README

---

See [Architecture Documentation](../architecture/) for design.
