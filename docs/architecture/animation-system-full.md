# OpenVim Animation System - Full-Featured Design

## Vision

A **first-class animation system** inspired by React Native Animated/Reanimated that makes animations:
- **Declarative**: Define what, not how
- **Performant**: 60fps+ on UI thread, GPU-accelerated when possible
- **Composable**: Chain, parallel, sequence, stagger animations
- **Plugin-friendly**: JavaScript plugins can create smooth animations via JSI
- **Type-safe**: Zig core with clean JavaScript API
- **Backend-agnostic**: Works across Terminal, GUI (like Zed), and Debug backends

## Why Animation System is Critical

### Multiple Backend Support

OpenVim will have **three backends**:

1. **Terminal Backend** (current): ANSI escape codes, limited animation capabilities
2. **GUI Backend** (future): Like Zed/VSCode - GPU-accelerated, smooth 120fps animations
3. **Debug Backend** (LLM/ovdb): Headless, no rendering, animations can be mocked/disabled

**The animation system enables**:
- Terminal: Graceful degradation (simple fade effects work, complex ones skip)
- GUI: Full power (smooth scrolling, cursor effects, layout animations, blur effects)
- Debug: Fast testing (animations can be instant or disabled)

### Future GUI Backend Use Cases

When we build the GUI backend (like Zed), the animation system will enable:

**Smooth Interactions**:
- Buttery smooth scrolling with spring physics
- Cursor that glides to position instead of jumping
- Autocomplete menu that slides in smoothly
- Search results that fade in/out
- Split views that animate into position

**Visual Polish**:
- Blur background when command palette opens
- Ripple effect on button clicks
- Sidebar that slides out with easing
- Hover effects with micro-animations
- Loading spinners and progress bars

**Layout Animations**:
- Window splits animate into position
- Tabs reorder with smooth transitions
- Side panels expand/collapse gracefully
- Notification toasts slide in from corner

This is **exactly like Zed's animations** - but plugins can create them too!

## Design Goals

1. **Plugin Developer Experience**: Plugins should be able to create smooth animations with simple APIs
2. **Native Performance**: Animations run on native thread, not blocked by JavaScript
3. **Declarative**: `animate(value).to(target).withSpring()` style APIs
4. **Composable**: Build complex animations from simple primitives
5. **Interruptible**: New animations can interrupt and take over from current state
6. **Debuggable**: Animation inspector, playback controls for debugging

## Core Architecture

### Layer 1: Zig Animation Core (Native)

The Zig core runs on the main thread and handles all animation state updates at 60-120fps.

