const std = @import("std");

var log_file: ?std.fs.File = null;
var log_mutex = std.Thread.Mutex{};

pub fn init() !void {
    log_file = try std.fs.cwd().createFile("/tmp/openvim_debug.log", .{ .truncate = true });
}

pub fn deinit() void {
    if (log_file) |f| {
        f.close();
        log_file = null;
    }
}

pub fn log(comptime fmt: []const u8, args: anytype) void {
    log_mutex.lock();
    defer log_mutex.unlock();

    if (log_file) |f| {
        var buf: [4096]u8 = undefined;
        var w = f.writer(&buf);
        const writer = &w.interface;
        writer.print(fmt, args) catch {};
        writer.writeAll("\n") catch {};
        f.sync() catch {};
    }
}
