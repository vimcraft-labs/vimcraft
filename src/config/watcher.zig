const std = @import("std");
const uv = @import("../event_loop/libuv.zig").uv;

/// Configuration file watcher for hot reload
pub const ConfigWatcher = struct {
    allocator: std.mem.Allocator,
    fs_event: uv.uv_fs_event_t,
    watched_dir: []u8,
    watched_dir_z: [:0]u8,
    target_filename: []u8,
    callback: *const fn (?*anyopaque) void,
    user_data: ?*anyopaque,
    is_watching: bool,
    is_closing: bool,

    /// Create a new file watcher
    pub fn init(
        allocator: std.mem.Allocator,
        filepath: []const u8,
        callback: *const fn (?*anyopaque) void,
        user_data: ?*anyopaque,
    ) !*ConfigWatcher {
        const self = try allocator.create(ConfigWatcher);

        // Get directory path
        const dir_end = std.mem.lastIndexOf(u8, filepath, "/") orelse return error.InvalidPath;
        const dir_path = filepath[0..dir_end];
        const filename = filepath[dir_end + 1 ..];

        self.* = .{
            .allocator = allocator,
            .fs_event = undefined,
            .watched_dir = try allocator.dupe(u8, dir_path),
            .watched_dir_z = try allocator.dupeZ(u8, dir_path),
            .target_filename = try allocator.dupe(u8, filename),
            .callback = callback,
            .user_data = user_data,
            .is_watching = false,
            .is_closing = false,
        };

        // Initialize fs_event handle
        _ = uv.uv_fs_event_init(uv.uv_default_loop(), &self.fs_event);
        self.fs_event.data = self;

        return self;
    }

    /// Start watching the file
    pub fn start(self: *ConfigWatcher) !void {
        if (self.is_watching) {
            return error.AlreadyWatching;
        }

        // Watch the directory
        const result = uv.uv_fs_event_start(
            &self.fs_event,
            onFsEvent,
            self.watched_dir_z.ptr,
            0,
        );

        if (result < 0) {
            return error.WatchFailed;
        }

        self.is_watching = true;
    }

    /// Stop watching the configuration file (immediate stop, but doesn't free memory)
    pub fn stop(self: *ConfigWatcher) void {
        if (!self.is_watching) {
            return;
        }

        _ = uv.uv_fs_event_stop(&self.fs_event);
        self.is_watching = false;
    }

    /// Properly close the watcher using libuv close callback
    /// This is the correct way to cleanup libuv handles - the callback will be
    /// invoked by the event loop when the handle is fully closed, at which point
    /// it's safe to free all memory including the struct itself.
    pub fn close(self: *ConfigWatcher) void {
        if (self.is_closing) {
            return;
        }

        self.is_closing = true;

        // Stop watching first
        if (self.is_watching) {
            _ = uv.uv_fs_event_stop(&self.fs_event);
            self.is_watching = false;
        }

        // Close the handle - the callback will be invoked when it's safe to free memory
        uv.uv_close(@ptrCast(&self.fs_event), onCloseCallback);
    }

    /// libuv close callback - called when handle is fully closed and safe to free
    fn onCloseCallback(handle: [*c]uv.uv_handle_t) callconv(.C) void {
        const fs_event: *uv.uv_fs_event_t = @ptrCast(@alignCast(handle));
        const self: *ConfigWatcher = @ptrCast(@alignCast(fs_event.data));

        // Now it's safe to free all memory
        const allocator = self.allocator;
        allocator.free(self.watched_dir);
        allocator.free(self.target_filename);
        allocator.free(self.watched_dir_z);
        allocator.destroy(self);
    }

    /// libuv callback for fs_event
    fn onFsEvent(
        handle: [*c]uv.uv_fs_event_t,
        filename: [*c]const u8,
        events: c_int,
        status: c_int,
    ) callconv(.C) void {
        if (status != 0) {
            return;
        }

        const self = @as(*ConfigWatcher, @ptrCast(@alignCast(handle.*.data)));

        // Check if it's our target file
        if (filename != null) {
            const changed_file = std.mem.span(filename);
            if (std.mem.eql(u8, changed_file, self.target_filename)) {
                // File changed - trigger callback
                if (events & uv.UV_CHANGE != 0 or events & uv.UV_RENAME != 0) {
                    self.callback(self.user_data);
                }
            }
        }
    }
};
