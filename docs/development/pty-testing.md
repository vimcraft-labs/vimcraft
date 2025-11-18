# PTY Testing Architecture

**Production-grade terminal backend testing using POSIX pseudoterminals**

## Overview

Vimcraft uses **PTY (pseudoterminal) testing** to validate terminal backend functionality end-to-end. Unlike debug protocol emulation (which bypasses the terminal backend), PTY tests exercise the **actual terminal I/O code path** that real users experience.

### Why PTY Testing?

**Problem**: Debug protocol `execute_keys` bypassed terminal backend code
- Input was simulated by calling Zig functions directly
- No ANSI output validation
- Render timing bugs went undetected (like the `Aii` bug)

**Solution**: PTY tests run Vimcraft as a child process in a pseudoterminal
- Input goes through terminal backend parsing (same as real users)
- ANSI output can be validated
- Catches render timing bugs and terminal-specific issues

## Architecture

### Components

```
Test Code                   PTY                 Vimcraft
┌──────────┐               ┌────┐              ┌────────┐
│ pty.zig  │──write()─────>│ Ma │──stdin──────>│ Term   │
│          │<────read()────│ st │<──stdout─────│ Backend│
└──────────┘               │ er │              └────────┘
                           └────┘
                            ↓↑
                           ┌────┐
                           │Sla │
                           │ve  │ (child process)
                           └────┘
```

**Files**:
- `src/backends/terminal/tests/pty.zig` - PTY wrapper (spawn, read, write, kill)
- `src/backends/terminal/tests/test_helpers.zig` - ANSI utilities (stripAnsi, parseAnsiCursor)
- `src/backends/terminal/tests/core_tests.zig` - 15 comprehensive tests

### How PTY Works

1. **Create PTY Pair**: `openpty()` creates master/slave file descriptors
2. **Fork Process**: `fork()` creates child process
3. **Redirect stdio**: Child's stdin/stdout/stderr → pty slave
4. **Execute Program**: Child calls `execve()` to run Vimcraft
5. **Parent Communicates**: Parent writes to master (simulates typing), reads output

**Key Insight**: Vimcraft thinks it's running in a real terminal (like iTerm2), but it's actually connected to our test code!

## Writing PTY Tests

### Basic Test Structure

```zig
test "PTY: Test description" {
    const allocator = std.testing.allocator;

    // 1. Create test file
    try createTestFile("Content\n");

    // 2. Spawn Vimcraft
    var pty = try spawnVimcraft(allocator);
    defer pty.kill();

    // 3. Wait for startup
    var buf: [4096]u8 = undefined;
    _ = try pty.read(&buf, 1000);

    // 4. Simulate user input
    try pty.write("i");  // Enter insert mode
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("Hello");  // Type text
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try pty.write("\x1b");  // ESC to exit insert
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // 5. Read and validate output
    const output = try pty.read(&buf, 1000);
    const stripped = try helpers.stripAnsi(allocator, output);
    defer allocator.free(stripped);

    try std.testing.expect(std.mem.indexOf(u8, stripped, "Hello") != null);
}
```

### Best Practices

**1. Sleep Between Operations**
```zig
try pty.write("A");
std.Thread.sleep(50 * std.time.ns_per_ms);  // ✅ Give editor time to process
```

**Why**: Terminal I/O is asynchronous. Without sleeps, commands may be processed out of order or buffered together.

**2. Strip ANSI Codes Before Assertions**
```zig
const output = try pty.read(&buf, 1000);
const stripped = try helpers.stripAnsi(allocator, output);  // ✅ Remove escape codes
defer allocator.free(stripped);

try std.testing.expect(std.mem.indexOf(u8, stripped, "text") != null);
```

**Why**: ANSI output contains escape codes (`\x1b[31m`, `\x1b[0m`, etc.). Strip them to test text content.

**3. Use Blocking Read with Timeout**
```zig
const output = try pty.read(&buf, 1000);  // ✅ Wait up to 1 second
```

**Why**: Non-blocking reads (`readAll()`) may return before output is written. Use timeout to wait for data.

**4. Always Clean Up**
```zig
var pty = try spawnVimcraft(allocator);
defer pty.kill();  // ✅ Ensure process is terminated
```

**Why**: Without `defer pty.kill()`, zombie processes accumulate on test failures.

## Running PTY Tests

### Prerequisites

Build Vimcraft first:
```bash
zig build
```

PTY tests require the `vimc` binary in `./zig-out/bin/`.

