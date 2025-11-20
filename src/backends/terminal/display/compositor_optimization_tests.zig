const std = @import("std");
const testing = std.testing;
const Compositor = @import("compositor.zig").Compositor;
const Layer = @import("layer.zig").Layer;
const Cell = @import("screen_grid.zig").Cell;
const Color = @import("../../../editor/config/highlights.zig").Color;

// Test Week 3 Optimization: Fast-path blending for opacity 1.0
test "compositor: fast-path for fully opaque cells" {
    const allocator = testing.allocator;

    var compositor = try Compositor.init(allocator, 24, 80);
    defer compositor.deinit();

    var layer = try Layer.init(allocator, 0, 0, 24, 80, "test_layer");
    defer layer.deinit();

    // Set layer opacity to 1.0 (fully opaque)
    layer.opacity = 1.0;
    layer.dirty = true;

    // Put a character in the layer
    layer.grid.setCell(0, 0, Cell{
        .char = 'A',
        .fg = Color{ .r = 255, .g = 0, .b = 0 }, // Red
        .bg = null,
    });

    // Composite the layer
    const layers = [_]*Layer{&layer};
    try compositor.composite(&layers);

    // Verify the output contains the character (fast-path should have been used)
    const result = compositor.output_grid.getCell(0, 0) orelse unreachable;
    try testing.expectEqual(@as(u21, 'A'), result.char);

    // Verify metrics show fast-path was used
    const stats = compositor.getStats();
    try testing.expect(stats.cells_fast_path_blended > 0);
    try testing.expectEqual(@as(usize, 0), stats.cells_slow_path_blended); // No slow-path
}

// Test Week 3 Optimization: Integer blending for semi-transparent cells
test "compositor: integer blending for semi-transparent cells" {
    const allocator = testing.allocator;

    var compositor = try Compositor.init(allocator, 24, 80);
    defer compositor.deinit();

    var layer1 = try Layer.init(allocator, 0, 0, 24, 80, "layer1");
    defer layer1.deinit();
    layer1.opacity = 1.0;
    layer1.dirty = true;

    var layer2 = try Layer.init(allocator, 1, 100, 24, 80, "layer2");
    defer layer2.deinit();
    layer2.opacity = 0.5; // Semi-transparent
    layer2.dirty = true;

    // Layer 1: Red background
    layer1.grid.setCell(0, 0, Cell{
        .char = 'A',
        .fg = Color{ .r = 255, .g = 0, .b = 0 }, // Red
        .bg = null,
    });

    // Layer 2: Blue foreground (semi-transparent)
    layer2.grid.setCell(0, 0, Cell{
        .char = 'B',
        .fg = Color{ .r = 0, .g = 0, .b = 255 }, // Blue
        .bg = null,
    });

    // Composite both layers
    const layers = [_]*Layer{ &layer1, &layer2 };
    try compositor.composite(&layers);

    // Verify metrics show slow-path was used
    const stats = compositor.getStats();
    try testing.expect(stats.cells_slow_path_blended > 0);

    // Verify blending occurred (color should be between red and blue)
    const result = compositor.output_grid.getCell(0, 0) orelse unreachable;
    try testing.expectEqual(@as(u21, 'B'), result.char); // Top layer char

    if (result.fg) |fg| {
        // Blended color: 50% blue (0,0,255) + 50% red (255,0,0) = ~(127,0,127)
        // Allow some tolerance for integer rounding
        try testing.expect(fg.r > 100 and fg.r < 150); // ~127
        try testing.expect(fg.g < 10); // ~0
        try testing.expect(fg.b > 100 and fg.b < 150); // ~127
    } else {
        return error.ExpectedForegroundColor;
    }
}

