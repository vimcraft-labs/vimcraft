/// vim.ai.chat - Conversation History Management
///
/// Manages chat sessions with automatic summarization when history grows too long.
/// Integrates with llm.zig for summarization and mem.zig for context.
///
/// Features:
///   - Multiple named sessions
///   - Auto-summarize when token budget exceeded
///   - Message threading and context preservation
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const llm = @import("llm.zig");
const mem = @import("mem.zig");
const provider = @import("providers/provider.zig");

/// A single message in a conversation
pub const Message = struct {
    role: Role,
    content: []const u8,
    timestamp: i64,
    id: u64,

    pub const Role = enum {
        user,
        assistant,
        system,
        summary,
    };

    pub fn deinit(self: *Message, allocator: Allocator) void {
        allocator.free(self.content);
    }

    pub fn estimateTokens(self: *const Message) u32 {
        // ~4 chars per token
        return @intCast(@max(1, self.content.len / 4));
    }
};

/// A conversation session
pub const Session = struct {
    allocator: Allocator,
    id: []const u8,
    messages: std.ArrayList(Message),
    summaries: std.ArrayList([]const u8),
    max_tokens: u32,
    next_msg_id: u64,
    created_at: i64,
    last_activity: i64,

    const Self = @This();

    pub fn init(allocator: Allocator, id: []const u8) !Self {
        return .{
            .allocator = allocator,
            .id = try allocator.dupe(u8, id),
            .messages = .empty,
            .summaries = .empty,
            .max_tokens = 8192, // Default history budget
            .next_msg_id = 1,
            .created_at = std.time.timestamp(),
            .last_activity = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);

        for (self.summaries.items) |s| {
            self.allocator.free(s);
        }
        self.summaries.deinit(self.allocator);

        self.allocator.free(self.id);
    }

    /// Add a user message
    pub fn addUserMessage(self: *Self, content: []const u8) !u64 {
        const msg_id = self.next_msg_id;
        self.next_msg_id += 1;

        try self.messages.append(self.allocator, .{
            .role = .user,
            .content = try self.allocator.dupe(u8, content),
            .timestamp = std.time.timestamp(),
            .id = msg_id,
        });

        self.last_activity = std.time.timestamp();
        return msg_id;
    }

    /// Add an assistant message
    pub fn addAssistantMessage(self: *Self, content: []const u8) !u64 {
        const msg_id = self.next_msg_id;
        self.next_msg_id += 1;

        try self.messages.append(self.allocator, .{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, content),
            .timestamp = std.time.timestamp(),
            .id = msg_id,
        });

        self.last_activity = std.time.timestamp();
        return msg_id;
    }

    /// Add a system message
    pub fn addSystemMessage(self: *Self, content: []const u8) !u64 {
        const msg_id = self.next_msg_id;
        self.next_msg_id += 1;

        try self.messages.append(self.allocator, .{
            .role = .system,
            .content = try self.allocator.dupe(u8, content),
            .timestamp = std.time.timestamp(),
            .id = msg_id,
        });

        self.last_activity = std.time.timestamp();
        return msg_id;
    }

    /// Get total token count
    pub fn getTokenCount(self: *const Self) u32 {
        var total: u32 = 0;
        for (self.messages.items) |*msg| {
            total += msg.estimateTokens();
        }
        return total;
    }

    /// Check if summarization is needed
    pub fn needsSummarization(self: *const Self) bool {
        return self.getTokenCount() > self.max_tokens;
    }

    /// Get messages as provider messages for LLM call
    pub fn toProviderMessages(self: *const Self, allocator: Allocator) ![]provider.Message {
        var result: std.ArrayList(provider.Message) = .empty;
        errdefer {
            for (result.items) |*m| m.deinit(allocator);
            result.deinit(allocator);
        }

        // Add summaries first as system messages
        for (self.summaries.items) |summary| {
            try result.append(allocator, .{
                .role = .system,
                .content = try allocator.dupe(u8, summary),
            });
        }

        // Add recent messages
        for (self.messages.items) |*msg| {
            const role: provider.Role = switch (msg.role) {
                .user => .user,
                .assistant => .assistant,
                .system, .summary => .system,
            };
            try result.append(allocator, .{
                .role = role,
                .content = try allocator.dupe(u8, msg.content),
            });
        }

        return result.toOwnedSlice(allocator);
    }

    /// Clear all messages
    pub fn clear(self: *Self) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.clearRetainingCapacity();

        for (self.summaries.items) |s| {
            self.allocator.free(s);
        }
        self.summaries.clearRetainingCapacity();
    }

    /// Summarize old messages (called by Chat manager with LLM)
    pub fn applySummary(self: *Self, summary: []const u8, messages_to_remove: usize) !void {
        // Store the summary
        try self.summaries.append(self.allocator, try self.allocator.dupe(u8, summary));

        // Remove old messages
        const remove_count = @min(messages_to_remove, self.messages.items.len);
        for (0..remove_count) |_| {
            var removed = self.messages.orderedRemove(0);
            removed.deinit(self.allocator);
        }
    }

    /// Get message by ID
    pub fn getMessageById(self: *const Self, id: u64) ?*const Message {
        for (self.messages.items) |*msg| {
            if (msg.id == id) return msg;
        }
        return null;
    }

    /// Get last N messages
    pub fn getLastMessages(self: *const Self, n: usize) []const Message {
        if (n >= self.messages.items.len) {
            return self.messages.items;
        }
        return self.messages.items[self.messages.items.len - n ..];
    }

    /// Export to JSON
    pub fn toJson(self: *const Self, allocator: Allocator) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);

        const writer = result.writer(allocator);
        try writer.print("{{\"id\":{any},\"messages\":[", .{std.json.fmt(self.id, .{})});

        for (self.messages.items, 0..) |*msg, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"id\":{d},\"role\":\"{s}\",\"content\":{any},\"timestamp\":{d}}}", .{
                msg.id,
                @tagName(msg.role),
                std.json.fmt(msg.content, .{}),
                msg.timestamp,
            });
        }

        try writer.print("],\"created_at\":{d},\"last_activity\":{d}}}", .{
            self.created_at,
            self.last_activity,
        });

        return result.toOwnedSlice(allocator);
    }
};

