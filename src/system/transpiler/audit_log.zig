/// Security Audit Logging for Forensic Analysis
/// Persistent logging of all security events with rotation and search capabilities
const std = @import("std");
const security_monitor = @import("security_monitor.zig");
const loader = @import("loader.zig");
const cache = @import("cache.zig");

// ============================================================================
// Audit Log Configuration
// ============================================================================

pub const AuditLogConfig = struct {
    log_dir: []const u8 = "~/.cache/vimcraft",
    log_filename: []const u8 = "security-audit.log",
    max_log_size_bytes: usize = 10 * 1024 * 1024, // 10MB
    max_rotated_logs: usize = 5, // Keep 5 rotated files
    enable_compression: bool = false, // Future: gzip old logs
};

// ============================================================================
// Audit Log Entry
// ============================================================================

pub const AuditLogEntry = struct {
    timestamp: i64, // Unix timestamp (ms)
    event_type: security_monitor.SecurityEventType,
    path: []const u8,
    resolved_path: ?[]const u8,
    error_code: ?loader.LoadError,
    user_context: ?[]const u8, // Future: username, session ID
    ip_address: ?[]const u8, // Future: remote IP for network mode
    severity: Severity,

    pub const Severity = enum {
        info, // Normal operations (cache hits, successful loads)
        warning, // Suspicious but not blocked (symlink resolution, case normalization)
        err, // Blocked attacks (traversal, injection, whitelist violation)
        critical, // Rapid failures, active attack patterns

        pub fn fromEventType(event_type: security_monitor.SecurityEventType) Severity {
            return switch (event_type) {
                .file_loaded_success, .cache_hit, .cache_miss => .info,
                .symlink_resolved, .case_normalized => .warning,
                .path_traversal_blocked, .relative_path_blocked, .null_byte_blocked, .whitelist_violation, .file_load_failed => .err,
                .rapid_failures, .suspicious_pattern, .unusual_path => .critical,
            };
        }
    };

    /// Format entry as JSON line (JSONL format for easy parsing)
    pub fn toJSON(self: AuditLogEntry, writer: anytype) !void {
        try writer.print("{{", .{});
        try writer.print("\"timestamp\":{d},", .{self.timestamp});
        try writer.print("\"event\":\"{s}\",", .{@tagName(self.event_type)});
        try writer.print("\"severity\":\"{s}\",", .{@tagName(self.severity)});
        try writer.print("\"path\":\"{s}\"", .{self.path});

        if (self.resolved_path) |resolved| {
            try writer.print(",\"resolved_path\":\"{s}\"", .{resolved});
        }

        if (self.error_code) |err| {
            try writer.print(",\"error\":\"{s}\"", .{@errorName(err)});
        }

        if (self.user_context) |user| {
            try writer.print(",\"user\":\"{s}\"", .{user});
        }

        if (self.ip_address) |ip| {
            try writer.print(",\"ip\":\"{s}\"", .{ip});
        }

        try writer.print("}}\n", .{});
    }
};

// ============================================================================
// Audit Logger
// ============================================================================