```zig
// src/animation/core.zig

/// Animated value that can be interpolated over time
pub const AnimatedValue = struct {
    current: f64,
    target: f64,
    velocity: f64 = 0,
    animation: ?*Animation = null,

    pub fn init(initial: f64) AnimatedValue {
        return .{
            .current = initial,
            .target = initial,
        };
    }

    /// Get current value (called every frame)
    pub fn get(self: *const AnimatedValue) f64 {
        return self.current;
    }

    /// Check if animation is finished
    pub fn isActive(self: *const AnimatedValue) bool {
        return self.animation != null;
    }
};

/// Vector value for 2D animations (cursor movement, scroll)
pub const AnimatedVector = struct {
    x: AnimatedValue,
    y: AnimatedValue,

    pub fn init(x: f64, y: f64) AnimatedVector {
        return .{
            .x = AnimatedValue.init(x),
            .y = AnimatedValue.init(y),
        };
    }
};

/// Animation types
pub const AnimationType = enum {
    timing,  // Linear interpolation with easing
    spring,  // Physics-based spring
    decay,   // Initial velocity with friction
};

/// Easing functions (similar to CSS)
pub const Easing = enum {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
    ease_in_cubic,
    ease_out_cubic,
    ease_in_out_cubic,
    ease_in_back,
    ease_out_back,
    ease_in_out_back,
    custom, // Custom bezier curve

    pub fn apply(self: Easing, t: f64) f64 {
        return switch (self) {
            .linear => t,
            .ease_in => t * t,
            .ease_out => t * (2.0 - t),
            .ease_in_out => if (t < 0.5)
                2.0 * t * t
            else
                -1.0 + (4.0 - 2.0 * t) * t,
            .ease_in_cubic => t * t * t,
            .ease_out_cubic => {
                const t1 = t - 1.0;
                return t1 * t1 * t1 + 1.0;
            },
            .ease_in_out_cubic => if (t < 0.5)
                4.0 * t * t * t
            else
                (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0,
            .ease_in_back => {
                const c1 = 1.70158;
                const c3 = c1 + 1.0;
                return c3 * t * t * t - c1 * t * t;
            },
            .ease_out_back => {
                const c1 = 1.70158;
                const c3 = c1 + 1.0;
                const t1 = t - 1.0;
                return 1.0 + c3 * t1 * t1 * t1 + c1 * t1 * t1;
            },
            .ease_in_out_back => {
                const c1 = 1.70158;
                const c2 = c1 * 1.525;
                if (t < 0.5) {
                    const t2 = 2.0 * t;
                    return (t2 * t2 * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0;
                } else {
                    const t2 = 2.0 * t - 2.0;
                    return (t2 * t2 * ((c2 + 1.0) * t2 + c2) + 2.0) / 2.0;
                }
            },
            .custom => t, // TODO: Support custom bezier
        };
    }
};

/// Timing animation config
pub const TimingConfig = struct {
    duration_ms: u32,
    easing: Easing = .ease_in_out,
    delay_ms: u32 = 0,
};

/// Spring animation config (physics-based)
pub const SpringConfig = struct {
    damping: f64 = 10.0,        // Resistance (higher = less bounce)
    stiffness: f64 = 100.0,     // Spring strength (higher = faster)
    mass: f64 = 1.0,            // Object mass (higher = slower)
    velocity: f64 = 0.0,        // Initial velocity

    // Common presets
    pub fn gentle() SpringConfig {
        return .{ .damping = 20.0, .stiffness = 120.0 };
    }

    pub fn wobbly() SpringConfig {
        return .{ .damping = 8.0, .stiffness = 180.0 };
    }

    pub fn stiff() SpringConfig {
        return .{ .damping = 26.0, .stiffness = 210.0 };
    }

    pub fn slow() SpringConfig {
        return .{ .damping = 26.0, .stiffness = 70.0 };
    }
};

/// Decay animation config
pub const DecayConfig = struct {
    velocity: f64,
    deceleration: f64 = 0.998, // Friction coefficient
};

/// Base animation interface
pub const Animation = struct {
    type: AnimationType,
    value: *AnimatedValue,
    start_time_ms: i64,

    // Union of configs
    timing_config: ?TimingConfig = null,
    spring_config: ?SpringConfig = null,
    decay_config: ?DecayConfig = null,

    // Callbacks
    on_update: ?*const fn (value: f64) void = null,
    on_complete: ?*const fn () void = null,

    /// Update animation (called every frame)
    /// Returns true if animation should continue
    pub fn update(self: *Animation, now_ms: i64) bool {
        const elapsed = now_ms - self.start_time_ms;

        switch (self.type) {
            .timing => return self.updateTiming(elapsed),
            .spring => return self.updateSpring(elapsed),
            .decay => return self.updateDecay(elapsed),
        }
    }

    fn updateTiming(self: *Animation, elapsed_ms: i64) bool {
        const config = self.timing_config.?;

        // Handle delay
        if (elapsed_ms < config.delay_ms) {
            return true;
        }

        const adjusted_elapsed = elapsed_ms - config.delay_ms;
        const duration = @as(f64, @floatFromInt(config.duration_ms));
        const t = @as(f64, @floatFromInt(adjusted_elapsed)) / duration;

        if (t >= 1.0) {
            self.value.current = self.value.target;
            if (self.on_complete) |cb| cb();
            return false; // Animation complete
        }

        // Apply easing
        const eased_t = config.easing.apply(t);
        const start = self.value.current - (self.value.target - self.value.current) * (eased_t / (1.0 - eased_t));
        self.value.current = start + (self.value.target - start) * eased_t;

        if (self.on_update) |cb| cb(self.value.current);
        return true;
    }

    fn updateSpring(self: *Animation, elapsed_ms: i64) bool {
        const config = self.spring_config.?;
        const dt = 0.016; // 60fps = ~16ms per frame

        // Spring physics: F = -kx - cv
        // Hooke's law + damping
        const displacement = self.value.current - self.value.target;
        const spring_force = -config.stiffness * displacement;
        const damping_force = -config.damping * self.value.velocity;

        const acceleration = (spring_force + damping_force) / config.mass;
        self.value.velocity += acceleration * dt;
        self.value.current += self.value.velocity * dt;

        // Check if settled (very small velocity and displacement)
        const is_settled = @abs(self.value.velocity) < 0.01 and @abs(displacement) < 0.01;

        if (is_settled) {
            self.value.current = self.value.target;
            self.value.velocity = 0;
            if (self.on_complete) |cb| cb();
            return false;
        }

        if (self.on_update) |cb| cb(self.value.current);
        return true;
    }

    fn updateDecay(self: *Animation, elapsed_ms: i64) bool {
        const config = self.decay_config.?;
        const dt = 0.016;

        // Decay: v = v * deceleration
        self.value.velocity *= config.deceleration;
        self.value.current += self.value.velocity * dt;

        // Stop when velocity is very small
        if (@abs(self.value.velocity) < 0.1) {
            self.value.velocity = 0;
            if (self.on_complete) |cb| cb();
            return false;
        }

        if (self.on_update) |cb| cb(self.value.current);
        return true;
    }
};

/// Animation manager (runs at 60-120fps)
pub const AnimationManager = struct {
    allocator: std.mem.Allocator,
    animations: std.ArrayList(*Animation),
    values: std.ArrayList(*AnimatedValue),
    frame_callback: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator) AnimationManager {
        return .{
            .allocator = allocator,
            .animations = std.ArrayList(*Animation).init(allocator),
            .values = std.ArrayList(*AnimatedValue).init(allocator),
        };
    }

    /// Create animated value
    pub fn createValue(self: *AnimationManager, initial: f64) !*AnimatedValue {
        const value = try self.allocator.create(AnimatedValue);
        value.* = AnimatedValue.init(initial);
        try self.values.append(value);
        return value;
    }

    /// Start animation
    pub fn startAnimation(self: *AnimationManager, animation: *Animation) !void {
        // Cancel existing animation on this value
        for (self.animations.items, 0..) |anim, i| {
            if (anim.value == animation.value) {
                _ = self.animations.swapRemove(i);
                self.allocator.destroy(anim);
                break;
            }
        }

        animation.start_time_ms = std.time.milliTimestamp();
        try self.animations.append(animation);
    }

    /// Update all animations (called every frame)
    pub fn update(self: *AnimationManager) void {
        const now = std.time.milliTimestamp();

        var i: usize = 0;
        while (i < self.animations.items.len) {
            const anim = self.animations.items[i];

            if (!anim.update(now)) {
                // Animation complete
                _ = self.animations.swapRemove(i);
                self.allocator.destroy(anim);
            } else {
                i += 1;
            }
        }

        // Trigger render if any animations active
        if (self.animations.items.len > 0 and self.frame_callback != null) {
            self.frame_callback.?();
        }
    }

    /// Check if any animations are running
    pub fn hasActiveAnimations(self: *const AnimationManager) bool {
        return self.animations.items.len > 0;
    }

    pub fn deinit(self: *AnimationManager) void {
        for (self.animations.items) |anim| {
            self.allocator.destroy(anim);
        }
        for (self.values.items) |value| {
            self.allocator.destroy(value);
        }
        self.animations.deinit();
        self.values.deinit();
    }
};

/// Composite animations
pub const CompositeAnimation = enum {
    parallel,  // Run all at once
    sequence,  // Run one after another
    stagger,   // Run with delays

    pub fn run(
        self: CompositeAnimation,
        manager: *AnimationManager,
        animations: []*Animation,
        stagger_delay_ms: u32,
    ) !void {
        switch (self) {
            .parallel => {
                for (animations) |anim| {
                    try manager.startAnimation(anim);
                }
            },
            .sequence => {
                // TODO: Implement sequence (chain on_complete callbacks)
                _ = animations;
            },
            .stagger => {
                for (animations, 0..) |anim, i| {
                    anim.timing_config.?.delay_ms = @intCast(i * stagger_delay_ms);
                    try manager.startAnimation(anim);
                }
            },
        }
    }
};
```

