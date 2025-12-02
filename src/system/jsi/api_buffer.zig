/// vim.api Buffer Functions (Full Multi-Buffer Support)
/// Implements Neovim-compatible buffer API:
/// - getCurrentBuf() -> Buffer (handle)
/// - setCurrentBuf(buf) -> void
/// - listBufs() -> Buffer[] (all valid handles)
/// - bufLineCount(buf) -> number
/// - bufGetLines(buf, start, end, strict) -> string[]
/// - bufSetLines(buf, start, end, strict, lines) -> void
/// - bufGetName(buf) -> string
/// - bufSetName(buf, name) -> void
/// - bufIsValid(buf) -> boolean
/// - bufDelete(buf, opts) -> void
///
/// Buffer Handle Convention (Neovim compatible):
/// - Handle 0 = current buffer (special case)
/// - Handle N (N > 0) = BufferId { .id = N }
///
/// These are registered as global functions for vim.api.* wrappers in runtime.js
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;
const editor_module = @import("../../editor/editor.zig");
const BufferId = editor_module.BufferId;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context for buffer API functions
/// Now stores Editor pointer directly for multi-buffer access
pub const ApiBufferContext = struct {
    allocator: std.mem.Allocator,
    /// Editor pointer (for multi-buffer operations)
    /// null for EditorContext (headless mode - single buffer only)
    editor: ?*Editor,
    /// EditorContext pointer (for headless mode)
    editor_ctx: ?*EditorContext,
};

/// Global context (set during registration)
var global_ctx: ?*ApiBufferContext = null;

// ============================================================================
// Helper: Get buffer by handle (0 = current, N = BufferId{.id=N})
// ============================================================================

fn getBufferByHandle(handle: i64) ?*Buffer {
    const ctx = global_ctx orelse return null;

    if (ctx.editor) |editor| {
        // Editor mode: full multi-buffer support
        if (handle == 0) {
            // Handle 0 = current buffer
            return editor.getCurrentBuffer();
        } else if (handle > 0) {
            // Handle N = BufferId{.id=N}
            // HashMap stores *Buffer, so get returns *Buffer directly
            const buf_id = BufferId{ .id = @intCast(handle) };
            return editor.buffers.get(buf_id);
        }
        return null;
    } else if (ctx.editor_ctx) |editor_ctx| {
        // EditorContext mode: single buffer only (handle 0)
        if (handle == 0) {
            return editor_ctx.buffer();
        }
        return null;
    }
    return null;
}

fn isBufferValid(handle: i64) bool {
    const ctx = global_ctx orelse return false;

    if (ctx.editor) |editor| {
        if (handle == 0) {
            return editor.current_buffer_id != null;
        } else if (handle > 0) {
            const buf_id = BufferId{ .id = @intCast(handle) };
            return editor.buffers.contains(buf_id);
        }
        return false;
    } else if (ctx.editor_ctx) |_| {
        // EditorContext: only buffer 0 is valid
        return handle == 0;
    }
    return false;
}

// ============================================================================
// vim.api.getCurrentBuf() -> Buffer
// ============================================================================

pub export fn apiGetCurrentBuf(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, 0);

    if (ctx.editor) |editor| {
        // Return actual current buffer ID
        if (editor.current_buffer_id) |buf_id| {
            return c.hermes_value_create_number(rt, @floatFromInt(buf_id.id));
        }
    }
    // EditorContext or no current buffer: return 0
    return c.hermes_value_create_number(rt, 0);
}

// ============================================================================
// vim.api.setCurrentBuf(buf) -> void
// ============================================================================

pub export fn apiSetCurrentBuf(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 1) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    if (ctx.editor) |editor| {
        if (buf_handle == 0) {
            // Already current buffer, nothing to do
            return c.hermes_value_create_undefined(rt);
        } else if (buf_handle > 0) {
            const buf_id = BufferId{ .id = @intCast(buf_handle) };
            editor.switchBuffer(buf_id) catch {
                // Buffer not found - silently fail (Neovim behavior)
                return c.hermes_value_create_undefined(rt);
            };
        }
    }
    // EditorContext: single buffer, ignore

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.api.listBufs() -> Buffer[]
// ============================================================================

