/// Namespace API - vim.api.createNamespace(), bufAddHighlight(), bufClearNamespace()
/// Implements Neovim-compatible namespace management for highlights and extmarks
///
/// Architecture:
/// - Namespaces are integer IDs that group related decorations (highlights, extmarks)
/// - Namespace 0 is global (applies everywhere)
/// - Named namespaces can be created with createNamespace()
/// - Buffer highlights are stored per-buffer and rendered by compositor
///
/// Usage:
///   const ns = vim.api.createNamespace('my-plugin');
///   vim.api.bufAddHighlight(0, ns, 'Error', 0, 0, 5);
///   vim.api.bufClearNamespace(0, ns, 0, -1);
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Editor = @import("../../editor/editor.zig").Editor;
const editor_module = @import("../../editor/editor.zig");
const BufferId = editor_module.BufferId;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// ============================================================================
// Types
// ============================================================================

/// Namespace ID (0 = global, N > 0 = created namespace)
pub const NamespaceId = u32;

/// A single buffer highlight (extmark with highlight)
pub const BufferHighlight = struct {
    /// Namespace this highlight belongs to
    ns_id: NamespaceId,
    /// Highlight group name (e.g., "Error", "Comment")
    hl_group: []const u8,
    /// Line number (0-indexed)
    line: usize,
    /// Start column (0-indexed, byte offset)
    col_start: usize,
    /// End column (0-indexed, byte offset, exclusive)
    col_end: usize,
    /// Unique ID for this highlight (returned by bufAddHighlight)
    id: u32,
};

/// Namespace registry - tracks named namespaces and their IDs
pub const NamespaceRegistry = struct {
    allocator: std.mem.Allocator,
    /// Name → ID mapping
    name_to_id: std.StringHashMap(NamespaceId),
    /// Next namespace ID to allocate
    next_id: NamespaceId,

    pub fn init(allocator: std.mem.Allocator) NamespaceRegistry {
        return .{
            .allocator = allocator,
            .name_to_id = std.StringHashMap(NamespaceId).init(allocator),
            .next_id = 1, // 0 is reserved for global
        };
    }

    pub fn deinit(self: *NamespaceRegistry) void {
        // Free all stored names
        var iter = self.name_to_id.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.name_to_id.deinit();
    }

    /// Create or get namespace by name
    /// Returns existing ID if name already registered, creates new if not
    pub fn getOrCreate(self: *NamespaceRegistry, name: []const u8) !NamespaceId {
        if (self.name_to_id.get(name)) |id| {
            return id;
        }

        // Create new namespace
        const id = self.next_id;
        self.next_id += 1;

        // Store name copy
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        try self.name_to_id.put(name_copy, id);
        return id;
    }
};

/// Buffer highlight storage - per-buffer collection of highlights
pub const BufferHighlights = struct {
    allocator: std.mem.Allocator,
    /// All highlights in this buffer
    highlights: std.ArrayListUnmanaged(BufferHighlight),
    /// Next highlight ID
    next_hl_id: u32,

    pub fn init(allocator: std.mem.Allocator) BufferHighlights {
        return .{
            .allocator = allocator,
            .highlights = .empty,
            .next_hl_id = 1,
        };
    }

    pub fn deinit(self: *BufferHighlights) void {
        // Free all hl_group strings
        for (self.highlights.items) |hl| {
            self.allocator.free(hl.hl_group);
        }
        self.highlights.deinit(self.allocator);
    }

    /// Add a highlight, returns unique ID
    pub fn add(
        self: *BufferHighlights,
        ns_id: NamespaceId,
        hl_group: []const u8,
        line: usize,
        col_start: usize,
        col_end: usize,
    ) !u32 {
        const id = self.next_hl_id;
        self.next_hl_id += 1;

        const hl_group_copy = try self.allocator.dupe(u8, hl_group);
        errdefer self.allocator.free(hl_group_copy);

        try self.highlights.append(self.allocator, .{
            .ns_id = ns_id,
            .hl_group = hl_group_copy,
            .line = line,
            .col_start = col_start,
            .col_end = col_end,
            .id = id,
        });

        return id;
    }

    /// Clear highlights in a namespace within a line range
    /// line_start and line_end are 0-indexed, line_end is exclusive
    /// If line_end < 0 (max value), clear to end of buffer
    pub fn clearNamespace(self: *BufferHighlights, ns_id: NamespaceId, line_start: usize, line_end: usize) void {
        // Remove matching highlights in reverse to avoid index invalidation
        var i: usize = self.highlights.items.len;
        while (i > 0) {
            i -= 1;
            const hl = self.highlights.items[i];

            // Check namespace match (ns_id 0 clears all namespaces)
            const ns_match = (ns_id == 0 or hl.ns_id == ns_id);

            // Check line range (max value for line_end means all lines)
            const in_range = hl.line >= line_start and
                (line_end == std.math.maxInt(usize) or hl.line < line_end);

            if (ns_match and in_range) {
                // Free hl_group string
                self.allocator.free(hl.hl_group);
                _ = self.highlights.orderedRemove(i);
            }
        }
    }

    /// Iterator for highlights on a specific line
    /// Used by compositor to render highlights without allocation
    pub const LineHighlightIterator = struct {
        highlights: []const BufferHighlight,
        line: usize,
        index: usize,

        pub fn next(self: *LineHighlightIterator) ?BufferHighlight {
            while (self.index < self.highlights.len) {
                const hl = self.highlights[self.index];
                self.index += 1;
                if (hl.line == self.line) {
                    return hl;
                }
            }
            return null;
        }
    };

    /// Get iterator for highlights on a specific line (used by compositor)
    /// Returns an iterator that yields only highlights matching the line
    /// Zero allocation - compositor can iterate without memory overhead
    pub fn iterHighlightsForLine(self: *const BufferHighlights, line: usize) LineHighlightIterator {
        return .{
            .highlights = self.highlights.items,
            .line = line,
            .index = 0,
        };
    }

    /// Check if any highlights exist for a line (fast path for compositor)
    pub fn hasHighlightsForLine(self: *const BufferHighlights, line: usize) bool {
        for (self.highlights.items) |hl| {
            if (hl.line == line) return true;
        }
        return false;
    }

    /// Get all highlights (for debugging/testing)
    pub fn getAllHighlights(self: *const BufferHighlights) []const BufferHighlight {
        return self.highlights.items;
    }
};