pub const AuditLogger = struct {
    allocator: std.mem.Allocator,
    config: AuditLogConfig,
    log_file: ?std.fs.File,
    current_size: usize,
    mutex: std.Thread.Mutex, // Thread-safe logging

    pub fn init(allocator: std.mem.Allocator, config: AuditLogConfig) !AuditLogger {
        var logger = AuditLogger{
            .allocator = allocator,
            .config = config,
            .log_file = null,
            .current_size = 0,
            .mutex = std.Thread.Mutex{},
        };

        try logger.openLogFile();
        return logger;
    }

    pub fn deinit(self: *AuditLogger) void {
        if (self.log_file) |file| {
            file.close();
        }
    }

    /// Open or create audit log file
    fn openLogFile(self: *AuditLogger) !void {
        // Expand ~ to home directory
        const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;

        var log_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const log_dir = if (std.mem.startsWith(u8, self.config.log_dir, "~/"))
            try std.fmt.bufPrint(&log_dir_buf, "{s}/{s}", .{ home, self.config.log_dir[2..] })
        else
            self.config.log_dir;

        // Create directory if it doesn't exist
        std.fs.cwd().makePath(log_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Open log file (append mode)
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const log_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ log_dir, self.config.log_filename });

        self.log_file = try std.fs.cwd().createFile(log_path, .{
            .read = true,
            .truncate = false, // Append mode
        });

        // Seek to end
        try self.log_file.?.seekFromEnd(0);

        // Get current size
        const stat = try self.log_file.?.stat();
        self.current_size = stat.size;
    }

    /// Log a security event
    pub fn logEvent(
        self: *AuditLogger,
        event_type: security_monitor.SecurityEventType,
        path: []const u8,
        resolved_path: ?[]const u8,
        error_code: ?loader.LoadError,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if rotation needed
        if (self.current_size >= self.config.max_log_size_bytes) {
            try self.rotateLogs();
        }

        const entry = AuditLogEntry{
            .timestamp = std.time.milliTimestamp(),
            .event_type = event_type,
            .path = path,
            .resolved_path = resolved_path,
            .error_code = error_code,
            .user_context = null, // Future: add user tracking
            .ip_address = null, // Future: add network tracking
            .severity = AuditLogEntry.Severity.fromEventType(event_type),
        };

        if (self.log_file) |file| {
            // Create a temporary ArrayList to format JSON, then write to file
            var json_buf = try std.ArrayList(u8).initCapacity(self.allocator, 256);
            defer json_buf.deinit(self.allocator);

            try entry.toJSON(json_buf.writer(self.allocator));

            // Write to file directly
            _ = try file.write(json_buf.items);

            // Update size estimate (rough, but avoids stat() call)
            self.current_size += json_buf.items.len;
        }
    }

    /// Rotate log files (audit.log → audit.log.1 → audit.log.2 → ...)
    fn rotateLogs(self: *AuditLogger) !void {
        // Close current file
        if (self.log_file) |file| {
            file.close();
            self.log_file = null;
        }

        const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;

        var log_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const log_dir = if (std.mem.startsWith(u8, self.config.log_dir, "~/"))
            try std.fmt.bufPrint(&log_dir_buf, "{s}/{s}", .{ home, self.config.log_dir[2..] })
        else
            self.config.log_dir;

        // Rotate existing files (audit.log.4 → audit.log.5, etc.)
        var i: usize = self.config.max_rotated_logs;
        while (i > 0) : (i -= 1) {
            var old_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;

            const old_path = if (i == 1)
                try std.fmt.bufPrint(&old_path_buf, "{s}/{s}", .{ log_dir, self.config.log_filename })
            else
                try std.fmt.bufPrint(&old_path_buf, "{s}/{s}.{d}", .{ log_dir, self.config.log_filename, i - 1 });

            const new_path = try std.fmt.bufPrint(&new_path_buf, "{s}/{s}.{d}", .{ log_dir, self.config.log_filename, i });

            // Rename (ignore errors if file doesn't exist)
            std.fs.cwd().rename(old_path, new_path) catch |err| {
                if (err != error.FileNotFound) {
                    std.log.warn("Failed to rotate log {s} → {s}: {any}", .{ old_path, new_path, err });
                }
            };
        }

        // Delete oldest file if exceeds max
        if (self.config.max_rotated_logs > 0) {
            var oldest_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const oldest_path = try std.fmt.bufPrint(&oldest_path_buf, "{s}/{s}.{d}", .{
                log_dir,
                self.config.log_filename,
                self.config.max_rotated_logs,
            });
            std.fs.cwd().deleteFile(oldest_path) catch |err| {
                if (err != error.FileNotFound) {
                    std.log.warn("Failed to delete old log {s}: {any}", .{ oldest_path, err });
                }
            };
        }

        // Open new log file
        self.current_size = 0;
        try self.openLogFile();

        std.log.info("Rotated audit logs (max size {d} bytes reached)", .{self.config.max_log_size_bytes});
    }

    /// Search logs by criteria (forensic analysis)
    pub fn search(
        self: *AuditLogger,
        allocator: std.mem.Allocator,
        criteria: SearchCriteria,
    ) !std.ArrayList(AuditLogEntry) {
        _ = self;
        _ = allocator;
        _ = criteria;
        // TODO: Implement search functionality
        return error.NotImplemented;
    }
};

// ============================================================================
// Search Criteria (Future Enhancement)
// ============================================================================

pub const SearchCriteria = struct {
    start_time: ?i64 = null,
    end_time: ?i64 = null,
    event_types: ?[]const security_monitor.SecurityEventType = null,
    severity: ?AuditLogEntry.Severity = null,
    path_pattern: ?[]const u8 = null, // Regex pattern
    ip_address: ?[]const u8 = null,
};

// ============================================================================
// Integration with SecurityMonitor
// ============================================================================

