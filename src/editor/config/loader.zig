const std = @import("std");

/// Configuration paths following XDG Base Directory specification
/// TypeScript-only: Vimcraft uses TypeScript exclusively for configuration
pub const ConfigPaths = struct {
    config_dir: []const u8,
    plugins_dir: []const u8, // Plugin directory: ~/.config/vimcraft/plugins
    index_ts_path: []const u8, // TypeScript config entry: ~/.config/vimcraft/index.ts
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ConfigPaths {
        // Get home directory
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

        // Config directory: ~/.config/vimcraft
        const config_dir = try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "vimcraft" });
        errdefer allocator.free(config_dir);

        // Plugins directory: ~/.config/vimcraft/plugins
        const plugins_dir = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "plugins" });
        errdefer allocator.free(plugins_dir);

        // Check for OPENVIM_CONFIG environment variable to override config path
        // This allows testing with custom config files: OPENVIM_CONFIG=/tmp/test.js ./vimc
        const index_ts_path = if (std.posix.getenv("OPENVIM_CONFIG")) |override_path|
            try allocator.dupe(u8, override_path)
        else
            // index.ts path: ~/.config/vimcraft/index.ts (TypeScript entry point)
            try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "index.ts" });

        return .{
            .config_dir = config_dir,
            .plugins_dir = plugins_dir,
            .index_ts_path = index_ts_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConfigPaths) void {
        self.allocator.free(self.config_dir);
        self.allocator.free(self.plugins_dir);
        self.allocator.free(self.index_ts_path);
    }

    /// Ensure config and plugins directories exist
    pub fn ensureConfigDir(self: *const ConfigPaths) !void {
        // Create config directory
        std.fs.makeDirAbsolute(self.config_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Create plugins directory
        std.fs.makeDirAbsolute(self.plugins_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    /// Check if index.ts exists
    pub fn indexTsExists(self: *const ConfigPaths) bool {
        const file = std.fs.openFileAbsolute(self.index_ts_path, .{}) catch return false;
        file.close();
        return true;
    }

    /// Read index.ts content
    pub fn readIndexTs(self: *const ConfigPaths, allocator: std.mem.Allocator) ![]const u8 {
        const file = try std.fs.openFileAbsolute(self.index_ts_path, .{});
        defer file.close();

        const max_size = 1024 * 1024; // 1MB max
        return try file.readToEndAlloc(allocator, max_size);
    }

    /// Create default index.ts if it doesn't exist
    pub fn createDefaultIndexTs(self: *const ConfigPaths) !void {
        // Don't overwrite existing file
        if (self.indexTsExists()) return;

        const default_config =
            \\// Vimcraft Configuration (TypeScript)
            \\// This file is transpiled to JavaScript and executed on startup
            \\
            \\// Display options (all off by default, matching Neovim)
            \\// vim.opt.number = true;                                         // Show line numbers
            \\// vim.opt.relativenumber = true;                                 // Relative line numbers
            \\// vim.opt.cursorline = true;                                     // Highlight cursor line
            \\
            \\// Color scheme examples:
            \\// vim.highlight('Normal', { bg: '#1e1e1e', fg: '#d4d4d4' });     // VS Code Dark
            \\// vim.highlight('Normal', { bg: '#282828', fg: '#ebdbb2' });     // Gruvbox Dark
            \\// vim.highlight('Normal', { bg: '#282a36', fg: '#f8f8f2' });     // Dracula
            \\// vim.highlight('CursorLine', { bg: '#2b2b2b' });                // Subtle gray
            \\
        ;

        const file = try std.fs.createFileAbsolute(self.index_ts_path, .{});
        defer file.close();

        try file.writeAll(default_config);
    }

    /// Plugin information structure
    pub const PluginInfo = struct {
        name: []const u8, // Plugin directory name (e.g., "a", "b", "smear-cursor")
        index_path: []const u8, // Absolute path to index.ts
        has_entry: bool, // Whether index.ts exists (determines if plugin gets loaded)

        pub fn deinit(self: *PluginInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.index_path);
        }
    };

    /// Discover plugins in ~/.config/vimcraft/plugins/
    /// Returns plugins sorted alphabetically by name
    /// Each plugin with index.ts will be loaded in order
    pub fn discoverPlugins(self: *const ConfigPaths, allocator: std.mem.Allocator) !std.ArrayList(PluginInfo) {
        var plugins = std.ArrayList(PluginInfo).empty;
        errdefer {
            for (plugins.items) |*plugin| {
                plugin.deinit(allocator);
            }
            plugins.deinit(allocator);
        }

        // Open plugins directory
        var dir = std.fs.openDirAbsolute(self.plugins_dir, .{ .iterate = true }) catch {
            // Plugins directory doesn't exist, return empty list
            return plugins;
        };
        defer dir.close();

        // Iterate over subdirectories in plugins/
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Only process directories
            if (entry.kind != .directory) continue;

            // Skip hidden directories and special names
            if (std.mem.startsWith(u8, entry.name, ".")) continue;
            if (std.mem.eql(u8, entry.name, "node_modules")) continue;

            // Build path to potential index.ts
            const index_path = try std.fs.path.join(allocator, &[_][]const u8{ self.plugins_dir, entry.name, "index.ts" });
            errdefer allocator.free(index_path);

            // Check if index.ts exists
            const has_entry = blk: {
                const file = std.fs.openFileAbsolute(index_path, .{}) catch break :blk false;
                file.close();
                break :blk true;
            };

            // Duplicate plugin name for PluginInfo
            const name = try allocator.dupe(u8, entry.name);
            errdefer allocator.free(name);

            try plugins.append(allocator, .{
                .name = name,
                .index_path = index_path,
                .has_entry = has_entry,
            });
        }

        // Sort plugins alphabetically by name
        std.mem.sort(PluginInfo, plugins.items, {}, struct {
            fn lessThan(_: void, a: PluginInfo, b: PluginInfo) bool {
                return std.mem.order(u8, a.name, b.name) == .lt;
            }
        }.lessThan);

        return plugins;
    }
};

/// Print config paths for debugging
pub fn printConfigInfo(paths: *const ConfigPaths, writer: anytype) !void {
    try writer.print("Config directory: {s}\n", .{paths.config_dir});
    try writer.print("Plugins directory: {s}\n", .{paths.plugins_dir});
    try writer.print("index.ts path: {s}\n", .{paths.index_ts_path});
    try writer.print("index.ts exists: {}\n", .{paths.indexTsExists()});
}
