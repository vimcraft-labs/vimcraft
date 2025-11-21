/// vimc remove - Remove installed plugins
///
/// Usage:
///   vimc remove <plugin-name>    - Remove plugin from ~/.config/vimcraft/plugins/
///   vimc remove --all            - Remove all plugins (with confirmation)
///
/// Examples:
///   vimc remove smear-cursor
///   vimc remove Hello-World

const std = @import("std");

/// Get ~/.config/vimcraft/plugins directory
fn getPluginsDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.config/vimcraft/plugins", .{home});
}

/// Remove a single plugin by name
fn removePlugin(allocator: std.mem.Allocator, name: []const u8) !void {
    const plugins_dir = try getPluginsDir(allocator);
    defer allocator.free(plugins_dir);

    const target_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ plugins_dir, name });
    defer allocator.free(target_path);

    // Check if plugin exists
    const stat = std.fs.cwd().statFile(target_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Plugin '{s}' not found.\n", .{name});
            std.debug.print("Use 'vimc list' to see installed plugins.\n", .{});
            return error.PluginNotFound;
        }
        std.debug.print("Error: Cannot access plugin '{s}': {}\n", .{ name, err });
        return err;
    };

    // Check if it's a symlink or directory
    const is_symlink = stat.kind == .sym_link;

    std.debug.print("Removing '{s}'", .{name});
    if (is_symlink) {
        std.debug.print(" (symlink)", .{});
    }
    std.debug.print("...\n", .{});

    // Remove symlink or directory
    if (is_symlink) {
        // For symlinks, use deleteFile
        std.fs.cwd().deleteFile(target_path) catch |err| {
            std.debug.print("Error: Failed to remove symlink: {}\n", .{err});
            return err;
        };
    } else {
        // For directories, use deleteTree
        std.fs.cwd().deleteTree(target_path) catch |err| {
            std.debug.print("Error: Failed to remove directory: {}\n", .{err});
            return err;
        };
    }

    std.debug.print("Removed '{s}'.\n", .{name});
}

/// Execute vimc remove command
pub fn execute(allocator: std.mem.Allocator, name: []const u8) !void {
    if (name.len == 0) {
        std.debug.print("Error: No plugin name specified.\n", .{});
        std.debug.print("Usage: vimc remove <plugin-name>\n", .{});
        std.debug.print("\nExamples:\n", .{});
        std.debug.print("  vimc remove smear-cursor\n", .{});
        std.debug.print("  vimc remove Hello-World\n", .{});
        std.debug.print("\nUse 'vimc list' to see installed plugins.\n", .{});
        return error.NoPluginName;
    }

    try removePlugin(allocator, name);
}

test "getPluginsDir" {
    // This test requires HOME to be set
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME")) |home| {
        const plugins_dir = try getPluginsDir(allocator);
        defer allocator.free(plugins_dir);

        // Should end with /.config/vimcraft/plugins
        try std.testing.expect(std.mem.endsWith(u8, plugins_dir, "/.config/vimcraft/plugins"));
        try std.testing.expect(std.mem.startsWith(u8, plugins_dir, home));
    }
}
