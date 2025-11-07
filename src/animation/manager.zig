const std = @import("std");
const AnimatedValue = @import("value.zig").AnimatedValue;
const ValueListener = @import("value.zig").ValueListener;
const Animation = @import("core.zig").Animation;
const AnimationType = @import("core.zig").AnimationType;
const TimingConfig = @import("core.zig").TimingConfig;
const SpringConfig = @import("core.zig").SpringConfig;
const DecayConfig = @import("core.zig").DecayConfig;

/// Time source for animations (supports mocking for tests)
pub const TimeSource = enum {
    system,
    mock,

    pub fn now(self: TimeSource) i64 {
        return switch (self) {
            .system => std.time.milliTimestamp(),
            .mock => mock_time,
        };
    }
};

// Mock time for testing
var mock_time: i64 = 0;

/// Set mock time (for testing)
pub fn setMockTime(ms: i64) void {
    mock_time = ms;
}

/// Derived value computation function
pub const DerivedFunction = *const fn (context: ?*anyopaque) f64;

/// Derived value definition
pub const DerivedValue = struct {
    value: *AnimatedValue,
    compute: DerivedFunction,
    context: ?*anyopaque,
    dependencies: []const u64, // AnimatedValue IDs this depends on

    /// Recompute derived value
    pub fn update(self: *DerivedValue) void {
        const new_value = self.compute(self.context);
        self.value.current = new_value;
        self.value.target = new_value;
    }
};

