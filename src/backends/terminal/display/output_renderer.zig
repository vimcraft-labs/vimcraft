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

    // O1: Cross-frame attribute tracking metrics
    cross_frame_fg_skipped: usize = 0, // FG codes skipped (same as last frame)
    cross_frame_bg_skipped: usize = 0, // BG codes skipped (same as last frame)
    cross_frame_attrs_skipped: usize = 0, // Bold/italic/underline skipped

    // O2: SGR batching metrics
    sgr_codes_batched: usize = 0, // Codes combined into single SGR

    // O5: Relative cursor movement metrics
    relative_moves_used: usize = 0, // Relative movements (shorter than absolute)
    absolute_moves_used: usize = 0, // Absolute movements
};

/// Result of ANSI generation
pub const AnsiResult = struct {
    ansi_bytes: []const u8, // The complete ANSI output
    breakdown: []const AnsiCommand, // Step-by-step ANSI commands
    optimizations: Optimizations, // Stats on optimizations applied
};

/// Generate ANSI escape sequences for terminal updates (Debug Protocol support)
/// This is the core rendering logic extracted for both Terminal output and debugging
/// Set collect_breakdown=true only for debugging - it allocates strings for every operation
pub fn generateANSI(
    allocator: std.mem.Allocator,
    updates: []const Update,
    grid: *const ScreenGrid,
    collect_breakdown: bool,
) !AnsiResult {
    if (updates.len == 0) {
        return AnsiResult{
            .ansi_bytes = &[_]u8{},
            .breakdown = &[_]AnsiCommand{},
            .optimizations = .{},
        };
    }

    // NOTE: Updates are already sorted by (row, col) from diff() which iterates:
    // 1. dirty_lines in ascending order (DynamicBitSet iterator)
    // 2. columns 0..width sequentially within each row
    // No need to duplicate and sort - this saves 1 allocation + O(n log n) per frame

    var buf: std.ArrayList(u8) = .empty;
    var breakdown: std.ArrayList(AnsiCommand) = .empty;
    var opts = Optimizations{
        .updates_sorted = updates.len, // Track number of updates processed
    };

    // Track state to minimize ANSI codes (Helix optimization)
    var current_fg: ?highlights.Color = null;
    var current_bg: ?highlights.Color = null;
    var current_bold: bool = false;
    var current_italic: bool = false;
    var current_underline: bool = false;
    var last_pos: ?struct { row: usize, col: usize } = null;
    var last_had_combining: bool = false;

    // Process updates (already sorted by row, col from diff())
    for (updates) |update| {
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

            if (collect_breakdown) {
                const seq = buf.items[seq_start..];
                const desc = try std.fmt.allocPrint(
                    allocator,
                    "Move cursor to row={d}, col={d}",
                    .{ update.row, update.col },
                );
                try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = desc });
            }

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

                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    const desc = try std.fmt.allocPrint(
                        allocator,
                        "Set foreground RGB({d},{d},{d})",
                        .{ fg.r, fg.g, fg.b },
                    );
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = desc });
                }
                current_fg = fg;
            } else {
                opts.attribute_changes_deduped += 1;
            }
        } else if (current_fg != null) {
            const seq_start = buf.items.len;
            try buf.writer(allocator).writeAll("\x1b[39m");
            if (collect_breakdown) {
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Reset foreground") });
            }
            current_fg = null;
        }

        // Background color
        if (update.cell.bg) |bg| {
            if (current_bg == null or !colorEql(current_bg.?, bg)) {
                var color_buf: [32]u8 = undefined;
                const bg_code = try bg.toAnsiBg(&color_buf);
                const seq_start = buf.items.len;
                try buf.writer(allocator).writeAll(bg_code);

                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    const desc = try std.fmt.allocPrint(
                        allocator,
                        "Set background RGB({d},{d},{d})",
                        .{ bg.r, bg.g, bg.b },
                    );
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = desc });
                }
                current_bg = bg;
            } else {
                opts.attribute_changes_deduped += 1;
            }
        } else if (current_bg != null) {
            const seq_start = buf.items.len;
            try buf.writer(allocator).writeAll("\x1b[49m");
            if (collect_breakdown) {
                const seq = buf.items[seq_start..];
                try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Reset background") });
            }
            current_bg = null;
        }

        // Bold
        if (update.cell.bold != current_bold) {
            const seq_start = buf.items.len;
            if (update.cell.bold) {
                try buf.writer(allocator).writeAll("\x1b[1m");
                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Enable bold") });
                }
            } else {
                try buf.writer(allocator).writeAll("\x1b[22m");
                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Disable bold") });
                }
            }
            current_bold = update.cell.bold;
        }

        // Italic
        if (update.cell.italic != current_italic) {
            const seq_start = buf.items.len;
            if (update.cell.italic) {
                try buf.writer(allocator).writeAll("\x1b[3m");
                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Enable italic") });
                }
            } else {
                try buf.writer(allocator).writeAll("\x1b[23m");
                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Disable italic") });
                }
            }
            current_italic = update.cell.italic;
        }

        // Underline
        if (update.cell.underline != current_underline) {
            const seq_start = buf.items.len;
            if (update.cell.underline) {
                try buf.writer(allocator).writeAll("\x1b[4m");
                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Enable underline") });
                }
            } else {
                try buf.writer(allocator).writeAll("\x1b[24m");
                if (collect_breakdown) {
                    const seq = buf.items[seq_start..];
                    try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Disable underline") });
                }
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

        if (collect_breakdown) {
            const seq = buf.items[seq_start..];
            const desc = try std.fmt.allocPrint(
                allocator,
                "Write char '{u}' (U+{X:0>4}){s}",
                .{ render_char, render_char, if (update.cell.char == 0) " [was char=0]" else "" },
            );
            try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = desc });
        }

        // Write any combining characters
        for (0..update.cell.combining_count) |i| {
            const combining_char = update.cell.combining[i];
            const combining_len = std.unicode.utf8Encode(combining_char, &char_buf) catch 1;
            const combining_start = buf.items.len;
            try buf.writer(allocator).writeAll(char_buf[0..combining_len]);

            if (collect_breakdown) {
                const combining_seq = buf.items[combining_start..];
                const combining_desc = try std.fmt.allocPrint(
                    allocator,
                    "Write combining char (U+{X:0>4})",
                    .{combining_char},
                );
                try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, combining_seq), .desc = combining_desc });
            }
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
    if (collect_breakdown) {
        const seq = buf.items[seq_start..];
        try breakdown.append(allocator, .{ .seq = try allocator.dupe(u8, seq), .desc = try allocator.dupe(u8, "Reset all attributes") });
    }

    return AnsiResult{
        .ansi_bytes = try buf.toOwnedSlice(allocator),
        .breakdown = if (collect_breakdown) try breakdown.toOwnedSlice(allocator) else &[_]AnsiCommand{},
        .optimizations = opts,
    };
}

