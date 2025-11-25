const std = @import("std");
const Window = @import("window.zig").Window;
const WindowId = @import("window.zig").WindowId;

/// Split direction
pub const SplitDirection = enum {
    /// Top/bottom split (horizontal line separator)
    horizontal,
    /// Left/right split (vertical line separator)
    vertical,
};

/// Navigation direction for window switching
pub const NavigationDirection = enum {
    left,
    right,
    up,
    down,
};

/// Layout node in the window tree
/// Leaf nodes contain a WindowId, internal nodes represent splits
pub const LayoutNode = union(enum) {
    /// Leaf node - contains a window
    window: WindowId,

    /// Split node - contains two children
    split: Split,

    pub const Split = struct {
        direction: SplitDirection,
        /// Ratio of first child (0.0 - 1.0), default 0.5 (equal split)
        ratio: f32 = 0.5,
        first: *LayoutNode,
        second: *LayoutNode,
    };

    /// Recursively free this node and its children
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

    /// Find the parent of a node containing a specific window
    /// Returns (parent_node, is_first_child) or null if not found or is root
    pub fn findParent(self: *LayoutNode, win_id: WindowId) ?struct { parent: *LayoutNode, is_first: bool } {
        switch (self.*) {
            .window => return null,
            .split => |s| {
                // Check if either child is the target
                if (s.first.* == .window and s.first.window.eql(win_id)) {
                    return .{ .parent = self, .is_first = true };
                }
                if (s.second.* == .window and s.second.window.eql(win_id)) {
                    return .{ .parent = self, .is_first = false };
                }
                // Recurse into children
                if (s.first.findParent(win_id)) |result| return result;
                return s.second.findParent(win_id);
            },
        }
    }

    /// Get all window IDs in this subtree (in order: left-to-right, top-to-bottom)
    pub fn getWindowIds(self: *LayoutNode, allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(WindowId)) !void {
        switch (self.*) {
            .window => |id| try result.append(allocator, id),
            .split => |s| {
                try s.first.getWindowIds(allocator, result);
                try s.second.getWindowIds(allocator, result);
            },
        }
    }

    /// Count total windows in this subtree
    pub fn countWindows(self: *LayoutNode) usize {
        switch (self.*) {
            .window => return 1,
            .split => |s| return s.first.countWindows() + s.second.countWindows(),
        }
    }

    /// Check if this node contains a specific window
    pub fn containsWindow(self: *LayoutNode, win_id: WindowId) bool {
        return self.findWindow(win_id) != null;
    }
};

