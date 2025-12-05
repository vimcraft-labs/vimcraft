/// vim.ai.mem - Memory Block System for AI Context
///
/// THE DIFFERENTIATOR: Dynamic memory blocks with temperature-based context budget.
/// Inspired by MemGPT's working memory concept.
///
/// API:
///   vim.ai.mem.get(name) -> {content, temperature, tokens, source} | null
///   vim.ai.mem.set(name, content, options?) -> boolean
///   vim.ai.mem.append(name, content) -> boolean
///   vim.ai.mem.delete(name) -> boolean
///   vim.ai.mem.list() -> string[]
///
///   vim.ai.mem.temperature(name) -> number | null
///   vim.ai.mem.setTemperature(name, temp) -> boolean
///
///   vim.ai.mem.loadFile(name, path) -> boolean  // AI.md support
///   vim.ai.mem.refresh(name) -> boolean
///
///   vim.ai.mem.tokens(name?) -> number  // null = total all blocks
///   vim.ai.mem.budget() -> number
///   vim.ai.mem.setBudget(tokens) -> boolean
///   vim.ai.mem.buildContext() -> string  // JSON array of blocks
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const c_api = @import("c_api.zig");
const c = c_api.c;

const mem = @import("../ai/mem.zig");

/// Context for AI memory API
pub const AiMemApiContext = struct {
    allocator: Allocator,
    memory: ?*mem.Memory = null,
    last_error: ?[]const u8 = null,

    /// Get or lazily initialize memory
    pub fn getOrInitMemory(self: *AiMemApiContext) !*mem.Memory {
        if (self.memory) |m| return m;

        // Get storage path with proper precedence:
        // 1. VIMCRAFT_AI_PATH (explicit override)
        // 2. XDG_CONFIG_HOME/vimcraft/ai (XDG standard)
        // 3. HOME/.config/vimcraft/ai (fallback)
        const base_path = if (std.posix.getenv("VIMCRAFT_AI_PATH")) |p|
            try self.allocator.dupe(u8, p)
        else if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg|
            try std.fs.path.join(self.allocator, &.{ xdg, "vimcraft", "ai" })
        else if (std.posix.getenv("HOME")) |home|
            try std.fs.path.join(self.allocator, &.{ home, ".config", "vimcraft", "ai" })
        else
            return error.NoConfigPath;
        defer self.allocator.free(base_path);

        const memory_ptr = try self.allocator.create(mem.Memory);
        errdefer self.allocator.destroy(memory_ptr);

        memory_ptr.* = try mem.Memory.init(self.allocator, base_path);

        self.memory = memory_ptr;
        return memory_ptr;
    }

    /// Set the last error message (clears previous)
    pub fn setError(self: *AiMemApiContext, msg: []const u8) void {
        self.clearError();
        self.last_error = self.allocator.dupe(u8, msg) catch null;
    }

    /// Set error from Zig error code
    pub fn setErrorFromCode(self: *AiMemApiContext, err: anyerror) void {
        self.setError(@errorName(err));
    }

    /// Clear any stored error
    pub fn clearError(self: *AiMemApiContext) void {
        if (self.last_error) |old| {
            self.allocator.free(old);
            self.last_error = null;
        }
    }
};

pub var global_ctx: ?*AiMemApiContext = null;

/// Get context from JSI callback
fn getContext(context: ?*anyopaque) ?*AiMemApiContext {
    const ctx_ptr = context orelse return null;
    return @ptrCast(@alignCast(ctx_ptr));
}

// ============================================================================
// vim.ai.mem.get(name) -> {content, temperature, tokens, source} | null
// ============================================================================

