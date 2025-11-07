# OpenVim Animation vs React Native Reanimated - Architecture Comparison

**Date**: 2025-01-08
**Purpose**: Compare OpenVim's animation system design with React Native Reanimated to ensure we support derived values, interpolation, and gesture-driven animations.

## React Native Reanimated Core Concepts

### 1. Shared Values (The Foundation)

**Concept**: A reactive value that can be read/written from both JavaScript and UI thread.

```javascript
const scrollY = useSharedValue(0);

// Read
const currentValue = scrollY.value;

// Write (triggers animations/re-renders)
scrollY.value = 100;

// Animate
scrollY.value = withSpring(200);
```

**Key Properties**:
- ✅ Cross-thread synchronization (JS ↔ UI thread)
- ✅ Doesn't trigger React re-renders (performance)
- ✅ Can be animated with `withSpring`, `withTiming`, etc.
- ✅ Foundation for all animations

### 2. Derived Values (Computed Values)

**Concept**: Create new values that automatically update when source values change.

```javascript
const scrollY = useSharedValue(0);

// Derived: opacity fades as you scroll
const opacity = useDerivedValue(() => {
    return 1 - (scrollY.value / 500);  // Fade out after 500px
});

// Derived: color changes based on scroll
const backgroundColor = useDerivedValue(() => {
    return scrollY.value > 100 ? 'red' : 'blue';
});

// Derived: combine multiple values
const scale = useDerivedValue(() => {
    return opacity.value * scrollY.value / 100;
});
```

**Key Properties**:
- ✅ Automatically recalculates when dependencies change
- ✅ Runs on UI thread (no JS bridge crossing)
- ✅ Readonly (output only)
- ✅ Can depend on other derived values (chaining)

### 3. Interpolation (Range Mapping)

**Concept**: Map an input range to an output range (like CSS `calc()` but reactive).

```javascript
const scrollY = useSharedValue(0);

// Map scroll position to opacity
const opacity = useDerivedValue(() => {
    return interpolate(
        scrollY.value,
        [0, 100, 200],     // Input range
        [0, 1, 0],         // Output range (fade in, then out)
        Extrapolation.CLAMP
    );
});

// Map scroll to rotation
const rotation = useDerivedValue(() => {
    return interpolate(
        scrollY.value,
        [0, 300],
        [0, 360],  // Full rotation after 300px scroll
    );
});

// Map scroll to color
const backgroundColor = useDerivedValue(() => {
    return interpolateColor(
        scrollY.value,
        [0, 100, 200],
        ['#FF0000', '#00FF00', '#0000FF']  // Red → Green → Blue
    );
});
```

**Key Properties**:
- ✅ Linear interpolation between keyframes
- ✅ Supports clamping, extending, or identity extrapolation
- ✅ Works with numbers, colors, transforms
- ✅ Multiple keyframes (not just start/end)

### 4. Gesture-Driven Animations

**Concept**: Animations directly controlled by user gestures (no "start animation" needed).

```javascript
const panGesture = Gesture.Pan()
    .onChange((event) => {
        // Directly update shared value during gesture
        scrollY.value += event.changeY;
    })
    .onEnd((event) => {
        // Animate to final position with velocity
        scrollY.value = withDecay({
            velocity: event.velocityY,
            deceleration: 0.998,
        });
    });

// UI automatically updates as scrollY changes
const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: scrollY.value }],
    opacity: interpolate(scrollY.value, [0, 100], [1, 0]),
}));
```

**Key Properties**:
- ✅ Direct manipulation (no lag)
- ✅ Velocity-aware (inertial scrolling)
- ✅ Interrupts ongoing animations seamlessly
- ✅ 120fps gesture tracking

### 5. Worklets (UI Thread Execution)

**Concept**: JavaScript code that runs on UI thread (not React thread).