/// Window layout manager
/// Manages the binary tree structure of window splits
pub const WindowLayout = struct {
    root: *LayoutNode,
    allocator: std.mem.Allocator,

    /// Initialize with a single window
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

    /// Split a window, creating a new window in the specified direction
    /// @param target_win The window to split
    /// @param new_win The new window to create
    /// @param direction Horizontal (top/bottom) or vertical (left/right)
    /// @param before If true, new window goes first (left/top); if false, second (right/bottom)
    pub fn split(
        self: *WindowLayout,
        target_win: WindowId,
        new_win: WindowId,
        direction: SplitDirection,
        before: bool,
    ) !void {
        const node = self.root.findWindow(target_win) orelse return error.WindowNotFound;

        // Create new leaf for the new window
        const new_leaf = try self.allocator.create(LayoutNode);
        errdefer self.allocator.destroy(new_leaf);
        new_leaf.* = .{ .window = new_win };

        // Create new leaf for the existing window
        const existing_leaf = try self.allocator.create(LayoutNode);
        errdefer self.allocator.destroy(existing_leaf);
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
        // Check if this is the only window
        if (self.root.* == .window) {
            if (self.root.window.eql(win_id)) {
                return null; // Cannot remove last window
            }
            return error.WindowNotFound;
        }

        return self.removeWindowRecursive(self.root, win_id);
    }

    fn removeWindowRecursive(self: *WindowLayout, node: *LayoutNode, win_id: WindowId) !?WindowId {
        switch (node.*) {
            .window => return error.WindowNotFound,
            .split => |*s| {
                // Check if first child is the target window
                if (s.first.* == .window and s.first.window.eql(win_id)) {
                    // Replace this split node with second child
                    const second = s.second;
                    self.allocator.destroy(s.first);
                    node.* = second.*;
                    self.allocator.destroy(second);

                    // Return a window from the remaining subtree
                    return self.getFirstWindow(node);
                }

                // Check if second child is the target window
                if (s.second.* == .window and s.second.window.eql(win_id)) {
                    // Replace this split node with first child
                    const first = s.first;
                    self.allocator.destroy(s.second);
                    node.* = first.*;
                    self.allocator.destroy(first);

                    // Return a window from the remaining subtree
                    return self.getFirstWindow(node);
                }

                // Recurse into children (check first, then second)
                if (s.first.containsWindow(win_id)) {
                    return self.removeWindowRecursive(s.first, win_id);
                }
                if (s.second.containsWindow(win_id)) {
                    return self.removeWindowRecursive(s.second, win_id);
                }

                return error.WindowNotFound;
            },
        }
    }

    /// Get the first window in the tree (leftmost/topmost)
    fn getFirstWindow(_: *WindowLayout, node: *LayoutNode) ?WindowId {
        return getFirstWindowHelper(node);
    }

    fn getFirstWindowHelper(node: *LayoutNode) ?WindowId {
        switch (node.*) {
            .window => |id| return id,
            .split => |s| return getFirstWindowHelper(s.first),
        }
    }

    /// Get all window IDs in layout order
    pub fn getAllWindows(self: *WindowLayout) ![]WindowId {
        var ids: std.ArrayListUnmanaged(WindowId) = .empty;
        errdefer ids.deinit(self.allocator);
        try self.root.getWindowIds(self.allocator, &ids);
        return ids.toOwnedSlice(self.allocator);
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
                // HashMap stores *Window, so get returns *Window directly
                if (windows.get(id)) |win| {
                    win.screen_row = row;
                    win.screen_col = col;
                    // Reserve 1 row for statusline
                    win.height = if (height > 1) height - 1 else 0;
                    win.width = width;
                    win.needs_redraw = true;
                }
            },
            .split => |s| {
                switch (s.direction) {
                    .horizontal => {
                        // Top/bottom split
                        const first_height = @as(usize, @intFromFloat(@as(f32, @floatFromInt(height)) * s.ratio));
                        const second_height = height -| first_height;

                        self.calculateLayoutRecursive(s.first, windows, row, col, first_height, width);
                        self.calculateLayoutRecursive(s.second, windows, row + first_height, col, second_height, width);
                    },
                    .vertical => {
                        // Left/right split (account for separator column)
                        const first_width = @as(usize, @intFromFloat(@as(f32, @floatFromInt(width)) * s.ratio));
                        // -1 for separator column
                        const second_width = if (width > first_width + 1) width - first_width - 1 else 0;

                        self.calculateLayoutRecursive(s.first, windows, row, col, height, first_width);
                        self.calculateLayoutRecursive(s.second, windows, row, col + first_width + 1, height, second_width);
                    },
                }
            },
        }
    }

    /// Get the bounds of a subtree (for separator rendering)
    pub fn getBounds(self: *WindowLayout, node: *LayoutNode, windows: *std.AutoHashMap(WindowId, *Window)) Bounds {
        return self.getBoundsRecursive(node, windows);
    }

    fn getBoundsRecursive(self: *WindowLayout, node: *LayoutNode, windows: *std.AutoHashMap(WindowId, *Window)) Bounds {
        switch (node.*) {
            .window => |id| {
                // HashMap stores *Window, so get returns *Window directly
                if (windows.get(id)) |win| {
                    return .{
                        .row = win.screen_row,
                        .col = win.screen_col,
                        .height = win.height + 1, // Include statusline
                        .width = win.width,
                    };
                }
                return .{ .row = 0, .col = 0, .height = 0, .width = 0 };
            },
            .split => |s| {
                const first = self.getBoundsRecursive(s.first, windows);
                const second = self.getBoundsRecursive(s.second, windows);
                return .{
                    .row = @min(first.row, second.row),
                    .col = @min(first.col, second.col),
                    .height = @max(first.row + first.height, second.row + second.height) -| @min(first.row, second.row),
                    .width = @max(first.col + first.width, second.col + second.width) -| @min(first.col, second.col),
                };
            },
        }
    }

    /// Resize a window by adjusting the split ratio of its parent
    pub fn resizeWindow(self: *WindowLayout, win_id: WindowId, delta_rows: i32, delta_cols: i32) !void {
        // Find parent split containing this window
        const parent_info = self.root.findParent(win_id) orelse return error.WindowNotFound;
        const parent = parent_info.parent;

        switch (parent.*) {
            .split => |*s| {
                const adjustment: f32 = switch (s.direction) {
                    .horizontal => @as(f32, @floatFromInt(delta_rows)) * 0.05, // 5% per row
                    .vertical => @as(f32, @floatFromInt(delta_cols)) * 0.02, // 2% per col
                };

                // Adjust ratio based on which child the window is in
                if (parent_info.is_first) {
                    s.ratio = @max(0.1, @min(0.9, s.ratio + adjustment));
                } else {
                    s.ratio = @max(0.1, @min(0.9, s.ratio - adjustment));
                }
            },
            else => {},
        }
    }

    /// Find window in a specific direction from the given window
    pub fn findAdjacentWindow(
        self: *WindowLayout,
        from_win: WindowId,
        direction: NavigationDirection,
        windows: *std.AutoHashMap(WindowId, *Window),
    ) ?WindowId {
        const from = windows.get(from_win) orelse return null;

        var best_match: ?WindowId = null;
        var best_distance: usize = std.math.maxInt(usize);

        var iter = windows.iterator();
        while (iter.next()) |entry| {
            if (entry.key_ptr.eql(from_win)) continue;

            const win = entry.value_ptr.*;
            const matches = switch (direction) {
                .left => win.screen_col + win.width <= from.screen_col,
                .right => win.screen_col >= from.screen_col + from.width,
                .up => win.screen_row + win.height <= from.screen_row,
                .down => win.screen_row >= from.screen_row + from.height,
            };

            if (matches) {
                const distance = switch (direction) {
                    .left => from.screen_col -| (win.screen_col + win.width),
                    .right => win.screen_col -| (from.screen_col + from.width),
                    .up => from.screen_row -| (win.screen_row + win.height),
                    .down => win.screen_row -| (from.screen_row + from.height),
                };

                if (distance < best_distance) {
                    best_distance = distance;
                    best_match = entry.key_ptr.*;
                }
            }
        }

        _ = self;
        return best_match;
    }
};

