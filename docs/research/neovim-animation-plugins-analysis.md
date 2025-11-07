# Neovim Animation Plugins - Research & Analysis

**Date**: 2025-01-08
**Purpose**: Understand how existing Neovim plugins implement animations WITHOUT native animation API support, to inform OpenVim's animation system design.

## Executive Summary

We analyzed three major Neovim animation plugins to understand their pain points and design better APIs:

1. **nvim-notify** (rcarriga) - Notification system with fade/slide animations
2. **neoscroll.nvim** (karb94) - Smooth scrolling with physics-based easing
3. **noice.nvim** (folke) - Complete UI replacement with animations

### Key Findings

**What Works Well**:
- ✅ Spring physics library (from Roblox) produces natural animations
- ✅ Lua timers (`vim.loop.new_timer()`) provide event loop for animations
- ✅ Easing functions create smooth non-linear motion
- ✅ Incremental updates via `nvim_win_set_config()` enable smooth position changes

**Major Pain Points**:
- ❌ **No native animation loop** - plugins must manage their own timers
- ❌ **Manual spring integration** - every plugin copies spring physics code
- ❌ **Callback hell** - timer callbacks get complex for multi-stage animations
- ❌ **No animation primitives** - composing parallel/sequence animations is manual
- ❌ **Performance hacks** - disable syntax highlighting during scroll to hit 60fps
- ❌ **Redraw control** - manual `vim.api.nvim__redraw()` calls required
- ❌ **State management** - tracking position/velocity manually for each animated value
- ❌ **No interpolation helpers** - opacity fades, color transitions done manually

---

## Plugin 1: nvim-notify (Notification Animations)

### What It Does

Displays notifications with smooth animations:
- Fade in/out with opacity transitions
- Slide in from corners
- Spring-based natural movement
- Multi-stage animations (appear → display → dismiss)

### Technical Implementation

**Architecture**:
```lua
WindowAnimator
├── win_stages[win_id] = stage_number  -- Track animation stage per window
├── win_states[win_id] = SpringState   -- Position/velocity per animated property
└── timers[win_id] = vim.loop.timer    -- One timer per notification window
```

**Animation Loop**:
```lua
-- Called every frame (~30fps by default)
function WindowAnimator:render(queue, time)
    for win in windows do
        self:_update_window(time, win)
    end
end

function WindowAnimator:_update_window(time, win)
    local goals = get_goals_for_stage(win)

    -- For each animated property (row, col, opacity, width, height)
    for field, goal in pairs(goals) do
        if is_spring_goal(goal) then
            animate.spring(time, goal[1], win_state[field],
                          goal.frequency, goal.damping)
        end
    end

    -- Apply changes to Neovim window
    nvim_win_set_config(win, new_conf)
    nvim__redraw({ win = win, flush = true })
end
```

**Spring Physics** (line 1-56 of `/lua/notify/animate/spring.lua`):
```lua
-- Adapted from Roblox Fraktality's damped spring
-- Handles three cases: critically damped, underdamped, overdamped
function spring(dt, goal, state, frequency, damping)
    local angular_freq = frequency * 2 * pi
    local offset = state.position - goal
    local decay = exp(-dt * damping * angular_freq)

    if damping == 1 then  -- Critical damping (fastest settle)
        state.position = (velocity * dt + offset * ...) * decay + goal
    elseif damping < 1 then  -- Underdamped (bouncy)
        -- Use sin/cos for oscillation
    else  -- Overdamped (slow, no bounce)
        -- Exponential decay
    end
end
```

**Timer Management**:
```lua
-- Start timer for auto-dismiss
local timer = vim.loop.new_timer()
timer:start(timeout_ms, timeout_ms, vim.schedule_wrap(function()
    self:_advance_win_stage(win)  -- Move to next animation stage
end))
```

**Multi-Stage Animations**:
```lua
stages = {
    -- Stage 1: Open window
    function(state)
        return {
            opacity = 0,   -- Start invisible
            col = 100,     -- Start off-screen
        }
    end,
    -- Stage 2: Fade in + slide in (spring-based)
    function(state)
        return {
            opacity = { 100, frequency = 2, damping = 1 },  -- Spring to 100
            col = { 10, frequency = 2, damping = 0.7 },     -- Spring to position
        }
    end,
    -- Stage 3: Hold (time-based)
    function(state)
        return { time = 3000 }  -- Display for 3 seconds
    end,
    -- Stage 4: Fade out
    function(state)
        return {
            opacity = { 0, frequency = 3, damping = 1 },
        }
    end
}
```

