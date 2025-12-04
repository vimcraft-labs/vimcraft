/// Git API Module
/// Exposes git operations to JavaScript plugins via vim.git.*
/// Uses libgit2 for native git operations (diff hunks, blame, etc.)
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const git = @import("../git/git.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context for git operations
const GitContext = struct {
    editor: *Editor,
    allocator: std.mem.Allocator,
};

/// Global context
var global_ctx: ?*GitContext = null;
/// Track if libgit2 was initialized
var git_initialized: bool = false;

// ============================================================================
// Host Object Implementation
// ============================================================================

/// Property getter for vim.git host object
pub export fn gitHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "getWorkTreeDiff", gitGetWorkTreeDiff },
        .{ "getFileStatus", gitGetFileStatus },
        .{ "getBranch", gitGetBranch },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

/// Enumerator for vim.git properties (for DevTools)
pub export fn gitHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const properties = [_][]const u8{
        "getWorkTreeDiff",
        "getFileStatus",
        "getBranch",
    };

    const arr = c.hermes_array_create(rt, properties.len) orelse return null;
    for (properties, 0..) |prop, i| {
        if (c.hermes_value_create_string(rt, prop.ptr, prop.len)) |str| {
            c.hermes_array_set(rt, arr, i, str);
        }
    }
    return arr;
}

// ============================================================================
// API Functions
// ============================================================================

/// vim.git.getWorkTreeDiff(filepath) -> Array<{startLine, lineCount, type}>
/// Get line-level diff hunks for a file compared to HEAD
pub export fn gitGetWorkTreeDiff(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Safety: Check context and libgit2 initialization
    if (context == null or !git_initialized) {
        return c.hermes_array_create(rt, 0);
    }

    const ctx: *GitContext = @ptrCast(@alignCast(context));

    if (count < 1) return c.hermes_array_create(rt, 0);

    const filepath_val = args[0] orelse return c.hermes_array_create(rt, 0);

    if (!c.hermes_value_is_string(filepath_val)) {
        return c.hermes_array_create(rt, 0);
    }

    var filepath_len: usize = 0;
    const filepath_ptr = c.hermes_value_get_string(rt, filepath_val, &filepath_len);
    if (filepath_ptr == null or filepath_len == 0) {
        return c.hermes_array_create(rt, 0);
    }

    const filepath = filepath_ptr[0..filepath_len];

    // Discover repository from file path
    const dir_path = std.fs.path.dirname(filepath) orelse ".";
    var repo = git.Repository.discover(ctx.allocator, dir_path) catch {
        return c.hermes_array_create(rt, 0);
    };
    defer repo.deinit();

    // Get relative path from repo root
    const workdir = repo.getWorkdir() orelse {
        return c.hermes_array_create(rt, 0);
    };

    // Make filepath relative to workdir
    const relative_path = if (std.mem.startsWith(u8, filepath, workdir))
        filepath[workdir.len..]
    else
        filepath;

    // Get diff hunks
    var diff_result = git.getWorkTreeDiff(&repo, relative_path, ctx.allocator) catch {
        return c.hermes_array_create(rt, 0);
    };
    defer diff_result.deinit();

    // Create result array
    const result = c.hermes_array_create(rt, diff_result.hunks.len) orelse return null;

    for (diff_result.hunks, 0..) |hunk, i| {
        // Create hunk object
        const hunk_obj = c.hermes_value_create_object(rt) orelse continue;

        // Set startLine
        c.hermes_value_set_property(rt, hunk_obj, "startLine", c.hermes_value_create_number(rt, @floatFromInt(hunk.start_line)));

        // Set lineCount
        c.hermes_value_set_property(rt, hunk_obj, "lineCount", c.hermes_value_create_number(rt, @floatFromInt(hunk.line_count)));

        // Set type
        const type_str: []const u8 = switch (hunk.hunk_type) {
            .add => "add",
            .delete => "delete",
            .change => "change",
        };
        if (c.hermes_value_create_string(rt, type_str.ptr, type_str.len)) |type_val| {
            c.hermes_value_set_property(rt, hunk_obj, "type", type_val);
        }

        c.hermes_array_set(rt, result, i, hunk_obj);
    }

    return result;
}

