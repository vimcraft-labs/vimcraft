# Window Splits Design Document

**Status**: Design Phase
**Target**: Phase 5-6
**Author**: Claude Code
**Date**: 2025-01-23

## Overview

This document describes the architecture for implementing Neovim-compatible window splits in Vimcraft. Window splits allow users to view multiple buffers (or the same buffer at different positions) simultaneously in a single terminal.

## Goals

1. **Neovim API Compatibility** - `vim.api.win*` functions work correctly with splits
2. **Efficient Rendering** - Only re-render windows that changed
3. **Flexible Layout** - Support arbitrary horizontal/vertical split combinations
4. **Plugin Support** - Plugins can create, manipulate, and query windows

## Non-Goals (Phase 5-6)

- Floating windows (Phase 7+)
- Tabs/tabpages (Phase 7+)
- Window-local statuslines with custom content (basic statusline only)

---

## Architecture

### 1. Data Structures

#### 1.1 Window

```zig
// src/editor/window.zig

pub const WindowId = struct {
    id: u32,

    pub fn eql(self: WindowId, other: WindowId) bool {
        return self.id == other.id;
    }
};

pub const Viewport = struct {
    /// First visible line (0-indexed)
    top_line: usize,
    /// First visible column (for horizontal scroll)
    left_col: usize,
    /// Cursor position relative to viewport (for rendering)
    cursor_screen_row: usize,
    cursor_screen_col: usize,
};

pub const WindowOptions = struct {
    /// Window-local options (w:)
    number: bool = true,
    relativenumber: bool = false,
    wrap: bool = true,
    cursorline: bool = false,
    cursorcolumn: bool = false,
    signcolumn: enum { auto, yes, no } = .auto,
    foldcolumn: u8 = 0,
    scrolloff: u8 = 0,
    sidescrolloff: u8 = 0,
};

pub const Window = struct {
    id: WindowId,

    /// Buffer displayed in this window
    buffer_id: BufferId,

    /// Cursor position (buffer coordinates, 0-indexed)
    cursor: Cursor,

    /// Viewport (scroll position)
    viewport: Viewport,

    /// Screen position and size (set by layout manager)
    screen_row: usize,
    screen_col: usize,
    height: usize,  // excluding statusline
    width: usize,

    /// Window-local options
    options: WindowOptions,

    /// Window-local variables (w:)
    variables: std.StringHashMap(*c.OVHermesValue),

    /// Dirty flag for rendering
    needs_redraw: bool = true,

    /// Allocator for variables
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: WindowId, buffer_id: BufferId) Window {
        return .{
            .id = id,
            .buffer_id = buffer_id,
            .cursor = .{ .row = 0, .col = 0 },
            .viewport = .{ .top_line = 0, .left_col = 0, .cursor_screen_row = 0, .cursor_screen_col = 0 },
            .screen_row = 0,
            .screen_col = 0,
            .height = 0,
            .width = 0,
            .options = .{},
            .variables = std.StringHashMap(*c.OVHermesValue).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Window) void {
        var it = self.variables.iterator();
        while (it.next()) |entry| {
            c.hermes_value_destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.variables.deinit();
    }

    /// Ensure cursor is visible in viewport, scrolling if necessary
    pub fn ensureCursorVisible(self: *Window) void {
        const scrolloff = self.options.scrolloff;

        // Vertical scrolling
        if (self.cursor.row < self.viewport.top_line + scrolloff) {
            self.viewport.top_line = if (self.cursor.row > scrolloff)
                self.cursor.row - scrolloff else 0;
        } else if (self.cursor.row >= self.viewport.top_line + self.height - scrolloff) {
            self.viewport.top_line = self.cursor.row - self.height + scrolloff + 1;
        }

        // Update cursor screen position
        self.viewport.cursor_screen_row = self.cursor.row - self.viewport.top_line;
        self.viewport.cursor_screen_col = self.cursor.col - self.viewport.left_col;
    }
};
```

#### 1.2 Window Layout Tree

The layout is represented as a binary tree where:
- **Leaf nodes** contain a WindowId
- **Internal nodes** represent splits (horizontal or vertical)

