/// File System API for JavaScript plugins
/// Provides Node.js-style file operations
const std = @import("std");
const c = @import("c_api.zig").c;

/// Context passed to all fs functions
pub const FsContext = struct {
    allocator: std.mem.Allocator,
};

// ============================================================================
// Host Object Getter
// ============================================================================

pub export fn fsHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "readTextFile", readTextFile },
        .{ "readFile", readFile },
        .{ "writeFile", writeFile },
        .{ "exists", exists },
        .{ "stat", stat },
        .{ "readDir", readDir },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

// ============================================================================
// File System Functions
// ============================================================================

/// fs.readTextFile(path) -> string
fn readTextFile(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "fs.readTextFile requires a path argument");
        return null;
    }

    const ctx: *FsContext = @ptrCast(@alignCast(context));
    const path_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid path argument");
        return null;
    };

    // Get path string
    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, path_val, &path_len);
    if (path_ptr == null or path_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get path string");
        return null;
    }
    const path = path_ptr[0..path_len];

    // Expand ~ to home directory
    const expanded_path = expandPath(ctx.allocator, path) catch {
        c.hermes_throw_error(runtime, "Failed to expand path");
        return null;
    };
    defer ctx.allocator.free(expanded_path);

    // Read file
    const file = std.fs.openFileAbsolute(expanded_path, .{}) catch {
        c.hermes_throw_error(runtime, "Failed to open file");
        return null;
    };
    defer file.close();

    const content = file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch {
        c.hermes_throw_error(runtime, "Failed to read file");
        return null;
    };
    defer ctx.allocator.free(content);

    return c.hermes_value_create_string(runtime, content.ptr, content.len);
}

/// fs.readFile(path) -> ArrayBuffer
fn readFile(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "fs.readFile requires a path argument");
        return null;
    }

    const ctx: *FsContext = @ptrCast(@alignCast(context));
    const path_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid path argument");
        return null;
    };

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, path_val, &path_len);
    if (path_ptr == null or path_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get path string");
        return null;
    }
    const path = path_ptr[0..path_len];

    const expanded_path = expandPath(ctx.allocator, path) catch {
        c.hermes_throw_error(runtime, "Failed to expand path");
        return null;
    };
    defer ctx.allocator.free(expanded_path);

    const file = std.fs.openFileAbsolute(expanded_path, .{}) catch {
        c.hermes_throw_error(runtime, "Failed to open file");
        return null;
    };
    defer file.close();

    const content = file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch {
        c.hermes_throw_error(runtime, "Failed to read file");
        return null;
    };
    // Note: content is NOT freed here - ownership transfers to ArrayBuffer finalizer

    // Create External ArrayBuffer with finalizer to free memory
    return c.hermes_value_create_arraybuffer_external(
        runtime,
        @ptrCast(content.ptr),
        content.len,
        arrayBufferFinalizer,
        @ptrCast(ctx),
    );
}

fn arrayBufferFinalizer(data: ?*anyopaque, context: ?*anyopaque) callconv(.c) void {
    _ = context;
    _ = data;
    // Note: We can't easily free this because we don't have the allocator or slice length
    // For now, this leaks memory. TODO: Use a more sophisticated approach with stored metadata
}

/// fs.writeFile(path, data) -> undefined
fn writeFile(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "fs.writeFile requires path and data arguments");
        return null;
    }

    const ctx: *FsContext = @ptrCast(@alignCast(context));
    const path_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid path argument");
        return null;
    };
    const data_val = args[1] orelse {
        c.hermes_throw_error(runtime, "Invalid data argument");
        return null;
    };

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, path_val, &path_len);
    if (path_ptr == null or path_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get path string");
        return null;
    }
    const path = path_ptr[0..path_len];

    const expanded_path = expandPath(ctx.allocator, path) catch {
        c.hermes_throw_error(runtime, "Failed to expand path");
        return null;
    };
    defer ctx.allocator.free(expanded_path);

    // Get data - either string or ArrayBuffer
    var data: []const u8 = undefined;

    if (c.hermes_value_is_string(data_val)) {
        var data_len: usize = 0;
        const data_ptr = c.hermes_value_get_string(runtime, data_val, &data_len);
        if (data_ptr == null) {
            c.hermes_throw_error(runtime, "Failed to get data string");
            return null;
        }
        data = data_ptr[0..data_len];
    } else {
        // Try ArrayBuffer
        var ab_data: ?*anyopaque = null;
        var ab_len: usize = 0;
        if (!c.hermes_value_get_arraybuffer_data(runtime, data_val, &ab_data, &ab_len)) {
            c.hermes_throw_error(runtime, "Data must be string or ArrayBuffer");
            return null;
        }
        data = @as([*]const u8, @ptrCast(ab_data.?))[0..ab_len];
    }

    // Write file
    const file = std.fs.createFileAbsolute(expanded_path, .{}) catch {
        c.hermes_throw_error(runtime, "Failed to create file");
        return null;
    };
    defer file.close();

    file.writeAll(data) catch {
        c.hermes_throw_error(runtime, "Failed to write file");
        return null;
    };

    return c.hermes_value_create_undefined(runtime);
}