### Pain Points

1. **Manual Spring Integration**
   - Plugin copies 56 lines of spring physics code
   - Every plugin needs to understand damping/frequency/angular_freq
   - No built-in spring presets (gentle, bouncy, stiff)

2. **State Management Complexity**
   ```lua
   -- Plugin must manually track:
   win_states[win] = {
       row = { position = 10, velocity = 0 },
       col = { position = 20, velocity = 0 },
       opacity = { position = 100, velocity = 0 },
   }
   ```

3. **Manual Redraw Calls**
   ```lua
   -- Plugin must explicitly request redraws
   pcall(vim.api.nvim__redraw, { win = win, valid = false, flush = true })
   ```

4. **Opacity Emulation**
   - Neovim has no native opacity support
   - Plugin manually creates highlight groups with adjusted colors
   - Requires blend() calculations to simulate transparency

5. **No Animation Composition**
   - Parallel animations (fade + slide) done manually with same timestamp
   - Sequence animations require callback chaining
   - No built-in `stagger`, `loop`, `reverse` primitives

---

## Plugin 2: neoscroll.nvim (Smooth Scrolling)

### What It Does

Smooth scrolling for ANY scroll command (`gg`, `G`, `Ctrl+D`, etc.):
- Physics-based easing (quadratic, cubic, circular, sine)
- Configurable duration
- Works with wrapped lines, folded code, etc.

### Technical Implementation

**Core Algorithm**:
```lua
-- Single timer that fires at variable intervals
function scroll:animate()
    local lines_to_scroll = target_line - relative_line

    -- Compute next timestep using easing function
    local time_step = self:compute_time_step(lines_to_scroll)

    -- Scroll one line
    vim.cmd.normal({ bang = true, args = { scroll_cmd } })

    -- Schedule next frame
    timer:set_repeat(time_step)
end
```

**Easing Functions** (lines 6-13):
```lua
easing_function = {
    quadratic = function(x) return 1 - math.pow(1 - x, 1/2) end,
    cubic = function(x) return 1 - math.pow(1 - x, 1/3) end,
    sine = function(x) return 2 * math.asin(x) / math.pi end,
}
```

**Dynamic Time Steps**:
```lua
-- Calculate time between frames based on progress
function scroll:compute_time_step(lines_to_scroll)
    local x1 = (range - lines_to_scroll) / range        -- Current progress
    local x2 = (range - lines_to_scroll + 1) / range    -- Next progress
    local time_step = duration * (ef(x2) - ef(x1))      -- Delta time
    return math.floor(time_step + 0.5)
end
```

**Performance Mode**:
```lua
-- Disable expensive features during scroll
if performance_mode then
    if vim.g.loaded_nvim_treesitter then
        vim.cmd("TSBufDisable highlight")  -- Disable tree-sitter
    end
    vim.bo.syntax = "OFF"  -- Disable syntax highlighting
end
```

### Pain Points

1. **Performance Hacks Required**
   - Must disable syntax highlighting to hit 60fps
   - Must disable treesitter during scroll
   - Requires event suppression (`eventignore`)
   - Shows that Neovim's rendering isn't optimized for animations

2. **Manual Easing Implementation**
   - Each plugin reimplements easing functions
   - No standard library for quadratic/cubic/sine/etc.

3. **Command-Based Animation**
   - Uses `vim.cmd.normal()` to scroll line-by-line
   - Inefficient - triggers full redraw for each line
   - Can't bypass command layer for direct viewport manipulation

4. **Complex Wrapped Line Handling**
   ```lua
   -- Plugin must manually track wrapped lines (140+ lines of code)
   local winline = vim.api.nvim_win_call(winid, vim.fn.winline)
   local lines_behind = winline - initial_cursor_win_line
   -- ... complex correction logic ...
   ```

5. **No Velocity Support**
   - User scrolls with momentum (gesture)
   - Plugin can't access scroll velocity from input
   - Can't do inertial scrolling like iOS/Android

---

## Plugin 3: noice.nvim (UI Replacement)

### What It Does

Replaces Neovim's entire UI (messages, cmdline, popupmenu) with animated equivalents.

### Technical Implementation

**Update Throttling**:
```lua
-- Configurable UI update frequency
throttle = 1000 / 30  -- ~30 updates per second (33ms)
```

**Experimental API Usage**:
```lua
-- Uses vim.ui_attach (experimental, unstable)
vim.ui_attach(ns_id, opts)
```

### Pain Points

1. **Experimental API Dependency**
   - Relies on `vim.ui_attach` which is marked experimental
   - "Issues are to be expected"
   - Requires nightly Neovim builds

