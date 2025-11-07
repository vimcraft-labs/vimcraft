// Animation system public exports
// This module provides the complete animation API for OpenVim

// Core types
pub const AnimatedValue = @import("animation/value.zig").AnimatedValue;
pub const ValueListener = @import("animation/value.zig").ValueListener;
pub const ListenerCallback = @import("animation/value.zig").ListenerCallback;

// Animation configuration
pub const Animation = @import("animation/core.zig").Animation;
pub const AnimationType = @import("animation/core.zig").AnimationType;
pub const Easing = @import("animation/core.zig").Easing;
pub const TimingConfig = @import("animation/core.zig").TimingConfig;
pub const SpringConfig = @import("animation/core.zig").SpringConfig;
pub const DecayConfig = @import("animation/core.zig").DecayConfig;

// Interpolation
pub const interpolate = @import("animation/interpolate.zig").interpolate;
pub const interpolateColor = @import("animation/interpolate.zig").interpolateColor;
pub const Extrapolation = @import("animation/interpolate.zig").Extrapolation;
pub const Color = @import("animation/interpolate.zig").Color;
pub const rgb = @import("animation/interpolate.zig").rgb;
pub const getRed = @import("animation/interpolate.zig").getRed;
pub const getGreen = @import("animation/interpolate.zig").getGreen;
pub const getBlue = @import("animation/interpolate.zig").getBlue;

// Manager
pub const AnimationManager = @import("animation/manager.zig").AnimationManager;
pub const DerivedValue = @import("animation/manager.zig").DerivedValue;
pub const DerivedFunction = @import("animation/manager.zig").DerivedFunction;
pub const TimeSource = @import("animation/manager.zig").TimeSource;
pub const setMockTime = @import("animation/manager.zig").setMockTime;

test {
    @import("std").testing.refAllDecls(@This());
}