/// Bounds structure for layout calculations
pub const Bounds = struct {
    row: usize,
    col: usize,
    height: usize,
    width: usize,
};

// Tests
test "WindowLayout init with single window" {
    const allocator = std.testing.allocator;
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    const windows = try layout.getAllWindows();
    defer allocator.free(windows);

    try std.testing.expectEqual(@as(usize, 1), windows.len);
    try std.testing.expectEqual(@as(u32, 0), windows[0].id);
}

test "WindowLayout horizontal split" {
    const allocator = std.testing.allocator;
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .horizontal, false);

    const windows = try layout.getAllWindows();
    defer allocator.free(windows);

    try std.testing.expectEqual(@as(usize, 2), windows.len);
}

test "WindowLayout vertical split" {
    const allocator = std.testing.allocator;
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    const windows = try layout.getAllWindows();
    defer allocator.free(windows);

    try std.testing.expectEqual(@as(usize, 2), windows.len);
}

test "WindowLayout remove window" {
    const allocator = std.testing.allocator;
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Create split
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    // Remove second window
    const new_active = try layout.removeWindow(WindowId{ .id = 1 });

    try std.testing.expect(new_active != null);
    try std.testing.expectEqual(@as(u32, 0), new_active.?.id);

    const windows = try layout.getAllWindows();
    defer allocator.free(windows);

    try std.testing.expectEqual(@as(usize, 1), windows.len);
}