```zig
// src/editor/window_layout.zig

pub const SplitDirection = enum {
    horizontal,  // top/bottom split (━━━)
    vertical,    // left/right split (┃)
};

pub const LayoutNode = union(enum) {
    /// Leaf node - contains a window
    window: WindowId,

    /// Split node - contains two children
    split: struct {
        direction: SplitDirection,
        /// Ratio of first child (0.0 - 1.0)
        ratio: f32,
        first: *LayoutNode,
        second: *LayoutNode,
    },

    pub fn deinit(self: *LayoutNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .window => {},
            .split => |s| {
                s.first.deinit(allocator);
                s.second.deinit(allocator);
                allocator.destroy(s.first);
                allocator.destroy(s.second);
            },
        }
    }

    /// Find the node containing a specific window
    pub fn findWindow(self: *LayoutNode, win_id: WindowId) ?*LayoutNode {
        switch (self.*) {
            .window => |id| return if (id.eql(win_id)) self else null,
            .split => |s| {
                if (s.first.findWindow(win_id)) |node| return node;
                return s.second.findWindow(win_id);
            },
        }
    }

    /// Get all window IDs in this subtree (in order)
    pub fn getWindowIds(self: *LayoutNode, result: *std.ArrayList(WindowId)) !void {
        switch (self.*) {
            .window => |id| try result.append(id),
            .split => |s| {
                try s.first.getWindowIds(result);
                try s.second.getWindowIds(result);
            },
        }
    }
};

pub const WindowLayout = struct {
    root: *LayoutNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, initial_window: WindowId) !WindowLayout {
        const root = try allocator.create(LayoutNode);
        root.* = .{ .window = initial_window };
        return .{
            .root = root,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WindowLayout) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
    }

    /// Split a window, returning the new window's position in the tree
    pub fn split(
        self: *WindowLayout,
        target_win: WindowId,
        new_win: WindowId,
        direction: SplitDirection,
        before: bool,  // true = new window goes first (left/top)
    ) !void {
        const node = self.root.findWindow(target_win) orelse return error.WindowNotFound;

        // Create new leaf for the new window
        const new_leaf = try self.allocator.create(LayoutNode);
        new_leaf.* = .{ .window = new_win };

        // Create new leaf for the existing window (we'll replace the current node)
        const existing_leaf = try self.allocator.create(LayoutNode);
        existing_leaf.* = .{ .window = target_win };

        // Replace current node with split
        node.* = .{
            .split = .{
                .direction = direction,
                .ratio = 0.5,
                .first = if (before) new_leaf else existing_leaf,
                .second = if (before) existing_leaf else new_leaf,
            },
        };
    }

    /// Remove a window from the layout
    /// Returns the WindowId that should become active, or null if this was the last window
    pub fn removeWindow(self: *WindowLayout, win_id: WindowId) !?WindowId {
        return self.removeWindowRecursive(self.root, null, win_id);
    }

    fn removeWindowRecursive(
        self: *WindowLayout,
        node: *LayoutNode,
        parent: ?*LayoutNode,
        win_id: WindowId,
    ) !?WindowId {
        switch (node.*) {
            .window => |id| {
                if (!id.eql(win_id)) return null;

                // This is the window to remove
                if (parent == null) {
                    // This is the root and only window
                    return null;
                }

                // Parent must be a split - replace parent with sibling
                // (handled by caller)
                return null;
            },
            .split => |*s| {
                // Check first child
                if (s.first.* == .window and s.first.window.eql(win_id)) {
                    // Replace this split node with second child
                    const second = s.second;
                    self.allocator.destroy(s.first);
                    node.* = second.*;
                    self.allocator.destroy(second);

                    // Return a window from the remaining subtree
                    var ids = std.ArrayList(WindowId).init(self.allocator);
                    defer ids.deinit();
                    try node.getWindowIds(&ids);
                    return if (ids.items.len > 0) ids.items[0] else null;
                }

                // Check second child
                if (s.second.* == .window and s.second.window.eql(win_id)) {
                    // Replace this split node with first child
                    const first = s.first;
                    self.allocator.destroy(s.second);
                    node.* = first.*;
                    self.allocator.destroy(first);

                    // Return a window from the remaining subtree
                    var ids = std.ArrayList(WindowId).init(self.allocator);
                    defer ids.deinit();
                    try node.getWindowIds(&ids);
                    return if (ids.items.len > 0) ids.items[0] else null;
                }

                // Recurse into children
                if (try self.removeWindowRecursive(s.first, node, win_id)) |new_active| {
                    return new_active;
                }
                return self.removeWindowRecursive(s.second, node, win_id);
            },
        }
    }

    /// Calculate screen positions and sizes for all windows
    pub fn calculateLayout(
        self: *WindowLayout,
        windows: *std.AutoHashMap(WindowId, *Window),
        total_rows: usize,
        total_cols: usize,
    ) void {
        self.calculateLayoutRecursive(self.root, windows, 0, 0, total_rows, total_cols);
    }

    fn calculateLayoutRecursive(
        self: *WindowLayout,
        node: *LayoutNode,
        windows: *std.AutoHashMap(WindowId, *Window),
        row: usize,
        col: usize,
        height: usize,
        width: usize,
    ) void {
        switch (node.*) {
            .window => |id| {
                if (windows.getPtr(id)) |win| {
                    win.screen_row = row;
                    win.screen_col = col;
                    win.height = height - 1;  // Reserve 1 row for statusline
                    win.width = width;
                    win.needs_redraw = true;
                }
            },
            .split => |s| {
                switch (s.direction) {
                    .horizontal => {
                        const first_height = @as(usize, @intFromFloat(@as(f32, @floatFromInt(height)) * s.ratio));
                        const second_height = height - first_height;

                        self.calculateLayoutRecursive(s.first, windows, row, col, first_height, width);
                        self.calculateLayoutRecursive(s.second, windows, row + first_height, col, second_height, width);
                    },
                    .vertical => {
                        const first_width = @as(usize, @intFromFloat(@as(f32, @floatFromInt(width)) * s.ratio));
                        const second_width = width - first_width - 1;  // -1 for separator

                        self.calculateLayoutRecursive(s.first, windows, row, col, height, first_width);
                        self.calculateLayoutRecursive(s.second, windows, row, col + first_width + 1, height, second_width);
                    },
                }
            },
        }
    }
};
```