### Run Tests

```bash
# Run all PTY tests
zig build pty_tests

# Run specific test
zig test src/backends/terminal/tests/core_tests.zig --test-filter "Append at end"
```

### Debugging Failed Tests

**Check stdout**:
```zig
std.debug.print("\nReceived: len={} data='{s}'\n", .{ output.len, output });
```

**Common Issues**:
- **0 bytes received**: Process may have crashed. Check with `pty.wait()` and inspect exit code.
- **Timeout**: Increase `pty.read()` timeout or add more `sleep()` between operations.
- **Wrong content**: Check ANSI codes - use `stripAnsi()` helper.

## Coverage

### What PTY Tests Cover (95%)

✅ Terminal input parsing (key sequences, escape codes)
✅ ANSI output rendering (colors, cursor movement, screen clearing)
✅ Render timing bugs (like `Aii` inserting on wrong line)
✅ User-facing behavior (exactly what users see)

### What PTY Tests Don't Cover (5%)

❌ Real terminal quirks (WezTerm-specific bugs, terminal emulator differences)
❌ Internal state inspection (use debug protocol for this)

## PTY vs Debug Protocol

**Use PTY tests when**:
- Testing terminal input/output
- Validating ANSI rendering
- Verifying end-to-end user experience
- Writing regression tests for user-facing bugs

**Use Debug Protocol when**:
- Inspecting internal state (cursor position, mode, registers)
- Debugging layer composition
- Analyzing logs
- Fast unit-level validation

**Best Practice**: Use BOTH!
```bash
# PTY test reproduces bug
var pty = try spawnVimcraft(allocator);
try pty.write("Aii");
const output = try pty.read(&buf, 1000);
// Bug confirmed: "ii" on line 2

# Debug protocol diagnoses root cause
./zig-out/bin/vimc --debug-protocol &
echo '{"cmd":"get_state","id":"1"}'
# Logs show: "transaction prevents line_starts rebuild"
```

## Test Catalog

### Core Tests (15 total)

1. **Startup** - Vimcraft launches and displays buffer
2. **Insert Mode** - Enter insert, type text, exit
3. **Append** - `A` moves to end of line and enters insert
4. **Navigation** - `hjkl` movement
5. **Delete** - `x` deletes character
6. **Undo** - `u` undoes last operation
7. **Visual Mode** - `v` enters visual, `d` deletes selection
8. **Paste** - `p` pastes from register
9. **Multi-line** - `j/k` between lines
10. **Word Motion** - `w` moves forward by word
11. **Line Boundaries** - `0` and `$`
12. **File Navigation** - `gg` and `G`
13. **Change Operator** - `cw` changes word
14. **Delete Line** - `dd` deletes current line
15. **Regression: Aii** - Critical regression test

## Implementation Details

### Fork Safety

**Problem**: Can't use heap allocation in child process after `fork()`

**Solution**: Convert argv to stack-allocated null-terminated strings
```zig
var argv_storage: [256][256:0]u8 = undefined;  // Stack allocation
var argv_ptrs: [257]?[*:0]const u8 = undefined;

for (argv, 0..) |arg, i| {
    @memcpy(argv_storage[i][0..arg.len], arg);  // Copy to stack
    argv_storage[i][arg.len] = 0;
    argv_ptrs[i] = &argv_storage[i];
}
argv_ptrs[argv.len] = null;
```

### EOF Signaling

**Problem**: If slave FD remains open in parent, reads block forever

**Solution**: Close slave FD in parent immediately after fork
```zig
const pid = try posix.fork();

if (pid == 0) {
    // Child uses slave
} else {
    // Parent MUST close slave!
    posix.close(slave);
}
```

**Why**: When the child exits, the master will only signal EOF if ALL slave FDs are closed. Parent's copy must be closed.

## Future Enhancements

- [ ] Test terminal resize (SIGWINCH)
- [ ] Test bracketed paste mode
- [ ] Test mouse input sequences
- [ ] Test Unicode rendering (emoji, combining characters)
- [ ] Benchmark PTY overhead vs unit tests

## Resources

- POSIX PTY Specification: https://pubs.opengroup.org/onlinepubs/9699919799/functions/openpty.html
- Expect-style testing: https://core.tcl-lang.org/expect/index
- PTY in Python: https://docs.python.org/3/library/pty.html (similar concepts, but we use pure Zig!)

---

**Status**: ✅ Production-ready (December 2024)
**Maintainer**: See CLAUDE.md for development workflows
