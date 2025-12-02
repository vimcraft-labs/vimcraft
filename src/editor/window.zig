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
    /// Minimum width for line number column (Neovim's numberwidth)
    /// Default 4 matches Neovim. Valid range: 1-20
    numberwidth: u8 = 4,
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
    /// How to display concealed text (0=show, 1=replace, 2=hide, 3=completely hide)
    conceallevel: u8 = 0,
    /// Whether to conceal on cursor line (combination of "n", "v", "i", "c")
    concealcursor: ConcealCursor = .{},

    pub const SignColumn = enum { auto, yes, no };

    /// Flags for which modes keep text concealed on cursor line
    pub const ConcealCursor = packed struct {
        n: bool = false, // Normal mode
        v: bool = false, // Visual mode
        i: bool = false, // Insert mode
        c: bool = false, // Command mode

        /// Parse from string like "n", "nv", "nvic"
        pub fn fromString(str: []const u8) ConcealCursor {
            var result = ConcealCursor{};
            for (str) |char| {
                switch (char) {
                    'n' => result.n = true,
                    'v' => result.v = true,
                    'i' => result.i = true,
                    'c' => result.c = true,
                    else => {},
                }
            }
            return result;
        }

        /// Convert to string representation
        pub fn toString(self: ConcealCursor, buf: *[4]u8) []const u8 {
            var i: usize = 0;
            if (self.n) {
                buf[i] = 'n';
                i += 1;
            }
            if (self.v) {
                buf[i] = 'v';
                i += 1;
            }
            if (self.i) {
                buf[i] = 'i';
                i += 1;
            }
            if (self.c) {
                buf[i] = 'c';
                i += 1;
            }
            return buf[0..i];
        }
    };
};

/// Cursor position within a buffer
pub const Cursor = struct {
    row: usize = 0,
    col: usize = 0,
};

/// Floating window anchor position
pub const FloatAnchor = enum {
    /// Top-left of window at (row, col)
    NW,
    /// Top-right of window at (row, col)
    NE,
    /// Bottom-left of window at (row, col)
    SW,
    /// Bottom-right of window at (row, col)
    SE,
};

/// Relative positioning for floating windows
pub const FloatRelative = enum {
    /// Relative to editor grid (screen coordinates)
    editor,
    /// Relative to current window
    win,
    /// Relative to cursor position
    cursor,
    /// Relative to a specific mouse position
    mouse,
};

/// Border style for floating windows
pub const BorderStyle = enum {
    none,
    single,
    double,
    rounded,
    solid,
    shadow,
};

/// Floating window configuration (Neovim-compatible)
/// MEMORY SAFETY: title and footer are OWNED by this struct when title_owned/footer_owned are true.
/// Call deinit() with an allocator to free owned strings.
pub const FloatingConfig = struct {
    /// Relative positioning mode
    relative: FloatRelative = .editor,
    /// Reference window (when relative="win")
    win: ?WindowId = null,
    /// Anchor corner of floating window
    anchor: FloatAnchor = .NW,
    /// Width in columns (required)
    width: usize = 1,
    /// Height in rows (required)
    height: usize = 1,
    /// Row position (depends on relative mode)
    row: i32 = 0,
    /// Column position (depends on relative mode)
    col: i32 = 0,
    /// Whether window can receive focus
    focusable: bool = true,
    /// Z-index for stacking order (higher = on top)
    zindex: u32 = 50,
    /// Window style/appearance
    style: Style = .minimal,
    /// Border configuration
    border: BorderStyle = .none,
    /// Title text (displayed in border if border is set)
    /// OWNED when title_owned is true - must be freed in deinit()
    title: ?[]const u8 = null,
    /// Whether title string is owned (allocated) by this config
    title_owned: bool = false,
    /// Title position: "left", "center", "right"
    title_pos: TitlePos = .left,
    /// Footer text (displayed in border if border is set)
    /// OWNED when footer_owned is true - must be freed in deinit()
    footer: ?[]const u8 = null,
    /// Whether footer string is owned (allocated) by this config
    footer_owned: bool = false,
    /// Footer position: "left", "center", "right"
    footer_pos: TitlePos = .left,
    /// Don't add to jump list
    noautocmd: bool = false,
    /// Buffer to show when external window (for nvim-specific, ignored in Vimcraft)
    external: bool = false,
    /// Hide the window without destroying it
    hide: bool = false,

    pub const Style = enum {
        /// No UI chrome (no line numbers, etc.)
        minimal,
    };

    pub const TitlePos = enum {
        left,
        center,
        right,
    };

    /// Free owned strings. Must be called when destroying a floating window.
    pub fn deinit(self: *FloatingConfig, allocator: std.mem.Allocator) void {
        if (self.title_owned) {
            if (self.title) |title| {
                allocator.free(title);
            }
            self.title = null;
            self.title_owned = false;
        }
        if (self.footer_owned) {
            if (self.footer) |footer| {
                allocator.free(footer);
            }
            self.footer = null;
            self.footer_owned = false;
        }
    }

    /// Create a deep copy of this config, duplicating owned strings
    pub fn clone(self: FloatingConfig, allocator: std.mem.Allocator) !FloatingConfig {
        var copy = self;
        // Deep copy title if present
        if (self.title) |title| {
            copy.title = try allocator.dupe(u8, title);
            copy.title_owned = true;
        }
        // Deep copy footer if present
        if (self.footer) |footer| {
            copy.footer = try allocator.dupe(u8, footer);
            copy.footer_owned = true;
        }
        return copy;
    }
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

    /// Floating window configuration (null = normal window)
    floating_config: ?FloatingConfig = null,

    /// Check if this is a floating window
    pub fn isFloating(self: *const Window) bool {
        return self.floating_config != null;
    }

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

    /// Create a floating window
    pub fn initFloating(allocator: std.mem.Allocator, id: WindowId, buffer_id: BufferId, config: FloatingConfig) Window {
        var win = init(allocator, id, buffer_id);
        win.floating_config = config;
        win.width = config.width;
        win.height = config.height;
        // Floating windows typically have minimal UI
        win.options.number = false;
        win.options.relativenumber = false;
        win.options.signcolumn = .no;
        return win;
    }

    pub fn deinit(self: *Window) void {
        // Clean up floating window config (owns title/footer strings)
        if (self.floating_config) |*config| {
            config.deinit(self.allocator);
        }

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