### Layer 2: JSI Bridge (JavaScript ↔ Zig)

Expose animation system to JavaScript plugins via zero-copy JSI.

```cpp
// src/jsi/animation_bridge.cpp

class AnimatedValueHostObject : public jsi::HostObject {
private:
    AnimatedValue* native_value;

public:
    AnimatedValueHostObject(AnimatedValue* value) : native_value(value) {}

    jsi::Value get(jsi::Runtime&, const jsi::PropNameID& name) override {
        auto prop = name.utf8(runtime);

        if (prop == "value") {
            return jsi::Value(native_value->get());
        }
        // ... other properties
    }

    void set(jsi::Runtime&, const jsi::PropNameID& name, const jsi::Value& value) override {
        // Allow setting target, not current
    }
};

// Register JSI functions
void registerAnimationAPI(jsi::Runtime& runtime) {
    // Animated.Value
    auto createValue = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "createAnimatedValue"),
        1,
        [](jsi::Runtime& runtime, const jsi::Value&, const jsi::Value* args, size_t count) {
            double initial = args[0].asNumber();
            auto* native_value = animation_manager->createValue(initial);
            return jsi::Object::createFromHostObject(
                runtime,
                std::make_shared<AnimatedValueHostObject>(native_value)
            );
        }
    );

    // Animated.timing()
    auto timing = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "timing"),
        2,
        [](jsi::Runtime& runtime, const jsi::Value&, const jsi::Value* args, size_t count) {
            auto value = getAnimatedValue(args[0]);
            auto config = args[1].asObject(runtime);

            auto toValue = config.getProperty(runtime, "toValue").asNumber();
            auto duration = config.getProperty(runtime, "duration").asNumber();

            // Create native animation
            auto* anim = createTimingAnimation(value, toValue, duration);
            animation_manager->startAnimation(anim);

            return jsi::Value::undefined();
        }
    );

    // Animated.spring()
    auto spring = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "spring"),
        2,
        [](jsi::Runtime& runtime, const jsi::Value&, const jsi::Value* args, size_t count) {
            // Similar to timing but with spring config
        }
    );

    // Register to global
    runtime.global().setProperty(runtime, "Animated", createAnimatedObject(runtime));
}
```

