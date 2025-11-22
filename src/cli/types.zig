/// vimc types - Sync vim.d.ts to ~/.config/vimcraft
///
/// Usage:
///   vimc types           - Sync vim.d.ts to config directory
///   vimc types --check   - Verify types are up-to-date (exit 1 if outdated)
///
/// The vim.d.ts file is embedded at build time, so this works from anywhere.

const std = @import("std");

/// Embedded vim.d.ts (source of truth, included at compile time)
const VIM_DTS_CONTENT = @embedFile("vim.d.ts");

/// Get ~/.config/vimcraft directory
fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.config/vimcraft", .{home});
}

/// Execute vimc types command
pub fn execute(allocator: std.mem.Allocator, check_only: bool) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const vim_dts_path = try std.fmt.allocPrint(allocator, "{s}/vim.d.ts", .{config_dir});
    defer allocator.free(vim_dts_path);

    if (check_only) {
        // Check mode: compare embedded vs installed
        const installed_content = std.fs.cwd().readFileAlloc(allocator, vim_dts_path, 1024 * 1024) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("vim.d.ts not found in {s}\n", .{config_dir});
                std.debug.print("Run 'vimc init' or 'vimc types' to install.\n", .{});
                return error.TypesOutdated;
            }
            return err;
        };
        defer allocator.free(installed_content);

        if (std.mem.eql(u8, VIM_DTS_CONTENT, installed_content)) {
            std.debug.print("vim.d.ts is up-to-date ({d} bytes)\n", .{VIM_DTS_CONTENT.len});
            return; // Success - types are current
        } else {
            std.debug.print("vim.d.ts is OUTDATED\n", .{});
            std.debug.print("  Installed: {d} bytes\n", .{installed_content.len});
            std.debug.print("  Latest:    {d} bytes\n", .{VIM_DTS_CONTENT.len});
            std.debug.print("\nRun 'vimc types' to update.\n", .{});
            return error.TypesOutdated;
        }
    }

    // Sync mode: write embedded types to config directory
    // Ensure config directory exists
    std.fs.cwd().makePath(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error: Failed to create config directory: {}\n", .{err});
            return err;
        }
    };

    // Write vim.d.ts
    try std.fs.cwd().writeFile(.{
        .sub_path = vim_dts_path,
        .data = VIM_DTS_CONTENT,
    });

    std.debug.print("Updated vim.d.ts ({d} bytes)\n", .{VIM_DTS_CONTENT.len});
    std.debug.print("  Location: {s}\n", .{vim_dts_path});
}
