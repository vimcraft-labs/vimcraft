const std = @import("std");

/// Animation type identifier
pub const AnimationType = enum {
    yank_highlight,
    cursor_blink,
    search_highlight,
    fade_message,
    scroll_smooth,
};

/// Easing functions for smooth animations
pub const Easing = enum {
    linear,
    ease_in,
    ease_out,
    ease_in_out,

    /// Apply easing function to normalized time (0.0 - 1.0)
    pub fn apply(self: Easing, t: f32) f32 {
        return switch (self) {
            .linear => t,
            .ease_in => t * t,
            .ease_out => t * (2.0 - t),
            .ease_in_out => if (t < 0.5)
                2.0 * t * t
            else
                -1.0 + (4.0 - 2.0 * t) * t,
        };
    }
};

/// Animation instance
pub const Animation = struct {
    type: AnimationType,
    start_ms: i64,
    duration_ms: i64,
    easing: Easing,
    context: ?*anyopaque = null,
    on_update: ?*const fn (ctx: ?*anyopaque, progress: f32) void = null,
    on_complete: ?*const fn (ctx: ?*anyopaque) void = null,

    /// Calculate current progress (0.0 - 1.0)
    /// Returns raw progress (not eased) for manager to determine completion
    pub fn update(self: *Animation, now_ms: i64) f32 {
        const elapsed = now_ms - self.start_ms;
        const raw_progress = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.duration_ms));
        const clamped = @min(raw_progress, 1.0);
        const eased = self.easing.apply(clamped);

        if (self.on_update) |callback| {
            callback(self.context, eased);
        }

        return clamped; // Return raw progress for completion check
    }

    /// Call completion callback
    pub fn complete(self: *Animation) void {
        if (self.on_complete) |callback| {
            callback(self.context);
        }
    }
};

// Tests
test "easing functions" {
    const testing = std.testing;

    // Linear: f(t) = t
    try testing.expectEqual(@as(f32, 0.0), Easing.linear.apply(0.0));
    try testing.expectEqual(@as(f32, 0.5), Easing.linear.apply(0.5));
    try testing.expectEqual(@as(f32, 1.0), Easing.linear.apply(1.0));

    // Ease-in: slower start
    try testing.expect(Easing.ease_in.apply(0.5) < 0.5);

    // Ease-out: slower end
    try testing.expect(Easing.ease_out.apply(0.5) > 0.5);
}

test "animation progress calculation" {
    var anim = Animation{
        .type = .yank_highlight,
        .start_ms = 0,
        .duration_ms = 100,
        .easing = .linear,
    };

    // 0% complete
    try std.testing.expectEqual(@as(f32, 0.0), anim.update(0));

    // 50% complete
    try std.testing.expectEqual(@as(f32, 0.5), anim.update(50));

    // 100% complete
    try std.testing.expectEqual(@as(f32, 1.0), anim.update(100));

    // Over 100% (clamped)
    try std.testing.expectEqual(@as(f32, 1.0), anim.update(150));
}

test "animation callbacks" {
    const TestContext = struct {
        update_count: usize = 0,
        complete_called: bool = false,

        fn onUpdate(ctx: ?*anyopaque, progress: f32) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.update_count += 1;
            _ = progress;
        }

        fn onComplete(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.complete_called = true;
        }
    };

    var test_ctx = TestContext{};

    var anim = Animation{
        .type = .yank_highlight,
        .start_ms = 0,
        .duration_ms = 100,
        .easing = .linear,
        .context = &test_ctx,
        .on_update = TestContext.onUpdate,
        .on_complete = TestContext.onComplete,
    };

    // Trigger update
    _ = anim.update(50);
    try std.testing.expectEqual(@as(usize, 1), test_ctx.update_count);
    try std.testing.expect(!test_ctx.complete_called);

    // Trigger completion
    anim.complete();
    try std.testing.expect(test_ctx.complete_called);
}
