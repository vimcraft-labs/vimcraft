/// vim.ai.storage.* and vim.ai.providers.* - AI Infrastructure Layer
///
/// This module provides the INFRASTRUCTURE for AI features:
/// - Storage: Pattern persistence (LMDB + usearch vectors)
/// - Providers: LLM API abstractions (OpenAI, Anthropic, Ollama)
/// - Utilities: Token estimation
///
/// NOTE: This is NOT the "LLM-native primitives" layer from the spec.
/// The spec's vim.ai.native.* namespace is reserved for FUTURE work:
/// - Pattern Space (navigate, compose, introspect)
/// - Context Flow (embedding streams, attention)
/// - Reality Interface (perceive, actuate, feedback loops)
/// - Meta-Cognition (uncertainty, reasoning traces)
///
/// Error Handling Contract:
///   - Mutating operations (save, delete, configure): return boolean (true=success)
///   - Query operations (get, find, search): return null on error, [] for empty results
///   - All errors are logged internally for debugging
///   - Use vim.ai.utils.getLastError() to retrieve last error message
///
/// API:
///   vim.ai.storage.patterns.save(id, json, embedding?, tags, successRate) -> boolean
///   vim.ai.storage.patterns.get(id) -> string | null
///   vim.ai.storage.patterns.delete(id) -> boolean
///   vim.ai.storage.patterns.findByTag(tag) -> string[] | null
///   vim.ai.storage.patterns.stats() -> {vectorCount, vectorMemoryBytes, vectorCapacity} | null
///
///   NOTE: searchSimilar(embedding, k) is not yet implemented - requires usearch integration
///
///   vim.ai.storage.edges.add(from, rel, to, metadata) -> boolean
///   vim.ai.storage.edges.remove(from, rel, to) -> boolean
///   vim.ai.storage.edges.outgoing(from, rel?) -> Edge[] | null
///   vim.ai.storage.edges.incoming(to, rel?) -> Edge[] | null
///
///   vim.ai.storage.conversations.add(convId, timestamp, messageJson) -> boolean
///   vim.ai.storage.conversations.get(convId) -> string[] | null (messages in order)
///
///   vim.ai.providers.configure(config) -> boolean
///   vim.ai.providers.buildRequest(request) -> string | null
///   vim.ai.providers.parseResponse(json) -> Response | null
///   vim.ai.providers.getEndpoint() -> string | null
///   vim.ai.providers.getHeaders() -> {name, value}[] | null
///
///   vim.ai.utils.estimateTokens(text) -> number
///   vim.ai.utils.getLastError() -> string | null
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const c_api = @import("c_api.zig");
const c = c_api.c;

const storage = @import("../ai/storage/storage.zig");
const provider = @import("../ai/providers/provider.zig");

/// Context for AI storage/provider infrastructure API
pub const AiStorageApiContext = struct {
    allocator: Allocator,
    storage: ?*storage.AIStorage = null,
    provider: ?*provider.Provider = null,
    last_error: ?[]const u8 = null,

    // Owned copies of provider config strings (to avoid dangling pointers)
    provider_api_key: ?[]const u8 = null,
    provider_base_url: ?[]const u8 = null,

    /// Get or lazily initialize storage
    /// Storage is created on first access to avoid loading LMDB/usearch unless needed
    pub fn getOrInitStorage(self: *AiStorageApiContext) !*storage.AIStorage {
        if (self.storage) |s| return s;

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

        const store = try self.allocator.create(storage.AIStorage);
        errdefer self.allocator.destroy(store);

        store.* = try storage.AIStorage.init(self.allocator, .{
            .base_path = base_path,
            .vector_dimensions = 384, // Default for small embedding models
            .vector_capacity = 100_000,
        });

        self.storage = store;
        return store;
    }

    /// Set the last error message (clears previous)
    pub fn setError(self: *AiStorageApiContext, msg: []const u8) void {
        self.clearError();
        self.last_error = self.allocator.dupe(u8, msg) catch null;
    }

    /// Set error from Zig error code
    pub fn setErrorFromCode(self: *AiStorageApiContext, err: anyerror) void {
        self.setError(@errorName(err));
    }

    /// Clear any stored error
    pub fn clearError(self: *AiStorageApiContext) void {
        if (self.last_error) |old| {
            self.allocator.free(old);
            self.last_error = null;
        }
    }

    /// Clean up owned provider strings
    pub fn freeProviderStrings(self: *AiStorageApiContext) void {
        if (self.provider_api_key) |k| {
            self.allocator.free(k);
            self.provider_api_key = null;
        }
        if (self.provider_base_url) |u| {
            self.allocator.free(u);
            self.provider_base_url = null;
        }
    }
};

