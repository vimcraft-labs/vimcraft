/// Diagnostic API - vim.diagnostic.set(), get(), reset(), count(), severity
/// Implements Neovim-compatible diagnostic system for LSP support
///
/// Architecture:
/// - Diagnostics are stored per-buffer, grouped by namespace
/// - Each diagnostic has: lnum, col, end_lnum, end_col, severity, message, source, code
/// - Severity levels: ERROR=1, WARN=2, INFO=3, HINT=4 (Neovim-compatible)
///
/// Usage:
///   const ns = vim.api.createNamespace('my-lsp');
///   vim.diagnostic.set(ns, 0, [{ lnum: 0, col: 5, message: "Error", severity: 1 }]);
///   const diags = vim.diagnostic.get(0);
///   vim.diagnostic.reset(ns, 0);
const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const EditorContext = @import("../../backends/headless/editor_context.zig").EditorContext;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// ============================================================================
// Types
// ============================================================================

/// Diagnostic severity levels (Neovim-compatible)
pub const DiagnosticSeverity = enum(u8) {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    HINT = 4,

    pub fn fromInt(val: u8) ?DiagnosticSeverity {
        return switch (val) {
            1 => .ERROR,
            2 => .WARN,
            3 => .INFO,
            4 => .HINT,
            else => null,
        };
    }

    pub fn toString(self: DiagnosticSeverity) []const u8 {
        return switch (self) {
            .ERROR => "ERROR",
            .WARN => "WARN",
            .INFO => "INFO",
            .HINT => "HINT",
        };
    }
};

/// Namespace ID (same as namespace_api.zig)
pub const NamespaceId = u32;

/// A single diagnostic entry
pub const Diagnostic = struct {
    /// Namespace this diagnostic belongs to
    ns_id: NamespaceId,
    /// Line number (0-indexed)
    lnum: usize,
    /// Column number (0-indexed, byte offset)
    col: usize,
    /// End line number (0-indexed)
    end_lnum: usize,
    /// End column number (0-indexed, byte offset)
    end_col: usize,
    /// Severity level
    severity: DiagnosticSeverity,
    /// Diagnostic message (owned)
    message: []const u8,
    /// Source (e.g., "typescript", "eslint") - optional, owned
    source: ?[]const u8,
    /// Error code (e.g., "TS6133") - optional, owned
    code: ?[]const u8,
    /// Buffer number this diagnostic belongs to
    bufnr: i64,
};

/// Buffer diagnostic storage - per-buffer collection of diagnostics
pub const BufferDiagnostics = struct {
    allocator: std.mem.Allocator,
    /// All diagnostics in this buffer
    diagnostics: std.ArrayListUnmanaged(Diagnostic),

    pub fn init(allocator: std.mem.Allocator) BufferDiagnostics {
        return .{
            .allocator = allocator,
            .diagnostics = .empty,
        };
    }

    pub fn deinit(self: *BufferDiagnostics) void {
        // Free all owned strings
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
            if (diag.source) |s| self.allocator.free(s);
            if (diag.code) |code_str| self.allocator.free(code_str);
        }
        self.diagnostics.deinit(self.allocator);
    }

    /// Set diagnostics for a namespace (replaces existing)
    /// NOTE: Takes ownership of strings in new_diagnostics (message, source, code)
    /// Caller must have allocated these with the same allocator
    pub fn setForNamespace(
        self: *BufferDiagnostics,
        ns_id: NamespaceId,
        new_diagnostics: []const Diagnostic,
        bufnr: i64,
    ) !void {
        // First, clear existing diagnostics for this namespace
        self.clearNamespace(ns_id);

        // Add new diagnostics (taking ownership of already-allocated strings)
        for (new_diagnostics) |diag| {
            try self.diagnostics.append(self.allocator, .{
                .ns_id = ns_id,
                .lnum = diag.lnum,
                .col = diag.col,
                .end_lnum = diag.end_lnum,
                .end_col = diag.end_col,
                .severity = diag.severity,
                .message = diag.message, // Takes ownership
                .source = diag.source,   // Takes ownership
                .code = diag.code,       // Takes ownership
                .bufnr = bufnr,
            });
        }
    }

    /// Clear diagnostics for a specific namespace
    pub fn clearNamespace(self: *BufferDiagnostics, ns_id: NamespaceId) void {
        // Remove matching diagnostics in reverse to avoid index invalidation
        var i: usize = self.diagnostics.items.len;
        while (i > 0) {
            i -= 1;
            const diag = self.diagnostics.items[i];

            if (diag.ns_id == ns_id) {
                // Free owned strings
                self.allocator.free(diag.message);
                if (diag.source) |s| self.allocator.free(s);
                if (diag.code) |code_str| self.allocator.free(code_str);
                _ = self.diagnostics.orderedRemove(i);
            }
        }
    }

};