// ============================================================================
// Context
// ============================================================================

pub const NamespaceContext = struct {
    allocator: std.mem.Allocator,
    /// Global namespace registry (shared across all buffers)
    registry: NamespaceRegistry,
    /// Per-buffer highlight storage: buffer_handle → highlights
    buffer_highlights: std.AutoHashMap(i64, *BufferHighlights),
    /// Per-buffer extmark storage: buffer_handle → extmarks
    buffer_extmarks: std.AutoHashMap(i64, *BufferExtmarks),
    /// Editor pointer (for buffer access)
    editor: ?*Editor,
    /// EditorContext pointer (for headless mode)
    editor_ctx: ?*EditorContext,
    /// Dirty flag for triggering re-render
    js_state_dirty: ?*bool,

    pub fn init(allocator: std.mem.Allocator, editor: ?*Editor, editor_ctx: ?*EditorContext, js_state_dirty: ?*bool) NamespaceContext {
        return .{
            .allocator = allocator,
            .registry = NamespaceRegistry.init(allocator),
            .buffer_highlights = std.AutoHashMap(i64, *BufferHighlights).init(allocator),
            .buffer_extmarks = std.AutoHashMap(i64, *BufferExtmarks).init(allocator),
            .editor = editor,
            .editor_ctx = editor_ctx,
            .js_state_dirty = js_state_dirty,
        };
    }

    pub fn deinit(self: *NamespaceContext) void {
        // Free all buffer highlights
        var hl_iter = self.buffer_highlights.valueIterator();
        while (hl_iter.next()) |hl_ptr| {
            hl_ptr.*.deinit();
            self.allocator.destroy(hl_ptr.*);
        }
        self.buffer_highlights.deinit();

        // Free all buffer extmarks
        var ext_iter = self.buffer_extmarks.valueIterator();
        while (ext_iter.next()) |ext_ptr| {
            ext_ptr.*.deinit();
            self.allocator.destroy(ext_ptr.*);
        }
        self.buffer_extmarks.deinit();

        self.registry.deinit();
    }

    /// Get or create buffer extmarks storage
    pub fn getOrCreateBufferExtmarks(self: *NamespaceContext, buf_handle: i64) !*BufferExtmarks {
        const result = try self.buffer_extmarks.getOrPut(buf_handle);
        if (!result.found_existing) {
            const ext = try self.allocator.create(BufferExtmarks);
            ext.* = BufferExtmarks.init(self.allocator);
            result.value_ptr.* = ext;
        }
        return result.value_ptr.*;
    }

    /// Get or create buffer highlights storage
    fn getOrCreateBufferHighlights(self: *NamespaceContext, buf_handle: i64) !*BufferHighlights {
        const result = try self.buffer_highlights.getOrPut(buf_handle);
        if (!result.found_existing) {
            const hl = try self.allocator.create(BufferHighlights);
            hl.* = BufferHighlights.init(self.allocator);
            result.value_ptr.* = hl;
        }
        return result.value_ptr.*;
    }

    /// Get buffer by handle (0 = current, N = BufferId{.id=N})
    fn getBufferByHandle(self: *NamespaceContext, handle: i64) ?*Buffer {
        if (self.editor) |editor| {
            if (handle == 0) {
                return editor.getCurrentBuffer();
            } else if (handle > 0) {
                const buf_id = BufferId{ .id = @intCast(handle) };
                return editor.buffers.get(buf_id);
            }
            return null;
        } else if (self.editor_ctx) |ctx| {
            if (handle == 0) {
                return ctx.buffer();
            }
            return null;
        }
        return null;
    }
};

