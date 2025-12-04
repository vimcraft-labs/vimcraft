/// usearch Vector Index Bindings
/// High-performance approximate nearest neighbor search (HNSW algorithm)
///
/// Usage:
///   - Add vectors with unique keys
///   - Search for k-nearest neighbors
///   - Persist to disk for durability
const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("usearch.h");
});

pub const VectorError = error{
    Init,
    Reserve,
    Add,
    Remove,
    Search,
    Get,
    Save,
    Load,
    OutOfMemory,
    DimensionMismatch,
    KeyNotFound,
};

/// Metric types for distance calculation
pub const Metric = enum(c_uint) {
    /// Cosine similarity (1 - cos_sim). Range [0, 2]. 0 = identical.
    cosine = c.usearch_metric_cos_k,
    /// Inner product (negative). More negative = more similar.
    inner_product = c.usearch_metric_ip_k,
    /// Squared L2 distance. 0 = identical.
    l2_squared = c.usearch_metric_l2sq_k,
    /// Hamming distance for binary vectors.
    hamming = c.usearch_metric_hamming_k,
    /// Jaccard distance for sets.
    jaccard = c.usearch_metric_jaccard_k,

    /// Convert distance to similarity score [0, 1] where 1 = identical
    pub fn distanceToSimilarity(self: Metric, distance: f32) f32 {
        return switch (self) {
            .cosine => 1.0 - (distance / 2.0), // cosine distance [0,2] -> sim [0,1]
            .inner_product => @exp(-distance), // arbitrary transform
            .l2_squared => 1.0 / (1.0 + distance), // inverse
            .hamming, .jaccard => 1.0 - distance,
        };
    }
};

/// Scalar types for vector components
pub const Scalar = enum(c_uint) {
    f32 = c.usearch_scalar_f32_k,
    f64 = c.usearch_scalar_f64_k,
    f16 = c.usearch_scalar_f16_k,
    i8 = c.usearch_scalar_i8_k,
};

/// Search result entry
pub const SearchResult = struct {
    key: u64,
    distance: f32,
    similarity: f32, // Normalized to [0, 1]
};