pub export fn apiListBufs(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_array_create(rt, 0);

    if (ctx.editor) |editor| {
        // Count buffers
        const buf_count = editor.buffers.count();
        const arr = c.hermes_array_create(rt, buf_count) orelse return c.hermes_array_create(rt, 0);

        // Fill array with buffer IDs
        var i: usize = 0;
        var iter = editor.buffers.keyIterator();
        while (iter.next()) |key| {
            const num = c.hermes_value_create_number(rt, @floatFromInt(key.id));
            if (num) |n| {
                c.hermes_array_set(rt, arr, i, n);
                c.hermes_value_destroy(n);
                i += 1;
            }
        }
        return arr;
    } else {
        // EditorContext: single buffer (ID 0)
        const arr = c.hermes_array_create(rt, 1) orelse return c.hermes_array_create(rt, 0);
        const zero = c.hermes_value_create_number(rt, 0);
        if (zero) |z| {
            c.hermes_array_set(rt, arr, 0, z);
            c.hermes_value_destroy(z);
        }
        return arr;
    }
}

// ============================================================================
// vim.api.bufLineCount(buf) -> number
// ============================================================================

pub export fn apiBufLineCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 1) return c.hermes_value_create_null(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_null(rt);
    return c.hermes_value_create_number(rt, @floatFromInt(buffer.lineCount()));
}

// ============================================================================
// vim.api.bufGetLines(buf, start, end, strict) -> string[]
// ============================================================================

