/// vim.ai.state.* - Editor State Access for AI Features
///
/// Provides zero-copy read-only access to editor state.
/// Returns strings (not ArrayBuffers) for convenience with AI APIs.
///
/// NOTE: This is infrastructure for AI features, not the "Context Flow"
/// primitive from the spec. The spec's vim.ai.native.context.* is reserved
/// for future LLM-native primitives (embedding streams, attention masks, etc.)
///
/// API:
///   vim.ai.state.buffer()      -> string (full buffer content)
///   vim.ai.state.selection()   -> string (selected text, empty if none)
///   vim.ai.state.cursor()      -> { row: number, col: number }
///   vim.ai.state.line()        -> string (current line)
///   vim.ai.state.lines(s, e)   -> string[] (line range)
///   vim.ai.state.filetype()    -> string (detected filetype)
///   vim.ai.state.filename()    -> string (current filename)
///   vim.ai.state.lineCount()   -> number (total lines)
///
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;

const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context for AI state API
pub const AiStateApiContext = struct {
    allocator: std.mem.Allocator,
    editor: ?*Editor,
    editor_ctx: ?*EditorContext,
};

var global_ctx: ?*AiStateApiContext = null;

// ============================================================================
// Helper: Get current buffer
// ============================================================================

fn getCurrentBuffer() ?*Buffer {
    const ctx = global_ctx orelse return null;

    if (ctx.editor) |editor| {
        return editor.getCurrentBuffer();
    } else if (ctx.editor_ctx) |editor_ctx| {
        return editor_ctx.buffer();
    }
    return null;
}

fn getEditor() ?*Editor {
    const ctx = global_ctx orelse return null;
    return ctx.editor;
}

// ============================================================================
// vim.ai.state.buffer() -> string
// Returns full buffer content as a string
// ============================================================================

fn contextBuffer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse return c.hermes_value_create_string(rt, "", 0);

    // Get content as string
    const content = buffer.content.toString() catch return c.hermes_value_create_string(rt, "", 0);
    defer buffer.allocator.free(content);

    return c.hermes_value_create_string(rt, content.ptr, content.len);
}

// ============================================================================
// vim.ai.state.selection() -> string
// Returns selected text (visual mode) or empty string
// ============================================================================

fn contextSelection(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_string(rt, "", 0);
    const buffer = getCurrentBuffer() orelse return c.hermes_value_create_string(rt, "", 0);

    // Check if we're in visual mode with a selection
    if (ctx.editor) |editor| {
        const vs = editor.visual_state;
        if (vs.active) {
            const Position = @import("../../editor/visual/visual.zig").Position;
            const cursor_pos = Position{ .line = buffer.cursor.row, .col = buffer.cursor.col };
            const range = vs.getRange(cursor_pos);

            // Extract selected text
            var lines: std.ArrayList(u8) = .empty;
            defer lines.deinit(buffer.allocator);

            var row = range.start.line;
            while (row <= range.end.line) : (row += 1) {
                if (buffer.getLine(row)) |line_slice| {
                    defer buffer.allocator.free(line_slice);
                    const line_start = if (row == range.start.line) @min(range.start.col, line_slice.len) else 0;
                    const line_end = if (row == range.end.line) @min(range.end.col + 1, line_slice.len) else line_slice.len;

                    if (line_start < line_end) {
                        lines.appendSlice(buffer.allocator, line_slice[line_start..line_end]) catch {};
                    }
                    if (row < range.end.line) {
                        lines.append(buffer.allocator, '\n') catch {};
                    }
                }
            }

            const result = lines.toOwnedSlice(buffer.allocator) catch return c.hermes_value_create_string(rt, "", 0);
            defer buffer.allocator.free(result);
            return c.hermes_value_create_string(rt, result.ptr, result.len);
        }
    }

    // No selection
    return c.hermes_value_create_string(rt, "", 0);
}

// ============================================================================
// vim.ai.state.cursor() -> { row: number, col: number }
// ============================================================================

fn contextCursor(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse {
        // Return { row: 0, col: 0 } as fallback
        const obj = c.hermes_value_create_object(rt);
        c.hermes_value_set_property(rt, obj, "row", c.hermes_value_create_number(rt, 0));
        c.hermes_value_set_property(rt, obj, "col", c.hermes_value_create_number(rt, 0));
        return obj;
    };

    const obj = c.hermes_value_create_object(rt);
    c.hermes_value_set_property(rt, obj, "row", c.hermes_value_create_number(rt, @floatFromInt(buffer.cursor.row)));
    c.hermes_value_set_property(rt, obj, "col", c.hermes_value_create_number(rt, @floatFromInt(buffer.cursor.col)));
    return obj;
}

