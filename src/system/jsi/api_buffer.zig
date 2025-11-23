/// vim.api Buffer Functions
/// Implements Neovim-compatible buffer API:
/// - getCurrentBuf() -> Buffer (handle)
/// - bufLineCount(buf) -> number
/// - bufGetLines(buf, start, end, strict) -> string[]
/// - bufSetLines(buf, start, end, strict, lines) -> void
/// - bufGetName(buf) -> string
/// - bufIsValid(buf) -> boolean
///
/// These are registered as global functions for vim.api.* wrappers in runtime.js
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// Context for buffer API functions
/// Stores pointer to editor (or context) and allocator
pub const ApiBufferContext = struct {
    allocator: std.mem.Allocator,
    /// Function pointer to get current buffer (works for both Editor and EditorContext)
    get_buffer_fn: *const fn (*anyopaque) ?*Buffer,
    /// Function pointer to get buffer filename
    get_filename_fn: *const fn (*anyopaque) []const u8,
    /// Opaque pointer to Editor or EditorContext
    context_ptr: *anyopaque,
};

/// Global context (set during registration)
var global_ctx: ?*ApiBufferContext = null;

/// vim.api.getCurrentBuf() -> Buffer
/// Returns current buffer handle (always 0 for single-buffer mode)
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

    // Return 0 for current buffer (Neovim convention)
    return c.hermes_value_create_number(rt, 0);
}

/// vim.api.bufLineCount(buf) -> number
/// Returns number of lines in buffer
pub export fn apiBufLineCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    // Validate arguments (buf handle)
    if (count < 1) return c.hermes_value_create_null(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const buf_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // Only buffer 0 (current) is valid for now
    if (buf_handle != 0) return c.hermes_value_create_null(rt);

    const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_null(rt);
    return c.hermes_value_create_number(rt, @floatFromInt(buffer.lineCount()));
}

/// vim.api.bufGetLines(buf, start, end, strict) -> string[]
/// Returns lines from buffer (0-indexed, end exclusive, -1 for end of file)
pub export fn apiBufGetLines(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    // Validate arguments (buf, start, end, strict)
    if (count < 4) return c.hermes_value_create_null(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const start_val = args[1] orelse return c.hermes_value_create_null(rt);
    const end_val = args[2] orelse return c.hermes_value_create_null(rt);
    // const strict_val = args[3]; // strict_indexing (for error vs clamp behavior)

    const buf_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const start_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(start_val)));
    const end_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(end_val)));

    // Only buffer 0 (current) is valid for now
    if (buf_handle != 0) return c.hermes_value_create_null(rt);

    const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_null(rt);
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
            // Empty line
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

/// vim.api.bufSetLines(buf, start, end, strict, lines) -> void
/// Replaces lines in buffer (0-indexed, end exclusive, -1 for end of file)
pub export fn apiBufSetLines(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    // Validate arguments (buf, start, end, strict, lines)
    if (count < 5) return c.hermes_value_create_null(rt);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_null(rt);
    const start_val = args[1] orelse return c.hermes_value_create_null(rt);
    const end_val = args[2] orelse return c.hermes_value_create_null(rt);
    // const strict_val = args[3]; // strict_indexing (for error vs clamp behavior)
    const lines_val = args[4] orelse return c.hermes_value_create_null(rt);

    const buf_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));
    const start_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(start_val)));
    const end_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(end_val)));

    // Only buffer 0 (current) is valid for now
    if (buf_handle != 0) return c.hermes_value_create_null(rt);

    const buffer = ctx.get_buffer_fn(ctx.context_ptr) orelse return c.hermes_value_create_null(rt);
    const line_count = buffer.lineCount();

    // Handle negative indices (Neovim: -1 = end of buffer)
    const start: usize = if (start_raw < 0) line_count else @intCast(@min(start_raw, @as(i64, @intCast(line_count))));
    const end: usize = if (end_raw < 0) line_count else @intCast(@min(end_raw, @as(i64, @intCast(line_count))));

    // Get lines array length
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
        // Ensure line ends with newline (last line might not have one)
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
        // Restore empty rope on failure
        buffer.content = Rope.init(ctx.allocator);
        return c.hermes_value_create_null(rt);
    };
    // Note: Rope tracks lines internally, no buildLineIndex needed
    buffer.version += 1;

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.bufGetName(buf) -> string
/// Returns buffer filename (empty string for unnamed buffer)
pub export fn apiBufGetName(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_string(rt, "", 0);

    // Validate arguments (buf handle)
    if (count < 1) return c.hermes_value_create_string(rt, "", 0);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_string(rt, "", 0);
    const buf_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // Only buffer 0 (current) is valid for now
    if (buf_handle != 0) return c.hermes_value_create_string(rt, "", 0);

    const filename = ctx.get_filename_fn(ctx.context_ptr);
    return c.hermes_value_create_string(rt, filename.ptr, filename.len);
}