#### 1.3 Editor Window Management

```zig
// src/editor/editor.zig (additions)

pub const Editor = struct {
    // Existing fields
    buffers: std.AutoHashMap(BufferId, Buffer),
    current_buffer_id: ?BufferId,

    // NEW: Window management
    windows: std.AutoHashMap(WindowId, Window),
    current_window_id: ?WindowId,
    layout: WindowLayout,
    next_window_id: u32,

    pub fn initWithWindow(allocator: std.mem.Allocator) !Editor {
        var editor = Editor{
            .buffers = std.AutoHashMap(BufferId, Buffer).init(allocator),
            .current_buffer_id = null,
            .windows = std.AutoHashMap(WindowId, Window).init(allocator),
            .current_window_id = null,
            .layout = undefined,
            .next_window_id = 1,
            .allocator = allocator,
        };

        // Create initial buffer
        const buf_id = try editor.createBuffer();

        // Create initial window
        const win_id = WindowId{ .id = 0 };
        const window = Window.init(allocator, win_id, buf_id);
        try editor.windows.put(win_id, window);
        editor.current_window_id = win_id;

        // Initialize layout
        editor.layout = try WindowLayout.init(allocator, win_id);

        return editor;
    }

    /// Get current window
    pub fn getCurrentWindow(self: *Editor) ?*Window {
        const win_id = self.current_window_id orelse return null;
        return self.windows.getPtr(win_id);
    }

    /// Get window by ID (0 = current window)
    pub fn getWindow(self: *Editor, handle: i64) ?*Window {
        if (handle == 0) {
            return self.getCurrentWindow();
        } else if (handle > 0) {
            const win_id = WindowId{ .id = @intCast(handle) };
            return self.windows.getPtr(win_id);
        }
        return null;
    }

    /// Split current window horizontally (new window below)
    pub fn splitHorizontal(self: *Editor) !WindowId {
        return self.splitWindow(.horizontal, false);
    }

    /// Split current window vertically (new window to the right)
    pub fn splitVertical(self: *Editor) !WindowId {
        return self.splitWindow(.vertical, false);
    }

    fn splitWindow(self: *Editor, direction: SplitDirection, before: bool) !WindowId {
        const current_win = self.getCurrentWindow() orelse return error.NoCurrentWindow;

        // Create new window ID
        const new_win_id = WindowId{ .id = self.next_window_id };
        self.next_window_id += 1;

        // Create new window showing same buffer
        var new_window = Window.init(self.allocator, new_win_id, current_win.buffer_id);
        new_window.cursor = current_win.cursor;
        new_window.viewport = current_win.viewport;

        try self.windows.put(new_win_id, new_window);

        // Update layout
        try self.layout.split(current_win.id, new_win_id, direction, before);

        // Focus new window
        self.current_window_id = new_win_id;

        return new_win_id;
    }

    /// Close a window
    pub fn closeWindow(self: *Editor, win_id: WindowId, force: bool) !void {
        const window = self.windows.getPtr(win_id) orelse return error.InvalidWindow;

        // Check if buffer is modified (unless force)
        if (!force) {
            if (self.buffers.getPtr(window.buffer_id)) |buffer| {
                if (buffer.modified) {
                    return error.BufferModified;
                }
            }
        }

        // Remove from layout
        const new_active = try self.layout.removeWindow(win_id) orelse {
            // This was the last window - don't close
            return error.CannotCloseLastWindow;
        };

        // Cleanup window
        var win = self.windows.fetchRemove(win_id).?.value;
        win.deinit();

        // Update current window
        self.current_window_id = new_active;
    }

    /// Focus a different window
    pub fn focusWindow(self: *Editor, win_id: WindowId) !void {
        if (!self.windows.contains(win_id)) {
            return error.InvalidWindow;
        }
        self.current_window_id = win_id;

        // Update current buffer to match window's buffer
        if (self.windows.getPtr(win_id)) |window| {
            self.current_buffer_id = window.buffer_id;
        }
    }

    /// Navigate to adjacent window
    pub fn navigateWindow(self: *Editor, direction: enum { left, right, up, down }) !void {
        // TODO: Implement spatial navigation based on layout
        _ = direction;
    }

    /// List all window IDs
    pub fn listWindows(self: *Editor) ![]WindowId {
        var ids = std.ArrayList(WindowId).init(self.allocator);
        try self.layout.root.getWindowIds(&ids);
        return ids.toOwnedSlice();
    }

    /// Recalculate all window positions after terminal resize
    pub fn relayout(self: *Editor, rows: usize, cols: usize) void {
        self.layout.calculateLayout(&self.windows, rows, cols);
    }
};
```

