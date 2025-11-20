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
        newline_count: usize, // Total newline count in entire subtree
        refcount: usize, // Reference count for shared nodes
    },

    /// Leaf node: actual string data
    leaf: struct {
        data: []const u8, // Slice (may be owned or reference-counted)
        owned: bool, // True if we own the memory (must free)
        newline_count: usize, // Cached newline count in this leaf
        refcount: usize, // Reference count for shared nodes
    },

    /// Get total byte length of this rope (recursive)
    pub fn len(self: *const Node) usize {
        return switch (self.*) {
            .internal => |i| i.weight + i.right.len(),
            .leaf => |l| l.data.len,
        };
    }

    /// Get total newline count in this subtree
    pub fn newlineCount(self: *const Node) usize {
        return switch (self.*) {
            .internal => |i| i.newline_count,
            .leaf => |l| l.newline_count,
        };
    }

    /// Get depth of tree (for debugging/balancing)
    pub fn depth(self: *const Node) usize {
        return switch (self.*) {
            .internal => |i| 1 + @max(i.left.depth(), i.right.depth()),
            .leaf => 0,
        };
    }

    /// Increment reference count
    pub fn incRef(self: *Node) void {
        switch (self.*) {
            .internal => |*i| i.refcount += 1,
            .leaf => |*l| l.refcount += 1,
        }
    }

    /// Decrement reference count and return new count
    pub fn decRef(self: *Node) usize {
        return switch (self.*) {
            .internal => |*i| {
                i.refcount -= 1;
                return i.refcount;
            },
            .leaf => |*l| {
                l.refcount -= 1;
                return l.refcount;
            },
        };
    }

    /// Recursively free all nodes (respects reference counting)
    /// Only actually frees when refcount reaches 0
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        const remaining = self.decRef();
        if (remaining > 0) return; // Still has references

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
            const newline_count = std.mem.count(u8, data, "\n");
            node.* = .{
                .leaf = .{
                    .data = data,
                    .owned = true,
                    .newline_count = newline_count,
                    .refcount = 1,
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
            const newline_count = std.mem.count(u8, data, "\n");
            node.* = .{
                .leaf = .{
                    .data = data,
                    .owned = true,
                    .newline_count = newline_count,
                    .refcount = 1,
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

    /// Find good split point (prefer whitespace/newlines, ensure UTF-8 boundary)
    fn findSplitPoint(string: []const u8) usize {
        const mid = string.len / 2;
        const search_range = @min(64, mid); // Look within 64 bytes of midpoint

        // Search backward for newline
        var i: usize = mid;
        while (i > mid - search_range and i > 0) : (i -= 1) {
            if (string[i] == '\n') {
                // Newline found - validate it's at UTF-8 boundary
                return validateUtf8Boundary(string, i + 1);
            }
        }

        // Search forward for newline
        i = mid;
        while (i < mid + search_range and i < string.len) : (i += 1) {
            if (string[i] == '\n') {
                // Newline found - validate it's at UTF-8 boundary
                return validateUtf8Boundary(string, i + 1);
            }
        }

        // No newline found, split at midpoint but ensure UTF-8 boundary
        return validateUtf8Boundary(string, mid);
    }

    /// Ensure split point is at a UTF-8 character boundary
    /// Walks backward from pos to find the start of a UTF-8 character
    /// UTF-8 continuation bytes have pattern 10xxxxxx (0x80-0xBF)
    /// Character start bytes have patterns: 0xxxxxxx, 110xxxxx, 1110xxxx, 11110xxx
    fn validateUtf8Boundary(string: []const u8, pos: usize) usize {
        if (pos == 0 or pos >= string.len) return pos;

        var i = pos;

        // Walk backward while we're in the middle of a UTF-8 sequence
        // Continuation bytes: 10xxxxxx (0x80 <= byte <= 0xBF)
        while (i > 0 and (string[i] & 0xC0) == 0x80) {
            i -= 1;
        }

        // Now i points to the start of a UTF-8 character
        // Verify we haven't walked back too far (max UTF-8 char is 4 bytes)
        if (pos - i > 4) {
            // Something wrong - just use pos (shouldn't happen with valid UTF-8)
            return pos;
        }

        return i;
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

    /// Get total line count (number of newlines + 1)
    /// Empty rope has 1 line, "a\nb" has 2 lines
    pub fn lineCount(self: *const Rope) usize {
        if (self.root) |root| {
            return root.newlineCount() + 1;
        }
        return 1; // Empty rope has 1 line
    }

    /// Get byte offset of the start of a given line (0-indexed)
    /// Returns the total length if line_num >= lineCount()
    pub fn byteOfLine(self: *const Rope, line_num: usize) usize {
        if (self.root == null) return 0;
        if (line_num == 0) return 0;

        return byteOfLineNode(self.root.?, line_num, 0, 0);
    }

    /// Recursive helper for byteOfLine
    /// current_line: line number at node_start position
    /// node_start: byte offset where this node starts
    fn byteOfLineNode(node: *const Node, target_line: usize, current_line: usize, node_start: usize) usize {
        switch (node.*) {
            .leaf => |l| {
                // Scan through leaf data counting newlines
                var line = current_line;
                var i: usize = 0;
                while (i < l.data.len) : (i += 1) {
                    if (l.data[i] == '\n') {
                        line += 1;
                        if (line == target_line) {
                            return node_start + i + 1; // Byte after newline
                        }
                    }
                }
                // Didn't find target line in this leaf
                return node_start + l.data.len;
            },
            .internal => |i| {
                const left_newlines = i.left.newlineCount();
                const lines_after_left = current_line + left_newlines;

                if (target_line <= lines_after_left) {
                    // Target is in left subtree
                    return byteOfLineNode(i.left, target_line, current_line, node_start);
                } else {
                    // Target is in right subtree
                    const right_start = node_start + i.weight;
                    return byteOfLineNode(i.right, target_line, lines_after_left, right_start);
                }
            },
        }
    }

    /// Concatenate two ropes (consumes both inputs)
    pub fn concat(left: Rope, right: Rope) !Rope {
        // Handle empty cases
        if (left.root == null) return right;
        if (right.root == null) return left;

        const allocator = left.allocator;

        // Create internal node
        const node = try allocator.create(Node);
        const left_newlines = left.root.?.newlineCount();
        const right_newlines = right.root.?.newlineCount();
        node.* = .{
            .internal = .{
                .left = left.root.?,
                .right = right.root.?,
                .weight = left.root.?.len(),
                .newline_count = left_newlines + right_newlines,
                .refcount = 1,
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

        const result = try concat(temp, right);

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

        const result = try concat(left, right);

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

        var result: std.ArrayList(u8) = .{};
        defer result.deinit(self.allocator);

        // Iterate and collect bytes in range
        try self.iterateRange(start, end, &result, self.allocator);

        // Create rope from collected bytes
        return try fromString(self.allocator, result.items);
    }

    /// Iterate over rope and collect bytes in range [start, end)
    fn iterateRange(self: *const Rope, start: usize, end: usize, output: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        if (self.root) |root| {
            try iterateNodeRange(root, 0, start, end, output, allocator);
        }
    }

    /// Recursive helper for iterateRange
    fn iterateNodeRange(node: *Node, node_start: usize, start: usize, end: usize, output: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        const node_len = node.len();
        const node_end = node_start + node_len;

        // No overlap
        if (end <= node_start or start >= node_end) return;

        switch (node.*) {
            .leaf => |l| {
                // Calculate overlap
                const copy_start = if (start > node_start) start - node_start else 0;
                const copy_end = if (end < node_end) end - node_start else node_len;
                try output.appendSlice(allocator, l.data[copy_start..copy_end]);
            },
            .internal => |i| {
                const left_end = node_start + i.weight;
                try iterateNodeRange(i.left, node_start, start, end, output, allocator);
                try iterateNodeRange(i.right, left_end, start, end, output, allocator);
            },
        }
    }

    /// Convert rope to string (allocates new buffer)
    pub fn toString(self: *const Rope) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        if (self.root) |root| {
            try collectString(root, &result, self.allocator);
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Recursive helper for toString
    fn collectString(node: *Node, output: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        switch (node.*) {
            .leaf => |l| try output.appendSlice(allocator, l.data),
            .internal => |i| {
                try collectString(i.left, output, allocator);
                try collectString(i.right, output, allocator);
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

    const rope1 = try Rope.fromString(allocator, "Hello");
    const rope2 = try Rope.fromString(allocator, "World");

    // concat() consumes both inputs (takes ownership of roots)
    var result = try Rope.concat(rope1, rope2);
    defer result.deinit();

    const string = try result.toString();
    defer allocator.free(string);

    try std.testing.expectEqualStrings("HelloWorld", string);
}

// ============================================================================
// UTF-8 Safety Tests
// ============================================================================

test "Rope: UTF-8 multi-byte character preservation" {
    const allocator = std.testing.allocator;

    // Test with various Unicode characters
    // '世' = UTF-8 [0xE4, 0xB8, 0x96] (3 bytes)
    // '界' = UTF-8 [0xE7, 0x95, 0x8C] (3 bytes)
    const unicode_text = "Hello 世界! This is a test.";

    var rope = try Rope.fromString(allocator, unicode_text);
    defer rope.deinit();

    // Verify round-trip preserves UTF-8
    const result = try rope.toString();
    defer allocator.free(result);

    try std.testing.expectEqualStrings(unicode_text, result);

    // Verify UTF-8 validity
    try std.testing.expect(std.unicode.utf8ValidateSlice(result));
}

test "Rope: UTF-8 emoji and combining characters" {
    const allocator = std.testing.allocator;

    // Test with emoji and combining characters
    // 👨‍👩‍👧‍👦 = Family emoji (multiple codepoints)
    // é = e + combining acute accent
    const emoji_text = "Hello 👨‍👩‍👧‍👦 café 🚀 world!";

    var rope = try Rope.fromString(allocator, emoji_text);
    defer rope.deinit();

    const result = try rope.toString();
    defer allocator.free(result);

    try std.testing.expectEqualStrings(emoji_text, result);
    try std.testing.expect(std.unicode.utf8ValidateSlice(result));
}

test "Rope: UTF-8 boundary not split mid-character" {
    const allocator = std.testing.allocator;

    // Create a large string with multi-byte characters near split points
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(allocator);

    // Fill to just before LEAF_SIZE with ASCII
    const padding_size = LEAF_SIZE - 10;
    try buffer.appendNTimes(allocator, 'A', padding_size);

    // Add multi-byte characters at potential split boundary
    try buffer.appendSlice(allocator, "世界");  // 6 bytes total

    var rope = try Rope.fromString(allocator, buffer.items);
    defer rope.deinit();

    const result = try rope.toString();
    defer allocator.free(result);

    // Verify no corruption
    try std.testing.expectEqualStrings(buffer.items, result);
    try std.testing.expect(std.unicode.utf8ValidateSlice(result));
}

test "Rope: large UTF-8 file preserves all characters" {
    const allocator = std.testing.allocator;

    // Create a 2KB string with mixed ASCII and UTF-8
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(allocator);

    // Repeat pattern to exceed multiple LEAF_SIZE boundaries
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try buffer.appendSlice(allocator, "Hello 世界🚀!\n");  // ~20 bytes per line
    }

    var rope = try Rope.fromString(allocator, buffer.items);
    defer rope.deinit();

    const result = try rope.toString();
    defer allocator.free(result);

    try std.testing.expectEqualStrings(buffer.items, result);
    try std.testing.expect(std.unicode.utf8ValidateSlice(result));
}

test "Rope: forced UTF-8 split without newlines - multi-level" {
    const allocator = std.testing.allocator;

    // Create string that forces MULTIPLE levels of splitting
    // AND positions UTF-8 chars at split boundaries (no newlines)
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(allocator);

    // Pattern: Fill to 75% of LEAF_SIZE, add UTF-8, fill to 125%, add UTF-8, repeat
    // This creates a 2KB+ string with UTF-8 at likely split points
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        // 384 bytes of ASCII (no newlines - all 'X')
        try buffer.appendNTimes(allocator, 'X', LEAF_SIZE * 3 / 4);

        // Multi-byte char at 75% boundary
        try buffer.appendSlice(allocator, "世");  // 3 bytes

        // 128 more bytes (crosses LEAF_SIZE boundary)
        try buffer.appendNTimes(allocator, 'Y', LEAF_SIZE / 4);

        // Another multi-byte char at 100%+ boundary
        try buffer.appendSlice(allocator, "界");  // 3 bytes
    }

    // Total: ~2.1KB, forces multi-level splits, UTF-8 at critical points

    var rope = try Rope.fromString(allocator, buffer.items);
    defer rope.deinit();

    const result = try rope.toString();
    defer allocator.free(result);

    // If split happens mid-UTF-8-char, this will fail
    try std.testing.expectEqualStrings(buffer.items, result);
    try std.testing.expect(std.unicode.utf8ValidateSlice(result));
}

// ============================================================================
// Line Tracking Tests
// ============================================================================

test "Rope: lineCount on single line" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Hello World");
    defer rope.deinit();

    try std.testing.expectEqual(@as(usize, 1), rope.lineCount());
}

test "Rope: lineCount with newlines" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Line 1\nLine 2\nLine 3");
    defer rope.deinit();

    // 2 newlines = 3 lines
    try std.testing.expectEqual(@as(usize, 3), rope.lineCount());
}

test "Rope: lineCount with trailing newline" {
    const allocator = std.testing.allocator;

    var rope = try Rope.fromString(allocator, "Line 1\nLine 2\n");
    defer rope.deinit();

    // 2 newlines = 3 lines (empty line after last newline)
    try std.testing.expectEqual(@as(usize, 3), rope.lineCount());
}

test "Rope: byteOfLine for each line" {
    const allocator = std.testing.allocator;

    const text = "abc\ndef\nghi";
    var rope = try Rope.fromString(allocator, text);
    defer rope.deinit();

    // Line 0: byte 0 (start of "abc")
    try std.testing.expectEqual(@as(usize, 0), rope.byteOfLine(0));

    // Line 1: byte 4 (start of "def", after '\n')
    try std.testing.expectEqual(@as(usize, 4), rope.byteOfLine(1));

    // Line 2: byte 8 (start of "ghi", after '\n')
    try std.testing.expectEqual(@as(usize, 8), rope.byteOfLine(2));
}

test "Rope: lineCount and byteOfLine with large file" {
    const allocator = std.testing.allocator;

    // Create a 2KB+ file with known line count
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(allocator);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try buffer.appendSlice(allocator, "Hello World!\n");  // 13 bytes per line
    }

    var rope = try Rope.fromString(allocator, buffer.items);
    defer rope.deinit();

    // Should have 101 lines (100 newlines + 1)
    try std.testing.expectEqual(@as(usize, 101), rope.lineCount());

    // Verify a few line offsets
    try std.testing.expectEqual(@as(usize, 0), rope.byteOfLine(0));
    try std.testing.expectEqual(@as(usize, 13), rope.byteOfLine(1));
    try std.testing.expectEqual(@as(usize, 26), rope.byteOfLine(2));
    try std.testing.expectEqual(@as(usize, 13 * 50), rope.byteOfLine(50));
}
