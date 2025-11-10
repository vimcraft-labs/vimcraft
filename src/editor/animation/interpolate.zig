const std = @import("std");

/// Extrapolation mode for values outside the input range
pub const Extrapolation = enum {
    clamp,    // Clamp to range edges (default)
    extend,   // Linear extrapolation beyond range
    identity, // Return input value unchanged
};

/// Interpolate a value from input range to output range
/// Similar to React Native Reanimated's interpolate()
///
/// Example:
///   interpolate(50, &[_]f64{0, 100}, &[_]f64{0, 1}, .clamp) => 0.5
///   interpolate(150, &[_]f64{0, 100}, &[_]f64{0, 360}, .clamp) => 360
pub fn interpolate(
    input: f64,
    input_range: []const f64,
    output_range: []const f64,
    extrapolate: Extrapolation,
) f64 {
    std.debug.assert(input_range.len == output_range.len);
    std.debug.assert(input_range.len >= 2);

    // Find the segment containing input
    var segment_start: usize = 0;
    for (input_range, 0..) |val, i| {
        if (i == input_range.len - 1) break;
        if (input >= val and input <= input_range[i + 1]) {
            segment_start = i;
            break;
        }
    }

    // Handle left extrapolation (input < first)
    if (input < input_range[0]) {
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

    // Handle right extrapolation (input > last)
    if (input > input_range[input_range.len - 1]) {
        const last = input_range.len - 1;
        return switch (extrapolate) {
            .clamp => output_range[last],
            .extend => {
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

/// RGB color represented as 0xRRGGBB
pub const Color = u32;

/// Extract red component (0-255)
pub fn getRed(color: Color) u8 {
    return @intCast((color >> 16) & 0xFF);
}

/// Extract green component (0-255)
pub fn getGreen(color: Color) u8 {
    return @intCast((color >> 8) & 0xFF);
}

/// Extract blue component (0-255)
pub fn getBlue(color: Color) u8 {
    return @intCast(color & 0xFF);
}

/// Create color from RGB components
pub fn rgb(r: u8, g: u8, b: u8) Color {
    return (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

/// Interpolate between colors
/// Similar to React Native Reanimated's interpolateColor()
///
/// Example:
///   interpolateColor(50, &[_]f64{0, 100}, &[_]Color{0xFF0000, 0x00FF00}, .clamp)
///   => color halfway between red and green
pub fn interpolateColor(
    input: f64,
    input_range: []const f64,
    colors: []const Color,
    extrapolate: Extrapolation,
) Color {
    std.debug.assert(input_range.len == colors.len);

    // Extract RGB components into separate ranges
    var r_range: [16]f64 = undefined; // Support up to 16 keyframes
    var g_range: [16]f64 = undefined;
    var b_range: [16]f64 = undefined;

    std.debug.assert(colors.len <= 16);

    for (colors, 0..) |color, i| {
        r_range[i] = @floatFromInt(getRed(color));
        g_range[i] = @floatFromInt(getGreen(color));
        b_range[i] = @floatFromInt(getBlue(color));
    }

    // Interpolate each component and clamp to 0-255
    const r_val = interpolate(input, input_range, r_range[0..colors.len], extrapolate);
    const g_val = interpolate(input, input_range, g_range[0..colors.len], extrapolate);
    const b_val = interpolate(input, input_range, b_range[0..colors.len], extrapolate);

    const r = @as(u8, @intFromFloat(@round(@min(@max(r_val, 0.0), 255.0))));
    const g = @as(u8, @intFromFloat(@round(@min(@max(g_val, 0.0), 255.0))));
    const b = @as(u8, @intFromFloat(@round(@min(@max(b_val, 0.0), 255.0))));

    return rgb(r, g, b);
}

// Tests
test "interpolate: basic linear" {
    const result = interpolate(
        50,
        &[_]f64{ 0, 100 },
        &[_]f64{ 0, 1 },
        .clamp,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result, 0.001);
}

test "interpolate: multiple keyframes" {
    // 0 -> 0, 100 -> 1, 200 -> 0 (fade in, fade out)
    const at_0 = interpolate(0, &[_]f64{ 0, 100, 200 }, &[_]f64{ 0, 1, 0 }, .clamp);
    const at_50 = interpolate(50, &[_]f64{ 0, 100, 200 }, &[_]f64{ 0, 1, 0 }, .clamp);
    const at_100 = interpolate(100, &[_]f64{ 0, 100, 200 }, &[_]f64{ 0, 1, 0 }, .clamp);
    const at_150 = interpolate(150, &[_]f64{ 0, 100, 200 }, &[_]f64{ 0, 1, 0 }, .clamp);
    const at_200 = interpolate(200, &[_]f64{ 0, 100, 200 }, &[_]f64{ 0, 1, 0 }, .clamp);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), at_0, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), at_50, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), at_100, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), at_150, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), at_200, 0.001);
}

test "interpolate: clamp extrapolation" {
    const below = interpolate(-50, &[_]f64{ 0, 100 }, &[_]f64{ 0, 1 }, .clamp);
    const above = interpolate(150, &[_]f64{ 0, 100 }, &[_]f64{ 0, 1 }, .clamp);

    try std.testing.expectEqual(@as(f64, 0.0), below);
    try std.testing.expectEqual(@as(f64, 1.0), above);
}

test "interpolate: extend extrapolation" {
    const below = interpolate(-50, &[_]f64{ 0, 100 }, &[_]f64{ 0, 1 }, .extend);
    const above = interpolate(150, &[_]f64{ 0, 100 }, &[_]f64{ 0, 1 }, .extend);

    try std.testing.expectApproxEqAbs(@as(f64, -0.5), below, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), above, 0.001);
}

