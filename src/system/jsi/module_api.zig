/// Module API - CommonJS require() implementation
/// Supports relative paths, absolute paths, and plugin name resolution
/// Compatible with future TypeScript transpilation (Phase 5+)
const std = @import("std");
const config_api = @import("config_api.zig");
const helpers = @import("helpers.zig");
const jsi_api = @import("jsi_api.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Validate that a resolved path is within allowed boundaries
/// Prevents path traversal attacks (e.g., require('../../../../etc/passwd'))
/// Also resolves symlinks to prevent symlink-based directory traversal
fn validateResolvedPath(resolved_path: []const u8, allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

    // Allowed root directories for module loading
    const allowed_roots = [_][]const u8{
        try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "vimcraft" }),
        try std.fs.path.join(allocator, &[_][]const u8{ home, ".local", "share", "vimcraft" }),
        "/tmp/", // Allow /tmp for testing
    };
    defer {
        allocator.free(allowed_roots[0]);
        allocator.free(allowed_roots[1]);
    }

    // Resolve symlinks to prevent symlink-based bypass
    // e.g., ~/.config/vimcraft/plugins/malicious.js -> /etc/passwd
    const real_path = std.fs.realpathAlloc(allocator, resolved_path) catch resolved_path;
    defer if (real_path.ptr != resolved_path.ptr) allocator.free(real_path);

    // Check if real path (after resolving symlinks) starts with any allowed root
    var is_safe = false;
    for (allowed_roots) |root| {
        if (std.mem.startsWith(u8, real_path, root)) {
            is_safe = true;
            break;
        }
    }

    if (!is_safe) {
        return error.PathTraversalAttempt;
    }
}

/// Resolve module path to absolute path
/// Supports 3 modes:
/// 1. Relative: ./utils.js, ../shared.js (relative to current_file)
/// 2. Absolute: /abs/path.js (only within allowed directories)
/// 3. Plugin name: telescope → ~/.config/vimcraft/plugins/telescope.js
///
/// Security: All resolved paths are validated to prevent directory traversal
fn resolveModulePath(
    allocator: std.mem.Allocator,
    path: []const u8,
    current_file: ?[]const u8,
) ![]const u8 {
    // Mode 1: Absolute path (starts with /)
    if (path.len > 0 and path[0] == '/') {
        const abs_path = try allocator.dupe(u8, path);
        errdefer allocator.free(abs_path);

        // Validate path is within allowed directories
        try validateResolvedPath(abs_path, allocator);

        return abs_path;
    }

    // Mode 2: Relative path (starts with ./ or ../)
    if (std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../")) {
        // Need current file context for relative resolution
        const base_dir = if (current_file) |file|
            std.fs.path.dirname(file) orelse "."
        else blk: {
            // No current file context - use config directory
            const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "vimcraft" });
        };
        defer if (current_file == null) allocator.free(base_dir);

        // Resolve relative path
        const resolved = try std.fs.path.resolve(allocator, &[_][]const u8{ base_dir, path });
        errdefer allocator.free(resolved);

        // Validate resolved path to prevent directory traversal
        try validateResolvedPath(resolved, allocator);

        return resolved;
    }

    // Mode 3: Plugin name (search plugin directories)
    const search_paths = [_][]const u8{
        "~/.config/vimcraft/plugins",
        "~/.local/share/vimcraft/plugins",
    };

    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

    for (search_paths) |search_path_template| {
        // Expand ~ to home directory
        const search_path = if (std.mem.startsWith(u8, search_path_template, "~/")) blk: {
            const rest = search_path_template[2..];
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ home, rest });
        } else search_path_template;
        defer if (!std.mem.eql(u8, search_path, search_path_template)) allocator.free(search_path);

        // Try 1: plugin_name.js (single file)
        const direct_path = try std.fs.path.join(allocator, &[_][]const u8{ search_path, path });
        defer allocator.free(direct_path);

        // Add .js extension if not present
        const with_ext = if (!std.mem.endsWith(u8, direct_path, ".js"))
            try std.fmt.allocPrint(allocator, "{s}.js", .{direct_path})
        else
            try allocator.dupe(u8, direct_path);
        defer allocator.free(with_ext);

        std.fs.accessAbsolute(with_ext, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Try 2: plugin_name/init.js (directory)
                const init_path = try std.fs.path.join(allocator, &[_][]const u8{ search_path, path, "init.js" });
                std.fs.accessAbsolute(init_path, .{}) catch |init_err| switch (init_err) {
                    error.FileNotFound => {
                        allocator.free(init_path);
                        continue; // Try next search path
                    },
                    else => {
                        allocator.free(init_path);
                        return init_err;
                    },
                };

                // Validate path (defense-in-depth, should already be safe)
                errdefer allocator.free(init_path);
                try validateResolvedPath(init_path, allocator);

                return init_path; // Found init.js
            },
            else => return err,
        };

        // Validate path (defense-in-depth, should already be safe)
        const final_path = try allocator.dupe(u8, with_ext);
        errdefer allocator.free(final_path);
        try validateResolvedPath(final_path, allocator);

        return final_path; // Found direct file
    }

    // Not found in any search path
    return error.ModuleNotFound;
}