---

### 2. Rendering Architecture

#### 2.1 Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Terminal (80x24)                         │
├─────────────────────────────────┬───────────────────────────┤
│         Window 1 (0,0)          │      Window 2 (0,41)      │
│         Buffer: main.zig        │      Buffer: test.zig     │
│         39 cols x 11 rows       │      39 cols x 11 rows    │
│                                 │                           │
│  1 const std = @import("std"); │  1 test "example" {       │
│  2                              │  2     // test code       │
│  3 pub fn main() void {        │  3 }                       │
│  4     // ...                   │  4                         │
│  5 }                            │  5                         │
│                                 │                           │
│ [main.zig] 1:1  NORMAL         │ [test.zig] 1:1            │
├─────────────────────────────────┼───────────────────────────┤
│         Window 3 (12,0)         │      Window 4 (12,41)     │
│         Buffer: main.zig        │      Buffer: log.txt      │
│         39 cols x 11 rows       │      39 cols x 11 rows    │
│                                 │                           │
│ (same buffer, different view)   │ [2024-01-23] Started...   │
│                                 │ [2024-01-23] Loading...   │
│                                 │                           │
│ [main.zig] 50:10               │ [log.txt] 1:1              │
└─────────────────────────────────┴───────────────────────────┘
                    │ (vertical separator)
```

#### 2.2 Rendering Pipeline

```
Phase 1: Layout Calculation
    Editor.relayout(terminal_rows, terminal_cols)
        └── WindowLayout.calculateLayout()
            └── Set each Window's screen_row, screen_col, height, width

Phase 2: Per-Window Rendering
    For each Window where needs_redraw == true:
        └── WindowRenderer.render(window, buffer)
            ├── Calculate visible lines (viewport.top_line to top_line + height)
            ├── Apply syntax highlighting
            ├── Apply window-local highlights
            ├── Render line numbers (if enabled)
            ├── Render sign column (if enabled)
            ├── Render buffer content (clipped to window bounds)
            ├── Render statusline
            └── Output to window's region of frame buffer

Phase 3: Separator Rendering
    WindowSeparatorRenderer.render(layout)
        └── Draw │ characters for vertical splits
        └── Draw ─ characters for horizontal splits (between statuslines)

Phase 4: Cursor Positioning
    Only in active window:
        └── Calculate screen position from window position + cursor position
        └── Send cursor move escape sequence

Phase 5: Diff & Output
    DiffRenderer.render(old_frame, new_frame)
        └── Only send changed cells to terminal
```

#### 2.3 Window Renderer

```zig
// src/backends/terminal/display/window_renderer.zig

