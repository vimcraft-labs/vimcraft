/// vim.ai.llm - LLM Communication JSI Bindings
///
/// API:
///   vim.ai.llm.configure(config) -> boolean
///   vim.ai.llm.buildRequest(model, message?) -> string (JSON)
///   vim.ai.llm.getEndpoint() -> string
///   vim.ai.llm.getHeaders() -> {name, value}[]
///   vim.ai.llm.parseResponse(json) -> Response
///   vim.ai.llm.executeToolCall(toolCall) -> string (result JSON)
///   vim.ai.llm.addUserMessage(content) -> boolean
///   vim.ai.llm.addAssistantMessage(content) -> boolean
///   vim.ai.llm.addToolResult(id, result) -> boolean
///   vim.ai.llm.clearHistory() -> void
///   vim.ai.llm.getHistoryTokens() -> number
///   vim.ai.llm.setMaxHistoryTokens(tokens) -> boolean
///   vim.ai.llm.getMemoryTools() -> Tool[]
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const c_api = @import("c_api.zig");
const c = c_api.c;

const llm_mod = @import("../ai/llm.zig");
const mem_mod = @import("../ai/mem.zig");
const provider_mod = @import("../ai/providers/provider.zig");
const ai_mem_api = @import("ai_mem_api.zig");

/// Context for AI LLM API
pub const AiLlmApiContext = struct {
    allocator: Allocator,
    llm: ?*llm_mod.LLM = null,
    provider_config: ?provider_mod.Config = null,
    last_error: ?[]const u8 = null,

    // Owned copies of config strings
    owned_api_key: ?[]const u8 = null,
    owned_base_url: ?[]const u8 = null,

    /// Get or lazily initialize LLM
    /// Requires memory to be initialized first (from ai_mem_api)
    pub fn getOrInitLLM(self: *AiLlmApiContext) !*llm_mod.LLM {
        if (self.llm) |l| return l;

        // Get memory from ai_mem_api context
        if (ai_mem_api.global_ctx == null) {
            return error.MemoryNotInitialized;
        }
        const mem_ctx = ai_mem_api.global_ctx.?;
        const memory = try mem_ctx.getOrInitMemory();

        // Get provider config
        const config = self.provider_config orelse return error.ProviderNotConfigured;

        const llm_ptr = try self.allocator.create(llm_mod.LLM);
        errdefer self.allocator.destroy(llm_ptr);

        llm_ptr.* = try llm_mod.LLM.init(self.allocator, memory, config);

        self.llm = llm_ptr;
        return llm_ptr;
    }

    /// Set the last error message
    pub fn setError(self: *AiLlmApiContext, msg: []const u8) void {
        self.clearError();
        self.last_error = self.allocator.dupe(u8, msg) catch null;
    }

    pub fn setErrorFromCode(self: *AiLlmApiContext, err: anyerror) void {
        self.setError(@errorName(err));
    }

    pub fn clearError(self: *AiLlmApiContext) void {
        if (self.last_error) |old| {
            self.allocator.free(old);
            self.last_error = null;
        }
    }

    pub fn freeOwnedStrings(self: *AiLlmApiContext) void {
        if (self.owned_api_key) |k| {
            self.allocator.free(k);
            self.owned_api_key = null;
        }
        if (self.owned_base_url) |u| {
            self.allocator.free(u);
            self.owned_base_url = null;
        }
    }
};

var global_ctx: ?*AiLlmApiContext = null;

fn getContext(context: ?*anyopaque) ?*AiLlmApiContext {
    const ctx_ptr = context orelse return null;
    return @ptrCast(@alignCast(ctx_ptr));
}

// ============================================================================
// vim.ai.llm.configure(config) -> boolean
// ============================================================================

