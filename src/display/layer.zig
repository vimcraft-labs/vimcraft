const std = @import("std");
const Allocator = std.mem.Allocator;
const ScreenGrid = @import("screen_grid.zig").ScreenGrid;
const DirtyRectTracker = @import("dirty_rect.zig").DirtyRectTracker;
const debug_log = @import("../debug/log.zig");

/// Layer z-index constants (Neovim-compatible ordering)
pub const ZIndex = struct {
    pub const BASE: i32 = 0; // Buffer content
    pub const GUTTER: i32 = 100; // Line numbers, signs, folds
    pub const CURSOR: i32 = 200; // Text cursor
    pub const VIRTUAL_TEXT: i32 = 300; // Inline diagnostics, hints
    pub const SELECTION: i32 = 400; // Visual mode selection
    pub const SEARCH: i32 = 500; // Search highlights
    pub const FLOAT: i32 = 600; // Floating windows (LSP popups)
    pub const CMDLINE: i32 = 700; // Command line
    pub const MESSAGE: i32 = 800; // Error/info messages
    pub const MODAL: i32 = 900; // Modal overlays/dialogs
};

/// Layer ID type (unique identifier for each layer)
pub const LayerId = usize;

/// Render layer (Neovim: window/buffer/extmark namespace)
/// Each layer has its own grid and rendering logic
/// Layers are composited in z-index order to produce final output
pub const Layer = struct {
    /// Unique identifier
    id: LayerId,

    /// Z-index for layer ordering (higher = on top)
    z_index: i32,

    /// Whether this layer is currently visible
    enabled: bool,

    /// Layer opacity (0.0 = transparent, 1.0 = opaque)
    /// Used for alpha blending during composition
    opacity: f32,

    /// Grid for this layer (same dimensions as terminal)
    /// Each layer renders to its own grid, then compositor blends them
    grid: ScreenGrid,

    /// Dirty flag (true = needs re-render)
    /// Optimization: skip rendering clean layers
    dirty: bool,

    /// Dirty rectangle tracker (Phase 6 optimization)
    /// Tracks which specific regions of the layer changed
    dirty_rect_tracker: DirtyRectTracker,

    /// Cache flag (true = layer content is static and cacheable)
    /// Static layers (like gutter) can be cached and skipped during composition
    cacheable: bool,

    /// Cache valid flag (true = cached version is up-to-date)
    cache_valid: bool,

    /// Layer metadata (for debugging/inspection)
    name: []const u8,

    /// Allocator for this layer
    allocator: Allocator,

    /// Initialize a new layer
    pub fn init(allocator: Allocator, id: LayerId, z_index: i32, height: usize, width: usize, name: []const u8) !Layer {
        return Layer{
            .id = id,
            .z_index = z_index,
            .enabled = true,
            .opacity = 1.0,
            .grid = try ScreenGrid.init(allocator, width, height),
            .dirty = true, // Start dirty (needs initial render)
            .dirty_rect_tracker = DirtyRectTracker.init(allocator),
            .cacheable = false, // Default: not cacheable
            .cache_valid = false,
            .name = name,
            .allocator = allocator,
        };
    }

    /// Deinitialize layer and free resources
    pub fn deinit(self: *Layer) void {
        self.grid.deinit();
        self.dirty_rect_tracker.deinit();
    }

    /// Mark layer as needing re-render
    pub fn markDirty(self: *Layer) void {
        self.dirty = true;
        self.dirty_rect_tracker.markFullDirty();
        self.cache_valid = false;
    }

    /// Mark specific cell as dirty (Phase 6 optimization)
    pub fn markCellDirty(self: *Layer, row: usize, col: usize) !void {
        self.dirty = true;
        try self.dirty_rect_tracker.markCell(row, col);
        self.cache_valid = false;
    }

    /// Mark layer as clean (render complete)
    pub fn markClean(self: *Layer) void {
        self.dirty = false;
        self.dirty_rect_tracker.clear();
        if (self.cacheable) {
            self.cache_valid = true;
        }
    }

    /// Clear layer grid (fill with empty cells)
    /// Only marks layer dirty if grid actually had content (optimization to prevent flickering)
    pub fn clear(self: *Layer) void {
        // Clear the grid (grid.clear() only marks lines dirty if they had content)
        self.grid.clear();

        // Only mark layer dirty if the grid had any dirty lines
        // (i.e., the grid had content that was cleared)
        if (self.grid.dirty_lines.count() > 0) {
            self.markDirty();
        }
    }

    /// Mark layer as cacheable (Phase 6 optimization)
    /// Cacheable layers (like gutter) don't change often
    pub fn setCacheable(self: *Layer, cacheable: bool) void {
        self.cacheable = cacheable;
        if (!cacheable) {
            self.cache_valid = false;
        }
    }

    /// Check if layer can be skipped during composition (Phase 6 optimization)
    pub fn canSkipComposition(self: *Layer) bool {
        return self.cacheable and self.cache_valid and !self.dirty;
    }

    /// Resize layer grid
    pub fn resize(self: *Layer, new_height: usize, new_width: usize) !void {
        try self.grid.resize(new_width, new_height);
        self.markDirty();
    }

    /// Set layer visibility
    pub fn setEnabled(self: *Layer, enabled: bool) void {
        if (self.enabled != enabled) {
            self.enabled = enabled;
            self.markDirty();
        }
    }

    /// Set layer opacity
    pub fn setOpacity(self: *Layer, opacity: f32) void {
        const clamped = @max(0.0, @min(1.0, opacity));
        if (self.opacity != clamped) {
            self.opacity = clamped;
            self.markDirty();
        }
    }

    /// Set layer z-index
    pub fn setZIndex(self: *Layer, z_index: i32) void {
        if (self.z_index != z_index) {
            self.z_index = z_index;
            self.markDirty();
        }
    }
};

