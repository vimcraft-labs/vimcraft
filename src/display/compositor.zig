const std = @import("std");
const Allocator = std.mem.Allocator;
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const Cell = @import("screen_grid.zig").Cell;
const Layer = @import("layer.zig").Layer;
const highlights = @import("../config/highlights.zig");
const Color = highlights.Color;

/// Compositor (blends multiple layers into final output grid)
/// Uses Porter-Duff alpha compositing for layer blending
/// Processes layers in z-index order (maintained by LayerManager)
pub const Compositor = struct {
    /// Output grid (final composited result)
    output_grid: ScreenGrid,

    /// Allocator
    allocator: Allocator,

    /// Statistics (for performance monitoring)
    stats: CompositorStats,

    /// Initialize compositor
    pub fn init(allocator: Allocator, height: usize, width: usize) !Compositor {
        return .{
            .output_grid = try ScreenGrid.init(allocator, width, height),
            .allocator = allocator,
            .stats = .{},
        };
    }

    /// Deinitialize compositor
    pub fn deinit(self: *Compositor) void {
        self.output_grid.deinit();
    }

    /// Resize output grid
    pub fn resize(self: *Compositor, new_height: usize, new_width: usize) !void {
        try self.output_grid.resize(new_width, new_height);
    }

    /// Composite all layers into output grid
    /// Layers must be sorted by z-index (lowest first)
    pub fn composite(self: *Compositor, layers: []const *Layer) !void {
        // Reset stats
        self.stats = .{};
        const start = std.time.nanoTimestamp();

        // Clear output grid
        self.output_grid.clear();

        // DEBUG: Log layer composition
        const debug_log = @import("../debug/log.zig");
        debug_log.log("=== COMPOSITOR: Starting composition ===", .{});
        debug_log.log("Total layers: {d}", .{layers.len});

        // Iterate layers in z-index order
        for (layers) |layer| {
            debug_log.log("Layer '{s}' (z={d}): enabled={}, dirty={}", .{
                layer.name,
                layer.z_index,
                layer.enabled,
                layer.dirty,
            });

            if (!layer.enabled) {
                self.stats.layers_skipped += 1;
                continue;
            }

            // Blend this layer onto output
            try self.blendLayer(layer);
            self.stats.layers_composited += 1;
            debug_log.log("  → Composited layer '{s}'", .{layer.name});
        }

        debug_log.log("=== COMPOSITOR: Done (composited={d}, skipped={d}) ===", .{
            self.stats.layers_composited,
            self.stats.layers_skipped,
        });

        // Record time
        const end = std.time.nanoTimestamp();
        self.stats.composite_time_ns = @intCast(end - start);
    }

    /// Composite only dirty layers (PHASE 6 OPTIMIZATION)
    /// Uses layer caching and incremental composition for maximum performance
    pub fn compositeIncremental(self: *Compositor, layers: []const *Layer) !void {
        // Reset stats
        self.stats = .{};
        const start = std.time.nanoTimestamp();

        // Find first dirty layer
        var first_dirty: ?usize = null;
        for (layers, 0..) |layer, i| {
            if (layer.dirty and layer.enabled) {
                first_dirty = i;
                break;
            }
        }

        // No dirty layers? All layers cached! Ultra-fast path
        if (first_dirty == null) {
            // Count cached layers
            for (layers) |layer| {
                if (layer.enabled and layer.cacheable and layer.cache_valid) {
                    self.stats.layers_cached += 1;
                    // Estimate cells from cache (assuming full grid)
                    self.stats.cells_from_cache += self.output_grid.width * self.output_grid.height;
                }
            }
            const end = std.time.nanoTimestamp();
            self.stats.composite_time_ns = @intCast(end - start);
            return;
        }

        // PHASE 6 FIX: Don't clear output grid!
        // Incremental composition means we only re-blend dirty layers
        // Cached layers stay in the output from previous frame
        // self.output_grid.clear(); // ← REMOVED! This was deleting cached content

        // Composite ALL layers (cached ones will be skipped but their previous
        // composition result remains in output_grid)
        for (layers[0..]) |layer| {
            if (!layer.enabled) {
                self.stats.layers_skipped += 1;
                continue;
            }

            // PHASE 6: Skip composition for cacheable layers that are clean
            if (layer.canSkipComposition()) {
                self.stats.layers_cached += 1;
                // Note: In a full implementation, we'd use the cached result
                // For now, we skip the layer entirely (optimization opportunity)
                continue;
            }

            try self.blendLayer(layer);
            self.stats.layers_composited += 1;

            // Mark layer as clean after composition
            if (layer.dirty) {
                // Layer will be marked clean by Display after rendering
            }
        }

        // Record time
        const end = std.time.nanoTimestamp();
        self.stats.composite_time_ns = @intCast(end - start);
    }

    /// Blend single layer onto output grid
    fn blendLayer(self: *Compositor, layer: *Layer) !void {
        const height = @min(self.output_grid.height, layer.grid.height);
        const width = @min(self.output_grid.width, layer.grid.width);

        for (0..height) |row| {
            for (0..width) |col| {
                const src = layer.grid.getCell(row, col) orelse continue;

                // Skip truly empty cells (no char and no colors)
                if ((src.char == 0 or src.char == ' ') and src.fg == null and src.bg == null) {
                    self.stats.cells_skipped += 1;
                    continue;
                }

                const dst_cell = self.output_grid.getCell(row, col);
                const dst = dst_cell orelse Cell{ .char = 0, .fg = null, .bg = null };

                // Blend cells using alpha compositing
                const result = blendCell(src, dst, layer.opacity);
                self.output_grid.setCell(row, col, result);
                self.stats.cells_blended += 1;
            }
        }
    }

    /// Get output grid (composited result)
    pub fn getOutput(self: *Compositor) *ScreenGrid {
        return &self.output_grid;
    }

    /// Get composition statistics
    pub fn getStats(self: *Compositor) CompositorStats {
        return self.stats;
    }

    /// Debug: Print composition stats
    pub fn debugPrintStats(self: *Compositor) void {
        const ms = @as(f64, @floatFromInt(self.stats.composite_time_ns)) / 1_000_000.0;
        std.debug.print("\n=== Compositor Stats ===\n", .{});
        std.debug.print("  Layers composited: {d}\n", .{self.stats.layers_composited});
        std.debug.print("  Layers skipped: {d}\n", .{self.stats.layers_skipped});
        std.debug.print("  Cells blended: {d}\n", .{self.stats.cells_blended});
        std.debug.print("  Cells skipped: {d}\n", .{self.stats.cells_skipped});
        std.debug.print("  Composite time: {d:.2}ms\n", .{ms});
        std.debug.print("========================\n\n", .{});
    }
};

