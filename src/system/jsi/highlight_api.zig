/// Highlight API - vim.api.setHighlight() (Neovim-compatible)
/// Hybrid design: Neovim API + Helix optimizations
///
/// Architecture:
/// - API Layer: vim.api.setHighlight(ns, name, def) - Neovim-compatible
/// - Storage: HashMap (API calls) + Vec (tree-sitter O(1)) - Helix optimization
/// - Scope Fallback: "ui.text.focus" → "ui.text" → "ui" - Helix pattern
/// - Link Resolution: "@function" → "Function" → { fg: ... } - Neovim pattern
///
/// Usage:
///   vim.api.setHighlight(0, "Function", { fg: "#61AFEF", bold: true });
///   vim.api.setHighlight(0, "@function", { link: "Function" });
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

// ============================================================================
// Core Types
// ============================================================================

/// Color representation (terminal-compatible)
pub const Color = union(enum) {
    rgb: struct { r: u8, g: u8, b: u8 },
    indexed: u8, // ANSI 0-255

    /// Parse color from string
    /// Formats: "#ff0000" (hex), "124" (ANSI index)
    pub fn parse(str: []const u8) !Color {
        if (str.len == 0) return error.InvalidColor;

        if (str[0] == '#') {
            // Hex color: "#ff0000"
            if (str.len < 7) return error.InvalidColor;

            const r = try std.fmt.parseInt(u8, str[1..3], 16);
            const g = try std.fmt.parseInt(u8, str[3..5], 16);
            const b = try std.fmt.parseInt(u8, str[5..7], 16);

            return .{ .rgb = .{ .r = r, .g = g, .b = b } };
        } else {
            // ANSI index: "124"
            const idx = try std.fmt.parseInt(u8, str, 10);
            if (idx > 255) return error.InvalidColor;
            return .{ .indexed = idx };
        }
    }

    /// Convert to RGB (for terminal output)
    pub fn toRgb(self: Color) struct { r: u8, g: u8, b: u8 } {
        return switch (self) {
            .rgb => |rgb| .{ .r = rgb.r, .g = rgb.g, .b = rgb.b },
            .indexed => |idx| {
                // Convert ANSI to approximate RGB (256-color palette)
                // Simplified - real implementation would use full ANSI palette
                return .{ .r = idx, .g = idx, .b = idx };
            },
        };
    }
};

/// Text modifiers
pub const Modifiers = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    undercurl: bool = false,
    strikethrough: bool = false,
};

/// Renderable style (final computed style)
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    sp: ?Color = null, // Special (underline color)
    modifiers: Modifiers = .{},

    pub fn default() Style {
        return .{};
    }
};

/// Highlight definition (from API calls)
pub const HighlightDef = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    sp: ?Color = null,

    // Modifiers
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    undercurl: bool = false,
    strikethrough: bool = false,

    // Link to another group (Neovim pattern)
    link: ?[]const u8 = null,

    pub fn toStyle(self: HighlightDef) Style {
        return Style{
            .fg = self.fg,
            .bg = self.bg,
            .sp = self.sp,
            .modifiers = .{
                .bold = self.bold,
                .italic = self.italic,
                .underline = self.underline,
                .undercurl = self.undercurl,
                .strikethrough = self.strikethrough,
            },
        };
    }
};

// ============================================================================
// Highlight Registry (Dual Storage: HashMap + Vec)
// ============================================================================

