const std = @import("std");

/// Configuration paths following XDG Base Directory specification
pub const ConfigPaths = struct {
    config_dir: []const u8,
    init_js_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ConfigPaths {
        // Get home directory
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

        // Config directory: ~/.config/openvim
        const config_dir = try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "openvim" });
        errdefer allocator.free(config_dir);

        // init.js path: ~/.config/openvim/init.js
        const init_js_path = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "init.js" });

        return .{
            .config_dir = config_dir,
            .init_js_path = init_js_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConfigPaths) void {
        self.allocator.free(self.config_dir);
        self.allocator.free(self.init_js_path);
    }

    /// Ensure config directory exists, create if needed
    pub fn ensureConfigDir(self: *const ConfigPaths) !void {
        std.fs.makeDirAbsolute(self.config_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    /// Check if init.js exists
    pub fn initJsExists(self: *const ConfigPaths) bool {
        const file = std.fs.openFileAbsolute(self.init_js_path, .{}) catch return false;
        file.close();
        return true;
    }

    /// Read init.js content
    pub fn readInitJs(self: *const ConfigPaths, allocator: std.mem.Allocator) ![]const u8 {
        const file = try std.fs.openFileAbsolute(self.init_js_path, .{});
        defer file.close();

        const max_size = 1024 * 1024; // 1MB max
        return try file.readToEndAlloc(allocator, max_size);
    }

    /// Create default init.js if it doesn't exist
    pub fn createDefaultInitJs(self: *const ConfigPaths) !void {
        // Don't overwrite existing file
        if (self.initJsExists()) return;

        const default_config =
            \\// OpenVim Configuration (JavaScript via Hermes+JSI)
            \\// This file is executed on startup
            \\
            \\// Set normal text background and foreground
            \\vim.highlight('Normal', { bg: '#1e1e1e', fg: '#d4d4d4' });
            \\
            \\// Set cursor line background color
            \\vim.highlight('CursorLine', { bg: '#2b2b2b' });
            \\
            \\// Enable cursor line highlighting
            \\vim.opt.cursorline = true;
            \\
            \\// More configuration examples:
            \\// vim.highlight('Normal', { bg: '#282828', fg: '#ebdbb2' });     // Gruvbox dark
            \\// vim.highlight('Normal', { bg: '#282a36', fg: '#f8f8f2' });     // Dracula
            \\// vim.highlight('CursorLine', { bg: '#3a3a3a' });                // lighter gray
            \\// vim.opt.cursorline = false;                                    // disable cursor line
            \\
        ;

        const file = try std.fs.createFileAbsolute(self.init_js_path, .{});
        defer file.close();

        try file.writeAll(default_config);
    }
};

/// Print config paths for debugging
pub fn printConfigInfo(paths: *const ConfigPaths, writer: anytype) !void {
    try writer.print("Config directory: {s}\n", .{paths.config_dir});
    try writer.print("init.js path: {s}\n", .{paths.init_js_path});
    try writer.print("init.js exists: {}\n", .{paths.initJsExists()});
}