pub export fn apiBufGetLines(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    if (count < 4) return c.hermes_value_create_null(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const start_val = args[1] orelse return c.hermes_value_create_null(rt);
    const end_val = args[2] orelse return c.hermes_value_create_null(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const start_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(start_val)));
    const end_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(end_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_null(rt);
    const line_count = buffer.lineCount();

    // Handle negative indices (Neovim: -1 = end of buffer)
    const start: usize = if (start_raw < 0) 0 else @intCast(@min(start_raw, @as(i64, @intCast(line_count))));
    const end: usize = if (end_raw < 0) line_count else @intCast(@min(end_raw, @as(i64, @intCast(line_count))));

    // Create result array
    const result_len = if (end > start) end - start else 0;
    const arr = c.hermes_array_create(rt, result_len) orelse return c.hermes_value_create_null(rt);

    // Fill array with lines
    var i: usize = 0;
    var line_num = start;
    while (line_num < end) : (line_num += 1) {
        const line = buffer.getLine(line_num) orelse {
            const empty_str = c.hermes_value_create_string(rt, "", 0) orelse continue;
            c.hermes_array_set(rt, arr, i, empty_str);
            c.hermes_value_destroy(empty_str);
            i += 1;
            continue;
        };
        defer ctx.allocator.free(line);

        // Remove trailing newline if present
        const clean_line = if (line.len > 0 and line[line.len - 1] == '\n')
            line[0 .. line.len - 1]
        else
            line;

        const str = c.hermes_value_create_string(rt, clean_line.ptr, clean_line.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
        i += 1;
    }

    return arr;
}

// ============================================================================
// vim.api.bufSetLines(buf, start, end, strict, lines) -> void
// ============================================================================

pub export fn apiBufSetLines(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    if (count < 5) return c.hermes_value_create_null(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const start_val = args[1] orelse return c.hermes_value_create_null(rt);
    const end_val = args[2] orelse return c.hermes_value_create_null(rt);
    const lines_val = args[4] orelse return c.hermes_value_create_null(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const start_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(start_val)));
    const end_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(end_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_null(rt);
    const line_count = buffer.lineCount();

    // Handle negative indices
    const start: usize = if (start_raw < 0) line_count else @intCast(@min(start_raw, @as(i64, @intCast(line_count))));
    const end: usize = if (end_raw < 0) line_count else @intCast(@min(end_raw, @as(i64, @intCast(line_count))));

    const lines_len = c.hermes_array_length(rt, lines_val);

    // Build new content string
    var new_content: std.ArrayList(u8) = .empty;
    defer new_content.deinit(ctx.allocator);

    // Add lines before start
    var line_num: usize = 0;
    while (line_num < start) : (line_num += 1) {
        const line = buffer.getLine(line_num) orelse continue;
        defer ctx.allocator.free(line);
        new_content.appendSlice(ctx.allocator, line) catch continue;
        if (line.len == 0 or line[line.len - 1] != '\n') {
            new_content.append(ctx.allocator, '\n') catch continue;
        }
    }

    // Add replacement lines
    var i: usize = 0;
    while (i < lines_len) : (i += 1) {
        const line_str_val = c.hermes_array_get(rt, lines_val, i) orelse continue;
        defer c.hermes_value_destroy(line_str_val);

        var line_len: usize = 0;
        const line_ptr = c.hermes_value_get_string(rt, line_str_val, &line_len);

        if (line_ptr) |ptr| {
            new_content.appendSlice(ctx.allocator, ptr[0..line_len]) catch continue;
            new_content.append(ctx.allocator, '\n') catch continue;
        }
    }

    // Add lines after end
    line_num = end;
    while (line_num < line_count) : (line_num += 1) {
        const line = buffer.getLine(line_num) orelse continue;
        defer ctx.allocator.free(line);
        new_content.appendSlice(ctx.allocator, line) catch continue;
    }

    // Replace buffer content using Rope
    const Rope = @import("../../editor/buffer/rope.zig").Rope;
    buffer.content.deinit();
    buffer.content = Rope.fromString(ctx.allocator, new_content.items) catch {
        buffer.content = Rope.init(ctx.allocator);
        return c.hermes_value_create_null(rt);
    };
    buffer.version += 1;

    // CRITICAL: Set js_state_dirty to trigger re-render
    // Without this, UI won't update after bufSetLines is called
    if (ctx.editor) |editor| {
        editor.js_state_dirty = true;
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.api.bufGetName(buf) -> string
// ============================================================================

pub export fn apiBufGetName(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 1) return c.hermes_value_create_string(rt, "", 0);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_string(rt, "", 0);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_string(rt, "", 0);
    const filename = buffer.filepath orelse "";
    return c.hermes_value_create_string(rt, filename.ptr, filename.len);
}

// ============================================================================
// vim.api.bufSetName(buf, name) -> void
// ============================================================================

pub export fn apiBufSetName(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 2) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_undefined(rt);

    // Free old filepath if any
    if (buffer.filepath) |old_path| {
        ctx.allocator.free(old_path);
    }

    // Set new filepath
    if (name_ptr) |ptr| {
        if (name_len > 0) {
            buffer.filepath = ctx.allocator.dupe(u8, ptr[0..name_len]) catch null;
        } else {
            buffer.filepath = null;
        }
    } else {
        buffer.filepath = null;
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.api.bufIsValid(buf) -> boolean
// ============================================================================

pub export fn apiBufIsValid(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 1) return c.hermes_value_create_boolean(rt, false);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_boolean(rt, false);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    return c.hermes_value_create_boolean(rt, isBufferValid(buf_handle));
}

// ============================================================================
// vim.api.bufDelete(buf, opts) -> void
// ============================================================================

pub export fn apiBufDelete(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 1) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // Parse opts (optional second argument)
    var force = false;
    if (count >= 2) {
        if (args[1]) |opts_val| {
            // Check for opts.force property
            const force_val = c.hermes_value_get_property(rt, opts_val, "force");
            if (force_val) |fv| {
                defer c.hermes_value_destroy(fv);
                if (c.hermes_value_is_boolean(fv)) {
                    force = c.hermes_value_get_boolean(fv);
                }
            }
        }
    }

    if (ctx.editor) |editor| {
        var buf_id: BufferId = undefined;

        if (buf_handle == 0) {
            // Delete current buffer
            buf_id = editor.current_buffer_id orelse return c.hermes_value_create_undefined(rt);
        } else if (buf_handle > 0) {
            buf_id = BufferId{ .id = @intCast(buf_handle) };
        } else {
            return c.hermes_value_create_undefined(rt);
        }

        editor.deleteBuffer(buf_id, force) catch {
            // Silently fail (buffer modified and force=false, or buffer not found)
        };
    }
    // EditorContext: cannot delete the only buffer

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.api.createBuf(listed, scratch) -> Buffer
// ============================================================================

pub export fn apiCreateBuf(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, 0);

    if (ctx.editor) |editor| {
        // Create new buffer (listed and scratch flags are stored in buffer metadata)
        const new_id = editor.createBuffer() catch {
            return c.hermes_value_create_number(rt, 0);
        };
        return c.hermes_value_create_number(rt, @floatFromInt(new_id.id));
    }
    // EditorContext: return 0 (single buffer mode)
    return c.hermes_value_create_number(rt, 0);
}

// ============================================================================
// vim.api.bufGetText(buf, sr, sc, er, ec) -> string[]
// ============================================================================

pub export fn apiBufGetText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_array_create(rt, 0);

    if (count < 5) return c.hermes_array_create(rt, 0);

    const buf_handle_val = args[0] orelse return c.hermes_array_create(rt, 0);
    const start_row_val = args[1] orelse return c.hermes_array_create(rt, 0);
    const start_col_val = args[2] orelse return c.hermes_array_create(rt, 0);
    const end_row_val = args[3] orelse return c.hermes_array_create(rt, 0);
    const end_col_val = args[4] orelse return c.hermes_array_create(rt, 0);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const start_row = @as(i64, @intFromFloat(c.hermes_value_get_number(start_row_val)));
    const start_col = @as(i64, @intFromFloat(c.hermes_value_get_number(start_col_val)));
    const end_row = @as(i64, @intFromFloat(c.hermes_value_get_number(end_row_val)));
    const end_col = @as(i64, @intFromFloat(c.hermes_value_get_number(end_col_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_array_create(rt, 0);
    const line_count = buffer.lineCount();

    // Validate range
    if (start_row < 0 or end_row < 0) return c.hermes_array_create(rt, 0);
    if (@as(usize, @intCast(start_row)) >= line_count) return c.hermes_array_create(rt, 0);

    const sr: usize = @intCast(start_row);
    const er: usize = @min(@as(usize, @intCast(end_row)), line_count - 1);
    const sc: usize = if (start_col < 0) 0 else @intCast(start_col);
    const ec: usize = if (end_col < 0) 0 else @intCast(end_col);

    // Build result - for simplicity, return array of partial lines
    var result_lines: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (result_lines.items) |line| {
            ctx.allocator.free(line);
        }
        result_lines.deinit(ctx.allocator);
    }

    var row = sr;
    while (row <= er) : (row += 1) {
        const line = buffer.getLine(row) orelse continue;
        defer ctx.allocator.free(line);

        // Remove trailing newline
        const clean_line = if (line.len > 0 and line[line.len - 1] == '\n')
            line[0 .. line.len - 1]
        else
            line;

        const col_start: usize = if (row == sr) @min(sc, clean_line.len) else 0;
        const col_end: usize = if (row == er) @min(ec, clean_line.len) else clean_line.len;

        if (col_start <= col_end and col_end <= clean_line.len) {
            const slice = ctx.allocator.dupe(u8, clean_line[col_start..col_end]) catch continue;
            result_lines.append(ctx.allocator, slice) catch {
                ctx.allocator.free(slice);
                continue;
            };
        }
    }

    // Create JS array
    const arr = c.hermes_array_create(rt, result_lines.items.len) orelse return c.hermes_array_create(rt, 0);
    for (result_lines.items, 0..) |line, i| {
        const str = c.hermes_value_create_string(rt, line.ptr, line.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// vim.api.bufSetText(buf, sr, sc, er, ec, replacement) -> void
// ============================================================================

pub export fn apiBufSetText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 6) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const start_row_val = args[1] orelse return c.hermes_value_create_undefined(rt);
    const start_col_val = args[2] orelse return c.hermes_value_create_undefined(rt);
    const end_row_val = args[3] orelse return c.hermes_value_create_undefined(rt);
    const end_col_val = args[4] orelse return c.hermes_value_create_undefined(rt);
    const replacement_val = args[5] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const start_row = @as(i64, @intFromFloat(c.hermes_value_get_number(start_row_val)));
    const start_col = @as(i64, @intFromFloat(c.hermes_value_get_number(start_col_val)));
    const end_row = @as(i64, @intFromFloat(c.hermes_value_get_number(end_row_val)));
    const end_col = @as(i64, @intFromFloat(c.hermes_value_get_number(end_col_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_undefined(rt);
    const line_count = buffer.lineCount();

    if (start_row < 0 or end_row < 0) return c.hermes_value_create_undefined(rt);
    if (@as(usize, @intCast(start_row)) >= line_count) return c.hermes_value_create_undefined(rt);

    const sr: usize = @intCast(start_row);
    const er: usize = @min(@as(usize, @intCast(end_row)), line_count - 1);
    const sc: usize = if (start_col < 0) 0 else @intCast(start_col);
    const ec: usize = if (end_col < 0) 0 else @intCast(end_col);

    // Get replacement text
    const repl_len = c.hermes_array_length(rt, replacement_val);
    var replacement_text: std.ArrayListUnmanaged(u8) = .empty;
    defer replacement_text.deinit(ctx.allocator);

    var i: usize = 0;
    while (i < repl_len) : (i += 1) {
        const str_val = c.hermes_array_get(rt, replacement_val, i) orelse continue;
        defer c.hermes_value_destroy(str_val);

        var str_len: usize = 0;
        const str_ptr = c.hermes_value_get_string(rt, str_val, &str_len);
        if (str_ptr) |ptr| {
            replacement_text.appendSlice(ctx.allocator, ptr[0..str_len]) catch continue;
            if (i < repl_len - 1) {
                replacement_text.append(ctx.allocator, '\n') catch continue;
            }
        }
    }

    // Build new content
    var new_content: std.ArrayListUnmanaged(u8) = .empty;
    defer new_content.deinit(ctx.allocator);

    // Add content before start position
    var row: usize = 0;
    while (row < sr) : (row += 1) {
        const line = buffer.getLine(row) orelse continue;
        defer ctx.allocator.free(line);
        new_content.appendSlice(ctx.allocator, line) catch continue;
    }

    // Add start of start_row (before start_col)
    if (sr < line_count) {
        const start_line = buffer.getLine(sr) orelse "";
        defer if (start_line.len > 0) ctx.allocator.free(@constCast(start_line));
        const clean_start = if (start_line.len > 0 and start_line[start_line.len - 1] == '\n')
            start_line[0 .. start_line.len - 1]
        else
            start_line;
        const prefix_end = @min(sc, clean_start.len);
        new_content.appendSlice(ctx.allocator, clean_start[0..prefix_end]) catch {};
    }

    // Add replacement text
    new_content.appendSlice(ctx.allocator, replacement_text.items) catch {};

    // Add end of end_row (after end_col)
    if (er < line_count) {
        const end_line = buffer.getLine(er) orelse "";
        defer if (end_line.len > 0) ctx.allocator.free(@constCast(end_line));
        const suffix_start = @min(ec, end_line.len);
        new_content.appendSlice(ctx.allocator, end_line[suffix_start..]) catch {};
    }

    // Add content after end position
    row = er + 1;
    while (row < line_count) : (row += 1) {
        const line = buffer.getLine(row) orelse continue;
        defer ctx.allocator.free(line);
        new_content.appendSlice(ctx.allocator, line) catch continue;
    }

    // Replace buffer content
    const Rope = @import("../../editor/buffer/rope.zig").Rope;
    buffer.content.deinit();
    buffer.content = Rope.fromString(ctx.allocator, new_content.items) catch {
        buffer.content = Rope.init(ctx.allocator);
        return c.hermes_value_create_undefined(rt);
    };
    buffer.version += 1;

    // CRITICAL: Set js_state_dirty to trigger re-render
    // Without this, UI won't update after bufSetText is called
    if (ctx.editor) |editor| {
        editor.js_state_dirty = true;
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.api.bufIsLoaded(buf) -> boolean
// ============================================================================

pub export fn apiBufIsLoaded(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 1) return c.hermes_value_create_boolean(rt, false);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_boolean(rt, false);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // In Vimcraft, valid buffers are always loaded (no lazy loading yet)
    return c.hermes_value_create_boolean(rt, isBufferValid(buf_handle));
}

// ============================================================================
// vim.api.bufGetVar/bufSetVar/bufDelVar - Buffer variables (b:)
// ============================================================================

// Buffer variable storage (per-buffer HashMap stored in global context)
var buffer_vars: ?std.AutoHashMap(i64, std.StringHashMap(*c.OVHermesValue)) = null;

fn getOrCreateBufferVars(buf_handle: i64) ?*std.StringHashMap(*c.OVHermesValue) {
    const ctx = global_ctx orelse return null;
    if (buffer_vars == null) {
        buffer_vars = std.AutoHashMap(i64, std.StringHashMap(*c.OVHermesValue)).init(ctx.allocator);
    }
    var vars = &buffer_vars.?;

    const result = vars.getOrPut(buf_handle) catch return null;
    if (!result.found_existing) {
        result.value_ptr.* = std.StringHashMap(*c.OVHermesValue).init(ctx.allocator);
    }
    return result.value_ptr;
}

pub export fn apiBufGetVar(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 2) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);

    const vars = getOrCreateBufferVars(buf_handle) orelse return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    if (vars.get(name)) |stored_val| {
        // Return a copy of the stored value
        return c.hermes_value_clone(rt, stored_val);
    }

    return c.hermes_value_create_undefined(rt);
}

pub export fn apiBufSetVar(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 3) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);
    const value_val = args[2] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);

    const vars = getOrCreateBufferVars(buf_handle) orelse return c.hermes_value_create_undefined(rt);

    // Duplicate name for storage
    const name_dup = ctx.allocator.dupe(u8, name_ptr[0..name_len]) catch return c.hermes_value_create_undefined(rt);

    // Clone value for storage
    const value_clone = c.hermes_value_clone(rt, value_val) orelse {
        ctx.allocator.free(name_dup);
        return c.hermes_value_create_undefined(rt);
    };

    // Delete old value if exists
    if (vars.fetchRemove(name_dup)) |old| {
        c.hermes_value_destroy(old.value);
        ctx.allocator.free(old.key);
    }

    vars.put(name_dup, value_clone) catch {
        c.hermes_value_destroy(value_clone);
        ctx.allocator.free(name_dup);
    };

    return c.hermes_value_create_undefined(rt);
}

pub export fn apiBufDelVar(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 2) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const name_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) return c.hermes_value_create_undefined(rt);

    const vars = getOrCreateBufferVars(buf_handle) orelse return c.hermes_value_create_undefined(rt);
    const name = name_ptr[0..name_len];

    if (vars.fetchRemove(name)) |old| {
        c.hermes_value_destroy(old.value);
        ctx.allocator.free(old.key);
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.api.bufGetChangedtick(buf) -> number
// ============================================================================

pub export fn apiBufGetChangedtick(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 1) return c.hermes_value_create_number(rt, 0);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_number(rt, 0);
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_number(rt, 0);

    // Buffer.version is the changedtick
    return c.hermes_value_create_number(rt, @floatFromInt(buffer.version));
}

// ============================================================================
// vim.api.bufGetOffset(buf, line) -> number
// ============================================================================

pub export fn apiBufGetOffset(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, -1);

    if (count < 2) return c.hermes_value_create_number(rt, -1);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_number(rt, -1);
    const line_val = args[1] orelse return c.hermes_value_create_number(rt, -1);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const line_num = @as(i64, @intFromFloat(c.hermes_value_get_number(line_val)));

    if (line_num < 0) return c.hermes_value_create_number(rt, -1);

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_number(rt, -1);
    const line_count = buffer.lineCount();

    if (@as(usize, @intCast(line_num)) >= line_count) return c.hermes_value_create_number(rt, -1);

    // Calculate byte offset by summing line lengths
    var offset: usize = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(line_num))) : (i += 1) {
        const line = buffer.getLine(i) orelse continue;
        defer ctx.allocator.free(line);
        offset += line.len;
    }

    return c.hermes_value_create_number(rt, @floatFromInt(offset));
}