/// Global context (set during registration)
var global_ctx: ?*NamespaceContext = null;

// ============================================================================
// vim.api.createNamespace(name) -> number
// ============================================================================

pub export fn apiCreateNamespace(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, 0);

    if (count < 1) return c.hermes_value_create_number(rt, 0);

    const name_val = args[0] orelse return c.hermes_value_create_number(rt, 0);

    if (!c.hermes_value_is_string(name_val)) {
        return c.hermes_value_create_number(rt, 0);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(rt, name_val, &name_len);
    if (name_ptr == null or name_len == 0) {
        return c.hermes_value_create_number(rt, 0);
    }

    const name = name_ptr[0..name_len];

    const ns_id = ctx.registry.getOrCreate(name) catch {
        return c.hermes_value_create_number(rt, 0);
    };

    return c.hermes_value_create_number(rt, @floatFromInt(ns_id));
}

// ============================================================================
// vim.api.getNamespaces() -> { [name: string]: number }
// ============================================================================

pub export fn apiGetNamespaces(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_object(rt);

    // Create result object
    const result = c.hermes_value_create_object(rt) orelse return null;

    // Iterate through all namespaces and add to result
    var iter = ctx.registry.name_to_id.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const id = entry.value_ptr.*;

        // Create number value for ID
        const id_val = c.hermes_value_create_number(rt, @floatFromInt(id));

        // Set property on result object (name must be null-terminated)
        // Create a null-terminated copy for the C API
        var name_buf: [256]u8 = undefined;
        if (name.len < name_buf.len) {
            @memcpy(name_buf[0..name.len], name);
            name_buf[name.len] = 0;
            c.hermes_value_set_property(rt, result, &name_buf, id_val);
        }
    }

    return result;
}

// ============================================================================
// vim.api.bufAddHighlight(buffer, ns_id, hl_group, line, col_start, col_end) -> number
// ============================================================================

pub export fn apiBufAddHighlight(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, 0);

    // Need 6 arguments: buffer, ns_id, hl_group, line, col_start, col_end
    if (count < 6) return c.hermes_value_create_number(rt, 0);

    const buf_val = args[0] orelse return c.hermes_value_create_number(rt, 0);
    const ns_val = args[1] orelse return c.hermes_value_create_number(rt, 0);
    const hl_group_val = args[2] orelse return c.hermes_value_create_number(rt, 0);
    const line_val = args[3] orelse return c.hermes_value_create_number(rt, 0);
    const col_start_val = args[4] orelse return c.hermes_value_create_number(rt, 0);
    const col_end_val = args[5] orelse return c.hermes_value_create_number(rt, 0);

    // Parse buffer handle
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_val)));

    // Validate buffer exists
    const buffer = ctx.getBufferByHandle(buf_handle) orelse {
        return c.hermes_value_create_number(rt, 0);
    };

    // Parse and validate namespace ID (must be non-negative)
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_value_create_number(rt, 0);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Parse highlight group name
    if (!c.hermes_value_is_string(hl_group_val)) {
        return c.hermes_value_create_number(rt, 0);
    }
    var hl_group_len: usize = 0;
    const hl_group_ptr = c.hermes_value_get_string(rt, hl_group_val, &hl_group_len);
    if (hl_group_ptr == null) {
        return c.hermes_value_create_number(rt, 0);
    }
    const hl_group = hl_group_ptr[0..hl_group_len];

    // Parse line number (0-indexed)
    const line_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(line_val)));
    if (line_raw < 0) return c.hermes_value_create_number(rt, 0);
    const line: usize = @intCast(line_raw);

    // Validate line exists in buffer
    if (line >= buffer.lineCount()) {
        return c.hermes_value_create_number(rt, 0);
    }

    // Parse column range
    const col_start_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(col_start_val)));
    const col_end_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(col_end_val)));

    const col_start: usize = if (col_start_raw < 0) 0 else @intCast(col_start_raw);
    // col_end < 0 means end of line (Neovim convention)
    const col_end: usize = if (col_end_raw < 0) std.math.maxInt(usize) else @intCast(col_end_raw);

    // Get or create buffer highlights
    const buf_hls = ctx.getOrCreateBufferHighlights(buf_handle) catch {
        return c.hermes_value_create_number(rt, 0);
    };

    // Add highlight
    const hl_id = buf_hls.add(ns_id, hl_group, line, col_start, col_end) catch {
        return c.hermes_value_create_number(rt, 0);
    };

    // Mark dirty for re-render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_number(rt, @floatFromInt(hl_id));
}