var global_ctx: ?*AiStorageApiContext = null;

/// Get context from JSI callback - fails explicitly if context is null
fn getContext(context: ?*anyopaque) ?*AiStorageApiContext {
    const ctx_ptr = context orelse return null;
    return @ptrCast(@alignCast(ctx_ptr));
}

// ============================================================================
// Patterns API - vim.ai.storage.patterns.*
// ============================================================================

fn patternsSave(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    // Clear previous error
    ctx.clearError();

    // Lazy-init storage
    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (count < 4) {
        ctx.setError("patternsSave requires 4 arguments: id, json, embedding, tags");
        return c.hermes_value_create_boolean(runtime, false);
    }

    // Get arguments: save(id, json, embedding?, tags, successRate?)
    var id_len: usize = 0;
    var json_len: usize = 0;
    const id = c.hermes_value_get_string(rt, args[0], &id_len) orelse {
        ctx.setError("id must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };
    const json_str = c.hermes_value_get_string(rt, args[1], &json_len) orelse {
        ctx.setError("json must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    const id_slice = id[0..id_len];
    const json_slice = json_str[0..json_len];

    // Parse embedding from args[2] (can be null or number array)
    var embedding_list: std.ArrayList(f32) = .empty;
    defer embedding_list.deinit(ctx.allocator);

    if (count >= 3) {
        const emb_val = args[2];
        if (emb_val != null and c.hermes_value_is_array(rt, emb_val)) {
            const emb_len = c.hermes_array_length(rt, emb_val);
            embedding_list.ensureTotalCapacity(ctx.allocator, emb_len) catch |err| {
                ctx.setErrorFromCode(err);
                return c.hermes_value_create_boolean(runtime, false);
            };

            var i: usize = 0;
            while (i < emb_len) : (i += 1) {
                const elem = c.hermes_array_get(rt, emb_val, i);
                if (c.hermes_value_is_number(elem)) {
                    embedding_list.append(ctx.allocator, @floatCast(c.hermes_value_get_number(elem))) catch |err| {
                        ctx.setErrorFromCode(err);
                        return c.hermes_value_create_boolean(runtime, false);
                    };
                }
            }
        }
    }

    const embedding: ?[]const f32 = if (embedding_list.items.len > 0) embedding_list.items else null;

    // Parse tags from args[3]
    var tags_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (tags_list.items) |t| ctx.allocator.free(t);
        tags_list.deinit(ctx.allocator);
    }

    if (count >= 4) {
        const tags_val = args[3] orelse {
            ctx.setError("tags must be an array");
            return c.hermes_value_create_boolean(runtime, false);
        };
        const tags_len = c.hermes_array_length(rt, tags_val);

        var i: usize = 0;
        while (i < tags_len) : (i += 1) {
            const tag_val = c.hermes_array_get(rt, tags_val, i);
            var tag_len: usize = 0;
            if (c.hermes_value_get_string(rt, tag_val, &tag_len)) |tag_str| {
                const duped = ctx.allocator.dupe(u8, tag_str[0..tag_len]) catch |err| {
                    ctx.setErrorFromCode(err);
                    return c.hermes_value_create_boolean(runtime, false);
                };
                tags_list.append(ctx.allocator, duped) catch |err| {
                    ctx.allocator.free(duped);
                    ctx.setErrorFromCode(err);
                    return c.hermes_value_create_boolean(runtime, false);
                };
            }
        }
    }

    // Parse success rate from args[4] (optional, default 0.5)
    const success_rate: f32 = if (count >= 5) blk: {
        const rate_val = args[4] orelse break :blk 0.5;
        break :blk @floatCast(c.hermes_value_get_number(rate_val));
    } else 0.5;

    store.savePattern(
        id_slice,
        json_slice,
        embedding,
        tags_list.items,
        success_rate,
    ) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

fn patternsGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };

    if (count < 1) {
        ctx.setError("patternsGet requires 1 argument: id");
        return null;
    }

    var id_len: usize = 0;
    const id = c.hermes_value_get_string(rt, args[0], &id_len) orelse {
        ctx.setError("id must be a string");
        return null;
    };
    const id_slice = id[0..id_len];

    const json = store.getPattern(id_slice) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer ctx.allocator.free(json);

    return c.hermes_value_create_string(rt, json.ptr, json.len);
}

fn patternsDelete(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (count < 1) {
        ctx.setError("patternsDelete requires 1 argument: id");
        return c.hermes_value_create_boolean(runtime, false);
    }

    var id_len: usize = 0;
    const id = c.hermes_value_get_string(rt, args[0], &id_len) orelse {
        ctx.setError("id must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };
    const id_slice = id[0..id_len];

    store.deletePattern(id_slice) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

fn patternsFindByTag(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };

    if (count < 1) {
        ctx.setError("patternsFindByTag requires 1 argument: tag");
        return null;
    }

    var tag_len: usize = 0;
    const tag = c.hermes_value_get_string(rt, args[0], &tag_len) orelse {
        ctx.setError("tag must be a string");
        return null;
    };
    const tag_slice = tag[0..tag_len];

    var results = store.findByTag(tag_slice) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer {
        for (results.items) |item| ctx.allocator.free(item);
        results.deinit(ctx.allocator);
    }

    const arr = c.hermes_array_create(rt, results.items.len);
    for (results.items, 0..) |item, i| {
        c.hermes_array_set(rt, arr, i, c.hermes_value_create_string(rt, item.ptr, item.len));
    }

    return arr;
}

fn patternsStats(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };

    const stats = store.getStats();

    const obj = c.hermes_value_create_object(rt);
    c.hermes_value_set_property(rt, obj, "vectorCount", c.hermes_value_create_number(rt, @floatFromInt(stats.vector_count)));
    c.hermes_value_set_property(rt, obj, "vectorMemoryBytes", c.hermes_value_create_number(rt, @floatFromInt(stats.vector_memory_bytes)));
    c.hermes_value_set_property(rt, obj, "vectorCapacity", c.hermes_value_create_number(rt, @floatFromInt(stats.vector_capacity)));

    return obj;
}

// ============================================================================
// Edges API - vim.ai.storage.edges.*
// ============================================================================

fn edgesAdd(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (count < 3) {
        ctx.setError("edgesAdd requires 3 arguments: from, relationship, to");
        return c.hermes_value_create_boolean(runtime, false);
    }

    var from_len: usize = 0;
    var rel_len: usize = 0;
    var to_len: usize = 0;
    const from = c.hermes_value_get_string(rt, args[0], &from_len) orelse {
        ctx.setError("from must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };
    const rel = c.hermes_value_get_string(rt, args[1], &rel_len) orelse {
        ctx.setError("relationship must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };
    const to = c.hermes_value_get_string(rt, args[2], &to_len) orelse {
        ctx.setError("to must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    var meta_len: usize = 0;
    const metadata = if (count >= 4)
        if (c.hermes_value_get_string(rt, args[3], &meta_len)) |m| m[0..meta_len] else "{}"
    else
        "{}";

    store.addEdge(from[0..from_len], rel[0..rel_len], to[0..to_len], metadata) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

fn edgesRemove(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (count < 3) {
        ctx.setError("edgesRemove requires 3 arguments: from, relationship, to");
        return c.hermes_value_create_boolean(runtime, false);
    }

    var from_len: usize = 0;
    var rel_len: usize = 0;
    var to_len: usize = 0;
    const from = c.hermes_value_get_string(rt, args[0], &from_len) orelse {
        ctx.setError("from must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };
    const rel = c.hermes_value_get_string(rt, args[1], &rel_len) orelse {
        ctx.setError("relationship must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };
    const to = c.hermes_value_get_string(rt, args[2], &to_len) orelse {
        ctx.setError("to must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    store.removeEdge(from[0..from_len], rel[0..rel_len], to[0..to_len]) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

fn edgesOutgoing(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };

    if (count < 1) {
        ctx.setError("edgesOutgoing requires 1 argument: from");
        return null;
    }

    var from_len: usize = 0;
    const from = c.hermes_value_get_string(rt, args[0], &from_len) orelse {
        ctx.setError("from must be a string");
        return null;
    };
    var rel_len: usize = 0;
    const rel: ?[]const u8 = if (count >= 2)
        if (c.hermes_value_get_string(rt, args[1], &rel_len)) |r| r[0..rel_len] else null
    else
        null;

    var edges = store.getOutgoingEdges(from[0..from_len], rel) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer {
        for (edges.items) |*e| e.deinit(ctx.allocator);
        edges.deinit(ctx.allocator);
    }

    const arr = c.hermes_array_create(rt, edges.items.len);
    for (edges.items, 0..) |edge, i| {
        const obj = c.hermes_value_create_object(rt);
        c.hermes_value_set_property(rt, obj, "from", c.hermes_value_create_string(rt, edge.from.ptr, edge.from.len));
        c.hermes_value_set_property(rt, obj, "relationship", c.hermes_value_create_string(rt, edge.relationship.ptr, edge.relationship.len));
        c.hermes_value_set_property(rt, obj, "to", c.hermes_value_create_string(rt, edge.to.ptr, edge.to.len));
        c.hermes_value_set_property(rt, obj, "metadata", c.hermes_value_create_string(rt, edge.metadata.ptr, edge.metadata.len));
        c.hermes_array_set(rt, arr, i, obj);
    }

    return arr;
}

fn edgesIncoming(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };

    if (count < 1) {
        ctx.setError("edgesIncoming requires 1 argument: to");
        return null;
    }

    var to_len: usize = 0;
    const to = c.hermes_value_get_string(rt, args[0], &to_len) orelse {
        ctx.setError("to must be a string");
        return null;
    };
    var rel_len: usize = 0;
    const rel: ?[]const u8 = if (count >= 2)
        if (c.hermes_value_get_string(rt, args[1], &rel_len)) |r| r[0..rel_len] else null
    else
        null;

    var edges = store.getIncomingEdges(to[0..to_len], rel) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer {
        for (edges.items) |*e| e.deinit(ctx.allocator);
        edges.deinit(ctx.allocator);
    }

    const arr = c.hermes_array_create(rt, edges.items.len);
    for (edges.items, 0..) |edge, i| {
        const obj = c.hermes_value_create_object(rt);
        c.hermes_value_set_property(rt, obj, "from", c.hermes_value_create_string(rt, edge.from.ptr, edge.from.len));
        c.hermes_value_set_property(rt, obj, "relationship", c.hermes_value_create_string(rt, edge.relationship.ptr, edge.relationship.len));
        c.hermes_value_set_property(rt, obj, "to", c.hermes_value_create_string(rt, edge.to.ptr, edge.to.len));
        c.hermes_value_set_property(rt, obj, "metadata", c.hermes_value_create_string(rt, edge.metadata.ptr, edge.metadata.len));
        c.hermes_array_set(rt, arr, i, obj);
    }

    return arr;
}

// ============================================================================
// Conversations API - vim.ai.storage.conversations.*
// ============================================================================

fn conversationsAdd(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    if (count < 3) {
        ctx.setError("conversationsAdd requires 3 arguments: convId, timestamp, messageJson");
        return c.hermes_value_create_boolean(runtime, false);
    }

    var conv_id_len: usize = 0;
    const conv_id = c.hermes_value_get_string(rt, args[0], &conv_id_len) orelse {
        ctx.setError("convId must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    // Timestamp as number (milliseconds since epoch)
    const ts_val = args[1] orelse {
        ctx.setError("timestamp is required");
        return c.hermes_value_create_boolean(runtime, false);
    };
    if (!c.hermes_value_is_number(ts_val)) {
        ctx.setError("timestamp must be a number");
        return c.hermes_value_create_boolean(runtime, false);
    }
    const ts_float = c.hermes_value_get_number(ts_val);
    // Validate timestamp range (must be positive, finite, and within i64 range)
    if (ts_float < 0 or ts_float != ts_float or ts_float == std.math.inf(f64) or ts_float == -std.math.inf(f64)) {
        ctx.setError("timestamp must be a positive finite number");
        return c.hermes_value_create_boolean(runtime, false);
    }
    if (ts_float > @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        ctx.setError("timestamp exceeds maximum safe integer");
        return c.hermes_value_create_boolean(runtime, false);
    }
    const timestamp: i64 = @intFromFloat(ts_float);

    var message_len: usize = 0;
    const message = c.hermes_value_get_string(rt, args[2], &message_len) orelse {
        ctx.setError("messageJson must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    store.addMessage(conv_id[0..conv_id_len], timestamp, message[0..message_len]) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    return c.hermes_value_create_boolean(runtime, true);
}

fn conversationsGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var store = ctx.getOrInitStorage() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };

    if (count < 1) {
        ctx.setError("conversationsGet requires 1 argument: convId");
        return null;
    }

    var conv_id_len: usize = 0;
    const conv_id = c.hermes_value_get_string(rt, args[0], &conv_id_len) orelse {
        ctx.setError("convId must be a string");
        return null;
    };

    var messages = store.getMessages(conv_id[0..conv_id_len]) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer {
        for (messages.items) |m| ctx.allocator.free(m);
        messages.deinit(ctx.allocator);
    }

    const arr = c.hermes_array_create(rt, messages.items.len);
    for (messages.items, 0..) |msg, i| {
        c.hermes_array_set(rt, arr, i, c.hermes_value_create_string(rt, msg.ptr, msg.len));
    }

    return arr;
}

// ============================================================================
// Provider API - vim.ai.providers.*
// ============================================================================

fn providerConfigure(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return c.hermes_value_create_boolean(runtime, false);
    const ctx = getContext(context) orelse return c.hermes_value_create_boolean(runtime, false);

    ctx.clearError();

    if (count < 1) {
        ctx.setError("providerConfigure requires 1 argument: config object");
        return c.hermes_value_create_boolean(runtime, false);
    }

    const config_val = args[0] orelse {
        ctx.setError("config must be an object");
        return c.hermes_value_create_boolean(runtime, false);
    };

    // Get provider type
    const provider_str_val = c.hermes_value_get_property(rt, config_val, "provider");
    var provider_str_len: usize = 0;
    const provider_str = c.hermes_value_get_string(rt, provider_str_val, &provider_str_len) orelse {
        ctx.setError("config.provider must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    const provider_type: provider.ProviderType = blk: {
        const s = provider_str[0..provider_str_len];
        if (std.mem.eql(u8, s, "openai")) break :blk .openai;
        if (std.mem.eql(u8, s, "anthropic")) break :blk .anthropic;
        if (std.mem.eql(u8, s, "ollama")) break :blk .ollama;
        break :blk .custom;
    };

    // Get API key - CRITICAL: dupe this to avoid dangling pointer
    const api_key_val = c.hermes_value_get_property(rt, config_val, "apiKey");
    var api_key_len: usize = 0;
    const api_key_jsi = c.hermes_value_get_string(rt, api_key_val, &api_key_len) orelse {
        ctx.setError("config.apiKey must be a string");
        return c.hermes_value_create_boolean(runtime, false);
    };

    // Get optional base URL - CRITICAL: dupe this to avoid dangling pointer
    const base_url_val = c.hermes_value_get_property(rt, config_val, "baseUrl");
    var base_url_len: usize = 0;
    const base_url_jsi: ?[]const u8 = if (c.hermes_value_get_string(rt, base_url_val, &base_url_len)) |u| u[0..base_url_len] else null;

    // Clean up old provider and owned strings
    if (ctx.provider) |p| {
        var mut_p = p;
        mut_p.deinit();
        ctx.allocator.destroy(p);
        ctx.provider = null;
    }
    ctx.freeProviderStrings();

    // Dupe the strings to owned copies BEFORE creating provider
    const api_key_owned = ctx.allocator.dupe(u8, api_key_jsi[0..api_key_len]) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };
    errdefer ctx.allocator.free(api_key_owned);

    const base_url_owned: ?[]const u8 = if (base_url_jsi) |u| blk: {
        const duped = ctx.allocator.dupe(u8, u) catch |err| {
            ctx.setErrorFromCode(err);
            return c.hermes_value_create_boolean(runtime, false);
        };
        break :blk duped;
    } else null;
    errdefer if (base_url_owned) |u| ctx.allocator.free(u);

    // Create new provider with owned strings
    const prov = ctx.allocator.create(provider.Provider) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };
    errdefer ctx.allocator.destroy(prov);

    prov.* = provider.Provider.init(ctx.allocator, .{
        .provider = provider_type,
        .api_key = api_key_owned,
        .base_url = base_url_owned,
    }) catch |err| {
        ctx.setErrorFromCode(err);
        return c.hermes_value_create_boolean(runtime, false);
    };

    // Store owned strings in context for later cleanup
    ctx.provider_api_key = api_key_owned;
    ctx.provider_base_url = base_url_owned;
    ctx.provider = prov;

    return c.hermes_value_create_boolean(runtime, true);
}

fn providerBuildRequest(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var prov = ctx.provider orelse {
        ctx.setError("provider not configured - call configure() first");
        return null;
    };

    if (count < 1) {
        ctx.setError("buildRequest requires 1 argument: request object");
        return null;
    }

    const request_val = args[0] orelse {
        ctx.setError("request must be an object");
        return null;
    };

    // Get model
    const model_val = c.hermes_value_get_property(rt, request_val, "model");
    var model_len: usize = 0;
    const model = c.hermes_value_get_string(rt, model_val, &model_len) orelse {
        ctx.setError("request.model must be a string");
        return null;
    };

    // Get messages array
    const messages_val = c.hermes_value_get_property(rt, request_val, "messages");
    const messages_len = c.hermes_array_length(rt, messages_val);

    var messages: std.ArrayList(provider.Message) = .empty;
    defer {
        for (messages.items) |*m| m.deinit(ctx.allocator);
        messages.deinit(ctx.allocator);
    }

    var i: usize = 0;
    while (i < messages_len) : (i += 1) {
        const msg_val = c.hermes_array_get(rt, messages_val, i);

        const role_val = c.hermes_value_get_property(rt, msg_val, "role");
        var role_str_len: usize = 0;
        const role_str = c.hermes_value_get_string(rt, role_val, &role_str_len) orelse continue;
        const role = provider.Role.fromString(role_str[0..role_str_len]) orelse continue;

        const content_val = c.hermes_value_get_property(rt, msg_val, "content");
        var content_len: usize = 0;
        const content = c.hermes_value_get_string(rt, content_val, &content_len) orelse continue;

        const content_owned = ctx.allocator.dupe(u8, content[0..content_len]) catch |err| {
            ctx.setErrorFromCode(err);
            return null;
        };
        messages.append(ctx.allocator, .{
            .role = role,
            .content = content_owned,
        }) catch |err| {
            ctx.allocator.free(content_owned); // Don't leak on append failure
            ctx.setErrorFromCode(err);
            return null;
        };
    }

    // Get optional temperature
    const temp_val = c.hermes_value_get_property(rt, request_val, "temperature");
    const temperature: f32 = if (c.hermes_value_is_number(temp_val))
        @floatCast(c.hermes_value_get_number(temp_val))
    else
        1.0;

    // Get optional max_tokens (clamp to u32 range)
    const max_val = c.hermes_value_get_property(rt, request_val, "maxTokens");
    const max_tokens: ?u32 = if (c.hermes_value_is_number(max_val)) blk: {
        const val = c.hermes_value_get_number(max_val);
        if (val <= 0 or val != val) break :blk null; // negative, zero, or NaN
        if (val > @as(f64, @floatFromInt(std.math.maxInt(u32)))) break :blk std.math.maxInt(u32);
        break :blk @intFromFloat(val);
    } else null;

    // Get optional stream
    const stream_val = c.hermes_value_get_property(rt, request_val, "stream");
    const stream = c.hermes_value_is_boolean(stream_val) and c.hermes_value_get_boolean(stream_val);

    const request = provider.Request{
        .model = model[0..model_len],
        .messages = messages.items,
        .temperature = temperature,
        .max_tokens = max_tokens,
        .stream = stream,
    };

    const json = prov.buildRequestJson(request) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer ctx.allocator.free(json);

    return c.hermes_value_create_string(rt, json.ptr, json.len);
}

fn providerGetEndpoint(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var prov = ctx.provider orelse {
        ctx.setError("provider not configured - call configure() first");
        return null;
    };

    const endpoint = prov.getChatEndpoint() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer ctx.allocator.free(endpoint);

    return c.hermes_value_create_string(rt, endpoint.ptr, endpoint.len);
}

fn providerGetHeaders(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var prov = ctx.provider orelse {
        ctx.setError("provider not configured - call configure() first");
        return null;
    };

    const headers = prov.getHeaders() catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer ctx.allocator.free(headers);

    const arr = c.hermes_array_create(rt, headers.len);
    for (headers, 0..) |h, i| {
        const obj = c.hermes_value_create_object(rt);
        c.hermes_value_set_property(rt, obj, "name", c.hermes_value_create_string(rt, h.name.ptr, h.name.len));
        c.hermes_value_set_property(rt, obj, "value", c.hermes_value_create_string(rt, h.value.ptr, h.value.len));
        c.hermes_array_set(rt, arr, i, obj);
    }

    return arr;
}

fn providerParseResponse(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const ctx = getContext(context) orelse return null;

    ctx.clearError();

    var prov = ctx.provider orelse {
        ctx.setError("provider not configured - call configure() first");
        return null;
    };

    if (count < 1) {
        ctx.setError("parseResponse requires 1 argument: json string");
        return null;
    }

    const json_val = args[0] orelse {
        ctx.setError("json must be a string");
        return null;
    };
    var json_len: usize = 0;
    const json = c.hermes_value_get_string(rt, json_val, &json_len) orelse {
        ctx.setError("json must be a string");
        return null;
    };

    var response = prov.parseResponse(json[0..json_len]) catch |err| {
        ctx.setErrorFromCode(err);
        return null;
    };
    defer response.deinit();

    const obj = c.hermes_value_create_object(rt);
    c.hermes_value_set_property(rt, obj, "id", c.hermes_value_create_string(rt, response.id.ptr, response.id.len));
    c.hermes_value_set_property(rt, obj, "model", c.hermes_value_create_string(rt, response.model.ptr, response.model.len));

    if (response.content) |content| {
        c.hermes_value_set_property(rt, obj, "content", c.hermes_value_create_string(rt, content.ptr, content.len));
    }

    const finish_str: []const u8 = switch (response.finish_reason) {
        .stop => "stop",
        .length => "length",
        .tool_calls => "tool_calls",
        .content_filter => "content_filter",
        .unknown => "unknown",
    };
    c.hermes_value_set_property(rt, obj, "finishReason", c.hermes_value_create_string(rt, finish_str.ptr, finish_str.len));

    // Usage
    const usage_obj = c.hermes_value_create_object(rt);
    c.hermes_value_set_property(rt, usage_obj, "promptTokens", c.hermes_value_create_number(rt, @floatFromInt(response.usage.prompt_tokens)));
    c.hermes_value_set_property(rt, usage_obj, "completionTokens", c.hermes_value_create_number(rt, @floatFromInt(response.usage.completion_tokens)));
    c.hermes_value_set_property(rt, usage_obj, "totalTokens", c.hermes_value_create_number(rt, @floatFromInt(response.usage.total_tokens)));
    c.hermes_value_set_property(rt, obj, "usage", usage_obj);

    return obj;
}

// ============================================================================
// Utility API - vim.ai.utils.*
// ============================================================================

fn estimateTokens(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Pure utility function - no context needed
    _ = context;

    const rt = runtime orelse return c.hermes_value_create_number(runtime, 0);

    if (count < 1) return c.hermes_value_create_number(runtime, 0);

    var text_len: usize = 0;
    const text = c.hermes_value_get_string(rt, args[0], &text_len) orelse return c.hermes_value_create_number(runtime, 0);
    const tokens = provider.estimateTokens(text[0..text_len]);

    return c.hermes_value_create_number(runtime, @floatFromInt(tokens));
}

fn getLastError(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return c.hermes_value_create_null(runtime);
    const ctx = getContext(context) orelse return c.hermes_value_create_null(rt);

    if (ctx.last_error) |err| {
        return c.hermes_value_create_string(rt, err.ptr, err.len);
    }

    return c.hermes_value_create_null(rt);
}

// ============================================================================
// HostObject Getters
// ============================================================================

/// vim.ai.storage.patterns.* HostObject getter
pub export fn aiStoragePatternsHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "save", patternsSave },
        .{ "get", patternsGet },
        .{ "delete", patternsDelete },
        .{ "findByTag", patternsFindByTag },
        .{ "stats", patternsStats },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

/// vim.ai.storage.edges.* HostObject getter
pub export fn aiStorageEdgesHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "add", edgesAdd },
        .{ "remove", edgesRemove },
        .{ "outgoing", edgesOutgoing },
        .{ "incoming", edgesIncoming },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

/// vim.ai.storage.conversations.* HostObject getter
pub export fn aiStorageConversationsHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "add", conversationsAdd },
        .{ "get", conversationsGet },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

/// vim.ai.providers.* HostObject getter
pub export fn aiProvidersHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "configure", providerConfigure },
        .{ "buildRequest", providerBuildRequest },
        .{ "getEndpoint", providerGetEndpoint },
        .{ "getHeaders", providerGetHeaders },
        .{ "parseResponse", providerParseResponse },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

/// vim.ai.utils.* HostObject getter
pub export fn aiUtilsHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "estimateTokens", estimateTokens },
        .{ "getLastError", getLastError },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, ctx: *AiStorageApiContext) void {
    global_ctx = ctx;

    // Register vim.ai.storage.patterns
    c.hermes_register_host_object(
        runtime,
        "__aiStoragePatterns",
        aiStoragePatternsHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );

    // Register vim.ai.storage.edges
    c.hermes_register_host_object(
        runtime,
        "__aiStorageEdges",
        aiStorageEdgesHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );

    // Register vim.ai.storage.conversations
    c.hermes_register_host_object(
        runtime,
        "__aiStorageConversations",
        aiStorageConversationsHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );

    // Register vim.ai.providers
    c.hermes_register_host_object(
        runtime,
        "__aiProviders",
        aiProvidersHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );

    // Register vim.ai.utils
    c.hermes_register_host_object(
        runtime,
        "__aiUtils",
        aiUtilsHostObjectGet,
        null,
        null,
        @ptrCast(ctx),
    );
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        // Clean up storage if initialized
        if (ctx.storage) |s| {
            s.deinit();
            ctx.allocator.destroy(s);
            ctx.storage = null;
        }
        // Clean up provider if initialized
        if (ctx.provider) |p| {
            var mut_p = p;
            mut_p.deinit();
            ctx.allocator.destroy(p);
            ctx.provider = null;
        }
        // Clean up owned provider strings
        ctx.freeProviderStrings();
        // Clean up last error if set
        ctx.clearError();

        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}