// ============================================================================
// vim.api.bufGetCharAt(buf, row, col) -> string
// Returns the character at the specified position (single UTF-8 codepoint)
// Used by smear-cursor to render the character under the cursor block
// ============================================================================

pub export fn apiBufGetCharAt(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_string(rt, "", 0);

    if (count < 3) return c.hermes_value_create_string(rt, "", 0);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_string(rt, "", 0);
    const row_val = args[1] orelse return c.hermes_value_create_string(rt, "", 0);
    const col_val = args[2] orelse return c.hermes_value_create_string(rt, "", 0);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const row = @as(i64, @intFromFloat(c.hermes_value_get_number(row_val)));
    const col = @as(i64, @intFromFloat(c.hermes_value_get_number(col_val)));

    if (row < 0 or col < 0) return c.hermes_value_create_string(rt, " ", 1);

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_string(rt, " ", 1);
    const line_count = buffer.lineCount();

    if (@as(usize, @intCast(row)) >= line_count) return c.hermes_value_create_string(rt, " ", 1);

    const line = buffer.getLine(@intCast(row)) orelse return c.hermes_value_create_string(rt, " ", 1);
    defer ctx.allocator.free(line);

    // Remove trailing newline if present
    const clean_line = if (line.len > 0 and line[line.len - 1] == '\n')
        line[0 .. line.len - 1]
    else
        line;

    // Handle column bounds - return space if beyond line end
    if (@as(usize, @intCast(col)) >= clean_line.len) {
        return c.hermes_value_create_string(rt, " ", 1);
    }

    // Find UTF-8 character at column (need to iterate codepoints)
    const target_col: usize = @intCast(col);
    var byte_idx: usize = 0;
    var col_idx: usize = 0;

    while (byte_idx < clean_line.len and col_idx < target_col) {
        const byte = clean_line[byte_idx];
        // Determine UTF-8 sequence length
        const seq_len: usize = if (byte & 0x80 == 0)
            1
        else if (byte & 0xE0 == 0xC0)
            2
        else if (byte & 0xF0 == 0xE0)
            3
        else if (byte & 0xF8 == 0xF0)
            4
        else
            1; // Invalid UTF-8, treat as single byte

        byte_idx += seq_len;
        col_idx += 1;
    }

    // Now byte_idx points to the start of the character at target_col
    if (byte_idx >= clean_line.len) {
        return c.hermes_value_create_string(rt, " ", 1);
    }

    // Determine length of character at this position
    const byte = clean_line[byte_idx];
    const char_len: usize = if (byte & 0x80 == 0)
        1
    else if (byte & 0xE0 == 0xC0)
        2
    else if (byte & 0xF0 == 0xE0)
        3
    else if (byte & 0xF8 == 0xF0)
        4
    else
        1;

    const end_idx = @min(byte_idx + char_len, clean_line.len);
    const char_slice = clean_line[byte_idx..end_idx];

    return c.hermes_value_create_string(rt, char_slice.ptr, char_slice.len);
}