/// Chat manager - handles multiple sessions
pub const Chat = struct {
    allocator: Allocator,
    sessions: std.StringHashMap(Session),
    active_session: ?[]const u8,
    memory: ?*mem.Memory,
    llm_instance: ?*llm.LLM,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .sessions = std.StringHashMap(Session).init(allocator),
            .active_session = null,
            .memory = null,
            .llm_instance = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            var session = entry.value_ptr;
            session.deinit();
        }
        self.sessions.deinit();
        if (self.active_session) |s| {
            self.allocator.free(s);
        }
    }

    /// Set memory reference for context integration
    pub fn setMemory(self: *Self, memory: *mem.Memory) void {
        self.memory = memory;
    }

    /// Set LLM reference for summarization
    pub fn setLlm(self: *Self, llm_instance: *llm.LLM) void {
        self.llm_instance = llm_instance;
    }

    /// Create or get a session
    pub fn getOrCreateSession(self: *Self, id: []const u8) !*Session {
        if (self.sessions.getPtr(id)) |session| {
            return session;
        }

        // Create new session - Session.init dupes the id internally
        var session = try Session.init(self.allocator, id);
        errdefer session.deinit();

        // Use session's owned id as HashMap key (single allocation, no leak)
        try self.sessions.put(session.id, session);

        return self.sessions.getPtr(session.id).?;
    }

    /// Get existing session
    pub fn getSession(self: *Self, id: []const u8) ?*Session {
        return self.sessions.getPtr(id);
    }

    /// Delete a session
    /// Note: kv.key points to session.id (same allocation), so only call session.deinit()
    pub fn deleteSession(self: *Self, id: []const u8) bool {
        if (self.sessions.fetchRemove(id)) |kv| {
            // Clear active_session if it points to the deleted session
            if (self.active_session) |active| {
                if (std.mem.eql(u8, active, id)) {
                    self.allocator.free(active);
                    self.active_session = null;
                }
            }
            // kv.key == session.id (same memory), session.deinit() frees it
            var session = kv.value;
            session.deinit();
            return true;
        }
        return false;
    }

    /// Set active session
    pub fn setActiveSession(self: *Self, id: []const u8) !void {
        if (self.active_session) |s| {
            self.allocator.free(s);
        }
        self.active_session = try self.allocator.dupe(u8, id);
    }

    /// Get active session
    pub fn getActiveSession(self: *Self) ?*Session {
        if (self.active_session) |id| {
            return self.sessions.getPtr(id);
        }
        return null;
    }

    /// List all session IDs
    pub fn listSessions(self: *Self) ![][]const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        errdefer {
            // Free any already-duped strings on error
            for (list.items) |s| self.allocator.free(s);
            list.deinit(self.allocator);
        }

        var it = self.sessions.keyIterator();
        while (it.next()) |key| {
            try list.append(self.allocator, try self.allocator.dupe(u8, key.*));
        }

        return list.toOwnedSlice(self.allocator);
    }

    /// Add user message to active session
    pub fn addUserMessage(self: *Self, content: []const u8) !u64 {
        const session = self.getActiveSession() orelse blk: {
            // Auto-create default session and use it directly (no recursion)
            const new_session = try self.getOrCreateSession("default");
            try self.setActiveSession("default");
            break :blk new_session;
        };
        return session.addUserMessage(content);
    }

    /// Add assistant message to active session
    pub fn addAssistantMessage(self: *Self, content: []const u8) !u64 {
        const session = self.getActiveSession() orelse return error.NoActiveSession;
        return session.addAssistantMessage(content);
    }

    /// Check if active session needs summarization
    pub fn needsSummarization(self: *Self) bool {
        const session = self.getActiveSession() orelse return false;
        return session.needsSummarization();
    }

    /// Build summarization prompt
    fn buildSummarizationPrompt(self: *Self, session: *Session) ![]const u8 {
        _ = self;
        var prompt: std.ArrayList(u8) = .empty;
        errdefer prompt.deinit(session.allocator);

        const writer = prompt.writer(session.allocator);
        try writer.writeAll("Summarize the following conversation concisely, preserving key information and context:\n\n");

        // Take first half of messages for summarization
        const count = session.messages.items.len / 2;
        for (session.messages.items[0..count]) |*msg| {
            try writer.print("[{s}]: {s}\n\n", .{ @tagName(msg.role), msg.content });
        }

        try writer.writeAll("\nProvide a concise summary (2-3 paragraphs) that captures the essential context.");

        return prompt.toOwnedSlice(session.allocator);
    }

    /// Perform summarization on active session
    /// Returns the summary text if successful
    pub fn summarizeIfNeeded(self: *Self) !?[]const u8 {
        const session = self.getActiveSession() orelse return null;
        if (!session.needsSummarization()) return null;

        const llm_inst = self.llm_instance orelse return error.NoLlmConfigured;

        // Build summarization prompt
        const prompt = try self.buildSummarizationPrompt(session);
        defer self.allocator.free(prompt);

        // Request summarization from LLM
        const request_json = try llm_inst.buildRequestJson("gpt-4o-mini", prompt);
        defer self.allocator.free(request_json);

        // Note: Actual HTTP call would happen in JS layer
        // This returns the request JSON for the JS layer to execute
        // For now, return the prompt to indicate summarization is needed
        return try self.allocator.dupe(u8, prompt);
    }

    /// Get active session token count
    pub fn getTokenCount(self: *Self) u32 {
        const session = self.getActiveSession() orelse return 0;
        return session.getTokenCount();
    }

    /// Clear active session
    pub fn clearActiveSession(self: *Self) void {
        if (self.getActiveSession()) |session| {
            session.clear();
        }
    }

    /// Export active session to JSON
    pub fn exportActiveSession(self: *Self) !?[]const u8 {
        const session = self.getActiveSession() orelse return null;
        const json = try session.toJson(self.allocator);
        return json;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "session basic operations" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "test-session");
    defer session.deinit();

    const id1 = try session.addUserMessage("Hello");
    const id2 = try session.addAssistantMessage("Hi there!");

    try std.testing.expectEqual(@as(u64, 1), id1);
    try std.testing.expectEqual(@as(u64, 2), id2);
    try std.testing.expectEqual(@as(usize, 2), session.messages.items.len);

    const msg = session.getMessageById(1);
    try std.testing.expect(msg != null);
    try std.testing.expectEqualStrings("Hello", msg.?.content);
}

