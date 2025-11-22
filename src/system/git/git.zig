/// High-level Zig wrapper for libgit2
/// Provides ergonomic API for git operations exposed to plugins
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Git errors
pub const GitError = error{
    LibGit2InitFailed,
    RepositoryNotFound,
    RepositoryOpenFailed,
    NotARepository,
    BranchNotFound,
    StatusFailed,
    HeadNotFound,
    InvalidPath,
    OutOfMemory,
};

/// File status in git
pub const FileStatus = enum {
    untracked,
    ignored,
    unmodified,
    modified,
    added,
    deleted,
    renamed,
    copied,
    conflicted,
};

/// Repository handle
pub const Repository = struct {
    ptr: *c.git_repository,
    allocator: std.mem.Allocator,

    /// Open a git repository from path
    /// Path can be a working directory or .git directory
    pub fn open(allocator: std.mem.Allocator, path: []const u8) GitError!Repository {
        var repo: ?*c.git_repository = null;
        const path_z = allocator.dupeZ(u8, path) catch return GitError.OutOfMemory;
        defer allocator.free(path_z);

        const result = c.git_repository_open(&repo, path_z.ptr);
        if (result < 0 or repo == null) {
            return GitError.RepositoryOpenFailed;
        }

        return Repository{
            .ptr = repo.?,
            .allocator = allocator,
        };
    }

    /// Discover repository from path (walks up to find .git)
    pub fn discover(allocator: std.mem.Allocator, start_path: []const u8) GitError!Repository {
        var buf: c.git_buf = .{ .ptr = null, .reserved = 0, .size = 0 };
        defer c.git_buf_dispose(&buf);

        const path_z = allocator.dupeZ(u8, start_path) catch return GitError.OutOfMemory;
        defer allocator.free(path_z);

        const result = c.git_repository_discover(&buf, path_z.ptr, 0, null);
        if (result < 0) {
            return GitError.RepositoryNotFound;
        }

        // Open the discovered repository
        var repo: ?*c.git_repository = null;
        const open_result = c.git_repository_open(&repo, buf.ptr);
        if (open_result < 0 or repo == null) {
            return GitError.RepositoryOpenFailed;
        }

        return Repository{
            .ptr = repo.?,
            .allocator = allocator,
        };
    }

    /// Close repository and free resources
    pub fn deinit(self: *Repository) void {
        c.git_repository_free(self.ptr);
    }

    /// Check if repository is bare
    pub fn isBare(self: *const Repository) bool {
        return c.git_repository_is_bare(self.ptr) != 0;
    }

    /// Check if repository is empty
    pub fn isEmpty(self: *const Repository) bool {
        return c.git_repository_is_empty(self.ptr) == 1;
    }

    /// Get repository path (.git directory)
    pub fn getPath(self: *const Repository) ?[]const u8 {
        const path = c.git_repository_path(self.ptr);
        if (path) |p| {
            return std.mem.span(p);
        }
        return null;
    }

    /// Get working directory path
    pub fn getWorkdir(self: *const Repository) ?[]const u8 {
        const path = c.git_repository_workdir(self.ptr);
        if (path) |p| {
            return std.mem.span(p);
        }
        return null;
    }

    /// Get current branch name
    pub fn getCurrentBranch(self: *const Repository, allocator: std.mem.Allocator) GitError![]const u8 {
        var head: ?*c.git_reference = null;
        const result = c.git_repository_head(&head, self.ptr);
        if (result < 0 or head == null) {
            return GitError.HeadNotFound;
        }
        defer c.git_reference_free(head);

        const name = c.git_reference_shorthand(head);
        if (name) |n| {
            return allocator.dupe(u8, std.mem.span(n)) catch return GitError.OutOfMemory;
        }
        return GitError.BranchNotFound;
    }

    /// Get HEAD commit hash (short form)
    pub fn getHeadShort(self: *const Repository, allocator: std.mem.Allocator) GitError![]const u8 {
        var head: ?*c.git_reference = null;
        const result = c.git_repository_head(&head, self.ptr);
        if (result < 0 or head == null) {
            return GitError.HeadNotFound;
        }
        defer c.git_reference_free(head);

        const oid = c.git_reference_target(head);
        if (oid) |o| {
            var buf: [8]u8 = undefined;
            _ = c.git_oid_tostr(&buf, buf.len, o);
            return allocator.dupe(u8, buf[0..7]) catch return GitError.OutOfMemory;
        }
        return GitError.HeadNotFound;
    }

    /// Check if file is tracked by git
    pub fn isTracked(self: *const Repository, filepath: []const u8) GitError!bool {
        var status_flags: c_uint = 0;
        const path_z = self.allocator.dupeZ(u8, filepath) catch return GitError.OutOfMemory;
        defer self.allocator.free(path_z);

        const result = c.git_status_file(&status_flags, self.ptr, path_z.ptr);
        if (result == c.GIT_ENOTFOUND) {
            return false;
        }
        if (result < 0) {
            return GitError.StatusFailed;
        }

        // Untracked files have GIT_STATUS_WT_NEW flag
        return (status_flags & c.GIT_STATUS_WT_NEW) == 0;
    }

    /// Get file status
    pub fn getFileStatus(self: *const Repository, filepath: []const u8) GitError!FileStatus {
        var status_flags: c_uint = 0;
        const path_z = self.allocator.dupeZ(u8, filepath) catch return GitError.OutOfMemory;
        defer self.allocator.free(path_z);

        const result = c.git_status_file(&status_flags, self.ptr, path_z.ptr);
        if (result == c.GIT_ENOTFOUND) {
            return .untracked;
        }
        if (result < 0) {
            return GitError.StatusFailed;
        }

        // Check flags in order of priority
        if (status_flags == 0) return .unmodified;
        if ((status_flags & c.GIT_STATUS_IGNORED) != 0) return .ignored;
        if ((status_flags & c.GIT_STATUS_CONFLICTED) != 0) return .conflicted;
        if ((status_flags & c.GIT_STATUS_WT_NEW) != 0) return .untracked;
        if ((status_flags & c.GIT_STATUS_INDEX_NEW) != 0) return .added;
        if ((status_flags & (c.GIT_STATUS_INDEX_DELETED | c.GIT_STATUS_WT_DELETED)) != 0) return .deleted;
        if ((status_flags & (c.GIT_STATUS_INDEX_RENAMED | c.GIT_STATUS_WT_RENAMED)) != 0) return .renamed;
        if ((status_flags & (c.GIT_STATUS_INDEX_MODIFIED | c.GIT_STATUS_WT_MODIFIED)) != 0) return .modified;

        return .unmodified;
    }

    /// Check if repository has uncommitted changes
    pub fn isDirty(self: *const Repository) GitError!bool {
        var opts: c.git_status_options = undefined;
        _ = c.git_status_options_init(&opts, c.GIT_STATUS_OPTIONS_VERSION);
        opts.show = c.GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
        opts.flags = c.GIT_STATUS_OPT_INCLUDE_UNTRACKED;

        var status_list: ?*c.git_status_list = null;
        const result = c.git_status_list_new(&status_list, self.ptr, &opts);
        if (result < 0 or status_list == null) {
            return GitError.StatusFailed;
        }
        defer c.git_status_list_free(status_list);

        const count = c.git_status_list_entrycount(status_list);
        return count > 0;
    }
};