// ============================================================================
// vim.api.bufClearNamespace(buffer, ns_id, line_start, line_end) -> void
// ============================================================================

pub export fn apiBufClearNamespace(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Need 4 arguments: buffer, ns_id, line_start, line_end
    if (count < 4) return c.hermes_value_create_undefined(rt);

    const buf_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const ns_val = args[1] orelse return c.hermes_value_create_undefined(rt);
    const line_start_val = args[2] orelse return c.hermes_value_create_undefined(rt);
    const line_end_val = args[3] orelse return c.hermes_value_create_undefined(rt);

    // Parse buffer handle
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_val)));

    // Parse and validate namespace ID (must be non-negative)
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_value_create_undefined(rt);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Parse line range
    const line_start_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(line_start_val)));
    const line_end_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(line_end_val)));

    const line_start: usize = if (line_start_raw < 0) 0 else @intCast(line_start_raw);
    // line_end < 0 means all lines (Neovim: -1 = end of buffer)
    const line_end: usize = if (line_end_raw < 0) std.math.maxInt(usize) else @intCast(line_end_raw);

    // Get buffer highlights (if exists)
    if (ctx.buffer_highlights.get(buf_handle)) |buf_hls| {
        buf_hls.clearNamespace(ns_id, line_start, line_end);

        // Mark dirty for re-render
        if (ctx.js_state_dirty) |dirty| {
            dirty.* = true;
        }
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// Registration
// ============================================================================

pub fn registerForEditor(runtime: *c.OVHermesRuntime, editor: *Editor, allocator: std.mem.Allocator, js_state_dirty: ?*bool) void {
    const ctx = allocator.create(NamespaceContext) catch return;
    ctx.* = NamespaceContext.init(allocator, editor, null, js_state_dirty);
    global_ctx = ctx;

    registerFunctions(runtime);
}

pub fn registerForEditorContext(runtime: *c.OVHermesRuntime, editor_ctx: *EditorContext, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(NamespaceContext) catch return;
    ctx.* = NamespaceContext.init(allocator, null, editor_ctx, null);
    global_ctx = ctx;

    registerFunctions(runtime);
}

fn registerFunctions(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_function(runtime, "vimApiCreateNamespace", apiCreateNamespace, null);
    c.hermes_register_host_function(runtime, "vimApiGetNamespaces", apiGetNamespaces, null);
    c.hermes_register_host_function(runtime, "vimApiBufAddHighlight", apiBufAddHighlight, null);
    c.hermes_register_host_function(runtime, "vimApiBufClearNamespace", apiBufClearNamespace, null);
    // Extmark API
    c.hermes_register_host_function(runtime, "vimApiBufSetExtmark", apiBufSetExtmark, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetExtmarks", apiBufGetExtmarks, null);
    c.hermes_register_host_function(runtime, "vimApiBufDelExtmark", apiBufDelExtmark, null);
    c.hermes_register_host_function(runtime, "vimApiBufGetExtmarkById", apiBufGetExtmarkById, null);
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        ctx.deinit();
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}

/// Get buffer highlights for rendering (called by compositor)
/// Returns all highlights for the given buffer
pub fn getBufferHighlights(buf_handle: i64) ?*const BufferHighlights {
    const ctx = global_ctx orelse return null;
    return ctx.buffer_highlights.get(buf_handle);
}

/// Get the global namespace context (for compositor integration)
pub fn getContext() ?*NamespaceContext {
    return global_ctx;
}

/// Clean up highlights for a specific buffer (called on BufDelete)
/// This prevents memory leaks when buffers are closed
pub fn cleanupBuffer(buf_handle: i64) void {
    const ctx = global_ctx orelse return;

    // Remove and free buffer highlights
    if (ctx.buffer_highlights.fetchRemove(buf_handle)) |kv| {
        var buf_hls = kv.value;
        buf_hls.deinit();
        ctx.allocator.destroy(buf_hls);
    }

    // Remove and free buffer extmarks
    if (ctx.buffer_extmarks.fetchRemove(buf_handle)) |kv| {
        var buf_exts = kv.value;
        buf_exts.deinit();
        ctx.allocator.destroy(buf_exts);
    }
}

// ============================================================================
// Extmarks API
// ============================================================================

/// Virtual text position
pub const VirtTextPos = enum {
    eol,
    overlay,
    rightAlign,
    @"inline",
};

/// A single extmark with position and metadata
pub const Extmark = struct {
    id: u32,
    ns_id: NamespaceId,
    line: usize,
    col: usize,
    end_line: ?usize = null,
    end_col: ?usize = null,
    hl_group: ?[]const u8 = null,
    priority: u32 = 0,
    virt_text_pos: VirtTextPos = .eol,
};

/// Buffer extmark storage
pub const BufferExtmarks = struct {
    allocator: std.mem.Allocator,
    extmarks: std.ArrayListUnmanaged(Extmark),
    next_id: u32,

    pub fn init(allocator: std.mem.Allocator) BufferExtmarks {
        return .{
            .allocator = allocator,
            .extmarks = .empty,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *BufferExtmarks) void {
        for (self.extmarks.items) |ext| {
            if (ext.hl_group) |hg| self.allocator.free(hg);
        }
        self.extmarks.deinit(self.allocator);
    }

    /// Set or update an extmark
    pub fn set(
        self: *BufferExtmarks,
        ns_id: NamespaceId,
        line: usize,
        col: usize,
        custom_id: ?u32,
        end_line: ?usize,
        end_col: ?usize,
        hl_group: ?[]const u8,
        priority: u32,
    ) !u32 {
        const id = custom_id orelse blk: {
            const new_id = self.next_id;
            self.next_id += 1;
            break :blk new_id;
        };

        // Check if updating existing extmark
        for (self.extmarks.items, 0..) |*ext, i| {
            if (ext.id == id and ext.ns_id == ns_id) {
                // Free old hl_group if exists
                if (ext.hl_group) |hg| self.allocator.free(hg);

                // Update in place
                ext.line = line;
                ext.col = col;
                ext.end_line = end_line;
                ext.end_col = end_col;
                ext.hl_group = if (hl_group) |hg| try self.allocator.dupe(u8, hg) else null;
                ext.priority = priority;

                // Re-sort
                self.sort();
                _ = i;
                return id;
            }
        }

        // Create new extmark
        const hl_group_copy = if (hl_group) |hg| try self.allocator.dupe(u8, hg) else null;
        errdefer if (hl_group_copy) |hg| self.allocator.free(hg);

        try self.extmarks.append(self.allocator, .{
            .id = id,
            .ns_id = ns_id,
            .line = line,
            .col = col,
            .end_line = end_line,
            .end_col = end_col,
            .hl_group = hl_group_copy,
            .priority = priority,
        });

        // Update next_id if custom_id was used
        if (custom_id) |cid| {
            if (cid >= self.next_id) {
                self.next_id = cid + 1;
            }
        }

        self.sort();
        return id;
    }

    /// Delete extmark by ID
    pub fn delete(self: *BufferExtmarks, ns_id: NamespaceId, id: u32) bool {
        for (self.extmarks.items, 0..) |ext, i| {
            if (ext.id == id and ext.ns_id == ns_id) {
                if (ext.hl_group) |hg| self.allocator.free(hg);
                _ = self.extmarks.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Get extmark by ID
    pub fn getById(self: *const BufferExtmarks, ns_id: NamespaceId, id: u32) ?Extmark {
        for (self.extmarks.items) |ext| {
            if (ext.id == id and ext.ns_id == ns_id) {
                return ext;
            }
        }
        return null;
    }

    /// Sort extmarks by position (line, col)
    fn sort(self: *BufferExtmarks) void {
        std.mem.sort(Extmark, self.extmarks.items, {}, struct {
            fn lessThan(_: void, a: Extmark, b: Extmark) bool {
                if (a.line != b.line) return a.line < b.line;
                return a.col < b.col;
            }
        }.lessThan);
    }
};

// ============================================================================
// vim.api.bufSetExtmark(buffer, ns, line, col, opts) -> number
// ============================================================================

pub export fn apiBufSetExtmark(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_number(rt, 0);

    if (count < 5) return c.hermes_value_create_number(rt, 0);

    const buf_val = args[0] orelse return c.hermes_value_create_number(rt, 0);
    const ns_val = args[1] orelse return c.hermes_value_create_number(rt, 0);
    const line_val = args[2] orelse return c.hermes_value_create_number(rt, 0);
    const col_val = args[3] orelse return c.hermes_value_create_number(rt, 0);
    const opts_val = args[4] orelse return c.hermes_value_create_number(rt, 0);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_val)));

    // Validate buffer handle is non-negative (0 = current buffer, >0 = specific buffer)
    if (buf_handle < 0) return c.hermes_value_create_number(rt, 0);

    // Validate ns_id is non-negative
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_value_create_number(rt, 0);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Validate line/col are non-negative
    const line_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(line_val)));
    const col_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(col_val)));
    if (line_raw < 0 or col_raw < 0) return c.hermes_value_create_number(rt, 0);

    const line: usize = @intCast(line_raw);
    const col: usize = @intCast(col_raw);

    // Parse options
    var custom_id: ?u32 = null;
    var end_line: ?usize = null;
    var end_col: ?usize = null;
    var hl_group: ?[]const u8 = null;
    var priority: u32 = 0;

    if (c.hermes_value_get_property(rt, opts_val, "id")) |id_val| {
        if (c.hermes_value_is_number(id_val)) {
            const id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(id_val)));
            if (id_raw > 0) {
                custom_id = @intCast(id_raw);
            }
            // id <= 0 is ignored (auto-generate ID)
        }
    }

    if (c.hermes_value_get_property(rt, opts_val, "endLine")) |el_val| {
        if (c.hermes_value_is_number(el_val)) {
            const el_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(el_val)));
            if (el_raw >= 0) {
                end_line = @intCast(el_raw);
            }
            // negative endLine is ignored
        }
    }

    if (c.hermes_value_get_property(rt, opts_val, "endCol")) |ec_val| {
        if (c.hermes_value_is_number(ec_val)) {
            const ec_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ec_val)));
            if (ec_raw >= 0) {
                end_col = @intCast(ec_raw);
            }
            // negative endCol is ignored
        }
    }

    if (c.hermes_value_get_property(rt, opts_val, "hlGroup")) |hg_val| {
        if (c.hermes_value_is_string(hg_val)) {
            var hg_len: usize = 0;
            const hg_ptr = c.hermes_value_get_string(rt, hg_val, &hg_len);
            if (hg_ptr != null and hg_len > 0) {
                hl_group = hg_ptr[0..hg_len];
            }
        }
    }

    if (c.hermes_value_get_property(rt, opts_val, "priority")) |p_val| {
        if (c.hermes_value_is_number(p_val)) {
            const p_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(p_val)));
            if (p_raw >= 0) {
                priority = @intCast(p_raw);
            }
            // negative priority is ignored (defaults to 0)
        }
    }

    // Get or create buffer extmarks
    const buf_exts = ctx.getOrCreateBufferExtmarks(buf_handle) catch {
        return c.hermes_value_create_number(rt, 0);
    };

    const id = buf_exts.set(ns_id, line, col, custom_id, end_line, end_col, hl_group, priority) catch {
        return c.hermes_value_create_number(rt, 0);
    };

    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_number(rt, @floatFromInt(id));
}