pub const WindowRenderer = struct {
    frame: *FrameBuffer,
    allocator: std.mem.Allocator,

    pub fn render(
        self: *WindowRenderer,
        window: *Window,
        buffer: *Buffer,
        highlights: *HighlightManager,
    ) void {
        const start_row = window.screen_row;
        const start_col = window.screen_col;
        const height = window.height;
        const width = window.width;

        // Calculate content area (excluding line numbers, signs, etc.)
        const gutter_width = self.calculateGutterWidth(window, buffer);
        const content_width = width - gutter_width;
        const content_start_col = start_col + gutter_width;

        // Render each visible line
        var screen_row: usize = 0;
        while (screen_row < height) : (screen_row += 1) {
            const buffer_line = window.viewport.top_line + screen_row;

            // Render gutter (line numbers, signs)
            self.renderGutter(window, buffer, buffer_line, start_row + screen_row, start_col, gutter_width);

            // Render line content
            if (buffer_line < buffer.lineCount()) {
                self.renderLine(window, buffer, buffer_line, start_row + screen_row, content_start_col, content_width, highlights);
            } else {
                // Empty line (~ for vim-style)
                self.renderEmptyLine(start_row + screen_row, content_start_col, content_width);
            }
        }

        // Render statusline
        self.renderStatusline(window, buffer, start_row + height, start_col, width);

        window.needs_redraw = false;
    }

    fn renderLine(
        self: *WindowRenderer,
        window: *Window,
        buffer: *Buffer,
        buffer_line: usize,
        screen_row: usize,
        screen_col: usize,
        width: usize,
        highlights: *HighlightManager,
    ) void {
        const line = buffer.getLine(buffer_line) orelse return;
        defer self.allocator.free(line);

        const start_col = window.viewport.left_col;
        var col: usize = 0;

        // Iterate through visible columns
        while (col < width) : (col += 1) {
            const buffer_col = start_col + col;

            if (buffer_col < line.len and line[buffer_col] != '\n') {
                const char = line[buffer_col];
                const hl = highlights.getHighlight(buffer_line, buffer_col);

                self.frame.setCell(screen_row, screen_col + col, .{
                    .char = char,
                    .fg = hl.fg,
                    .bg = hl.bg,
                    .bold = hl.bold,
                    .italic = hl.italic,
                });
            } else {
                // Past end of line
                self.frame.setCell(screen_row, screen_col + col, .{
                    .char = ' ',
                    .fg = null,
                    .bg = null,
                });
            }
        }

        // Highlight cursor line if enabled
        if (window.options.cursorline and buffer_line == window.cursor.row) {
            self.applyCursorLine(screen_row, screen_col, width);
        }
    }

    fn renderStatusline(
        self: *WindowRenderer,
        window: *Window,
        buffer: *Buffer,
        screen_row: usize,
        screen_col: usize,
        width: usize,
    ) void {
        // Format: [filename] line:col  MODE
        const filename = buffer.filepath orelse "[No Name]";
        const modified = if (buffer.modified) "[+]" else "";

        // Build statusline string
        var status_buf: [256]u8 = undefined;
        const status = std.fmt.bufPrint(&status_buf, " {s}{s} {d}:{d}", .{
            filename,
            modified,
            window.cursor.row + 1,
            window.cursor.col + 1,
        }) catch "[Error]";

        // Render with inverted colors
        var col: usize = 0;
        while (col < width) : (col += 1) {
            const char: u8 = if (col < status.len) status[col] else ' ';
            self.frame.setCell(screen_row, screen_col + col, .{
                .char = char,
                .fg = .{ .r = 0, .g = 0, .b = 0 },
                .bg = .{ .r = 200, .g = 200, .b = 200 },
                .bold = false,
            });
        }
    }

    fn calculateGutterWidth(self: *WindowRenderer, window: *Window, buffer: *Buffer) usize {
        _ = self;
        var width: usize = 0;

        // Sign column
        if (window.options.signcolumn == .yes or
            (window.options.signcolumn == .auto and buffer.hasSigns())) {
            width += 2;
        }

        // Line numbers
        if (window.options.number or window.options.relativenumber) {
            const line_count = buffer.lineCount();
            const digits = std.math.log10(line_count) + 1;
            width += @max(digits, 4) + 1;  // minimum 4 digits + 1 space
        }

        return width;
    }
};
```

#### 2.4 Separator Renderer

```zig
// src/backends/terminal/display/separator_renderer.zig

pub const SeparatorRenderer = struct {
    frame: *FrameBuffer,

    /// Render all window separators
    pub fn render(self: *SeparatorRenderer, layout: *WindowLayout, windows: *std.AutoHashMap(WindowId, *Window)) void {
        self.renderNode(layout.root, windows);
    }

    fn renderNode(self: *SeparatorRenderer, node: *LayoutNode, windows: *std.AutoHashMap(WindowId, *Window)) void {
        switch (node.*) {
            .window => {},
            .split => |s| {
                switch (s.direction) {
                    .vertical => {
                        // Draw vertical separator between first and second
                        // Find the rightmost column of first child
                        const first_bounds = self.getBounds(s.first, windows);
                        const col = first_bounds.col + first_bounds.width;

                        // Draw │ from top to bottom
                        var row = first_bounds.row;
                        while (row < first_bounds.row + first_bounds.height + 1) : (row += 1) {
                            self.frame.setCell(row, col, .{
                                .char = '│',
                                .fg = .{ .r = 100, .g = 100, .b = 100 },
                                .bg = null,
                            });
                        }
                    },
                    .horizontal => {
                        // Horizontal splits use statuslines as separators
                        // No additional rendering needed
                    },
                }

                // Recurse
                self.renderNode(s.first, windows);
                self.renderNode(s.second, windows);
            },
        }
    }

    const Bounds = struct { row: usize, col: usize, height: usize, width: usize };

    fn getBounds(self: *SeparatorRenderer, node: *LayoutNode, windows: *std.AutoHashMap(WindowId, *Window)) Bounds {
        _ = self;
        switch (node.*) {
            .window => |id| {
                if (windows.getPtr(id)) |win| {
                    return .{
                        .row = win.screen_row,
                        .col = win.screen_col,
                        .height = win.height,
                        .width = win.width,
                    };
                }
                return .{ .row = 0, .col = 0, .height = 0, .width = 0 };
            },
            .split => |s| {
                const first = self.getBounds(s.first, windows);
                const second = self.getBounds(s.second, windows);
                return .{
                    .row = @min(first.row, second.row),
                    .col = @min(first.col, second.col),
                    .height = @max(first.row + first.height, second.row + second.height) - @min(first.row, second.row),
                    .width = @max(first.col + first.width, second.col + second.width) - @min(first.col, second.col),
                };
            },
        }
    }
};
```

---

### 3. API Implementation

#### 3.1 Updated Window API

```zig
// src/system/jsi/api_window.zig (updates)

