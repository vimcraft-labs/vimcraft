/// AI Provider Abstraction
///
/// Unified interface for LLM providers (OpenAI, Anthropic, Ollama).
/// All providers internally use OpenAI's Chat Completions format as the standard.
///
/// Architecture:
///   User Code → Unified API → Provider Adapter → HTTP → LLM Service
///
/// Why Zig:
///   - Zero-copy for large context
///   - Native memory management (no GC pauses)
///   - Explicit allocators
///   - C interop for HTTP/TLS
///
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Provider types
pub const ProviderType = enum {
    openai,
    anthropic,
    ollama,
    custom,
};

/// Message role (OpenAI convention)
pub const Role = enum {
    system,
    user,
    assistant,
    tool,

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }

    pub fn fromString(s: []const u8) ?Role {
        const map = std.StaticStringMap(Role).initComptime(.{
            .{ "system", .system },
            .{ "user", .user },
            .{ "assistant", .assistant },
            .{ "tool", .tool },
        });
        return map.get(s);
    }
};

/// Message in conversation
pub const Message = struct {
    role: Role,
    content: []const u8,
    name: ?[]const u8 = null,
    tool_call_id: ?[]const u8 = null,

    pub fn deinit(self: *Message, allocator: Allocator) void {
        allocator.free(self.content);
        if (self.name) |n| allocator.free(n);
        if (self.tool_call_id) |id| allocator.free(id);
    }
};

/// Tool definition (function calling)
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: []const u8, // JSON schema

    pub fn deinit(self: *Tool, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.parameters);
    }
};

/// Tool call from assistant
pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8, // JSON string

    pub fn deinit(self: *ToolCall, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.arguments);
    }
};

/// Request to LLM
pub const Request = struct {
    model: []const u8,
    messages: []const Message,
    tools: ?[]const Tool = null,
    temperature: f32 = 1.0,
    max_tokens: ?u32 = null,
    stream: bool = false,
    stop: ?[]const []const u8 = null,

    // Provider-specific options (passed through)
    extra: ?[]const u8 = null,
};

/// Response from LLM
pub const Response = struct {
    id: []const u8,
    model: []const u8,
    content: ?[]const u8,
    tool_calls: ?[]ToolCall,
    finish_reason: FinishReason,
    usage: Usage,

    allocator: Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.id);
        self.allocator.free(self.model);
        if (self.content) |c| self.allocator.free(c);
        if (self.tool_calls) |calls| {
            for (calls) |*call| call.deinit(self.allocator);
            self.allocator.free(calls);
        }
    }
};

pub const FinishReason = enum {
    stop,
    length,
    tool_calls,
    content_filter,
    unknown,

    pub fn fromString(s: []const u8) FinishReason {
        const map = std.StaticStringMap(FinishReason).initComptime(.{
            .{ "stop", .stop },
            .{ "end_turn", .stop }, // Anthropic
            .{ "length", .length },
            .{ "max_tokens", .length }, // Anthropic
            .{ "tool_calls", .tool_calls },
            .{ "tool_use", .tool_calls }, // Anthropic
            .{ "content_filter", .content_filter },
        });
        return map.get(s) orelse .unknown;
    }
};

pub const Usage = struct {
    prompt_tokens: u32 = 0,
    completion_tokens: u32 = 0,
    total_tokens: u32 = 0,
};

/// Streaming event
pub const StreamEvent = union(enum) {
    content_delta: []const u8,
    tool_call_delta: struct {
        id: []const u8,
        name: ?[]const u8,
        arguments_delta: []const u8,
    },
    done: Response,
    err: ProviderError,
};

/// Provider configuration
pub const Config = struct {
    provider: ProviderType,
    api_key: []const u8,
    base_url: ?[]const u8 = null, // For custom endpoints / Ollama
    organization: ?[]const u8 = null, // OpenAI org
    timeout_ms: u32 = 60_000,
    max_retries: u8 = 3,
};

/// Provider errors
pub const ProviderError = error{
    NetworkError,
    AuthenticationFailed,
    RateLimited,
    InvalidRequest,
    ModelNotFound,
    ContentFiltered,
    ServerError,
    Timeout,
    ParseError,
    OutOfMemory,
};