```javascript
const animatedStyle = useAnimatedStyle(() => {
    'worklet';  // Runs on UI thread, 120fps

    // Complex calculations without JS bridge
    const scale = Math.sin(scrollY.value / 100) * 0.5 + 1;
    const rotation = scrollY.value % 360;

    return {
        transform: [
            { scale },
            { rotate: `${rotation}deg` },
        ],
    };
});
```

**Key Properties**:
- ✅ Runs at 120fps (not blocked by JS)
- ✅ Access to shared values without bridge crossing
- ✅ Can do complex math/logic
- ✅ Auto-workletized by Reanimated

---

## OpenVim Animation Architecture (Enhanced)

Based on Reanimated's design, here's what OpenVim should provide:

### 1. AnimatedValue (= Shared Value)

```zig
// src/animation/value.zig

pub const AnimatedValue = struct {
    id: u64,
    current: f64,
    target: f64,
    velocity: f64,

    // For derived values
    is_derived: bool = false,
    dependencies: ?std.ArrayList(*AnimatedValue) = null,
    derive_fn: ?*const fn (deps: []f64) f64 = null,

    pub fn init(initial: f64) AnimatedValue {
        return .{
            .id = generateId(),
            .current = initial,
            .target = initial,
            .velocity = 0,
        };
    }

    pub fn get(self: *const AnimatedValue) f64 {
        return self.current;
    }

    pub fn set(self: *AnimatedValue, value: f64) void {
        self.current = value;
        self.target = value;
        self.velocity = 0;
    }
};
```

**JavaScript API**:
```javascript
const scrollY = Animated.Value(0);

// Read
const current = scrollY.value;

// Write
scrollY.value = 100;

// Animate
Animated.spring(scrollY, { toValue: 200 }).start();
```

### 2. DerivedValue (= useDerivedValue)

```zig
// src/animation/derived.zig

pub const DerivedValue = struct {
    base: AnimatedValue,
    source_ids: std.ArrayList(u64),
    compute_fn: *const fn (manager: *AnimationManager, sources: []u64) f64,

    /// Update derived value when any source changes
    pub fn update(self: *DerivedValue, manager: *AnimationManager) void {
        var source_values = std.ArrayList(f64).init(manager.allocator);
        defer source_values.deinit();

        for (self.source_ids.items) |id| {
            const value = manager.getValueById(id);
            source_values.append(value.current) catch unreachable;
        }

        self.base.current = self.compute_fn(manager, source_values.items);
    }
};

pub fn createDerived(
    manager: *AnimationManager,
    sources: []*AnimatedValue,
    compute: *const fn (*AnimationManager, []f64) f64,
) !*AnimatedValue {
    var derived = try manager.allocator.create(DerivedValue);

    derived.* = .{
        .base = AnimatedValue.init(0),
        .source_ids = std.ArrayList(u64).init(manager.allocator),
        .compute_fn = compute,
    };

    for (sources) |src| {
        try derived.source_ids.append(src.id);
    }

    // Initial calculation
    derived.update(manager);

    return &derived.base;
}
```

**JavaScript API**:
```javascript
const scrollY = Animated.Value(0);

// Derived: opacity fades as you scroll
const opacity = Animated.derived([scrollY], ([scroll]) => {
    return 1 - (scroll / 500);
});

// Derived: combine multiple sources
const scale = Animated.derived([scrollY, opacity], ([scroll, op]) => {
    return op * scroll / 100;
});

// Use in animation
opacity.addListener((value) => {
    openvim.window.setOpacity(value);
});
```

### 3. Interpolation (= interpolate)

