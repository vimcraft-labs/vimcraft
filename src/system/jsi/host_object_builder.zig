/// HostObject Builder Utility
/// Provides dual-mode (comptime/runtime) builder for creating JSI HostObjects
/// This is the foundation for both internal APIs and the future Plugin SDK
///
/// Design:
/// - Comptime mode: For Vimcraft internal APIs (zero runtime cost, optimal dispatch)
/// - Runtime mode: For external plugin SDK (dynamic registration, stable ABI)
///
/// Usage (Comptime):
///   var builder = HostObjectBuilder.initComptime("motion", allocator);
///   _ = try builder.addMethod("up", vimMotionUp, ctx);
///   _ = try builder.addMethod("down", vimMotionDown, ctx);
///   const vtable = try builder.build();
///   c.hermes_register_host_object(runtime, "motion", vtable, ctx);
///
/// Usage (Runtime - Future Plugin SDK):
///   var builder = try HostObjectBuilder.initRuntime("fzf", allocator);
///   _ = try builder.addMethod("find", fzfFind, ctx);
///   const vtable = try builder.build();
///   c.hermes_register_host_object(runtime, "fzf", vtable, ctx);

const std = @import("std");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;
const helpers = @import("helpers.zig");

/// Host function signature (same as Hermes JSI)
pub const HostFunction = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue;

/// Property getter signature
pub const PropertyGetter = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue;

/// Property setter signature
pub const PropertySetter = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue;

/// Property descriptor (getter + optional setter)
pub const PropertyDescriptor = struct {
    get: PropertyGetter,
    set: ?PropertySetter = null,
};

/// Property handler (either method or property)
pub const PropertyHandler = union(enum) {
    method: struct {
        func: HostFunction,
        context: ?*anyopaque,
    },
    property: PropertyDescriptor,
};

/// HostObject VTable (what gets passed to C++)
pub const HostObjectVTable = struct {
    get: GetterFn,
    set: ?SetterFn = null,
    getPropertyNames: ?EnumeratorFn = null,
    context: ?*anyopaque = null,
};

/// Getter function signature (used by C++ CustomHostObject)
pub const GetterFn = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*:0]const u8,
) callconv(.c) ?*c.OVHermesValue;

/// Setter function signature
pub const SetterFn = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*:0]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue;

/// Enumerator function signature (for Object.keys())
pub const EnumeratorFn = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue;

/// Builder mode
pub const BuilderMode = enum {
    comptime_optimized, // For Vimcraft internal APIs
    runtime_dynamic,    // For external plugin SDK
};

/// HostObject Builder
pub const HostObjectBuilder = struct {
    name: []const u8,
    properties: std.StringHashMap(PropertyHandler),
    allocator: std.mem.Allocator,
    mode: BuilderMode,
    property_names: std.ArrayList([]const u8), // For enumeration

    /// Initialize builder in comptime mode (for Vimcraft internal APIs)
    /// This mode uses comptime optimization for zero-cost property dispatch
    pub fn initComptime(comptime name: []const u8, allocator: std.mem.Allocator) !HostObjectBuilder {
        return .{
            .name = name,
            .properties = std.StringHashMap(PropertyHandler).init(allocator),
            .allocator = allocator,
            .mode = .comptime_optimized,
            .property_names = .{},  // ArrayList with default initialization
        };
    }

    /// Initialize builder in runtime mode (for external plugin SDK)
    /// This mode allows dynamic registration of properties at runtime
    pub fn initRuntime(name: []const u8, allocator: std.mem.Allocator) !HostObjectBuilder {
        const name_copy = try allocator.dupe(u8, name);

        return .{
            .name = name_copy,
            .properties = std.StringHashMap(PropertyHandler).init(allocator),
            .allocator = allocator,
            .mode = .runtime_dynamic,
            .property_names = .{},  // ArrayList with default initialization
        };
    }

    /// Add method to HostObject
    /// Methods are callable functions: vim.motion.up()
    pub fn addMethod(
        self: *HostObjectBuilder,
        name: []const u8,
        func: HostFunction,
        context: ?*anyopaque,
    ) !*HostObjectBuilder {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.properties.put(name_copy, .{
            .method = .{
                .func = func,
                .context = context,
            },
        });
        try self.property_names.append(self.allocator, name_copy);
        return self;
    }

    /// Add property to HostObject
    /// Properties have getter/setter: vim.opt.number = 10
    pub fn addProperty(
        self: *HostObjectBuilder,
        name: []const u8,
        getter: PropertyGetter,
        setter: ?PropertySetter,
    ) !*HostObjectBuilder {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.properties.put(name_copy, .{
            .property = .{
                .get = getter,
                .set = setter,
            },
        });
        try self.property_names.append(self.allocator, name_copy);
        return self;
    }

    /// Build HostObject VTable
    /// This generates the getter/setter functions that C++ will call
    pub fn build(self: *HostObjectBuilder) !HostObjectVTable {
        // Create persistent context that will outlive this function
        const ctx = try self.allocator.create(BuilderContext);
        ctx.* = .{
            .properties = self.properties,
            .property_names = self.property_names,
            .mode = self.mode,
        };

        return .{
            .get = generatedGetter,
            .set = generatedSetter,
            .getPropertyNames = generatedEnumerator,
            .context = ctx,
        };
    }

    /// Clean up builder resources
    pub fn deinit(self: *HostObjectBuilder) void {
        // Free property name copies
        var it = self.properties.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.properties.deinit();
        self.property_names.deinit(self.allocator);

        // Free name copy (runtime mode only)
        if (self.mode == .runtime_dynamic) {
            self.allocator.free(self.name);
        }
    }
};