/// Vector Index wrapper
pub const VectorIndex = struct {
    index: c.usearch_index_t,
    dimensions: usize,
    metric: Metric,
    allocator: Allocator,

    const Self = @This();

    /// Configuration for index creation
    pub const Config = struct {
        dimensions: usize,
        metric: Metric = .cosine,
        connectivity: usize = 16, // M parameter, higher = more accurate but slower
        expansion_add: usize = 128, // efConstruction
        expansion_search: usize = 64, // ef
        capacity: usize = 100_000,
    };

    /// Initialize a new vector index
    pub fn init(allocator: Allocator, config: Config) !Self {
        var options = c.usearch_init_options_t{
            .metric_kind = @intFromEnum(config.metric),
            .metric = null,
            .quantization = c.usearch_scalar_f32_k,
            .dimensions = config.dimensions,
            .connectivity = config.connectivity,
            .expansion_add = config.expansion_add,
            .expansion_search = config.expansion_search,
            .multi = false,
        };

        var err: c.usearch_error_t = null;
        const index = c.usearch_init(&options, &err);

        if (index == null) {
            logError("usearch_init", err);
            return VectorError.Init;
        }

        // Reserve capacity
        c.usearch_reserve(index, config.capacity, &err);
        if (err != null) {
            logError("usearch_reserve", err);
            c.usearch_free(index, &err);
            return VectorError.Reserve;
        }

        return .{
            .index = index,
            .dimensions = config.dimensions,
            .metric = config.metric,
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        if (self.index != null) {
            var err: c.usearch_error_t = null;
            c.usearch_free(self.index, &err);
            self.index = null;
        }
    }

    /// Add a vector to the index
    pub fn add(self: *Self, key: u64, vector: []const f32) !void {
        if (vector.len != self.dimensions) {
            return VectorError.DimensionMismatch;
        }

        var err: c.usearch_error_t = null;
        c.usearch_add(
            self.index,
            key,
            @ptrCast(vector.ptr),
            c.usearch_scalar_f32_k,
            &err,
        );

        if (err != null) {
            logError("usearch_add", err);
            return VectorError.Add;
        }
    }

    /// Remove a vector from the index
    pub fn remove(self: *Self, key: u64) !void {
        var err: c.usearch_error_t = null;
        const removed = c.usearch_remove(self.index, key, &err);

        if (err != null) {
            logError("usearch_remove", err);
            return VectorError.Remove;
        }

        if (removed == 0) {
            return VectorError.KeyNotFound;
        }
    }

    /// Search for k-nearest neighbors
    pub fn search(self: *Self, query: []const f32, k: usize) ![]SearchResult {
        if (query.len != self.dimensions) {
            return VectorError.DimensionMismatch;
        }

        // Handle empty index
        const current_size = self.size();
        if (current_size == 0) {
            return &[_]SearchResult{};
        }

        // Limit k to actual size
        const actual_k = @min(k, current_size);

        const keys = try self.allocator.alloc(u64, actual_k);
        defer self.allocator.free(keys);

        const distances = try self.allocator.alloc(f32, actual_k);
        defer self.allocator.free(distances);

        var err: c.usearch_error_t = null;
        const found = c.usearch_search(
            self.index,
            @ptrCast(query.ptr),
            c.usearch_scalar_f32_k,
            actual_k,
            keys.ptr,
            distances.ptr,
            &err,
        );

        if (err != null) {
            logError("usearch_search", err);
            return VectorError.Search;
        }

        // Build results with similarity scores
        const results = try self.allocator.alloc(SearchResult, found);
        for (0..found) |i| {
            results[i] = .{
                .key = keys[i],
                .distance = distances[i],
                .similarity = self.metric.distanceToSimilarity(distances[i]),
            };
        }

        return results;
    }

    /// Check if key exists in index
    pub fn contains(self: *Self, key: u64) !bool {
        var err: c.usearch_error_t = null;
        const result = c.usearch_contains(self.index, key, &err);

        if (err != null) {
            logError("usearch_contains", err);
            return VectorError.Get;
        }

        return result;
    }

    /// Get current size of index
    pub fn size(self: *Self) usize {
        var err: c.usearch_error_t = null;
        const result = c.usearch_size(self.index, &err);
        if (err != null) {
            logError("usearch_size", err);
            return 0;
        }
        return result;
    }

    /// Get current capacity
    pub fn capacity(self: *Self) usize {
        var err: c.usearch_error_t = null;
        const result = c.usearch_capacity(self.index, &err);
        if (err != null) {
            logError("usearch_capacity", err);
            return 0;
        }
        return result;
    }

    /// Save index to file
    pub fn save(self: *Self, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        var err: c.usearch_error_t = null;
        c.usearch_save(self.index, path_z.ptr, &err);

        if (err != null) {
            logError("usearch_save", err);
            return VectorError.Save;
        }
    }

    /// Load index from file
    pub fn load(self: *Self, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        var err: c.usearch_error_t = null;
        c.usearch_load(self.index, path_z.ptr, &err);

        if (err != null) {
            logError("usearch_load", err);
            return VectorError.Load;
        }
    }

    /// Get memory usage in bytes
    pub fn memoryUsage(self: *Self) usize {
        var err: c.usearch_error_t = null;
        const result = c.usearch_memory_usage(self.index, &err);
        if (err != null) {
            logError("usearch_memory_usage", err);
            return 0;
        }
        return result;
    }

    /// Log usearch error message
    fn logError(operation: []const u8, err: c.usearch_error_t) void {
        if (err) |msg| {
            std.log.err("usearch {s}: {s}", .{ operation, msg });
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "vector index basic operations" {
    const allocator = std.testing.allocator;

    var index = try VectorIndex.init(allocator, .{
        .dimensions = 4,
        .capacity = 100,
    });
    defer index.deinit();

    // Add some vectors
    try index.add(1, &[_]f32{ 1.0, 0.0, 0.0, 0.0 });
    try index.add(2, &[_]f32{ 0.0, 1.0, 0.0, 0.0 });
    try index.add(3, &[_]f32{ 0.0, 0.0, 1.0, 0.0 });

    try std.testing.expectEqual(@as(usize, 3), index.size());
    try std.testing.expect(try index.contains(1));
    try std.testing.expect(!try index.contains(999));

    // Search
    const results = try index.search(&[_]f32{ 1.0, 0.1, 0.0, 0.0 }, 2);
    defer allocator.free(results);

    try std.testing.expect(results.len > 0);
    try std.testing.expectEqual(@as(u64, 1), results[0].key);
    try std.testing.expect(results[0].similarity > 0.9); // Should be very similar
}

test "vector index dimension mismatch" {
    const allocator = std.testing.allocator;

    var index = try VectorIndex.init(allocator, .{
        .dimensions = 4,
        .capacity = 100,
    });
    defer index.deinit();

    // Wrong dimension should fail
    const result = index.add(1, &[_]f32{ 1.0, 0.0, 0.0 }); // Only 3 dims
    try std.testing.expectError(VectorError.DimensionMismatch, result);
}

test "vector index empty search" {
    const allocator = std.testing.allocator;

    var index = try VectorIndex.init(allocator, .{
        .dimensions = 4,
        .capacity = 100,
    });
    defer index.deinit();

    // Search on empty index should return empty
    const results = try index.search(&[_]f32{ 1.0, 0.0, 0.0, 0.0 }, 10);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}
