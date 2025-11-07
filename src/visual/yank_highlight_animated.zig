const std = @import("std");
const Position = @import("visual.zig").Position;
const VisualMode = @import("visual.zig").VisualMode;
const animation = @import("animation");
const AnimatedValue = animation.AnimatedValue;
const AnimationManager = animation.AnimationManager;
const SpringConfig = animation.SpringConfig;
const TimingConfig = animation.TimingConfig;

/// Animated yank highlight - demonstrates the animation system
/// Shows smooth fade-out with spring-based intensity
pub const AnimatedYankHighlight = struct {
    active: bool = false,
    mode: VisualMode = .char,
    start: Position = .{ .line = 0, .col = 0 },
    end: Position = .{ .line = 0, .col = 0 },

    // Animation values
    opacity: AnimatedValue, // Fades from 1.0 to 0.0
    intensity: AnimatedValue, // Spring-based flash effect (0.5 -> 1.0 -> 0.8)

    /// Initialize yank highlight with animation
    pub fn init(allocator: std.mem.Allocator, start_pos: Position, end_pos: Position, mode: VisualMode, anim_mgr: *AnimationManager) !AnimatedYankHighlight {
        // Normalize positions
        var start = start_pos;
        var end = end_pos;
        if (!start_pos.lessThan(end_pos)) {
            start = end_pos;
            end = start_pos;
        }

        // Create animated values
        var opacity = AnimatedValue.init(1.0);
        var intensity = AnimatedValue.init(0.5);

        try anim_mgr.registerValue(&opacity);
        try anim_mgr.registerValue(&intensity);

        // Start animations
        // 1. Opacity: smooth fade out over 300ms
        opacity.setTarget(0.0);
        try anim_mgr.animateTiming(&opacity, .{
            .duration_ms = 300,
            .easing = .ease_out,
        });

        // 2. Intensity: flash effect with spring
        intensity.setTarget(1.0);
        try anim_mgr.animateSpring(&intensity, SpringConfig.bouncy());

        // After spring settles, fade to 0.8 over 200ms
        // NOTE: In real usage, this would be triggered by on_complete callback
        // For now, we'll let spring animation complete naturally

        _ = allocator; // Will be used for derived values in future

        return .{
            .active = true,
            .mode = mode,
            .start = start,
            .end = end,
            .opacity = opacity,
            .intensity = intensity,
        };
    }

    /// Get current opacity (0.0 = invisible, 1.0 = fully visible)
    pub fn getOpacity(self: *const AnimatedYankHighlight) f64 {
        return self.opacity.get();
    }

    /// Get current intensity (controls highlight brightness)
    pub fn getIntensity(self: *const AnimatedYankHighlight) f64 {
        return self.intensity.get();
    }

    /// Check if highlight should still be visible
    pub fn isVisible(self: *const AnimatedYankHighlight) bool {
        if (!self.active) return false;
        return self.opacity.get() > 0.01; // Visible if opacity > 1%
    }

    /// Deactivate highlight
    pub fn deactivate(self: *AnimatedYankHighlight) void {
        self.active = false;
    }

    /// Check if position is within yank highlight
    pub fn contains(self: *const AnimatedYankHighlight, pos: Position) bool {
        if (!self.active) return false;

        switch (self.mode) {
            .char => {
                if (pos.line < self.start.line or pos.line > self.end.line) {
                    return false;
                }
                if (pos.line == self.start.line and pos.col < self.start.col) {
                    return false;
                }
                if (pos.line == self.end.line and pos.col > self.end.col) {
                    return false;
                }
                return true;
            },
            .line => {
                return pos.line >= self.start.line and pos.line <= self.end.line;
            },
            .block => {
                return pos.line >= self.start.line and
                    pos.line <= self.end.line and
                    pos.col >= self.start.col and
                    pos.col <= self.end.col;
            },
        }
    }
};

// Tests
test "AnimatedYankHighlight: opacity fades" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    mgr.time_source = .mock;
    @import("../animation/manager.zig").setMockTime(0);

    const start = Position{ .line = 0, .col = 5 };
    const end = Position{ .line = 0, .col = 10 };
    var yh = try AnimatedYankHighlight.init(testing.allocator, start, end, .char, &mgr);

    // Initially at 1.0 opacity
    try testing.expectEqual(@as(f64, 1.0), yh.getOpacity());

    // After 150ms (50% through 300ms fade)
    @import("../animation/manager.zig").setMockTime(150);
    _ = mgr.update();
    const mid_opacity = yh.getOpacity();
    try testing.expect(mid_opacity > 0.3 and mid_opacity < 0.7);

    // After 300ms: should be at or near 0.0
    @import("../animation/manager.zig").setMockTime(300);
    _ = mgr.update();
    try testing.expectApproxEqAbs(@as(f64, 0.0), yh.getOpacity(), 0.01);

    // Should no longer be visible
    try testing.expect(!yh.isVisible());
}

test "AnimatedYankHighlight: intensity springs" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    mgr.time_source = .mock;
    @import("../animation/manager.zig").setMockTime(0);

    const start = Position{ .line = 0, .col = 5 };
    const end = Position{ .line = 0, .col = 10 };
    var yh = try AnimatedYankHighlight.init(testing.allocator, start, end, .char, &mgr);

    // Initially at 0.5 intensity
    try testing.expectEqual(@as(f64, 0.5), yh.getIntensity());

    // After a few frames, should move towards 1.0
    var time_ms: i64 = 0;
    var moved = false;
    var iterations: usize = 0;
    while (iterations < 10) : (iterations += 1) {
        time_ms += 16;
        @import("../animation/manager.zig").setMockTime(time_ms);
        _ = mgr.update();
        if (yh.getIntensity() > 0.6) {
            moved = true;
            break;
        }
    }

    try testing.expect(moved);
}

test "AnimatedYankHighlight: contains position" {
    const testing = std.testing;

    var mgr = AnimationManager.init(testing.allocator);
    defer mgr.deinit();

    const yh = try AnimatedYankHighlight.init(
        testing.allocator,
        .{ .line = 0, .col = 5 },
        .{ .line = 0, .col = 10 },
        .char,
        &mgr,
    );

    try testing.expect(yh.contains(.{ .line = 0, .col = 7 }));
    try testing.expect(!yh.contains(.{ .line = 0, .col = 3 }));
    try testing.expect(!yh.contains(.{ .line = 0, .col = 12 }));
}
