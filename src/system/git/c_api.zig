/// libgit2 C API bindings for Zig
/// Provides direct access to libgit2 functions via @cImport
const std = @import("std");

pub const c = @cImport({
    @cInclude("git2.h");
});

/// Initialize libgit2 library (must be called before any other git functions)
/// Returns the number of initializations (for nested init/shutdown)
pub fn init() !c_int {
    const result = c.git_libgit2_init();
    if (result < 0) {
        return error.LibGit2InitFailed;
    }
    return result;
}

/// Shutdown libgit2 library (call once for each init)
pub fn shutdown() !void {
    const result = c.git_libgit2_shutdown();
    if (result < 0) {
        return error.LibGit2ShutdownFailed;
    }
}

/// Get the last libgit2 error message
pub fn getLastError() ?[]const u8 {
    const err = c.git_error_last();
    if (err != null) {
        if (err.*.message) |msg| {
            return std.mem.span(msg);
        }
    }
    return null;
}

/// Get libgit2 version
pub fn getVersion() struct { major: c_int, minor: c_int, rev: c_int } {
    var major: c_int = 0;
    var minor: c_int = 0;
    var rev: c_int = 0;
    _ = c.git_libgit2_version(&major, &minor, &rev);
    return .{ .major = major, .minor = minor, .rev = rev };
}

// ============================================================================
// Tests
// ============================================================================

test "libgit2 init and version" {
    const init_count = try init();
    defer shutdown() catch {};

    try std.testing.expect(init_count >= 1);

    const version = getVersion();
    std.debug.print("\nlibgit2 version: {d}.{d}.{d}\n", .{ version.major, version.minor, version.rev });

    // Should be 1.9.x
    try std.testing.expect(version.major >= 1);
}
