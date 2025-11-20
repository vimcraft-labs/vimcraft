/// Security Monitoring and Metrics for TypeScript Transpiler
/// Tracks attack attempts, blocks, and anomalies
const std = @import("std");
const loader = @import("loader.zig");

// ============================================================================
// Security Event Types
// ============================================================================

pub const SecurityEventType = enum {
    // Path validation events
    path_traversal_blocked,
    relative_path_blocked,
    null_byte_blocked,
    symlink_resolved,
    case_normalized,
    whitelist_violation,

    // File operation events
    file_loaded_success,
    file_load_failed,
    cache_hit,
    cache_miss,

    // Anomaly detection
    rapid_failures, // Multiple failures in short time
    suspicious_pattern, // Known attack pattern detected
    unusual_path, // Path outside normal patterns
};

pub const SecurityEvent = struct {
    event_type: SecurityEventType,
    timestamp: i64,
    path: []const u8,
    resolved_path: ?[]const u8 = null,
    error_code: ?loader.LoadError = null,
    user_agent: ?[]const u8 = null, // For future HTTP integration
    source_ip: ?[]const u8 = null, // For future HTTP integration

    pub fn format(
        self: SecurityEvent,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const timestamp_ms = @as(u64, @intCast(self.timestamp));
        const event_name = @tagName(self.event_type);

        try writer.print("[{d}] {s}: {s}", .{ timestamp_ms, event_name, self.path });

        if (self.resolved_path) |resolved| {
            try writer.print(" → {s}", .{resolved});
        }

        if (self.error_code) |err| {
            try writer.print(" (error: {any})", .{err});
        }
    }
};

// ============================================================================
// Security Metrics
// ============================================================================

pub const SecurityMetrics = struct {
    // Block counters
    path_traversal_attempts: usize = 0,
    relative_path_attempts: usize = 0,
    null_byte_attempts: usize = 0,
    symlink_resolutions: usize = 0,
    case_normalizations: usize = 0,
    whitelist_violations: usize = 0,

    // Success counters
    successful_loads: usize = 0,
    cache_hits: usize = 0,
    cache_misses: usize = 0,

    // Anomaly counters
    rapid_failure_sequences: usize = 0,
    suspicious_patterns: usize = 0,
    unusual_paths: usize = 0,

    // Performance metrics
    total_load_attempts: usize = 0,
    total_blocked_attempts: usize = 0,
    average_validation_time_ns: u64 = 0,

    // Time tracking
    first_event_time: i64 = 0,
    last_event_time: i64 = 0,

    pub fn totalEvents(self: *const SecurityMetrics) usize {
        return self.path_traversal_attempts + self.relative_path_attempts +
            self.null_byte_attempts + self.whitelist_violations +
            self.successful_loads;
    }

    pub fn blockRate(self: *const SecurityMetrics) f64 {
        if (self.total_load_attempts == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_blocked_attempts)) /
            @as(f64, @floatFromInt(self.total_load_attempts));
    }

    pub fn format(
        self: SecurityMetrics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("SecurityMetrics{{\n", .{});
        try writer.print("  Blocks: traversal={d} relative={d} null_byte={d} whitelist={d}\n", .{
            self.path_traversal_attempts,
            self.relative_path_attempts,
            self.null_byte_attempts,
            self.whitelist_violations,
        });
        try writer.print("  Success: loads={d} cache_hits={d} cache_misses={d}\n", .{
            self.successful_loads,
            self.cache_hits,
            self.cache_misses,
        });
        try writer.print("  Anomalies: rapid_failures={d} suspicious={d} unusual={d}\n", .{
            self.rapid_failure_sequences,
            self.suspicious_patterns,
            self.unusual_paths,
        });
        try writer.print("  Total: attempts={d} blocked={d} block_rate={d:.2}%\n", .{
            self.total_load_attempts,
            self.total_blocked_attempts,
            self.blockRate() * 100.0,
        });
        try writer.print("}}", .{});
    }
};

// ============================================================================
// Security Monitor
// ============================================================================