/// Highlight registry with Helix optimizations
///
/// Design:
/// - HashMap: For API calls, UI scopes, fallback lookup
/// - Vec: For tree-sitter O(1) lookup by index (Helix optimization)
/// - Scope fallback: "ui.text.focus" → "ui.text" → "ui" (Helix pattern)
/// - Link resolution: "@function" → "Function" → style (Neovim pattern)
pub const HighlightRegistry = struct {
    allocator: Allocator,

    // HashMap storage (for API calls + fallback)
    highlights: std.StringHashMap(Style),
    links: std.StringHashMap([]const u8), // name → target

    // Vec storage (for tree-sitter O(1) lookup - HELIX OPTIMIZATION)
    scopes: std.ArrayList([]const u8), // index → scope name
    highlight_vec: std.ArrayList(Style), // index → style
    scope_to_index: std.StringHashMap(u32), // scope → index

    pub fn init(allocator: Allocator) HighlightRegistry {
        return .{
            .allocator = allocator,
            .highlights = std.StringHashMap(Style).init(allocator),
            .links = std.StringHashMap([]const u8).init(allocator),
            .scopes = std.ArrayList([]const u8){},
            .highlight_vec = std.ArrayList(Style){},
            .scope_to_index = std.StringHashMap(u32).init(allocator),
        };
    }

    /// Initialize default UI highlights (Neovim pattern)
    /// This sets up the basic highlight groups that are expected by the UI layer
    /// Call this immediately after init() to ensure UI has sensible defaults
    pub fn initDefaults(self: *HighlightRegistry) !void {
        // Default colors (similar to Neovim's defaults)
        const default_fg = Color{ .rgb = .{ .r = 0xAB, .g = 0xB2, .b = 0xBF } }; // Light gray
        const default_bg = Color{ .rgb = .{ .r = 0x1A, .g = 0x1B, .b = 0x26 } }; // Dark background
        const cursor_bg = Color{ .rgb = .{ .r = 0xAE, .g = 0xAF, .b = 0xAD } };  // Light gray cursor
        const cursorline_bg = Color{ .rgb = .{ .r = 0x1E, .g = 0x20, .b = 0x2F } }; // Subtle highlight
        const visual_bg = Color{ .rgb = .{ .r = 0x28, .g = 0x34, .b = 0x57 } };   // Blue tint
        const line_nr_fg = Color{ .rgb = .{ .r = 0x34, .g = 0x35, .b = 0x43 } };  // Dim gray
        const active_line_nr_fg = Color{ .rgb = .{ .r = 0x51, .g = 0xAF, .b = 0xEF } }; // Bright blue
        const invisible_fg = Color{ .rgb = .{ .r = 0x37, .g = 0x38, .b = 0x4F } };  // Very dim gray
        const yank_flash_bg = Color{ .rgb = .{ .r = 0x64, .g = 0x64, .b = 0x32 } }; // Yellow flash

        // Normal - base colors for text
        try self.set("Normal", .{ .fg = default_fg, .bg = default_bg });

        // Cursor - cursor block color
        try self.set("Cursor", .{ .bg = cursor_bg });

        // CursorLine - current line highlight
        try self.set("CursorLine", .{ .bg = cursorline_bg });

        // Visual - visual mode selection
        try self.set("Visual", .{ .bg = visual_bg });

        // Line numbers
        try self.set("LineNr", .{ .fg = line_nr_fg });
        try self.set("CursorLineNr", .{ .fg = active_line_nr_fg });

        // Whitespace/invisible characters (listchars)
        try self.set("Whitespace", .{ .fg = invisible_fg });
        try self.set("SpecialKey", .{ .fg = invisible_fg });
        try self.set("NonText", .{ .fg = invisible_fg });

        // Yank flash
        try self.set("YankFlash", .{ .bg = yank_flash_bg });
    }

    pub fn deinit(self: *HighlightRegistry) void {
        // Free owned strings (scopes shares pointers with highlights, don't free twice)
        var it = self.highlights.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }

        var link_it = self.links.iterator();
        while (link_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        // Don't free scopes items - they point to highlights keys (already freed above)

        self.highlights.deinit();
        self.links.deinit();
        self.scopes.deinit(self.allocator);
        self.highlight_vec.deinit(self.allocator);
        self.scope_to_index.deinit();
    }

    /// Set highlight (called by vim.api.setHighlight)
    pub fn set(self: *HighlightRegistry, name: []const u8, def: HighlightDef) !void {
        const name_copy = try self.allocator.dupe(u8, name);

        if (def.link) |link_target| {
            // Link to another group (Neovim pattern)
            const target_copy = try self.allocator.dupe(u8, link_target);

            // Remove old link if exists
            if (self.links.fetchRemove(name_copy)) |old| {
                self.allocator.free(old.key);
                self.allocator.free(old.value);
            }

            try self.links.put(name_copy, target_copy);
        } else {
            // Direct style definition
            const style = def.toStyle();

            // Remove old highlight if exists
            if (self.highlights.fetchRemove(name_copy)) |old| {
                // CRITICAL: Also remove from scope_to_index (pointer will be invalid)
                _ = self.scope_to_index.fetchRemove(old.key);
                self.allocator.free(old.key);
            }

            try self.highlights.put(name_copy, style);

            // Add to Vec if it's a syntax scope (for O(1) tree-sitter lookup)
            if (self.isSyntaxScope(name)) {
                // Check if already indexed (use name string comparison, not pointer)
                const existing_index_opt = blk: {
                    var it = self.scope_to_index.iterator();
                    while (it.next()) |entry| {
                        if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                            break :blk entry.value_ptr.*;
                        }
                    }
                    break :blk null;
                };

                if (existing_index_opt) |existing_index| {
                    // Update existing entry
                    self.highlight_vec.items[existing_index] = style;
                    try self.scope_to_index.put(name_copy, existing_index);
                } else {
                    // Add new entry
                    const index: u32 = @intCast(self.scopes.items.len);
                    try self.scopes.append(self.allocator, name_copy);
                    try self.highlight_vec.append(self.allocator, style);
                    try self.scope_to_index.put(name_copy, index);
                }
            }
        }
    }

    /// Get highlight by name with HELIX SCOPE FALLBACK
    ///
    /// Resolves links and falls back to parent scopes:
    /// "@function" → "Function" → { fg: ... }
    /// "ui.text.focus" → "ui.text" → "ui" → default
    pub fn get(self: *const HighlightRegistry, scope: []const u8) Style {
        var current = scope;
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        while (true) {
            // Prevent cycles
            if (visited.contains(current)) return Style.default();
            visited.put(current, {}) catch return Style.default();

            // Check if it's a link
            if (self.links.get(current)) |target| {
                current = target; // Follow link
                continue;
            }

            // Check direct definition
            if (self.highlights.get(current)) |style| {
                return style;
            }

            // HELIX SCOPE FALLBACK: "ui.text.focus" → "ui.text"
            if (std.mem.lastIndexOf(u8, current, ".")) |dot_pos| {
                current = current[0..dot_pos];
            } else {
                return Style.default();
            }
        }
    }

    /// Get highlight by index (O(1) for tree-sitter - HELIX OPTIMIZATION)
    pub fn getByIndex(self: *HighlightRegistry, index: u32) Style {
        if (index >= self.highlight_vec.items.len) return Style.default();
        return self.highlight_vec.items[index];
    }

    /// Get index for scope name (used during query compilation)
    pub fn getScopeIndex(self: *HighlightRegistry, scope: []const u8) ?u32 {
        return self.scope_to_index.get(scope);
    }

    /// Clear all highlights
    pub fn clear(self: *HighlightRegistry) void {
        // Free all owned strings
        var it = self.highlights.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }

        var link_it = self.links.iterator();
        while (link_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        // Don't free scopes items - they point to highlights keys (already freed above)

        self.highlights.clearRetainingCapacity();
        self.links.clearRetainingCapacity();
        self.scopes.clearRetainingCapacity(self.allocator);
        self.highlight_vec.clearRetainingCapacity(self.allocator);
        self.scope_to_index.clearRetainingCapacity();
    }

    fn isSyntaxScope(self: *HighlightRegistry, name: []const u8) bool {
        _ = self;

        // Tree-sitter captures start with @
        if (name.len > 0 and name[0] == '@') return true;

        // UI scopes (not syntax)
        if (std.mem.startsWith(u8, name, "ui.")) return false;

        // Traditional Vim groups (syntax)
        const vim_groups = [_][]const u8{
            "Comment",  "Constant", "String",     "Character", "Number",
            "Boolean",  "Float",    "Identifier", "Function",  "Statement",
            "Conditional", "Repeat", "Label",      "Operator",  "Keyword",
            "Exception", "PreProc", "Include",    "Define",    "Macro",
            "PreCondit", "Type",    "StorageClass", "Structure", "Typedef",
            "Special",  "SpecialChar", "Tag",      "Delimiter", "SpecialComment",
            "Debug",    "Underlined", "Ignore",    "Error",     "Todo",
        };

        for (vim_groups) |group| {
            if (std.mem.eql(u8, name, group)) return true;
        }

        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HighlightRegistry: basic set/get" {
    const allocator = std.testing.allocator;

    var registry = HighlightRegistry.init(allocator);
    defer registry.deinit();

    // Set direct style
    const def = HighlightDef{
        .fg = .{ .rgb = .{ .r = 0xFF, .g = 0x00, .b = 0x00 } },
        .bold = true,
    };
    try registry.set("Function", def);

    // Get style
    const style = registry.get("Function");
    try std.testing.expect(style.fg != null);
    try std.testing.expect(style.modifiers.bold);
}

