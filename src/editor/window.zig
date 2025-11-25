const std = @import("std");
const c_api = @import("../system/jsi/c_api.zig");
const c = c_api.c;

/// Buffer identifier - must match editor.BufferId exactly
/// (cannot import editor.zig due to circular dependency)
pub const BufferId = struct {
    id: u64,

    pub fn eql(self: BufferId, other: BufferId) bool {
        return self.id == other.id;
    }
};

/// Window identifier (Neovim-compatible)
/// Handle 0 = "current window" (resolved at API call time)
/// Positive handles = WindowId.id
pub const WindowId = struct {
    id: u32,

    pub fn eql(self: WindowId, other: WindowId) bool {
        return self.id == other.id;
    }

    /// Format for debugging
    pub fn format(
        self: WindowId,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("WindowId({})", .{self.id});
    }
};

/// Viewport state for scrolling
pub const Viewport = struct {
    /// First visible line (0-indexed)
    top_line: usize = 0,
    /// First visible column (for horizontal scroll)
    left_col: usize = 0,
    /// Cursor position relative to viewport (for rendering)
    cursor_screen_row: usize = 0,
    cursor_screen_col: usize = 0,
};

/// Window-local options (w:)
pub const WindowOptions = struct {
    /// Show line numbers
    number: bool = true,
    /// Show relative line numbers
    relativenumber: bool = false,
    /// Wrap long lines
    wrap: bool = true,
    /// Highlight current line
    cursorline: bool = false,
    /// Highlight current column
    cursorcolumn: bool = false,
    /// Sign column display mode
    signcolumn: SignColumn = .auto,
    /// Fold column width
    foldcolumn: u8 = 0,
    /// Minimum lines above/below cursor
    scrolloff: u8 = 0,
    /// Minimum columns left/right of cursor
    sidescrolloff: u8 = 0,

    pub const SignColumn = enum { auto, yes, no };
};

/// Cursor position within a buffer
pub const Cursor = struct {
    row: usize = 0,
    col: usize = 0,
};