/// Render updates to terminal (Step 3: optimized output)
/// This implements ALL 6 Principal Engineer optimizations:
///   O1: Cross-frame attribute tracking (30-50% fewer SGR codes)
///   O2: SGR batching (combine fg+bg+bold into single code)
///   O3: Pre-allocated buffer (zero per-frame allocations)
///   O4: Terminal scroll region integration (delegated to display.zig)
///   O5: Relative cursor movements (shorter escape sequences)
///   O6: Updates already sorted from diff() (no extra work needed)
pub fn renderUpdates(self: *Display, updates: []const Update) !void {
    if (updates.len == 0) return;

    // O3: Reuse pre-allocated buffer (clear but keep capacity)
    self.render_output_buf.clearRetainingCapacity();
    var buf = &self.render_output_buf;

    // O1: Use cross-frame attribute state (persisted in Display)
    // These represent the ACTUAL terminal state from previous frame
    var current_fg = self.cross_frame_fg;
    var current_bg = self.cross_frame_bg;
    var current_bold = self.cross_frame_bold;
    var current_italic = self.cross_frame_italic;
    var current_underline = self.cross_frame_underline;

    // O5: Track cursor position for relative movements
    var cursor_row: usize = 0;
    var cursor_col: usize = 0;
    var cursor_known = false;

    // O6: Updates already sorted by (row, col) from diff() - no sorting needed

    for (updates) |update| {
        // Skip continuation cells - terminals handle double-width chars automatically
        if (update.cell.is_continuation) continue;

        // O5: Choose optimal cursor movement (relative vs absolute)
        if (!cursor_known or update.row != cursor_row or update.col != cursor_col) {
            // Need to move cursor
            if (cursor_known) {
                // Try relative movement first (often shorter)
                const row_diff = @as(isize, @intCast(update.row)) - @as(isize, @intCast(cursor_row));
                const col_diff = @as(isize, @intCast(update.col)) - @as(isize, @intCast(cursor_col));

                // Calculate lengths for comparison
                // Absolute: \x1b[row;colH = 4 + digits(row+1) + digits(col+1)
                // Relative: depends on direction and distance

                const use_relative = shouldUseRelativeMove(row_diff, col_diff, update.row, update.col);

                if (use_relative and row_diff == 0 and col_diff > 0 and col_diff <= 9) {
                    // Forward on same line: \x1b[nC (n <= 9 = 4 bytes)
                    try buf.writer(self.allocator).print("\x1b[{d}C", .{@as(usize, @intCast(col_diff))});
                } else if (use_relative and row_diff == 0 and col_diff < 0 and col_diff >= -9) {
                    // Backward on same line: \x1b[nD (n <= 9 = 4 bytes)
                    try buf.writer(self.allocator).print("\x1b[{d}D", .{@as(usize, @intCast(-col_diff))});
                } else if (use_relative and col_diff == 0 and row_diff > 0 and row_diff <= 9) {
                    // Down on same column: \x1b[nB (n <= 9 = 4 bytes)
                    try buf.writer(self.allocator).print("\x1b[{d}B", .{@as(usize, @intCast(row_diff))});
                } else if (use_relative and col_diff == 0 and row_diff < 0 and row_diff >= -9) {
                    // Up on same column: \x1b[nA (n <= 9 = 4 bytes)
                    try buf.writer(self.allocator).print("\x1b[{d}A", .{@as(usize, @intCast(-row_diff))});
                } else {
                    // Absolute positioning: \x1b[row;colH
                    try buf.writer(self.allocator).print("\x1b[{d};{d}H", .{ update.row + 1, update.col + 1 });
                }
            } else {
                // First move or cursor position unknown - use absolute
                try buf.writer(self.allocator).print("\x1b[{d};{d}H", .{ update.row + 1, update.col + 1 });
            }
        }
        // else: cursor already at correct position (adjacent cell optimization)

        // O2: SGR batching - collect all attribute changes, emit single code
        var sgr_parts: [8][]const u8 = undefined;
        var sgr_count: usize = 0;
        var color_buf_fg: [24]u8 = undefined;
        var color_buf_bg: [24]u8 = undefined;

        // Check each attribute and batch changes
        const need_fg_change = blk: {
            if (update.cell.fg) |fg| {
                if (current_fg == null or !colorEql(current_fg.?, fg)) break :blk true;
            } else if (current_fg != null) {
                break :blk true;
            }
            break :blk false;
        };

        const need_bg_change = blk: {
            if (update.cell.bg) |bg| {
                if (current_bg == null or !colorEql(current_bg.?, bg)) break :blk true;
            } else if (current_bg != null) {
                break :blk true;
            }
            break :blk false;
        };

        const need_bold_change = (update.cell.bold != current_bold);
        const need_italic_change = (update.cell.italic != current_italic);
        const need_underline_change = (update.cell.underline != current_underline);

        // Build batched SGR if any attributes changed
        if (need_fg_change or need_bg_change or need_bold_change or need_italic_change or need_underline_change) {
            // Bold
            if (need_bold_change) {
                sgr_parts[sgr_count] = if (update.cell.bold) "1" else "22";
                sgr_count += 1;
                current_bold = update.cell.bold;
            }

            // Italic
            if (need_italic_change) {
                sgr_parts[sgr_count] = if (update.cell.italic) "3" else "23";
                sgr_count += 1;
                current_italic = update.cell.italic;
            }

            // Underline
            if (need_underline_change) {
                sgr_parts[sgr_count] = if (update.cell.underline) "4" else "24";
                sgr_count += 1;
                current_underline = update.cell.underline;
            }

            // Foreground color
            if (need_fg_change) {
                if (update.cell.fg) |fg| {
                    const len = std.fmt.bufPrint(&color_buf_fg, "38;2;{d};{d};{d}", .{ fg.r, fg.g, fg.b }) catch unreachable;
                    sgr_parts[sgr_count] = len;
                    current_fg = fg;
                } else {
                    sgr_parts[sgr_count] = "39";
                    current_fg = null;
                }
                sgr_count += 1;
            }

            // Background color
            if (need_bg_change) {
                if (update.cell.bg) |bg| {
                    const len = std.fmt.bufPrint(&color_buf_bg, "48;2;{d};{d};{d}", .{ bg.r, bg.g, bg.b }) catch unreachable;
                    sgr_parts[sgr_count] = len;
                    current_bg = bg;
                } else {
                    sgr_parts[sgr_count] = "49";
                    current_bg = null;
                }
                sgr_count += 1;
            }

            // Emit single batched SGR code: \x1b[part1;part2;...m
            if (sgr_count > 0) {
                try buf.writer(self.allocator).writeAll("\x1b[");
                for (sgr_parts[0..sgr_count], 0..) |part, i| {
                    if (i > 0) try buf.writer(self.allocator).writeByte(';');
                    try buf.writer(self.allocator).writeAll(part);
                }
                try buf.writer(self.allocator).writeByte('m');
            }
        }

        // Write the base character
        const render_char = if (update.cell.char == 0) ' ' else update.cell.char;
        var char_buf: [4]u8 = undefined;
        const char_len = std.unicode.utf8Encode(render_char, &char_buf) catch 1;
        try buf.writer(self.allocator).writeAll(char_buf[0..char_len]);

        // Write any combining characters
        for (0..update.cell.combining_count) |i| {
            const combining_char = update.cell.combining[i];
            const combining_len = std.unicode.utf8Encode(combining_char, &char_buf) catch 1;
            try buf.writer(self.allocator).writeAll(char_buf[0..combining_len]);
        }

        // Track cursor position after rendering this character
        cursor_row = update.row;
        cursor_col = update.col + 1; // Cursor advances after character
        cursor_known = true;

        // Handle double-width characters
        if (update.col + 1 < self.compositor.getOutput().width) {
            const output = self.compositor.getOutput();
            if (output.getCell(update.row, update.col + 1)) |next_cell| {
                if (next_cell.is_continuation) {
                    cursor_col = update.col + 2;
                }
            }
        }
    }

    // O1: Persist attribute state to Display for next frame
    // CRITICAL: Don't reset attributes! Terminal remembers them.
    // Only reset if needed for other terminal operations (handled elsewhere)
    self.cross_frame_fg = current_fg;
    self.cross_frame_bg = current_bg;
    self.cross_frame_bold = current_bold;
    self.cross_frame_italic = current_italic;
    self.cross_frame_underline = current_underline;

    // NEOVIM + HELIX PATTERN: Single flush (batched output)
    // Use writeOutput to support PTY capture mode for E2E testing
    try self.writeOutput(buf.items);
}