// ============================================================================
// vim.api.bufGetExtmarks(buffer, ns, start, end, opts) -> array
// ============================================================================

const ExtmarkPosition = struct {
    line: usize,
    col: usize,
};

fn parseExtmarkPosition(
    rt: *c.OVHermesRuntime,
    val: *c.OVHermesValue,
    buf_extmarks: ?*const BufferExtmarks,
    ns_id: NamespaceId,
    is_end: bool,
) ?ExtmarkPosition {
    // Check if it's an array [line, col]
    if (c.hermes_value_is_array(rt, val)) {
        const len = c.hermes_array_length(rt, val);
        if (len >= 2) {
            const line_val = c.hermes_array_get(rt, val, 0) orelse return null;
            const col_val = c.hermes_array_get(rt, val, 1) orelse return null;

            if (c.hermes_value_is_number(line_val) and c.hermes_value_is_number(col_val)) {
                // Validate non-negative values
                const line_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(line_val)));
                const col_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(col_val)));
                if (line_raw < 0 or col_raw < 0) return null;
                return .{
                    .line = @intCast(line_raw),
                    .col = @intCast(col_raw),
                };
            }
        }
        return null;
    }

    // Check if it's a number
    if (c.hermes_value_is_number(val)) {
        const num = @as(i64, @intFromFloat(c.hermes_value_get_number(val)));

        if (num == 0) {
            return .{ .line = 0, .col = 0 };
        } else if (num == -1) {
            return .{ .line = std.math.maxInt(usize), .col = std.math.maxInt(usize) };
        } else if (num > 0) {
            // Positive number = extmark ID, lookup its position
            if (buf_extmarks) |exts| {
                if (exts.getById(ns_id, @intCast(num))) |ext| {
                    if (is_end) {
                        // For end position, use end of extmark if available
                        return .{
                            .line = ext.end_line orelse ext.line,
                            .col = ext.end_col orelse ext.col,
                        };
                    } else {
                        return .{ .line = ext.line, .col = ext.col };
                    }
                }
            }
        }
    }

    return null;
}