```zig
// src/animation/interpolate.zig

pub const Extrapolation = enum {
    clamp,    // Clamp to range edges
    extend,   // Linear extrapolation
    identity, // Return input value
};

pub fn interpolate(
    input: f64,
    input_range: []const f64,
    output_range: []const f64,
    extrapolate: Extrapolation,
) f64 {
    std.debug.assert(input_range.len == output_range.len);
    std.debug.assert(input_range.len >= 2);

    // Find the segment
    var segment_start: usize = 0;
    for (input_range, 0..) |val, i| {
        if (input < val) break;
        segment_start = i;
    }

    // Handle extrapolation
    if (segment_start == 0 and input < input_range[0]) {
        return switch (extrapolate) {
            .clamp => output_range[0],
            .extend => {
                const slope = (output_range[1] - output_range[0]) /
                             (input_range[1] - input_range[0]);
                return output_range[0] + slope * (input - input_range[0]);
            },
            .identity => input,
        };
    }

    if (segment_start >= input_range.len - 1) {
        return switch (extrapolate) {
            .clamp => output_range[output_range.len - 1],
            .extend => {
                const last = input_range.len - 1;
                const slope = (output_range[last] - output_range[last - 1]) /
                             (input_range[last] - input_range[last - 1]);
                return output_range[last] + slope * (input - input_range[last]);
            },
            .identity => input,
        };
    }

    // Linear interpolation within segment
    const x0 = input_range[segment_start];
    const x1 = input_range[segment_start + 1];
    const y0 = output_range[segment_start];
    const y1 = output_range[segment_start + 1];

    const t = (input - x0) / (x1 - x0);
    return y0 + (y1 - y0) * t;
}

/// Color interpolation (RGB)
pub fn interpolateColor(
    input: f64,
    input_range: []const f64,
    colors: []const u32,  // RGB colors as 0xRRGGBB
    extrapolate: Extrapolation,
) u32 {
    // Extract RGB components
    var r_range = std.ArrayList(f64).init(...);
    var g_range = std.ArrayList(f64).init(...);
    var b_range = std.ArrayList(f64).init(...);

    for (colors) |color| {
        r_range.append(@floatFromInt((color >> 16) & 0xFF));
        g_range.append(@floatFromInt((color >> 8) & 0xFF));
        b_range.append(@floatFromInt(color & 0xFF));
    }

    const r = @as(u32, @intFromFloat(interpolate(input, input_range, r_range.items, extrapolate)));
    const g = @as(u32, @intFromFloat(interpolate(input, input_range, g_range.items, extrapolate)));
    const b = @as(u32, @intFromFloat(interpolate(input, input_range, b_range.items, extrapolate)));

    return (r << 16) | (g << 8) | b;
}
```

**JavaScript API**:
```javascript
const scrollY = Animated.Value(0);

// Interpolate scroll to opacity
const opacity = Animated.derived([scrollY], ([scroll]) => {
    return Animated.interpolate(
        scroll,
        [0, 100, 200],  // Input range
        [0, 1, 0],      // Output: fade in, then out
        'clamp'
    );
});

// Interpolate to color
const bgColor = Animated.derived([scrollY], ([scroll]) => {
    return Animated.interpolateColor(
        scroll,
        [0, 100, 200],
        ['#FF0000', '#00FF00', '#0000FF']
    );
});

// Apply to UI
opacity.addListener((value) => {
    openvim.window.setOpacity(value);
});
```

### 4. Gesture-Driven Animations

```zig
// src/input/gesture.zig

pub const GestureEvent = struct {
    type: GestureType,
    delta_x: f64,
    delta_y: f64,
    velocity_x: f64,
    velocity_y: f64,
    state: GestureState,
};

pub const GestureType = enum {
    pan,
    pinch,
    rotate,
};

pub const GestureState = enum {
    began,
    changed,
    ended,
    cancelled,
};
```

**JavaScript API**:
```javascript
const scrollY = Animated.Value(0);
const scrollVelocity = Animated.Value(0);

openvim.gestures.onPan((event) => {
    if (event.state === 'changed') {
        // Direct manipulation - update immediately
        scrollY.value += event.deltaY;
        scrollVelocity.value = event.velocityY;
    }

    if (event.state === 'ended') {
        // Animate with decay based on velocity
        Animated.decay(scrollY, {
            velocity: scrollVelocity.value,
            deceleration: 0.998,
        }).start();
    }
});

// Derived: parallax effect based on scroll
const backgroundY = Animated.derived([scrollY], ([scroll]) => {
    return scroll * 0.5;  // Move background slower
});

// Derived: opacity based on scroll
const headerOpacity = Animated.derived([scrollY], ([scroll]) => {
    return Animated.interpolate(scroll, [0, 100], [1, 0], 'clamp');
});
```

