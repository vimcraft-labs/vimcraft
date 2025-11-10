/// JSI Helper Functions
/// Common utilities for working with Hermes JavaScript Interface
/// Used across all JSI API modules to reduce code duplication

const std = @import("std");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Extract string from JSI argument
/// Copies string to provided buffer to avoid shared buffer corruption
/// Returns error if argument is null, not a string, or too long for buffer
pub fn extractStringArg(runtime: *c.OVHermesRuntime, arg: ?*c.OVHermesValue, buffer: []u8) ![]const u8 {
    if (arg == null) return error.NullArg;
    if (!c.hermes_value_is_string(arg)) return error.NotAString;

    var len: usize = 0;
    const ptr = c.hermes_value_get_string(runtime, arg, &len) orelse return error.NullString;

    if (len >= buffer.len) return error.StringTooLong;

    @memcpy(buffer[0..len], ptr[0..len]);
    return buffer[0..len];
}

/// Return undefined to JavaScript
/// This is the most common return value for host functions
pub fn returnUndefined(runtime: ?*c.OVHermesRuntime) ?*c.OVHermesValue {
    return c.hermes_value_create_undefined(runtime);
}

/// Return error with optional logging
/// Logs error message and returns undefined
pub fn returnError(runtime: ?*c.OVHermesRuntime, comptime error_msg: []const u8) ?*c.OVHermesValue {
    std.debug.print("[JSI] {s}\n", .{error_msg});
    return c.hermes_value_create_undefined(runtime);
}

/// Extract number from JSI argument
/// Returns error if argument is null or not a number
pub fn extractNumberArg(runtime: *c.OVHermesRuntime, arg: ?*c.OVHermesValue) !f64 {
    _ = runtime;
    if (arg == null) return error.NullArg;
    if (!c.hermes_value_is_number(arg)) return error.NotANumber;

    return c.hermes_value_get_number(arg);
}

/// Extract boolean from JSI argument
/// Returns error if argument is null or not a boolean
pub fn extractBooleanArg(arg: ?*c.OVHermesValue) !bool {
    if (arg == null) return error.NullArg;
    if (!c.hermes_value_is_boolean(arg)) return error.NotABoolean;

    return c.hermes_value_get_boolean(arg);
}

/// Check if number is valid (not NaN or Infinity)
pub fn isValidNumber(num: f64) bool {
    return !std.math.isNan(num) and !std.math.isInf(num);
}

/// Validate number is finite and non-negative
pub fn validateNonNegativeNumber(num: f64) !void {
    if (std.math.isNan(num) or std.math.isInf(num) or num < 0) {
        return error.InvalidNumber;
    }
}
