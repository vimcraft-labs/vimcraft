/// AI Storage - Unified Storage Layer
///
/// Combines LMDB (key-value) + usearch (vectors) for AI primitives storage.
/// Uses DynamoDB-style key design patterns for flexible NoSQL queries.
///
/// Key Schema:
///   pattern:{id}               → {JSON document}
///   idx:tag:{tag}:{id}         → "" (secondary index)
///   idx:success:{rate}:{id}    → "" (success rate index)
///   vec:{id}                   → {vector_key} (vector reference)
///   veckey:{vector_key}        → {id} (reverse lookup for similarity search)
///   edge:{from}:{rel}:{to}     → {metadata JSON}
///   redge:{to}:{rel}:{from}    → "" (reverse index)
///   conv:{id}                  → {conversation metadata}
///   conv:{id}:msg:{ts}         → {message JSON}
///
const std = @import("std");
const Allocator = std.mem.Allocator;
const lmdb = @import("lmdb.zig");
const vectors = @import("vectors.zig");

pub const StorageError = error{
    NotFound,
    SerializationFailed,
    VectorDimensionMismatch,
    InvalidKey,
    InvalidPath,
    AlreadyExists,
} || lmdb.LmdbError || vectors.VectorError || std.mem.Allocator.Error;

/// Schema version for future migrations
const SCHEMA_VERSION: u32 = 1;

/// AI Storage configuration
pub const Config = struct {
    /// Path to storage directory (will be duped)
    base_path: []const u8,
    /// Maximum LMDB size in MB (default 256MB)
    max_db_size_mb: usize = 256,
    /// Vector dimensions (for embeddings, typically 1536 for OpenAI, 384 for small models)
    vector_dimensions: usize = 384,
    /// Vector index capacity
    vector_capacity: usize = 100_000,
    /// Vector similarity metric
    vector_metric: vectors.Metric = .cosine,
};