// Test Week 3 Optimization: Metrics tracking
test "compositor: tracks fast-path and slow-path metrics" {
    const allocator = testing.allocator;

    var compositor = try Compositor.init(allocator, 24, 80);
    defer compositor.deinit();

    // Create two layers with different opacities
    var layer_opaque = try Layer.init(allocator, 0, 0, 24, 80, "opaque");
    defer layer_opaque.deinit();
    layer_opaque.opacity = 1.0;
    layer_opaque.dirty = true;

    var layer_transparent = try Layer.init(allocator, 1, 100, 24, 80, "transparent");
    defer layer_transparent.deinit();
    layer_transparent.opacity = 0.7;
    layer_transparent.dirty = true;

    // Add cells to both layers
    for (0..10) |col| {
        layer_opaque.grid.setCell(0, col, Cell{
            .char = 'A',
            .fg = Color{ .r = 255, .g = 0, .b = 0 },
            .bg = null,
        });

        layer_transparent.grid.setCell(0, col, Cell{
            .char = 'B',
            .fg = Color{ .r = 0, .g = 255, .b = 0 },
            .bg = null,
        });
    }

    // Composite layers
    const layers = [_]*Layer{ &layer_opaque, &layer_transparent };
    try compositor.composite(&layers);

    // Verify metrics
    const stats = compositor.getStats();

    // Fast-path should be used for opaque layer (10 cells)
    try testing.expect(stats.cells_fast_path_blended >= 10);

    // Slow-path should be used for transparent layer (10 cells)
    try testing.expect(stats.cells_slow_path_blended >= 10);

    // Total blended should be sum of both
    try testing.expect(stats.cells_blended >= 20);
}

// Benchmark: Measure actual compositor performance
test "compositor: benchmark fast-path vs slow-path" {
    const allocator = testing.allocator;

    const iterations = 1000;

    // Benchmark 1: Fast-path (opacity 1.0)
    {
        var compositor = try Compositor.init(allocator, 24, 80);
        defer compositor.deinit();

        var layer = try Layer.init(allocator, 0, 0, 24, 80, "bench_fast");
        defer layer.deinit();
        layer.opacity = 1.0;
        layer.dirty = true;

        // Fill layer with cells
        for (0..24) |row| {
            for (0..80) |col| {
                layer.grid.setCell(row, col, Cell{
                    .char = 'X',
                    .fg = Color{ .r = 255, .g = 255, .b = 255 },
                    .bg = null,
                });
            }
        }

        const layers = [_]*Layer{&layer};

        const start = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            try compositor.composite(&layers);
        }
        const end = std.time.nanoTimestamp();

        const elapsed_ns = @as(u64, @intCast(end - start));
        const avg_ns = elapsed_ns / iterations;

        std.debug.print("\n[BENCHMARK] Fast-path compositor ({d} iterations):\n", .{iterations});
        std.debug.print("  Total time: {d}ms\n", .{elapsed_ns / 1_000_000});
        std.debug.print("  Avg per composite: {d}μs\n", .{avg_ns / 1_000});
        std.debug.print("  Fast-path cells: {d}\n", .{compositor.stats.cells_fast_path_blended});
        std.debug.print("  Slow-path cells: {d}\n", .{compositor.stats.cells_slow_path_blended});
    }

    // Benchmark 2: Slow-path (opacity 0.5)
    {
        var compositor = try Compositor.init(allocator, 24, 80);
        defer compositor.deinit();

        // Create base layer (opaque)
        var base_layer = try Layer.init(allocator, 0, 0, 24, 80, "base");
        defer base_layer.deinit();
        base_layer.opacity = 1.0;
        base_layer.dirty = true;

        // Create transparent layer
        var trans_layer = try Layer.init(allocator, 1, 100, 24, 80, "bench_slow");
        defer trans_layer.deinit();
        trans_layer.opacity = 0.5;
        trans_layer.dirty = true;

        // Fill both layers
        for (0..24) |row| {
            for (0..80) |col| {
                base_layer.grid.setCell(row, col, Cell{
                    .char = 'A',
                    .fg = Color{ .r = 255, .g = 0, .b = 0 },
                    .bg = null,
                });

                trans_layer.grid.setCell(row, col, Cell{
                    .char = 'B',
                    .fg = Color{ .r = 0, .g = 255, .b = 0 },
                    .bg = null,
                });
            }
        }

        const layers = [_]*Layer{ &base_layer, &trans_layer };

        const start = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            try compositor.composite(&layers);
        }
        const end = std.time.nanoTimestamp();

        const elapsed_ns = @as(u64, @intCast(end - start));
        const avg_ns = elapsed_ns / iterations;

        std.debug.print("\n[BENCHMARK] Slow-path compositor ({d} iterations):\n", .{iterations});
        std.debug.print("  Total time: {d}ms\n", .{elapsed_ns / 1_000_000});
        std.debug.print("  Avg per composite: {d}μs\n", .{avg_ns / 1_000});
        std.debug.print("  Fast-path cells: {d}\n", .{compositor.stats.cells_fast_path_blended});
        std.debug.print("  Slow-path cells: {d}\n", .{compositor.stats.cells_slow_path_blended});
    }
}