/// Provider interface
pub const Provider = struct {
    allocator: Allocator,
    config: Config,
    base_url: []const u8,

    const Self = @This();

    /// Initialize provider
    pub fn init(allocator: Allocator, config: Config) !Self {
        const base_url = if (config.base_url) |url|
            try allocator.dupe(u8, url)
        else switch (config.provider) {
            .openai => try allocator.dupe(u8, "https://api.openai.com/v1"),
            .anthropic => try allocator.dupe(u8, "https://api.anthropic.com/v1"),
            .ollama => try allocator.dupe(u8, "http://localhost:11434/api"),
            .custom => return ProviderError.InvalidRequest,
        };

        return .{
            .allocator = allocator,
            .config = config,
            .base_url = base_url,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.base_url);
    }

    /// Build request JSON for provider
    pub fn buildRequestJson(self: *Self, request: Request) ![]const u8 {
        var json_buf: std.ArrayList(u8) = .empty;
        errdefer json_buf.deinit(self.allocator);

        const writer = json_buf.writer(self.allocator);

        switch (self.config.provider) {
            .openai, .ollama => try self.buildOpenAiFormat(writer, request),
            .anthropic => try self.buildAnthropicFormat(writer, request),
            .custom => try self.buildOpenAiFormat(writer, request), // Default to OpenAI
        }

        return json_buf.toOwnedSlice(self.allocator);
    }

    fn buildOpenAiFormat(self: *Self, writer: anytype, request: Request) !void {
        _ = self;

        try writer.writeAll("{");

        // Model
        try writer.print("\"model\":\"{s}\"", .{request.model});

        // Messages
        try writer.writeAll(",\"messages\":[");
        for (request.messages, 0..) |msg, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{{\"role\":\"{s}\",\"content\":{any}}}", .{ msg.role.toString(), std.json.fmt(msg.content, .{}) });
        }
        try writer.writeByte(']');

        // Temperature
        if (request.temperature != 1.0) {
            try writer.print(",\"temperature\":{d:.2}", .{request.temperature});
        }

        // Max tokens
        if (request.max_tokens) |mt| {
            try writer.print(",\"max_tokens\":{d}", .{mt});
        }

        // Stream
        if (request.stream) {
            try writer.writeAll(",\"stream\":true");
        }

        // Tools
        if (request.tools) |tools| {
            try writer.writeAll(",\"tools\":[");
            for (tools, 0..) |tool, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.print("{{\"type\":\"function\",\"function\":{{\"name\":\"{s}\",\"description\":{any},\"parameters\":{s}}}}}", .{ tool.name, std.json.fmt(tool.description, .{}), tool.parameters });
            }
            try writer.writeByte(']');
        }

        try writer.writeByte('}');
    }

    fn buildAnthropicFormat(self: *Self, writer: anytype, request: Request) !void {
        _ = self;

        try writer.writeAll("{");

        // Model
        try writer.print("\"model\":\"{s}\"", .{request.model});

        // Max tokens (required for Anthropic)
        const max_tokens = request.max_tokens orelse 4096;
        try writer.print(",\"max_tokens\":{d}", .{max_tokens});

        // Extract system message
        var system_content: ?[]const u8 = null;
        for (request.messages) |msg| {
            if (msg.role == .system) {
                system_content = msg.content;
                break;
            }
        }

        if (system_content) |sys| {
            try writer.print(",\"system\":{any}", .{std.json.fmt(sys, .{})});
        }

        // Messages (without system)
        try writer.writeAll(",\"messages\":[");
        var first = true;
        for (request.messages) |msg| {
            if (msg.role == .system) continue;
            if (!first) try writer.writeByte(',');
            first = false;

            try writer.print("{{\"role\":\"{s}\",\"content\":{any}}}", .{ msg.role.toString(), std.json.fmt(msg.content, .{}) });
        }
        try writer.writeByte(']');

        // Stream
        if (request.stream) {
            try writer.writeAll(",\"stream\":true");
        }

        // Tools (Anthropic format)
        if (request.tools) |tools| {
            try writer.writeAll(",\"tools\":[");
            for (tools, 0..) |tool, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.print("{{\"name\":\"{s}\",\"description\":{any},\"input_schema\":{s}}}", .{ tool.name, std.json.fmt(tool.description, .{}), tool.parameters });
            }
            try writer.writeByte(']');
        }

        try writer.writeByte('}');
    }

    /// Get endpoint for chat completions
    pub fn getChatEndpoint(self: *Self) ![]const u8 {
        return switch (self.config.provider) {
            .openai => try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url}),
            .anthropic => try std.fmt.allocPrint(self.allocator, "{s}/messages", .{self.base_url}),
            .ollama => try std.fmt.allocPrint(self.allocator, "{s}/chat", .{self.base_url}),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url}),
        };
    }

    /// Get required headers
    pub fn getHeaders(self: *Self) ![]const Header {
        var headers: std.ArrayList(Header) = .empty;

        try headers.append(self.allocator, .{ .name = "Content-Type", .value = "application/json" });

        switch (self.config.provider) {
            .openai => {
                const auth = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.config.api_key});
                try headers.append(self.allocator, .{ .name = "Authorization", .value = auth });

                if (self.config.organization) |org| {
                    try headers.append(self.allocator, .{ .name = "OpenAI-Organization", .value = org });
                }
            },
            .anthropic => {
                try headers.append(self.allocator, .{ .name = "x-api-key", .value = self.config.api_key });
                try headers.append(self.allocator, .{ .name = "anthropic-version", .value = "2023-06-01" });
            },
            .ollama => {
                // Ollama typically doesn't need auth for local
            },
            .custom => {
                const auth = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.config.api_key});
                try headers.append(self.allocator, .{ .name = "Authorization", .value = auth });
            },
        }

        return headers.toOwnedSlice(self.allocator);
    }

    /// Parse response JSON based on provider
    pub fn parseResponse(self: *Self, json_bytes: []const u8) !Response {
        return switch (self.config.provider) {
            .openai, .ollama, .custom => self.parseOpenAiResponse(json_bytes),
            .anthropic => self.parseAnthropicResponse(json_bytes),
        };
    }

    fn parseOpenAiResponse(self: *Self, json_bytes: []const u8) !Response {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_bytes, .{}) catch
            return ProviderError.ParseError;
        defer parsed.deinit();

        const root = parsed.value.object;

        // Check for error
        if (root.get("error")) |_| {
            return ProviderError.ServerError;
        }

        const id = if (root.get("id")) |v| try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "");
        const model = if (root.get("model")) |v| try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "");

        var content: ?[]const u8 = null;
        var finish_reason: FinishReason = .unknown;
        var tool_calls: ?[]ToolCall = null;

        if (root.get("choices")) |choices| {
            if (choices.array.items.len > 0) {
                const choice = choices.array.items[0].object;

                if (choice.get("finish_reason")) |fr| {
                    if (fr != .null) {
                        finish_reason = FinishReason.fromString(fr.string);
                    }
                }

                if (choice.get("message")) |msg| {
                    const msg_obj = msg.object;
                    if (msg_obj.get("content")) |c| {
                        if (c != .null) {
                            content = try self.allocator.dupe(u8, c.string);
                        }
                    }

                    if (msg_obj.get("tool_calls")) |tc| {
                        var calls: std.ArrayList(ToolCall) = .empty;
                        for (tc.array.items) |call_val| {
                            const call = call_val.object;
                            const func = call.get("function").?.object;

                            try calls.append(self.allocator, .{
                                .id = try self.allocator.dupe(u8, call.get("id").?.string),
                                .name = try self.allocator.dupe(u8, func.get("name").?.string),
                                .arguments = try self.allocator.dupe(u8, func.get("arguments").?.string),
                            });
                        }
                        tool_calls = try calls.toOwnedSlice(self.allocator);
                    }
                }
            }
        }

        var usage = Usage{};
        if (root.get("usage")) |u| {
            const usage_obj = u.object;
            if (usage_obj.get("prompt_tokens")) |pt| usage.prompt_tokens = @intCast(pt.integer);
            if (usage_obj.get("completion_tokens")) |ct| usage.completion_tokens = @intCast(ct.integer);
            if (usage_obj.get("total_tokens")) |tt| usage.total_tokens = @intCast(tt.integer);
        }

        return .{
            .id = id,
            .model = model,
            .content = content,
            .tool_calls = tool_calls,
            .finish_reason = finish_reason,
            .usage = usage,
            .allocator = self.allocator,
        };
    }

    fn parseAnthropicResponse(self: *Self, json_bytes: []const u8) !Response {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_bytes, .{}) catch
            return ProviderError.ParseError;
        defer parsed.deinit();

        const root = parsed.value.object;

        // Check for error
        if (root.get("error")) |_| {
            return ProviderError.ServerError;
        }

        const id = if (root.get("id")) |v| try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "");
        const model = if (root.get("model")) |v| try self.allocator.dupe(u8, v.string) else try self.allocator.dupe(u8, "");

        var content: ?[]const u8 = null;
        var tool_calls: ?[]ToolCall = null;
        var finish_reason: FinishReason = .unknown;

        if (root.get("stop_reason")) |sr| {
            if (sr != .null) {
                finish_reason = FinishReason.fromString(sr.string);
            }
        }

        // Anthropic uses "content" as an array of blocks
        if (root.get("content")) |content_arr| {
            var text_parts: std.ArrayList(u8) = .empty;
            var calls: std.ArrayList(ToolCall) = .empty;

            for (content_arr.array.items) |block| {
                const block_obj = block.object;
                const block_type = block_obj.get("type").?.string;

                if (std.mem.eql(u8, block_type, "text")) {
                    try text_parts.appendSlice(self.allocator, block_obj.get("text").?.string);
                } else if (std.mem.eql(u8, block_type, "tool_use")) {
                    // Format input JSON as string
                    const input_val = block_obj.get("input");
                    const input_str = if (input_val) |iv| blk: {
                        break :blk try std.fmt.allocPrint(self.allocator, "{any}", .{std.json.fmt(iv, .{})});
                    } else try self.allocator.dupe(u8, "{}");

                    try calls.append(self.allocator, .{
                        .id = try self.allocator.dupe(u8, block_obj.get("id").?.string),
                        .name = try self.allocator.dupe(u8, block_obj.get("name").?.string),
                        .arguments = input_str,
                    });
                }
            }

            if (text_parts.items.len > 0) {
                content = try text_parts.toOwnedSlice(self.allocator);
            } else {
                text_parts.deinit(self.allocator);
            }

            if (calls.items.len > 0) {
                tool_calls = try calls.toOwnedSlice(self.allocator);
            } else {
                calls.deinit(self.allocator);
            }
        }

        var usage = Usage{};
        if (root.get("usage")) |u| {
            const usage_obj = u.object;
            if (usage_obj.get("input_tokens")) |it| usage.prompt_tokens = @intCast(it.integer);
            if (usage_obj.get("output_tokens")) |ot| usage.completion_tokens = @intCast(ot.integer);
            usage.total_tokens = usage.prompt_tokens + usage.completion_tokens;
        }

        return .{
            .id = id,
            .model = model,
            .content = content,
            .tool_calls = tool_calls,
            .finish_reason = finish_reason,
            .usage = usage,
            .allocator = self.allocator,
        };
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

