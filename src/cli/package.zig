/// vimc package management - Install/uninstall/list plugins
///
/// Commands:
///   vimc install <source>   - Install from Git URL or local path
///   vimc uninstall <name>   - Remove installed plugin
///   vimc list               - Show installed plugins

const std = @import("std");

/// Install plugin from source (Git URL or local path)
pub fn install(allocator: std.mem.Allocator, source: []const u8) !void {
    _ = allocator;

    // TODO: Implement vimc install
    // 1. Detect source type (git URL vs local path)
    // 2. If git URL:
    //    - Extract plugin name from URL
    //    - git clone to ~/.config/vimcraft/plugins/<name>/
    // 3. If local path:
    //    - Symlink or copy to ~/.config/vimcraft/plugins/
    // 4. Parse vimcraft.json (if exists)
    // 5. Install dependencies recursively
    // 6. Update ~/.config/vimcraft/.vimcraft/installed.json

    std.debug.print("TODO: vimc install {s}\n", .{source});
    return error.NotImplemented;
}

/// Uninstall plugin by name
pub fn uninstall(allocator: std.mem.Allocator, name: []const u8) !void {
    _ = allocator;

    // TODO: Implement vimc uninstall
    // 1. Check if plugin exists in ~/.config/vimcraft/plugins/
    // 2. Remove directory/file
    // 3. Update ~/.config/vimcraft/.vimcraft/installed.json
    // 4. ⚠️ Don't remove dependencies (might be used by other plugins)

    std.debug.print("TODO: vimc uninstall {s}\n", .{name});
    return error.NotImplemented;
}

/// List installed plugins
pub fn list(allocator: std.mem.Allocator) !void {
    _ = allocator;

    // TODO: Implement vimc list
    // 1. Read ~/.config/vimcraft/.vimcraft/installed.json
    // 2. For each plugin:
    //    - Print name, version, source (git URL or local path)
    //    - Indicate if it's a dependency

    std.debug.print("TODO: vimc list\n", .{});
    return error.NotImplemented;
}