/// Unified AI Storage
pub const AIStorage = struct {
    db: lmdb.Env,
    vec: vectors.VectorIndex,
    allocator: Allocator,
    base_path: []const u8, // Owned copy
    vector_dimensions: usize,

    const Self = @This();

    /// Initialize AI storage
    pub fn init(allocator: Allocator, config: Config) !Self {
        // Own the base path to avoid lifetime issues
        const base_path = try allocator.dupe(u8, config.base_path);
        errdefer allocator.free(base_path);

        // Create base directory
        std.fs.makeDirAbsolute(base_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return StorageError.InvalidPath,
        };

        // Initialize LMDB
        const db_path = try std.fs.path.join(allocator, &.{ base_path, "data" });
        defer allocator.free(db_path);

        var db = try lmdb.Env.init(allocator, db_path, config.max_db_size_mb);
        errdefer db.deinit();

        // Store schema version
        db.put("_meta:version", std.fmt.comptimePrint("{d}", .{SCHEMA_VERSION})) catch {};

        // Initialize vector index
        var vec = try vectors.VectorIndex.init(allocator, .{
            .dimensions = config.vector_dimensions,
            .capacity = config.vector_capacity,
            .metric = config.vector_metric,
        });
        errdefer vec.deinit();

        // Try to load existing vector index
        const vec_path = try std.fs.path.join(allocator, &.{ base_path, "vectors.usearch" });
        defer allocator.free(vec_path);

        vec.load(vec_path) catch {
            // No existing index, that's fine
        };

        return .{
            .db = db,
            .vec = vec,
            .allocator = allocator,
            .base_path = base_path,
            .vector_dimensions = config.vector_dimensions,
        };
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        // Save vector index
        const vec_path = std.fs.path.join(self.allocator, &.{ self.base_path, "vectors.usearch" }) catch {
            self.vec.deinit();
            self.db.deinit();
            self.allocator.free(self.base_path);
            return;
        };
        defer self.allocator.free(vec_path);

        self.vec.save(vec_path) catch |err| {
            std.log.err("Failed to save vector index: {}", .{err});
        };
        self.vec.deinit();
        self.db.deinit();
        self.allocator.free(self.base_path);
    }

    // =========================================================================
    // Pattern Storage (documents with embeddings)
    // =========================================================================

    /// Store a pattern with optional embedding (ATOMIC)
    pub fn savePattern(
        self: *Self,
        id: []const u8,
        json: []const u8,
        embedding: ?[]const f32,
        tags: []const []const u8,
        success_rate: f32,
    ) !void {
        // Escape the ID to handle special characters
        const escaped_id = try lmdb.escapeKeyComponent(self.allocator, id);
        defer self.allocator.free(escaped_id);

        // Begin atomic transaction
        var txn = try self.db.beginTransaction();
        errdefer txn.abort();

        // 1. Store document
        const pattern_key = try std.fmt.allocPrint(self.allocator, "pattern:{s}", .{escaped_id});
        defer self.allocator.free(pattern_key);
        try txn.put(pattern_key, json);

        // 2. Store tag indexes
        for (tags) |tag| {
            const escaped_tag = try lmdb.escapeKeyComponent(self.allocator, tag);
            defer self.allocator.free(escaped_tag);

            const tag_key = try std.fmt.allocPrint(self.allocator, "idx:tag:{s}:{s}", .{ escaped_tag, escaped_id });
            defer self.allocator.free(tag_key);
            try txn.put(tag_key, "");
        }

        // 3. Store success rate index (padded for lexicographic sorting)
        const rate_int: u32 = @intFromFloat(@min(1.0, @max(0.0, success_rate)) * 10000);
        const rate_key = try std.fmt.allocPrint(self.allocator, "idx:success:{d:0>5}:{s}", .{ rate_int, escaped_id });
        defer self.allocator.free(rate_key);
        try txn.put(rate_key, "");

        // 4. Store vector with reverse lookup
        if (embedding) |emb| {
            if (emb.len != self.vector_dimensions) {
                return StorageError.VectorDimensionMismatch;
            }

            // Use hash of ID as vector key (handle collision by using full ID in key)
            const vec_key = std.hash.Wyhash.hash(0, id);

            // Store in vector index (outside transaction, but idempotent)
            try self.vec.add(vec_key, emb);

            // Store forward mapping: vec:{id} → {vec_key}
            const vec_ref_key = try std.fmt.allocPrint(self.allocator, "vec:{s}", .{escaped_id});
            defer self.allocator.free(vec_ref_key);
            const vec_ref_val = try std.fmt.allocPrint(self.allocator, "{d}", .{vec_key});
            defer self.allocator.free(vec_ref_val);
            try txn.put(vec_ref_key, vec_ref_val);

            // Store reverse mapping: veckey:{vec_key} → {id} (for O(1) lookup)
            const veckey_key = try std.fmt.allocPrint(self.allocator, "veckey:{d}", .{vec_key});
            defer self.allocator.free(veckey_key);
            try txn.put(veckey_key, escaped_id);
        }

        // Commit all changes atomically
        try txn.commit();
    }

    /// Get pattern by ID
    pub fn getPattern(self: *Self, id: []const u8) ![]const u8 {
        const escaped_id = try lmdb.escapeKeyComponent(self.allocator, id);
        defer self.allocator.free(escaped_id);

        const pattern_key = try std.fmt.allocPrint(self.allocator, "pattern:{s}", .{escaped_id});
        defer self.allocator.free(pattern_key);
        return self.db.get(pattern_key);
    }

    /// Delete pattern and all its indexes (ATOMIC)
    pub fn deletePattern(self: *Self, id: []const u8) !void {
        const escaped_id = try lmdb.escapeKeyComponent(self.allocator, id);
        defer self.allocator.free(escaped_id);

        // Begin atomic transaction
        var txn = try self.db.beginTransaction();
        errdefer txn.abort();

        // 1. Delete pattern document
        const pattern_key = try std.fmt.allocPrint(self.allocator, "pattern:{s}", .{escaped_id});
        defer self.allocator.free(pattern_key);
        try txn.deleteIfExists(pattern_key);

        // 2. Delete tag indexes (scan for all tags)
        {
            var iter = try self.db.iteratePrefix("idx:tag:");
            defer iter.deinit();

            var keys_to_delete: std.ArrayList([]const u8) = .empty;
            defer {
                for (keys_to_delete.items) |k| self.allocator.free(k);
                keys_to_delete.deinit(self.allocator);
            }

            while (iter.next()) |entry| {
                // Check if this index entry is for our pattern
                if (std.mem.endsWith(u8, entry.key, escaped_id)) {
                    try keys_to_delete.append(self.allocator, try self.allocator.dupe(u8, entry.key));
                }
            }

            for (keys_to_delete.items) |key| {
                try txn.deleteIfExists(key);
            }
        }

        // 3. Delete success rate index
        {
            var iter = try self.db.iteratePrefix("idx:success:");
            defer iter.deinit();

            while (iter.next()) |entry| {
                if (std.mem.endsWith(u8, entry.key, escaped_id)) {
                    try txn.deleteIfExists(entry.key);
                    break;
                }
            }
        }

        // 4. Delete vector references
        const vec_ref_key = try std.fmt.allocPrint(self.allocator, "vec:{s}", .{escaped_id});
        defer self.allocator.free(vec_ref_key);

        // Get vector key before deleting
        if (self.db.get(vec_ref_key)) |vec_key_str| {
            defer self.allocator.free(vec_key_str);

            if (std.fmt.parseInt(u64, vec_key_str, 10)) |vec_key| {
                // Delete from vector index
                self.vec.remove(vec_key) catch {};

                // Delete reverse mapping
                const veckey_key = try std.fmt.allocPrint(self.allocator, "veckey:{d}", .{vec_key});
                defer self.allocator.free(veckey_key);
                try txn.deleteIfExists(veckey_key);
            } else |_| {}

            try txn.deleteIfExists(vec_ref_key);
        } else |_| {}

        // Commit all changes atomically
        try txn.commit();
    }

    /// Find patterns by tag
    pub fn findByTag(self: *Self, tag: []const u8) !std.ArrayList([]const u8) {
        const escaped_tag = try lmdb.escapeKeyComponent(self.allocator, tag);
        defer self.allocator.free(escaped_tag);

        var results: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (results.items) |item| self.allocator.free(item);
            results.deinit(self.allocator);
        }

        const prefix = try std.fmt.allocPrint(self.allocator, "idx:tag:{s}:", .{escaped_tag});
        defer self.allocator.free(prefix);

        var iter = try self.db.iteratePrefix(prefix);
        defer iter.deinit();

        while (iter.next()) |entry| {
            // Extract ID from key (after the prefix)
            if (entry.key.len > prefix.len) {
                const escaped_id = entry.key[prefix.len..];
                const id = try lmdb.unescapeKeyComponent(self.allocator, escaped_id);
                defer self.allocator.free(id);

                const pattern = self.getPattern(id) catch continue;
                try results.append(self.allocator, pattern);
            }
        }

        return results;
    }

    /// Search similar patterns by embedding (O(log n) + O(k))
    pub fn searchSimilar(self: *Self, query_embedding: []const f32, k: usize) ![]PatternMatch {
        if (query_embedding.len != self.vector_dimensions) {
            return StorageError.VectorDimensionMismatch;
        }

        // O(log n) vector search
        const vec_results = try self.vec.search(query_embedding, k);
        defer self.allocator.free(vec_results);

        if (vec_results.len == 0) {
            return &[_]PatternMatch{};
        }

        // Build results with O(1) lookups via veckey index
        var matches = std.ArrayList(PatternMatch).init(self.allocator);
        errdefer {
            for (matches.items) |m| self.allocator.free(m.pattern_json);
            matches.deinit();
        }

        for (vec_results) |result| {
            // O(1) lookup: veckey:{vec_key} → pattern_id
            const veckey_key = try std.fmt.allocPrint(self.allocator, "veckey:{d}", .{result.key});
            defer self.allocator.free(veckey_key);

            const escaped_id = self.db.get(veckey_key) catch continue;
            defer self.allocator.free(escaped_id);

            const id = try lmdb.unescapeKeyComponent(self.allocator, escaped_id);
            defer self.allocator.free(id);

            const pattern = self.getPattern(id) catch continue;

            try matches.append(.{
                .pattern_json = pattern,
                .similarity = result.similarity,
                .distance = result.distance,
            });
        }

        return try matches.toOwnedSlice();
    }

    pub const PatternMatch = struct {
        pattern_json: []const u8,
        similarity: f32,
        distance: f32,

        pub fn deinit(self: *PatternMatch, allocator: Allocator) void {
            allocator.free(self.pattern_json);
        }
    };

    // =========================================================================
    // Graph Edges (relationships)
    // =========================================================================

    /// Add a relationship edge (ATOMIC)
    pub fn addEdge(self: *Self, from: []const u8, relationship: []const u8, to: []const u8, metadata: []const u8) !void {
        const escaped_from = try lmdb.escapeKeyComponent(self.allocator, from);
        defer self.allocator.free(escaped_from);
        const escaped_rel = try lmdb.escapeKeyComponent(self.allocator, relationship);
        defer self.allocator.free(escaped_rel);
        const escaped_to = try lmdb.escapeKeyComponent(self.allocator, to);
        defer self.allocator.free(escaped_to);

        var txn = try self.db.beginTransaction();
        errdefer txn.abort();

        // Forward edge
        const edge_key = try std.fmt.allocPrint(self.allocator, "edge:{s}:{s}:{s}", .{ escaped_from, escaped_rel, escaped_to });
        defer self.allocator.free(edge_key);
        try txn.put(edge_key, metadata);

        // Reverse edge for incoming lookups
        const redge_key = try std.fmt.allocPrint(self.allocator, "redge:{s}:{s}:{s}", .{ escaped_to, escaped_rel, escaped_from });
        defer self.allocator.free(redge_key);
        try txn.put(redge_key, "");

        try txn.commit();
    }

    /// Remove an edge (ATOMIC)
    pub fn removeEdge(self: *Self, from: []const u8, relationship: []const u8, to: []const u8) !void {
        const escaped_from = try lmdb.escapeKeyComponent(self.allocator, from);
        defer self.allocator.free(escaped_from);
        const escaped_rel = try lmdb.escapeKeyComponent(self.allocator, relationship);
        defer self.allocator.free(escaped_rel);
        const escaped_to = try lmdb.escapeKeyComponent(self.allocator, to);
        defer self.allocator.free(escaped_to);

        var txn = try self.db.beginTransaction();
        errdefer txn.abort();

        const edge_key = try std.fmt.allocPrint(self.allocator, "edge:{s}:{s}:{s}", .{ escaped_from, escaped_rel, escaped_to });
        defer self.allocator.free(edge_key);
        try txn.deleteIfExists(edge_key);

        const redge_key = try std.fmt.allocPrint(self.allocator, "redge:{s}:{s}:{s}", .{ escaped_to, escaped_rel, escaped_from });
        defer self.allocator.free(redge_key);
        try txn.deleteIfExists(redge_key);

        try txn.commit();
    }

    /// Get outgoing edges from a node
    pub fn getOutgoingEdges(self: *Self, from: []const u8, relationship: ?[]const u8) !std.ArrayList(Edge) {
        const escaped_from = try lmdb.escapeKeyComponent(self.allocator, from);
        defer self.allocator.free(escaped_from);

        var results: std.ArrayList(Edge) = .empty;
        errdefer {
            for (results.items) |*e| e.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        const prefix = if (relationship) |rel| blk: {
            const escaped_rel = try lmdb.escapeKeyComponent(self.allocator, rel);
            defer self.allocator.free(escaped_rel);
            break :blk try std.fmt.allocPrint(self.allocator, "edge:{s}:{s}:", .{ escaped_from, escaped_rel });
        } else try std.fmt.allocPrint(self.allocator, "edge:{s}:", .{escaped_from});
        defer self.allocator.free(prefix);

        var iter = try self.db.iteratePrefix(prefix);
        defer iter.deinit();

        while (iter.next()) |entry| {
            if (parseEdgeKey(self.allocator, entry.key)) |edge_parts| {
                defer {
                    self.allocator.free(edge_parts.from);
                    self.allocator.free(edge_parts.relationship);
                    self.allocator.free(edge_parts.to);
                }

                try results.append(self.allocator, .{
                    .from = try self.allocator.dupe(u8, edge_parts.from),
                    .relationship = try self.allocator.dupe(u8, edge_parts.relationship),
                    .to = try self.allocator.dupe(u8, edge_parts.to),
                    .metadata = try self.allocator.dupe(u8, entry.value),
                });
            }
        }

        return results;
    }

    /// Get incoming edges to a node
    pub fn getIncomingEdges(self: *Self, to: []const u8, relationship: ?[]const u8) !std.ArrayList(Edge) {
        const escaped_to = try lmdb.escapeKeyComponent(self.allocator, to);
        defer self.allocator.free(escaped_to);

        var results: std.ArrayList(Edge) = .empty;
        errdefer {
            for (results.items) |*e| e.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        const prefix = if (relationship) |rel| blk: {
            const escaped_rel = try lmdb.escapeKeyComponent(self.allocator, rel);
            defer self.allocator.free(escaped_rel);
            break :blk try std.fmt.allocPrint(self.allocator, "redge:{s}:{s}:", .{ escaped_to, escaped_rel });
        } else try std.fmt.allocPrint(self.allocator, "redge:{s}:", .{escaped_to});
        defer self.allocator.free(prefix);

        var iter = try self.db.iteratePrefix(prefix);
        defer iter.deinit();

        while (iter.next()) |entry| {
            // Parse redge key: redge:{to}:{rel}:{from}
            var parts = std.mem.splitScalar(u8, entry.key, ':');
            _ = parts.next(); // skip "redge"
            _ = parts.next(); // skip {to}
            const escaped_rel = parts.next() orelse continue;
            const escaped_from = parts.next() orelse continue;

            const rel = lmdb.unescapeKeyComponent(self.allocator, escaped_rel) catch continue;
            defer self.allocator.free(rel);
            const from = lmdb.unescapeKeyComponent(self.allocator, escaped_from) catch continue;
            defer self.allocator.free(from);

            // Get the actual edge metadata
            const edge_key = try std.fmt.allocPrint(self.allocator, "edge:{s}:{s}:{s}", .{ escaped_from, escaped_rel, escaped_to });
            defer self.allocator.free(edge_key);

            const metadata = self.db.get(edge_key) catch try self.allocator.dupe(u8, "");

            try results.append(self.allocator, .{
                .from = try self.allocator.dupe(u8, from),
                .relationship = try self.allocator.dupe(u8, rel),
                .to = try self.allocator.dupe(u8, to),
                .metadata = metadata,
            });
        }

        return results;
    }

    pub const Edge = struct {
        from: []const u8,
        relationship: []const u8,
        to: []const u8,
        metadata: []const u8,

        pub fn deinit(self: *Edge, allocator: Allocator) void {
            allocator.free(self.from);
            allocator.free(self.relationship);
            allocator.free(self.to);
            allocator.free(self.metadata);
        }
    };

    fn parseEdgeKey(allocator: Allocator, key: []const u8) ?struct {
        from: []const u8,
        relationship: []const u8,
        to: []const u8,
    } {
        var parts = std.mem.splitScalar(u8, key, ':');
        _ = parts.next(); // skip "edge"
        const escaped_from = parts.next() orelse return null;
        const escaped_rel = parts.next() orelse return null;
        const escaped_to = parts.next() orelse return null;

        const from = lmdb.unescapeKeyComponent(allocator, escaped_from) catch return null;
        errdefer allocator.free(from);
        const rel = lmdb.unescapeKeyComponent(allocator, escaped_rel) catch return null;
        errdefer allocator.free(rel);
        const to = lmdb.unescapeKeyComponent(allocator, escaped_to) catch return null;

        return .{ .from = from, .relationship = rel, .to = to };
    }

    // =========================================================================
    // Conversations
    // =========================================================================

    /// Store a conversation message
    pub fn addMessage(self: *Self, conv_id: []const u8, timestamp: i64, message_json: []const u8) !void {
        const escaped_id = try lmdb.escapeKeyComponent(self.allocator, conv_id);
        defer self.allocator.free(escaped_id);

        const key = try std.fmt.allocPrint(self.allocator, "conv:{s}:msg:{d:0>20}", .{ escaped_id, @as(u64, @bitCast(timestamp)) });
        defer self.allocator.free(key);
        try self.db.put(key, message_json);
    }

    /// Get conversation messages (in timestamp order)
    pub fn getMessages(self: *Self, conv_id: []const u8) !std.ArrayList([]const u8) {
        const escaped_id = try lmdb.escapeKeyComponent(self.allocator, conv_id);
        defer self.allocator.free(escaped_id);

        var results: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (results.items) |item| self.allocator.free(item);
            results.deinit(self.allocator);
        }

        const prefix = try std.fmt.allocPrint(self.allocator, "conv:{s}:msg:", .{escaped_id});
        defer self.allocator.free(prefix);

        var iter = try self.db.iteratePrefix(prefix);
        defer iter.deinit();

        while (iter.next()) |entry| {
            try results.append(self.allocator, try self.allocator.dupe(u8, entry.value));
        }

        return results;
    }

    // =========================================================================
    // Raw Key-Value Access
    // =========================================================================

    /// Put raw key-value
    pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
        try self.db.put(key, value);
    }

    /// Get raw value
    pub fn get(self: *Self, key: []const u8) ![]const u8 {
        return self.db.get(key);
    }

    /// Delete key
    pub fn delete(self: *Self, key: []const u8) !void {
        try self.db.delete(key);
    }

    /// Check if key exists
    pub fn exists(self: *Self, key: []const u8) bool {
        return self.db.exists(key);
    }

    // =========================================================================
    // Statistics
    // =========================================================================

    pub const Stats = struct {
        vector_count: usize,
        vector_memory_bytes: usize,
        vector_capacity: usize,
    };

    pub fn getStats(self: *Self) Stats {
        return .{
            .vector_count = self.vec.size(),
            .vector_memory_bytes = self.vec.memoryUsage(),
            .vector_capacity = self.vec.capacity(),
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "ai storage basic operations" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var storage = try AIStorage.init(allocator, .{
        .base_path = path,
        .vector_dimensions = 4,
        .vector_capacity = 100,
    });
    defer storage.deinit();

    // Test raw put/get
    try storage.put("test:key", "test value");
    const value = try storage.get("test:key");
    defer allocator.free(value);
    try std.testing.expectEqualStrings("test value", value);
}

test "ai storage pattern lifecycle" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var storage = try AIStorage.init(allocator, .{
        .base_path = path,
        .vector_dimensions = 4,
        .vector_capacity = 100,
    });
    defer storage.deinit();

    // Save pattern
    try storage.savePattern(
        "pattern1",
        "{\"name\": \"test\"}",
        &[_]f32{ 1.0, 0.0, 0.0, 0.0 },
        &[_][]const u8{"coding"},
        0.85,
    );

    // Get pattern
    const pattern = try storage.getPattern("pattern1");
    defer allocator.free(pattern);
    try std.testing.expectEqualStrings("{\"name\": \"test\"}", pattern);

    // Find by tag
    var by_tag = try storage.findByTag("coding");
    defer {
        for (by_tag.items) |item| allocator.free(item);
        by_tag.deinit();
    }
    try std.testing.expectEqual(@as(usize, 1), by_tag.items.len);

    // Delete pattern
    try storage.deletePattern("pattern1");

    // Should not exist anymore
    const result = storage.getPattern("pattern1");
    try std.testing.expectError(lmdb.LmdbError.NotFound, result);
}