pub const SecurityMonitor = struct {
    allocator: std.mem.Allocator,
    metrics: SecurityMetrics,
    recent_events: std.ArrayList(SecurityEvent),
    failure_timestamps: std.ArrayList(i64), // For anomaly detection
    max_recent_events: usize = 100,
    alert_threshold: usize = 10, // Failures per minute to trigger alert

    pub fn init(allocator: std.mem.Allocator) !SecurityMonitor {
        return SecurityMonitor{
            .allocator = allocator,
            .metrics = SecurityMetrics{},
            .recent_events = try std.ArrayList(SecurityEvent).initCapacity(allocator, 100),
            .failure_timestamps = try std.ArrayList(i64).initCapacity(allocator, 50),
        };
    }

    pub fn deinit(self: *SecurityMonitor) void {
        // Free allocated path strings in events
        for (self.recent_events.items) |event| {
            self.allocator.free(event.path);
            if (event.resolved_path) |resolved| {
                self.allocator.free(resolved);
            }
        }
        self.recent_events.deinit(self.allocator);
        self.failure_timestamps.deinit(self.allocator);
    }

    /// Record a security event
    pub fn recordEvent(
        self: *SecurityMonitor,
        event_type: SecurityEventType,
        path: []const u8,
        resolved_path: ?[]const u8,
        error_code: ?loader.LoadError,
    ) !void {
        const now = std.time.milliTimestamp();

        // Update metrics
        self.metrics.total_load_attempts += 1;

        if (self.metrics.first_event_time == 0) {
            self.metrics.first_event_time = now;
        }
        self.metrics.last_event_time = now;

        switch (event_type) {
            .path_traversal_blocked => {
                self.metrics.path_traversal_attempts += 1;
                self.metrics.total_blocked_attempts += 1;
                try self.recordFailure(now);
            },
            .relative_path_blocked => {
                self.metrics.relative_path_attempts += 1;
                self.metrics.total_blocked_attempts += 1;
                try self.recordFailure(now);
            },
            .null_byte_blocked => {
                self.metrics.null_byte_attempts += 1;
                self.metrics.total_blocked_attempts += 1;
                try self.recordFailure(now);
            },
            .symlink_resolved => {
                self.metrics.symlink_resolutions += 1;
            },
            .case_normalized => {
                self.metrics.case_normalizations += 1;
            },
            .whitelist_violation => {
                self.metrics.whitelist_violations += 1;
                self.metrics.total_blocked_attempts += 1;
                try self.recordFailure(now);
            },
            .file_loaded_success => {
                self.metrics.successful_loads += 1;
            },
            .file_load_failed => {
                self.metrics.total_blocked_attempts += 1;
                try self.recordFailure(now);
            },
            .cache_hit => {
                self.metrics.cache_hits += 1;
            },
            .cache_miss => {
                self.metrics.cache_misses += 1;
            },
            .rapid_failures => {
                self.metrics.rapid_failure_sequences += 1;
            },
            .suspicious_pattern => {
                self.metrics.suspicious_patterns += 1;
            },
            .unusual_path => {
                self.metrics.unusual_paths += 1;
            },
        }

        // Store event (keep only recent events)
        const event = SecurityEvent{
            .event_type = event_type,
            .timestamp = now,
            .path = try self.allocator.dupe(u8, path),
            .resolved_path = if (resolved_path) |p| try self.allocator.dupe(u8, p) else null,
            .error_code = error_code,
        };

        try self.recent_events.append(self.allocator, event);

        // Prune old events if exceeding limit
        if (self.recent_events.items.len > self.max_recent_events) {
            const removed = self.recent_events.orderedRemove(0);
            self.allocator.free(removed.path);
            if (removed.resolved_path) |p| {
                self.allocator.free(p);
            }
        }

        // Check for anomalies
        self.detectAnomalies();
    }

    /// Record failure timestamp for anomaly detection
    fn recordFailure(self: *SecurityMonitor, timestamp: i64) !void {
        try self.failure_timestamps.append(self.allocator, timestamp);

        // Prune old timestamps (older than 1 minute)
        const one_minute_ago = timestamp - 60_000;
        var i: usize = 0;
        while (i < self.failure_timestamps.items.len) {
            if (self.failure_timestamps.items[i] < one_minute_ago) {
                _ = self.failure_timestamps.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Detect anomalous patterns (e.g., rapid failures)
    fn detectAnomalies(self: *SecurityMonitor) void {
        // Check for rapid failures (more than threshold per minute)
        if (self.failure_timestamps.items.len >= self.alert_threshold) {
            const first = self.failure_timestamps.items[0];
            const last = self.failure_timestamps.items[self.failure_timestamps.items.len - 1];
            const duration_ms = last - first;

            if (duration_ms < 60_000) { // Within 1 minute
                std.log.warn("SECURITY ALERT: Rapid failures detected ({} failures in {}ms)", .{
                    self.failure_timestamps.items.len,
                    duration_ms,
                });

                // Record anomaly metric (don't call recordEvent to avoid recursion)
                self.metrics.rapid_failure_sequences += 1;
            }
        }

        // Check for known attack patterns in recent events
        if (self.recent_events.items.len > 0) {
            const last_event = self.recent_events.items[self.recent_events.items.len - 1];
            if (std.mem.indexOf(u8, last_event.path, "../../../") != null) {
                std.log.warn("SECURITY ALERT: Classic traversal pattern detected: {s}", .{last_event.path});
                self.metrics.suspicious_patterns += 1;
            }
        }
    }

    /// Generate security report
    pub fn generateReport(self: *const SecurityMonitor, writer: anytype) !void {
        try writer.print("\n" ++ "=" ** 80 ++ "\n", .{});
        try writer.print("  SECURITY MONITORING REPORT\n", .{});
        try writer.print("=" ** 80 ++ "\n\n", .{});

        // Metrics
        try writer.print("Metrics:\n{any}\n\n", .{self.metrics});

        // Recent events (last 10)
        try writer.print("Recent Events (last {}):\n", .{@min(10, self.recent_events.items.len)});

        const start = if (self.recent_events.items.len > 10)
            self.recent_events.items.len - 10
        else
            0;

        for (self.recent_events.items[start..]) |event| {
            try writer.print("  {any}\n", .{event});
        }

        try writer.print("\n" ++ "=" ** 80 ++ "\n", .{});
    }
};

/// Export metrics as JSON for external monitoring
pub fn exportMetricsJSON(metrics: *const SecurityMetrics, writer: anytype) !void {
    try writer.print("{{\n", .{});
    try writer.print("  \"path_traversal_attempts\": {},\n", .{metrics.path_traversal_attempts});
    try writer.print("  \"relative_path_attempts\": {},\n", .{metrics.relative_path_attempts});
    try writer.print("  \"null_byte_attempts\": {},\n", .{metrics.null_byte_attempts});
    try writer.print("  \"whitelist_violations\": {},\n", .{metrics.whitelist_violations});
    try writer.print("  \"successful_loads\": {},\n", .{metrics.successful_loads});
    try writer.print("  \"total_load_attempts\": {},\n", .{metrics.total_load_attempts});
    try writer.print("  \"total_blocked_attempts\": {},\n", .{metrics.total_blocked_attempts});
    try writer.print("  \"block_rate\": {d:.4},\n", .{metrics.blockRate()});
    try writer.print("  \"rapid_failure_sequences\": {},\n", .{metrics.rapid_failure_sequences});
    try writer.print("  \"suspicious_patterns\": {}\n", .{metrics.suspicious_patterns});
    try writer.print("}}\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "SecurityMonitor: Record events" {
    const allocator = std.testing.allocator;
    var monitor = try SecurityMonitor.init(allocator);
    defer monitor.deinit();

    // Record some events
    try monitor.recordEvent(.path_traversal_blocked, "/tmp/../etc/passwd", null, loader.LoadError.PathTraversal);
    try monitor.recordEvent(.file_loaded_success, "/tmp/test.ts", "/private/tmp/test.ts", null);
    try monitor.recordEvent(.cache_hit, "/tmp/test.ts", null, null);

    // Check metrics
    try std.testing.expectEqual(@as(usize, 1), monitor.metrics.path_traversal_attempts);
    try std.testing.expectEqual(@as(usize, 1), monitor.metrics.successful_loads);
    try std.testing.expectEqual(@as(usize, 1), monitor.metrics.cache_hits);
    try std.testing.expectEqual(@as(usize, 3), monitor.metrics.total_load_attempts);

    std.debug.print("\n=== SecurityMonitor Test ===\n", .{});
    std.debug.print("{any}\n", .{monitor.metrics});
}

test "SecurityMonitor: Anomaly detection" {
    const allocator = std.testing.allocator;
    var monitor = try SecurityMonitor.init(allocator);
    defer monitor.deinit();

    monitor.alert_threshold = 5; // Lower threshold for testing

    std.debug.print("\n=== Anomaly Detection Test ===\n", .{});

    // Simulate rapid failures
    for (0..6) |i| {
        const path = try std.fmt.allocPrint(allocator, "/tmp/../etc/passwd_{}", .{i});
        defer allocator.free(path);
        try monitor.recordEvent(.path_traversal_blocked, path, null, loader.LoadError.PathTraversal);
    }

    // Check that rapid_failures anomaly was detected
    try std.testing.expect(monitor.metrics.rapid_failure_sequences > 0);
    std.debug.print("✅ Rapid failures detected: {} sequences\n", .{monitor.metrics.rapid_failure_sequences});
}

test "SecurityMonitor: Generate report" {
    const allocator = std.testing.allocator;
    var monitor = try SecurityMonitor.init(allocator);
    defer monitor.deinit();

    // Record various events
    try monitor.recordEvent(.path_traversal_blocked, "/tmp/../etc/passwd", null, loader.LoadError.PathTraversal);
    try monitor.recordEvent(.null_byte_blocked, "/tmp/test.ts\x00", null, loader.LoadError.InvalidPath);
    try monitor.recordEvent(.file_loaded_success, "/tmp/test.ts", "/private/tmp/test.ts", null);

    std.debug.print("\n=== Security Report Test ===\n", .{});

    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buf.deinit(allocator);

    try monitor.generateReport(buf.writer(allocator));
    std.debug.print("{s}\n", .{buf.items});
}

test "SecurityMonitor: JSON export" {
    const allocator = std.testing.allocator;
    var monitor = try SecurityMonitor.init(allocator);
    defer monitor.deinit();

    // Record events
    try monitor.recordEvent(.path_traversal_blocked, "/tmp/../etc/passwd", null, loader.LoadError.PathTraversal);
    try monitor.recordEvent(.file_loaded_success, "/tmp/test.ts", null, null);

    std.debug.print("\n=== JSON Export Test ===\n", .{});

    var buf = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer buf.deinit(allocator);

    try exportMetricsJSON(&monitor.metrics, buf.writer(allocator));
    std.debug.print("{s}\n", .{buf.items});

    // Verify JSON is valid (basic check)
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"path_traversal_attempts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"block_rate\"") != null);
}