test "HighlightRegistry: link resolution" {
    const allocator = std.testing.allocator;

    var registry = HighlightRegistry.init(allocator);
    defer registry.deinit();

    // Define base style
    try registry.set("Function", .{ .fg = .{ .rgb = .{ .r = 0xFF, .g = 0, .b = 0 } } });

    // Link to base
    try registry.set("@function", .{ .link = "Function" });

    // Should resolve to Function's style
    const style = registry.get("@function");
    try std.testing.expect(style.fg != null);
}

test "HighlightRegistry: scope fallback" {
    const allocator = std.testing.allocator;

    var registry = HighlightRegistry.init(allocator);
    defer registry.deinit();

    // Define parent scope
    try registry.set("ui.text", .{ .fg = .{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } } });

    // Child scope inherits
    const style = registry.get("ui.text.focus");
    try std.testing.expect(style.fg != null);
}

test "Color: parse hex" {
    const color = try Color.parse("#ff0000");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0xFF, .g = 0, .b = 0 } }, color);
}

test "Color: parse ANSI" {
    const color = try Color.parse("124");
    try std.testing.expectEqual(Color{ .indexed = 124 }, color);
}

// ============================================================================
// JSI Exports (JavaScript Bridge)
// ============================================================================

/// Context for highlight API (passed to all JSI functions)
pub const HighlightContext = struct {
    registry: *HighlightRegistry,
    allocator: Allocator,
    js_state_dirty: ?*bool = null, // Pointer to editor's dirty flag (null in some modes)
};