test "WindowLayout cannot remove last window" {
    const allocator = std.testing.allocator;
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    const result = try layout.removeWindow(WindowId{ .id = 0 });
    try std.testing.expect(result == null);
}

test "WindowLayout nested splits" {
    const allocator = std.testing.allocator;
    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Split 0 -> [0, 1]
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    // Split 1 -> [1, 2]
    try layout.split(WindowId{ .id = 1 }, WindowId{ .id = 2 }, .horizontal, false);

    const windows = try layout.getAllWindows();
    defer allocator.free(windows);

    try std.testing.expectEqual(@as(usize, 3), windows.len);
}

test "WindowLayout calculateLayout single window" {
    const allocator = std.testing.allocator;
    const BufferId = @import("window.zig").BufferId;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Create window struct
    var win0 = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 0 });
    defer win0.deinit();

    // Create windows HashMap
    var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
    defer windows.deinit();
    try windows.put(WindowId{ .id = 0 }, &win0);

    // Calculate layout for 24x80 terminal
    layout.calculateLayout(&windows, 24, 80);

    // Single window should take full width and height minus statusline
    try std.testing.expectEqual(@as(usize, 0), win0.screen_row);
    try std.testing.expectEqual(@as(usize, 0), win0.screen_col);
    try std.testing.expectEqual(@as(usize, 23), win0.height); // 24 - 1 for statusline
    try std.testing.expectEqual(@as(usize, 80), win0.width);
}

test "WindowLayout calculateLayout vertical split" {
    const allocator = std.testing.allocator;
    const BufferId = @import("window.zig").BufferId;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Create vertical split
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    // Create window structs
    var win0 = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 0 });
    defer win0.deinit();
    var win1 = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 0 });
    defer win1.deinit();

    var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
    defer windows.deinit();
    try windows.put(WindowId{ .id = 0 }, &win0);
    try windows.put(WindowId{ .id = 1 }, &win1);

    // Calculate layout for 24x80 terminal
    layout.calculateLayout(&windows, 24, 80);

    // Left window (win0): col 0, width = 40 (half of 80)
    try std.testing.expectEqual(@as(usize, 0), win0.screen_row);
    try std.testing.expectEqual(@as(usize, 0), win0.screen_col);
    try std.testing.expectEqual(@as(usize, 40), win0.width);

    // Right window (win1): col = 41 (40 + 1 for separator)
    try std.testing.expectEqual(@as(usize, 0), win1.screen_row);
    try std.testing.expectEqual(@as(usize, 41), win1.screen_col);
    // Width = 80 - 40 - 1 = 39
    try std.testing.expectEqual(@as(usize, 39), win1.width);
}

test "WindowLayout calculateLayout horizontal split" {
    const allocator = std.testing.allocator;
    const BufferId = @import("window.zig").BufferId;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Create horizontal split
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .horizontal, false);

    // Create window structs
    var win0 = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 0 });
    defer win0.deinit();
    var win1 = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 0 });
    defer win1.deinit();

    var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
    defer windows.deinit();
    try windows.put(WindowId{ .id = 0 }, &win0);
    try windows.put(WindowId{ .id = 1 }, &win1);

    // Calculate layout for 24x80 terminal
    layout.calculateLayout(&windows, 24, 80);

    // Top window (win0): row 0, height = 11 (12 - 1 for statusline, half of 24)
    try std.testing.expectEqual(@as(usize, 0), win0.screen_row);
    try std.testing.expect(win0.height > 0);

    // Bottom window (win1): row = 12 (half of 24)
    try std.testing.expect(win1.screen_row > 0);
    try std.testing.expect(win1.height > 0);
    // Both should have full width
    try std.testing.expectEqual(@as(usize, 80), win0.width);
    try std.testing.expectEqual(@as(usize, 80), win1.width);
}

