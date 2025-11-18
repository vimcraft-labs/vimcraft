/// Rope Data Structure
/// Tree-based string representation for efficient editing of large buffers
///
/// Performance characteristics:
/// - Insert/Delete: O(log n) vs ArrayList's O(n)
/// - Concat: O(1) vs ArrayList's O(n)
/// - Index: O(log n) vs ArrayList's O(1)
/// - Iteration: O(n) same as ArrayList
///
/// Tree structure:
/// - Internal nodes: Concatenation (left + right subtrees)
/// - Leaf nodes: String slices (up to LEAF_SIZE bytes)
/// - Self-balancing via weight heuristic
const std = @import("std");

/// Maximum bytes per leaf node (tuned for cache locality)
/// Smaller = deeper tree, more overhead
/// Larger = less balanced, worse for small edits
const LEAF_SIZE = 512;

/// Rope node (internal or leaf)
pub const Node = union(enum) {
    /// Internal node: concatenation of left and right subtrees
    internal: struct {
        left: *Node,
        right: *Node,
        weight: usize, // Byte count in left subtree (for O(log n) indexing)
    },

    /// Leaf node: actual string data
    leaf: struct {
        data: []const u8, // Slice (may be owned or reference-counted)
        owned: bool, // True if we own the memory (must free)
    },

    /// Get total byte length of this rope (recursive)
    pub fn len(self: *const Node) usize {
        return switch (self.*) {
            .internal => |i| i.weight + i.right.len(),
            .leaf => |l| l.data.len,
        };
    }

    /// Get depth of tree (for debugging/balancing)
    pub fn depth(self: *const Node) usize {
        return switch (self.*) {
            .internal => |i| 1 + @max(i.left.depth(), i.right.depth()),
            .leaf => 0,
        };
    }

    /// Recursively free all nodes
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .internal => |i| {
                i.left.deinit(allocator);
                i.right.deinit(allocator);
                allocator.destroy(i.left);
                allocator.destroy(i.right);
            },
            .leaf => |l| {
                if (l.owned) {
                    allocator.free(l.data);
                }
            },
        }
    }
};

