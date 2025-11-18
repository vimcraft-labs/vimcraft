/// Layer API Module
/// Handles all layer-related JSI functions for virtual text rendering
/// Generic layer system for plugins to create custom overlays (Neovim-style extmarks)
const std = @import("std");
const Display = @import("../../backends/terminal/display/display.zig").Display;
const helpers = @import("helpers.zig");
const debug_log = @import("../../backends/debug/log.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// Import animation API for dirty flag management
const animation_api = @import("animation_api.zig");

/// Global display pointer for virtual text rendering (Neovim-style extmarks)
/// Set during initialization
var global_display: ?*Display = null;

/// Set the global display for layer operations
pub fn setDisplay(display: ?*Display) void {
    global_display = display;
}

/// Zig host function: drawVirtualText(row, col, char, fg, bg)
/// Renders a virtual text overlay at screen coordinates (Neovim-style extmark)
/// This is a general primitive - plugins handle coordinate conversion
pub export fn drawVirtualText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    _ = context;

    if (count < 5) return null;

    const display = global_display orelse return null;

    const row_val = args[0] orelse return null;
    const col_val = args[1] orelse return null;
    const char_val = args[2] orelse return null;
    const fg_val = args[3] orelse return null;
    const bg_val = args[4] orelse return null;

    const row_f = c.hermes_value_get_number(row_val);
    const col_f = c.hermes_value_get_number(col_val);
    const char_f = c.hermes_value_get_number(char_val);

    // NaN/Infinity protection
    if (std.math.isNan(row_f) or std.math.isInf(row_f) or row_f < 0) return null;
    if (std.math.isNan(col_f) or std.math.isInf(col_f) or col_f < 0) return null;
    if (std.math.isNan(char_f) or std.math.isInf(char_f) or char_f < 0) return null;

    const row: usize = @intFromFloat(row_f);
    const col: usize = @intFromFloat(col_f);
    const char: u21 = @intCast(@as(u32, @intFromFloat(char_f)));

    // Parse optional colors (null = use default)
    var fg: ?u24 = null;
    var bg: ?u24 = null;

    if (!c.hermes_value_is_null(fg_val)) {
        const fg_f = c.hermes_value_get_number(fg_val);
        if (!std.math.isNan(fg_f) and !std.math.isInf(fg_f) and fg_f >= 0) {
            fg = @intCast(@as(u32, @intFromFloat(fg_f)));
        }
    }

    if (!c.hermes_value_is_null(bg_val)) {
        const bg_f = c.hermes_value_get_number(bg_val);
        if (!std.math.isNan(bg_f) and !std.math.isInf(bg_f) and bg_f >= 0) {
            bg = @intCast(@as(u32, @intFromFloat(bg_f)));
        }
    }

    // Add virtual text cell to display (Neovim: nvim_buf_set_extmark with virt_text)
    display.virtual_text.addCell(.{
        .row = row,
        .col = col,
        .char = char,
        .fg = fg,
        .bg = bg,
    }) catch return null;

    return null; // Return undefined
}

/// Zig host function: clearVirtualText()
/// Clears all virtual text overlays (Neovim: nvim_buf_clear_namespace)
pub export fn clearVirtualText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = runtime;
    _ = context;
    _ = args;
    _ = count;

    const display = global_display orelse return null;

    // Clear all virtual text cells
    display.virtual_text.clear();

    return null; // Return undefined
}

/// Zig host function: getViewportInfo() -> {top, left, height, width}
/// Returns viewport scroll position and dimensions for coordinate conversion
pub export fn getViewportInfo(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const display = global_display orelse return null;

    // Create JavaScript object: {top, left, height, width}
    const obj = c.hermes_value_create_object(runtime) orelse return null;

    // Create number values
    const top_val = c.hermes_value_create_number(runtime, @floatFromInt(display.viewport_top));
    const left_val = c.hermes_value_create_number(runtime, @floatFromInt(display.viewport_left));
    const height_val = c.hermes_value_create_number(runtime, @floatFromInt(display.terminal_rows));
    const width_val = c.hermes_value_create_number(runtime, @floatFromInt(display.terminal_cols));

    if (top_val != null and left_val != null and height_val != null and width_val != null) {
        // Set properties on the object
        c.hermes_value_set_property(runtime, obj, "top", top_val);
        c.hermes_value_set_property(runtime, obj, "left", left_val);
        c.hermes_value_set_property(runtime, obj, "height", height_val);
        c.hermes_value_set_property(runtime, obj, "width", width_val);

        // Clean up temporary values
        c.hermes_value_destroy(top_val);
        c.hermes_value_destroy(left_val);
        c.hermes_value_destroy(height_val);
        c.hermes_value_destroy(width_val);
    }

    return obj;
}