test "interpolate: identity extrapolation" {
    const below = interpolate(-50, &[_]f64{ 0, 100 }, &[_]f64{ 0, 1 }, .identity);
    try std.testing.expectEqual(@as(f64, -50.0), below);
}

test "color: RGB extraction" {
    const red = rgb(255, 0, 0);
    try std.testing.expectEqual(@as(u8, 255), getRed(red));
    try std.testing.expectEqual(@as(u8, 0), getGreen(red));
    try std.testing.expectEqual(@as(u8, 0), getBlue(red));

    const cyan = rgb(0, 255, 255);
    try std.testing.expectEqual(@as(u8, 0), getRed(cyan));
    try std.testing.expectEqual(@as(u8, 255), getGreen(cyan));
    try std.testing.expectEqual(@as(u8, 255), getBlue(cyan));
}

test "interpolateColor: red to green" {
    const color = interpolateColor(
        50,
        &[_]f64{ 0, 100 },
        &[_]Color{ rgb(255, 0, 0), rgb(0, 255, 0) },
        .clamp,
    );

    // Halfway between red and green
    try std.testing.expectApproxEqAbs(@as(f64, 127.5), @as(f64, @floatFromInt(getRed(color))), 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 127.5), @as(f64, @floatFromInt(getGreen(color))), 1.0);
    try std.testing.expectEqual(@as(u8, 0), getBlue(color));
}

test "interpolateColor: three colors" {
    // Red -> Green -> Blue
    const at_0 = interpolateColor(
        0,
        &[_]f64{ 0, 100, 200 },
        &[_]Color{ rgb(255, 0, 0), rgb(0, 255, 0), rgb(0, 0, 255) },
        .clamp,
    );
    const at_100 = interpolateColor(
        100,
        &[_]f64{ 0, 100, 200 },
        &[_]Color{ rgb(255, 0, 0), rgb(0, 255, 0), rgb(0, 0, 255) },
        .clamp,
    );
    const at_200 = interpolateColor(
        200,
        &[_]f64{ 0, 100, 200 },
        &[_]Color{ rgb(255, 0, 0), rgb(0, 255, 0), rgb(0, 0, 255) },
        .clamp,
    );

    try std.testing.expectEqual(rgb(255, 0, 0), at_0);
    try std.testing.expectEqual(rgb(0, 255, 0), at_100);
    try std.testing.expectEqual(rgb(0, 0, 255), at_200);
}
