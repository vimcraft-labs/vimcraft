const std = @import("std");
const Allocator = std.mem.Allocator;

/// Virtual text cell - a character rendered at a specific screen position
/// This is OpenVim's equivalent to Neovim's extmarks with virt_text
/// Plugins can use this to render arbitrary content overlaid on the buffer
pub const VirtualTextCell = struct {
    /// Screen row (0-indexed, relative to viewport)
    row: usize,
    /// Screen column (0-indexed, includes gutter)
    col: usize,
    /// Unicode codepoint to render
    char: u21,
    /// Foreground color (24-bit RGB, optional)
    fg: ?u24,
    /// Background color (24-bit RGB, optional)
    bg: ?u24,
};

/// Virtual text overlay renderer
/// Provides Neovim-style extmark/virtual text functionality
/// Plugins can draw arbitrary characters at screen positions
pub const VirtualTextRenderer = struct {
    cells: std.ArrayList(VirtualTextCell),
    allocator: Allocator,

    pub fn init(allocator: Allocator) VirtualTextRenderer {
        return .{
            .cells = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VirtualTextRenderer) void {
        self.cells.deinit(self.allocator);
    }

    /// Add a virtual text cell (Neovim: nvim_buf_set_extmark with virt_text)
    pub fn addCell(self: *VirtualTextRenderer, cell: VirtualTextCell) !void {
        try self.cells.append(self.allocator, cell);
    }

    /// Clear all virtual text (Neovim: nvim_buf_clear_namespace)
    pub fn clear(self: *VirtualTextRenderer) void {
        self.cells.clearRetainingCapacity();
    }

    /// Apply virtual text to the screen grid (overlay rendering)
    /// This is called AFTER buffer content is rendered but BEFORE diff computation
    /// Note: Coordinates are SCREEN coordinates (includes viewport scroll and gutter offset)
    pub fn applyToGrid(self: *const VirtualTextRenderer, grid: anytype) void {
        const Cell = @import("screen_grid.zig").Cell;
        const highlights = @import("../../../editor/config/highlights.zig");

        // Overlay virtual text cells on grid
        for (self.cells.items) |virt_cell| {
            // Bounds check
            if (virt_cell.row >= grid.height or virt_cell.col >= grid.width) {
                continue;
            }

            // Convert u24 colors to Color structs
            const fg_color = if (virt_cell.fg) |fg| blk: {
                const r: u8 = @intCast((fg >> 16) & 0xFF);
                const g: u8 = @intCast((fg >> 8) & 0xFF);
                const b: u8 = @intCast(fg & 0xFF);
                break :blk highlights.Color{ .r = r, .g = g, .b = b };
            } else null;

            const bg_color = if (virt_cell.bg) |bg| blk: {
                const r: u8 = @intCast((bg >> 16) & 0xFF);
                const g: u8 = @intCast((bg >> 8) & 0xFF);
                const b: u8 = @intCast(bg & 0xFF);
                break :blk highlights.Color{ .r = r, .g = g, .b = b };
            } else null;

            // Overlay virtual text cell on grid (marks dirty automatically)
            grid.setCell(virt_cell.row, virt_cell.col, Cell{
                .char = virt_cell.char,
                .fg = fg_color,
                .bg = bg_color,
            });
        }
    }
};