### 5. Worklets (JSI Callbacks)

For OpenVim, worklets are handled via JSI - JavaScript functions can run in the Zig thread.

```cpp
// src/jsi/animation_bridge.cpp

// Register derived value with JavaScript callback
auto createDerived = jsi::Function::createFromHostFunction(
    runtime,
    jsi::PropNameID::forAscii(runtime, "derived"),
    2,
    [manager](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
        // args[0] = array of source AnimatedValues
        // args[1] = compute function

        auto sources = extractAnimatedValues(rt, args[0]);
        auto compute_fn = args[1].asObject(rt).asFunction(rt);

        // Create native derived value
        auto* derived = manager->createDerivedValue(sources, [&](double* values, size_t len) {
            // Call JavaScript compute function from Zig thread
            auto js_args = jsi::Array(rt, len);
            for (size_t i = 0; i < len; i++) {
                js_args.setValueAtIndex(rt, i, jsi::Value(values[i]));
            }

            auto result = compute_fn.call(rt, js_args);
            return result.asNumber();
        });

        return AnimatedValueHostObject::create(rt, derived);
    }
);
```

---

## Comparison Table

| Feature | React Native Reanimated | OpenVim Animation (Proposed) |
|---------|-------------------------|------------------------------|
| **Shared Values** | ✅ useSharedValue | ✅ Animated.Value |
| **Derived Values** | ✅ useDerivedValue | ✅ Animated.derived |
| **Interpolation** | ✅ interpolate, interpolateColor | ✅ Animated.interpolate, interpolateColor |
| **Springs** | ✅ withSpring | ✅ Animated.spring |
| **Timing** | ✅ withTiming | ✅ Animated.timing |
| **Decay** | ✅ withDecay | ✅ Animated.decay |
| **Gesture Input** | ✅ Gesture.Pan, etc. | ✅ openvim.gestures.onPan |
| **Worklets** | ✅ 'worklet'; directive | ✅ JSI callbacks (auto) |
| **Parallel** | ✅ No special API (just set multiple) | ✅ Animated.parallel |
| **Sequence** | ✅ withSequence | ✅ Animated.sequence |
| **Loop** | ✅ withRepeat | ✅ Animated.loop |
| **Color Interpolation** | ✅ interpolateColor | ✅ Animated.interpolateColor |
| **Native Driver** | ✅ useNativeDriver: true | ✅ useNativeDriver: true |
| **Performance** | 120fps on UI thread | 60-120fps in Zig |

---

## Real-World Examples

### Example 1: Parallax Scroll

**Reanimated**:
```javascript
const scrollY = useSharedValue(0);

const backgroundStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: scrollY.value * 0.5 }],
}));

const headerOpacity = useAnimatedStyle(() => ({
    opacity: interpolate(scrollY.value, [0, 100], [1, 0]),
}));
```

**OpenVim**:
```javascript
const scrollY = Animated.Value(0);

const backgroundY = Animated.derived([scrollY], ([scroll]) =>
    scroll * 0.5
);

const headerOpacity = Animated.derived([scrollY], ([scroll]) =>
    Animated.interpolate(scroll, [0, 100], [1, 0], 'clamp')
);

backgroundY.addListener((y) => {
    openvim.background.setScrollY(y);
});

headerOpacity.addListener((opacity) => {
    openvim.header.setOpacity(opacity);
});
```

### Example 2: Gesture-Driven Card Swipe

