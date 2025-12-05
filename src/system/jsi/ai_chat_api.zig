/// ai_chat_api.zig - JSI bindings for vim.ai.chat
///
/// Exposes chat session management to JavaScript:
///   - vim.ai.chat.createSession(id)
///   - vim.ai.chat.getSession(id)
///   - vim.ai.chat.deleteSession(id)
///   - vim.ai.chat.setActive(id)
///   - vim.ai.chat.addUser(content)
///   - vim.ai.chat.addAssistant(content)
///   - vim.ai.chat.list()
///   - vim.ai.chat.export()
///   - vim.ai.chat.clear()
///   - vim.ai.chat.tokens
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const c_api = @import("c_api.zig");
const c = c_api.c;
const chat = @import("../ai/chat.zig");
const ai_mem_api = @import("ai_mem_api.zig");

/// Global context for chat API
pub var global_ctx: ?*AiChatApiContext = null;

pub const AiChatApiContext = struct {
    allocator: Allocator,
    chat_manager: chat.Chat,

    pub fn init(allocator: Allocator) !*AiChatApiContext {
        const ctx = try allocator.create(AiChatApiContext);
        ctx.* = .{
            .allocator = allocator,
            .chat_manager = chat.Chat.init(allocator),
        };

        // Link to memory if available
        if (ai_mem_api.global_ctx) |mem_ctx| {
            if (mem_ctx.memory) |mem_ptr| {
                ctx.chat_manager.setMemory(mem_ptr);
            }
        }

        return ctx;
    }

    pub fn deinit(self: *AiChatApiContext) void {
        self.chat_manager.deinit();
        self.allocator.destroy(self);
    }
};

/// Deinitialize chat API
pub fn deinitChatApi() void {
    if (global_ctx) |ctx| {
        ctx.deinit();
        global_ctx = null;
    }
}

fn getContext(context: ?*anyopaque) ?*AiChatApiContext {
    const ctx_ptr = context orelse return null;
    return @ptrCast(@alignCast(ctx_ptr));
}

// =============================================================================
// API Functions
// =============================================================================

