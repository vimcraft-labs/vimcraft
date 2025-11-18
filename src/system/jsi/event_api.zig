/// Event API - JavaScript bindings for EventEmitter
/// Exposes vim.on(), vim.off(), vim.emit() to JavaScript
///
/// Critical for Phase 4 autocommands
///
/// Usage:
///   vim.on('BufEnter', (bufnr) => console.log('Entered buffer', bufnr));
///   vim.off('BufEnter', callback);
///   vim.emit('CustomEvent', arg1, arg2);
const std = @import("std");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const c_api = @import("c_api.zig");
const c = c_api.c;

/// vim.on(event_name, callback)
/// Register an event listener
///
/// JavaScript usage:
///   vim.on('BufEnter', (bufnr) => {
///       console.log('Entered buffer', bufnr);
///   });
///
/// Arguments:
///   args[0]: event_name (string) - Event to listen for
///   args[1]: callback (function) - Function to call when event fires
///
/// Returns: undefined
pub export fn eventOn(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Validate arguments
    if (count < 2) {
        std.debug.print("[vim.on] Error: requires 2 arguments (event_name, callback)\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name (arg 0)
    if (!c.hermes_value_is_string(args[0])) {
        std.debug.print("[vim.on] Error: event_name must be a string\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Get callback (arg 1)
    const callback = args[1] orelse {
        std.debug.print("[vim.on] Error: callback is null\n", .{});
        return c.hermes_value_create_undefined(rt);
    };

    if (!c.hermes_value_is_function(rt, callback)) {
        std.debug.print("[vim.on] Error: callback must be a function\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    // Register callback
    emitter.on(event_name, callback) catch |err| {
        std.debug.print("[vim.on] Error registering callback for '{s}': {}\n", .{ event_name, err });
        return c.hermes_value_create_undefined(rt);
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.off(event_name, callback)
/// Remove an event listener
///
/// JavaScript usage:
///   const handler = (bufnr) => console.log(bufnr);
///   vim.on('BufEnter', handler);
///   vim.off('BufEnter', handler);  // Remove specific handler
///
/// Arguments:
///   args[0]: event_name (string) - Event name
///   args[1]: callback (function) - Callback to remove
///
/// Returns: undefined
///
/// NOTE: Currently removes ALL listeners for the event (TODO: selective removal)
pub export fn eventOff(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Validate arguments
    if (count < 2) {
        std.debug.print("[vim.off] Error: requires 2 arguments (event_name, callback)\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name (arg 0)
    if (!c.hermes_value_is_string(args[0])) {
        std.debug.print("[vim.off] Error: event_name must be a string\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Get callback (arg 1)
    const callback = args[1] orelse {
        std.debug.print("[vim.off] Error: callback is null\n", .{});
        return c.hermes_value_create_undefined(rt);
    };

    // Remove callback
    emitter.off(event_name, callback) catch |err| {
        std.debug.print("[vim.off] Error removing callback for '{s}': {}\n", .{ event_name, err });
        return c.hermes_value_create_undefined(rt);
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.emit(event_name, ...args)
/// Emit an event with arguments
///
/// JavaScript usage:
///   vim.emit('CustomEvent', arg1, arg2, arg3);
///
/// Arguments:
///   args[0]: event_name (string) - Event to emit
///   args[1..]: event arguments - Passed to all listeners
///
/// Returns: undefined
pub export fn eventEmit(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Validate arguments
    if (count < 1) {
        std.debug.print("[vim.emit] Error: requires at least 1 argument (event_name)\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name (arg 0)
    if (!c.hermes_value_is_string(args[0])) {
        std.debug.print("[vim.emit] Error: event_name must be a string\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Collect remaining args (event arguments)
    // Cast from []?*c.OVHermesValue to []const *c.OVHermesValue
    const event_args_slice = args[1..count];
    const event_args: []const *c.OVHermesValue = @ptrCast(event_args_slice);

    // Emit event
    emitter.emit(event_name, event_args) catch |err| {
        std.debug.print("[vim.emit] Error emitting '{s}': {}\n", .{ event_name, err });
        return c.hermes_value_create_undefined(rt);
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.removeAllListeners(event_name)
/// Remove all listeners for an event
///
/// JavaScript usage:
///   vim.removeAllListeners('BufEnter');
///
/// Arguments:
///   args[0]: event_name (string) - Event name
///
/// Returns: undefined
pub export fn eventRemoveAllListeners(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Validate arguments
    if (count < 1) {
        std.debug.print("[vim.removeAllListeners] Error: requires 1 argument (event_name)\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name (arg 0)
    if (!c.hermes_value_is_string(args[0])) {
        std.debug.print("[vim.removeAllListeners] Error: event_name must be a string\n", .{});
        return c.hermes_value_create_undefined(rt);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Remove all listeners
    emitter.removeAllListeners(event_name);

    return c.hermes_value_create_undefined(rt);
}

/// vim.listenerCount(event_name)
/// Get number of listeners for an event
///
/// JavaScript usage:
///   const count = vim.listenerCount('BufEnter');
///   console.log('BufEnter has', count, 'listeners');
///
/// Arguments:
///   args[0]: event_name (string) - Event name
///
/// Returns: number
pub export fn eventListenerCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Validate arguments
    if (count < 1) {
        std.debug.print("[vim.listenerCount] Error: requires 1 argument (event_name)\n", .{});
        return c.hermes_value_create_number(rt, 0);
    }

    const emitter: *EventEmitter = @ptrCast(@alignCast(context.?));

    // Get event name (arg 0)
    if (!c.hermes_value_is_string(args[0])) {
        std.debug.print("[vim.listenerCount] Error: event_name must be a string\n", .{});
        return c.hermes_value_create_number(rt, 0);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, args[0], &name_len);
    const event_name = name_ptr[0..name_len];

    // Get listener count
    const listener_count = emitter.listenerCount(event_name);

    return c.hermes_value_create_number(rt, @floatFromInt(listener_count));
}

// ============================================================================
// HostObject Support (vim.on, vim.off, vim.emit)
// ============================================================================

/// Event API HostObject getter - routes property access to methods
/// Exposes: vim.on, vim.off, vim.emit, vim.removeAllListeners, vim.listenerCount
pub export fn eventHostObjectGet(
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
        .{ "on", eventOn },
        .{ "off", eventOff },
        .{ "emit", eventEmit },
        .{ "removeAllListeners", eventRemoveAllListeners },
        .{ "listenerCount", eventListenerCount },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// Event API HostObject enumerator - returns array of method names
pub export fn eventHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "on",
        "off",
        "emit",
        "removeAllListeners",
        "listenerCount",
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

/// Register event API as HostObject
/// Exposes vim.on(), vim.off(), vim.emit(), etc.
pub fn register(runtime: *c.OVHermesRuntime, emitter: *EventEmitter) void {
    c.hermes_register_host_object(
        runtime,
        "vimEventEmitter", // Global name (accessed as 'vimEventEmitter' in JS, but we'll integrate into vim.* namespace)
        eventHostObjectGet,
        null, // No setter (read-only methods)
        eventHostObjectEnumerator,
        @ptrCast(emitter),
    );
}
