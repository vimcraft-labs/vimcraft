/// Buffer API Module
/// Exposes buffer content via ArrayBuffer
/// Works with current ArrayList-based buffer (will upgrade to Rope later)
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const helpers = @import("helpers.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// vim.buffer.getContent() -> ArrayBuffer
/// Returns buffer content as External ArrayBuffer (zero-copy!)
///
/// JavaScript usage:
///   const ab = vim.buffer.getContent();          // ArrayBuffer
///   const view = new Uint8Array(ab);             // View into native memory
///   const text = new TextDecoder().decode(view); // Convert to string if needed
///
/// ⚠️  IMPORTANT: This is a SNAPSHOT! ArrayBuffer is invalidated when:
///    - Buffer is modified (insert/delete)
///    - Buffer is reallocated (grows beyond capacity)
///    - Buffer version changes
///
/// Safe pattern:
///   const snapshot = new Uint8Array(vim.buffer.getContent()).slice(); // Copy immediately
pub export fn getBufferContent(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    // Get current buffer content
    const content = buffer.content.items;

    // Return External ArrayBuffer (zero-copy!)
    // Finalizer is NULL because buffer owns the memory
    // JavaScript gets read-only view into native ArrayList
    return c.hermes_value_create_arraybuffer_external(
        rt,
        @ptrCast(@constCast(content.ptr)),
        content.len,
        null, // No finalizer - buffer owns the memory
        null, // No finalizer context
    );
}

/// vim.buffer.getContentCopy() -> string
/// Returns buffer content as string (copy)
/// (Identical to getContent() for now, kept for API compatibility)
///
/// JavaScript usage:
///   const content = vim.buffer.getContentCopy();  // string
pub export fn getBufferContentCopy(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // For now, identical to getContent() since both return strings
    return getBufferContent(runtime, context, args, count);
}

/// vim.buffer.getLineContent(line_num) -> ArrayBuffer
/// Returns a single line as External ArrayBuffer (zero-copy!)
///
/// JavaScript usage:
///   const ab = vim.buffer.getLineContent(5);     // ArrayBuffer for line 5
///   const view = new Uint8Array(ab);             // View into native memory
///   const text = new TextDecoder().decode(view); // Convert to string if needed
///
/// ⚠️  IMPORTANT: This is a SNAPSHOT! ArrayBuffer is invalidated on buffer modifications.
pub export fn getLineContent(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    if (count < 1) return c.hermes_value_create_null(rt);

    const line_num_val = args[0] orelse return c.hermes_value_create_null(rt);
    const line_num = @as(usize, @intFromFloat(c.hermes_value_get_number(line_num_val)));

    // Get line slice
    const line = buffer.getLine(line_num) orelse return c.hermes_value_create_null(rt);

    // Return External ArrayBuffer (zero-copy!)
    return c.hermes_value_create_arraybuffer_external(
        rt,
        @ptrCast(@constCast(line.ptr)),
        line.len,
        null, // No finalizer - buffer owns the memory
        null, // No finalizer context
    );
}

/// vim.buffer.getLength() -> number
/// Returns buffer content length in bytes
pub export fn getBufferLength(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    return c.hermes_value_create_number(rt, @floatFromInt(buffer.content.items.len));
}

/// vim.buffer.getLineCount() -> number
/// Returns number of lines in buffer
pub export fn getBufferLineCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    return c.hermes_value_create_number(rt, @floatFromInt(buffer.lineCount()));
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.buffer HostObject getter - routes property access to methods
pub export fn bufferHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Use StaticStringMap for O(1) property dispatch
    const PropertyMap = std.StaticStringMap(*const fn (
        ?*c.OVHermesRuntime,
        ?*anyopaque,
        [*c]?*c.OVHermesValue,
        usize,
    ) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "getContent", getBufferContent },
        .{ "getContentCopy", getBufferContentCopy },
        .{ "getLineContent", getLineContent },
        .{ "getLength", getBufferLength },
        .{ "getLineCount", getBufferLineCount },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.buffer HostObject enumerator - returns array of method names
pub export fn bufferHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "getContent",
        "getContentCopy",
        "getLineContent",
        "getLength",
        "getLineCount",
    };

    const arr = c.hermes_array_create(rt, method_names.len) orelse return null;

    for (method_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register buffer API as HostObject (zero-copy ArrayBuffer access)
/// JavaScript usage: vim.buffer.getContent(), vim.buffer.getLineContent(5)
pub fn register(runtime: *c.OVHermesRuntime, buffer: *Buffer) void {
    c.hermes_register_host_object(
        runtime,
        "vimBuffer",
        bufferHostObjectGet,
        null, // No setter (read-only methods for now)
        bufferHostObjectEnumerator,
        @ptrCast(buffer),
    );
}

/// Legacy registration (backwards compatibility)
/// TODO: Remove after all examples/tests updated
pub fn registerLegacy(runtime: *c.OVHermesRuntime, buffer: *Buffer) void {
    c.hermes_register_host_function(
        runtime,
        "getBufferContent",
        getBufferContent,
        @ptrCast(buffer),
    );
    c.hermes_register_host_function(
        runtime,
        "getBufferContentCopy",
        getBufferContentCopy,
        @ptrCast(buffer),
    );
    c.hermes_register_host_function(
        runtime,
        "getLineContent",
        getLineContent,
        @ptrCast(buffer),
    );
}