// ============================================================================
// vim.api.bufCall(buf, fun) -> any
// ============================================================================

pub export fn apiBufCall(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    if (count < 2) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const fun_val = args[1] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // Verify buffer exists
    if (!isBufferValid(buf_handle)) {
        return c.hermes_value_create_undefined(rt);
    }

    // Call the function (in single-buffer mode, context doesn't change much)
    // Pass empty args array
    const result = c.hermes_call_function(rt, fun_val, null, 0);
    return result;
}

// ============================================================================
// vim.api.bufSetOption(buf, name, value) -> void
// Sets buffer-local options (currently supports 'filetype')
// When 'filetype' is set, also triggers tree-sitter syntax parsing for the buffer
// (per-buffer syntax following Neovim architecture for floating window highlighting)
// ============================================================================

pub export fn apiBufSetOption(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    if (count < 3) return c.hermes_value_create_undefined(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const opt_name_val = args[1] orelse return c.hermes_value_create_undefined(rt);
    const opt_value_val = args[2] orelse return c.hermes_value_create_undefined(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // Get option name
    var opt_name_len: usize = 0;
    const opt_name_ptr = c.hermes_value_get_string(rt, opt_name_val, &opt_name_len);
    if (opt_name_ptr == null or opt_name_len == 0) return c.hermes_value_create_undefined(rt);
    const opt_name = opt_name_ptr[0..opt_name_len];

    const buffer = getBufferByHandle(buf_handle) orelse return c.hermes_value_create_undefined(rt);

    // Handle 'filetype' option
    if (std.mem.eql(u8, opt_name, "filetype")) {
        var value_len: usize = 0;
        const value_ptr = c.hermes_value_get_string(rt, opt_value_val, &value_len);

        if (value_ptr) |ptr| {
            if (value_len > 0) {
                const filetype = ptr[0..value_len];
                buffer.setFiletype(filetype) catch {};

                // Trigger tree-sitter syntax parsing
                // NOTE: Scratch buffers CAN have syntax highlighting (e.g., markdown for hover popups)
                // The key is using the CORRECT filetype, not the source buffer's filetype
                if (ctx.editor) |editor| {
                    editor.parseBufferSyntax(buffer, filetype) catch {};
                } else if (ctx.editor_ctx) |editor_ctx| {
                    editor_ctx.editor.parseBufferSyntax(buffer, filetype) catch {};
                }
            } else {
                buffer.setFiletype(null) catch {};
                // Clear syntax when filetype is cleared
                buffer.deinitSyntax();
            }
        } else {
            buffer.setFiletype(null) catch {};
            // Clear syntax when filetype is cleared
            buffer.deinitSyntax();
        }
    }
    // Other options can be added here as needed

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// Registration
// ============================================================================

pub fn registerForEditor(runtime: *c.OVHermesRuntime, editor: *Editor, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(ApiBufferContext) catch return;
    ctx.* = ApiBufferContext{
        .allocator = allocator,
        .editor = editor,
        .editor_ctx = null,
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

pub fn registerForEditorContext(runtime: *c.OVHermesRuntime, editor_ctx: *EditorContext, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(ApiBufferContext) catch return;
    ctx.* = ApiBufferContext{
        .allocator = allocator,
        .editor = null,
        .editor_ctx = editor_ctx,
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

fn registerFunctions(runtime: *c.OVHermesRuntime) void {
    // Core buffer functions (Phase 1)
    c.hermes_register_host_function(runtime, "vimApiGetCurrentBuf", apiGetCurrentBuf, null);
    c.hermes_register_host_function(runtime, "vimApiSetCurrentBuf", apiSetCurrentBuf, null);
    c.hermes_register_host_function(runtime, "vimApiListBufs", apiListBufs, null);
    c.hermes_register_host_function(runtime, "vimApiBufLineCount", apiBufLineCount, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetLines", apiBufGetLines, null);
    c.hermes_register_host_function(runtime, "vimApiBufSetLines", apiBufSetLines, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetName", apiBufGetName, null);
    c.hermes_register_host_function(runtime, "vimApiBufSetName", apiBufSetName, null);
    c.hermes_register_host_function(runtime, "vimApiBufIsValid", apiBufIsValid, null);
    c.hermes_register_host_function(runtime, "vimApiBufDelete", apiBufDelete, null);

    // Extended buffer functions (Neovim compatibility)
    c.hermes_register_host_function(runtime, "vimApiCreateBuf", apiCreateBuf, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetText", apiBufGetText, null);
    c.hermes_register_host_function(runtime, "vimApiBufSetText", apiBufSetText, null);
    c.hermes_register_host_function(runtime, "vimApiBufIsLoaded", apiBufIsLoaded, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetVar", apiBufGetVar, null);
    c.hermes_register_host_function(runtime, "vimApiBufSetVar", apiBufSetVar, null);
    c.hermes_register_host_function(runtime, "vimApiBufDelVar", apiBufDelVar, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetChangedtick", apiBufGetChangedtick, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetOffset", apiBufGetOffset, null);
    c.hermes_register_host_function(runtime, "vimApiBufCall", apiBufCall, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetCharAt", apiBufGetCharAt, null);
    c.hermes_register_host_function(runtime, "vimApiBufSetOption", apiBufSetOption, null);
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}