/// Compositor statistics (for performance monitoring)
pub const CompositorStats = struct {
    layers_composited: usize = 0,
    layers_skipped: usize = 0,
    layers_cached: usize = 0, // Phase 6: cached layer count
    cells_blended: usize = 0,
    cells_skipped: usize = 0,
    cells_from_cache: usize = 0, // Phase 6: cells skipped due to caching
    composite_time_ns: i64 = 0,
};

/// Alpha blend two cells (Porter-Duff "over" operator)
/// Formula: result = src + dst * (1 - src.alpha)
/// Reference: https://en.wikipedia.org/wiki/Alpha_compositing
fn blendCell(src: Cell, dst: Cell, opacity: f32) Cell {
    // Fully opaque? Just replace
    if (opacity >= 1.0) return src;

    // Fully transparent? Keep dst
    if (opacity <= 0.0) return dst;

    // Blend foreground color
    var blended_fg: ?Color = null;
    if (src.fg) |src_fg| {
        if (dst.fg) |dst_fg| {
            // Blend two colors
            blended_fg = Color{
                .r = blendChannel(src_fg.r, dst_fg.r, opacity),
                .g = blendChannel(src_fg.g, dst_fg.g, opacity),
                .b = blendChannel(src_fg.b, dst_fg.b, opacity),
            };
        } else {
            // No dst fg, use src fg with opacity
            blended_fg = src_fg;
        }
    } else {
        // No src fg, keep dst fg
        blended_fg = dst.fg;
    }

    // Blend background color
    var blended_bg: ?Color = null;
    if (src.bg) |src_bg| {
        if (dst.bg) |dst_bg| {
            // Blend two colors
            blended_bg = Color{
                .r = blendChannel(src_bg.r, dst_bg.r, opacity),
                .g = blendChannel(src_bg.g, dst_bg.g, opacity),
                .b = blendChannel(src_bg.b, dst_bg.b, opacity),
            };
        } else {
            // No dst bg, use src bg with opacity
            blended_bg = src_bg;
        }
    } else {
        // No src bg, keep dst bg
        blended_bg = dst.bg;
    }

    // Return blended cell
    // PHASE 6 FIX: Keep dst char if src is just providing background (space/null)
    // This allows cursor layer to only affect background without hiding text
    const final_char = if (src.char == ' ' or src.char == 0)
        dst.char
    else
        src.char;

    return Cell{
        .char = final_char,
        .fg = blended_fg,
        .bg = blended_bg,
    };
}