test "session token estimation" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "test");
    defer session.deinit();

    // Add some messages
    _ = try session.addUserMessage("This is a test message with some content");
    _ = try session.addAssistantMessage("Here is a response");

    const tokens = session.getTokenCount();
    try std.testing.expect(tokens > 0);
}

test "chat manager sessions" {
    const allocator = std.testing.allocator;

    var chat = Chat.init(allocator);
    defer chat.deinit();

    // Create sessions
    const s1 = try chat.getOrCreateSession("session1");
    _ = try chat.getOrCreateSession("session2");

    _ = try s1.addUserMessage("Hello in session 1");

    // List sessions
    const sessions = try chat.listSessions();
    defer {
        for (sessions) |s| allocator.free(s);
        allocator.free(sessions);
    }

    try std.testing.expectEqual(@as(usize, 2), sessions.len);

    // Set active and add message
    try chat.setActiveSession("session1");
    const msg_id = try chat.addAssistantMessage("Response in session 1");
    try std.testing.expectEqual(@as(u64, 2), msg_id);

    // Delete session
    try std.testing.expect(chat.deleteSession("session2"));
    try std.testing.expect(!chat.deleteSession("nonexistent"));
}

test "session json export" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "test-export");
    defer session.deinit();

    _ = try session.addUserMessage("Test message");

    const json = try session.toJson(allocator);
    defer allocator.free(json);

    // Basic JSON validation
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"test-export\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"messages\":") != null);
}
