/// vimc install - Install plugins from Git URL or local path
///
/// Usage:
///   vimc install <git-url>        - Clone repo to ~/.config/vimcraft/plugins/<name>/
///   vimc install <local-path>     - Symlink local directory to plugins/
///   vimc install <name>           - Install from vimcraft registry (future)
///
/// Examples:
///   vimc install https://github.com/vimcraft/smear-cursor
///   vimc install ./my-local-plugin
///   vimc install @vimcraft/smear-cursor  (future registry support)

const std = @import("std");

/// Plugin source type
const SourceType = enum {
    git_url,
    local_path,
    registry, // Future: @vimcraft/package-name
};

/// Detect source type from input string
fn detectSourceType(source: []const u8) SourceType {
    if (std.mem.startsWith(u8, source, "https://") or
        std.mem.startsWith(u8, source, "git@") or
        std.mem.startsWith(u8, source, "http://"))
    {
        return .git_url;
    } else if (std.mem.startsWith(u8, source, "@")) {
        return .registry;
    } else {
        return .local_path;
    }
}

/// Extract plugin name from Git URL
/// Examples:
///   https://github.com/vimcraft/smear-cursor -> smear-cursor
///   https://github.com/vimcraft/smear-cursor.git -> smear-cursor
///   git@github.com:vimcraft/smear-cursor.git -> smear-cursor
fn extractPluginName(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    // Remove trailing .git if present
    var clean_url = url;
    if (std.mem.endsWith(u8, clean_url, ".git")) {
        clean_url = clean_url[0 .. clean_url.len - 4];
    }

    // Find last '/' or ':'
    var last_sep: usize = 0;
    for (clean_url, 0..) |c, i| {
        if (c == '/' or c == ':') {
            last_sep = i + 1;
        }
    }

    if (last_sep >= clean_url.len) {
        return error.InvalidUrl;
    }

    return try allocator.dupe(u8, clean_url[last_sep..]);
}

/// Get ~/.config/vimcraft directory
fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.config/vimcraft", .{home});
}

/// Get ~/.config/vimcraft/plugins directory
fn getPluginsDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.config/vimcraft/plugins", .{home});
}

/// Install plugin from Git URL
fn installFromGit(allocator: std.mem.Allocator, url: []const u8, force: bool) !void {
    const plugins_dir = try getPluginsDir(allocator);
    defer allocator.free(plugins_dir);

    // Ensure plugins directory exists
    std.fs.cwd().makePath(plugins_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error: Failed to create plugins directory: {}\n", .{err});
            return err;
        }
    };

    // Extract plugin name from URL
    const plugin_name = try extractPluginName(allocator, url);
    defer allocator.free(plugin_name);

    // Build target path
    const target_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ plugins_dir, plugin_name });
    defer allocator.free(target_path);

    // Check if already exists
    const exists = blk: {
        std.fs.cwd().access(target_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (exists and !force) {
        std.debug.print("Plugin '{s}' already exists.\n", .{plugin_name});
        std.debug.print("Use --force to reinstall.\n", .{});
        return error.AlreadyExists;
    }

    if (exists and force) {
        std.debug.print("Removing existing plugin '{s}'...\n", .{plugin_name});
        std.fs.cwd().deleteTree(target_path) catch |err| {
            std.debug.print("Error: Failed to remove existing plugin: {}\n", .{err});
            return err;
        };
    }

    std.debug.print("Installing '{s}' from {s}...\n", .{ plugin_name, url });

    // Run git clone
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "clone", "--depth", "1", url, target_path },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Error: git clone failed:\n{s}\n", .{result.stderr});
        return error.GitCloneFailed;
    }

    std.debug.print("Installed '{s}' to {s}\n", .{ plugin_name, target_path });

    // Check for entry point
    const has_index_ts = blk: {
        const index_ts = try std.fmt.allocPrint(allocator, "{s}/index.ts", .{target_path});
        defer allocator.free(index_ts);
        std.fs.cwd().access(index_ts, .{}) catch break :blk false;
        break :blk true;
    };

    const has_index_js = blk: {
        const index_js = try std.fmt.allocPrint(allocator, "{s}/index.js", .{target_path});
        defer allocator.free(index_js);
        std.fs.cwd().access(index_js, .{}) catch break :blk false;
        break :blk true;
    };

    if (has_index_ts) {
        std.debug.print("Found index.ts - plugin will be auto-loaded on startup.\n", .{});
    } else if (has_index_js) {
        std.debug.print("Found index.js - plugin will be auto-loaded on startup.\n", .{});
    } else {
        std.debug.print("Warning: No index.ts or index.js found.\n", .{});
        std.debug.print("Plugin may need manual configuration in init.ts.\n", .{});
    }
}