fn memGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    if (count < 1) return null;

    // Get name argument
    const name_arg = args[0] orelse return null;
    if (!c.hermes_value_is_string(name_arg)) return null;

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return null;

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    const block = memory.get(name_ptr[0..name_len]) catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    defer {
        var mut_block = block;
        mut_block.deinit();
    }

    // Create result object with content, temperature, tokens, source
    const obj = c.hermes_value_create_object(rt);
    if (obj == null) return null;

    // Add content
    const content_val = c.hermes_value_create_string(rt, block.content.ptr, block.content.len);
    c.hermes_value_set_property(rt, obj, "content", content_val);

    // Add temperature
    const temp_val = c.hermes_value_create_number(rt, @floatCast(block.temperature));
    c.hermes_value_set_property(rt, obj, "temperature", temp_val);

    // Add tokens
    const tokens_val = c.hermes_value_create_number(rt, @floatFromInt(block.tokens));
    c.hermes_value_set_property(rt, obj, "tokens", tokens_val);

    // Add source
    const source_str = switch (block.source) {
        .manual => "manual",
        .learned => "learned",
        .file => "file",
        .auto => "auto",
    };
    const source_val = c.hermes_value_create_string(rt, source_str.ptr, source_str.len);
    c.hermes_value_set_property(rt, obj, "source", source_val);

    return obj;
}

// ============================================================================
// vim.ai.mem.set(name, content, options?) -> boolean
// ============================================================================

fn memSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 2) return c.hermes_value_create_boolean(runtime, false);

    // Get name argument
    const name_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(name_arg)) return c.hermes_value_create_boolean(runtime, false);

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Get content argument
    const content_arg = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(content_arg)) return c.hermes_value_create_boolean(runtime, false);

    var content_len: usize = 0;
    const content_ptr = c.hermes_value_get_string(rt, content_arg, &content_len);
    if (content_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Copy strings since Hermes uses shared buffer
    const name = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return c.hermes_value_create_boolean(runtime, false);
    defer ctx.allocator.free(name);

    const content = ctx.allocator.dupe(u8, content_ptr[0..content_len]) catch return c.hermes_value_create_boolean(runtime, false);
    defer ctx.allocator.free(content);

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.set(name, content) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.append(name, content) -> boolean
// ============================================================================

fn memAppend(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 2) return c.hermes_value_create_boolean(runtime, false);

    // Get name argument
    const name_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(name_arg)) return c.hermes_value_create_boolean(runtime, false);

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Get content argument
    const content_arg = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(content_arg)) return c.hermes_value_create_boolean(runtime, false);

    var content_len: usize = 0;
    const content_ptr = c.hermes_value_get_string(rt, content_arg, &content_len);
    if (content_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Copy strings since Hermes uses shared buffer
    const name = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return c.hermes_value_create_boolean(runtime, false);
    defer ctx.allocator.free(name);

    const content = ctx.allocator.dupe(u8, content_ptr[0..content_len]) catch return c.hermes_value_create_boolean(runtime, false);
    defer ctx.allocator.free(content);

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.append(name, content) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.delete(name) -> boolean
// ============================================================================

fn memDelete(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    // Get name argument
    const name_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(name_arg)) return c.hermes_value_create_boolean(runtime, false);

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.delete(name_ptr[0..name_len]) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.list() -> string[]
// ============================================================================

fn memList(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    var names = memory.list() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    defer {
        for (names.items) |n| ctx.allocator.free(n);
        names.deinit(ctx.allocator);
    }

    // Create JavaScript array
    const arr = c.hermes_array_create(rt, names.items.len) orelse return null;

    for (names.items, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len);
        c.hermes_array_set(rt, arr, i, str);
    }

    return arr;
}

// ============================================================================
// vim.ai.mem.temperature(name) -> number | null
// ============================================================================

fn memTemperature(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    if (count < 1) return null;

    // Get name argument
    const name_arg = args[0] orelse return null;
    if (!c.hermes_value_is_string(name_arg)) return null;

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return null;

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    const temp = memory.temperature(name_ptr[0..name_len]) catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    return c.hermes_value_create_number(rt, @floatCast(temp));
}

// ============================================================================
// vim.ai.mem.setTemperature(name, temp) -> boolean
// ============================================================================

fn memSetTemperature(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 2) return c.hermes_value_create_boolean(runtime, false);

    // Get name argument
    const name_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(name_arg)) return c.hermes_value_create_boolean(runtime, false);

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Get temp argument
    const temp_arg = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(temp_arg)) return c.hermes_value_create_boolean(runtime, false);

    const temp: f32 = @floatCast(c.hermes_value_get_number(temp_arg));

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.setTemperature(name_ptr[0..name_len], temp) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.loadFile(name, path) -> boolean
// ============================================================================