// ============================================================================
// vim.ai.state.line() -> string (current line)
// ============================================================================

fn contextLine(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse return c.hermes_value_create_string(rt, "", 0);

    if (buffer.getLine(buffer.cursor.row)) |line| {
        // getLine returns cached/borrowed memory - do NOT free
        return c.hermes_value_create_string(rt, line.ptr, line.len);
    }

    return c.hermes_value_create_string(rt, "", 0);
}

// ============================================================================
// vim.ai.state.lines(start, end) -> string[] (line range, 0-indexed)
// ============================================================================

fn contextLines(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse return c.hermes_array_create(rt, 0);

    // Parse arguments
    var start: usize = 0;
    var end: usize = buffer.lineCount();

    if (count >= 1) {
        const start_val = args[0] orelse return c.hermes_array_create(rt, 0);
        start = @intFromFloat(c.hermes_value_get_number(start_val));
    }
    if (count >= 2) {
        const end_val = args[1] orelse return c.hermes_array_create(rt, 0);
        end = @intFromFloat(c.hermes_value_get_number(end_val));
    }

    // Clamp to valid range
    start = @min(start, buffer.lineCount());
    end = @min(end, buffer.lineCount());
    if (start > end) {
        const tmp = start;
        start = end;
        end = tmp;
    }

    const line_count = end - start;
    const arr = c.hermes_array_create(rt, line_count);

    var i: usize = 0;
    var row = start;
    while (row < end) : (row += 1) {
        if (buffer.getLine(row)) |line| {
            // getLine returns cached/borrowed memory - do NOT free
            const str = c.hermes_value_create_string(rt, line.ptr, line.len);
            c.hermes_array_set(rt, arr, i, str);
        } else {
            c.hermes_array_set(rt, arr, i, c.hermes_value_create_string(rt, "", 0));
        }
        i += 1;
    }

    return arr;
}

// ============================================================================
// vim.ai.state.filetype() -> string
// ============================================================================

fn contextFiletype(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse return c.hermes_value_create_string(rt, "", 0);

    if (buffer.filetype) |ft| {
        return c.hermes_value_create_string(rt, ft.ptr, ft.len);
    }

    return c.hermes_value_create_string(rt, "", 0);
}

// ============================================================================
// vim.ai.state.filename() -> string
// ============================================================================

fn contextFilename(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse return c.hermes_value_create_string(rt, "", 0);

    if (buffer.filepath) |path| {
        return c.hermes_value_create_string(rt, path.ptr, path.len);
    }

    return c.hermes_value_create_string(rt, "", 0);
}

// ============================================================================
// vim.ai.state.lineCount() -> number
// ============================================================================

fn contextLineCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer = getCurrentBuffer() orelse return c.hermes_value_create_number(rt, 0);

    return c.hermes_value_create_number(rt, @floatFromInt(buffer.lineCount()));
}

// ============================================================================
// HostObject Getter - vim.ai.state.*
// ============================================================================

pub export fn aiStateHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const name = std.mem.span(prop_name);

    const PropertyMap = std.StaticStringMap(*const fn (?*c.OVHermesRuntime, ?*anyopaque, [*c]?*c.OVHermesValue, usize) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "buffer", contextBuffer },
        .{ "selection", contextSelection },
        .{ "cursor", contextCursor },
        .{ "line", contextLine },
        .{ "lines", contextLines },
        .{ "filetype", contextFiletype },
        .{ "filename", contextFilename },
        .{ "lineCount", contextLineCount },
    });

    const func = PropertyMap.get(name) orelse return null;
    return c.hermes_create_function(runtime, prop_name, func, context);
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, ctx: *AiStateApiContext) void {
    global_ctx = ctx;

    // Register as vim.ai.state (nested under vim.ai namespace)
    // This will be wired up in runtime.ts
    c.hermes_register_host_object(
        runtime,
        "__aiState",
        aiStateHostObjectGet,
        null, // No setter
        null, // No enumerator
        @ptrCast(ctx),
    );
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}