/// Install plugin from local path (creates symlink)
fn installFromLocal(allocator: std.mem.Allocator, path: []const u8, force: bool) !void {
    const plugins_dir = try getPluginsDir(allocator);
    defer allocator.free(plugins_dir);

    // Ensure plugins directory exists
    std.fs.cwd().makePath(plugins_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error: Failed to create plugins directory: {}\n", .{err});
            return err;
        }
    };

    // Resolve absolute path
    const abs_path = try std.fs.cwd().realpathAlloc(allocator, path);
    defer allocator.free(abs_path);

    // Check source exists and is directory
    const stat = std.fs.cwd().statFile(abs_path) catch |err| {
        std.debug.print("Error: Cannot access '{s}': {}\n", .{ path, err });
        return err;
    };

    if (stat.kind != .directory) {
        std.debug.print("Error: '{s}' is not a directory.\n", .{path});
        return error.NotADirectory;
    }

    // Extract plugin name from path (basename)
    const plugin_name = std.fs.path.basename(abs_path);

    // Build target path (symlink location)
    const target_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ plugins_dir, plugin_name });
    defer allocator.free(target_path);

    // Check if already exists
    const exists = blk: {
        std.fs.cwd().access(target_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (exists and !force) {
        std.debug.print("Plugin '{s}' already exists.\n", .{plugin_name});
        std.debug.print("Use --force to reinstall.\n", .{});
        return error.AlreadyExists;
    }

    if (exists and force) {
        std.debug.print("Removing existing plugin '{s}'...\n", .{plugin_name});
        // Remove symlink or directory
        std.fs.cwd().deleteFile(target_path) catch {
            std.fs.cwd().deleteTree(target_path) catch |err| {
                std.debug.print("Error: Failed to remove existing plugin: {}\n", .{err});
                return err;
            };
        };
    }

    std.debug.print("Linking '{s}' from {s}...\n", .{ plugin_name, abs_path });

    // Create symlink
    std.fs.cwd().symLink(abs_path, target_path, .{}) catch |err| {
        std.debug.print("Error: Failed to create symlink: {}\n", .{err});
        return err;
    };

    std.debug.print("Installed '{s}' (symlinked to {s})\n", .{ plugin_name, abs_path });
    std.debug.print("Changes to source will be reflected immediately.\n", .{});

    // Check for entry point
    const has_index_ts = blk: {
        const index_ts = try std.fmt.allocPrint(allocator, "{s}/index.ts", .{abs_path});
        defer allocator.free(index_ts);
        std.fs.cwd().access(index_ts, .{}) catch break :blk false;
        break :blk true;
    };

    const has_index_js = blk: {
        const index_js = try std.fmt.allocPrint(allocator, "{s}/index.js", .{abs_path});
        defer allocator.free(index_js);
        std.fs.cwd().access(index_js, .{}) catch break :blk false;
        break :blk true;
    };

    if (has_index_ts) {
        std.debug.print("Found index.ts - plugin will be auto-loaded on startup.\n", .{});
    } else if (has_index_js) {
        std.debug.print("Found index.js - plugin will be auto-loaded on startup.\n", .{});
    } else {
        std.debug.print("Warning: No index.ts or index.js found.\n", .{});
        std.debug.print("Plugin may need manual configuration in init.ts.\n", .{});
    }
}

/// Execute vimc install command
pub fn execute(allocator: std.mem.Allocator, source: []const u8, force: bool) !void {
    if (source.len == 0) {
        std.debug.print("Error: No source specified.\n", .{});
        std.debug.print("Usage: vimc install <git-url|local-path>\n", .{});
        std.debug.print("\nExamples:\n", .{});
        std.debug.print("  vimc install https://github.com/vimcraft/smear-cursor\n", .{});
        std.debug.print("  vimc install ./my-local-plugin\n", .{});
        return error.NoSource;
    }

    const source_type = detectSourceType(source);

    switch (source_type) {
        .git_url => {
            try installFromGit(allocator, source, force);
        },
        .local_path => {
            try installFromLocal(allocator, source, force);
        },
        .registry => {
            std.debug.print("Error: Registry install not yet implemented.\n", .{});
            std.debug.print("Use a Git URL instead:\n", .{});
            std.debug.print("  vimc install https://github.com/vimcraft/{s}\n", .{source[1..]});
            return error.NotImplemented;
        },
    }

    std.debug.print("\nRestart vimc to load the new plugin.\n", .{});
}

test "extractPluginName: https URL" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const name1 = try extractPluginName(allocator, "https://github.com/vimcraft/smear-cursor");
    try std.testing.expectEqualStrings("smear-cursor", name1);

    const name2 = try extractPluginName(allocator, "https://github.com/vimcraft/smear-cursor.git");
    try std.testing.expectEqualStrings("smear-cursor", name2);
}

test "extractPluginName: git@ URL" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const name = try extractPluginName(allocator, "git@github.com:vimcraft/smear-cursor.git");
    try std.testing.expectEqualStrings("smear-cursor", name);
}

test "detectSourceType" {
    try std.testing.expectEqual(SourceType.git_url, detectSourceType("https://github.com/foo/bar"));
    try std.testing.expectEqual(SourceType.git_url, detectSourceType("git@github.com:foo/bar"));
    try std.testing.expectEqual(SourceType.local_path, detectSourceType("./my-plugin"));
    try std.testing.expectEqual(SourceType.local_path, detectSourceType("/home/user/plugin"));
    try std.testing.expectEqual(SourceType.registry, detectSourceType("@vimcraft/smear-cursor"));
}