2. **Manual Throttling**
   - Plugin must manually throttle updates to avoid lag
   - No built-in frame rate control from Neovim

3. **Limited Animation Control**
   - Can't query if animations are currently running
   - No way to pause/resume animations system-wide
   - No animation inspector/debugger

---

## Common Patterns Across All Plugins

### 1. Timer-Based Animation Loop

**Every plugin does this**:
```lua
local timer = vim.loop.new_timer()

function animate_frame()
    update_animation_state(elapsed_time)
    apply_to_ui()

    if not is_complete() then
        schedule_next_frame()
    end
end

timer:start(16, 16, vim.schedule_wrap(animate_frame))  -- ~60fps
```

**Problems**:
- Boilerplate repeated in every plugin
- No centralized frame scheduler
- Multiple timers compete for CPU
- Hard to sync animations across plugins

### 2. Spring Physics (Copied Code)

**nvim-notify** copies 56 lines from Roblox Fraktality
**Others** would benefit but don't use it (too complex to integrate)

**What developers want**:
```lua
-- Instead of:
animate.spring(dt, goal, state, frequency, damping)

-- Prefer:
Animated.spring(value, {
    toValue = goal,
    preset = "gentle"  -- or { damping = 15, stiffness = 150 }
}).start()
```

### 3. Manual State Tracking

**Every plugin tracks**:
```lua
state = {
    position = current_value,
    velocity = 0,
    target = goal_value,
}
```

**What developers want**:
```lua
local animated_value = Animated.Value(initial)
-- Zig core handles position/velocity/target automatically
```

### 4. Redraw Management

**Plugins must call**:
```lua
vim.api.nvim__redraw({ win = win, flush = true })  -- Private API!
```

**Problem**: Using private API, no guarantees of stability

---

## What Neovim is Missing (OpenVim Opportunities)

### 1. Native Animation Loop ⭐⭐⭐⭐⭐

**Problem**: Every plugin implements its own timer-based loop

**Solution OpenVim Should Provide**:
```javascript
// Plugin API
const manager = openvim.animation.createManager();

manager.onFrame((deltaTime) => {
    // Called 60-120 times per second by Zig
    // Plugins can update multiple animations here
});
```

**Benefits**:
- Centralized frame scheduling
- Automatic vsync alignment
- Better battery life (consolidated wake-ups)
- Easier debugging (one animation inspector)

### 2. Spring Physics Library ⭐⭐⭐⭐⭐

**Problem**: Plugins copy complex spring code or skip springs entirely

**Solution OpenVim Should Provide**:
```javascript
// Declarative spring animation
Animated.spring(scrollY, {
    toValue: 1000,
    preset: 'gentle',  // damping=20, stiffness=120
    useNativeDriver: true,  // Runs in Zig, not JS
}).start();

// Presets: gentle, wobbly, stiff, slow
```

**Benefits**:
- Natural, physics-based motion out of the box
- No math required from plugin developers
- Consistent feel across all plugins

### 3. AnimatedValue Abstraction ⭐⭐⭐⭐

**Problem**: Plugins manually track position/velocity/target

**Solution OpenVim Should Provide**:
```javascript
const scrollY = Animated.Value(0);
const opacity = Animated.Value(1);

scrollY.addListener((value) => {
    openvim.viewport.setScrollY(value);
});
```

**Benefits**:
- Zig core handles interpolation
- JS just reads values
- Zero-copy via JSI (direct memory access)

### 4. Easing Functions Library ⭐⭐⭐⭐

**Problem**: Each plugin reimplements cubic/sine/back easings

**Solution OpenVim Should Provide**:
```javascript
Animated.timing(opacity, {
    toValue: 0,
    duration: 300,
    easing: Animated.Easing.easeInOut,  // or cubic, back, elastic
}).start();
```

**Benefits**:
- Consistent curves across plugins
- GPU-optimized in Zig
- More options (elastic, bounce, back, etc.)

### 5. Composite Animations ⭐⭐⭐⭐

**Problem**: Parallel/sequence animations are manual callback hell

**Solution OpenVim Should Provide**:
```javascript
Animated.parallel([
    Animated.spring(scrollY, { toValue: 1000 }),
    Animated.timing(opacity, { toValue: 0, duration: 200 }),
]).start();

Animated.sequence([
    Animated.spring(scale, { toValue: 1.2, duration: 100 }),
    Animated.spring(scale, { toValue: 1.0 }),
]).start();

Animated.stagger(50, [
    fadeIn(item1),
    fadeIn(item2),
    fadeIn(item3),
]).start();
```