// ============================================================================
// Context
// ============================================================================

pub const DiagnosticContext = struct {
    allocator: std.mem.Allocator,
    /// Per-buffer diagnostic storage: buffer_handle -> diagnostics
    buffer_diagnostics: std.AutoHashMap(i64, *BufferDiagnostics),
    /// Editor pointer (for buffer access)
    editor: ?*Editor,
    /// EditorContext pointer (for headless mode)
    editor_ctx: ?*EditorContext,
    /// Dirty flag for triggering re-render
    js_state_dirty: ?*bool,

    pub fn init(allocator: std.mem.Allocator, editor: ?*Editor, editor_ctx: ?*EditorContext, js_state_dirty: ?*bool) DiagnosticContext {
        return .{
            .allocator = allocator,
            .buffer_diagnostics = std.AutoHashMap(i64, *BufferDiagnostics).init(allocator),
            .editor = editor,
            .editor_ctx = editor_ctx,
            .js_state_dirty = js_state_dirty,
        };
    }

    pub fn deinit(self: *DiagnosticContext) void {
        // Free all buffer diagnostics
        var iter = self.buffer_diagnostics.valueIterator();
        while (iter.next()) |diag_ptr| {
            diag_ptr.*.deinit();
            self.allocator.destroy(diag_ptr.*);
        }
        self.buffer_diagnostics.deinit();
    }

    /// Get or create buffer diagnostics storage
    pub fn getOrCreateBufferDiagnostics(self: *DiagnosticContext, buf_handle: i64) !*BufferDiagnostics {
        const result = try self.buffer_diagnostics.getOrPut(buf_handle);
        if (!result.found_existing) {
            const diags = try self.allocator.create(BufferDiagnostics);
            diags.* = BufferDiagnostics.init(self.allocator);
            result.value_ptr.* = diags;
        }
        return result.value_ptr.*;
    }
};

/// Global context (set during registration)
var global_ctx: ?*DiagnosticContext = null;

// ============================================================================
// vim.diagnostic.set(namespace, bufnr, diagnostics, opts?)
// ============================================================================