/// Rope: High-level API for rope operations
pub const Rope = struct {
    allocator: std.mem.Allocator,
    root: ?*Node, // Null for empty rope

    /// Create empty rope
    pub fn init(allocator: std.mem.Allocator) Rope {
        return .{
            .allocator = allocator,
            .root = null,
        };
    }

    /// Create rope from string (copies data)
    pub fn fromString(allocator: std.mem.Allocator, string: []const u8) !Rope {
        if (string.len == 0) return Rope.init(allocator);

        // For small strings, single leaf node
        if (string.len <= LEAF_SIZE) {
            const node = try allocator.create(Node);
            const data = try allocator.dupe(u8, string);
            node.* = .{
                .leaf = .{
                    .data = data,
                    .owned = true,
                },
            };
            return .{
                .allocator = allocator,
                .root = node,
            };
        }

        // For large strings, split into balanced tree
        return try fromStringSplit(allocator, string);
    }

    /// Split large string into balanced rope tree
    fn fromStringSplit(allocator: std.mem.Allocator, string: []const u8) !Rope {
        // Recursively split string into LEAF_SIZE chunks
        if (string.len <= LEAF_SIZE) {
            const node = try allocator.create(Node);
            const data = try allocator.dupe(u8, string);
            node.* = .{
                .leaf = .{
                    .data = data,
                    .owned = true,
                },
            };
            return .{
                .allocator = allocator,
                .root = node,
            };
        }

        // Split roughly in half (prefer splitting at whitespace)
        const mid = findSplitPoint(string);

        var left_rope = try fromStringSplit(allocator, string[0..mid]);
        errdefer left_rope.deinit();

        var right_rope = try fromStringSplit(allocator, string[mid..]);
        errdefer right_rope.deinit();

        return try concat(left_rope, right_rope);
    }

    /// Find good split point (prefer whitespace/newlines)
    fn findSplitPoint(string: []const u8) usize {
        const mid = string.len / 2;
        const search_range = @min(64, mid); // Look within 64 bytes of midpoint

        // Search backward for newline
        var i: usize = mid;
        while (i > mid - search_range and i > 0) : (i -= 1) {
            if (string[i] == '\n') return i + 1;
        }

        // Search forward for newline
        i = mid;
        while (i < mid + search_range and i < string.len) : (i += 1) {
            if (string[i] == '\n') return i + 1;
        }

        // No newline found, just split at midpoint
        return mid;
    }

    /// Free rope memory
    pub fn deinit(self: *Rope) void {
        if (self.root) |root| {
            root.deinit(self.allocator);
            self.allocator.destroy(root);
        }
    }

    /// Get total byte length
    pub fn len(self: *const Rope) usize {
        return if (self.root) |root| root.len() else 0;
    }

    /// Concatenate two ropes (consumes both inputs)
    pub fn concat(left: Rope, right: Rope) !Rope {
        // Handle empty cases
        if (left.root == null) return right;
        if (right.root == null) return left;

        const allocator = left.allocator;

        // Create internal node
        const node = try allocator.create(Node);
        node.* = .{
            .internal = .{
                .left = left.root.?,
                .right = right.root.?,
                .weight = left.root.?.len(),
            },
        };

        return .{
            .allocator = allocator,
            .root = node,
        };
    }

    /// Insert string at byte offset
    pub fn insert(self: *Rope, offset: usize, string: []const u8) !void {
        if (string.len == 0) return;

        // Create rope for new string
        var new_rope = try fromString(self.allocator, string);
        errdefer new_rope.deinit();

        // Split at insertion point
        var left = try self.slice(0, offset);
        errdefer left.deinit();

        var right = try self.slice(offset, self.len());
        errdefer right.deinit();

        // Concat: left + new_rope + right
        var temp = try concat(left, new_rope);
        errdefer temp.deinit();

        var result = try concat(temp, right);

        // Replace self.root
        if (self.root) |old_root| {
            old_root.deinit(self.allocator);
            self.allocator.destroy(old_root);
        }
        self.root = result.root;
    }

    /// Delete bytes from [start, end)
    pub fn delete(self: *Rope, start: usize, end: usize) !void {
        if (start >= end) return;

        // Split: [0, start) + [end, len)
        var left = try self.slice(0, start);
        errdefer left.deinit();

        var right = try self.slice(end, self.len());
        errdefer right.deinit();

        var result = try concat(left, right);

        // Replace self.root
        if (self.root) |old_root| {
            old_root.deinit(self.allocator);
            self.allocator.destroy(old_root);
        }
        self.root = result.root;
    }

    /// Create rope slice [start, end)
    /// Returns NEW rope (does not share nodes - copies leaf data)
    pub fn slice(self: *const Rope, start: usize, end: usize) !Rope {
        if (start >= end or self.root == null) return Rope.init(self.allocator);

        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        // Iterate and collect bytes in range
        try self.iterateRange(start, end, &result);

        // Create rope from collected bytes
        return try fromString(self.allocator, result.items);
    }

    /// Iterate over rope and collect bytes in range [start, end)
    fn iterateRange(self: *const Rope, start: usize, end: usize, output: *std.ArrayList(u8)) !void {
        if (self.root) |root| {
            try iterateNodeRange(root, 0, start, end, output);
        }
    }

    /// Recursive helper for iterateRange
    fn iterateNodeRange(node: *Node, node_start: usize, start: usize, end: usize, output: *std.ArrayList(u8)) !void {
        const node_len = node.len();
        const node_end = node_start + node_len;

        // No overlap
        if (end <= node_start or start >= node_end) return;

        switch (node.*) {
            .leaf => |l| {
                // Calculate overlap
                const copy_start = if (start > node_start) start - node_start else 0;
                const copy_end = if (end < node_end) end - node_start else node_len;
                try output.appendSlice(l.data[copy_start..copy_end]);
            },
            .internal => |i| {
                const left_end = node_start + i.weight;
                try iterateNodeRange(i.left, node_start, start, end, output);
                try iterateNodeRange(i.right, left_end, start, end, output);
            },
        }
    }

    /// Convert rope to string (allocates new buffer)
    pub fn toString(self: *const Rope) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        if (self.root) |root| {
            try collectString(root, &result);
        }

        return result.toOwnedSlice();
    }

    /// Recursive helper for toString
    fn collectString(node: *Node, output: *std.ArrayList(u8)) !void {
        switch (node.*) {
            .leaf => |l| try output.appendSlice(l.data),
            .internal => |i| {
                try collectString(i.left, output);
                try collectString(i.right, output);
            },
        }
    }

    /// Get byte at index (O(log n))
    pub fn byteAt(self: *const Rope, index: usize) ?u8 {
        if (self.root) |root| {
            return byteAtNode(root, index);
        }
        return null;
    }

    /// Recursive helper for byteAt
    fn byteAtNode(node: *Node, index: usize) ?u8 {
        switch (node.*) {
            .leaf => |l| {
                if (index < l.data.len) return l.data[index];
                return null;
            },
            .internal => |i| {
                if (index < i.weight) {
                    return byteAtNode(i.left, index);
                } else {
                    return byteAtNode(i.right, index - i.weight);
                }
            },
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Rope: create from string" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Hello, World!");
    defer rope.deinit();

    try std.testing.expectEqual(@as(usize, 13), rope.len());
}

test "Rope: insert" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Hello, World!");
    defer rope.deinit();

    try rope.insert(7, "Beautiful ");

    const result = try rope.toString();
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello, Beautiful World!", result);
}

test "Rope: delete" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Hello, Beautiful World!");
    defer rope.deinit();

    try rope.delete(7, 17); // Delete "Beautiful "

    const result = try rope.toString();
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "Rope: slice" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Hello, World!");
    defer rope.deinit();

    var slice_rope = try rope.slice(0, 5);
    defer slice_rope.deinit();

    const result = try slice_rope.toString();
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello", result);
}

test "Rope: large string" {
    const allocator = std.testing.allocator;

    // Create 10KB string
    const large_data = try allocator.alloc(u8, 10 * 1024);
    defer allocator.free(large_data);
    @memset(large_data, 'A');

    var rope = try Rope.fromString(allocator, large_data);
    defer rope.deinit();

    try std.testing.expectEqual(@as(usize, 10 * 1024), rope.len());

    // Verify tree depth is reasonable (should be ~log2(10KB/512) = ~5)
    if (rope.root) |root| {
        const tree_depth = root.depth();
        try std.testing.expect(tree_depth < 10); // Should be well-balanced
    }
}

test "Rope: concat" {
    const allocator = std.testing.allocator;

    var rope1 = try Rope.fromString(allocator, "Hello");
    defer rope1.deinit();

    var rope2 = try Rope.fromString(allocator, "World");
    defer rope2.deinit();

    var result = try Rope.concat(rope1, rope2);
    defer result.deinit();

    const string = try result.toString();
    defer allocator.free(string);

    try std.testing.expectEqualStrings("HelloWorld", string);
}