/// vim.api.getCurrentWin() -> Window
pub export fn apiGetCurrentWin(...) ?*c.OVHermesValue {
    const editor = getEditor() orelse return null;
    const win_id = editor.current_window_id orelse return c.hermes_value_create_number(rt, 0);
    return c.hermes_value_create_number(rt, @floatFromInt(win_id.id));
}

/// vim.api.setCurrentWin(win) -> void
pub export fn apiSetCurrentWin(...) ?*c.OVHermesValue {
    const editor = getEditor() orelse return null;
    const win_id = WindowId{ .id = @intCast(handle) };
    editor.focusWindow(win_id) catch {
        // Invalid window - silently fail (Neovim behavior)
    };
    return c.hermes_value_create_undefined(rt);
}

/// vim.api.listWins() -> Window[]
pub export fn apiListWins(...) ?*c.OVHermesValue {
    const editor = getEditor() orelse return null;
    const win_ids = editor.listWindows() catch return c.hermes_array_create(rt, 0);
    defer editor.allocator.free(win_ids);

    const arr = c.hermes_array_create(rt, win_ids.len) orelse return null;
    for (win_ids, 0..) |win_id, i| {
        const num = c.hermes_value_create_number(rt, @floatFromInt(win_id.id));
        if (num) |n| {
            c.hermes_array_set(rt, arr, i, n);
            c.hermes_value_destroy(n);
        }
    }
    return arr;
}

/// vim.api.winClose(win, force) -> void
pub export fn apiWinClose(...) ?*c.OVHermesValue {
    const editor = getEditor() orelse return null;
    const win_id = if (handle == 0)
        editor.current_window_id orelse return c.hermes_value_create_undefined(rt)
    else
        WindowId{ .id = @intCast(handle) };

    editor.closeWindow(win_id, force) catch |err| switch (err) {
        error.CannotCloseLastWindow => {},  // Silently fail
        error.BufferModified => {},  // Silently fail (should throw in strict mode)
        else => {},
    };

    return c.hermes_value_create_undefined(rt);
}

/// vim.api.winSetHeight(win, height) -> void
pub export fn apiWinSetHeight(...) ?*c.OVHermesValue {
    const editor = getEditor() orelse return null;
    const win_id = if (handle == 0)
        editor.current_window_id orelse return c.hermes_value_create_undefined(rt)
    else
        WindowId{ .id = @intCast(handle) };

    // Update split ratio to achieve desired height
    editor.setWindowHeight(win_id, height) catch {};

    return c.hermes_value_create_undefined(rt);
}
```

#### 3.2 New Split Commands

```zig
// src/commands/window_commands.zig

pub fn registerWindowCommands(commands: *CommandRegistry) void {
    commands.register("split", "sp", cmdSplit);
    commands.register("vsplit", "vs", cmdVsplit);
    commands.register("close", "clo", cmdClose);
    commands.register("only", "on", cmdOnly);
    commands.register("wincmd", "winc", cmdWincmd);
}

fn cmdSplit(editor: *Editor, args: []const u8) !void {
    _ = args;
    _ = try editor.splitHorizontal();
    // TODO: If args contains filename, open that file in new window
}

fn cmdVsplit(editor: *Editor, args: []const u8) !void {
    _ = args;
    _ = try editor.splitVertical();
}

fn cmdClose(editor: *Editor, args: []const u8) !void {
    const force = std.mem.indexOf(u8, args, "!") != null;
    const win_id = editor.current_window_id orelse return;
    editor.closeWindow(win_id, force) catch |err| switch (err) {
        error.CannotCloseLastWindow => {
            editor.showError("E444: Cannot close last window");
        },
        error.BufferModified => {
            editor.showError("E37: No write since last change (add ! to override)");
        },
        else => {},
    };
}