pub export fn diagnosticSet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Need at least 3 arguments: namespace, bufnr, diagnostics
    if (count < 3) return c.hermes_value_create_undefined(rt);

    const ns_val = args[0] orelse return c.hermes_value_create_undefined(rt);
    const bufnr_val = args[1] orelse return c.hermes_value_create_undefined(rt);
    const diags_val = args[2] orelse return c.hermes_value_create_undefined(rt);

    // Parse namespace ID
    const ns_id_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
    if (ns_id_raw < 0) return c.hermes_value_create_undefined(rt);
    const ns_id: NamespaceId = @intCast(ns_id_raw);

    // Parse buffer handle
    const buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(bufnr_val)));

    // Parse diagnostics array
    if (!c.hermes_value_is_array(rt, diags_val)) {
        return c.hermes_value_create_undefined(rt);
    }

    const diag_count = c.hermes_array_length(rt, diags_val);

    // Use ArrayListUnmanaged for temporary allocations during parsing
    var temp_list: std.ArrayListUnmanaged(Diagnostic) = .empty;
    defer temp_list.deinit(ctx.allocator);

    for (0..diag_count) |i| {
        const diag_obj = c.hermes_array_get(rt, diags_val, i) orelse continue;

        // Parse required fields
        const lnum_val = c.hermes_value_get_property(rt, diag_obj, "lnum") orelse continue;
        const col_val = c.hermes_value_get_property(rt, diag_obj, "col") orelse continue;
        const msg_val = c.hermes_value_get_property(rt, diag_obj, "message") orelse continue;

        if (!c.hermes_value_is_number(lnum_val) or !c.hermes_value_is_number(col_val)) continue;
        if (!c.hermes_value_is_string(msg_val)) continue;

        const lnum_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(lnum_val)));
        const col_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(col_val)));
        if (lnum_raw < 0 or col_raw < 0) continue;

        var msg_len: usize = 0;
        const msg_ptr = c.hermes_value_get_string(rt, msg_val, &msg_len);
        if (msg_ptr == null) continue;

        // Parse optional severity (default to ERROR=1)
        var severity: DiagnosticSeverity = .ERROR;
        if (c.hermes_value_get_property(rt, diag_obj, "severity")) |sev_val| {
            if (c.hermes_value_is_number(sev_val)) {
                const sev_raw = @as(u8, @intFromFloat(c.hermes_value_get_number(sev_val)));
                severity = DiagnosticSeverity.fromInt(sev_raw) orelse .ERROR;
            }
        }

        // Parse optional end_lnum/end_col (default to lnum/col)
        const lnum: usize = @intCast(lnum_raw);
        const col: usize = @intCast(col_raw);

        var end_lnum: usize = lnum;
        var end_col: usize = col;

        if (c.hermes_value_get_property(rt, diag_obj, "endLnum")) |el_val| {
            if (c.hermes_value_is_number(el_val)) {
                const el_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(el_val)));
                if (el_raw >= 0) end_lnum = @intCast(el_raw);
            }
        }

        if (c.hermes_value_get_property(rt, diag_obj, "endCol")) |ec_val| {
            if (c.hermes_value_is_number(ec_val)) {
                const ec_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ec_val)));
                if (ec_raw >= 0) end_col = @intCast(ec_raw);
            }
        }

        // Copy message immediately (Hermes strings may be GC'd)
        const message_copy = ctx.allocator.dupe(u8, msg_ptr[0..msg_len]) catch continue;
        errdefer ctx.allocator.free(message_copy);

        // Parse optional source (copy immediately)
        var source_copy: ?[]const u8 = null;
        if (c.hermes_value_get_property(rt, diag_obj, "source")) |src_val| {
            if (c.hermes_value_is_string(src_val)) {
                var src_len: usize = 0;
                const src_ptr = c.hermes_value_get_string(rt, src_val, &src_len);
                if (src_ptr != null and src_len > 0) {
                    source_copy = ctx.allocator.dupe(u8, src_ptr[0..src_len]) catch null;
                }
            }
        }
        errdefer if (source_copy) |s| ctx.allocator.free(s);

        // Parse optional code (copy immediately)
        var code_copy: ?[]const u8 = null;
        if (c.hermes_value_get_property(rt, diag_obj, "code")) |code_val| {
            if (c.hermes_value_is_string(code_val)) {
                var code_len: usize = 0;
                const code_ptr = c.hermes_value_get_string(rt, code_val, &code_len);
                if (code_ptr != null and code_len > 0) {
                    code_copy = ctx.allocator.dupe(u8, code_ptr[0..code_len]) catch null;
                }
            }
        }
        errdefer if (code_copy) |c_str| ctx.allocator.free(c_str);

        temp_list.append(ctx.allocator, .{
            .ns_id = ns_id,
            .lnum = lnum,
            .col = col,
            .end_lnum = end_lnum,
            .end_col = end_col,
            .severity = severity,
            .message = message_copy,
            .source = source_copy,
            .code = code_copy,
            .bufnr = buf_handle,
        }) catch {
            // Clean up on append failure
            ctx.allocator.free(message_copy);
            if (source_copy) |s| ctx.allocator.free(s);
            if (code_copy) |c_str| ctx.allocator.free(c_str);
            continue;
        };
    }

    // Get or create buffer diagnostics
    const buf_diags = ctx.getOrCreateBufferDiagnostics(buf_handle) catch {
        // On failure, free all strings we allocated in temp_list
        for (temp_list.items) |diag| {
            ctx.allocator.free(diag.message);
            if (diag.source) |s| ctx.allocator.free(s);
            if (diag.code) |c_str| ctx.allocator.free(c_str);
        }
        return c.hermes_value_create_undefined(rt);
    };

    // Set diagnostics (replaces existing for this namespace)
    // This takes ownership of the strings, so clear temp_list capacity to prevent double-free
    buf_diags.setForNamespace(ns_id, temp_list.items, buf_handle) catch {
        // On failure, free all strings we allocated in temp_list
        for (temp_list.items) |diag| {
            ctx.allocator.free(diag.message);
            if (diag.source) |s| ctx.allocator.free(s);
            if (diag.code) |c_str| ctx.allocator.free(c_str);
        }
        return c.hermes_value_create_undefined(rt);
    };

    // Ownership transferred - clear items to prevent double-free in defer
    temp_list.items.len = 0;

    // Mark dirty for re-render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.diagnostic.get(bufnr?, opts?)
