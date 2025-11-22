const std = @import("std");

// C imports
const c = @cImport({
    @cInclude("backends/headless/cdp_debugger.h");
});

/// Chrome DevTools Protocol Debugger
/// Enables debugging JavaScript configuration with Chrome DevTools
pub const Debugger = struct {
    handle: *c.CDPDebugger,

    /// Create a new debugger instance
    /// runtime: Hermes runtime to debug
    /// port: WebSocket port (default: 9229)
    pub fn init(runtime: *anyopaque, port: u16) !Debugger {
        const handle = c.cdp_debugger_create(
            @ptrCast(runtime),
            port,
        ) orelse return error.DebuggerCreateFailed;

        return Debugger{ .handle = handle };
    }

    /// Start the debugger server
    /// Prints Chrome DevTools URL for user to connect
    pub fn start(self: *Debugger) !void {
        if (!c.cdp_debugger_start(self.handle)) {
            return error.DebuggerStartFailed;
        }
    }

    /// Check if Chrome DevTools is connected
    pub fn isConnected(self: *const Debugger) bool {
        return c.cdp_debugger_is_connected(self.handle);
    }

    /// Send a log message to Chrome Console
    /// This allows Zig code to send debug messages to Chrome DevTools
    pub fn log(self: *Debugger, message: []const u8, level: LogLevel) void {
        const c_msg = @as([*c]const u8, @ptrCast(message.ptr));
        c.cdp_debugger_log(self.handle, c_msg, @intFromEnum(level));
    }

    /// Get the Chrome DevTools URL
    pub fn getUrl(self: *const Debugger) ?[:0]const u8 {
        const url = c.cdp_debugger_get_url(self.handle) orelse return null;
        return std.mem.span(url);
    }

    /// Stop the debugger server
    pub fn stop(self: *Debugger) void {
        c.cdp_debugger_stop(self.handle);
    }

    /// Clean up debugger resources
    pub fn deinit(self: *Debugger) void {
        c.cdp_debugger_destroy(self.handle);
    }
};

/// Console log levels for Chrome DevTools
pub const LogLevel = enum(c_int) {
    log = 0,
    debug = 1,
    info = 2,
    err = 3,
    warning = 4,
};