/// vim.git.getFileStatus(filepath) -> string
/// Get file status: 'untracked', 'modified', 'added', 'deleted', etc.
pub export fn gitGetFileStatus(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    // Safety: Check context and libgit2 initialization
    if (context == null or !git_initialized) {
        return c.hermes_value_create_null(rt);
    }

    const ctx: *GitContext = @ptrCast(@alignCast(context));

    if (count < 1) return c.hermes_value_create_null(rt);

    const filepath_val = args[0] orelse return c.hermes_value_create_null(rt);

    if (!c.hermes_value_is_string(filepath_val)) {
        return c.hermes_value_create_null(rt);
    }

    var filepath_len: usize = 0;
    const filepath_ptr = c.hermes_value_get_string(rt, filepath_val, &filepath_len);
    if (filepath_ptr == null or filepath_len == 0) {
        return c.hermes_value_create_null(rt);
    }

    const filepath = filepath_ptr[0..filepath_len];

    // Discover repository
    const dir_path = std.fs.path.dirname(filepath) orelse ".";
    var repo = git.Repository.discover(ctx.allocator, dir_path) catch {
        return c.hermes_value_create_null(rt);
    };
    defer repo.deinit();

    // Get relative path
    const workdir = repo.getWorkdir() orelse {
        return c.hermes_value_create_null(rt);
    };

    const relative_path = if (std.mem.startsWith(u8, filepath, workdir))
        filepath[workdir.len..]
    else
        filepath;

    // Get file status
    const status = repo.getFileStatus(relative_path) catch {
        return c.hermes_value_create_null(rt);
    };

    const status_str: []const u8 = switch (status) {
        .untracked => "untracked",
        .ignored => "ignored",
        .unmodified => "unmodified",
        .modified => "modified",
        .added => "added",
        .deleted => "deleted",
        .renamed => "renamed",
        .copied => "copied",
        .conflicted => "conflicted",
    };

    return c.hermes_value_create_string(rt, status_str.ptr, status_str.len);
}

/// vim.git.getBranch() -> string | null
/// Get current branch name
pub export fn gitGetBranch(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;

    // Safety: Check context and libgit2 initialization
    if (context == null or !git_initialized) {
        return c.hermes_value_create_null(rt);
    }

    const ctx: *GitContext = @ptrCast(@alignCast(context));

    // Get current buffer's filepath to find repo
    const buffer = ctx.editor.getCurrentBuffer() orelse return c.hermes_value_create_null(rt);
    const filepath = buffer.filepath orelse return c.hermes_value_create_null(rt);

    const dir_path = std.fs.path.dirname(filepath) orelse ".";
    var repo = git.Repository.discover(ctx.allocator, dir_path) catch {
        return c.hermes_value_create_null(rt);
    };
    defer repo.deinit();

    const branch = repo.getCurrentBranch(ctx.allocator) catch {
        return c.hermes_value_create_null(rt);
    };
    defer ctx.allocator.free(branch);

    return c.hermes_value_create_string(rt, branch.ptr, branch.len);
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, editor: *Editor, allocator: std.mem.Allocator) void {
    // Initialize libgit2 (safe to call multiple times)
    git.init() catch {
        // Failed to initialize libgit2 - git API won't work but don't crash
        return;
    };
    git_initialized = true;

    const ctx = allocator.create(GitContext) catch return;
    ctx.* = .{
        .editor = editor,
        .allocator = allocator,
    };
    global_ctx = ctx;

    // Register vim.git as a host object
    c.hermes_register_host_object(
        runtime,
        "vimGit",
        gitHostObjectGet,
        null, // No setter (read-only methods)
        gitHostObjectEnumerator,
        @ptrCast(ctx),
    );
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
    if (git_initialized) {
        git.shutdown();
        git_initialized = false;
    }
}