// ============================================================================

pub export fn diagnosticGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_array_create(rt, 0);

    // Parse optional bufnr (nil = all buffers)
    var buf_handle: ?i64 = null;
    if (count >= 1) {
        if (args[0]) |bufnr_val| {
            if (c.hermes_value_is_number(bufnr_val)) {
                buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(bufnr_val)));
            }
        }
    }

    // Parse optional opts
    var ns_filter: ?NamespaceId = null;
    var severity_filter: ?DiagnosticSeverity = null;
    var lnum_filter: ?usize = null;

    if (count >= 2) {
        if (args[1]) |opts_val| {
            // namespace filter
            if (c.hermes_value_get_property(rt, opts_val, "namespace")) |ns_val| {
                if (c.hermes_value_is_number(ns_val)) {
                    const ns_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
                    if (ns_raw > 0) ns_filter = @intCast(ns_raw);
                }
            }

            // severity filter
            if (c.hermes_value_get_property(rt, opts_val, "severity")) |sev_val| {
                if (c.hermes_value_is_number(sev_val)) {
                    const sev_raw = @as(u8, @intFromFloat(c.hermes_value_get_number(sev_val)));
                    severity_filter = DiagnosticSeverity.fromInt(sev_raw);
                }
            }

            // lnum filter
            if (c.hermes_value_get_property(rt, opts_val, "lnum")) |lnum_val| {
                if (c.hermes_value_is_number(lnum_val)) {
                    const lnum_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(lnum_val)));
                    if (lnum_raw >= 0) lnum_filter = @intCast(lnum_raw);
                }
            }
        }
    }

    // Collect diagnostics
    var result_list: std.ArrayListUnmanaged(Diagnostic) = .empty;
    defer result_list.deinit(ctx.allocator);

    if (buf_handle) |bh| {
        // Single buffer
        if (ctx.buffer_diagnostics.get(bh)) |buf_diags| {
            for (buf_diags.diagnostics.items) |diag| {
                if (matchesFilter(diag, ns_filter, severity_filter, lnum_filter)) {
                    result_list.append(ctx.allocator, diag) catch continue;
                }
            }
        }
    } else {
        // All buffers
        var iter = ctx.buffer_diagnostics.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.*.diagnostics.items) |diag| {
                if (matchesFilter(diag, ns_filter, severity_filter, lnum_filter)) {
                    result_list.append(ctx.allocator, diag) catch continue;
                }
            }
        }
    }

    // Create JS array
    const result = c.hermes_array_create(rt, result_list.items.len) orelse return null;

    for (result_list.items, 0..) |diag, i| {
        const diag_obj = c.hermes_value_create_object(rt) orelse continue;

        // Required fields
        c.hermes_value_set_property(rt, diag_obj, "lnum", c.hermes_value_create_number(rt, @floatFromInt(diag.lnum)));
        c.hermes_value_set_property(rt, diag_obj, "col", c.hermes_value_create_number(rt, @floatFromInt(diag.col)));
        c.hermes_value_set_property(rt, diag_obj, "endLnum", c.hermes_value_create_number(rt, @floatFromInt(diag.end_lnum)));
        c.hermes_value_set_property(rt, diag_obj, "endCol", c.hermes_value_create_number(rt, @floatFromInt(diag.end_col)));
        c.hermes_value_set_property(rt, diag_obj, "severity", c.hermes_value_create_number(rt, @floatFromInt(@intFromEnum(diag.severity))));
        c.hermes_value_set_property(rt, diag_obj, "bufnr", c.hermes_value_create_number(rt, @floatFromInt(diag.bufnr)));

        if (c.hermes_value_create_string(rt, diag.message.ptr, diag.message.len)) |msg_val| {
            c.hermes_value_set_property(rt, diag_obj, "message", msg_val);
        }

        // Optional fields
        if (diag.source) |src| {
            if (c.hermes_value_create_string(rt, src.ptr, src.len)) |src_val| {
                c.hermes_value_set_property(rt, diag_obj, "source", src_val);
            }
        }

        if (diag.code) |code_str| {
            if (c.hermes_value_create_string(rt, code_str.ptr, code_str.len)) |code_val| {
                c.hermes_value_set_property(rt, diag_obj, "code", code_val);
            }
        }

        c.hermes_array_set(rt, result, i, diag_obj);
    }

    return result;
}