/// Persistent context passed to generated functions
const BuilderContext = struct {
    properties: std.StringHashMap(PropertyHandler),
    property_names: std.ArrayList([]const u8),
    mode: BuilderMode,
};

/// Generated getter function (called by C++ CustomHostObject::get)
fn generatedGetter(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*:0]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = @as(*BuilderContext, @ptrCast(@alignCast(context orelse return null)));
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Lookup property in hash map
    const handler = ctx.properties.get(name) orelse return null;

    return switch (handler) {
        .method => |method| {
            // Return function object that calls the method
            return c.hermes_create_function(rt, prop_name, method.func, method.context);
        },
        .property => |prop| {
            // Call getter immediately
            return prop.get(rt, context);
        },
    };
}

/// Generated setter function (called by C++ CustomHostObject::set)
fn generatedSetter(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*:0]const u8,
    value: ?*c.OVHermesValue,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = @as(*BuilderContext, @ptrCast(@alignCast(context orelse return null)));
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Lookup property in hash map
    const handler = ctx.properties.get(name) orelse {
        return helpers.returnError(rt, "Property does not exist or is not settable");
    };

    return switch (handler) {
        .method => {
            // Methods are not settable
            return helpers.returnError(rt, "Cannot set method property");
        },
        .property => |prop| {
            if (prop.set) |setter| {
                return setter(rt, context, value);
            } else {
                return helpers.returnError(rt, "Property is read-only");
            }
        },
    };
}

/// Generated enumerator function (for Object.keys())
fn generatedEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = @as(*BuilderContext, @ptrCast(@alignCast(context orelse return null)));
    const rt = runtime orelse return null;

    // Create JavaScript array of property names
    const arr = c.hermes_array_create(rt, ctx.property_names.items.len) orelse return null;

    for (ctx.property_names.items, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

/// Comptime-optimized dispatcher using ComptimeStringMap
/// This generates an optimal switch statement at compile time
pub fn ComptimeDispatcher(comptime PropertyMap: type) type {
    return struct {
        /// Generate getter function with comptime-optimized dispatch
        pub fn generateGetter(comptime map: PropertyMap) GetterFn {
            return struct {
                fn get(
                    runtime: ?*c.OVHermesRuntime,
                    context: ?*anyopaque,
                    prop_name: [*:0]const u8,
                ) callconv(.c) ?*c.OVHermesValue {
                    const name = std.mem.span(prop_name);
                    const rt = runtime orelse return null;

                    // Comptime string map for O(1) dispatch
                    const string_map = std.ComptimeStringMap(PropertyHandler, map);
                    const handler = string_map.get(name) orelse return null;

                    return switch (handler) {
                        .method => |method| c.hermes_create_function(rt, prop_name, method.func, method.context),
                        .property => |prop| prop.get(rt, context),
                    };
                }
            }.get;
        }
    };
}

// ============================================================================
// C API Extensions (for future Plugin SDK)
// ============================================================================

/// These functions will be exported to external plugins via plugin_api.h
/// For now, they're internal utilities used by the builder

/// Create function value (wraps host function in JSI Function)
/// This is what gets returned when accessing a method property
pub fn createFunctionValue(
    runtime: *c.OVHermesRuntime,
    name: [*:0]const u8,
    func: HostFunction,
    context: ?*anyopaque,
) ?*c.OVHermesValue {
    return c.hermes_create_function(runtime, name, func, context);
}

/// Validate property name (no special characters, valid identifier)
pub fn validatePropertyName(name: []const u8) !void {
    if (name.len == 0) return error.EmptyPropertyName;
    if (name.len > 256) return error.PropertyNameTooLong;

    // First character must be letter or underscore
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') {
        return error.InvalidPropertyName;
    }

    // Remaining characters must be alphanumeric or underscore
    for (name[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') {
            return error.InvalidPropertyName;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "HostObjectBuilder: basic construction" {
    const allocator = std.testing.allocator;

    var builder = try HostObjectBuilder.initComptime("test", allocator);
    defer builder.deinit();

    try std.testing.expectEqualStrings("test", builder.name);
    try std.testing.expectEqual(BuilderMode.comptime_optimized, builder.mode);
    try std.testing.expectEqual(@as(usize, 0), builder.properties.count());
}

test "HostObjectBuilder: add method" {
    const allocator = std.testing.allocator;

    var builder = try HostObjectBuilder.initComptime("test", allocator);
    defer builder.deinit();

    // Dummy function
    const dummyFn = struct {
        fn func(
            runtime: ?*c.OVHermesRuntime,
            context: ?*anyopaque,
            args: [*c]?*c.OVHermesValue,
            arg_count: usize,
        ) callconv(.c) ?*c.OVHermesValue {
            _ = runtime;
            _ = context;
            _ = args;
            _ = arg_count;
            return null;
        }
    }.func;

    _ = try builder.addMethod("testMethod", dummyFn, null);

    try std.testing.expectEqual(@as(usize, 1), builder.properties.count());
    const handler = builder.properties.get("testMethod").?;
    try std.testing.expect(handler == .method);
}

test "validatePropertyName: valid names" {
    try validatePropertyName("validName");
    try validatePropertyName("_private");
    try validatePropertyName("name123");
    try validatePropertyName("camelCase");
}

test "validatePropertyName: invalid names" {
    try std.testing.expectError(error.EmptyPropertyName, validatePropertyName(""));
    try std.testing.expectError(error.InvalidPropertyName, validatePropertyName("123invalid"));
    try std.testing.expectError(error.InvalidPropertyName, validatePropertyName("invalid-name"));
    try std.testing.expectError(error.InvalidPropertyName, validatePropertyName("invalid.name"));
}
