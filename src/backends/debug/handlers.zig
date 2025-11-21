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
            defer ctx.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
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
            defer ctx.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
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

    // Generate ANSI output with breakdown (debug protocol needs breakdown for inspection)
    const ansi_result = try output_renderer.generateANSI(
        ctx.allocator,
        updates,
        output,
        true, // collect_breakdown=true for debug protocol
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

/// Extended context for handlers that need Editor access
/// This is needed for execute_keys_with_render_trace which needs to call Editor.executeKeys()
pub const ExtendedHandlerContext = struct {
    base: HandlerContext,
    editor_context: *@import("editor_context.zig").EditorContext, // For executeKeys access
};

/// Get vim option values (all or specific options)
pub fn handleGetOptions(
    ctx: ExtendedHandlerContext,
    option_names: ?[]const []const u8,
) !protocol.ResponseResult {
    const allocator = ctx.base.allocator;
    const editor = ctx.editor_context;

    if (editor.options_manager) |opts_mgr| {
        var entries = std.ArrayList(protocol.OptionEntry).empty;
        defer entries.deinit(allocator);

        if (option_names) |names| {
            // Get specific options
            for (names) |name| {
                // Try to get the option value
                if (opts_mgr.getBoolean(name)) |bool_val| {
                    try entries.append(allocator, protocol.OptionEntry{
                        .name = try allocator.dupe(u8, name),
                        .value = .{ .boolean = bool_val },
                        .scope = try allocator.dupe(u8, "auto"),
                    });
                } else if (opts_mgr.getNumber(name)) |num_val| {
                    try entries.append(allocator, protocol.OptionEntry{
                        .name = try allocator.dupe(u8, name),
                        .value = .{ .number = num_val },
                        .scope = try allocator.dupe(u8, "auto"),
                    });
                } else if (opts_mgr.getString(name)) |str_val| {
                    try entries.append(allocator, protocol.OptionEntry{
                        .name = try allocator.dupe(u8, name),
                        .value = .{ .string = try allocator.dupe(u8, str_val) },
                        .scope = try allocator.dupe(u8, "auto"),
                    });
                }
            }
        } else {
            // Get all options - we need to query the option names from the manager
            // For now, return a subset of commonly used options
            const common_options = [_][]const u8{
                "number",
                "relativeNumber",
                "cursorLine",
                "cursorColumn",
                "tabstop",
                "shiftwidth",
                "expandtab",
                "wrap",
                "list",
                "listchars",
            };

            for (common_options) |name| {
                if (opts_mgr.getBoolean(name)) |bool_val| {
                    try entries.append(allocator, protocol.OptionEntry{
                        .name = try allocator.dupe(u8, name),
                        .value = .{ .boolean = bool_val },
                        .scope = try allocator.dupe(u8, "auto"),
                    });
                } else if (opts_mgr.getNumber(name)) |num_val| {
                    try entries.append(allocator, protocol.OptionEntry{
                        .name = try allocator.dupe(u8, name),
                        .value = .{ .number = num_val },
                        .scope = try allocator.dupe(u8, "auto"),
                    });
                } else if (opts_mgr.getString(name)) |str_val| {
                    try entries.append(allocator, protocol.OptionEntry{
                        .name = try allocator.dupe(u8, name),
                        .value = .{ .string = try allocator.dupe(u8, str_val) },
                        .scope = try allocator.dupe(u8, "auto"),
                    });
                }
            }
        }

        return .{ .options = protocol.OptionsState{
            .options = try entries.toOwnedSlice(allocator),
            .count = entries.items.len,
        } };
    } else {
        // No options manager, return empty
        return .{ .options = protocol.OptionsState{
            .options = &[_]protocol.OptionEntry{},
            .count = 0,
        } };
    }
}

/// Get module cache (for hot reload verification)
pub fn handleGetModuleCache(ctx: ExtendedHandlerContext) !protocol.ResponseResult {
    const allocator = ctx.base.allocator;
    const jsi_api = @import("../../system/jsi/jsi_api.zig");

    // Get module cache from JSI API
    if (jsi_api.global_config_ctx) |ctx_ptr| {
        var module_paths = std.ArrayList([]const u8).empty;
        defer module_paths.deinit(allocator);

        // Iterate through module cache
        var iter = ctx_ptr.module_cache.iterator();
        while (iter.next()) |entry| {
            // entry.key_ptr.* is the absolute path ([]const u8)
            const path_copy = try allocator.dupe(u8, entry.key_ptr.*);
            try module_paths.append(allocator, path_copy);
        }

        return .{ .module_cache = protocol.ModuleCacheState{
            .modules = try module_paths.toOwnedSlice(allocator),
            .count = module_paths.items.len,
        } };
    } else {
        // No JSI context, return empty
        return .{ .module_cache = protocol.ModuleCacheState{
            .modules = &[_][]const u8{},
            .count = 0,
        } };
    }
}

/// Execute keys and capture render pipeline state DURING render (before swapBuffers)
/// This is THE KEY to debugging terminal rendering bugs without a TTY
///
/// The problem with get_terminal_updates:
/// - execute_keys → renderHeadless → swapBuffers (clears dirty flags)
/// - get_terminal_updates → diff() returns [] (no dirty rows!)
///
/// This handler solves it by:
/// - execute_keys (buffer state changes)
/// - Manually run render steps WITHOUT swapBuffers
/// - Capture diff() output BEFORE swapBuffers clears dirty flags
/// - Return RenderTrace with all pipeline state
pub fn handleExecuteKeysWithRenderTrace(
    ext_ctx: ExtendedHandlerContext,
    keys: []const u8,
) !protocol.ResponseResult {
    const ctx = ext_ctx.base;
    const editor = ext_ctx.editor_context;

    // STEP 1: Execute keys to update buffer state
    try editor.executeKeys(keys);

    // STEP 2: Manually run render pipeline (same as renderHeadless but with capture)
    const layer_renderer = @import("../terminal/display/layer_renderer.zig");
    const ListChars = @import("../../editor/config/listchars.zig").ListChars;

    // Get list/listchars options
    const list_enabled = if (editor.options_manager) |opts|
        opts.getBoolean("list") orelse false
    else
        false;

    const listchars = if (editor.options_manager) |opts| blk: {
        const lcs_str = opts.getString("listchars") orelse "tab:> ,trail:-,nbsp:+";
        break :blk try ListChars.parse(ctx.allocator, lcs_str);
    } else
        ListChars{};

    // Get cursorline option (for current line highlighting)
    const cursorline_enabled = if (editor.options_manager) |opts|
        opts.getBoolean("cursorLine") orelse false
    else
        false;

    // Update layers from buffer state
    try layer_renderer.updateLayers(
        ctx.display,
        editor,
        editor.mode_manager.getModeString(),
        &editor.highlight_registry,
        &editor.visual_state,
        &editor.yank_highlight,
        cursorline_enabled,
        list_enabled,
        &listchars,
    );

    // Apply virtual text overlay
    ctx.display.virtual_text.applyToGrid(&ctx.display.virtual_text_layer.grid);

    // Composite all layers
    try ctx.display.compositor.composite(ctx.display.layer_manager.layers.items);

    // STEP 3: CRITICAL - Capture dirty rows BEFORE calling diff()
    // (diff() doesn't modify dirty flags, but we need them for analysis)
    const output = ctx.display.compositor.getOutput();
    var dirty_rows = std.ArrayList(usize).empty;
    defer dirty_rows.deinit(ctx.allocator);

    var iter = output.dirty_lines.iterator(.{});
    while (iter.next()) |row| {
        try dirty_rows.append(ctx.allocator, row);
    }

    // STEP 4: Call diff() to generate terminal updates
    // This is the data we COULDN'T get before (because swapBuffers cleared dirty flags)
    const updates = try output.diff(ctx.allocator);
    defer ctx.allocator.free(updates);

    // Clone raw updates for response
    var raw_updates = std.ArrayList(protocol.RawUpdate).empty;
    defer raw_updates.deinit(ctx.allocator);

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

    // STEP 5: Capture compositor output grid state (for comparison/debugging)
    var compositor_cells = std.ArrayList(protocol.OutputCell).empty;
    defer compositor_cells.deinit(ctx.allocator);

    for (0..output.height) |row| {
        for (0..output.width) |col| {
            const cell = output.getCell(row, col) orelse continue;

            // Only include non-empty cells to reduce JSON size
            if (cell.char == 0 and cell.fg == null and cell.bg == null) continue;

            try compositor_cells.append(ctx.allocator, protocol.OutputCell{
                .row = row,
                .col = col,
                .char = cell.char,
                .fg = if (cell.fg) |fg| protocol.Color{
                    .r = fg.r,
                    .g = fg.g,
                    .b = fg.b,
                } else null,
                .bg = if (cell.bg) |bg| protocol.Color{
                    .r = bg.r,
                    .g = bg.g,
                    .b = bg.b,
                } else null,
            });
        }
    }

    // STEP 6: Capture buffer state (for verification)
    var buffer_lines = std.ArrayList([]const u8).empty;
    defer buffer_lines.deinit(ctx.allocator);

    for (0..editor.buffer.lineCount()) |i| {
        if (editor.buffer.getLine(i)) |line| {
            defer ctx.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
            const owned = try ctx.allocator.dupe(u8, line);
            try buffer_lines.append(ctx.allocator, owned);
        }
    }

    const mode_str = try ctx.allocator.dupe(u8, editor.mode_manager.getModeString());

    // STEP 7: NOW call swapBuffers to maintain state consistency
    // This ensures next render sees correct previous state
    output.swapBuffers();

    // STEP 8: Return RenderTrace with all captured data
    return .{ .render_trace = protocol.RenderTrace{
        .terminal_updates = try raw_updates.toOwnedSlice(ctx.allocator),
        .update_count = updates.len,
        .dirty_rows = try dirty_rows.toOwnedSlice(ctx.allocator),
        .compositor_cells = try compositor_cells.toOwnedSlice(ctx.allocator),
        .buffer_lines = try buffer_lines.toOwnedSlice(ctx.allocator),
        .cursor = .{
            .line = editor.buffer.cursor.row,
            .col = editor.buffer.cursor.col,
        },
        .mode = mode_str,
    } };
}