fn cmdOnly(editor: *Editor, args: []const u8) !void {
    const force = std.mem.indexOf(u8, args, "!") != null;

    // Close all windows except current
    const current = editor.current_window_id orelse return;
    const all_windows = try editor.listWindows();
    defer editor.allocator.free(all_windows);

    for (all_windows) |win_id| {
        if (!win_id.eql(current)) {
            editor.closeWindow(win_id, force) catch continue;
        }
    }
}
```

#### 3.3 Window Navigation Keybindings

```zig
// src/keymap/window_keys.zig

pub fn registerWindowKeys(keymap: *KeymapManager) void {
    // Ctrl+W prefix for window commands
    keymap.registerPrefix("n", "<C-w>");

    // Navigation
    keymap.register("n", "<C-w>h", windowLeft);
    keymap.register("n", "<C-w>j", windowDown);
    keymap.register("n", "<C-w>k", windowUp);
    keymap.register("n", "<C-w>l", windowRight);
    keymap.register("n", "<C-w><C-h>", windowLeft);
    keymap.register("n", "<C-w><C-j>", windowDown);
    keymap.register("n", "<C-w><C-k>", windowUp);
    keymap.register("n", "<C-w><C-l>", windowRight);
    keymap.register("n", "<C-w>w", windowNext);
    keymap.register("n", "<C-w><C-w>", windowNext);
    keymap.register("n", "<C-w>p", windowPrevious);

    // Splitting
    keymap.register("n", "<C-w>s", splitHorizontal);
    keymap.register("n", "<C-w><C-s>", splitHorizontal);
    keymap.register("n", "<C-w>v", splitVertical);
    keymap.register("n", "<C-w><C-v>", splitVertical);
    keymap.register("n", "<C-w>n", newWindow);

    // Closing
    keymap.register("n", "<C-w>c", closeWindow);
    keymap.register("n", "<C-w>q", closeWindow);
    keymap.register("n", "<C-w>o", onlyWindow);
    keymap.register("n", "<C-w><C-o>", onlyWindow);

    // Resizing
    keymap.register("n", "<C-w>=", equalizeWindows);
    keymap.register("n", "<C-w>_", maximizeHeight);
    keymap.register("n", "<C-w>|", maximizeWidth);
    keymap.register("n", "<C-w>+", increaseHeight);
    keymap.register("n", "<C-w>-", decreaseHeight);
    keymap.register("n", "<C-w>>", increaseWidth);
    keymap.register("n", "<C-w><", decreaseWidth);

    // Moving windows
    keymap.register("n", "<C-w>H", moveWindowLeft);
    keymap.register("n", "<C-w>J", moveWindowDown);
    keymap.register("n", "<C-w>K", moveWindowUp);
    keymap.register("n", "<C-w>L", moveWindowRight);
    keymap.register("n", "<C-w>r", rotateWindowsDown);
    keymap.register("n", "<C-w>R", rotateWindowsUp);
    keymap.register("n", "<C-w>x", exchangeWindows);
}
```

---

### 4. Testing Strategy

#### 4.1 Unit Tests

```zig
// tests/unit/window_layout_test.zig

test "initial layout has single window" {
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    var ids = std.ArrayList(WindowId).init(allocator);
    defer ids.deinit();
    try layout.root.getWindowIds(&ids);

    try std.testing.expectEqual(@as(usize, 1), ids.items.len);
    try std.testing.expectEqual(@as(u32, 0), ids.items[0].id);
}

test "horizontal split creates two windows" {
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .horizontal, false);

    var ids = std.ArrayList(WindowId).init(allocator);
    defer ids.deinit();
    try layout.root.getWindowIds(&ids);

    try std.testing.expectEqual(@as(usize, 2), ids.items.len);
}

test "layout calculation distributes space correctly" {
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
    defer windows.deinit();

    var win0 = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 0 });
    var win1 = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 0 });
    try windows.put(WindowId{ .id = 0 }, &win0);
    try windows.put(WindowId{ .id = 1 }, &win1);

    layout.calculateLayout(&windows, 24, 80);

    // Window 0 should be left half (minus separator)
    try std.testing.expectEqual(@as(usize, 0), win0.screen_col);
    try std.testing.expectEqual(@as(usize, 39), win0.width);

    // Window 1 should be right half
    try std.testing.expectEqual(@as(usize, 40), win1.screen_col);
    try std.testing.expectEqual(@as(usize, 40), win1.width);
}
```

#### 4.2 E2E Tests

```typescript
// tests/e2e/window-splits/e2e.ts

