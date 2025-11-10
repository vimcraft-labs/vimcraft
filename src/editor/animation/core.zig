const std = @import("std");
const AnimatedValue = @import("value.zig").AnimatedValue;

/// Animation types
pub const AnimationType = enum {
    timing, // Duration-based with easing
    spring, // Physics-based (damped spring)
    decay,  // Velocity-based deceleration
};

/// Easing functions for timing animations
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

    /// Apply easing function to normalized time (0.0 - 1.0)
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
            else blk: {
                const t1 = t - 1.0;
                break :blk t1 * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0;
            },
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
        };
    }
};

/// Timing animation configuration
pub const TimingConfig = struct {
    duration_ms: u32,
    easing: Easing = .ease_in_out,
    delay_ms: u32 = 0,
};

/// Spring animation configuration
/// Based on Roblox Fraktality's damped spring algorithm
/// https://gist.github.com/Fraktality/1033625223e13c01aa7144abe4aaf54d
pub const SpringConfig = struct {
    damping: f64 = 10.0,    // Resistance (higher = less bounce)
    stiffness: f64 = 100.0, // Spring strength (higher = faster)
    mass: f64 = 1.0,        // Object mass (higher = slower)
    velocity: f64 = 0.0,    // Initial velocity

    /// Gentle spring (smooth, no overshoot)
    pub fn gentle() SpringConfig {
        return .{ .damping = 20.0, .stiffness = 120.0 };
    }

    /// Bouncy spring (fun, playful)
    pub fn bouncy() SpringConfig {
        return .{ .damping = 8.0, .stiffness = 180.0 };
    }

    /// Stiff spring (snappy, fast)
    pub fn stiff() SpringConfig {
        return .{ .damping = 26.0, .stiffness = 210.0 };
    }

    /// Slow spring (smooth, gentle)
    pub fn slow() SpringConfig {
        return .{ .damping = 26.0, .stiffness = 70.0 };
    }
};

/// Decay animation configuration
pub const DecayConfig = struct {
    velocity: f64,
    deceleration: f64 = 0.998, // Friction coefficient (higher = less friction)
};

/// Animation drives an AnimatedValue towards a target
pub const Animation = struct {
    value: *AnimatedValue,
    type: AnimationType,
    start_time_ms: i64,
    initial_value: f64 = 0.0, // Value at animation start

    // Config based on type
    timing_config: ?TimingConfig = null,
    spring_config: ?SpringConfig = null,
    decay_config: ?DecayConfig = null,

    // Lifecycle callbacks
    on_update: ?*const fn (value: f64, context: ?*anyopaque) void = null,
    on_complete: ?*const fn (context: ?*anyopaque) void = null,
    callback_context: ?*anyopaque = null,

    /// Update animation (called every frame)
    /// Returns true if animation should continue
    pub fn update(self: *Animation, now_ms: i64) bool {
        const elapsed_ms = now_ms - self.start_time_ms;

        const should_continue = switch (self.type) {
            .timing => self.updateTiming(elapsed_ms),
            .spring => self.updateSpring(elapsed_ms),
            .decay => self.updateDecay(elapsed_ms),
        };

        // Fire on_update callback
        if (self.on_update) |callback| {
            callback(self.value.current, self.callback_context);
        }

        // Fire on_complete if done
        if (!should_continue) {
            if (self.on_complete) |callback| {
                callback(self.callback_context);
            }
        }

        return should_continue;
    }

    fn updateTiming(self: *Animation, elapsed_ms: i64) bool {
        const config = self.timing_config.?;

        // Handle delay
        if (elapsed_ms < config.delay_ms) {
            return true;
        }

        const adjusted_elapsed = @as(f64, @floatFromInt(elapsed_ms - config.delay_ms));
        const duration = @as(f64, @floatFromInt(config.duration_ms));
        const t = adjusted_elapsed / duration;

        if (t >= 1.0) {
            self.value.current = self.value.target;
            return false; // Animation complete
        }

        // Apply easing
        const eased_t = config.easing.apply(t);

        // Interpolate from initial to target
        self.value.current = self.initial_value + (self.value.target - self.initial_value) * eased_t;

        return true;
    }

    fn updateSpring(self: *Animation, elapsed_ms: i64) bool {
        _ = elapsed_ms;
        const config = self.spring_config.?;
        const dt = 0.016; // 60fps = ~16ms per frame

        // Spring physics: F = -kx - cv
        // Hooke's law (spring force) + damping force
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
            return false; // Animation complete
        }

        return true;
    }

    fn updateDecay(self: *Animation, elapsed_ms: i64) bool {
        _ = elapsed_ms;
        const config = self.decay_config.?;
        const dt = 0.016; // 60fps

        // Decay: v = v * deceleration
        self.value.velocity *= config.deceleration;
        self.value.current += self.value.velocity * dt;

        // Stop when velocity is very small
        if (@abs(self.value.velocity) < 0.1) {
            self.value.velocity = 0;
            self.value.target = self.value.current; // Lock to final position
            return false;
        }

        return true;
    }
};