const HostFunction = *const fn (
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue;

/// createSession(id: string): boolean
fn chatCreateSession(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(id_val)) return c.hermes_value_create_boolean(runtime, false);

    var id_len: usize = 0;
    const id_ptr = c.hermes_value_get_string(rt, id_val, &id_len);
    if (id_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const id = id_ptr[0..id_len];

    // Create session
    _ = ctx.chat_manager.getOrCreateSession(id) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

/// getSession(id: string): string | null
fn chatGetSession(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_null(runtime);
    const rt = runtime orelse return c.hermes_value_create_null(runtime);

    if (count < 1) return c.hermes_value_create_null(runtime);

    const id_val = args[0] orelse return c.hermes_value_create_null(runtime);
    if (!c.hermes_value_is_string(id_val)) return c.hermes_value_create_null(runtime);

    var id_len: usize = 0;
    const id_ptr = c.hermes_value_get_string(rt, id_val, &id_len);
    if (id_ptr == null) return c.hermes_value_create_null(runtime);

    const id = id_ptr[0..id_len];

    const session = ctx.chat_manager.getSession(id) orelse {
        return c.hermes_value_create_null(runtime);
    };

    // Return session info as JSON
    const json = session.toJson(ctx.allocator) catch {
        return c.hermes_value_create_null(runtime);
    };
    defer ctx.allocator.free(json);

    return c.hermes_value_create_string(rt, json.ptr, json.len);
}

/// deleteSession(id: string): boolean
fn chatDeleteSession(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(id_val)) return c.hermes_value_create_boolean(runtime, false);

    var id_len: usize = 0;
    const id_ptr = c.hermes_value_get_string(rt, id_val, &id_len);
    if (id_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const id = id_ptr[0..id_len];

    return c.hermes_value_create_boolean(runtime, ctx.chat_manager.deleteSession(id));
}

/// setActive(id: string): boolean
fn chatSetActive(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const id_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(id_val)) return c.hermes_value_create_boolean(runtime, false);

    var id_len: usize = 0;
    const id_ptr = c.hermes_value_get_string(rt, id_val, &id_len);
    if (id_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const id = id_ptr[0..id_len];

    ctx.chat_manager.setActiveSession(id) catch {
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

/// getActive(): string | null
fn chatGetActive(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_null(runtime);
    const rt = runtime orelse return c.hermes_value_create_null(runtime);

    if (ctx.chat_manager.active_session) |id| {
        return c.hermes_value_create_string(rt, id.ptr, id.len);
    }

    return c.hermes_value_create_null(runtime);
}

/// addUser(content: string): number (message ID)
fn chatAddUser(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_number(runtime, -1);
    const rt = runtime orelse return c.hermes_value_create_number(runtime, -1);

    if (count < 1) return c.hermes_value_create_number(runtime, -1);

    const content_val = args[0] orelse return c.hermes_value_create_number(runtime, -1);
    if (!c.hermes_value_is_string(content_val)) return c.hermes_value_create_number(runtime, -1);

    var content_len: usize = 0;
    const content_ptr = c.hermes_value_get_string(rt, content_val, &content_len);
    if (content_ptr == null) return c.hermes_value_create_number(runtime, -1);

    const content = content_ptr[0..content_len];

    const msg_id = ctx.chat_manager.addUserMessage(content) catch {
        return c.hermes_value_create_number(runtime, -1);
    };

    return c.hermes_value_create_number(runtime, @floatFromInt(msg_id));
}

/// addAssistant(content: string): number (message ID)
fn chatAddAssistant(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_number(runtime, -1);
    const rt = runtime orelse return c.hermes_value_create_number(runtime, -1);

    if (count < 1) return c.hermes_value_create_number(runtime, -1);

    const content_val = args[0] orelse return c.hermes_value_create_number(runtime, -1);
    if (!c.hermes_value_is_string(content_val)) return c.hermes_value_create_number(runtime, -1);

    var content_len: usize = 0;
    const content_ptr = c.hermes_value_get_string(rt, content_val, &content_len);
    if (content_ptr == null) return c.hermes_value_create_number(runtime, -1);

    const content = content_ptr[0..content_len];

    const msg_id = ctx.chat_manager.addAssistantMessage(content) catch {
        return c.hermes_value_create_number(runtime, -1);
    };

    return c.hermes_value_create_number(runtime, @floatFromInt(msg_id));
}

/// list(): string[] - returns session IDs
fn chatList(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_array_create(runtime, 0);
    const rt = runtime orelse return c.hermes_array_create(runtime, 0);

    const sessions = ctx.chat_manager.listSessions() catch {
        return c.hermes_array_create(runtime, 0);
    };
    defer {
        for (sessions) |s| ctx.allocator.free(s);
        ctx.allocator.free(sessions);
    }

    const arr = c.hermes_array_create(rt, sessions.len);
    for (sessions, 0..) |id, i| {
        const str_val = c.hermes_value_create_string(rt, id.ptr, id.len);
        c.hermes_array_set(rt, arr, i, str_val);
    }

    return arr;
}

/// export(): string | null - export active session as JSON
fn chatExport(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_null(runtime);
    const rt = runtime orelse return c.hermes_value_create_null(runtime);

    const json = ctx.chat_manager.exportActiveSession() catch {
        return c.hermes_value_create_null(runtime);
    };

    if (json) |j| {
        defer ctx.allocator.free(j);
        return c.hermes_value_create_string(rt, j.ptr, j.len);
    }

    return c.hermes_value_create_null(runtime);
}

/// clear(): void - clear active session
fn chatClear(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_undefined(runtime);

    ctx.chat_manager.clearActiveSession();

    return c.hermes_value_create_undefined(runtime);
}

/// tokens(): number - get active session token count
fn chatTokens(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_number(runtime, 0);

    const tokens = ctx.chat_manager.getTokenCount();
    return c.hermes_value_create_number(runtime, @floatFromInt(tokens));
}

/// needsSummary(): boolean
fn chatNeedsSummary(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    return c.hermes_value_create_boolean(runtime, ctx.chat_manager.needsSummarization());
}

// =============================================================================
// HostObject Implementation
// =============================================================================

pub export fn aiChatHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(HostFunction).initComptime(.{
        .{ "createSession", chatCreateSession },
        .{ "getSession", chatGetSession },
        .{ "deleteSession", chatDeleteSession },
        .{ "setActive", chatSetActive },
        .{ "getActive", chatGetActive },
        .{ "addUser", chatAddUser },
        .{ "addAssistant", chatAddAssistant },
        .{ "list", chatList },
        .{ "export", chatExport },
        .{ "clear", chatClear },
        .{ "tokens", chatTokens },
        .{ "needsSummary", chatNeedsSummary },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(rt, prop_name, func, context);
}
