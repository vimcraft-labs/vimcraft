/// vim.ai.llm - LLM Communication Layer
///
/// Orchestrates communication with LLMs using memory blocks for context
/// and supports self-editing loop through tool calling.
///
/// Architecture:
///   mem.zig (context) → llm.zig (orchestration) → provider.zig (API) → HTTP → LLM
///
/// Self-Editing Loop (MemGPT-inspired):
///   LLM → tool_call(mem_set) → llm.zig executes → LLM continues
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const mem = @import("mem.zig");
const provider = @import("providers/provider.zig");

/// LLM orchestrator
pub const LLM = struct {
    allocator: Allocator,
    memory: *mem.Memory,
    llm_provider: provider.Provider,
    chat_history: std.ArrayList(provider.Message),
    max_history_tokens: u32,

    const Self = @This();

    /// Initialize LLM with memory and provider config
    pub fn init(allocator: Allocator, memory: *mem.Memory, config: provider.Config) !Self {
        return .{
            .allocator = allocator,
            .memory = memory,
            .llm_provider = try provider.Provider.init(allocator, config),
            .chat_history = .empty,
            .max_history_tokens = 4096, // Default chat history budget
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.chat_history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.chat_history.deinit(self.allocator);
        self.llm_provider.deinit();
    }

    /// Build system prompt from memory blocks
    /// Temperature controls inclusion priority
    pub fn buildSystemPrompt(self: *Self) ![]const u8 {
        const context = try self.memory.buildContext();

        // buildContext() returns plain text in [name]\ncontent\n\n format
        // If empty, provide a default system prompt
        if (context.len == 0) {
            self.allocator.free(context);
            return try self.allocator.dupe(u8, "You are an AI assistant integrated into Vimcraft editor.");
        }

        // The context is already formatted, return it directly
        return context;
    }

    /// Get built-in tools for self-editing memory loop
    pub fn getMemoryTools() []const provider.Tool {
        return &[_]provider.Tool{
            .{
                .name = "mem_get",
                .description = "Get a memory block by name",
                .parameters =
                \\{"type":"object","properties":{"name":{"type":"string","description":"Block name"}},"required":["name"]}
                ,
            },
            .{
                .name = "mem_set",
                .description = "Set or create a memory block",
                .parameters =
                \\{"type":"object","properties":{"name":{"type":"string","description":"Block name"},"content":{"type":"string","description":"Block content"}},"required":["name","content"]}
                ,
            },
            .{
                .name = "mem_append",
                .description = "Append content to a memory block",
                .parameters =
                \\{"type":"object","properties":{"name":{"type":"string","description":"Block name"},"content":{"type":"string","description":"Content to append"}},"required":["name","content"]}
                ,
            },
            .{
                .name = "mem_delete",
                .description = "Delete a memory block",
                .parameters =
                \\{"type":"object","properties":{"name":{"type":"string","description":"Block name"}},"required":["name"]}
                ,
            },
        };
    }

    /// Execute a tool call against memory
    pub fn executeToolCall(self: *Self, tool_call: provider.ToolCall) ![]const u8 {
        // Parse arguments
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, tool_call.arguments, .{}) catch {
            return try self.allocator.dupe(u8, "{\"error\":\"Invalid arguments\"}");
        };
        defer parsed.deinit();

        const args = parsed.value.object;

        if (std.mem.eql(u8, tool_call.name, "mem_get")) {
            const name = args.get("name") orelse return try self.allocator.dupe(u8, "{\"error\":\"Missing name\"}");
            if (name != .string) return try self.allocator.dupe(u8, "{\"error\":\"Invalid name type\"}");

            const block = self.memory.get(name.string) catch |e| {
                return try std.fmt.allocPrint(self.allocator, "{{\"error\":\"{s}\"}}", .{@errorName(e)});
            };
            defer {
                var mut_block = block;
                mut_block.deinit();
            }

            return try std.fmt.allocPrint(self.allocator, "{{\"content\":{any},\"temperature\":{d}}}", .{ std.json.fmt(block.content, .{}), block.temperature });
        } else if (std.mem.eql(u8, tool_call.name, "mem_set")) {
            const name = args.get("name") orelse return try self.allocator.dupe(u8, "{\"error\":\"Missing name\"}");
            const content = args.get("content") orelse return try self.allocator.dupe(u8, "{\"error\":\"Missing content\"}");

            if (name != .string or content != .string) {
                return try self.allocator.dupe(u8, "{\"error\":\"Invalid argument types\"}");
            }

            self.memory.set(name.string, content.string) catch |e| {
                return try std.fmt.allocPrint(self.allocator, "{{\"error\":\"{s}\"}}", .{@errorName(e)});
            };

            return try self.allocator.dupe(u8, "{\"success\":true}");
        } else if (std.mem.eql(u8, tool_call.name, "mem_append")) {
            const name = args.get("name") orelse return try self.allocator.dupe(u8, "{\"error\":\"Missing name\"}");
            const content = args.get("content") orelse return try self.allocator.dupe(u8, "{\"error\":\"Missing content\"}");

            if (name != .string or content != .string) {
                return try self.allocator.dupe(u8, "{\"error\":\"Invalid argument types\"}");
            }

            self.memory.append(name.string, content.string) catch |e| {
                return try std.fmt.allocPrint(self.allocator, "{{\"error\":\"{s}\"}}", .{@errorName(e)});
            };

            return try self.allocator.dupe(u8, "{\"success\":true}");
        } else if (std.mem.eql(u8, tool_call.name, "mem_delete")) {
            const name = args.get("name") orelse return try self.allocator.dupe(u8, "{\"error\":\"Missing name\"}");
            if (name != .string) return try self.allocator.dupe(u8, "{\"error\":\"Invalid name type\"}");

            self.memory.delete(name.string) catch |e| {
                return try std.fmt.allocPrint(self.allocator, "{{\"error\":\"{s}\"}}", .{@errorName(e)});
            };

            return try self.allocator.dupe(u8, "{\"success\":true}");
        }

        return try self.allocator.dupe(u8, "{\"error\":\"Unknown tool\"}");
    }

    /// Add user message to history
    pub fn addUserMessage(self: *Self, content: []const u8) !void {
        try self.chat_history.append(self.allocator, .{
            .role = .user,
            .content = try self.allocator.dupe(u8, content),
        });
        try self.trimHistory();
    }

    /// Add assistant message to history
    pub fn addAssistantMessage(self: *Self, content: []const u8) !void {
        try self.chat_history.append(self.allocator, .{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, content),
        });
        try self.trimHistory();
    }

    /// Add tool result to history
    pub fn addToolResult(self: *Self, tool_call_id: []const u8, result: []const u8) !void {
        const msg = provider.Message{
            .role = .tool,
            .content = try self.allocator.dupe(u8, result),
            .tool_call_id = try self.allocator.dupe(u8, tool_call_id),
        };
        try self.chat_history.append(self.allocator, msg);
    }

    /// Trim history to stay within token budget
    fn trimHistory(self: *Self) !void {
        var total_tokens = provider.estimateMessagesTokens(self.chat_history.items);

        // Remove oldest messages until under budget
        while (total_tokens > self.max_history_tokens and self.chat_history.items.len > 1) {
            var removed = self.chat_history.orderedRemove(0);
            removed.deinit(self.allocator);
            total_tokens = provider.estimateMessagesTokens(self.chat_history.items);
        }
    }

    /// Build full request with system prompt, history, and tools
    pub fn buildRequest(self: *Self, model: []const u8, user_message: ?[]const u8) !provider.Request {
        // Build system prompt from memory
        const system_prompt = try self.buildSystemPrompt();
        errdefer self.allocator.free(system_prompt);

        // Build messages array
        var messages: std.ArrayList(provider.Message) = .empty;
        errdefer {
            for (messages.items) |*m| m.deinit(self.allocator);
            messages.deinit(self.allocator);
        }

        // Add system message
        try messages.append(self.allocator, .{
            .role = .system,
            .content = system_prompt,
        });

        // Add chat history
        for (self.chat_history.items) |msg| {
            try messages.append(self.allocator, .{
                .role = msg.role,
                .content = try self.allocator.dupe(u8, msg.content),
                .tool_call_id = if (msg.tool_call_id) |id| try self.allocator.dupe(u8, id) else null,
            });
        }

        // Add current user message if provided
        if (user_message) |um| {
            try messages.append(self.allocator, .{
                .role = .user,
                .content = try self.allocator.dupe(u8, um),
            });
        }

        return .{
            .model = model,
            .messages = try messages.toOwnedSlice(self.allocator),
            .tools = getMemoryTools(),
            .temperature = 0.7,
        };
    }

    /// Build request JSON for HTTP call
    pub fn buildRequestJson(self: *Self, model: []const u8, user_message: ?[]const u8) ![]const u8 {
        const request = try self.buildRequest(model, user_message);
        defer {
            // Use @constCast because we own the messages and need to free their memory
            const mutable_msgs = @constCast(request.messages);
            for (mutable_msgs) |*msg| {
                msg.deinit(self.allocator);
            }
            self.allocator.free(mutable_msgs);
        }

        return self.llm_provider.buildRequestJson(request);
    }

    /// Get endpoint URL
    pub fn getEndpoint(self: *Self) ![]const u8 {
        return self.llm_provider.getChatEndpoint();
    }

    /// Get headers for request
    /// Caller must use provider.freeHeaders() to clean up
    pub fn getHeaders(self: *Self) ![]provider.Header {
        return self.llm_provider.getHeaders();
    }

    /// Parse response from LLM
    pub fn parseResponse(self: *Self, json_bytes: []const u8) !provider.Response {
        return self.llm_provider.parseResponse(json_bytes);
    }

    /// Clear chat history
    pub fn clearHistory(self: *Self) void {
        for (self.chat_history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.chat_history.clearRetainingCapacity();
    }

    /// Get current history length in tokens
    pub fn getHistoryTokens(self: *Self) u32 {
        return provider.estimateMessagesTokens(self.chat_history.items);
    }

    /// Set max history tokens
    pub fn setMaxHistoryTokens(self: *Self, max_tokens: u32) void {
        self.max_history_tokens = max_tokens;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "memory tools schema" {
    const tools = LLM.getMemoryTools();
    try std.testing.expectEqual(@as(usize, 4), tools.len);
    try std.testing.expectEqualStrings("mem_get", tools[0].name);
    try std.testing.expectEqualStrings("mem_set", tools[1].name);
    try std.testing.expectEqualStrings("mem_append", tools[2].name);
    try std.testing.expectEqualStrings("mem_delete", tools[3].name);
}