/// Blend single color channel (0-255 range)
fn blendChannel(src: u8, dst: u8, alpha: f32) u8 {
    const src_f = @as(f32, @floatFromInt(src));
    const dst_f = @as(f32, @floatFromInt(dst));
    const result = src_f * alpha + dst_f * (1.0 - alpha);
    return @intFromFloat(@min(255.0, @max(0.0, result)));
}

// Tests
test "Compositor basic blending" {
    const allocator = std.testing.allocator;

    var compositor = try Compositor.init(allocator, 24, 80);
    defer compositor.deinit();

    var layer1 = try Layer.init(allocator, 0, 0, 24, 80, "layer1");
    defer layer1.deinit();

    var layer2 = try Layer.init(allocator, 1, 100, 24, 80, "layer2");
    defer layer2.deinit();

    // Put a character in layer1
    layer1.grid.setCell(0, 0, Cell{
        .char = 'A',
        .fg = Color{ .r = 255, .g = 0, .b = 0 },
        .bg = null,
    });

    // Put a different character in layer2 (same position)
    layer2.grid.setCell(0, 0, Cell{
        .char = 'B',
        .fg = Color{ .r = 0, .g = 255, .b = 0 },
        .bg = null,
    });

    // Composite layers
    const layers = [_]*Layer{ &layer1, &layer2 };
    try compositor.composite(&layers);

    // Layer2 should be on top (higher z-index)
    const result = compositor.output_grid.getCell(0, 0) orelse unreachable;
    try std.testing.expectEqual(@as(u21, 'B'), result.char);
}

test "Compositor opacity blending" {
    const allocator = std.testing.allocator;

    var compositor = try Compositor.init(allocator, 24, 80);
    defer compositor.deinit();

    var layer1 = try Layer.init(allocator, 0, 0, 24, 80, "layer1");
    defer layer1.deinit();

    var layer2 = try Layer.init(allocator, 1, 100, 24, 80, "layer2");
    defer layer2.deinit();

    // Layer2 is semi-transparent
    layer2.opacity = 0.5;

    // Put cells in both layers
    layer1.grid.setCell(0, 0, Cell{
        .char = 'A',
        .fg = Color{ .r = 255, .g = 0, .b = 0 }, // Red
        .bg = null,
    });

    layer2.grid.setCell(0, 0, Cell{
        .char = 'B',
        .fg = Color{ .r = 0, .g = 255, .b = 0 }, // Green
        .bg = null,
    });

    // Composite layers
    const layers = [_]*Layer{ &layer1, &layer2 };
    try compositor.composite(&layers);

    // Should blend colors (50% green, 50% red = ~127 for each)
    const result = compositor.output_grid.getCell(0, 0) orelse unreachable;
    try std.testing.expectEqual(@as(u21, 'B'), result.char); // Top layer char
    const fg = result.fg.?;
    // Blended color should be between red and green
    try std.testing.expect(fg.r > 100 and fg.r < 150); // ~127
    try std.testing.expect(fg.g > 100 and fg.g < 150); // ~127
}

test "Compositor skip disabled layers" {
    const allocator = std.testing.allocator;

    var compositor = try Compositor.init(allocator, 24, 80);
    defer compositor.deinit();

    var layer1 = try Layer.init(allocator, 0, 0, 24, 80, "layer1");
    defer layer1.deinit();

    var layer2 = try Layer.init(allocator, 1, 100, 24, 80, "layer2");
    defer layer2.deinit();

    // Disable layer2
    layer2.enabled = false;

    // Put cells in both layers
    layer1.grid.setCell(0, 0, Cell{ .char = 'A', .fg = null, .bg = null });
    layer2.grid.setCell(0, 0, Cell{ .char = 'B', .fg = null, .bg = null });

    // Composite layers
    const layers = [_]*Layer{ &layer1, &layer2 };
    try compositor.composite(&layers);

    // Should only see layer1 (layer2 is disabled)
    const result = compositor.output_grid.getCell(0, 0) orelse unreachable;
    try std.testing.expectEqual(@as(u21, 'A'), result.char);

    // Verify stats
    const stats = compositor.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.layers_composited);
    try std.testing.expectEqual(@as(usize, 1), stats.layers_skipped);
}