fn memLoadFile(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 2) return c.hermes_value_create_boolean(runtime, false);

    // Get name argument
    const name_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(name_arg)) return c.hermes_value_create_boolean(runtime, false);

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Get path argument
    const path_arg = args[1] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(path_arg)) return c.hermes_value_create_boolean(runtime, false);

    var path_len: usize = 0;
    const path_ptr = c.hermes_value_get_string(rt, path_arg, &path_len);
    if (path_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    // Copy strings since Hermes uses shared buffer
    const name = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return c.hermes_value_create_boolean(runtime, false);
    defer ctx.allocator.free(name);

    const path = ctx.allocator.dupe(u8, path_ptr[0..path_len]) catch return c.hermes_value_create_boolean(runtime, false);
    defer ctx.allocator.free(path);

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.loadFile(name, path) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.refresh(name) -> boolean
// ============================================================================

fn memRefresh(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    // Get name argument
    const name_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(name_arg)) return c.hermes_value_create_boolean(runtime, false);

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
    if (name_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.refresh(name_ptr[0..name_len]) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.tokens(name?) -> number
// ============================================================================

fn memTokens(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    // If name provided, get tokens for that block; otherwise total
    if (count > 0) {
        const name_arg = args[0] orelse return null;
        if (c.hermes_value_is_string(name_arg)) {
            var name_len: usize = 0;
            const name_ptr = c.hermes_value_get_string(rt, name_arg, &name_len);
            if (name_ptr != null) {
                const tokens = memory.tokens(name_ptr[0..name_len]) catch |e| {
                    ctx.setErrorFromCode(e);
                    return null;
                };
                return c.hermes_value_create_number(rt, @floatFromInt(tokens));
            }
        }
    }

    // Total tokens
    const total = memory.tokens(null) catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    return c.hermes_value_create_number(rt, @floatFromInt(total));
}

// ============================================================================
// vim.ai.mem.budget() -> number
// ============================================================================

fn memBudget(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    return c.hermes_value_create_number(rt, @floatFromInt(memory.getBudget()));
}

// ============================================================================
// vim.ai.mem.setBudget(tokens) -> boolean
// ============================================================================

fn memSetBudget(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const budget_arg = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(budget_arg)) return c.hermes_value_create_boolean(runtime, false);

    const budget: u32 = @intFromFloat(c.hermes_value_get_number(budget_arg));

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    memory.setBudget(budget) catch |e| {
        ctx.setErrorFromCode(e);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.mem.buildContext() -> string (JSON array)
// ============================================================================

fn memBuildContext(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const memory = ctx.getOrInitMemory() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    const json = memory.buildContext() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    defer ctx.allocator.free(json);

    return c.hermes_value_create_string(rt, json.ptr, json.len);
}

// ============================================================================
// HostObject Getter
// ============================================================================

const HostFunction = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue;

pub export fn aiMemHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(HostFunction).initComptime(.{
        .{ "get", memGet },
        .{ "set", memSet },
        .{ "append", memAppend },
        .{ "delete", memDelete },
        .{ "list", memList },
        .{ "temperature", memTemperature },
        .{ "setTemperature", memSetTemperature },
        .{ "loadFile", memLoadFile },
        .{ "refresh", memRefresh },
        .{ "tokens", memTokens },
        .{ "budget", memBudget },
        .{ "setBudget", memSetBudget },
        .{ "buildContext", memBuildContext },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(rt, prop_name, func, context);
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, ctx: *AiMemApiContext) void {
    global_ctx = ctx;

    // Register vim.ai.mem as __aiMem (runtime.ts maps to vim.ai.mem)
    c.hermes_register_host_object(
        runtime,
        "__aiMem",
        aiMemHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        if (ctx.memory) |m| {
            m.deinit();
            ctx.allocator.destroy(m);
            ctx.memory = null;
        }
        ctx.clearError();
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}