/// Load and execute a JavaScript module
/// Sets up module/exports globals, executes file, returns module.exports
fn executeModule(
    allocator: std.mem.Allocator,
    runtime: *c.OVHermesRuntime,
    abs_path: []const u8,
    ctx: *config_api.ConfigContext,
) !*c.OVHermesValue {
    // Create module object: { exports: {} }
    const module_obj = c.hermes_value_create_object(runtime) orelse return error.CreateObjectFailed;
    errdefer c.hermes_value_destroy(module_obj);

    // Create exports object (initially empty)
    const exports_obj = c.hermes_value_create_object(runtime) orelse {
        c.hermes_value_destroy(module_obj);
        return error.CreateObjectFailed;
    };
    errdefer c.hermes_value_destroy(exports_obj);

    // Set module.exports = exports
    c.hermes_value_set_property(runtime, module_obj, "exports", exports_obj);

    // Set globals: module and exports
    const global_obj = c.hermes_get_global_object(runtime);
    defer c.hermes_object_destroy(global_obj);

    c.hermes_object_set_property(runtime, global_obj, "module", module_obj);
    c.hermes_object_set_property(runtime, global_obj, "exports", exports_obj);

    // Save previous current_file_path and set new one
    const prev_file_path = ctx.current_file_path;
    ctx.current_file_path = abs_path;
    defer ctx.current_file_path = prev_file_path;

    // Execute the file using jsi_api.loadPlugin (directory-based mtime tracking for cache invalidation)
    jsi_api.loadPlugin(runtime, abs_path, allocator) catch |err| {
        c.hermes_value_destroy(module_obj);
        c.hermes_value_destroy(exports_obj);
        return err;
    };

    // Get final module.exports (may have been reassigned)
    const final_exports = c.hermes_value_get_property(runtime, module_obj, "exports") orelse exports_obj;

    // Clean up temporary objects (keep final_exports)
    c.hermes_value_destroy(module_obj);
    if (final_exports != exports_obj) {
        c.hermes_value_destroy(exports_obj);
    }

    return final_exports;
}