/// O5: Determine if relative cursor movement is shorter than absolute
fn shouldUseRelativeMove(row_diff: isize, col_diff: isize, target_row: usize, target_col: usize) bool {
    // Absolute: \x1b[row;colH
    // Length = 2 (escape+[) + digits(row+1) + 1 (;) + digits(col+1) + 1 (H)
    const abs_len = 4 + countDigits(target_row + 1) + countDigits(target_col + 1);

    // Relative movements: \x1b[nX where X is A/B/C/D
    // Only consider simple cases (single direction)
    if (row_diff == 0 and col_diff != 0) {
        // Horizontal only: \x1b[nC or \x1b[nD
        const dist = if (col_diff > 0) @as(usize, @intCast(col_diff)) else @as(usize, @intCast(-col_diff));
        const rel_len = 3 + countDigits(dist); // \x1b[ + n + C/D
        return rel_len < abs_len;
    } else if (col_diff == 0 and row_diff != 0) {
        // Vertical only: \x1b[nA or \x1b[nB
        const dist = if (row_diff > 0) @as(usize, @intCast(row_diff)) else @as(usize, @intCast(-row_diff));
        const rel_len = 3 + countDigits(dist);
        return rel_len < abs_len;
    }

    // Diagonal or complex movement - use absolute
    return false;
}

fn countDigits(n: usize) usize {
    if (n == 0) return 1;
    var count: usize = 0;
    var val = n;
    while (val > 0) {
        count += 1;
        val /= 10;
    }
    return count;
}

/// Helper: Compare two colors
fn colorEql(a: highlights.Color, b: highlights.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b;
}