/// A window displays a buffer at a specific viewport position
pub const Window = struct {
    id: WindowId,

    /// Buffer displayed in this window
    buffer_id: BufferId,

    /// Cursor position (buffer coordinates, 0-indexed)
    cursor: Cursor,

    /// Viewport (scroll position)
    viewport: Viewport,

    /// Screen position and size (set by layout manager)
    screen_row: usize = 0,
    screen_col: usize = 0,
    height: usize = 0, // excluding statusline
    width: usize = 0,

    /// Window-local options
    options: WindowOptions,

    /// Window-local variables (w:)
    variables: std.StringHashMap(*c.OVHermesValue),

    /// Dirty flag for rendering (true = needs redraw)
    needs_redraw: bool = true,

    /// Allocator for variables
    allocator: std.mem.Allocator,

    /// Hermes runtime for variable management
    runtime: ?*c.OVHermesRuntime = null,

    pub fn init(allocator: std.mem.Allocator, id: WindowId, buffer_id: BufferId) Window {
        return .{
            .id = id,
            .buffer_id = buffer_id,
            .cursor = .{},
            .viewport = .{},
            .options = .{},
            .variables = std.StringHashMap(*c.OVHermesValue).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Window) void {
        // Clean up window variables
        var it = self.variables.iterator();
        while (it.next()) |entry| {
            c.hermes_value_destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.variables.deinit();
    }

    /// Set the Hermes runtime (called when JSI is initialized)
    pub fn setRuntime(self: *Window, runtime: *c.OVHermesRuntime) void {
        self.runtime = runtime;
    }

    /// Ensure cursor is visible in viewport, scrolling if necessary
    pub fn ensureCursorVisible(self: *Window) void {
        const scrolloff = self.options.scrolloff;

        // Vertical scrolling
        if (self.height > 0) {
            if (self.cursor.row < self.viewport.top_line + scrolloff) {
                self.viewport.top_line = if (self.cursor.row > scrolloff)
                    self.cursor.row - scrolloff
                else
                    0;
            } else if (self.cursor.row >= self.viewport.top_line + self.height - scrolloff) {
                self.viewport.top_line = self.cursor.row -| (self.height -| scrolloff -| 1);
            }
        }

        // Horizontal scrolling (if wrap is disabled)
        if (!self.options.wrap and self.width > 0) {
            const sidescrolloff = self.options.sidescrolloff;
            if (self.cursor.col < self.viewport.left_col + sidescrolloff) {
                self.viewport.left_col = if (self.cursor.col > sidescrolloff)
                    self.cursor.col - sidescrolloff
                else
                    0;
            } else if (self.cursor.col >= self.viewport.left_col + self.width - sidescrolloff) {
                self.viewport.left_col = self.cursor.col -| (self.width -| sidescrolloff -| 1);
            }
        }

        // Update cursor screen position
        self.viewport.cursor_screen_row = self.cursor.row -| self.viewport.top_line;
        self.viewport.cursor_screen_col = self.cursor.col -| self.viewport.left_col;
    }

    /// Mark window as needing redraw
    pub fn markDirty(self: *Window) void {
        self.needs_redraw = true;
    }

    /// Get window variable
    pub fn getVar(self: *Window, name: []const u8) ?*c.OVHermesValue {
        return self.variables.get(name);
    }

    /// Set window variable
    pub fn setVar(self: *Window, name: []const u8, value: *c.OVHermesValue) !void {
        const rt = self.runtime orelse return error.NoRuntime;

        // Clone the value for storage
        const cloned = c.hermes_value_clone(rt, value) orelse return error.CloneFailed;

        // Check if key exists
        if (self.variables.getPtr(name)) |existing| {
            // Destroy old value
            c.hermes_value_destroy(existing.*);
            existing.* = cloned;
        } else {
            // Allocate new key
            const owned_key = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(owned_key);
            try self.variables.put(owned_key, cloned);
        }
    }

    /// Delete window variable
    pub fn delVar(self: *Window, name: []const u8) void {
        if (self.variables.fetchRemove(name)) |kv| {
            _ = self.runtime; // Runtime not needed for destroy
            c.hermes_value_destroy(kv.value);
            self.allocator.free(kv.key);
        }
    }
};

// Tests
test "WindowId equality" {
    const a = WindowId{ .id = 1 };
    const b = WindowId{ .id = 1 };
    const c_id = WindowId{ .id = 2 };

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c_id));
}

test "Window init and deinit" {
    const allocator = std.testing.allocator;
    const win_id = WindowId{ .id = 0 };
    const buf_id = BufferId{ .id = 1 };

    var window = Window.init(allocator, win_id, buf_id);
    defer window.deinit();

    try std.testing.expectEqual(win_id.id, window.id.id);
    try std.testing.expectEqual(buf_id.id, window.buffer_id.id);
    try std.testing.expectEqual(@as(usize, 0), window.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), window.cursor.col);
}

test "Window ensureCursorVisible scrolls down" {
    const allocator = std.testing.allocator;
    var window = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 1 });
    defer window.deinit();

    window.height = 10;
    window.width = 80;
    window.cursor.row = 15;
    window.options.scrolloff = 2;

    window.ensureCursorVisible();

    // Cursor at row 15, height 10, scrolloff 2
    // top_line should be adjusted so cursor is visible with scrolloff
    try std.testing.expect(window.viewport.top_line > 0);
    try std.testing.expect(window.cursor.row >= window.viewport.top_line);
    try std.testing.expect(window.cursor.row < window.viewport.top_line + window.height);
}

test "Window ensureCursorVisible scrolls up" {
    const allocator = std.testing.allocator;
    var window = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 1 });
    defer window.deinit();

    window.height = 10;
    window.width = 80;
    window.viewport.top_line = 20;
    window.cursor.row = 5;
    window.options.scrolloff = 2;

    window.ensureCursorVisible();

    // Cursor at row 5 but viewport started at 20, should scroll up
    try std.testing.expect(window.viewport.top_line <= window.cursor.row);
}