/// fs.exists(path) -> boolean
fn exists(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "fs.exists requires a path argument");
        return null;
    }

    const ctx: *FsContext = @ptrCast(@alignCast(context));
    const path_val = args[0] orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, path_val, &path_len);
    if (path_ptr == null or path_len == 0) {
        return c.hermes_value_create_boolean(runtime, false);
    }
    const path = path_ptr[0..path_len];

    const expanded_path = expandPath(ctx.allocator, path) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };
    defer ctx.allocator.free(expanded_path);

    const file_exists = blk: {
        std.fs.accessAbsolute(expanded_path, .{}) catch break :blk false;
        break :blk true;
    };

    return c.hermes_value_create_boolean(runtime, file_exists);
}

/// fs.stat(path) -> {size, mtime, isDirectory, isFile}
fn stat(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "fs.stat requires a path argument");
        return null;
    }

    const ctx: *FsContext = @ptrCast(@alignCast(context));
    const path_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid path argument");
        return null;
    };

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, path_val, &path_len);
    if (path_ptr == null or path_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get path string");
        return null;
    }
    const path = path_ptr[0..path_len];

    const expanded_path = expandPath(ctx.allocator, path) catch {
        c.hermes_throw_error(runtime, "Failed to expand path");
        return null;
    };
    defer ctx.allocator.free(expanded_path);

    const stat_result = std.fs.cwd().statFile(expanded_path) catch {
        c.hermes_throw_error(runtime, "Failed to stat file");
        return null;
    };

    // Create result object
    const obj = c.hermes_value_create_object(runtime);
    if (obj == null) {
        c.hermes_throw_error(runtime, "Failed to create object");
        return null;
    }

    // size
    c.hermes_value_set_property(
        runtime,
        obj,
        "size",
        c.hermes_value_create_number(runtime, @floatFromInt(stat_result.size)),
    );

    // mtime (as milliseconds timestamp)
    const mtime_ns = stat_result.mtime;
    const mtime_ms: f64 = @floatFromInt(@divFloor(mtime_ns, std.time.ns_per_ms));
    c.hermes_value_set_property(
        runtime,
        obj,
        "mtime",
        c.hermes_value_create_number(runtime, mtime_ms),
    );

    // isDirectory
    c.hermes_value_set_property(
        runtime,
        obj,
        "isDirectory",
        c.hermes_value_create_boolean(runtime, stat_result.kind == .directory),
    );

    // isFile
    c.hermes_value_set_property(
        runtime,
        obj,
        "isFile",
        c.hermes_value_create_boolean(runtime, stat_result.kind == .file),
    );

    return obj;
}

/// fs.readDir(path) -> string[]
fn readDir(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "fs.readDir requires a path argument");
        return null;
    }

    const ctx: *FsContext = @ptrCast(@alignCast(context));
    const path_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid path argument");
        return null;
    };

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, path_val, &path_len);
    if (path_ptr == null or path_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get path string");
        return null;
    }
    const path = path_ptr[0..path_len];

    const expanded_path = expandPath(ctx.allocator, path) catch {
        c.hermes_throw_error(runtime, "Failed to expand path");
        return null;
    };
    defer ctx.allocator.free(expanded_path);

    var dir = std.fs.openDirAbsolute(expanded_path, .{ .iterate = true }) catch {
        c.hermes_throw_error(runtime, "Failed to open directory");
        return null;
    };
    defer dir.close();

    // Create array
    const arr = c.hermes_array_create(runtime, 0);
    if (arr == null) {
        c.hermes_throw_error(runtime, "Failed to create array");
        return null;
    }

    var index: usize = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const name_str = c.hermes_value_create_string(runtime, entry.name.ptr, entry.name.len);
        c.hermes_array_set(runtime, arr, index, name_str);
        c.hermes_value_destroy(name_str);
        index += 1;
    }

    return arr;
}

// ============================================================================
// Helper Functions
// ============================================================================

fn expandPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (path.len == 0) return error.EmptyPath;

    if (path[0] == '~') {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
        const expanded = try allocator.alloc(u8, home.len + path.len - 1);
        @memcpy(expanded[0..home.len], home);
        @memcpy(expanded[home.len..], path[1..]);
        return expanded;
    }

    // Make relative paths absolute
    if (path[0] != '/') {
        var cwd_buf: [4096]u8 = undefined;
        const cwd = std.posix.getcwd(&cwd_buf) catch return error.GetCwdFailed;
        const expanded = try allocator.alloc(u8, cwd.len + 1 + path.len);
        @memcpy(expanded[0..cwd.len], cwd);
        expanded[cwd.len] = '/';
        @memcpy(expanded[cwd.len + 1 ..], path);
        return expanded;
    }

    // Path is already absolute - duplicate it so we have a proper allocation
    // (the original path from JS string might not be properly managed)
    return try allocator.dupe(u8, path);
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, context: *FsContext) void {
    c.hermes_register_host_object(
        runtime,
        "__fs",
        fsHostObjectGet,
        null, // No setter
        null, // No enumerator
        @ptrCast(context),
    );
}
