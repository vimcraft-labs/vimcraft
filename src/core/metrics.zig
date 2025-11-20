/// Performance metrics tracking for Vimcraft
/// Exposes timing information via vim.metrics API
const std = @import("std");

/// Global metrics singleton
var global_metrics: ?*Metrics = null;

/// Performance metrics
pub const Metrics = struct {
    allocator: std.mem.Allocator,

    // Timing metrics (milliseconds)
    process_start_ms: i64,
    hermes_init_start_ms: i64 = 0,
    hermes_init_end_ms: i64 = 0,
    config_load_start_ms: i64 = 0,
    config_load_end_ms: i64 = 0,
    first_render_ms: i64 = 0,

    // Plugin metrics
    plugins_loaded: usize = 0,
    plugin_load_times_ms: std.ArrayList(PluginLoadTime),

    // Memory metrics (bytes)
    initial_memory_bytes: usize = 0,
    current_memory_bytes: usize = 0,

    pub const PluginLoadTime = struct {
        name: []const u8,
        duration_ms: i64,
    };

    pub fn init(allocator: std.mem.Allocator) !*Metrics {
        const metrics = try allocator.create(Metrics);
        metrics.* = .{
            .allocator = allocator,
            .process_start_ms = std.time.milliTimestamp(),
            .plugin_load_times_ms = .empty,
        };
        global_metrics = metrics;
        return metrics;
    }

    pub fn deinit(self: *Metrics) void {
        for (self.plugin_load_times_ms.items) |plugin| {
            self.allocator.free(plugin.name);
        }
        self.plugin_load_times_ms.deinit(self.allocator);
        self.allocator.destroy(self);
        global_metrics = null;
    }

    /// Mark Hermes initialization start
    pub fn markHermesInitStart(self: *Metrics) void {
        self.hermes_init_start_ms = std.time.milliTimestamp();
    }

    /// Mark Hermes initialization end
    pub fn markHermesInitEnd(self: *Metrics) void {
        self.hermes_init_end_ms = std.time.milliTimestamp();
    }

    /// Mark config loading start
    pub fn markConfigLoadStart(self: *Metrics) void {
        self.config_load_start_ms = std.time.milliTimestamp();
    }

    /// Mark config loading end
    pub fn markConfigLoadEnd(self: *Metrics) void {
        self.config_load_end_ms = std.time.milliTimestamp();
    }

    /// Mark first render
    pub fn markFirstRender(self: *Metrics) void {
        if (self.first_render_ms == 0) {
            self.first_render_ms = std.time.milliTimestamp();
        }
    }

    /// Record plugin load time
    pub fn recordPluginLoad(self: *Metrics, name: []const u8, duration_ms: i64) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.plugin_load_times_ms.append(self.allocator, .{
            .name = name_copy,
            .duration_ms = duration_ms,
        });
        self.plugins_loaded += 1;
    }

    /// Get total startup time (process start to first render)
    pub fn getStartupTime(self: *const Metrics) i64 {
        if (self.first_render_ms == 0) return 0;
        return self.first_render_ms - self.process_start_ms;
    }

    /// Get Hermes initialization time
    pub fn getHermesInitTime(self: *const Metrics) i64 {
        if (self.hermes_init_end_ms == 0) return 0;
        return self.hermes_init_end_ms - self.hermes_init_start_ms;
    }

    /// Get config load time
    pub fn getConfigLoadTime(self: *const Metrics) i64 {
        if (self.config_load_end_ms == 0) return 0;
        return self.config_load_end_ms - self.config_load_start_ms;
    }

    /// Get total time since process start
    pub fn getUptime(self: *const Metrics) i64 {
        return std.time.milliTimestamp() - self.process_start_ms;
    }
};

/// Get global metrics instance
pub fn getGlobalMetrics() ?*Metrics {
    return global_metrics;
}