vim.e2e.describe("Window Splits", function() {
    vim.e2e.test("vsplit creates new window", function() {
        const before = vim.api.listWins();
        vim.e2e.assert.equal(before.length, 1);

        vim.cmd("vsplit");

        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, 2);
    });

    vim.e2e.test("split shares buffer by default", function() {
        vim.cmd("vsplit");

        const wins = vim.api.listWins();
        const buf1 = vim.api.winGetBuf(wins[0]);
        const buf2 = vim.api.winGetBuf(wins[1]);

        vim.e2e.assert.equal(buf1, buf2);
    });

    vim.e2e.test("Ctrl+W h navigates left", function() {
        vim.cmd("vsplit");

        // Focus is on new (right) window
        const rightWin = vim.api.getCurrentWin();

        vim.e2e.keys("<C-w>h");

        const currentWin = vim.api.getCurrentWin();
        vim.e2e.assert.notEqual(currentWin, rightWin);
    });

    vim.e2e.test("close removes window from list", function() {
        vim.cmd("vsplit");
        vim.e2e.assert.equal(vim.api.listWins().length, 2);

        vim.cmd("close");
        vim.e2e.assert.equal(vim.api.listWins().length, 1);
    });

    vim.e2e.test("cannot close last window", function() {
        vim.e2e.assert.equal(vim.api.listWins().length, 1);

        vim.cmd("close");  // Should show error, not close

        vim.e2e.assert.equal(vim.api.listWins().length, 1);
    });

    vim.e2e.test("winSetHeight affects window size", function() {
        vim.cmd("split");

        const win = vim.api.getCurrentWin();
        const before = vim.api.winGetHeight(win);

        vim.api.winSetHeight(win, before + 5);

        const after = vim.api.winGetHeight(win);
        vim.e2e.assert.true(after > before);
    });
});
```

---

### 5. Implementation Phases

#### Phase 5.1: Foundation (Week 1-2)
- [ ] Create `Window` and `WindowId` structs
- [ ] Create `WindowLayout` tree structure
- [ ] Add `windows` HashMap to Editor
- [ ] Implement basic `splitHorizontal` / `splitVertical`
- [ ] Unit tests for layout tree

#### Phase 5.2: Layout Calculation (Week 2-3)
- [ ] Implement `calculateLayout` to set window screen positions
- [ ] Handle terminal resize → relayout all windows
- [ ] Implement `closeWindow` with layout tree updates
- [ ] Unit tests for layout calculation

#### Phase 5.3: Rendering (Week 3-4)
- [ ] Create `WindowRenderer` for per-window rendering
- [ ] Create `SeparatorRenderer` for split lines
- [ ] Modify `Compositor` to handle multiple windows
- [ ] Implement viewport scrolling per window
- [ ] Visual tests for split rendering

#### Phase 5.4: Navigation & Commands (Week 4-5)
- [ ] Implement `:split`, `:vsplit`, `:close`, `:only` commands
- [ ] Implement `Ctrl+W` navigation keybindings
- [ ] Implement window focus tracking
- [ ] E2E tests for commands

#### Phase 5.5: API Completion (Week 5-6)
- [ ] Update all `vim.api.win*` functions for real splits
- [ ] Implement window resizing (`winSetHeight`, `winSetWidth`)
- [ ] Window-local options (`winGetOption`, `winSetOption`)
- [ ] E2E tests for API functions

#### Phase 5.6: Polish (Week 6)
- [ ] Performance optimization (only redraw changed windows)
- [ ] Edge cases (very small windows, many splits)
- [ ] Documentation
- [ ] Integration with existing features (syntax highlighting, virtual text)

---

### 6. Open Questions

1. **Statusline per window or global?**
   - Neovim: Each window has its own statusline
   - Recommendation: Per-window statusline (Phase 5.3)

2. **Window-local virtual text?**
   - Virtual text is buffer-level in Neovim
   - Recommendation: Keep buffer-level, render in all windows showing that buffer

3. **Floating windows?**
   - Much more complex (z-ordering, transparency, borders)
   - Recommendation: Defer to Phase 7+

4. **Maximum number of windows?**
   - Neovim has no hard limit
   - Recommendation: Soft limit based on minimum window size (e.g., 3 rows x 10 cols)

5. **Split direction preference?**
   - `splitbelow` / `splitright` options
   - Recommendation: Implement as part of Phase 5.4

---

### 7. References

- [Neovim Window API](https://neovim.io/doc/user/api.html#api-window)
- [Neovim window.c](https://github.com/neovim/neovim/blob/master/src/nvim/window.c)
- [Helix View](https://github.com/helix-editor/helix/blob/master/helix-view/src/view.rs)
- [Helix Tree](https://github.com/helix-editor/helix/blob/master/helix-view/src/tree.rs)
