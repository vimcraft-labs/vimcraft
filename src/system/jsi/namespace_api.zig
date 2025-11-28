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
            .editor = editor,
            .editor_ctx = editor_ctx,
            .js_state_dirty = js_state_dirty,
        };
    }

    pub fn deinit(self: *NamespaceContext) void {
        // Free all buffer highlights
        var iter = self.buffer_highlights.valueIterator();
        while (iter.next()) |hl_ptr| {
            hl_ptr.*.deinit();
            self.allocator.destroy(hl_ptr.*);
        }
        self.buffer_highlights.deinit();
        self.registry.deinit();
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

    // Parse namespace ID
    const ns_id = @as(NamespaceId, @intFromFloat(c.hermes_value_get_number(ns_val)));

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

    // Parse namespace ID
    const ns_id = @as(NamespaceId, @intFromFloat(c.hermes_value_get_number(ns_val)));

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
    c.hermes_register_host_function(runtime, "vimApiBufAddHighlight", apiBufAddHighlight, null);
    c.hermes_register_host_function(runtime, "vimApiBufClearNamespace", apiBufClearNamespace, null);
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
}
