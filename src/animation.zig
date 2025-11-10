// Animation system public exports
// This module provides the complete animation API for OpenVim

// Core types
pub const AnimatedValue = @import("editor/animation/value.zig").AnimatedValue;
pub const ValueListener = @import("editor/animation/value.zig").ValueListener;
pub const ListenerCallback = @import("editor/animation/value.zig").ListenerCallback;

// Animation configuration
pub const Animation = @import("editor/animation/core.zig").Animation;
pub const AnimationType = @import("editor/animation/core.zig").AnimationType;
pub const Easing = @import("editor/animation/core.zig").Easing;
pub const TimingConfig = @import("editor/animation/core.zig").TimingConfig;
pub const SpringConfig = @import("editor/animation/core.zig").SpringConfig;
pub const DecayConfig = @import("editor/animation/core.zig").DecayConfig;

// Interpolation
pub const interpolate = @import("editor/animation/interpolate.zig").interpolate;
pub const interpolateColor = @import("editor/animation/interpolate.zig").interpolateColor;
pub const Extrapolation = @import("editor/animation/interpolate.zig").Extrapolation;
pub const Color = @import("editor/animation/interpolate.zig").Color;
pub const rgb = @import("editor/animation/interpolate.zig").rgb;
pub const getRed = @import("editor/animation/interpolate.zig").getRed;
pub const getGreen = @import("editor/animation/interpolate.zig").getGreen;
pub const getBlue = @import("editor/animation/interpolate.zig").getBlue;

// Manager
pub const AnimationManager = @import("editor/animation/manager.zig").AnimationManager;
pub const DerivedValue = @import("editor/animation/manager.zig").DerivedValue;
pub const DerivedFunction = @import("editor/animation/manager.zig").DerivedFunction;
pub const TimeSource = @import("editor/animation/manager.zig").TimeSource;
pub const setMockTime = @import("editor/animation/manager.zig").setMockTime;

test {
    @import("std").testing.refAllDecls(@This());
}
