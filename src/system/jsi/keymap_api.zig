/// Keymap API Module
/// JSI bridge for vim.keymap.set() and vim.keymap.del()
/// Allows JavaScript to register custom key mappings
const std = @import("std");
const KeymapManager = @import("../../editor/keymap/keymap.zig").KeymapManager;
const Mode = @import("../../editor/keymap/keymap.zig").Mode;
const MappingRHS = @import("../../editor/keymap/keymap.zig").MappingRHS;
const KeymapOpts = @import("../../editor/keymap/keymap.zig").KeymapOpts;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;
const helpers = @import("helpers.zig");

/// Context for keymap API
pub const KeymapContext = struct {
    keymap_manager: *KeymapManager,
    allocator: std.mem.Allocator,
    runtime: *c.OVHermesRuntime,

    pub fn init(allocator: std.mem.Allocator, keymap_manager: *KeymapManager, runtime: *c.OVHermesRuntime) !*KeymapContext {
        const ctx = try allocator.create(KeymapContext);
        ctx.* = .{
            .keymap_manager = keymap_manager,
            .allocator = allocator,
            .runtime = runtime,
        };
        return ctx;
    }

    pub fn deinit(self: *KeymapContext) void {
        self.allocator.destroy(self);
    }
};

/// Convert string to null-terminated buffer
fn valueToString(runtime: *c.OVHermesRuntime, value: *c.OVHermesValue, allocator: std.mem.Allocator) ![]const u8 {
    var len: usize = 0;
    const ptr = c.hermes_value_get_string(runtime, value, &len) orelse return error.NullString;

    const result = try allocator.alloc(u8, len);
    @memcpy(result, ptr[0..len]);
    return result;
}

/// Get object property helper
fn getObjectProperty(runtime: *c.OVHermesRuntime, obj: *c.OVHermesValue, key: [*:0]const u8) ?*c.OVHermesValue {
    return c.hermes_value_get_property(runtime, obj, key);
}

/// vim.keymap.set(mode, lhs, rhs, opts)
/// mode: string ('n', 'i', 'v', 'c')
/// lhs: string (key to map, e.g., 'H', '<leader>w')
/// rhs: string (command to execute) - function callbacks not yet supported
/// opts: table { noremap: bool, silent: bool, buffer: bool }
pub export fn keymapSet(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*KeymapContext, @ptrCast(@alignCast(context.?)));

    // Validate argument count
    if (arg_count < 3) {
        return helpers.returnError(runtime, "keymap.set requires at least 3 arguments (mode, lhs, rhs)");
    }

    // Extract mode (arg 0)
    const mode_str = valueToString(runtime, args[0].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "keymap.set: mode must be a string");
    };
    defer ctx.allocator.free(mode_str);

    const mode = Mode.fromString(mode_str) orelse {
        return helpers.returnError(runtime, "keymap.set: invalid mode (must be 'n', 'i', 'v', or 'c')");
    };

    // Extract lhs (arg 1)
    const lhs = valueToString(runtime, args[1].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "keymap.set: lhs must be a string");
    };
    defer ctx.allocator.free(lhs);

    // Extract rhs (arg 2) - only support strings for now
    const rhs_value = args[2].?;
    if (!c.hermes_value_is_string(rhs_value)) {
        return helpers.returnError(runtime, "keymap.set: rhs must be a string (callbacks not yet supported)");
    }

    const rhs_str = valueToString(runtime, rhs_value, ctx.allocator) catch {
        return helpers.returnError(runtime, "keymap.set: failed to convert rhs to string");
    };
    const rhs = MappingRHS{ .keys = rhs_str };

    // Extract options (arg 3, optional)
    var opts = KeymapOpts{};
    if (arg_count >= 4) {
        const opts_value = args[3].?;
        if (c.hermes_value_is_object(opts_value)) {
            // Extract noremap
            if (getObjectProperty(runtime, opts_value, "noremap")) |noremap_val| {
                defer c.hermes_value_destroy(noremap_val);
                if (c.hermes_value_is_boolean(noremap_val)) {
                    opts.noremap = c.hermes_value_get_boolean(noremap_val);
                }
            }

            // Extract silent
            if (getObjectProperty(runtime, opts_value, "silent")) |silent_val| {
                defer c.hermes_value_destroy(silent_val);
                if (c.hermes_value_is_boolean(silent_val)) {
                    opts.silent = c.hermes_value_get_boolean(silent_val);
                }
            }

            // Extract buffer
            if (getObjectProperty(runtime, opts_value, "buffer")) |buffer_val| {
                defer c.hermes_value_destroy(buffer_val);
                if (c.hermes_value_is_boolean(buffer_val)) {
                    opts.buffer = c.hermes_value_get_boolean(buffer_val);
                }
            }
        }
    }

    // Determine buffer ID (for now, Vimcraft has single-buffer support)
    // When opts.buffer = true, use buffer 0 (current buffer)
    // When opts.buffer = false, use null (global)
    const buffer_id: ?usize = if (opts.buffer) 0 else null;

    // Set the mapping
    ctx.keymap_manager.set(mode, lhs, rhs, opts, buffer_id) catch {
        return helpers.returnError(runtime, "keymap.set: failed to set mapping");
    };

    return c.hermes_value_create_undefined(runtime);
}