/// Zig host function: getGutterWidth() -> number
/// Returns total gutter width (line numbers + signs) for horizontal offset calculation
pub export fn getGutterWidth(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    _ = args;
    _ = count;

    const display = global_display orelse return null;

    // Get total gutter width
    const gutter_width = display.gutter_manager.getTotalWidth();

    // Return as JavaScript number
    return c.hermes_value_create_number(runtime, @floatFromInt(gutter_width));
}

// ============================================================================
// Generic Virtual Text Layer API (Phase 1)
// ============================================================================

/// Zig host function: createLayer(name, options)
/// JavaScript: createLayer('my_layer', {z_index: 50, opacity: 1.0, cacheable: false})
/// Creates a custom rendering layer for plugins
pub export fn createLayer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse {
        std.debug.print("[JSI] ERROR: global_display is null!\n", .{});
        return c.hermes_value_create_undefined(runtime);
    };

    if (count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    // Copy name to avoid shared buffer corruption
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: options object {z_index, opacity?, cacheable?}
    if (args[1] == null or !c.hermes_value_is_object(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opts_val = args[1].?;

    // Get z_index (required) - use hermes_value_get_property directly
    const z_index_val = c.hermes_value_get_property(runtime, opts_val, "z_index");
    if (z_index_val == null or !c.hermes_value_is_number(z_index_val)) {
        if (z_index_val != null) c.hermes_value_destroy(z_index_val);
        return c.hermes_value_create_undefined(runtime);
    }
    const z_index: i32 = @intFromFloat(c.hermes_value_get_number(z_index_val));
    c.hermes_value_destroy(z_index_val);

    // Get opacity (optional, default 1.0)
    var opacity: f32 = 1.0;
    const opacity_val = c.hermes_value_get_property(runtime, opts_val, "opacity");
    if (opacity_val != null and c.hermes_value_is_number(opacity_val)) {
        opacity = @floatCast(c.hermes_value_get_number(opacity_val));
        c.hermes_value_destroy(opacity_val);
    } else if (opacity_val != null) {
        c.hermes_value_destroy(opacity_val);
    }

    // Get cacheable (optional, default false)
    var cacheable: bool = false;
    const cacheable_val = c.hermes_value_get_property(runtime, opts_val, "cacheable");
    if (cacheable_val != null and c.hermes_value_is_boolean(cacheable_val)) {
        cacheable = c.hermes_value_get_boolean(cacheable_val);
        c.hermes_value_destroy(cacheable_val);
    } else if (cacheable_val != null) {
        c.hermes_value_destroy(cacheable_val);
    }

    // Create custom layer via LayerManager
    const height = display.terminal_rows;
    const width = display.terminal_cols;

    _ = display.layer_manager.createCustomLayer(
        z_index,
        height,
        width,
        name,
        .{ .opacity = opacity, .cacheable = cacheable },
    ) catch {
        // Layer creation failed (likely ReservedZIndex error)
        std.debug.print("[JSI] ERROR: Failed to create layer '{s}' with z_index={d}\n", .{ name, z_index });
        return c.hermes_value_create_undefined(runtime);
    };

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: renderVirtualText(name, cells)
/// JavaScript: renderVirtualText('my_layer', [{row, col, char, fg?, bg?}, ...])
/// Renders cells to a custom layer
pub export fn renderVirtualText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: cells array (check if it's an object with length property)
    if (args[1] == null or !c.hermes_value_is_object(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Get layer by name
    const layer = display.layer_manager.getLayerByName(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Clear layer before rendering new cells
    layer.clear();

    // Get array length using hermes_value_get_property
    const cells_val = args[1].?;
    const length_val = c.hermes_value_get_property(runtime, cells_val, "length");
    if (length_val == null) return c.hermes_value_create_undefined(runtime);
    const length = @as(usize, @intFromFloat(c.hermes_value_get_number(length_val)));
    c.hermes_value_destroy(length_val);

    // Import Cell type
    const Cell = @import("../../backends/terminal/display/screen_grid.zig").Cell;
    const Color = @import("../../editor/config/highlights.zig").Color;

    // Iterate over cells array
    var i: usize = 0;
    while (i < length) : (i += 1) {
        // Get cell object at index i (convert index to string for property access)
        var idx_buf: [32]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch continue;
        const idx_str_null = std.fmt.bufPrintZ(&idx_buf, "{d}", .{i}) catch continue;
        _ = idx_str;

        const cell_val = c.hermes_value_get_property(runtime, cells_val, idx_str_null.ptr);
        if (cell_val == null or !c.hermes_value_is_object(cell_val)) {
            if (cell_val != null) c.hermes_value_destroy(cell_val);
            continue;
        }

        // Extract cell properties using hermes_value_get_property
        const row_val = c.hermes_value_get_property(runtime, cell_val, "row");
        const col_val = c.hermes_value_get_property(runtime, cell_val, "col");
        const char_val = c.hermes_value_get_property(runtime, cell_val, "char");

        if (row_val == null or col_val == null or char_val == null) {
            if (row_val != null) c.hermes_value_destroy(row_val);
            if (col_val != null) c.hermes_value_destroy(col_val);
            if (char_val != null) c.hermes_value_destroy(char_val);
            c.hermes_value_destroy(cell_val);
            continue;
        }

        const row_f = c.hermes_value_get_number(row_val);
        const col_f = c.hermes_value_get_number(col_val);

        // Validate coordinates
        if (std.math.isNan(row_f) or std.math.isInf(row_f) or row_f < 0 or
            std.math.isNan(col_f) or std.math.isInf(col_f) or col_f < 0)
        {
            c.hermes_value_destroy(row_val);
            c.hermes_value_destroy(col_val);
            c.hermes_value_destroy(char_val);
            c.hermes_value_destroy(cell_val);
            continue;
        }

        const row = @as(usize, @intFromFloat(row_f));
        const col = @as(usize, @intFromFloat(col_f));

        // Get character (could be number codepoint or string)
        var char: u21 = ' ';
        if (c.hermes_value_is_number(char_val)) {
            const char_f = c.hermes_value_get_number(char_val);
            if (!std.math.isNan(char_f) and !std.math.isInf(char_f) and char_f >= 0) {
                char = @intCast(@as(u32, @intFromFloat(char_f)));
            }
        } else if (c.hermes_value_is_string(char_val)) {
            var char_len: usize = 0;
            const char_ptr = c.hermes_value_get_string(runtime, char_val, &char_len);
            if (char_ptr != null and char_len > 0) {
                char = @intCast(char_ptr[0]);
            }
        }

        // Get optional fg/bg colors (null or hex number)
        var fg: ?Color = null;
        var bg: ?Color = null;

        const fg_val = c.hermes_value_get_property(runtime, cell_val, "fg");
        if (fg_val != null and !c.hermes_value_is_null(fg_val)) {
            if (c.hermes_value_is_number(fg_val)) {
                const fg_num = c.hermes_value_get_number(fg_val);
                if (!std.math.isNan(fg_num) and !std.math.isInf(fg_num)) {
                    const rgb: u24 = @intCast(@as(u32, @intFromFloat(fg_num)));
                    fg = Color{
                        .r = @intCast((rgb >> 16) & 0xFF),
                        .g = @intCast((rgb >> 8) & 0xFF),
                        .b = @intCast(rgb & 0xFF),
                    };
                }
            }
            c.hermes_value_destroy(fg_val);
        } else if (fg_val != null) {
            c.hermes_value_destroy(fg_val);
        }

        const bg_val = c.hermes_value_get_property(runtime, cell_val, "bg");
        if (bg_val != null and !c.hermes_value_is_null(bg_val)) {
            if (c.hermes_value_is_number(bg_val)) {
                const bg_num = c.hermes_value_get_number(bg_val);
                if (!std.math.isNan(bg_num) and !std.math.isInf(bg_num)) {
                    const rgb: u24 = @intCast(@as(u32, @intFromFloat(bg_num)));
                    bg = Color{
                        .r = @intCast((rgb >> 16) & 0xFF),
                        .g = @intCast((rgb >> 8) & 0xFF),
                        .b = @intCast(rgb & 0xFF),
                    };
                }
            }
            c.hermes_value_destroy(bg_val);
        } else if (bg_val != null) {
            c.hermes_value_destroy(bg_val);
        }

        // Set cell in layer grid
        layer.grid.setCell(row, col, Cell{ .char = char, .fg = fg, .bg = bg });

        // Cleanup
        c.hermes_value_destroy(row_val);
        c.hermes_value_destroy(col_val);
        c.hermes_value_destroy(char_val);
        c.hermes_value_destroy(cell_val);
    }

    // Mark layer as dirty to trigger re-composition
    layer.markDirty();

    // Mark that this animation frame modified layers (triggers re-render)
    // This is safe because renderVirtualText ALWAYS renders content
    animation_api.markLayersModified();

    // Debug: Log rendering (to debug log, not terminal)
    debug_log.log("[JSI] renderVirtualText('{s}') - rendered {d} cells, marked dirty", .{ name, length });

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: setLayerOpacity(name, opacity)
/// JavaScript: setLayerOpacity('my_layer', 0.5)
/// Updates layer opacity for fade effects
pub export fn setLayerOpacity(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 1: opacity (number)
    if (args[1] == null or !c.hermes_value_is_number(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opacity_f = c.hermes_value_get_number(args[1]);
    if (std.math.isNan(opacity_f) or std.math.isInf(opacity_f)) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opacity: f32 = @floatCast(opacity_f);

    // Get layer by name
    const layer = display.layer_manager.getLayerByName(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Update opacity
    layer.setOpacity(opacity);

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: clearLayer(name)
/// JavaScript: clearLayer('my_layer')
/// Clears layer content (keeps layer alive)
pub export fn clearLayer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Get layer by name
    const layer = display.layer_manager.getLayerByName(name) orelse {
        return c.hermes_value_create_undefined(runtime);
    };

    // Check if layer has actual content before clearing
    // This is critical to prevent flickering - don't mark dirty if clearing empty layer
    const had_content = layer.grid.hasContent();

    // Clear layer content
    layer.clear();

    // Only mark animation frame dirty if layer actually had content to clear
    // This prevents idle flickering when clearing already-empty layers
    if (had_content) {
        animation_api.markLayersModified();
        debug_log.log("[JSI] clearLayer('{s}') - had content, marked dirty", .{name});
    } else {
        debug_log.log("[JSI] clearLayer('{s}') - was empty, NOT marking dirty", .{name});
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: destroyLayer(name)
/// JavaScript: destroyLayer('my_layer')
/// Destroys layer and frees resources
pub export fn destroyLayer(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    const display = global_display orelse return c.hermes_value_create_undefined(runtime);

    if (count < 1) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: layer name (string)
    if (args[0] == null or !c.hermes_value_is_string(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[0], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Destroy layer via LayerManager
    display.layer_manager.destroyCustomLayer(name) catch {
        // Layer not found or cannot destroy core layer
        return c.hermes_value_create_undefined(runtime);
    };

    return c.hermes_value_create_undefined(runtime);
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.layer HostObject getter - routes property access to methods
pub export fn layerHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    _ = context; // Not used for layer API (uses global_display)
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Use StaticStringMap for O(1) property dispatch
    const PropertyMap = std.StaticStringMap(*const fn (
        ?*c.OVHermesRuntime,
        ?*anyopaque,
        [*c]?*c.OVHermesValue,
        usize,
    ) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "drawVirtualText", drawVirtualText },
        .{ "clearVirtualText", clearVirtualText },
        .{ "getViewportInfo", getViewportInfo },
        .{ "getGutterWidth", getGutterWidth },
        .{ "createLayer", createLayer },
        .{ "renderVirtualText", renderVirtualText },
        .{ "setLayerOpacity", setLayerOpacity },
        .{ "clearLayer", clearLayer },
        .{ "destroyLayer", destroyLayer },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, null);
}

/// vim.layer HostObject enumerator - returns array of method names
pub export fn layerHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "drawVirtualText",
        "clearVirtualText",
        "getViewportInfo",
        "getGutterWidth",
        "createLayer",
        "renderVirtualText",
        "setLayerOpacity",
        "clearLayer",
        "destroyLayer",
    };

    const arr = c.hermes_array_create(rt, method_names.len) orelse return null;

    for (method_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register layer API as HostObject (zero-copy, 3-5x faster)
/// JavaScript usage: vim.layer.createLayer('name', opts), vim.layer.renderVirtualText('name', cells)
pub fn register(runtime: *c.OVHermesRuntime, display: ?*Display) void {
    // Set global display
    global_display = display;

    c.hermes_register_host_object(
        runtime,
        "vimLayer",
        layerHostObjectGet,
        null, // No setter (read-only methods)
        layerHostObjectEnumerator,
        null, // Context not needed (uses global_display)
    );
}

/// Legacy registration (backwards compatibility)
/// TODO: Remove after all examples/tests updated
pub fn registerLegacy(runtime: *c.OVHermesRuntime, display: ?*Display) void {
    // Set global display
    global_display = display;

    c.hermes_register_host_function(
        runtime,
        "drawVirtualText",
        drawVirtualText,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "clearVirtualText",
        clearVirtualText,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "getViewportInfo",
        getViewportInfo,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "getGutterWidth",
        getGutterWidth,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "createLayer",
        createLayer,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "renderVirtualText",
        renderVirtualText,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "setLayerOpacity",
        setLayerOpacity,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "clearVirtualText",
        clearLayer,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "clearLayer",
        clearLayer,
        null,
    );

    c.hermes_register_host_function(
        runtime,
        "destroyLayer",
        destroyLayer,
        null,
    );
}