/// Zig host function: require(path)
/// CommonJS module loading with caching and circular dependency detection
/// Supports relative paths (./file.js), absolute paths (/abs/path.js),
/// and plugin names (telescope → ~/.config/vimcraft/plugins/telescope.js)
pub export fn hermesRequire(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*config_api.ConfigContext, @ptrCast(@alignCast(context.?)));

    // Arg 0: module path (string)
    if (arg_count < 1) {
        c.hermes_throw_type_error(runtime, "require() expects 1 argument (module path)");
        return null;
    }

    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        c.hermes_throw_type_error(runtime, "require() expects string argument");
        return null;
    }

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(runtime, args[0], &path_len);
    if (path_ptr == null) {
        c.hermes_throw_error(runtime, "Failed to extract string from argument");
        return null;
    }

    // Validate input: reject empty strings
    if (path_len == 0) {
        c.hermes_throw_error(runtime, "require() path cannot be empty");
        return null;
    }

    // CRITICAL FIX #7: Check length BEFORE allocating buffer
    // Previous code had logic error: checked length but still used buffer
    if (path_len >= 2048) {
        c.hermes_throw_error(runtime, "Module path too long (max 2048 characters)");
        return null;
    }

    // Copy path to avoid shared buffer corruption
    // Use 2048 bytes to support macOS PATH_MAX (1024) with .js extension
    var path_buf: [2048]u8 = undefined;
    @memcpy(path_buf[0..path_len], path_ptr[0..path_len]);
    const path = path_buf[0..path_len];

    // Validate input: reject null bytes (security - prevents null byte injection)
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        c.hermes_throw_error(runtime, "require() path contains null byte (security violation)");
        return null;
    }

    // Resolve to absolute path
    const abs_path = resolveModulePath(ctx.allocator, path, ctx.current_file_path) catch |err| {
        // Build helpful error message with search paths
        var error_msg_buf: [1024]u8 = undefined;
        const error_msg = switch (err) {
            error.ModuleNotFound => std.fmt.bufPrint(&error_msg_buf,
                \\Module not found: '{s}'
                \\Search paths:
                \\  - ~/.config/vimcraft/plugins/{s}.js
                \\  - ~/.config/vimcraft/plugins/{s}/init.js
                \\  - ~/.local/share/vimcraft/plugins/{s}.js
                \\  - ~/.local/share/vimcraft/plugins/{s}/init.js
            , .{ path, path, path, path, path }) catch "Module not found",

            error.PathTraversalAttempt => std.fmt.bufPrint(&error_msg_buf,
                "Security violation: require() path '{s}' attempts directory traversal"
            , .{path}) catch "Path traversal attempt",

            else => std.fmt.bufPrint(&error_msg_buf,
                "Failed to resolve module path: {s}"
            , .{@errorName(err)}) catch "Module resolution failed",
        };

        c.hermes_throw_error(runtime, error_msg.ptr);
        return null;
    };
    defer ctx.allocator.free(abs_path);

    // Check cache (using absolute path as key)
    if (ctx.module_cache.get(abs_path)) |entry| {
        if (entry.loading) {
            // Circular dependency detected!
            var error_msg_buf: [512]u8 = undefined;
            const error_msg = std.fmt.bufPrint(&error_msg_buf,
                "Circular dependency detected when loading module '{s}'"
            , .{abs_path}) catch "Circular dependency detected";

            c.hermes_throw_error(runtime, error_msg.ptr);
            return null;
        }

        // Return cached exports
        return entry.exports;
    }

    // Mark as loading (circular dependency detection)
    // CRITICAL FIX: Initialize exports with safe placeholder (prevents undefined behavior)
    const loading_entry = config_api.ModuleEntry{
        .exports = c.hermes_value_create_undefined(runtime) orelse {
            c.hermes_throw_error(runtime, "Failed to create placeholder for module loading");
            return null;
        },
        .loading = true,
    };

    // Add to cache (using owned copy of abs_path)
    const cache_key = ctx.allocator.dupe(u8, abs_path) catch {
        c.hermes_throw_error(runtime, "Out of memory: failed to allocate module cache key");
        return null;
    };
    errdefer ctx.allocator.free(cache_key);

    ctx.module_cache.put(cache_key, loading_entry) catch {
        ctx.allocator.free(cache_key);
        c.hermes_throw_error(runtime, "Out of memory: failed to add module to cache");
        return null;
    };

    // Execute module
    const exports = executeModule(ctx.allocator, runtime, abs_path, ctx) catch |err| {
        // Execution failed - remove from cache and cleanup
        // CRITICAL FIX: Destroy placeholder value before removing
        if (ctx.module_cache.fetchRemove(cache_key)) |removed| {
            c.hermes_value_destroy(removed.value.exports);
        }
        ctx.allocator.free(cache_key);

        // Build error message
        var error_msg_buf: [512]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&error_msg_buf,
            "Failed to execute module '{s}': {s}"
        , .{ abs_path, @errorName(err) }) catch "Module execution failed";

        c.hermes_throw_error(runtime, error_msg.ptr);
        return null;
    };

    // Update cache entry with final exports
    // CRITICAL FIX: Destroy placeholder value before replacing
    if (ctx.module_cache.get(cache_key)) |old_entry| {
        c.hermes_value_destroy(old_entry.exports);
    }

    const final_entry = config_api.ModuleEntry{
        .exports = exports,
        .loading = false,
    };

    ctx.module_cache.put(cache_key, final_entry) catch {
        c.hermes_value_destroy(exports);
        ctx.allocator.free(cache_key);
        c.hermes_throw_error(runtime, "Out of memory: failed to update module cache");
        return null;
    };

    return exports;
}

/// Register require() as global function
pub fn register(runtime: *c.OVHermesRuntime, ctx: *config_api.ConfigContext) void {
    c.hermes_register_host_function(
        runtime,
        "require",
        hermesRequire,
        @ptrCast(ctx),
    );
}
