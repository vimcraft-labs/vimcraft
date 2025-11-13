# Testing Guide

Testing strategy and workflow.

---

## Overview

Vimcraft uses multiple testing levels:
- Unit tests (Zig)
- Integration tests (JavaScript + Zig)
- End-to-end tests (shell scripts)

---

## Running Tests

### All Tests

```bash
zig build test
```

### Specific Module

```bash
zig test src/buffer/buffer.zig
```

### Integration Tests

```bash
./test_vimcraft.sh
```

---

## Writing Tests

### Unit Test Example

```zig
test "buffer line count" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.appendLine("Line 1");
    try buffer.appendLine("Line 2");

    try std.testing.expectEqual(@as(usize, 2), buffer.lineCount());
}
```

---

## Test Guidelines

- All new functions need tests
- Bug fixes need regression tests
- Integration tests for API functions
- Performance tests for critical paths

---

See [Contributing Guidelines](./contributing.md) for testing requirements.
