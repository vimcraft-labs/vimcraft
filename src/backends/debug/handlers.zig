/// Shared command handlers for debug protocol
/// Used by both Terminal mode (debug_socket.zig) and Headless mode (server.zig)
/// to avoid code duplication while maintaining separate server implementations.

const std = @import("std");
const protocol = @import("protocol.zig");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const ModeManager = @import("../../editor/mode/mode.zig").ModeManager;
const VisualState = @import("../../backends/terminal/visual/visual.zig").VisualState;
const Display = @import("../../backends/terminal/display/display.zig").Display;

/// Context for shared handlers - abstracts away Editor vs EditorContext differences
pub const HandlerContext = struct {
    allocator: std.mem.Allocator,
    buffer: *Buffer,
    mode_manager: *ModeManager,
    visual_state: *VisualState,
    display: *Display,
};

/// Get full editor state snapshot
pub fn handleGetState(ctx: HandlerContext) !protocol.ResponseResult {
    const mode_str = try ctx.allocator.dupe(u8, ctx.mode_manager.getModeString());

    // Get buffer lines
    var buffer_lines = std.ArrayList([]const u8).empty;
    defer buffer_lines.deinit(ctx.allocator);

    for (0..ctx.buffer.lineCount()) |i| {
        if (ctx.buffer.getLine(i)) |line| {
            const owned = try ctx.allocator.dupe(u8, line);
            try buffer_lines.append(ctx.allocator, owned);
        }
    }

    // Get viewport state from display
    const viewport = protocol.ViewportState{
        .top = ctx.display.viewport_top,
        .left = ctx.display.viewport_left,
        .height = if (ctx.display.terminal_rows > 1)
            ctx.display.terminal_rows - 1
        else
            1,
        .width = ctx.display.terminal_cols,
    };

    // Get visual state (if active)
    var visual: ?protocol.VisualState = null;
    if (ctx.visual_state.active) {
        const cursor = ctx.buffer.cursor;
        const range = ctx.visual_state.getRange(.{ .line = cursor.row, .col = cursor.col });

        var text_lines = std.ArrayList([]const u8).empty;
        defer text_lines.deinit(ctx.allocator);

        for (range.start.line..range.end.line + 1) |line_idx| {
            const line = ctx.buffer.getLine(line_idx) orelse continue;
            const owned = try ctx.allocator.dupe(u8, line);
            try text_lines.append(ctx.allocator, owned);
        }

        const mode_str_vis = switch (ctx.visual_state.mode) {
            .char => "char",
            .line => "line",
            .block => "block",
        };

        visual = protocol.VisualState{
            .active = true,
            .mode = try ctx.allocator.dupe(u8, mode_str_vis),
            .anchor = .{ .line = ctx.visual_state.anchor.line, .col = ctx.visual_state.anchor.col },
            .head = .{ .line = cursor.row, .col = cursor.col },
            .text = try text_lines.toOwnedSlice(ctx.allocator),
        };
    }

    return .{ .state = protocol.EditorState{
        .mode = mode_str,
        .cursor = .{
            .line = ctx.buffer.cursor.row,
            .col = ctx.buffer.cursor.col,
        },
        .buffer = protocol.BufferState{
            .path = if (ctx.buffer.filepath) |p| try ctx.allocator.dupe(u8, p) else null,
            .lines = try buffer_lines.toOwnedSlice(ctx.allocator),
            .modified = false, // TODO: track modifications
            .line_count = ctx.buffer.lineCount(),
        },
        .visual = visual,
        .registers = protocol.RegistersState{
            .registers = &[_]protocol.RegisterState{},
            .count = 0,
        },
        .viewport = viewport,
    } };
}

/// Get cursor position
pub fn handleGetCursor(ctx: HandlerContext) !protocol.ResponseResult {
    return .{ .cursor = .{
        .line = ctx.buffer.cursor.row,
        .col = ctx.buffer.cursor.col,
    } };
}

/// Get current mode
pub fn handleGetMode(ctx: HandlerContext) !protocol.ResponseResult {
    const mode_str = try ctx.allocator.dupe(u8, ctx.mode_manager.getModeString());
    return .{ .mode = .{ .mode = mode_str } };
}

