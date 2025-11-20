const std = @import("std");
const testing = std.testing;
const output_renderer = @import("output_renderer.zig");
const Update = @import("screen_grid.zig").Update;
const Cell = @import("screen_grid.zig").Cell;
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const Color = @import("../../../editor/config/highlights.zig").Color;

// Test Week 4 Optimization: Updates are sorted by (row, col)
test "terminal batching: updates sorted correctly" {
    const allocator = testing.allocator;

    // Create a test grid
    var grid = try ScreenGrid.init(allocator, 80, 24);
    defer grid.deinit();

    // Create unsorted updates
    const unsorted_updates = [_]Update{
        .{ .row = 2, .col = 5, .cell = Cell{ .char = 'A', .fg = null, .bg = null } },
        .{ .row = 0, .col = 10, .cell = Cell{ .char = 'B', .fg = null, .bg = null } },
        .{ .row = 2, .col = 6, .cell = Cell{ .char = 'C', .fg = null, .bg = null } },
        .{ .row = 1, .col = 0, .cell = Cell{ .char = 'D', .fg = null, .bg = null } },
    };

    // Generate ANSI output (internally sorts updates)
    const result = try output_renderer.generateANSI(allocator, &unsorted_updates, &grid);
    defer {
        allocator.free(result.ansi_bytes);
        for (result.breakdown) |cmd| {
            allocator.free(cmd.seq);
            allocator.free(cmd.desc);
        }
        allocator.free(result.breakdown);
    }

    // Verify that updates_sorted metric is correct
    try testing.expectEqual(@as(usize, 4), result.optimizations.updates_sorted);

    // Verify ANSI output is correct (sorted order should be: (0,10), (1,0), (2,5), (2,6))
    // This is harder to test directly, so we check the breakdown contains expected moves
    var has_0_10 = false;
    var has_1_0 = false;
    var has_2_5 = false;
    var has_2_6 = false;

    for (result.breakdown) |cmd| {
        if (std.mem.indexOf(u8, cmd.desc, "row=0, col=10") != null) has_0_10 = true;
        if (std.mem.indexOf(u8, cmd.desc, "row=1, col=0") != null) has_1_0 = true;
        if (std.mem.indexOf(u8, cmd.desc, "row=2, col=5") != null) has_2_5 = true;
        if (std.mem.indexOf(u8, cmd.desc, "row=2, col=6") != null) has_2_6 = true;
    }

    try testing.expect(has_0_10);
    try testing.expect(has_1_0);
    try testing.expect(has_2_5);
    // Note: (2,6) is adjacent to (2,5), so cursor move may be skipped
}

// Test Week 4 Optimization: Adjacent cells are detected after sorting
test "terminal batching: adjacent cells detected" {
    const allocator = testing.allocator;

    var grid = try ScreenGrid.init(allocator, 80, 24);
    defer grid.deinit();

    // Create updates that are adjacent when sorted
    const updates = [_]Update{
        .{ .row = 0, .col = 5, .cell = Cell{ .char = 'A', .fg = null, .bg = null } },
        .{ .row = 0, .col = 6, .cell = Cell{ .char = 'B', .fg = null, .bg = null } },
        .{ .row = 0, .col = 7, .cell = Cell{ .char = 'C', .fg = null, .bg = null } },
    };

    const result = try output_renderer.generateANSI(allocator, &updates, &grid);
    defer {
        allocator.free(result.ansi_bytes);
        for (result.breakdown) |cmd| {
            allocator.free(cmd.seq);
            allocator.free(cmd.desc);
        }
        allocator.free(result.breakdown);
    }

    // Should have 1 cursor move (to start position), then 2 adjacent writes
    try testing.expectEqual(@as(usize, 1), result.optimizations.cursor_moves_total);
    try testing.expectEqual(@as(usize, 2), result.optimizations.adjacent_cells_skipped);
}

