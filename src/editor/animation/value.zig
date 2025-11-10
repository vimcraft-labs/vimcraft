const std = @import("std");

/// Unique identifier for animated values
var next_id: u64 = 1;

fn generateId() u64 {
    const id = next_id;
    next_id += 1;
    return id;
}

/// AnimatedValue - The foundation of the animation system
/// Similar to React Native Reanimated's SharedValue
///
/// An AnimatedValue can be:
/// - A regular value that gets animated (e.g., scrollY, opacity)
/// - A derived value computed from other AnimatedValues
///
/// Plugin developers interact with AnimatedValues, not animations directly.
pub const AnimatedValue = struct {
    id: u64,
    current: f64,
    target: f64,
    velocity: f64,

    // For derived values
    is_derived: bool = false,

    /// Create a new animated value
    pub fn init(initial: f64) AnimatedValue {
        return .{
            .id = generateId(),
            .current = initial,
            .target = initial,
            .velocity = 0,
        };
    }

    /// Get current value
    pub fn get(self: *const AnimatedValue) f64 {
        return self.current;
    }

    /// Set value immediately (no animation)
    pub fn set(self: *AnimatedValue, value: f64) void {
        self.current = value;
        self.target = value;
        self.velocity = 0;
    }

    /// Set target for animation (call Animation.start() to animate)
    pub fn setTarget(self: *AnimatedValue, value: f64) void {
        self.target = value;
    }
};

/// Listener callback type
pub const ListenerCallback = *const fn (value: f64, context: ?*anyopaque) void;

/// Listener for value changes
pub const ValueListener = struct {
    value_id: u64,
    callback: ListenerCallback,
    context: ?*anyopaque,

    pub fn notify(self: *const ValueListener, value: f64) void {
        self.callback(value, self.context);
    }
};

// Tests
test "AnimatedValue: init and get" {
    const value = AnimatedValue.init(100.0);
    try std.testing.expectEqual(@as(f64, 100.0), value.get());
    try std.testing.expectEqual(@as(f64, 100.0), value.current);
    try std.testing.expectEqual(@as(f64, 100.0), value.target);
    try std.testing.expectEqual(@as(f64, 0.0), value.velocity);
}

test "AnimatedValue: set" {
    var value = AnimatedValue.init(100.0);
    value.set(200.0);
    try std.testing.expectEqual(@as(f64, 200.0), value.get());
    try std.testing.expectEqual(@as(f64, 200.0), value.target);
    try std.testing.expectEqual(@as(f64, 0.0), value.velocity);
}

test "AnimatedValue: setTarget" {
    var value = AnimatedValue.init(100.0);
    value.setTarget(200.0);
    try std.testing.expectEqual(@as(f64, 100.0), value.current);
    try std.testing.expectEqual(@as(f64, 200.0), value.target);
}

test "AnimatedValue: unique IDs" {
    const v1 = AnimatedValue.init(1.0);
    const v2 = AnimatedValue.init(2.0);
    try std.testing.expect(v1.id != v2.id);
}