/// Zig host function: vim.api.setHighlight(ns_id, name, opts)
/// Called from JavaScript: vim.api.setHighlight(0, "Function", { fg: "#61AFEF", bold: true })
///
/// Arguments:
/// - ns_id (number): Namespace ID (0 for global, for future namespacing support)
/// - name (string): Highlight group name (e.g., "Function", "@function", "ui.text")
/// - opts (object): Highlight definition
///   - fg (string): Foreground color ("#ff0000" or "124")
///   - bg (string): Background color
///   - sp (string): Special color (underline)
///   - bold (boolean): Bold text
///   - italic (boolean): Italic text
///   - underline (boolean): Underline text
///   - undercurl (boolean): Curly underline
///   - strikethrough (boolean): Strikethrough text
///   - link (string): Link to another group (e.g., "Function")
pub export fn vimApiSetHighlight(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // Unwrap nullable runtime
    const runtime = runtime_nullable orelse return null;

    // Get context
    const ctx = @as(*HighlightContext, @ptrCast(@alignCast(context.?)));

    // Validate arguments: (ns_id, name, opts)
    if (arg_count < 3) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: namespace ID (number) - currently unused but required for Neovim compatibility
    if (args[0] == null or !c.hermes_value_is_number(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }
    // const ns_id = @as(i32, @intFromFloat(c.hermes_value_get_number(args[0])));

    // Arg 1: highlight group name (string)
    if (args[1] == null or !c.hermes_value_is_string(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[1], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }

    // IMPORTANT: Copy the name! hermes_value_get_string() uses a shared buffer
    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Arg 2: options object
    if (args[2] == null or !c.hermes_value_is_object(args[2])) {
        return c.hermes_value_create_undefined(runtime);
    }

    const opts = args[2].?;
    var def = HighlightDef{};

    // Helper function to get string property
    const getStringProp = struct {
        fn call(rt: *c.OVHermesRuntime, obj: *c.OVHermesValue, prop_name: [*:0]const u8) ?[]const u8 {
            const prop = c.hermes_value_get_property(rt, obj, prop_name) orelse return null;
            defer c.hermes_value_destroy(prop);

            if (!c.hermes_value_is_string(prop)) return null;

            var len: usize = 0;
            const ptr = c.hermes_value_get_string(rt, prop, &len);
            if (ptr == null) return null;

            return ptr[0..len];
        }
    }.call;

    // Helper function to get boolean property
    const getBoolProp = struct {
        fn call(rt: *c.OVHermesRuntime, obj: *c.OVHermesValue, prop_name: [*:0]const u8) bool {
            const prop = c.hermes_value_get_property(rt, obj, prop_name) orelse return false;
            defer c.hermes_value_destroy(prop);

            if (!c.hermes_value_is_boolean(prop)) return false;
            return c.hermes_value_get_boolean(prop);
        }
    }.call;

    // Parse color properties
    if (getStringProp(runtime, opts, "fg")) |fg_str| {
        def.fg = Color.parse(fg_str) catch null;
    }

    if (getStringProp(runtime, opts, "bg")) |bg_str| {
        def.bg = Color.parse(bg_str) catch null;
    }

    if (getStringProp(runtime, opts, "sp")) |sp_str| {
        def.sp = Color.parse(sp_str) catch null;
    }

    // Parse link property
    if (getStringProp(runtime, opts, "link")) |link_str| {
        // Need to allocate for link (stored in registry)
        def.link = ctx.allocator.dupe(u8, link_str) catch null;
    }

    // Parse modifier properties
    def.bold = getBoolProp(runtime, opts, "bold");
    def.italic = getBoolProp(runtime, opts, "italic");
    def.underline = getBoolProp(runtime, opts, "underline");
    def.undercurl = getBoolProp(runtime, opts, "undercurl");
    def.strikethrough = getBoolProp(runtime, opts, "strikethrough");

    // Apply highlight to registry
    ctx.registry.set(name, def) catch {
        // Free link allocation on error
        if (def.link) |link| {
            ctx.allocator.free(link);
        }
        return c.hermes_value_create_undefined(runtime);
    };

    // Free link allocation (registry made its own copy)
    if (def.link) |link| {
        ctx.allocator.free(link);
    }

    // Mark editor state as dirty to trigger render
    if (ctx.js_state_dirty) |dirty| {
        dirty.* = true;
    }

    return c.hermes_value_create_undefined(runtime);
}

/// Zig host function: vim.api.getHighlight(ns_id, name)
/// Called from JavaScript: vim.api.getHighlight(0, "Function")
///
/// Returns: object with highlight properties or undefined if not found
pub export fn vimApiGetHighlight(
    runtime_nullable: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const runtime = runtime_nullable orelse return null;
    const ctx = @as(*HighlightContext, @ptrCast(@alignCast(context.?)));

    // Validate arguments: (ns_id, name)
    if (arg_count < 2) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 0: namespace ID (number)
    if (args[0] == null or !c.hermes_value_is_number(args[0])) {
        return c.hermes_value_create_undefined(runtime);
    }

    // Arg 1: highlight group name (string)
    if (args[1] == null or !c.hermes_value_is_string(args[1])) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_len: usize = 0;
    const name_ptr = c.hermes_value_get_string(runtime, args[1], &name_len);
    if (name_ptr == null) {
        return c.hermes_value_create_undefined(runtime);
    }

    var name_buf: [256]u8 = undefined;
    if (name_len >= name_buf.len) return c.hermes_value_create_undefined(runtime);
    @memcpy(name_buf[0..name_len], name_ptr[0..name_len]);
    const name = name_buf[0..name_len];

    // Get style from registry (with fallback resolution)
    const style = ctx.registry.get(name);

    // Create JavaScript object with style properties
    const obj = c.hermes_value_create_object(runtime);

    // Helper to create color string
    const createColorString = struct {
        fn call(alloc: Allocator, color: Color) ![]const u8 {
            const rgb = color.toRgb();
            return std.fmt.allocPrint(alloc, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
        }
    }.call;

    // Set fg property
    if (style.fg) |fg| {
        const fg_str = createColorString(ctx.allocator, fg) catch return obj;
        defer ctx.allocator.free(fg_str);
        const fg_val = c.hermes_value_create_string(runtime, fg_str.ptr, fg_str.len);
        c.hermes_value_set_property(runtime, obj, "fg", fg_val);
        c.hermes_value_destroy(fg_val);
    }

    // Set bg property
    if (style.bg) |bg| {
        const bg_str = createColorString(ctx.allocator, bg) catch return obj;
        defer ctx.allocator.free(bg_str);
        const bg_val = c.hermes_value_create_string(runtime, bg_str.ptr, bg_str.len);
        c.hermes_value_set_property(runtime, obj, "bg", bg_val);
        c.hermes_value_destroy(bg_val);
    }

    // Set sp property
    if (style.sp) |sp| {
        const sp_str = createColorString(ctx.allocator, sp) catch return obj;
        defer ctx.allocator.free(sp_str);
        const sp_val = c.hermes_value_create_string(runtime, sp_str.ptr, sp_str.len);
        c.hermes_value_set_property(runtime, obj, "sp", sp_val);
        c.hermes_value_destroy(sp_val);
    }

    // Set modifier properties
    if (style.modifiers.bold) {
        const val = c.hermes_value_create_boolean(runtime, true);
        c.hermes_value_set_property(runtime, obj, "bold", val);
        c.hermes_value_destroy(val);
    }

    if (style.modifiers.italic) {
        const val = c.hermes_value_create_boolean(runtime, true);
        c.hermes_value_set_property(runtime, obj, "italic", val);
        c.hermes_value_destroy(val);
    }

    if (style.modifiers.underline) {
        const val = c.hermes_value_create_boolean(runtime, true);
        c.hermes_value_set_property(runtime, obj, "underline", val);
        c.hermes_value_destroy(val);
    }

    if (style.modifiers.undercurl) {
        const val = c.hermes_value_create_boolean(runtime, true);
        c.hermes_value_set_property(runtime, obj, "undercurl", val);
        c.hermes_value_destroy(val);
    }

    if (style.modifiers.strikethrough) {
        const val = c.hermes_value_create_boolean(runtime, true);
        c.hermes_value_set_property(runtime, obj, "strikethrough", val);
        c.hermes_value_destroy(val);
    }

    return obj;
}

// ============================================================================
// Registration
// ============================================================================

/// Register highlight API functions with Hermes runtime
/// JavaScript usage: vim.api.setHighlight(0, "Function", { fg: "#61AFEF" })
pub fn register(runtime: *c.OVHermesRuntime, ctx: *HighlightContext) void {
    c.hermes_register_host_function(
        runtime,
        "vimApiSetHighlight",
        vimApiSetHighlight,
        @ptrCast(ctx),
    );

    c.hermes_register_host_function(
        runtime,
        "vimApiGetHighlight",
        vimApiGetHighlight,
        @ptrCast(ctx),
    );
}