/// vim.api.bufIsValid(buf) -> boolean
/// Returns true if buffer handle is valid
pub export fn apiBufIsValid(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;

    // Validate arguments (buf handle)
    if (count < 1) return c.hermes_value_create_boolean(rt, false);

    const buf_handle_val = args[0] orelse return c.hermes_value_create_boolean(rt, false);
    const buf_handle = @as(i32, @intFromFloat(c.hermes_value_get_number(buf_handle_val)));

    // Only buffer 0 (current) is valid for now
    // In future with multi-buffer support, this would check buffer registry
    return c.hermes_value_create_boolean(rt, buf_handle == 0);
}

// ============================================================================
// Registration
// ============================================================================

/// Register vim.api buffer functions for Editor mode
pub fn registerForEditor(runtime: *c.OVHermesRuntime, editor: *Editor, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(ApiBufferContext) catch return;
    ctx.* = ApiBufferContext{
        .allocator = allocator,
        .get_buffer_fn = &getBufferFromEditor,
        .get_filename_fn = &getFilenameFromEditor,
        .context_ptr = @ptrCast(editor),
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

/// Register vim.api buffer functions for EditorContext mode (headless/E2E)
pub fn registerForEditorContext(runtime: *c.OVHermesRuntime, editor_ctx: *EditorContext, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(ApiBufferContext) catch return;
    ctx.* = ApiBufferContext{
        .allocator = allocator,
        .get_buffer_fn = &getBufferFromEditorContext,
        .get_filename_fn = &getFilenameFromEditorContext,
        .context_ptr = @ptrCast(editor_ctx),
    };
    global_ctx = ctx;

    registerFunctions(runtime);
}

fn registerFunctions(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_function(runtime, "vimApiGetCurrentBuf", apiGetCurrentBuf, null);
    c.hermes_register_host_function(runtime, "vimApiBufLineCount", apiBufLineCount, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetLines", apiBufGetLines, null);
    c.hermes_register_host_function(runtime, "vimApiBufSetLines", apiBufSetLines, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetName", apiBufGetName, null);
    c.hermes_register_host_function(runtime, "vimApiBufIsValid", apiBufIsValid, null);
}

/// Cleanup
pub fn deinit() void {
    if (global_ctx) |ctx| {
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}

// ============================================================================
// Helper functions for context abstraction
// ============================================================================

fn getBufferFromEditor(ptr: *anyopaque) ?*Buffer {
    const editor: *Editor = @ptrCast(@alignCast(ptr));
    return editor.getCurrentBuffer();
}

fn getBufferFromEditorContext(ptr: *anyopaque) ?*Buffer {
    const ctx: *EditorContext = @ptrCast(@alignCast(ptr));
    // EditorContext.buffer() returns *Buffer (non-optional)
    return ctx.buffer();
}

fn getFilenameFromEditor(ptr: *anyopaque) []const u8 {
    const editor: *Editor = @ptrCast(@alignCast(ptr));
    const buffer = editor.getCurrentBuffer() orelse return "";
    return buffer.filepath orelse "";
}

fn getFilenameFromEditorContext(ptr: *anyopaque) []const u8 {
    const ctx: *EditorContext = @ptrCast(@alignCast(ptr));
    // EditorContext.buffer() returns *Buffer (non-optional)
    const buffer = ctx.buffer();
    return buffer.filepath orelse "";
}