// Test Week 4 Optimization: Unsorted vs sorted comparison
test "terminal batching: unsorted increases cursor moves" {
    const allocator = testing.allocator;

    var grid = try ScreenGrid.init(allocator, 80, 24);
    defer grid.deinit();

    // Create scattered updates
    const scattered_updates = [_]Update{
        .{ .row = 0, .col = 0, .cell = Cell{ .char = 'A', .fg = null, .bg = null } },
        .{ .row = 5, .col = 10, .cell = Cell{ .char = 'B', .fg = null, .bg = null } },
        .{ .row = 0, .col = 1, .cell = Cell{ .char = 'C', .fg = null, .bg = null } },
        .{ .row = 5, .col = 11, .cell = Cell{ .char = 'D', .fg = null, .bg = null } },
    };

    const result = try output_renderer.generateANSI(allocator, &scattered_updates, &grid);
    defer {
        allocator.free(result.ansi_bytes);
        for (result.breakdown) |cmd| {
            allocator.free(cmd.seq);
            allocator.free(cmd.desc);
        }
        allocator.free(result.breakdown);
    }

    // After sorting: (0,0), (0,1), (5,10), (5,11)
    // Expected: 1 move to (0,0), skip (0,1), move to (5,10), skip (5,11)
    // Total: 2 cursor moves, 2 adjacent skips
    try testing.expectEqual(@as(usize, 2), result.optimizations.cursor_moves_total);
    try testing.expectEqual(@as(usize, 2), result.optimizations.adjacent_cells_skipped);
}

// Benchmark: Measure cursor move reduction
test "terminal batching: benchmark sorted vs unsorted" {
    const allocator = testing.allocator;

    var grid = try ScreenGrid.init(allocator, 80, 24);
    defer grid.deinit();

    const iterations = 100;

    std.debug.print("\n[BENCHMARK] Terminal Batching ({d} iterations)\n", .{iterations});

    // Scenario 1: Horizontal line (many adjacent cells)
    {
        var updates = std.ArrayList(Update).init(allocator);
        defer updates.deinit();

        // 20 cells in a horizontal line
        for (0..20) |col| {
            try updates.append(.{
                .row = 0,
                .col = col,
                .cell = Cell{ .char = 'X', .fg = null, .bg = null },
            });
        }

        var total_cursor_moves: usize = 0;
        var total_adjacent_skips: usize = 0;

        for (0..iterations) |_| {
            const result = try output_renderer.generateANSI(allocator, updates.items, &grid);
            defer {
                allocator.free(result.ansi_bytes);
                for (result.breakdown) |cmd| {
                    allocator.free(cmd.seq);
                    allocator.free(cmd.desc);
                }
                allocator.free(result.breakdown);
            }

            total_cursor_moves += result.optimizations.cursor_moves_total;
            total_adjacent_skips += result.optimizations.adjacent_cells_skipped;
        }

        const avg_cursor_moves = total_cursor_moves / iterations;
        const avg_adjacent_skips = total_adjacent_skips / iterations;

        std.debug.print("\nScenario: Horizontal line (20 cells)\n", .{});
        std.debug.print("  Avg cursor moves: {d}\n", .{avg_cursor_moves});
        std.debug.print("  Avg adjacent skips: {d}\n", .{avg_adjacent_skips});
        std.debug.print("  Reduction: {d}%\n", .{(avg_adjacent_skips * 100) / 20});
    }

    // Scenario 2: Scattered updates
    {
        var updates = std.ArrayList(Update).init(allocator);
        defer updates.deinit();

        // 20 scattered cells (simulate random diff output)
        var row: usize = 0;
        var col: usize = 0;
        for (0..20) |_| {
            try updates.append(.{
                .row = row,
                .col = col,
                .cell = Cell{ .char = 'Y', .fg = null, .bg = null },
            });
            row = (row + 3) % 24; // Jump rows
            col = (col + 17) % 80; // Jump columns
        }

        var total_cursor_moves: usize = 0;
        var total_adjacent_skips: usize = 0;

        for (0..iterations) |_| {
            const result = try output_renderer.generateANSI(allocator, updates.items, &grid);
            defer {
                allocator.free(result.ansi_bytes);
                for (result.breakdown) |cmd| {
                    allocator.free(cmd.seq);
                    allocator.free(cmd.desc);
                }
                allocator.free(result.breakdown);
            }

            total_cursor_moves += result.optimizations.cursor_moves_total;
            total_adjacent_skips += result.optimizations.adjacent_cells_skipped;
        }

        const avg_cursor_moves = total_cursor_moves / iterations;
        const avg_adjacent_skips = total_adjacent_skips / iterations;

        std.debug.print("\nScenario: Scattered updates (20 cells)\n", .{});
        std.debug.print("  Avg cursor moves: {d}\n", .{avg_cursor_moves});
        std.debug.print("  Avg adjacent skips: {d}\n", .{avg_adjacent_skips});
        if (avg_adjacent_skips > 0) {
            std.debug.print("  Reduction: {d}%\n", .{(avg_adjacent_skips * 100) / 20});
        } else {
            std.debug.print("  Reduction: 0%\n", .{});
        }
    }
}