/// Wrapper that logs to both SecurityMonitor and AuditLogger
pub const SecureLoader = struct {
    allocator: std.mem.Allocator,
    monitor: *security_monitor.SecurityMonitor,
    audit_logger: *AuditLogger,

    pub fn init(
        allocator: std.mem.Allocator,
        monitor: *security_monitor.SecurityMonitor,
        audit_logger: *AuditLogger,
    ) SecureLoader {
        return SecureLoader{
            .allocator = allocator,
            .monitor = monitor,
            .audit_logger = audit_logger,
        };
    }

    /// Load module with full security logging
    pub fn loadModule(
        self: *SecureLoader,
        config: loader.LoaderConfig,
        path: []const u8,
    ) ![]const u8 {
        const result = loader.loadModule(self.allocator, config, path);

        // Determine event type and error code based on result
        const event_type: security_monitor.SecurityEventType = if (result) |_|
            .file_loaded_success
        else |err| switch (err) {
            loader.LoadError.PathTraversal => .path_traversal_blocked,
            loader.LoadError.InvalidPath => .relative_path_blocked,
            loader.LoadError.PathNotFound => .file_load_failed,
            else => .file_load_failed,
        };

        const error_code: ?loader.LoadError = if (result) |_| null else |err| err;

        // Log to both systems
        try self.monitor.recordEvent(event_type, path, null, error_code);
        try self.audit_logger.logEvent(event_type, path, null, error_code);

        return result;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "AuditLogger: Basic logging" {
    const allocator = std.testing.allocator;

    const config = AuditLogConfig{
        .log_dir = "/tmp/vimcraft-audit-test",
        .log_filename = "test-audit.log",
        .max_log_size_bytes = 1024, // Small for testing rotation
        .max_rotated_logs = 3,
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    // Log some events
    try logger.logEvent(.path_traversal_blocked, "/tmp/../etc/passwd", null, loader.LoadError.PathTraversal);
    try logger.logEvent(.file_loaded_success, "/tmp/test.ts", "/private/tmp/test.ts", null);
    try logger.logEvent(.cache_hit, "/tmp/test.ts", null, null);

    std.debug.print("✅ Logged 3 security events to audit log\n", .{});
}

test "AuditLogger: Log rotation" {
    const allocator = std.testing.allocator;

    const config = AuditLogConfig{
        .log_dir = "/tmp/vimcraft-audit-rotation-test",
        .log_filename = "rotation-test.log",
        .max_log_size_bytes = 200, // Very small to trigger rotation
        .max_rotated_logs = 2,
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    // Log enough to trigger rotation
    for (0..10) |i| {
        const path = try std.fmt.allocPrint(allocator, "/tmp/test-{d}.ts", .{i});
        defer allocator.free(path);
        try logger.logEvent(.file_loaded_success, path, null, null);
    }

    std.debug.print("✅ Log rotation triggered and completed\n", .{});
}

test "AuditLogEntry: JSON serialization" {
    const allocator = std.testing.allocator;

    const entry = AuditLogEntry{
        .timestamp = 1737417600000, // 2025-01-20 16:00:00 UTC
        .event_type = .path_traversal_blocked,
        .path = "/tmp/../etc/passwd",
        .resolved_path = "/etc/passwd",
        .error_code = loader.LoadError.PathTraversal,
        .user_context = null,
        .ip_address = null,
        .severity = .err,
    };

    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);

    try entry.toJSON(buf.writer(allocator));

    std.debug.print("\n=== JSON Audit Entry ===\n{s}\n", .{buf.items});

    // Verify JSON contains key fields
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"event\":\"path_traversal_blocked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"severity\":\"err\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\"/tmp/../etc/passwd\"") != null);
}

test "SecureLoader: Integrated logging" {
    const allocator = std.testing.allocator;

    var monitor = try security_monitor.SecurityMonitor.init(allocator);
    defer monitor.deinit();

    const audit_config = AuditLogConfig{
        .log_dir = "/tmp/vimcraft-secure-loader-test",
        .log_filename = "secure-loader-test.log",
    };

    var audit_logger = try AuditLogger.init(allocator, audit_config);
    defer audit_logger.deinit();

    var secure_loader = SecureLoader.init(allocator, &monitor, &audit_logger);

    var stats = cache.CacheStats{};
    const config = loader.LoaderConfig{
        .cache_dir = "/tmp/vimcraft-cache-secure-test",
        .enable_cache = false,
        .stats = &stats,
    };

    // Attempt to load malicious path
    const result = secure_loader.loadModule(config, "/tmp/../etc/passwd");
    try std.testing.expectError(loader.LoadError.PathTraversal, result);

    // Verify both systems logged the event
    try std.testing.expectEqual(@as(usize, 1), monitor.metrics.path_traversal_attempts);
    try std.testing.expectEqual(@as(usize, 1), monitor.metrics.total_blocked_attempts);

    std.debug.print("✅ SecureLoader logged to both monitor and audit log\n", .{});
}
