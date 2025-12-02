// highlight_cache.zig - Buffer-level syntax highlighting cache
//
// Design: Cache tree-sitter highlights per-line to avoid re-computation on every render.
// Invalidation: When buffer content changes, only affected lines are re-computed.
// Zero-copy: Highlight data can be exposed to JavaScript via ArrayBuffer.
//
// Performance target: First render computes highlights (~5ms for 1000 lines),
// subsequent renders read from cache (~0.1ms).

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import Style from highlight_api for direct caching
const highlight_api = @import("../system/jsi/highlight_api.zig");
pub const Style = highlight_api.Style;

/// Style span for direct rendering (stores actual Style, not ID)
/// Used for caching computed tree-sitter results
pub const StyleSpan = struct {
    start_byte: u32,
    end_byte: u32,
    style: Style,
};

/// Cached styles for a single line (for direct rendering use)
pub const CachedLineStyles = struct {
    spans: []StyleSpan,
    version: u64,

    pub fn deinit(self: *CachedLineStyles, allocator: Allocator) void {
        if (self.spans.len > 0) {
            allocator.free(self.spans);
        }
        self.spans = &[_]StyleSpan{};
    }

    /// Populate a highlight map from cached spans
    pub fn populateMap(self: *const CachedLineStyles, map: *std.AutoHashMap(usize, Style), line_start_byte: usize) void {
        for (self.spans) |span| {
            var byte_offset: usize = span.start_byte;
            while (byte_offset < span.end_byte) : (byte_offset += 1) {
                // Offset is relative to line start for the map
                if (byte_offset >= line_start_byte) {
                    map.put(byte_offset - line_start_byte, span.style) catch {};
                }
            }
        }
    }
};

/// Compact highlight span within a line
/// Using u16 for column positions (max 65535 columns per line)
pub const HighlightSpan = packed struct {
    /// Start column (byte offset within line)
    start_col: u16,
    /// End column (byte offset within line, exclusive)
    end_col: u16,
    /// Style ID (index into style registry)
    style_id: u16,
    /// Padding for alignment
    _padding: u16 = 0,

    pub fn init(start: usize, end: usize, style: u16) HighlightSpan {
        return .{
            .start_col = @intCast(@min(start, std.math.maxInt(u16))),
            .end_col = @intCast(@min(end, std.math.maxInt(u16))),
            .style_id = style,
        };
    }
};

/// Cached highlights for a single line
pub const LineHighlights = struct {
    /// Highlight spans for this line (sorted by start_col)
    spans: []HighlightSpan,
    /// Version when this line was last computed
    version: u64,

    pub fn deinit(self: *LineHighlights, allocator: Allocator) void {
        if (self.spans.len > 0) {
            allocator.free(self.spans);
        }
        self.spans = &[_]HighlightSpan{};
    }
};

/// Style entry in the style registry
/// Stores actual color values to avoid repeated highlight group lookups
pub const CachedStyle = struct {
    fg: ?u24 = null, // RGB color or null for default
    bg: ?u24 = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
};