fn matchesFilter(diag: Diagnostic, ns_filter: ?NamespaceId, severity_filter: ?DiagnosticSeverity, lnum_filter: ?usize) bool {
    if (ns_filter) |ns| {
        if (diag.ns_id != ns) return false;
    }
    if (severity_filter) |sev| {
        if (diag.severity != sev) return false;
    }
    if (lnum_filter) |lnum| {
        if (diag.lnum != lnum) return false;
    }
    return true;
}

// ============================================================================
// vim.diagnostic.reset(namespace?, bufnr?)
// ============================================================================

pub export fn diagnosticReset(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_undefined(rt);

    // Parse optional namespace
    var ns_filter: ?NamespaceId = null;
    if (count >= 1) {
        if (args[0]) |ns_val| {
            if (c.hermes_value_is_number(ns_val)) {
                const ns_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
                if (ns_raw > 0) ns_filter = @intCast(ns_raw);
            }
        }
    }

    // Parse optional bufnr
    var buf_handle: ?i64 = null;
    if (count >= 2) {
        if (args[1]) |bufnr_val| {
            if (c.hermes_value_is_number(bufnr_val)) {
                buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(bufnr_val)));
            }
        }
    }

    if (ns_filter) |ns| {
        // Clear specific namespace
        if (buf_handle) |bh| {
            // Specific buffer
            if (ctx.buffer_diagnostics.get(bh)) |buf_diags| {
                buf_diags.clearNamespace(ns);
            }
        } else {
            // All buffers
            var iter = ctx.buffer_diagnostics.valueIterator();
            while (iter.next()) |buf_diags| {
                buf_diags.*.clearNamespace(ns);
            }
        }
    } else {
        // Clear all diagnostics
        if (buf_handle) |bh| {
            // Specific buffer - clear all namespaces
            if (ctx.buffer_diagnostics.get(bh)) |buf_diags| {
                // Clear all by deiniting and reiniting
                buf_diags.deinit();
                buf_diags.* = BufferDiagnostics.init(ctx.allocator);
            }
        } else {
            // All buffers - clear everything
            var iter = ctx.buffer_diagnostics.valueIterator();
            while (iter.next()) |buf_diags| {
                buf_diags.*.deinit();
                buf_diags.*.* = BufferDiagnostics.init(ctx.allocator);
            }
        }
    }

    // Mark dirty for re-render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(rt);
}

// ============================================================================
// vim.diagnostic.count(bufnr?, opts?)
// ============================================================================

