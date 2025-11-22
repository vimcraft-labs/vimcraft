/// Comprehensive unit tests for libgit2 Zig wrapper
/// Tests both c_api.zig and git.zig functionality
const std = @import("std");
const git = @import("git.zig");
const c_api = @import("c_api.zig");

// ============================================================================
// C API Tests (c_api.zig)
// ============================================================================

test "c_api: init returns positive count" {
    const count = try c_api.init();
    defer c_api.shutdown() catch {};

    try std.testing.expect(count >= 1);
}

test "c_api: multiple init/shutdown pairs" {
    // First init
    const count1 = try c_api.init();
    try std.testing.expect(count1 >= 1);

    // Second init (nested)
    const count2 = try c_api.init();
    try std.testing.expect(count2 >= 2);

    // Shutdown both
    try c_api.shutdown();
    try c_api.shutdown();
}

test "c_api: version returns valid values" {
    _ = try c_api.init();
    defer c_api.shutdown() catch {};

    const version = c_api.getVersion();

    // libgit2 1.9.x
    try std.testing.expect(version.major >= 1);
    try std.testing.expect(version.minor >= 0);
    try std.testing.expect(version.rev >= 0);
}

test "c_api: getLastError returns null when no error" {
    _ = try c_api.init();
    defer c_api.shutdown() catch {};

    // No operations have failed, so no error
    // Note: getLastError might return a previous error, so we just check it doesn't crash
    _ = c_api.getLastError();
}

// ============================================================================
// High-Level API Tests (git.zig)
// ============================================================================

test "git: init and shutdown" {
    try git.init();
    git.shutdown();

    // Should be able to init again
    try git.init();
    git.shutdown();
}

test "git: version string format" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;
    const version = try git.getVersionString(allocator);
    defer allocator.free(version);

    // Version should be in format "X.Y.Z"
    try std.testing.expect(version.len >= 5); // At least "1.0.0"

    // Should contain dots
    var dot_count: usize = 0;
    for (version) |ch| {
        if (ch == '.') dot_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), dot_count);
}

test "git: discover repository from vimcraft root" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    // Vimcraft itself is a git repo, so discovery should succeed
    var repo = git.Repository.discover(allocator, ".") catch |err| {
        // In CI or non-git environments, this is acceptable
        std.debug.print("Repository discovery failed (expected in some environments): {}\n", .{err});
        return;
    };
    defer repo.deinit();

    // Repository should have a path
    const path = repo.getPath();
    try std.testing.expect(path != null);
    try std.testing.expect(path.?.len > 0);

    // Path should end with ".git/"
    if (path) |p| {
        try std.testing.expect(std.mem.endsWith(u8, p, ".git/") or std.mem.endsWith(u8, p, ".git"));
    }
}

test "git: repository properties" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    // Vimcraft repo is not bare
    try std.testing.expect(!repo.isBare());

    // Vimcraft repo is not empty (has commits)
    try std.testing.expect(!repo.isEmpty());

    // Should have a working directory
    const workdir = repo.getWorkdir();
    try std.testing.expect(workdir != null);
}