**Benefits**:
- Declarative composition
- No callback nesting
- Easier to read and maintain

### 6. Performance Hints ⭐⭐⭐

**Problem**: Plugins must disable syntax/treesitter to hit 60fps

**Solution OpenVim Should Provide**:
```javascript
Animated.spring(scrollY, {
    toValue: 1000,
    useNativeDriver: true,  // Tell Zig to optimize
    priority: 'high',        // Deprioritize other renders
}).start();
```

**Benefits**:
- Editor can optimize rendering automatically
- No manual syntax disabling
- Smoother with less plugin code

### 7. Velocity-Based Animations ⭐⭐⭐

**Problem**: Scroll gestures don't provide velocity to plugins

**Solution OpenVim Should Provide**:
```javascript
openvim.on('scroll', (event) => {
    if (event.velocity) {
        Animated.decay(scrollY, {
            velocity: event.velocity,
            deceleration: 0.997,
        }).start();
    }
});
```

**Benefits**:
- Natural inertial scrolling (like mobile)
- Respects user's gesture momentum

### 8. Animation Debugging ⭐⭐

**Problem**: No way to inspect running animations

**Solution OpenVim Should Provide**:
```javascript
// Debug API
openvim.animation.getActiveAnimations()  // List all running
openvim.animation.pause()                // Pause all
openvim.animation.resume()               // Resume all
openvim.animation.setSpeed(0.5)          // Slow-mo for debugging
```

**Benefits**:
- Easier to debug complex animation sequences
- Can record/replay animations
- Performance profiling

---

## Recommended OpenVim Animation API

Based on the research, here's what OpenVim should provide:

### Layer 1: Zig Core (Native)

```zig
// Core animation primitives
AnimatedValue { current, target, velocity }
AnimationType { timing, spring, decay }
AnimationManager { 60-120fps update loop }
SpringPhysics { damping, stiffness, mass }
EasingFunctions { cubic, back, elastic, bounce }
```

### Layer 2: JSI Bridge (Zero-Copy)

```cpp
// Expose to JavaScript via JSI
AnimatedValueHostObject (direct memory access)
AnimationAPI (timing, spring, decay, parallel, sequence)
```

### Layer 3: JavaScript Plugin API

```javascript
// React Native Reanimated-style API
const Animated = openvim.animation;

const scrollY = Animated.Value(0);
const opacity = Animated.Value(1);

Animated.parallel([
    Animated.spring(scrollY, {
        toValue: 1000,
        preset: 'gentle',
        useNativeDriver: true,
    }),
    Animated.timing(opacity, {
        toValue: 0,
        duration: 300,
        easing: Animated.Easing.easeInOut,
    }),
]).start(() => {
    console.log('Animation complete!');
});
```

---

## Implementation Priority

Based on pain point severity:

1. **🔥 Critical - Implement First**
   - AnimatedValue + AnimationManager (native loop)
   - Spring physics with presets
   - JSI bridge for zero-copy

2. **⚡ High Value - Implement Second**
   - Easing functions library
   - Composite animations (parallel, sequence, stagger)
   - Timing + spring + decay animation types

3. **✨ Nice to Have - Implement Third**
   - Loop, reverse, repeat modifiers
   - Animation debugging tools
   - Velocity-based decay animations

---

## Success Criteria

OpenVim's animation system succeeds if:

✅ Plugin developers can create smooth 60fps animations in **<10 lines of code**
✅ No need to copy spring physics code
✅ No need to disable syntax highlighting for performance
✅ Animations feel as good as VS Code / Zed
✅ Works in headless mode (can be disabled/mocked for testing)

---

## Next Steps

1. ✅ Keep current simple animation system for Phase 3
2. 🚧 Integrate AnimationManager into yank highlight (prove it works)
3. 📅 Implement spring physics in Zig (Phase 4)
4. 📅 Build JSI bridge for plugins (Phase 4)
5. 📅 Create example plugins showcasing animations (Phase 4)

---

## References

- **nvim-notify**: https://github.com/rcarriga/nvim-notify
- **neoscroll.nvim**: https://github.com/karb94/neoscroll.nvim
- **noice.nvim**: https://github.com/folke/noice.nvim
- **Roblox Spring Physics**: https://gist.github.com/Fraktality/1033625223e13c01aa7144abe4aaf54d
- **Damped Springs Explained**: https://www.ryanjuckett.com/damped-springs/
- **React Native Reanimated**: https://docs.swmansion.com/react-native-reanimated/