/// Buffer-level highlight cache
pub const HighlightCache = struct {
    allocator: Allocator,

    /// Per-line highlight data (indexed by line number) - for compact storage
    lines: std.ArrayList(?LineHighlights),

    /// Per-line style cache (indexed by line number) - for direct rendering
    /// Stores actual Style objects for fast render-time lookup
    style_lines: std.ArrayList(?CachedLineStyles),

    /// Style registry - maps style_id to actual style
    /// Avoids storing full style data in every span
    styles: std.ArrayList(CachedStyle),

    /// Style name to ID mapping for deduplication
    style_map: std.StringHashMap(u16),

    /// Current buffer version (incremented on each edit)
    buffer_version: u64,

    /// Filetype for this cache (null if no syntax highlighting)
    filetype: ?[]const u8,

    /// Whether cache is fully computed (all visible lines)
    is_complete: bool,

    /// Statistics for debugging/profiling
    stats: CacheStats,

    pub const CacheStats = struct {
        cache_hits: u64 = 0,
        cache_misses: u64 = 0,
        lines_computed: u64 = 0,
        total_spans: u64 = 0,
        last_compute_time_ns: i128 = 0,
    };

    pub fn init(allocator: Allocator) HighlightCache {
        return .{
            .allocator = allocator,
            .lines = .empty,
            .style_lines = .empty,
            .styles = .empty,
            .style_map = std.StringHashMap(u16).init(allocator),
            .buffer_version = 0,
            .filetype = null,
            .is_complete = false,
            .stats = .{},
        };
    }

    pub fn deinit(self: *HighlightCache) void {
        // Free all line highlights
        for (self.lines.items) |*maybe_line| {
            if (maybe_line.*) |*line| {
                line.deinit(self.allocator);
            }
        }
        self.lines.deinit(self.allocator);

        // Free all style line caches
        for (self.style_lines.items) |*maybe_line| {
            if (maybe_line.*) |*line| {
                line.deinit(self.allocator);
            }
        }
        self.style_lines.deinit(self.allocator);

        // Free style map keys (we own the strings)
        var key_iter = self.style_map.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.style_map.deinit();

        self.styles.deinit(self.allocator);

        if (self.filetype) |ft| {
            self.allocator.free(ft);
        }
    }

    /// Set filetype and invalidate entire cache
    pub fn setFiletype(self: *HighlightCache, filetype: ?[]const u8) !void {
        // Free old filetype
        if (self.filetype) |old_ft| {
            self.allocator.free(old_ft);
        }

        // Store new filetype
        if (filetype) |ft| {
            self.filetype = try self.allocator.dupe(u8, ft);
        } else {
            self.filetype = null;
        }

        // Invalidate entire cache
        self.invalidateAll();
    }

    /// Invalidate all cached highlights
    pub fn invalidateAll(self: *HighlightCache) void {
        for (self.lines.items) |*maybe_line| {
            if (maybe_line.*) |*line| {
                line.deinit(self.allocator);
            }
            maybe_line.* = null;
        }
        // Also invalidate style_lines
        for (self.style_lines.items) |*maybe_line| {
            if (maybe_line.*) |*line| {
                line.deinit(self.allocator);
            }
            maybe_line.* = null;
        }
        self.buffer_version += 1;
        self.is_complete = false;
    }

    /// Invalidate highlights for a range of lines
    /// Called when buffer content changes
    pub fn invalidateRange(self: *HighlightCache, start_line: usize, end_line: usize) void {
        const actual_end = @min(end_line, self.lines.items.len);
        if (start_line < actual_end) {
            for (start_line..actual_end) |line_num| {
                if (self.lines.items[line_num]) |*line| {
                    line.deinit(self.allocator);
                    self.lines.items[line_num] = null;
                }
            }
        }
        // Also invalidate style_lines
        const style_actual_end = @min(end_line, self.style_lines.items.len);
        if (start_line < style_actual_end) {
            for (start_line..style_actual_end) |line_num| {
                if (self.style_lines.items[line_num]) |*line| {
                    line.deinit(self.allocator);
                    self.style_lines.items[line_num] = null;
                }
            }
        }
        self.buffer_version += 1;
        self.is_complete = false;
    }

    /// Invalidate from a line to end of buffer (for insertions/deletions)
    pub fn invalidateFromLine(self: *HighlightCache, start_line: usize) void {
        self.invalidateRange(start_line, @max(self.lines.items.len, self.style_lines.items.len));
    }

    /// Ensure capacity for given number of lines
    pub fn ensureCapacity(self: *HighlightCache, line_count: usize) !void {
        while (self.lines.items.len < line_count) {
            try self.lines.append(self.allocator, null);
        }
    }

    /// Ensure capacity for style_lines
    pub fn ensureStyleCapacity(self: *HighlightCache, line_count: usize) !void {
        while (self.style_lines.items.len < line_count) {
            try self.style_lines.append(self.allocator, null);
        }
    }

    /// Check if line has cached styles
    pub fn hasStyleLine(self: *const HighlightCache, line_num: usize) bool {
        if (line_num >= self.style_lines.items.len) return false;
        return self.style_lines.items[line_num] != null;
    }

    /// Get cached styles for a line (null if not cached)
    pub fn getStyleLine(self: *HighlightCache, line_num: usize) ?*const CachedLineStyles {
        if (line_num >= self.style_lines.items.len) return null;
        if (self.style_lines.items[line_num]) |*line| {
            self.stats.cache_hits += 1;
            return line;
        }
        self.stats.cache_misses += 1;
        return null;
    }

    /// Store computed styles for a line
    pub fn setStyleLine(self: *HighlightCache, line_num: usize, spans: []const StyleSpan) !void {
        // Ensure capacity
        try self.ensureStyleCapacity(line_num + 1);

        // Free existing if present
        if (self.style_lines.items[line_num]) |*existing| {
            existing.deinit(self.allocator);
        }

        // Store new styles
        const spans_copy = try self.allocator.dupe(StyleSpan, spans);
        self.style_lines.items[line_num] = .{
            .spans = spans_copy,
            .version = self.buffer_version,
        };

        self.stats.lines_computed += 1;
        self.stats.total_spans += spans.len;
    }

    /// Get or create style ID for a highlight group
    pub fn getOrCreateStyleId(self: *HighlightCache, group_name: []const u8, style: CachedStyle) !u16 {
        // Check if style already registered
        if (self.style_map.get(group_name)) |id| {
            return id;
        }

        // Register new style
        const id: u16 = @intCast(self.styles.items.len);
        try self.styles.append(self.allocator, style);

        // Store name -> id mapping (duplicate the key)
        const key = try self.allocator.dupe(u8, group_name);
        try self.style_map.put(key, id);

        return id;
    }

    /// Get style by ID
    pub fn getStyle(self: *const HighlightCache, style_id: u16) ?CachedStyle {
        if (style_id < self.styles.items.len) {
            return self.styles.items[style_id];
        }
        return null;
    }

    /// Check if line has cached highlights
    pub fn hasLine(self: *const HighlightCache, line_num: usize) bool {
        if (line_num >= self.lines.items.len) return false;
        return self.lines.items[line_num] != null;
    }

    /// Get cached highlights for a line (null if not cached)
    pub fn getLine(self: *HighlightCache, line_num: usize) ?*const LineHighlights {
        if (line_num >= self.lines.items.len) return null;
        if (self.lines.items[line_num]) |*line| {
            self.stats.cache_hits += 1;
            return line;
        }
        self.stats.cache_misses += 1;
        return null;
    }

    /// Store computed highlights for a line
    pub fn setLine(self: *HighlightCache, line_num: usize, spans: []const HighlightSpan) !void {
        // Ensure capacity
        try self.ensureCapacity(line_num + 1);

        // Free existing if present
        if (self.lines.items[line_num]) |*existing| {
            existing.deinit(self.allocator);
        }

        // Store new highlights
        const spans_copy = try self.allocator.dupe(HighlightSpan, spans);
        self.lines.items[line_num] = .{
            .spans = spans_copy,
            .version = self.buffer_version,
        };

        self.stats.lines_computed += 1;
        self.stats.total_spans += spans.len;
    }

    /// Get highlights for a line, computing if necessary
    /// Returns slice of spans (caller should not free)
    pub fn getOrComputeLine(
        self: *HighlightCache,
        line_num: usize,
        compute_fn: *const fn (line_num: usize, ctx: *anyopaque) ?[]HighlightSpan,
        ctx: *anyopaque,
    ) ?[]const HighlightSpan {
        // Check cache first
        if (self.getLine(line_num)) |line| {
            return line.spans;
        }

        // Compute highlights
        const start_time = std.time.nanoTimestamp();
        if (compute_fn(line_num, ctx)) |spans| {
            defer self.allocator.free(spans); // compute_fn allocates, we copy
            self.setLine(line_num, spans) catch return null;
            self.stats.last_compute_time_ns = std.time.nanoTimestamp() - start_time;
            return self.lines.items[line_num].?.spans;
        }

        return null;
    }

    /// Get cache statistics
    pub fn getStats(self: *const HighlightCache) CacheStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *HighlightCache) void {
        self.stats = .{};
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HighlightCache: basic operations" {
    const allocator = std.testing.allocator;

    var cache = HighlightCache.init(allocator);
    defer cache.deinit();

    // Register a style
    const style_id = try cache.getOrCreateStyleId("Keyword", .{ .fg = 0xFF0000, .bold = true });
    try std.testing.expectEqual(@as(u16, 0), style_id);

    // Same style returns same ID
    const style_id2 = try cache.getOrCreateStyleId("Keyword", .{ .fg = 0xFF0000, .bold = true });
    try std.testing.expectEqual(style_id, style_id2);

    // Different style gets new ID
    const style_id3 = try cache.getOrCreateStyleId("String", .{ .fg = 0x00FF00 });
    try std.testing.expectEqual(@as(u16, 1), style_id3);

    // Set line highlights
    const spans = [_]HighlightSpan{
        HighlightSpan.init(0, 5, style_id),
        HighlightSpan.init(6, 10, style_id3),
    };
    try cache.setLine(0, &spans);

    // Get line highlights
    const line = cache.getLine(0);
    try std.testing.expect(line != null);
    try std.testing.expectEqual(@as(usize, 2), line.?.spans.len);
}

test "HighlightCache: invalidation" {
    const allocator = std.testing.allocator;

    var cache = HighlightCache.init(allocator);
    defer cache.deinit();

    const style_id = try cache.getOrCreateStyleId("Test", .{});

    // Set highlights for multiple lines
    const span = [_]HighlightSpan{HighlightSpan.init(0, 5, style_id)};
    try cache.setLine(0, &span);
    try cache.setLine(1, &span);
    try cache.setLine(2, &span);

    // Verify all cached
    try std.testing.expect(cache.hasLine(0));
    try std.testing.expect(cache.hasLine(1));
    try std.testing.expect(cache.hasLine(2));

    // Invalidate range
    cache.invalidateRange(1, 2);

    // Line 0 still cached, line 1 invalidated, line 2 still cached
    try std.testing.expect(cache.hasLine(0));
    try std.testing.expect(!cache.hasLine(1));
    try std.testing.expect(cache.hasLine(2));

    // Invalidate all
    cache.invalidateAll();
    try std.testing.expect(!cache.hasLine(0));
    try std.testing.expect(!cache.hasLine(2));
}

test "HighlightSpan: packed size" {
    // Ensure HighlightSpan is 8 bytes (compact for cache efficiency)
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(HighlightSpan));
}