// =============================================================================
// Token Estimation (fast heuristic)
// =============================================================================

/// Estimate tokens for text (heuristic: ~4 chars per token for English)
pub fn estimateTokens(text: []const u8) u32 {
    // Simple heuristic: roughly 4 characters per token
    // More accurate for OpenAI: ~3.5-4 chars/token for English
    // For code: ~2-3 chars/token (more tokens per character)
    return @intCast(@max(1, text.len / 4));
}

/// Estimate tokens for messages
pub fn estimateMessagesTokens(messages: []const Message) u32 {
    var total: u32 = 0;
    for (messages) |msg| {
        total += estimateTokens(msg.content);
        total += 4; // Overhead for role, formatting
    }
    return total;
}

// =============================================================================
// Tests
// =============================================================================

test "provider json building" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, .{
        .provider = .openai,
        .api_key = "test-key",
    });
    defer provider.deinit();

    const request = Request{
        .model = "gpt-4",
        .messages = &[_]Message{
            .{ .role = .system, .content = "You are helpful." },
            .{ .role = .user, .content = "Hello" },
        },
        .temperature = 0.7,
    };

    const json = try provider.buildRequestJson(request);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\":\"gpt-4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"role\":\"system\"") != null);
}

test "token estimation" {
    // "Hello, world!" = 13 chars ≈ 3-4 tokens
    const tokens = estimateTokens("Hello, world!");
    try std.testing.expect(tokens >= 2 and tokens <= 5);
}

test "role conversion" {
    try std.testing.expectEqual(Role.user, Role.fromString("user").?);
    try std.testing.expectEqualStrings("assistant", Role.assistant.toString());
}
