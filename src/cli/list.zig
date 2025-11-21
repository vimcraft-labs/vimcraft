/// vimc list - List installed plugins
///
/// Usage:
///   vimc list    - Show all installed plugins
///   vimc ls      - Alias for list
///
/// Output format:
///   plugin-name     (git)      - Cloned from Git
///   plugin-name     (local)    - Symlinked from local path

const std = @import("std");

/// Get ~/.config/vimcraft/plugins directory
fn getPluginsDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.config/vimcraft/plugins", .{home});
}

/// Plugin info for display
const PluginInfo = struct {
    name: []const u8,
    source_type: enum { git, local, unknown },
    target_path: ?[]const u8, // For symlinks, the target path

    fn getTypeString(self: PluginInfo) []const u8 {
        return switch (self.source_type) {
            .git => "git",
            .local => "local",
            .unknown => "unknown",
        };
    }
};

/// Execute vimc list command
pub fn execute(allocator: std.mem.Allocator) !void {
    const plugins_dir = try getPluginsDir(allocator);
    defer allocator.free(plugins_dir);

    // Check if plugins directory exists
    var dir = std.fs.cwd().openDir(plugins_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No plugins installed.\n", .{});
            std.debug.print("\nInstall plugins with:\n", .{});
            std.debug.print("  vimc install <git-url>\n", .{});
            std.debug.print("  vimc install <local-path>\n", .{});
            return;
        }
        std.debug.print("Error: Cannot access plugins directory: {}\n", .{err});
        return err;
    };
    defer dir.close();

    // Collect plugins
    var plugins: std.ArrayListUnmanaged(PluginInfo) = .empty;
    defer {
        for (plugins.items) |plugin| {
            allocator.free(plugin.name);
            if (plugin.target_path) |path| {
                allocator.free(path);
            }
        }
        plugins.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip hidden files
        if (entry.name[0] == '.') continue;

        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);

        // Check if it's a symlink
        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ plugins_dir, entry.name });
        defer allocator.free(full_path);

        // Use readLink to detect symlinks (statFile follows symlinks)
        var symlink_buf: [std.fs.max_path_bytes]u8 = undefined;
        const is_symlink = blk: {
            _ = std.fs.cwd().readLink(full_path, &symlink_buf) catch break :blk false;
            break :blk true;
        };

        if (is_symlink) {
            // Get symlink target
            var target_buf: [std.fs.max_path_bytes]u8 = undefined;
            const target = std.fs.cwd().readLink(full_path, &target_buf) catch {
                try plugins.append(allocator, .{
                    .name = name,
                    .source_type = .local,
                    .target_path = null,
                });
                continue;
            };
            const target_path = try allocator.dupe(u8, target);

            try plugins.append(allocator, .{
                .name = name,
                .source_type = .local,
                .target_path = target_path,
            });
        } else {
            // It's a directory - check if it has .git (cloned repo)
            const git_path = try std.fmt.allocPrint(allocator, "{s}/.git", .{full_path});
            defer allocator.free(git_path);

            const is_git = blk: {
                std.fs.cwd().access(git_path, .{}) catch break :blk false;
                break :blk true;
            };

            try plugins.append(allocator, .{
                .name = name,
                .source_type = if (is_git) .git else .unknown,
                .target_path = null,
            });
        }
    }

    // Display results
    if (plugins.items.len == 0) {
        std.debug.print("No plugins installed.\n", .{});
        std.debug.print("\nInstall plugins with:\n", .{});
        std.debug.print("  vimc install <git-url>\n", .{});
        std.debug.print("  vimc install <local-path>\n", .{});
        return;
    }

    std.debug.print("Installed plugins ({d}):\n\n", .{plugins.items.len});

    // Find max name length for alignment
    var max_name_len: usize = 0;
    for (plugins.items) |plugin| {
        if (plugin.name.len > max_name_len) {
            max_name_len = plugin.name.len;
        }
    }

    // Print each plugin
    for (plugins.items) |plugin| {
        // Pad name for alignment
        std.debug.print("  {s}", .{plugin.name});
        var padding = max_name_len - plugin.name.len + 2;
        while (padding > 0) : (padding -= 1) {
            std.debug.print(" ", .{});
        }

        std.debug.print("({s})", .{plugin.getTypeString()});

        if (plugin.target_path) |target| {
            std.debug.print("  -> {s}", .{target});
        }

        std.debug.print("\n", .{});
    }

    std.debug.print("\nUse 'vimc remove <name>' to uninstall a plugin.\n", .{});
}

test "getPluginsDir" {
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME")) |home| {
        const plugins_dir = try getPluginsDir(allocator);
        defer allocator.free(plugins_dir);

        try std.testing.expect(std.mem.endsWith(u8, plugins_dir, "/.config/vimcraft/plugins"));
        try std.testing.expect(std.mem.startsWith(u8, plugins_dir, home));
    }
}
