const std = @import("std");
const Display = @import("display.zig").Display;
const highlights = @import("../../../editor/config/highlights.zig");
const Update = @import("screen_grid.zig").Update;
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;

/// ANSI command breakdown for debugging
pub const AnsiCommand = struct {
    seq: []const u8, // The ANSI escape sequence or character
    desc: []const u8, // Human-readable description
};

/// Optimization statistics for debugging
pub const Optimizations = struct {
    adjacent_cells_skipped: usize = 0, // Cursor moves skipped due to adjacency
    attribute_changes_deduped: usize = 0, // Attribute codes skipped (already set)
    char_zero_to_space: usize = 0, // char=0 converted to space

    // WEEK 4: Terminal output batching metrics
    cursor_moves_total: usize = 0, // Total cursor position codes sent
    updates_sorted: usize = 0, // Number of updates sorted for batching
};

/// Result of ANSI generation
pub const AnsiResult = struct {
    ansi_bytes: []const u8, // The complete ANSI output
    breakdown: []const AnsiCommand, // Step-by-step ANSI commands
    optimizations: Optimizations, // Stats on optimizations applied
};

/// Generate ANSI escape sequences for terminal updates (Debug Protocol support)
/// This is the core rendering logic extracted for both Terminal output and debugging
pub fn generateANSI(
    allocator: std.mem.Allocator,
    updates: []const Update,
    grid: *const ScreenGrid,
) !AnsiResult {
    if (updates.len == 0) {
        return AnsiResult{
            .ansi_bytes = &[_]u8{},
            .breakdown = &[_]AnsiCommand{},
            .optimizations = .{},
        };
    }

    // WEEK 4 OPTIMIZATION: Sort updates by (row, col) to maximize adjacency
    // This dramatically increases the effectiveness of adjacent cell skipping
    // Example: Updates at [(0,5), (1,0), (0,6)] become [(0,5), (0,6), (1,0)]
    //          → 1 cursor move saved (cells at col 5 and 6 are now adjacent in array)
    const sorted_updates = try allocator.dupe(Update, updates);
    defer allocator.free(sorted_updates);

    std.mem.sort(Update, sorted_updates, {}, struct {
        fn lessThan(_: void, a: Update, b: Update) bool {
            if (a.row != b.row) return a.row < b.row;
            return a.col < b.col;
        }
    }.lessThan);

    var buf: std.ArrayList(u8) = .empty;
    var breakdown: std.ArrayList(AnsiCommand) = .empty;
    var opts = Optimizations{
        .updates_sorted = sorted_updates.len, // Track number of updates sorted
    };

    // Track state to minimize ANSI codes (Helix optimization)
    var current_fg: ?highlights.Color = null;
    var current_bg: ?highlights.Color = null;
    var current_bold: bool = false;
    var current_italic: bool = false;
    var current_underline: bool = false;
    var last_pos: ?struct { row: usize, col: usize } = null;
    var last_had_combining: bool = false;

    // Process sorted updates (maximizes adjacent cell batching)
    for (sorted_updates) |update| {
        // Skip continuation cells - terminals handle double-width chars automatically
        if (update.cell.is_continuation) {
            continue;
        }

        // HELIX OPTIMIZATION 1: Skip cursor movement if adjacent
        const is_adjacent = if (last_pos) |pos|
            (update.row == pos.row and update.col == pos.col and !last_had_combining)
        else
            false;

        if (!is_adjacent) {
            // Move cursor to position
            const seq_start = buf.items.len;
            try buf.writer(allocator).print("\x1b[{d};{d}H", .{ update.row + 1, update.col + 1 });
            const seq = buf.items[seq_start..];

            const desc = try std.fmt.allocPrint(
                allocator,
                "Move cursor to row={d}, col={d}",
                .{ update.row, update.col },
            );
            try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = desc });

            // WEEK 4: Track cursor move count
            opts.cursor_moves_total += 1;
        } else {
            opts.adjacent_cells_skipped += 1;
        }

        // HELIX OPTIMIZATION 2: Only send attribute changes
        // Foreground color
        if (update.cell.fg) |fg| {
            if (current_fg == null or !colorEql(current_fg.?, fg)) {
                var color_buf: [32]u8 = undefined;
                const fg_code = try fg.toAnsiFg(&color_buf);
                const seq_start = buf.items.len;
                try buf.writer(allocator).writeAll(fg_code);
                const seq = buf.items[seq_start..];

                const desc = try std.fmt.allocPrint(
                    allocator,
                    "Set foreground RGB({d},{d},{d})",
                    .{ fg.r, fg.g, fg.b },
                );
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = desc });
                current_fg = fg;
            } else {
                opts.attribute_changes_deduped += 1;
            }
        } else if (current_fg != null) {
            const seq_start = buf.items.len;
            try buf.writer(allocator).writeAll("\x1b[39m");
            const seq = buf.items[seq_start..];
            try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Reset foreground") });
            current_fg = null;
        }

        // Background color
        if (update.cell.bg) |bg| {
            if (current_bg == null or !colorEql(current_bg.?, bg)) {
                var color_buf: [32]u8 = undefined;
                const bg_code = try bg.toAnsiBg(&color_buf);
                const seq_start = buf.items.len;
                try buf.writer(allocator).writeAll(bg_code);
                const seq = buf.items[seq_start..];

                const desc = try std.fmt.allocPrint(
                    allocator,
                    "Set background RGB({d},{d},{d})",
                    .{ bg.r, bg.g, bg.b },
                );
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = desc });
                current_bg = bg;
            } else {
                opts.attribute_changes_deduped += 1;
            }
        } else if (current_bg != null) {
            const seq_start = buf.items.len;
            try buf.writer(allocator).writeAll("\x1b[49m");
            const seq = buf.items[seq_start..];
            try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Reset background") });
            current_bg = null;
        }

        // Bold
        if (update.cell.bold != current_bold) {
            const seq_start = buf.items.len;
            if (update.cell.bold) {
                try buf.writer(allocator).writeAll("\x1b[1m");
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Enable bold") });
            } else {
                try buf.writer(allocator).writeAll("\x1b[22m");
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Disable bold") });
            }
            current_bold = update.cell.bold;
        }

        // Italic
        if (update.cell.italic != current_italic) {
            const seq_start = buf.items.len;
            if (update.cell.italic) {
                try buf.writer(allocator).writeAll("\x1b[3m");
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Enable italic") });
            } else {
                try buf.writer(allocator).writeAll("\x1b[23m");
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Disable italic") });
            }
            current_italic = update.cell.italic;
        }

        // Underline
        if (update.cell.underline != current_underline) {
            const seq_start = buf.items.len;
            if (update.cell.underline) {
                try buf.writer(allocator).writeAll("\x1b[4m");
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Enable underline") });
            } else {
                try buf.writer(allocator).writeAll("\x1b[24m");
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Disable underline") });
            }
            current_underline = update.cell.underline;
        }

        // Write the base character
        const render_char = if (update.cell.char == 0) blk: {
            opts.char_zero_to_space += 1;
            break :blk ' ';
        } else update.cell.char;

        var char_buf: [4]u8 = undefined;
        const char_len = std.unicode.utf8Encode(render_char, &char_buf) catch 1;
        const seq_start = buf.items.len;
        try buf.writer(allocator).writeAll(char_buf[0..char_len]);
        const seq = buf.items[seq_start..];

        const desc = try std.fmt.allocPrint(
            allocator,
            "Write char '{u}' (U+{X:0>4}){s}",
            .{ render_char, render_char, if (update.cell.char == 0) " [was char=0]" else "" },
        );
        try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = desc });

        // Write any combining characters
        for (0..update.cell.combining_count) |i| {
            const combining_char = update.cell.combining[i];
            const combining_len = std.unicode.utf8Encode(combining_char, &char_buf) catch 1;
            const combining_start = buf.items.len;
            try buf.writer(allocator).writeAll(char_buf[0..combining_len]);
            const combining_seq = buf.items[combining_start..];

            const combining_desc = try std.fmt.allocPrint(
                allocator,
                "Write combining char (U+{X:0>4})",
                .{combining_char},
            );
            try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, combining_seq), .desc = combining_desc });
        }

        // Track where the terminal cursor is after rendering this character
        const char_display_width: usize = if (update.col + 1 < grid.width and
            grid.current[update.row][update.col + 1].is_continuation)
            2
        else
            1;

        last_pos = .{ .row = update.row, .col = update.col + char_display_width };
        last_had_combining = (update.cell.combining_count > 0);
    }

    // Reset all attributes at end
    const seq_start = buf.items.len;
    try buf.writer(allocator).writeAll("\x1b[0m");
    const seq = buf.items[seq_start..];
    try breakdown.append(allocator,.{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Reset all attributes") });

    return AnsiResult{
        .ansi_bytes = try buf.toOwnedSlice(allocator),
        .breakdown = try breakdown.toOwnedSlice(allocator),
        .optimizations = opts,
    };
}

/// Render updates to terminal (Step 3: optimized output)
/// This implements Helix's optimizations: adjacent cell skipping and attribute tracking
pub fn renderUpdates(self: *Display, updates: []const Update) !void {
    if (updates.len == 0) return;

    // Generate ANSI output (reusing core logic)
    const ansi_result = try generateANSI(self.allocator, updates, &self.grid);
    defer {
        self.allocator.free(ansi_result.ansi_bytes);
        // Free breakdown items
        for (ansi_result.breakdown) |cmd| {
            self.allocator.free(cmd.seq);
            self.allocator.free(cmd.desc);
        }
        self.allocator.free(ansi_result.breakdown);
    }

    // NEOVIM + HELIX PATTERN: Single flush (batched output)
    try self.stdout.writeAll(ansi_result.ansi_bytes);
}

/// Helper: Compare two colors
fn colorEql(a: highlights.Color, b: highlights.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b;
}