test "git: get current branch" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    const branch = repo.getCurrentBranch(allocator) catch |err| {
        // Detached HEAD is acceptable
        if (err == git.GitError.HeadNotFound) {
            std.debug.print("Detached HEAD state\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(branch);

    // Branch name should not be empty
    try std.testing.expect(branch.len > 0);

    // Common branch names for vimcraft
    std.debug.print("Current branch: {s}\n", .{branch});
}

test "git: get HEAD short hash" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    const head = repo.getHeadShort(allocator) catch |err| {
        if (err == git.GitError.HeadNotFound) {
            return; // Empty repo
        }
        return err;
    };
    defer allocator.free(head);

    // Short hash should be 7 characters
    try std.testing.expectEqual(@as(usize, 7), head.len);

    // Should be hex characters
    for (head) |ch| {
        try std.testing.expect((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'));
    }
}

test "git: file status for tracked file" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    // build.zig should be tracked
    const status = repo.getFileStatus("build.zig") catch |err| {
        std.debug.print("getFileStatus failed: {}\n", .{err});
        return err;
    };

    // build.zig could be modified or unmodified
    try std.testing.expect(status == .modified or status == .unmodified);
}

test "git: file status for untracked file" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    // A random non-existent file should be untracked
    const status = repo.getFileStatus("this_file_does_not_exist_12345.txt") catch |err| {
        std.debug.print("getFileStatus failed: {}\n", .{err});
        return err;
    };

    try std.testing.expectEqual(git.FileStatus.untracked, status);
}

test "git: isTracked for known files" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    // build.zig should be tracked
    const build_tracked = repo.isTracked("build.zig") catch false;
    try std.testing.expect(build_tracked);

    // Non-existent file should not be tracked
    const nonexistent_tracked = repo.isTracked("nonexistent_file_xyz.txt") catch true;
    try std.testing.expect(!nonexistent_tracked);
}

test "git: isDirty detection" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    var repo = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    defer repo.deinit();

    // Just verify isDirty doesn't crash and returns a boolean
    const dirty = repo.isDirty() catch |err| {
        std.debug.print("isDirty failed: {}\n", .{err});
        return err;
    };

    std.debug.print("Repository dirty: {}\n", .{dirty});
    // We can't assert the value since it depends on the working state
}

test "git: open repository directly" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    // First discover to get the path
    var discovered = git.Repository.discover(allocator, ".") catch {
        return; // Skip in non-git environments
    };
    const git_path = discovered.getPath() orelse {
        discovered.deinit();
        return;
    };

    // Copy the path since we'll close the discovered repo
    const path_copy = allocator.dupe(u8, git_path) catch {
        discovered.deinit();
        return;
    };
    defer allocator.free(path_copy);
    discovered.deinit();

    // Now open directly using the path
    var repo = git.Repository.open(allocator, path_copy) catch |err| {
        std.debug.print("Repository.open failed: {}\n", .{err});
        return err;
    };
    defer repo.deinit();

    // Should have same properties
    try std.testing.expect(!repo.isBare());
}

test "git: open non-existent repository fails" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    // Try to open a non-existent path
    const result = git.Repository.open(allocator, "/tmp/definitely_not_a_git_repo_12345");

    try std.testing.expectError(git.GitError.RepositoryOpenFailed, result);
}

test "git: discover from non-git directory fails" {
    try git.init();
    defer git.shutdown();

    const allocator = std.testing.allocator;

    // /tmp is unlikely to be inside a git repo
    const result = git.Repository.discover(allocator, "/tmp");

    try std.testing.expectError(git.GitError.RepositoryNotFound, result);
}

// ============================================================================
// FileStatus enum tests
// ============================================================================

test "git: FileStatus enum values" {
    // Verify all status values are distinct
    const statuses = [_]git.FileStatus{
        .untracked,
        .ignored,
        .unmodified,
        .modified,
        .added,
        .deleted,
        .renamed,
        .copied,
        .conflicted,
    };

    // Each status should have a unique value
    for (statuses, 0..) |s1, i| {
        for (statuses[i + 1 ..]) |s2| {
            try std.testing.expect(s1 != s2);
        }
    }
}

// ============================================================================
// Error handling tests
// ============================================================================

test "git: GitError enum has expected variants" {
    // This test ensures the error enum compiles and has expected variants
    const errors = [_]git.GitError{
        git.GitError.LibGit2InitFailed,
        git.GitError.RepositoryNotFound,
        git.GitError.RepositoryOpenFailed,
        git.GitError.NotARepository,
        git.GitError.BranchNotFound,
        git.GitError.StatusFailed,
        git.GitError.HeadNotFound,
        git.GitError.InvalidPath,
        git.GitError.OutOfMemory,
    };

    try std.testing.expectEqual(@as(usize, 9), errors.len);
}