### Layer 3: JavaScript Plugin API

Clean, React Native-like API for plugin developers.

```javascript
// Plugin API (runs in Hermes)

// ~/.config/openvim/plugins/smooth-scroll.js

const Animated = openvim.animation;

class SmoothScrollPlugin {
  constructor() {
    // Create animated values
    this.scrollY = Animated.Value(0);
    this.scrollX = Animated.Value(0);

    // Listen to scroll events
    openvim.on('scroll', (event) => {
      this.animateScroll(event.targetY, event.targetX);
    });

    // Update viewport on animation frame
    this.scrollY.addListener((value) => {
      openvim.viewport.setScrollY(value.value);
    });
  }

  animateScroll(targetY, targetX) {
    // Smooth spring animation
    Animated.parallel([
      Animated.spring(this.scrollY, {
        toValue: targetY,
        damping: 15,
        stiffness: 150,
        useNativeDriver: true, // Run on Zig thread
      }),
      Animated.spring(this.scrollX, {
        toValue: targetX,
        damping: 15,
        stiffness: 150,
        useNativeDriver: true,
      }),
    ]).start();
  }
}

openvim.registerPlugin('smooth-scroll', SmoothScrollPlugin);
```

```javascript
// ~/.config/openvim/plugins/cursor-effects.js

const Animated = openvim.animation;

class CursorEffectsPlugin {
  constructor() {
    this.opacity = Animated.Value(1);
    this.scale = Animated.Value(1);

    // Blink animation
    this.startBlinkAnimation();

    // Pulse on movement
    openvim.on('cursor:move', () => {
      this.pulseEffect();
    });
  }

  startBlinkAnimation() {
    Animated.loop(
      Animated.sequence([
        Animated.timing(this.opacity, {
          toValue: 0,
          duration: 500,
          easing: Animated.Easing.ease,
        }),
        Animated.timing(this.opacity, {
          toValue: 1,
          duration: 500,
          easing: Animated.Easing.ease,
        }),
      ])
    ).start();
  }

  pulseEffect() {
    Animated.sequence([
      Animated.timing(this.scale, {
        toValue: 1.2,
        duration: 100,
        easing: Animated.Easing.easeOut,
      }),
      Animated.spring(this.scale, {
        toValue: 1.0,
        damping: 5,
        stiffness: 200,
      }),
    ]).start();
  }
}
```