pub export fn apiBufGetExtmarks(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_array_create(rt, 0);

    if (count < 4) return c.hermes_array_create(rt, 0);

    const buf_val = args[0] orelse return c.hermes_array_create(rt, 0);
    const ns_val = args[1] orelse return c.hermes_array_create(rt, 0);
    const start_val = args[2] orelse return c.hermes_array_create(rt, 0);
    const end_val = args[3] orelse return c.hermes_array_create(rt, 0);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_val)));

    // Validate ns_id is non-negative
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_array_create(rt, 0);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Get buffer extmarks
    const buf_exts = ctx.buffer_extmarks.get(buf_handle) orelse {
        return c.hermes_array_create(rt, 0);
    };

    // Parse start/end positions
    const start_pos = parseExtmarkPosition(rt, start_val, buf_exts, ns_id, false) orelse {
        return c.hermes_array_create(rt, 0);
    };
    const end_pos = parseExtmarkPosition(rt, end_val, buf_exts, ns_id, true) orelse {
        return c.hermes_array_create(rt, 0);
    };

    // Parse options
    var limit: ?usize = null;
    var details = false;

    if (count >= 5) {
        if (args[4]) |opts_val| {
            if (c.hermes_value_get_property(rt, opts_val, "limit")) |l_val| {
                if (c.hermes_value_is_number(l_val)) {
                    const l_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(l_val)));
                    if (l_raw > 0) {
                        limit = @intCast(l_raw);
                    }
                    // negative or zero limit is ignored (no limit)
                }
            }
            if (c.hermes_value_get_property(rt, opts_val, "details")) |d_val| {
                // Check if truthy (boolean true or non-zero number)
                if (c.hermes_value_is_boolean(d_val)) {
                    details = c.hermes_value_get_boolean(d_val);
                }
            }
        }
    }

    // Check for limit=0 early
    if (limit) |l| {
        if (l == 0) return c.hermes_array_create(rt, 0);
    }

    // Helper to compare positions without overflow
    const posLessThanOrEqual = struct {
        fn cmp(a_line: usize, a_col: usize, b_line: usize, b_col: usize) bool {
            if (a_line < b_line) return true;
            if (a_line > b_line) return false;
            return a_col <= b_col;
        }
    }.cmp;

    // First pass: count matching extmarks
    var match_count: usize = 0;
    for (buf_exts.extmarks.items) |ext| {
        if (ext.ns_id != ns_id) continue;
        // Check: start_pos <= ext_pos <= end_pos
        const after_start = posLessThanOrEqual(start_pos.line, start_pos.col, ext.line, ext.col);
        const before_end = posLessThanOrEqual(ext.line, ext.col, end_pos.line, end_pos.col);
        if (!after_start or !before_end) continue;
        match_count += 1;
        if (limit) |l| {
            if (match_count >= l) break;
        }
    }

    // Create result array with correct size
    const result = c.hermes_array_create(rt, match_count) orelse return null;
    var result_idx: usize = 0;

    for (buf_exts.extmarks.items) |ext| {
        if (ext.ns_id != ns_id) continue;

        // Check position range: start_pos <= ext_pos <= end_pos
        const after_start = posLessThanOrEqual(start_pos.line, start_pos.col, ext.line, ext.col);
        const before_end = posLessThanOrEqual(ext.line, ext.col, end_pos.line, end_pos.col);
        if (!after_start or !before_end) continue;

        // Check limit
        if (limit) |l| {
            if (result_idx >= l) break;
        }

        // Create extmark tuple
        if (details) {
            // [id, line, col, details]
            const tuple = c.hermes_array_create(rt, 4) orelse continue;
            c.hermes_array_set(rt, tuple, 0, c.hermes_value_create_number(rt, @floatFromInt(ext.id)));
            c.hermes_array_set(rt, tuple, 1, c.hermes_value_create_number(rt, @floatFromInt(ext.line)));
            c.hermes_array_set(rt, tuple, 2, c.hermes_value_create_number(rt, @floatFromInt(ext.col)));

            // Create details object
            const det = c.hermes_value_create_object(rt) orelse continue;

            if (ext.end_line) |el| {
                c.hermes_value_set_property(rt, det, "endLine", c.hermes_value_create_number(rt, @floatFromInt(el)));
            }
            if (ext.end_col) |ec| {
                c.hermes_value_set_property(rt, det, "endCol", c.hermes_value_create_number(rt, @floatFromInt(ec)));
            }
            if (ext.hl_group) |hg| {
                if (c.hermes_value_create_string(rt, hg.ptr, hg.len)) |hg_val| {
                    c.hermes_value_set_property(rt, det, "hlGroup", hg_val);
                }
            }
            c.hermes_value_set_property(rt, det, "priority", c.hermes_value_create_number(rt, @floatFromInt(ext.priority)));

            c.hermes_array_set(rt, tuple, 3, det);
            c.hermes_array_set(rt, result, result_idx, tuple);
        } else {
            // [id, line, col]
            const tuple = c.hermes_array_create(rt, 3) orelse continue;
            c.hermes_array_set(rt, tuple, 0, c.hermes_value_create_number(rt, @floatFromInt(ext.id)));
            c.hermes_array_set(rt, tuple, 1, c.hermes_value_create_number(rt, @floatFromInt(ext.line)));
            c.hermes_array_set(rt, tuple, 2, c.hermes_value_create_number(rt, @floatFromInt(ext.col)));
            c.hermes_array_set(rt, result, result_idx, tuple);
        }

        result_idx += 1;
    }

    return result;
}

