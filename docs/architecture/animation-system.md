# Animation/Timer System - Design Decision

## Problem Statement

Yank highlight needs to disappear after 250ms. How should we implement time-based visual effects?

## Research: Neovim's Approach

Neovim uses **libuv timers** for time-based effects:

```lua
-- vim.hl.on_yank implementation
local yank_timer
local yank_hl_clear

function M.on_yank(opts)
  -- Cancel previous timer if active
  if yank_timer and not yank_timer:is_closing() then
    yank_timer:close()
    yank_hl_clear()
  end

  -- Set highlight with timeout
  yank_timer, yank_hl_clear = M.range(bufnr, ns, higroup, "'[", "']", {
    timeout = opts.timeout or 150,
  })
end

-- vim.hl.range implementation
function M.range(bufnr, ns, higroup, start, finish, opts)
  -- ...set extmarks...

  if timeout ~= -1 then
    local range_timer = vim.defer_fn(range_hl_clear, timeout)
    return range_timer, range_hl_clear
  end
end
```

**Key insights**:
1. Use libuv's `uv_timer_t` via `vim.defer_fn(callback, timeout)`
2. Single global timer for yank highlights (cancel previous before starting new)
3. Extmarks for rendering (namespace-based, per-window)
4. **No complex "animation system"** - just simple timers

## Our Design Decision: Passive Timer Check

**Chosen approach**: Check expiration during render loop (passive timer)

**Why NOT use libuv timers**:
- Terminal app doesn't have libuv integrated
- Would require adding libuv dependency just for yank highlights
- Passive checking is simpler and works perfectly for this use case

**Why passive checking is CORRECT**:
- Render happens frequently (every keystroke + event loop polls at ~10-100ms)
- User won't notice sub-100ms delay in highlight disappearing
- Zero external dependencies
- Clean separation: Editor core stays headless, backend handles timing

## Implementation

```zig
// In TerminalBackend.render() - src/terminal/backend.zig:187
pub fn render(self: *TerminalBackend) !void {
    // Check if yank highlight has expired and deactivate it
    if (self.editor.yank_highlight.active and !self.editor.yank_highlight.isVisible()) {
        self.editor.yank_highlight.deactivate();
    }

    // ... rest of render logic
}

// In YankHighlight - src/visual/yank_highlight.zig
pub fn isVisible(self: *const YankHighlight) bool {
    if (!self.active) return false;
    const now = std.time.milliTimestamp();
    const elapsed = now - self.timestamp_ms;
    return elapsed < 250; // 250ms highlight duration
}
```

**Why this is sufficient**:
- ✅ Simple: 4 lines of code, no complex system
- ✅ Works: User experience is identical to Neovim
- ✅ Headless-compatible: No I/O in editor core
- ✅ Zero dependencies: Pure Zig standard library
- ✅ Testable: Mock time in tests

## Future Considerations

**When we WOULD need a proper animation system**:
- Smooth scrolling (requires per-frame interpolation)
- Cursor blink (requires active timer loop)
- GUI rendering with 60fps animations
- Complex state machines (fade-in + fade-out chains)

**For now**: Passive checking is the right trade-off between simplicity and functionality.

## References

- Neovim: `/Users/le/projects/neovim/runtime/lua/vim/hl.lua`
- Test: `/Users/le/projects/neovim/test/functional/lua/hl_spec.lua:116-141`
- Implementation: `src/terminal/backend.zig:187-191`