fn llmConfigure(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const config_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_object(config_val)) return c.hermes_value_create_boolean(runtime, false);

    // Free previous config strings
    ctx.freeOwnedStrings();

    // Get provider type
    const provider_val = c.hermes_value_get_property(rt, config_val, "provider") orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(provider_val)) return c.hermes_value_create_boolean(runtime, false);

    var provider_len: usize = 0;
    const provider_ptr = c.hermes_value_get_string(rt, provider_val, &provider_len);
    if (provider_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const provider_type = blk: {
        const s = provider_ptr[0..provider_len];
        if (std.mem.eql(u8, s, "openai")) break :blk provider_mod.ProviderType.openai;
        if (std.mem.eql(u8, s, "anthropic")) break :blk provider_mod.ProviderType.anthropic;
        if (std.mem.eql(u8, s, "ollama")) break :blk provider_mod.ProviderType.ollama;
        break :blk provider_mod.ProviderType.custom;
    };

    // Get API key
    const api_key_val = c.hermes_value_get_property(rt, config_val, "apiKey");
    var api_key: []const u8 = "";
    if (api_key_val) |av| {
        if (c.hermes_value_is_string(av)) {
            var key_len: usize = 0;
            const key_ptr = c.hermes_value_get_string(rt, av, &key_len);
            if (key_ptr != null) {
                ctx.owned_api_key = ctx.allocator.dupe(u8, key_ptr[0..key_len]) catch return c.hermes_value_create_boolean(runtime, false);
                api_key = ctx.owned_api_key.?;
            }
        }
    }

    // Get base URL (optional)
    var base_url: ?[]const u8 = null;
    const base_url_val = c.hermes_value_get_property(rt, config_val, "baseUrl");
    if (base_url_val) |bv| {
        if (c.hermes_value_is_string(bv)) {
            var url_len: usize = 0;
            const url_ptr = c.hermes_value_get_string(rt, bv, &url_len);
            if (url_ptr != null) {
                ctx.owned_base_url = ctx.allocator.dupe(u8, url_ptr[0..url_len]) catch return c.hermes_value_create_boolean(runtime, false);
                base_url = ctx.owned_base_url;
            }
        }
    }

    ctx.provider_config = .{
        .provider = provider_type,
        .api_key = api_key,
        .base_url = base_url,
    };

    // Reset LLM to pick up new config
    if (ctx.llm) |l| {
        l.deinit();
        ctx.allocator.destroy(l);
        ctx.llm = null;
    }

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.llm.buildRequest(model, message?) -> string (JSON)
// ============================================================================

fn llmBuildRequest(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    if (count < 1) return null;

    // Get model
    const model_val = args[0] orelse return null;
    if (!c.hermes_value_is_string(model_val)) return null;

    var model_len: usize = 0;
    const model_ptr = c.hermes_value_get_string(rt, model_val, &model_len);
    if (model_ptr == null) return null;

    // Get optional message
    var message: ?[]const u8 = null;
    if (count > 1) {
        const msg_val = args[1] orelse null;
        if (msg_val != null and c.hermes_value_is_string(msg_val)) {
            var msg_len: usize = 0;
            const msg_ptr = c.hermes_value_get_string(rt, msg_val, &msg_len);
            if (msg_ptr != null) {
                message = msg_ptr[0..msg_len];
            }
        }
    }

    const llm = ctx.getOrInitLLM() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    // Copy model string
    const model = ctx.allocator.dupe(u8, model_ptr[0..model_len]) catch return null;
    defer ctx.allocator.free(model);

    // Copy message if present
    var owned_message: ?[]const u8 = null;
    if (message) |m| {
        owned_message = ctx.allocator.dupe(u8, m) catch return null;
    }
    defer if (owned_message) |om| ctx.allocator.free(om);

    const json = llm.buildRequestJson(model, owned_message) catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    defer ctx.allocator.free(json);

    return c.hermes_value_create_string(rt, json.ptr, json.len);
}

// ============================================================================
// vim.ai.llm.getEndpoint() -> string
// ============================================================================

fn llmGetEndpoint(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const llm = ctx.getOrInitLLM() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    const endpoint = llm.getEndpoint() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    defer ctx.allocator.free(endpoint);

    return c.hermes_value_create_string(rt, endpoint.ptr, endpoint.len);
}

// ============================================================================
// vim.ai.llm.getHeaders() -> {name, value}[]
// ============================================================================

fn llmGetHeaders(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const llm = ctx.getOrInitLLM() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };

    const headers = llm.getHeaders() catch |e| {
        ctx.setErrorFromCode(e);
        return null;
    };
    defer provider_mod.freeHeaders(ctx.allocator, headers);

    const arr = c.hermes_array_create(rt, headers.len) orelse return null;

    for (headers, 0..) |h, i| {
        const obj = c.hermes_value_create_object(rt);
        c.hermes_value_set_property(rt, obj, "name", c.hermes_value_create_string(rt, h.name.ptr, h.name.len));
        c.hermes_value_set_property(rt, obj, "value", c.hermes_value_create_string(rt, h.value.ptr, h.value.len));
        c.hermes_array_set(rt, arr, i, obj);
    }

    return arr;
}

// ============================================================================
// vim.ai.llm.addUserMessage(content) -> boolean
// ============================================================================