// Tests
test "Easing: linear" {
    try std.testing.expectEqual(@as(f64, 0.0), Easing.linear.apply(0.0));
    try std.testing.expectEqual(@as(f64, 0.5), Easing.linear.apply(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), Easing.linear.apply(1.0));
}

test "Easing: ease_in is slower at start" {
    const at_25 = Easing.ease_in.apply(0.25);
    try std.testing.expect(at_25 < 0.25); // Slower than linear
}

test "Easing: ease_out is faster at start" {
    const at_25 = Easing.ease_out.apply(0.25);
    try std.testing.expect(at_25 > 0.25); // Faster than linear
}

test "SpringConfig: presets" {
    const gentle = SpringConfig.gentle();
    try std.testing.expectEqual(@as(f64, 20.0), gentle.damping);
    try std.testing.expectEqual(@as(f64, 120.0), gentle.stiffness);

    const bouncy = SpringConfig.bouncy();
    try std.testing.expect(bouncy.damping < gentle.damping); // More bounce
}

test "Animation: timing basics" {
    var value = AnimatedValue.init(0.0);
    value.setTarget(100.0);

    var anim = Animation{
        .value = &value,
        .type = .timing,
        .start_time_ms = 0,
        .initial_value = 0.0,
        .timing_config = .{
            .duration_ms = 100,
            .easing = .linear,
        },
    };

    // At 50ms: should be at 50%
    _ = anim.update(50);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), value.current, 0.01);

    // At 100ms: should be at 100%
    const done = !anim.update(100);
    try std.testing.expect(done);
    try std.testing.expectEqual(@as(f64, 100.0), value.current);
}

test "Animation: spring moves towards target" {
    var value = AnimatedValue.init(0.0);
    value.setTarget(100.0);

    var anim = Animation{
        .value = &value,
        .type = .spring,
        .start_time_ms = 0,
        .spring_config = SpringConfig.stiff(),
    };

    // After one frame, value should have moved towards target
    const initial = value.current;
    _ = anim.update(16);
    try std.testing.expect(value.current > initial);
    try std.testing.expect(value.current < 100.0);
}

test "Animation: spring eventually settles" {
    var value = AnimatedValue.init(0.0);
    value.setTarget(100.0);

    var anim = Animation{
        .value = &value,
        .type = .spring,
        .start_time_ms = 0,
        .spring_config = SpringConfig.stiff(),
    };

    // Simulate many frames
    var time_ms: i64 = 0;
    var settled = false;
    var iterations: usize = 0;
    while (iterations < 1000) : (iterations += 1) {
        time_ms += 16;
        const should_continue = anim.update(time_ms);
        if (!should_continue) {
            settled = true;
            break;
        }
    }

    try std.testing.expect(settled);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), value.current, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), value.velocity, 0.1);
}

test "Animation: decay slows down" {
    var value = AnimatedValue.init(0.0);
    value.velocity = 100.0; // Initial velocity

    var anim = Animation{
        .value = &value,
        .type = .decay,
        .start_time_ms = 0,
        .decay_config = .{
            .velocity = 100.0,
            .deceleration = 0.95, // Strong friction for faster test
        },
    };

    // After frames, velocity should decrease
    _ = anim.update(16);
    try std.testing.expect(value.velocity < 100.0);

    _ = anim.update(32);
    try std.testing.expect(value.velocity < 95.0);
}