test "ai storage edges" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var storage = try AIStorage.init(allocator, .{
        .base_path = path,
        .vector_dimensions = 4,
        .vector_capacity = 100,
    });
    defer storage.deinit();

    // Add edge
    try storage.addEdge("A", "depends_on", "B", "{\"weight\": 1.0}");

    // Get outgoing
    var outgoing = try storage.getOutgoingEdges("A", null);
    defer {
        for (outgoing.items) |*e| e.deinit(allocator);
        outgoing.deinit();
    }
    try std.testing.expectEqual(@as(usize, 1), outgoing.items.len);
    try std.testing.expectEqualStrings("B", outgoing.items[0].to);

    // Get incoming
    var incoming = try storage.getIncomingEdges("B", null);
    defer {
        for (incoming.items) |*e| e.deinit(allocator);
        incoming.deinit();
    }
    try std.testing.expectEqual(@as(usize, 1), incoming.items.len);
    try std.testing.expectEqualStrings("A", incoming.items[0].from);

    // Remove edge
    try storage.removeEdge("A", "depends_on", "B");

    var after_remove = try storage.getOutgoingEdges("A", null);
    defer after_remove.deinit();
    try std.testing.expectEqual(@as(usize, 0), after_remove.items.len);
}

test "ai storage special characters in keys" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var storage = try AIStorage.init(allocator, .{
        .base_path = path,
        .vector_dimensions = 4,
        .vector_capacity = 100,
    });
    defer storage.deinit();

    // ID with special characters
    try storage.savePattern(
        "pattern:with:colons",
        "{\"test\": true}",
        null,
        &[_][]const u8{"tag:with:colons"},
        0.5,
    );

    const pattern = try storage.getPattern("pattern:with:colons");
    defer allocator.free(pattern);
    try std.testing.expectEqualStrings("{\"test\": true}", pattern);
}
