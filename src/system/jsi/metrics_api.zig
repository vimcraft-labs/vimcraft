/// JSI API for vim.metrics - Performance metrics access
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;
const metrics_mod = @import("../../core/metrics.zig");

/// Get startup time in milliseconds
export fn vimMetricsGetStartupTime(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        return c.hermes_value_create_number(runtime, 0);
    };

    const startup_time = metrics.getStartupTime();
    return c.hermes_value_create_number(runtime, @floatFromInt(startup_time));
}

/// Get Hermes initialization time in milliseconds
export fn vimMetricsGetHermesInitTime(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        return c.hermes_value_create_number(runtime, 0);
    };

    const init_time = metrics.getHermesInitTime();
    return c.hermes_value_create_number(runtime, @floatFromInt(init_time));
}

/// Get config load time in milliseconds
export fn vimMetricsGetConfigLoadTime(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        return c.hermes_value_create_number(runtime, 0);
    };

    const load_time = metrics.getConfigLoadTime();
    return c.hermes_value_create_number(runtime, @floatFromInt(load_time));
}

/// Get uptime in milliseconds
export fn vimMetricsGetUptime(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        return c.hermes_value_create_number(runtime, 0);
    };

    const uptime = metrics.getUptime();
    return c.hermes_value_create_number(runtime, @floatFromInt(uptime));
}

/// Get number of plugins loaded
export fn vimMetricsGetPluginCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        return c.hermes_value_create_number(runtime, 0);
    };

    return c.hermes_value_create_number(runtime, @floatFromInt(metrics.plugins_loaded));
}

/// Get plugin load times as array
export fn vimMetricsGetPluginLoadTimes(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = arg_count;

    const rt = runtime orelse return c.hermes_value_create_undefined(runtime);

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        // Return empty array
        return c.hermes_array_create(rt, 0);
    };

    // Create array
    const arr = c.hermes_array_create(rt, metrics.plugin_load_times_ms.items.len);
    if (arr == null) return c.hermes_value_create_undefined(runtime);

    // Populate array with {name, duration_ms} objects
    for (metrics.plugin_load_times_ms.items, 0..) |plugin, i| {
        const obj = c.hermes_value_create_object(rt);
        if (obj == null) continue;

        // Set name property
        const name_val = c.hermes_value_create_string(rt, plugin.name.ptr, plugin.name.len);
        if (name_val != null) {
            c.hermes_value_set_property(rt, obj, "name", name_val);
            c.hermes_value_destroy(name_val);
        }

        // Set durationMs property
        const duration_val = c.hermes_value_create_number(rt, @floatFromInt(plugin.duration_ms));
        if (duration_val != null) {
            c.hermes_value_set_property(rt, obj, "durationMs", duration_val);
            c.hermes_value_destroy(duration_val);
        }

        // Add to array
        c.hermes_array_set(rt, arr, i, obj);
        c.hermes_value_destroy(obj);
    }

    return arr;
}

/// HostObject getter for vim.metrics
export fn vimMetricsHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    const metrics = metrics_mod.getGlobalMetrics() orelse {
        // Metrics disabled - return 0 or empty array
        if (std.mem.eql(u8, name, "pluginLoadTimes")) {
            return c.hermes_array_create(rt, 0);
        }
        return c.hermes_value_create_number(rt, 0);
    };

    // Return property values directly (not functions)
    if (std.mem.eql(u8, name, "startupTime")) {
        return c.hermes_value_create_number(rt, @floatFromInt(metrics.getStartupTime()));
    } else if (std.mem.eql(u8, name, "hermesInitTime")) {
        return c.hermes_value_create_number(rt, @floatFromInt(metrics.getHermesInitTime()));
    } else if (std.mem.eql(u8, name, "configLoadTime")) {
        return c.hermes_value_create_number(rt, @floatFromInt(metrics.getConfigLoadTime()));
    } else if (std.mem.eql(u8, name, "uptime")) {
        return c.hermes_value_create_number(rt, @floatFromInt(metrics.getUptime()));
    } else if (std.mem.eql(u8, name, "pluginCount")) {
        return c.hermes_value_create_number(rt, @floatFromInt(metrics.plugins_loaded));
    } else if (std.mem.eql(u8, name, "pluginLoadTimes")) {
        // Create array
        const arr = c.hermes_array_create(rt, metrics.plugin_load_times_ms.items.len);
        if (arr == null) return c.hermes_value_create_undefined(rt);

        // Populate array with {name, duration_ms} objects
        for (metrics.plugin_load_times_ms.items, 0..) |plugin, i| {
            const obj = c.hermes_value_create_object(rt);
            if (obj == null) continue;

            // Set name property
            const name_val = c.hermes_value_create_string(rt, plugin.name.ptr, plugin.name.len);
            if (name_val != null) {
                c.hermes_value_set_property(rt, obj, "name", name_val);
                c.hermes_value_destroy(name_val);
            }

            // Set durationMs property
            const duration_val = c.hermes_value_create_number(rt, @floatFromInt(plugin.duration_ms));
            if (duration_val != null) {
                c.hermes_value_set_property(rt, obj, "durationMs", duration_val);
                c.hermes_value_destroy(duration_val);
            }

            // Add to array
            c.hermes_array_set(rt, arr, i, obj);
            c.hermes_value_destroy(obj);
        }

        return arr;
    }

    return null;
}

/// HostObject enumerator for vim.metrics
export fn vimMetricsHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const arr = c.hermes_array_create(rt, 6);
    if (arr == null) return null;

    const properties = [_][]const u8{
        "startupTime",
        "hermesInitTime",
        "configLoadTime",
        "uptime",
        "pluginCount",
        "pluginLoadTimes",
    };

    for (properties, 0..) |prop, i| {
        const val = c.hermes_value_create_string(rt, prop.ptr, prop.len);
        if (val != null) {
            c.hermes_array_set(rt, arr, i, val);
            c.hermes_value_destroy(val);
        }
    }

    return arr;
}

/// Register vim.metrics HostObject
pub fn register(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_object(
        runtime,
        "vimMetrics",
        vimMetricsHostObjectGet,
        null, // Read-only
        vimMetricsHostObjectEnumerator,
        null,
    );
}