test "WindowLayout findAdjacentWindow vertical split" {
    const allocator = std.testing.allocator;
    const BufferId = @import("window.zig").BufferId;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Create vertical split (left/right)
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    var win0 = Window.init(allocator, WindowId{ .id = 0 }, BufferId{ .id = 0 });
    defer win0.deinit();
    var win1 = Window.init(allocator, WindowId{ .id = 1 }, BufferId{ .id = 0 });
    defer win1.deinit();

    var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
    defer windows.deinit();
    try windows.put(WindowId{ .id = 0 }, &win0);
    try windows.put(WindowId{ .id = 1 }, &win1);

    layout.calculateLayout(&windows, 24, 80);

    // From win0 (left), going right should find win1
    const right_of_0 = layout.findAdjacentWindow(WindowId{ .id = 0 }, .right, &windows);
    try std.testing.expect(right_of_0 != null);
    try std.testing.expectEqual(@as(u32, 1), right_of_0.?.id);

    // From win1 (right), going left should find win0
    const left_of_1 = layout.findAdjacentWindow(WindowId{ .id = 1 }, .left, &windows);
    try std.testing.expect(left_of_1 != null);
    try std.testing.expectEqual(@as(u32, 0), left_of_1.?.id);

    // From win0, going left should find nothing
    const left_of_0 = layout.findAdjacentWindow(WindowId{ .id = 0 }, .left, &windows);
    try std.testing.expect(left_of_0 == null);
}

test "WindowLayout resizeWindow adjusts ratio" {
    const allocator = std.testing.allocator;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Create vertical split
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    // Initial ratio is 0.5
    // Resize window 0 (first child) to be larger
    try layout.resizeWindow(WindowId{ .id = 0 }, 0, 5); // delta_cols = 5

    // Get the ratio from root split
    switch (layout.root.*) {
        .split => |s| {
            // Ratio should have increased (window 0 is first child)
            try std.testing.expect(s.ratio > 0.5);
            try std.testing.expect(s.ratio <= 0.9); // Clamped
        },
        else => unreachable,
    }
}

test "WindowLayout split before parameter" {
    const allocator = std.testing.allocator;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    // Split with before=true (new window goes first/left)
    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, true);

    const windows = try layout.getAllWindows();
    defer allocator.free(windows);

    // Order should be: [1, 0] (new window first)
    try std.testing.expectEqual(@as(u32, 1), windows[0].id);
    try std.testing.expectEqual(@as(u32, 0), windows[1].id);
}

test "LayoutNode countWindows" {
    const allocator = std.testing.allocator;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    try std.testing.expectEqual(@as(usize, 1), layout.root.countWindows());

    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);
    try std.testing.expectEqual(@as(usize, 2), layout.root.countWindows());

    try layout.split(WindowId{ .id = 1 }, WindowId{ .id = 2 }, .horizontal, false);
    try std.testing.expectEqual(@as(usize, 3), layout.root.countWindows());
}

test "LayoutNode containsWindow" {
    const allocator = std.testing.allocator;

    var layout = try WindowLayout.init(allocator, WindowId{ .id = 0 });
    defer layout.deinit();

    try std.testing.expect(layout.root.containsWindow(WindowId{ .id = 0 }));
    try std.testing.expect(!layout.root.containsWindow(WindowId{ .id = 99 }));

    try layout.split(WindowId{ .id = 0 }, WindowId{ .id = 1 }, .vertical, false);

    try std.testing.expect(layout.root.containsWindow(WindowId{ .id = 0 }));
    try std.testing.expect(layout.root.containsWindow(WindowId{ .id = 1 }));
    try std.testing.expect(!layout.root.containsWindow(WindowId{ .id = 99 }));
}