/// Layer manager (manages all rendering layers)
/// Maintains layers in z-index order for efficient composition
pub const LayerManager = struct {
    /// All layers, sorted by z-index (lowest first)
    layers: std.ArrayList(*Layer),

    /// Next layer ID (auto-incrementing)
    next_id: LayerId,

    /// Allocator for layer storage
    allocator: Allocator,

    /// Initialize layer manager
    pub fn init(allocator: Allocator) LayerManager {
        return .{
            .layers = .empty,
            .next_id = 0,
            .allocator = allocator,
        };
    }

    /// Deinitialize layer manager and all layers
    pub fn deinit(self: *LayerManager) void {
        // Free all layers
        for (self.layers.items) |layer| {
            // Free layer name if it's a custom layer (not a core layer)
            if (!isCoreLayerName(layer.name)) {
                self.allocator.free(layer.name);
            }
            layer.deinit();
            self.allocator.destroy(layer);
        }
        self.layers.deinit(self.allocator);
    }

    /// Create and add a new layer
    pub fn createLayer(
        self: *LayerManager,
        z_index: i32,
        height: usize,
        width: usize,
        name: []const u8,
    ) !*Layer {
        const id = self.next_id;
        self.next_id += 1;

        const layer = try self.allocator.create(Layer);
        errdefer self.allocator.destroy(layer);

        layer.* = try Layer.init(self.allocator, id, z_index, height, width, name);
        errdefer layer.deinit();

        try self.addLayer(layer);
        return layer;
    }

    /// Add existing layer (maintains z-index order)
    pub fn addLayer(self: *LayerManager, layer: *Layer) !void {
        // Find insertion point (binary search for efficiency)
        const insert_idx = self.findInsertionPoint(layer.z_index);
        try self.layers.insert(self.allocator, insert_idx, layer);

        // Debug: Log layer addition (to debug log, not terminal)
        debug_log.log("[LayerManager] Added layer '{s}' (id={d}, z={d}, enabled={}, dirty={})", .{
            layer.name,
            layer.id,
            layer.z_index,
            layer.enabled,
            layer.dirty,
        });
    }

    /// Remove layer by ID
    pub fn removeLayer(self: *LayerManager, id: LayerId) ?*Layer {
        for (self.layers.items, 0..) |layer, i| {
            if (layer.id == id) {
                return self.layers.orderedRemove(i);
            }
        }
        return null;
    }

    /// Get layer by ID
    pub fn getLayer(self: *LayerManager, id: LayerId) ?*Layer {
        for (self.layers.items) |layer| {
            if (layer.id == id) return layer;
        }
        return null;
    }

    /// Get layer by name
    pub fn getLayerByName(self: *LayerManager, name: []const u8) ?*Layer {
        for (self.layers.items) |layer| {
            if (std.mem.eql(u8, layer.name, name)) return layer;
        }
        return null;
    }

    /// Update layer z-index (maintains sort order)
    pub fn updateZIndex(self: *LayerManager, id: LayerId, new_z_index: i32) !void {
        // Remove layer
        const layer = self.removeLayer(id) orelse return;

        // Update z-index
        layer.z_index = new_z_index;
        layer.markDirty();

        // Re-insert at correct position
        try self.addLayer(layer);
    }

    /// Get all dirty layers (need re-render)
    pub fn getDirtyLayers(self: *LayerManager, allocator: Allocator) !std.ArrayList(*Layer) {
        var dirty: std.ArrayList(*Layer) = .empty;
        for (self.layers.items) |layer| {
            if (layer.dirty and layer.enabled) {
                try dirty.append(allocator, layer);
            }
        }
        return dirty;
    }

    /// Mark all layers as dirty (force full re-render)
    pub fn markAllDirty(self: *LayerManager) void {
        for (self.layers.items) |layer| {
            layer.markDirty();
        }
    }

    /// Resize all layers (terminal resize event)
    pub fn resizeAll(self: *LayerManager, new_height: usize, new_width: usize) !void {
        for (self.layers.items) |layer| {
            try layer.resize(new_height, new_width);
        }
    }

    /// Find insertion point for z-index (binary search)
    fn findInsertionPoint(self: *LayerManager, z_index: i32) usize {
        if (self.layers.items.len == 0) return 0;

        var left: usize = 0;
        var right: usize = self.layers.items.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            if (self.layers.items[mid].z_index < z_index) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return left;
    }

    /// Debug: Print layer hierarchy
    pub fn debugPrint(self: *LayerManager) void {
        std.debug.print("\n=== Layer Hierarchy ===\n", .{});
        for (self.layers.items) |layer| {
            std.debug.print(
                "  [{d:3}] z={d:4} opacity={d:.2} dirty={} enabled={} name={s}\n",
                .{ layer.id, layer.z_index, layer.opacity, layer.dirty, layer.enabled, layer.name },
            );
        }
        std.debug.print("======================\n\n", .{});
    }

    /// Create a custom layer for plugins (takes owned name string)
    /// Used by JavaScript plugins via JSI bridge
    /// Returns error if z-index conflicts with core layers
    pub fn createCustomLayer(
        self: *LayerManager,
        z_index: i32,
        height: usize,
        width: usize,
        name: []const u8,
        opts: struct {
            opacity: f32 = 1.0,
            cacheable: bool = false,
        },
    ) !*Layer {
        // Validate z-index doesn't conflict with core layers
        if (isReservedZIndex(z_index)) {
            return error.ReservedZIndex;
        }

        // Duplicate name for layer ownership
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const id = self.next_id;
        self.next_id += 1;

        const layer = try self.allocator.create(Layer);
        errdefer self.allocator.destroy(layer);

        layer.* = try Layer.init(self.allocator, id, z_index, height, width, owned_name);
        errdefer layer.deinit();

        // Apply custom options
        layer.opacity = @max(0.0, @min(1.0, opts.opacity));
        layer.setCacheable(opts.cacheable);

        try self.addLayer(layer);
        return layer;
    }

    /// Destroy a custom layer by name
    /// Used by JavaScript plugins for cleanup
    pub fn destroyCustomLayer(self: *LayerManager, name: []const u8) !void {
        // Find layer by name
        const layer = self.getLayerByName(name) orelse return error.LayerNotFound;

        // Don't allow destroying core layers
        if (isCoreLayerName(name)) {
            return error.CannotDestroyCoreLayer;
        }

        // Remove from manager
        _ = self.removeLayer(layer.id) orelse return error.LayerNotFound;

        // Free name (we own it for custom layers)
        self.allocator.free(layer.name);

        // Cleanup layer
        layer.deinit();
        self.allocator.destroy(layer);
    }

    /// Check if z-index is reserved for core layers
    fn isReservedZIndex(z_index: i32) bool {
        return z_index == ZIndex.BASE or
            z_index == ZIndex.GUTTER or
            z_index == ZIndex.CURSOR or
            z_index == ZIndex.VIRTUAL_TEXT or
            z_index == ZIndex.SELECTION or
            z_index == ZIndex.SEARCH or
            z_index == ZIndex.FLOAT or
            z_index == ZIndex.CMDLINE or
            z_index == ZIndex.MESSAGE or
            z_index == ZIndex.MODAL;
    }

    /// Check if layer name is a core layer
    fn isCoreLayerName(name: []const u8) bool {
        return std.mem.eql(u8, name, "buffer") or
            std.mem.eql(u8, name, "gutter") or
            std.mem.eql(u8, name, "cursor") or
            std.mem.eql(u8, name, "virtual_text") or
            std.mem.eql(u8, name, "selection") or
            std.mem.eql(u8, name, "yank");
    }
};

