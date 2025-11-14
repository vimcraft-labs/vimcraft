const std = @import("std");

/// Log level for messages
pub const LogLevel = enum {
    debug,
    info,
    warning,
    err,
};

/// Log entry that Core produces for Backends to consume
pub const LogEntry = struct {
    message: []const u8,
    level: LogLevel,
    timestamp_ms: i64,

    pub fn init(message: []const u8, level: LogLevel) LogEntry {
        return .{
            .message = message,
            .level = level,
            .timestamp_ms = std.time.milliTimestamp(),
        };
    }
};

/// Log buffer (ring buffer for LLM backend to analyze)
pub const LogBuffer = struct {
    entries: std.ArrayList(LogEntry),
    allocator: std.mem.Allocator,
    max_entries: usize,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) LogBuffer {
        return .{
            .entries = .empty,
            .allocator = allocator,
            .max_entries = max_entries,
        };
    }

    pub fn deinit(self: *LogBuffer) void {
        // Free all message strings
        for (self.entries.items) |entry| {
            self.allocator.free(entry.message);
        }
        self.entries.deinit(self.allocator);
    }

    /// Add a log entry (takes ownership of message string)
    pub fn append(self: *LogBuffer, entry: LogEntry) !void {
        // If at max capacity, remove oldest entry
        if (self.entries.items.len >= self.max_entries) {
            const oldest = self.entries.orderedRemove(0);
            self.allocator.free(oldest.message);
        }

        try self.entries.append(self.allocator, entry);
    }

    /// Get all log entries (for LLM to read)
    pub fn getAll(self: *const LogBuffer) []const LogEntry {
        return self.entries.items;
    }

    /// Get recent N entries
    pub fn getRecent(self: *const LogBuffer, n: usize) []const LogEntry {
        const start = if (self.entries.items.len > n) self.entries.items.len - n else 0;
        return self.entries.items[start..];
    }

    /// Clear all entries
    pub fn clear(self: *LogBuffer) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.message);
        }
        self.entries.clearRetainingCapacity();
    }
};

/// Logger that Editor Core uses
/// Backends subscribe to logs via callback
pub const Logger = struct {
    buffer: LogBuffer,
    callback: ?*const fn (LogEntry) void = null,

    pub fn init(allocator: std.mem.Allocator) Logger {
        return .{
            .buffer = LogBuffer.init(allocator, 10000), // Keep last 10000 log entries
        };
    }

    pub fn deinit(self: *Logger) void {
        self.buffer.deinit();
    }

    /// Set callback for backends to receive logs in real-time
    pub fn setCallback(self: *Logger, callback: *const fn (LogEntry) void) void {
        self.callback = callback;
    }

    /// Log a message from Core (takes ownership of message string)
    pub fn log(self: *Logger, message: []const u8, level: LogLevel) !void {
        const entry = LogEntry.init(message, level);

        // Store in buffer (for LLM backend analysis)
        try self.buffer.append(entry);

        // Notify backend via callback (for Terminal backend with Chrome Debugger)
        if (self.callback) |cb| {
            cb(entry);
        }
    }

    /// Convenience functions
    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const msg = try std.fmt.allocPrint(self.buffer.allocator, fmt, args);
        errdefer self.buffer.allocator.free(msg);
        try self.log(msg, .debug);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const msg = try std.fmt.allocPrint(self.buffer.allocator, fmt, args);
        errdefer self.buffer.allocator.free(msg);
        try self.log(msg, .info);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const msg = try std.fmt.allocPrint(self.buffer.allocator, fmt, args);
        errdefer self.buffer.allocator.free(msg);
        try self.log(msg, .warning);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const msg = try std.fmt.allocPrint(self.buffer.allocator, fmt, args);
        errdefer self.buffer.allocator.free(msg);
        try self.log(msg, .err);
    }
};