/// Get gutter state (line numbers, sign column, etc.)
pub fn handleGetGutterState(ctx: HandlerContext) !protocol.ResponseResult {
    const gutter_mgr = &ctx.display.gutter_manager;
    const gutter_width = gutter_mgr.getTotalWidth();

    // Collect gutter columns
    var columns = std.ArrayList(protocol.GutterColumn).empty;
    defer columns.deinit(ctx.allocator);

    for (gutter_mgr.columns.items) |col| {
        try columns.append(ctx.allocator, protocol.GutterColumn{
            .name = try ctx.allocator.dupe(u8, col.name),
            .enabled = col.enabled,
            .cached_width = col.cached_width,
            .cache_key = col.cache_key,
        });
    }

    // Get line number mode
    const line_mode = ctx.display.line_number_config.getMode();
    const line_mode_str = @tagName(line_mode);

    // Get sign column mode
    const sign_mode_str = @tagName(ctx.display.sign_column_config.mode);

    return .{ .gutter_state = .{
        .gutter_width = gutter_width,
        .cached_line_count = ctx.display.cached_line_count,
        .columns = try columns.toOwnedSlice(ctx.allocator),
        .line_number_config = .{
            .mode = try ctx.allocator.dupe(u8, line_mode_str),
            .number = ctx.display.line_number_config.number,
            .relative_number = ctx.display.line_number_config.relative_number,
        },
        .sign_column_config = .{
            .mode = try ctx.allocator.dupe(u8, sign_mode_str),
        },
    } };
}

/// Get terminal updates (ANSI rendering output for debugging)
pub fn handleGetTerminalUpdates(ctx: HandlerContext) !protocol.ResponseResult {
    const output_renderer = @import("../terminal/display/output_renderer.zig");
    const compositor = &ctx.display.compositor;
    const output = compositor.getOutput();

    // Get raw updates from diff (snapshot semantics)
    const updates = try output.diff(ctx.allocator);
    defer ctx.allocator.free(updates);

    // Clone raw updates for response
    var raw_updates: std.ArrayList(protocol.RawUpdate) = .empty;
    for (updates) |update| {
        try raw_updates.append(ctx.allocator, protocol.RawUpdate{
            .row = update.row,
            .col = update.col,
            .char = update.cell.char,
            .fg = if (update.cell.fg) |fg| protocol.Color{
                .r = fg.r,
                .g = fg.g,
                .b = fg.b,
            } else null,
            .bg = if (update.cell.bg) |bg| protocol.Color{
                .r = bg.r,
                .g = bg.g,
                .b = bg.b,
            } else null,
            .bold = update.cell.bold,
            .italic = update.cell.italic,
            .underline = update.cell.underline,
        });
    }

    // Generate ANSI output with breakdown
    const ansi_result = try output_renderer.generateANSI(
        ctx.allocator,
        updates,
        output,
    );
    defer {
        ctx.allocator.free(ansi_result.ansi_bytes);
        for (ansi_result.breakdown) |ansi_cmd| {
            ctx.allocator.free(ansi_cmd.seq);
            ctx.allocator.free(ansi_cmd.desc);
        }
        ctx.allocator.free(ansi_result.breakdown);
    }

    // Clone breakdown for response
    var breakdown: std.ArrayList(protocol.AnsiCommand) = .empty;
    for (ansi_result.breakdown) |ansi_cmd| {
        try breakdown.append(ctx.allocator, protocol.AnsiCommand{
            .seq = try ctx.allocator.dupe(u8, ansi_cmd.seq),
            .desc = try ctx.allocator.dupe(u8, ansi_cmd.desc),
        });
    }

    return .{ .terminal_updates = .{
        .raw_updates = try raw_updates.toOwnedSlice(ctx.allocator),
        .update_count = updates.len,
        .ansi_bytes = try ctx.allocator.dupe(u8, ansi_result.ansi_bytes),
        .ansi_breakdown = try breakdown.toOwnedSlice(ctx.allocator),
        .optimizations = .{
            .adjacent_cells_skipped = ansi_result.optimizations.adjacent_cells_skipped,
            .attribute_changes_deduped = ansi_result.optimizations.attribute_changes_deduped,
            .char_zero_to_space = ansi_result.optimizations.char_zero_to_space,
        },
    } };
}