/// Initialize libgit2 (call once at startup)
pub fn init() !void {
    _ = try c_api.init();
}

/// Shutdown libgit2 (call once at shutdown)
pub fn shutdown() void {
    c_api.shutdown() catch {};
}

/// Get libgit2 version string
pub fn getVersionString(allocator: std.mem.Allocator) ![]const u8 {
    const v = c_api.getVersion();
    return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ v.major, v.minor, v.rev });
}

// ============================================================================
// Tests
// ============================================================================

test "git init and version" {
    try init();
    defer shutdown();

    const allocator = std.testing.allocator;
    const version = try getVersionString(allocator);
    defer allocator.free(version);

    std.debug.print("\nlibgit2 version: {s}\n", .{version});
    try std.testing.expect(version.len > 0);
}

test "discover repository" {
    try init();
    defer shutdown();

    const allocator = std.testing.allocator;

    // Try to discover repo from current directory (vimcraft is a git repo)
    if (Repository.discover(allocator, ".")) |discovered| {
        var repo = discovered;
        defer repo.deinit();

        std.debug.print("\nFound repository at: {s}\n", .{repo.getPath() orelse "unknown"});

        if (repo.getCurrentBranch(allocator)) |branch| {
            defer allocator.free(branch);
            std.debug.print("Current branch: {s}\n", .{branch});
        } else |_| {}

        if (repo.getHeadShort(allocator)) |head| {
            defer allocator.free(head);
            std.debug.print("HEAD: {s}\n", .{head});
        } else |_| {}

        const dirty = repo.isDirty() catch false;
        std.debug.print("Dirty: {}\n", .{dirty});
    } else |_| {
        std.debug.print("\nNo git repository found (expected in some test environments)\n", .{});
    }
}