/// Central animation coordinator
/// Manages AnimatedValues, Animations, and derived value dependencies
pub const AnimationManager = struct {
    allocator: std.mem.Allocator,

    // Core animation state
    animations: std.ArrayList(Animation),
    values: std.ArrayList(*AnimatedValue),
    derived_values: std.ArrayList(DerivedValue),
    listeners: std.ArrayList(ValueListener),

    time_source: TimeSource,

    pub fn init(allocator: std.mem.Allocator) AnimationManager {
        return .{
            .allocator = allocator,
            .animations = .{},
            .values = .{},
            .derived_values = .{},
            .listeners = .{},
            .time_source = .system,
        };
    }

    /// Register an AnimatedValue with the manager
    pub fn registerValue(self: *AnimationManager, value: *AnimatedValue) !void {
        try self.values.append(self.allocator, value);
    }

    /// Create and register a derived value
    /// The compute function will be called whenever dependencies change
    pub fn createDerived(
        self: *AnimationManager,
        compute: DerivedFunction,
        context: ?*anyopaque,
        dependencies: []const u64,
    ) !*AnimatedValue {
        const value = try self.allocator.create(AnimatedValue);
        value.* = AnimatedValue.init(0.0);
        value.is_derived = true;

        const derived = DerivedValue{
            .value = value,
            .compute = compute,
            .context = context,
            .dependencies = try self.allocator.dupe(u64, dependencies),
        };

        try self.derived_values.append(self.allocator, derived);
        try self.values.append(self.allocator, value);

        // Initial computation
        value.current = compute(context);
        value.target = value.current;

        return value;
    }

    /// Add a listener for value changes
    pub fn addListener(
        self: *AnimationManager,
        value_id: u64,
        callback: @import("value.zig").ListenerCallback,
        context: ?*anyopaque,
    ) !void {
        try self.listeners.append(self.allocator, .{
            .value_id = value_id,
            .callback = callback,
            .context = context,
        });
    }

    /// Start a timing animation on a value
    pub fn animateTiming(
        self: *AnimationManager,
        value: *AnimatedValue,
        config: TimingConfig,
    ) !void {
        const now = self.time_source.now();
        try self.animations.append(self.allocator, .{
            .value = value,
            .type = .timing,
            .start_time_ms = now,
            .initial_value = value.current,
            .timing_config = config,
        });
    }

    /// Start a spring animation on a value
    pub fn animateSpring(
        self: *AnimationManager,
        value: *AnimatedValue,
        config: SpringConfig,
    ) !void {
        const now = self.time_source.now();
        try self.animations.append(self.allocator, .{
            .value = value,
            .type = .spring,
            .start_time_ms = now,
            .initial_value = value.current,
            .spring_config = config,
        });
    }

    /// Start a decay animation on a value
    pub fn animateDecay(
        self: *AnimationManager,
        value: *AnimatedValue,
        config: DecayConfig,
    ) !void {
        const now = self.time_source.now();
        try self.animations.append(self.allocator, .{
            .value = value,
            .type = .decay,
            .start_time_ms = now,
            .initial_value = value.current,
            .decay_config = config,
        });
    }

    /// Update all active animations and derived values
    /// Returns true if any animation is still active (needs re-render)
    pub fn update(self: *AnimationManager) bool {
        const now = self.time_source.now();
        var needs_render = false;

        // Track which values changed this frame
        var changed_values = std.AutoHashMap(u64, void).init(self.allocator);
        defer changed_values.deinit();

        // Update animations
        var i: usize = 0;
        while (i < self.animations.items.len) {
            var anim = &self.animations.items[i];

            const should_continue = anim.update(now);

            // Track that this value changed
            changed_values.put(anim.value.id, {}) catch {};

            if (!should_continue) {
                // Animation complete - remove it
                _ = self.animations.swapRemove(i);
                // Don't increment i - we just moved a different element here
            } else {
                needs_render = true;
                i += 1;
            }
        }

        // Update derived values whose dependencies changed
        for (self.derived_values.items) |*derived| {
            var should_update = false;
            for (derived.dependencies) |dep_id| {
                if (changed_values.contains(dep_id)) {
                    should_update = true;
                    break;
                }
            }

            if (should_update) {
                const old_value = derived.value.current;
                derived.update();

                if (old_value != derived.value.current) {
                    changed_values.put(derived.value.id, {}) catch {};
                    needs_render = true;
                }
            }
        }

        // Notify listeners of changed values
        for (self.listeners.items) |*listener| {
            if (changed_values.contains(listener.value_id)) {
                // Find the value
                for (self.values.items) |value| {
                    if (value.id == listener.value_id) {
                        listener.notify(value.current);
                        break;
                    }
                }
            }
        }

        return needs_render;
    }

    /// Check if any animations are active
    pub fn hasActive(self: *const AnimationManager) bool {
        return self.animations.items.len > 0;
    }

    /// Cancel all animations targeting a specific value
    pub fn cancelValue(self: *AnimationManager, value: *const AnimatedValue) void {
        var i: usize = 0;
        while (i < self.animations.items.len) {
            if (self.animations.items[i].value == value) {
                _ = self.animations.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Cancel all animations of a specific type
    pub fn cancelType(self: *AnimationManager, anim_type: AnimationType) void {
        var i: usize = 0;
        while (i < self.animations.items.len) {
            if (self.animations.items[i].type == anim_type) {
                _ = self.animations.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Cancel all animations
    pub fn cancelAll(self: *AnimationManager) void {
        self.animations.clearRetainingCapacity();
    }

    pub fn deinit(self: *AnimationManager) void {
        // Free derived value dependencies
        for (self.derived_values.items) |derived| {
            self.allocator.free(derived.dependencies);
        }

        // Free derived AnimatedValues we created
        for (self.derived_values.items) |derived| {
            self.allocator.destroy(derived.value);
        }

        self.animations.deinit(self.allocator);
        self.values.deinit(self.allocator);
        self.derived_values.deinit(self.allocator);
        self.listeners.deinit(self.allocator);
    }
};

// Tests
test "AnimationManager: basic lifecycle" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    // Initially no active animations
    try testing.expect(!mgr.hasActive());
}

test "AnimationManager: register and animate value" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    var value = AnimatedValue.init(0.0);
    try mgr.registerValue(&value);

    // Start timing animation
    value.setTarget(100.0);
    try mgr.animateTiming(&value, .{
        .duration_ms = 100,
        .easing = .linear,
    });

    try testing.expect(mgr.hasActive());
    try testing.expectEqual(@as(usize, 1), mgr.animations.items.len);
}

test "AnimationManager: spring animation completes" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    mgr.time_source = .mock;
    setMockTime(0);

    var value = AnimatedValue.init(0.0);
    value.setTarget(100.0);
    try mgr.registerValue(&value);

    try mgr.animateSpring(&value, SpringConfig.stiff());

    // Simulate many frames until settled
    var time_ms: i64 = 0;
    var iterations: usize = 0;
    while (iterations < 1000) : (iterations += 1) {
        time_ms += 16;
        setMockTime(time_ms);
        const still_active = mgr.update();
        if (!still_active) break;
    }

    // Should have settled
    try testing.expect(!mgr.hasActive());
    try testing.expectApproxEqAbs(@as(f64, 100.0), value.current, 0.1);
}

test "AnimationManager: derived values update" {
    const testing = std.testing;

    const Context = struct {
        source: *AnimatedValue,

        fn compute(ctx: ?*anyopaque) f64 {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            return self.source.current * 2.0; // Derived = source * 2
        }
    };

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    mgr.time_source = .mock;
    setMockTime(0);

    var source = AnimatedValue.init(10.0);
    try mgr.registerValue(&source);

    var ctx = Context{ .source = &source };
    const deps = [_]u64{source.id};
    const derived = try mgr.createDerived(Context.compute, &ctx, &deps);

    // Initial value
    try testing.expectEqual(@as(f64, 20.0), derived.current);

    // Animate source to new value
    source.setTarget(50.0);
    try mgr.animateTiming(&source, .{
        .duration_ms = 100,
        .easing = .linear,
    });

    // Update to completion
    setMockTime(100);
    _ = mgr.update();

    // Derived should update
    try testing.expectEqual(@as(f64, 100.0), derived.current);
}

test "AnimationManager: listeners get notified" {
    const testing = std.testing;

    const Context = struct {
        notified: bool = false,
        last_value: f64 = 0,

        fn onValueChange(value: f64, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.notified = true;
            self.last_value = value;
        }
    };

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    mgr.time_source = .mock;
    setMockTime(0);

    var value = AnimatedValue.init(0.0);
    value.setTarget(100.0);
    try mgr.registerValue(&value);

    var ctx = Context{};
    try mgr.addListener(value.id, Context.onValueChange, &ctx);

    try mgr.animateTiming(&value, .{
        .duration_ms = 100,
        .easing = .linear,
    });

    // Update animation
    setMockTime(50);
    _ = mgr.update();

    // Listener should have been notified
    try testing.expect(ctx.notified);
    try testing.expect(ctx.last_value > 0.0);
}

test "AnimationManager: cancel animations" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    var value1 = AnimatedValue.init(0.0);
    var value2 = AnimatedValue.init(0.0);

    value1.setTarget(100.0);
    value2.setTarget(100.0);

    try mgr.animateSpring(&value1, SpringConfig.gentle());
    try mgr.animateSpring(&value2, SpringConfig.bouncy());

    try testing.expectEqual(@as(usize, 2), mgr.animations.items.len);

    // Cancel animations on value1
    mgr.cancelValue(&value1);

    try testing.expectEqual(@as(usize, 1), mgr.animations.items.len);
    try testing.expect(mgr.animations.items[0].value == &value2);
}