// ============================================================================
// vim.api.bufDelExtmark(buffer, ns, id) -> boolean
// ============================================================================

pub export fn apiBufDelExtmark(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_boolean(rt, false);

    if (count < 3) return c.hermes_value_create_boolean(rt, false);

    const buf_val = args[0] orelse return c.hermes_value_create_boolean(rt, false);
    const ns_val = args[1] orelse return c.hermes_value_create_boolean(rt, false);
    const id_val = args[2] orelse return c.hermes_value_create_boolean(rt, false);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_val)));

    // Validate ns_id is non-negative
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_value_create_boolean(rt, false);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Validate id is non-negative
    const id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(id_val)));
    if (id_raw < 0) return c.hermes_value_create_boolean(rt, false);
    const id: u32 = @intCast(id_raw);

    const buf_exts = ctx.buffer_extmarks.get(buf_handle) orelse {
        return c.hermes_value_create_boolean(rt, false);
    };

    const deleted = buf_exts.delete(ns_id, id);

    if (deleted) {
        if (ctx.js_state_dirty) |dirty| {
            dirty.* = true;
        }
    }

    return c.hermes_value_create_boolean(rt, deleted);
}

// ============================================================================
// vim.api.bufGetExtmarkById(buffer, ns, id, opts) -> [line, col] | null
// ============================================================================

