const std = @import("std");
const ScreenGrid = @import("screen_grid").ScreenGrid;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a grid
    var grid = try ScreenGrid.init(allocator, 80, 24);
    defer grid.deinit();

    // Test cases: different emoji patterns
    const test_cases = [_][]const u8{
        "- 🖥️ Terminal",  // Modern emoji + VS-16
        "- ⚙️ Basic",      // Older emoji + VS-16
        "- ⚡ High",       // Older emoji no VS-16
        "- 📝 Text",       // Modern emoji no VS-16
    };

    std.debug.print("\n=== EMOJI GRID DEBUG ===\n\n", .{});

    for (test_cases, 0..) |test_str, test_idx| {
        // Render the string
        const end_col = grid.setString(0, 0, test_str, null, null);

        std.debug.print("Test {}: {s}\n", .{ test_idx + 1, test_str });
        std.debug.print("  End column: {}\n", .{end_col});
        std.debug.print("  Bytes: ", .{});
        for (test_str) |byte| {
            std.debug.print("{X:02} ", .{byte});
        }
        std.debug.print("\n\n", .{});

        // Print grid layout
        std.debug.print("  Grid cells:\n", .{});
        for (0..@min(end_col + 3, 20)) |col| {
            const cell = grid.getCell(0, col).?;

            // Format character display
            const char_str = if (cell.char == ' ')
                "(space)"
            else if (cell.char >= 32 and cell.char <= 126)
                blk: {
                    var buf: [8]u8 = undefined;
                    break :blk try std.fmt.bufPrint(&buf, "'{c}'", .{@as(u8, @intCast(cell.char))});
                }
            else
                blk: {
                    var buf: [16]u8 = undefined;
                    break :blk try std.fmt.bufPrint(&buf, "U+{X:04}", .{cell.char});
                };

            // Determine width by checking if next cell is a continuation
            const width: u8 = if (col + 1 < 80 and grid.getCell(0, col + 1)) |next_cell|
                if (next_cell.is_continuation) 2 else 1
            else
                1;

            std.debug.print("    [{d:2}] {s:10} w={d} cont={} comb={d}", .{
                col,
                char_str,
                width,
                cell.is_continuation,
                cell.combining_count,
            });

            // Show combining characters
            if (cell.combining_count > 0) {
                std.debug.print(" [", .{});
                for (0..cell.combining_count) |i| {
                    std.debug.print("U+{X:04}", .{cell.combining[i]});
                    if (i < cell.combining_count - 1) std.debug.print(", ", .{});
                }
                std.debug.print("]", .{});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("\n  ═══════════════════════════════════════\n\n", .{});

        // Clear grid for next test
        grid.clear();
    }
}