```javascript
// ~/.config/openvim/plugins/yank-highlight.js

const Animated = openvim.animation;

class YankHighlightPlugin {
  constructor() {
    this.opacity = Animated.Value(0);
    this.scale = Animated.Value(0.9);

    openvim.on('yank', (event) => {
      this.showHighlight(event.range);
    });
  }

  showHighlight(range) {
    // Fade in + scale up
    Animated.parallel([
      Animated.timing(this.opacity, {
        toValue: 1.0,
        duration: 100,
        easing: Animated.Easing.easeOut,
      }),
      Animated.spring(this.scale, {
        toValue: 1.0,
        stiffness: 300,
        damping: 15,
      }),
    ]).start();

    // Then fade out after 250ms
    setTimeout(() => {
      Animated.timing(this.opacity, {
        toValue: 0,
        duration: 200,
        easing: Animated.Easing.easeIn,
      }).start(() => {
        openvim.highlights.clear(range);
      });
    }, 250);
  }
}
```

## Built-in Animations (OpenVim Core)

The core editor will use the animation system for default effects:

1. **Yank Highlight**: Fade in + fade out with spring
2. **Smooth Scrolling**: Spring-based scroll animation
3. **Cursor Blink**: Loop timing animation
4. **Search Highlight**: Fade in/out
5. **Command Palette**: Slide in from top with spring
6. **Notifications**: Slide in from corner, auto-dismiss with fade

## Implementation Plan

### Phase 1: Core Animation Engine (Week 1-2)
- [ ] Implement `AnimatedValue`, `AnimatedVector`
- [ ] Implement `Animation` with timing/spring/decay
- [ ] Implement `AnimationManager` with 60fps update loop
- [ ] Add easing functions
- [ ] Unit tests for spring physics, timing, etc.

### Phase 2: JSI Bridge (Week 3)
- [ ] Create `AnimatedValueHostObject` for JSI
- [ ] Expose `Animated.Value`, `Animated.Vector`
- [ ] Expose `Animated.timing`, `Animated.spring`, `Animated.decay`
- [ ] Expose composite: `parallel`, `sequence`, `stagger`, `loop`
- [ ] Add `useNativeDriver` support

### Phase 3: Plugin API (Week 4)
- [ ] JavaScript wrapper for clean API
- [ ] Event system for plugins to hook into
- [ ] Interpolation helpers (map ranges)
- [ ] Animation debugging tools

### Phase 4: Core Integration (Week 5)
- [ ] Replace yank highlight with animation system
- [ ] Add smooth scrolling
- [ ] Add cursor blink
- [ ] Add search highlight animations

### Phase 5: Advanced Features (Week 6+)
- [ ] Gesture-driven animations (scroll with velocity)
- [ ] Layout animations (for splits, windows)
- [ ] Keyframe animations
- [ ] Animation inspector/debugger UI

## Performance Targets

- **Animation FPS**: 60fps minimum, 120fps target
- **Overhead**: <1ms per frame for animation updates
- **Memory**: <1KB per active animation
- **Startup**: <10ms to initialize animation system
- **JSI Call Overhead**: <0.1ms per animation start/stop

## API Design Philosophy

1. **Declarative > Imperative**: Define what, not how
2. **Sensible Defaults**: Works great out of the box
3. **Escape Hatches**: Advanced control when needed
4. **Type Safety**: Zig ensures correctness, TypeScript for plugins
5. **Zero-Copy**: JSI enables true native performance
6. **Composable**: Small primitives, powerful combinations

## Success Criteria

✅ Plugin developer can create smooth 60fps animation in <10 lines
✅ Animation system feels as good as VS Code / Zed
✅ Zero jank during text editing + animations
✅ Animations work in headless mode (can be disabled/mocked)
✅ Animation API is documented with examples

This will make OpenVim **the most animation-friendly terminal editor** and enable plugin developers to create truly delightful experiences!