/// vim.keymap.del(mode, lhs)
/// mode: string ('n', 'i', 'v', 'c')
/// lhs: string (key to unmap)
pub export fn keymapDel(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*KeymapContext, @ptrCast(@alignCast(context.?)));

    // Validate argument count
    if (arg_count < 2) {
        return helpers.returnError(runtime, "keymap.del requires 2 arguments (mode, lhs)");
    }

    // Extract mode (arg 0)
    const mode_str = valueToString(runtime, args[0].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "keymap.del: mode must be a string");
    };
    defer ctx.allocator.free(mode_str);

    const mode = Mode.fromString(mode_str) orelse {
        return helpers.returnError(runtime, "keymap.del: invalid mode (must be 'n', 'i', 'v', or 'c')");
    };

    // Extract lhs (arg 1)
    const lhs = valueToString(runtime, args[1].?, ctx.allocator) catch {
        return helpers.returnError(runtime, "keymap.del: lhs must be a string");
    };
    defer ctx.allocator.free(lhs);

    // Delete the mapping (try both buffer-local and global)
    // For now, delete from buffer 0 (current buffer) and global
    ctx.keymap_manager.del(mode, lhs, 0) catch {}; // Buffer-local (ignore errors)
    ctx.keymap_manager.del(mode, lhs, null) catch {}; // Global (ignore errors)

    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.keymap HostObject getter - routes property access to methods
pub export fn keymapHostObjectGet(
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
        .{ "set", keymapSet },
        .{ "del", keymapDel },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.keymap HostObject enumerator - returns array of method names
pub export fn keymapHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "set",
        "del",
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

/// Register keymap API as HostObject (zero-copy, 3-5x faster)
/// JavaScript usage: vim.keymap.set(mode, lhs, rhs, opts), vim.keymap.del(mode, lhs)
pub fn register(runtime: *c.OVHermesRuntime, ctx: *KeymapContext) void {
    c.hermes_register_host_object(
        runtime,
        "vimKeymap",
        keymapHostObjectGet,
        null, // No setter (read-only methods)
        keymapHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

/// Legacy registration (backwards compatibility)
/// TODO: Remove after all examples/tests updated
pub fn registerLegacy(runtime: *c.OVHermesRuntime, ctx: *KeymapContext) void {
    c.hermes_register_host_function(runtime, "keymapSet", keymapSet, @ptrCast(ctx));
    c.hermes_register_host_function(runtime, "keymapDel", keymapDel, @ptrCast(ctx));
}