// Tests
test "Layer creation and properties" {
    const allocator = std.testing.allocator;

    var layer = try Layer.init(allocator, 0, ZIndex.BASE, 24, 80, "test");
    defer layer.deinit();

    try std.testing.expectEqual(@as(LayerId, 0), layer.id);
    try std.testing.expectEqual(@as(i32, ZIndex.BASE), layer.z_index);
    try std.testing.expect(layer.enabled);
    try std.testing.expectEqual(@as(f32, 1.0), layer.opacity);
    try std.testing.expect(layer.dirty);
}

test "LayerManager z-index ordering" {
    const allocator = std.testing.allocator;

    var manager = LayerManager.init(allocator);
    defer manager.deinit();

    // Create layers in random z-index order
    const layer1 = try manager.createLayer(ZIndex.VIRTUAL_TEXT, 24, 80, "virtual_text");
    const layer2 = try manager.createLayer(ZIndex.BASE, 24, 80, "base");
    const layer3 = try manager.createLayer(ZIndex.CURSOR, 24, 80, "cursor");

    // Verify they're sorted by z-index
    try std.testing.expectEqual(layer2, manager.layers.items[0]); // BASE (0)
    try std.testing.expectEqual(layer3, manager.layers.items[1]); // CURSOR (200)
    try std.testing.expectEqual(layer1, manager.layers.items[2]); // VIRTUAL_TEXT (300)
}