fn llmAddUserMessage(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const content_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(content_val)) return c.hermes_value_create_boolean(runtime, false);

    var content_len: usize = 0;
    const content_ptr = c.hermes_value_get_string(rt, content_val, &content_len);
    if (content_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const llm = ctx.getOrInitLLM() catch return c.hermes_value_create_boolean(runtime, false);

    llm.addUserMessage(content_ptr[0..content_len]) catch return c.hermes_value_create_boolean(runtime, false);

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.llm.addAssistantMessage(content) -> boolean
// ============================================================================

fn llmAddAssistantMessage(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const content_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_string(content_val)) return c.hermes_value_create_boolean(runtime, false);

    var content_len: usize = 0;
    const content_ptr = c.hermes_value_get_string(rt, content_val, &content_len);
    if (content_ptr == null) return c.hermes_value_create_boolean(runtime, false);

    const llm = ctx.getOrInitLLM() catch return c.hermes_value_create_boolean(runtime, false);

    llm.addAssistantMessage(content_ptr[0..content_len]) catch return c.hermes_value_create_boolean(runtime, false);

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.llm.clearHistory() -> void
// ============================================================================

fn llmClearHistory(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_undefined(runtime);

    if (ctx.llm) |llm| {
        llm.clearHistory();
    }

    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// vim.ai.llm.getHistoryTokens() -> number
// ============================================================================

fn llmGetHistoryTokens(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    const llm = ctx.getOrInitLLM() catch return c.hermes_value_create_number(rt, 0);

    return c.hermes_value_create_number(rt, @floatFromInt(llm.getHistoryTokens()));
}

// ============================================================================
// vim.ai.llm.setMaxHistoryTokens(tokens) -> boolean
// ============================================================================

fn llmSetMaxHistoryTokens(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    if (count < 1) return c.hermes_value_create_boolean(runtime, false);

    const tokens_val = args[0] orelse return c.hermes_value_create_boolean(runtime, false);
    if (!c.hermes_value_is_number(tokens_val)) return c.hermes_value_create_boolean(runtime, false);

    const tokens: u32 = @intFromFloat(c.hermes_value_get_number(tokens_val));

    const llm = ctx.getOrInitLLM() catch return c.hermes_value_create_boolean(runtime, false);

    llm.setMaxHistoryTokens(tokens);

    return c.hermes_value_create_boolean(runtime, true);
}

// ============================================================================
// vim.ai.llm.getMemoryTools() -> Tool[]
// ============================================================================

fn llmGetMemoryTools(
    runtime: ?*c.OVHermesRuntime,
    _: ?*anyopaque,
    _: [*c]?*c.OVHermesValue,
    _: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;

    const tools = llm_mod.LLM.getMemoryTools();
    const arr = c.hermes_array_create(rt, tools.len) orelse return null;

    for (tools, 0..) |tool, i| {
        const obj = c.hermes_value_create_object(rt);
        c.hermes_value_set_property(rt, obj, "name", c.hermes_value_create_string(rt, tool.name.ptr, tool.name.len));
        c.hermes_value_set_property(rt, obj, "description", c.hermes_value_create_string(rt, tool.description.ptr, tool.description.len));
        c.hermes_value_set_property(rt, obj, "parameters", c.hermes_value_create_string(rt, tool.parameters.ptr, tool.parameters.len));
        c.hermes_array_set(rt, arr, i, obj);
    }

    return arr;
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

pub export fn aiLlmHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(HostFunction).initComptime(.{
        .{ "configure", llmConfigure },
        .{ "buildRequest", llmBuildRequest },
        .{ "getEndpoint", llmGetEndpoint },
        .{ "getHeaders", llmGetHeaders },
        .{ "addUserMessage", llmAddUserMessage },
        .{ "addAssistantMessage", llmAddAssistantMessage },
        .{ "clearHistory", llmClearHistory },
        .{ "getHistoryTokens", llmGetHistoryTokens },
        .{ "setMaxHistoryTokens", llmSetMaxHistoryTokens },
        .{ "getMemoryTools", llmGetMemoryTools },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(rt, prop_name, func, context);
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, ctx: *AiLlmApiContext) void {
    global_ctx = ctx;

    c.hermes_register_host_object(
        runtime,
        "__aiLlm",
        aiLlmHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        if (ctx.llm) |l| {
            l.deinit();
            ctx.allocator.destroy(l);
            ctx.llm = null;
        }
        ctx.freeOwnedStrings();
        ctx.clearError();
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}