pub export fn apiBufGetExtmarkById(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_null(rt);

    if (count < 3) return c.hermes_value_create_null(rt);

    const buf_val = args[0] orelse return c.hermes_value_create_null(rt);
    const ns_val = args[1] orelse return c.hermes_value_create_null(rt);
    const id_val = args[2] orelse return c.hermes_value_create_null(rt);

    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(buf_val)));

    // Validate ns_id is non-negative
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_value_create_null(rt);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Validate id is non-negative
    const id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(id_val)));
    if (id_raw < 0) return c.hermes_value_create_null(rt);
    const id: u32 = @intCast(id_raw);

    const buf_exts = ctx.buffer_extmarks.get(buf_handle) orelse {
        return c.hermes_value_create_null(rt);
    };

    const ext = buf_exts.getById(ns_id, id) orelse {
        return c.hermes_value_create_null(rt);
    };

    // Check for details option
    var details = false;
    if (count >= 4) {
        if (args[3]) |opts_val| {
            if (c.hermes_value_get_property(rt, opts_val, "details")) |d_val| {
                if (c.hermes_value_is_boolean(d_val)) {
                    details = c.hermes_value_get_boolean(d_val);
                }
            }
        }
    }

    if (details) {
        // Return [line, col, details]
        const result = c.hermes_array_create(rt, 3) orelse return c.hermes_value_create_null(rt);
        c.hermes_array_set(rt, result, 0, c.hermes_value_create_number(rt, @floatFromInt(ext.line)));
        c.hermes_array_set(rt, result, 1, c.hermes_value_create_number(rt, @floatFromInt(ext.col)));

        const det = c.hermes_value_create_object(rt) orelse return c.hermes_value_create_null(rt);
        if (ext.end_line) |el| {
            c.hermes_value_set_property(rt, det, "endLine", c.hermes_value_create_number(rt, @floatFromInt(el)));
        }
        if (ext.end_col) |ec| {
            c.hermes_value_set_property(rt, det, "endCol", c.hermes_value_create_number(rt, @floatFromInt(ec)));
        }
        if (ext.hl_group) |hg| {
            if (c.hermes_value_create_string(rt, hg.ptr, hg.len)) |hg_val| {
                c.hermes_value_set_property(rt, det, "hlGroup", hg_val);
            }
        }
        c.hermes_value_set_property(rt, det, "priority", c.hermes_value_create_number(rt, @floatFromInt(ext.priority)));

        c.hermes_array_set(rt, result, 2, det);
        return result;
    } else {
        // Return [line, col]
        const result = c.hermes_array_create(rt, 2) orelse return c.hermes_value_create_null(rt);
        c.hermes_array_set(rt, result, 0, c.hermes_value_create_number(rt, @floatFromInt(ext.line)));
        c.hermes_array_set(rt, result, 1, c.hermes_value_create_number(rt, @floatFromInt(ext.col)));
        return result;
    }
}