**Reanimated**:
```javascript
const translateX = useSharedValue(0);

const panGesture = Gesture.Pan()
    .onChange((e) => {
        translateX.value += e.changeX;
    })
    .onEnd((e) => {
        if (Math.abs(translateX.value) > 100) {
            translateX.value = withSpring(e.velocityX > 0 ? 500 : -500);
        } else {
            translateX.value = withSpring(0);
        }
    });

const cardStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
    opacity: interpolate(Math.abs(translateX.value), [0, 200], [1, 0]),
}));
```

**OpenVim**:
```javascript
const translateX = Animated.Value(0);

openvim.gestures.onPan((event) => {
    if (event.state === 'changed') {
        translateX.value += event.deltaX;
    }

    if (event.state === 'ended') {
        if (Math.abs(translateX.value) > 100) {
            const target = event.velocityX > 0 ? 500 : -500;
            Animated.spring(translateX, {
                toValue: target,
                preset: 'gentle',
            }).start();
        } else {
            Animated.spring(translateX, {
                toValue: 0,
                preset: 'gentle',
            }).start();
        }
    }
});

const opacity = Animated.derived([translateX], ([x]) => {
    return Animated.interpolate(
        Math.abs(x),
        [0, 200],
        [1, 0],
        'clamp'
    );
});

translateX.addListener((x) => {
    openvim.card.setPositionX(x);
});

opacity.addListener((op) => {
    openvim.card.setOpacity(op);
});
```

### Example 3: Loading Spinner

**Reanimated**:
```javascript
const rotation = useSharedValue(0);

useEffect(() => {
    rotation.value = withRepeat(
        withTiming(360, { duration: 1000 }),
        -1,  // Infinite
        false
    );
}, []);

const spinnerStyle = useAnimatedStyle(() => ({
    transform: [{ rotate: `${rotation.value}deg` }],
}));
```

**OpenVim**:
```javascript
const rotation = Animated.Value(0);

Animated.loop(
    Animated.timing(rotation, {
        toValue: 360,
        duration: 1000,
        easing: Animated.Easing.linear,
    })
).start();

rotation.addListener((deg) => {
    openvim.spinner.setRotation(deg);
});
```

---

## Key Differences

### 1. Threading Model

**Reanimated**: Two threads (JS thread + UI thread)
- Worklets run on UI thread
- Shared values synchronized across threads

**OpenVim**: Zig native thread + JavaScript (Hermes) thread
- JSI enables zero-copy access
- Derived value callbacks run in Zig thread via JSI
- Even better performance (no serialization)

### 2. Listener Pattern

**Reanimated**: useAnimatedStyle() auto-subscribes
```javascript
const style = useAnimatedStyle(() => ({
    opacity: opacity.value  // Auto-subscribes to opacity changes
}));
```

**OpenVim**: Explicit listeners
```javascript
opacity.addListener((value) => {
    openvim.window.setOpacity(value);
});
```

**Trade-off**: OpenVim is more explicit but also more flexible for non-UI updates.

### 3. Color Interpolation

**Reanimated**: Built-in for React Native colors
```javascript
interpolateColor(value, [0, 100], ['rgba(255,0,0,1)', 'rgba(0,255,0,1)'])
```

**OpenVim**: Hex colors (terminal limitation)
```javascript
Animated.interpolateColor(value, [0, 100], ['#FF0000', '#00FF00'])
```

---

## Conclusion

**OpenVim's animation system matches Reanimated's capabilities**:

✅ **Shared Values** → AnimatedValue
✅ **Derived Values** → Animated.derived
✅ **Interpolation** → Animated.interpolate
✅ **Gesture-Driven** → openvim.gestures + direct value manipulation
✅ **Worklets** → JSI callbacks (even better - zero-copy)
✅ **Spring Physics** → Animated.spring with presets
✅ **Composition** → parallel, sequence, stagger, loop

**The architecture is sound and matches industry-leading animation libraries!**

Next steps:
1. Implement AnimatedValue with derived value support
2. Implement interpolate() function
3. Add gesture event system
4. Build JSI bridge for derived values with callbacks
5. Test with real-world examples (parallax scroll, swipe cards)