pub export fn diagnosticCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const rt = runtime orelse return null;
    const ctx = global_ctx orelse return c.hermes_value_create_object(rt);

    // Parse optional bufnr
    var buf_handle: ?i64 = null;
    if (count >= 1) {
        if (args[0]) |bufnr_val| {
            if (c.hermes_value_is_number(bufnr_val)) {
                buf_handle = @as(i64, @intFromFloat(c.hermes_value_get_number(bufnr_val)));
            }
        }
    }

    // Parse optional opts (for namespace filter)
    var ns_filter: ?NamespaceId = null;
    if (count >= 2) {
        if (args[1]) |opts_val| {
            if (c.hermes_value_get_property(rt, opts_val, "namespace")) |ns_val| {
                if (c.hermes_value_is_number(ns_val)) {
                    const ns_raw = @as(i64, @intFromFloat(c.hermes_value_get_number(ns_val)));
                    if (ns_raw > 0) ns_filter = @intCast(ns_raw);
                }
            }
        }
    }

    // Count by severity
    var counts: [5]usize = .{ 0, 0, 0, 0, 0 }; // Index 0 unused, 1-4 for severities

    if (buf_handle) |bh| {
        if (ctx.buffer_diagnostics.get(bh)) |buf_diags| {
            for (buf_diags.diagnostics.items) |diag| {
                if (ns_filter == null or diag.ns_id == ns_filter.?) {
                    counts[@intFromEnum(diag.severity)] += 1;
                }
            }
        }
    } else {
        var iter = ctx.buffer_diagnostics.valueIterator();
        while (iter.next()) |buf_diags| {
            for (buf_diags.*.diagnostics.items) |diag| {
                if (ns_filter == null or diag.ns_id == ns_filter.?) {
                    counts[@intFromEnum(diag.severity)] += 1;
                }
            }
        }
    }

    // Create result object with severity keys (1-4)
    // Neovim returns sparse object: only keys with count > 0
    const result = c.hermes_value_create_object(rt) orelse return null;

    if (counts[1] > 0) {
        c.hermes_value_set_property(rt, result, "1", c.hermes_value_create_number(rt, @floatFromInt(counts[1])));
    }
    if (counts[2] > 0) {
        c.hermes_value_set_property(rt, result, "2", c.hermes_value_create_number(rt, @floatFromInt(counts[2])));
    }
    if (counts[3] > 0) {
        c.hermes_value_set_property(rt, result, "3", c.hermes_value_create_number(rt, @floatFromInt(counts[3])));
    }
    if (counts[4] > 0) {
        c.hermes_value_set_property(rt, result, "4", c.hermes_value_create_number(rt, @floatFromInt(counts[4])));
    }

    return result;
}

// ============================================================================
// Registration
// ============================================================================

pub fn registerForEditor(runtime: *c.OVHermesRuntime, editor: *Editor, allocator: std.mem.Allocator, js_state_dirty: ?*bool) void {
    const ctx = allocator.create(DiagnosticContext) catch return;
    ctx.* = DiagnosticContext.init(allocator, editor, null, js_state_dirty);
    global_ctx = ctx;

    registerFunctions(runtime);
}

pub fn registerForEditorContext(runtime: *c.OVHermesRuntime, editor_ctx: *EditorContext, allocator: std.mem.Allocator) void {
    const ctx = allocator.create(DiagnosticContext) catch return;
    ctx.* = DiagnosticContext.init(allocator, null, editor_ctx, null);
    global_ctx = ctx;

    registerFunctions(runtime);
}

fn registerFunctions(runtime: *c.OVHermesRuntime) void {
    c.hermes_register_host_function(runtime, "vimDiagnosticSet", diagnosticSet, null);
    c.hermes_register_host_function(runtime, "vimDiagnosticGet", diagnosticGet, null);
    c.hermes_register_host_function(runtime, "vimDiagnosticReset", diagnosticReset, null);
    c.hermes_register_host_function(runtime, "vimDiagnosticCount", diagnosticCount, null);
}

pub fn deinit() void {
    if (global_ctx) |ctx| {
        ctx.deinit();
        ctx.allocator.destroy(ctx);
        global_ctx = null;
    }
}

/// Get buffer diagnostics for rendering (called by compositor)
pub fn getBufferDiagnostics(buf_handle: i64) ?*const BufferDiagnostics {
    const ctx = global_ctx orelse return null;
    return ctx.buffer_diagnostics.get(buf_handle);
}

/// Clean up diagnostics for a specific buffer (called on BufDelete)
pub fn cleanupBuffer(buf_handle: i64) void {
    const ctx = global_ctx orelse return;

    if (ctx.buffer_diagnostics.fetchRemove(buf_handle)) |kv| {
        var buf_diags = kv.value;
        buf_diags.deinit();
        ctx.allocator.destroy(buf_diags);
    }
}