test "LayerManager dirty tracking" {
    const allocator = std.testing.allocator;

    var manager = LayerManager.init(allocator);
    defer manager.deinit();

    const layer1 = try manager.createLayer(ZIndex.BASE, 24, 80, "layer1");
    const layer2 = try manager.createLayer(ZIndex.CURSOR, 24, 80, "layer2");

    // Mark layer1 as clean
    layer1.markClean();
    try std.testing.expect(!layer1.dirty);

    // Get dirty layers
    var dirty = try manager.getDirtyLayers(allocator);
    defer dirty.deinit(allocator);

    // Only layer2 should be dirty
    try std.testing.expectEqual(@as(usize, 1), dirty.items.len);
    try std.testing.expectEqual(layer2, dirty.items[0]);
}

test "LayerManager update z-index" {
    const allocator = std.testing.allocator;

    var manager = LayerManager.init(allocator);
    defer manager.deinit();

    const layer = try manager.createLayer(ZIndex.BASE, 24, 80, "test");
    const id = layer.id;

    // Update z-index
    try manager.updateZIndex(id, ZIndex.CURSOR);

    // Verify z-index changed
    const updated = manager.getLayer(id).?;
    try std.testing.expectEqual(@as(i32, ZIndex.CURSOR), updated.z_index);
    try std.testing.expect(updated.dirty); // Should be marked dirty
}
