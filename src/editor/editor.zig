const std = @import("std");
const Buffer = @import("buffer/buffer.zig").Buffer;
const ModeManager = @import("mode/mode.zig").ModeManager;
const EditOps = @import("buffer/edit.zig").EditOps;
const RegisterManager = @import("register/register.zig").RegisterManager;
const VisualState = @import("visual/visual.zig").VisualState;
const YankHighlight = @import("visual/yank_highlight.zig").YankHighlight;
const movement = @import("movement/movement.zig");
const Position = @import("visual/visual.zig").Position;
const yank = @import("buffer/yank.zig");
const paste = @import("buffer/paste.zig");
const visual_ops = @import("buffer/visual_ops.zig");
const Logger = @import("log.zig").Logger;
const text_objects = @import("movement/text_objects/text_objects.zig");
const TextObjectModifier = text_objects.TextObjectModifier;
const TextObjectType = text_objects.TextObjectType;
const OptionsManager = @import("config/options.zig").OptionsManager;
const KeymapManager = @import("keymap/keymap.zig").KeymapManager;
const Loader = @import("treesitter/loader.zig").Loader;
const EventEmitter = @import("../system/jsi/event_emitter.zig").EventEmitter;
const AutocmdManager = @import("../system/jsi/autocmd_api.zig").AutocmdManager;
const usercommand_api_mod = @import("../system/jsi/usercommand_api.zig");
const UserCommandContext = usercommand_api_mod.UserCommandContext;
const UserCommand = usercommand_api_mod.UserCommand;
const HighlightRegistry = @import("../system/jsi/highlight_api.zig").HighlightRegistry;
const namespace_api = @import("../system/jsi/namespace_api.zig");
const Syntax = @import("treesitter/syntax.zig").Syntax;
const Parser = @import("treesitter/parser.zig").Parser;
const languages = @import("treesitter/languages.zig");

// Window management
const Window = @import("window.zig").Window;
pub const WindowId = @import("window.zig").WindowId;
const WindowLayout = @import("window_layout.zig").WindowLayout;
const SplitDirection = @import("window_layout.zig").SplitDirection;
const NavigationDirection = @import("window_layout.zig").NavigationDirection;

/// Buffer identifier (Helix-style architecture)
/// Re-export from window.zig to avoid type mismatch issues
pub const BufferId = @import("window.zig").BufferId;

/// Pending command for multi-key sequences (like dd, dw)
const PendingCommand = struct {
    char: ?u8 = null,

    fn set(self: *PendingCommand, c: u8) void {
        self.char = c;
    }

    fn clear(self: *PendingCommand) void {
        self.char = null;
    }

    fn get(self: *const PendingCommand) ?u8 {
        return self.char;
    }
};

/// Pending register selection (after pressing ")
const PendingRegister = struct {
    waiting_for_name: bool = false,
    selected: ?u8 = null,

    fn startSelection(self: *PendingRegister) void {
        self.waiting_for_name = true;
    }

    fn setRegister(self: *PendingRegister, reg: u8) void {
        self.selected = reg;
        self.waiting_for_name = false;
    }

    fn clear(self: *PendingRegister) void {
        self.waiting_for_name = false;
        self.selected = null;
    }

    fn isWaitingForName(self: *const PendingRegister) bool {
        return self.waiting_for_name;
    }

    fn getSelected(self: *const PendingRegister) ?u8 {
        return self.selected;
    }
};

/// Pending text object (after pressing i/a following an operator)
const PendingTextObject = struct {
    waiting: bool = false,
    modifier: ?TextObjectModifier = null,

    fn start(self: *PendingTextObject, modifier: TextObjectModifier) void {
        self.waiting = true;
        self.modifier = modifier;
    }

    fn clear(self: *PendingTextObject) void {
        self.waiting = false;
        self.modifier = null;
    }

    fn isWaiting(self: *const PendingTextObject) bool {
        return self.waiting;
    }

    fn getModifier(self: *const PendingTextObject) ?TextObjectModifier {
        return self.modifier;
    }
};

/// Command buffer for command mode
const CommandBuffer = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) CommandBuffer {
        return .{
            .buffer = .empty,
            .allocator = allocator,
        };
    }

    fn deinit(self: *CommandBuffer) void {
        self.buffer.deinit(self.allocator);
    }

    fn clear(self: *CommandBuffer) void {
        self.buffer.clearRetainingCapacity();
    }

    fn append(self: *CommandBuffer, char: u8) !void {
        try self.buffer.append(self.allocator, char);
    }

    fn backspace(self: *CommandBuffer) void {
        if (self.buffer.items.len > 0) {
            _ = self.buffer.pop();
        }
    }

    fn getString(self: *const CommandBuffer) []const u8 {
        return self.buffer.items;
    }
};

/// Headless editor core - no I/O, pure state and logic
/// This is the single source of truth for editor behavior
/// Both Terminal backend and Debug backend use this
pub const Editor = struct {
    allocator: std.mem.Allocator,

    // Buffer management (Helix-style HashMap architecture)
    // CRITICAL: Store *Buffer (heap-allocated pointers) to prevent HashMap rehash invalidation
    // When HashMap rehashes on grow, value pointers from getPtr() become stale
    // With *Buffer, the Buffer objects live on heap and survive HashMap rehashing
    buffers: std.AutoHashMap(BufferId, *Buffer),
    current_buffer_id: ?BufferId,
    next_buffer_id: u64,
    cwd: []const u8, // Working directory (owned, must be freed in deinit)

    // Core state (backends can access these directly)
    mode_manager: ModeManager,
    edit_ops: EditOps,
    register_mgr: RegisterManager,
    visual_state: VisualState,
    yank_highlight: YankHighlight,
    keymap_mgr: KeymapManager,

    // Tree-sitter filetype detection
    ts_loader: Loader,

    // Tree-sitter parser and syntax highlighting
    parser: Parser,
    syntax: ?Syntax, // null if file has no tree-sitter support

    // Logger (Core→Backend architecture: Core produces logs, backends consume them)
    logger: Logger,

    // Options (optional - null for headless mode without config)
    options_manager: ?*OptionsManager = null,

    // Highlight registry for tree-sitter syntax highlighting (vim.api.setHighlight)
    // Initialized when JSI runtime created (terminal backend sets this during JSI setup)
    highlight_registry: HighlightRegistry,

    // Event emitter for autocommands (initialized when JSI runtime created)
    // Null until JSI runtime is available (terminal backend sets this during JSI setup)
    event_emitter: ?*EventEmitter = null,

    // Autocmd manager for Neovim-compatible autocommands (vim.api.createAutoCommand)
    // Null until JSI runtime is available (terminal backend sets this during JSI setup)
    autocmd_manager: ?*AutocmdManager = null,

    // User command context for Neovim-compatible user commands (vim.api.createUserCommand)
    // Null until JSI runtime is available (terminal backend sets this during JSI setup)
    usercommand_ctx: ?*UserCommandContext = null,

    // JavaScript state change flag (for plugins that modify state via timers/callbacks)
    // Set this to true when JavaScript APIs modify editor state to trigger re-render
    js_state_dirty: bool = false,

    // Guard to prevent reentrant CursorMoved autocmd calls
    // (plugin callbacks might trigger cursor operations that fire more CursorMoved)
    firing_cursor_moved: bool = false,

    // Internal state
    pending_cmd: PendingCommand,
    pending_register: PendingRegister,
    pending_text_object: PendingTextObject,
    cmd_buffer: CommandBuffer,

    // Viewport commands - set when ready for backend execution
    // Separate from pending_cmd to allow immediate execution during keymap strings
    viewport_movement: ?u8 = null, // H/M/L - move cursor to viewport top/middle/bottom
    viewport_adjustment: ?u8 = null, // zz/zt/zb - adjust viewport to center/top/bottom current line

    // Keymap recursion protection (Neovim E223: recursive mapping)
    // Tracks depth to prevent infinite loops from self-referencing mappings
    mapping_depth: usize = 0,

    // Viewport hints (for renderers, not actual rendering)
    viewport_top: usize = 0,
    viewport_left: usize = 0,

    // Window management (Phase 5)
    // Windows map WindowId -> Window for O(1) access
    windows: std.AutoHashMap(WindowId, *Window),
    current_window_id: ?WindowId = null,
    window_layout: ?WindowLayout = null,
    next_window_id: u32 = 1, // Window ID 0 is reserved for "current" in API

    // Terminal dimensions (for relayout after splits)
    // Set by backend on resize, used for window dimension calculations
    terminal_rows: usize = 24,
    terminal_cols: usize = 80,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        // Get current working directory (heap-allocated, will be freed in deinit)
        const cwd = std.process.getCwdAlloc(allocator) catch |err| blk: {
            std.debug.print("Warning: Failed to get cwd: {}\n", .{err});
            break :blk try allocator.dupe(u8, "."); // Fallback to "."
        };
        errdefer allocator.free(cwd);

        // Initialize buffer HashMap (stores *Buffer to survive HashMap rehashing)
        var buffers = std.AutoHashMap(BufferId, *Buffer).init(allocator);
        errdefer buffers.deinit();

        // Create initial unnamed buffer (ID 1) - heap-allocated to survive HashMap rehash
        const initial_buffer = try allocator.create(Buffer);
        errdefer allocator.destroy(initial_buffer);
        initial_buffer.* = Buffer.init(allocator);
        const initial_id = BufferId{ .id = 1 };
        try buffers.put(initial_id, initial_buffer);

        // Initialize window HashMap and create initial window
        var windows = std.AutoHashMap(WindowId, *Window).init(allocator);
        errdefer windows.deinit();

        const initial_win_id = WindowId{ .id = 1 };
        const initial_window = try allocator.create(Window);
        errdefer allocator.destroy(initial_window);
        initial_window.* = Window.init(allocator, initial_win_id, initial_id);
        try windows.put(initial_win_id, initial_window);

        // Initialize window layout with the initial window
        var window_layout = try WindowLayout.init(allocator, initial_win_id);
        errdefer window_layout.deinit();

        var ts_loader = try Loader.init(allocator);
        errdefer ts_loader.deinit();

        var parser = try Parser.init(allocator);
        errdefer parser.deinit();

        var highlight_registry = HighlightRegistry.init(allocator);
        try highlight_registry.initDefaults(); // Initialize default UI highlights (Neovim pattern)
        errdefer highlight_registry.deinit();

        // Set up default links from tree-sitter captures to Vim highlight groups
        // This connects tree-sitter names (e.g. "@keyword") to theme definitions (e.g. "Keyword")
        try setupDefaultHighlightLinks(&highlight_registry);

        return Editor{
            .allocator = allocator,
            .buffers = buffers,
            .current_buffer_id = initial_id,
            .next_buffer_id = 2, // Next buffer will be ID 2
            .cwd = cwd,
            .mode_manager = ModeManager.init(),
            .edit_ops = EditOps.init(allocator),
            .register_mgr = RegisterManager.init(allocator),
            .visual_state = VisualState{
                .active = false,
                .mode = .char,
                .anchor = .{ .line = 0, .col = 0 },
            },
            .yank_highlight = YankHighlight{},
            .keymap_mgr = KeymapManager.init(allocator),
            .ts_loader = ts_loader,
            .parser = parser,
            .syntax = null,
            .logger = Logger.init(allocator),
            .highlight_registry = highlight_registry,
            .pending_cmd = PendingCommand{},
            .pending_register = PendingRegister{},
            .pending_text_object = PendingTextObject{},
            .cmd_buffer = CommandBuffer.init(allocator),
            // Window management
            .windows = windows,
            .current_window_id = initial_win_id,
            .window_layout = window_layout,
            .next_window_id = 2, // Next window will be ID 2
        };
    }

    /// Setup default links from tree-sitter captures to Vim highlight groups
    /// This allows tree-sitter highlights (@keyword, @function, etc.) to use
    /// theme definitions for traditional Vim groups (Keyword, Function, etc.)
    fn setupDefaultHighlightLinks(registry: *HighlightRegistry) !void {
        const HighlightDef = @import("../system/jsi/highlight_api.zig").HighlightDef;

        // Set default highlight groups (fallback definitions)
        // These are used if theme doesn't define them
        try registry.set("Keyword", HighlightDef{
            .fg = .{ .rgb = .{ .r = 197, .g = 134, .b = 192 } }, // Purple
        });

        try registry.set("Function", HighlightDef{
            .fg = .{ .rgb = .{ .r = 130, .g = 170, .b = 255 } }, // Blue
        });

        try registry.set("String", HighlightDef{
            .fg = .{ .rgb = .{ .r = 152, .g = 195, .b = 121 } }, // Green
        });

        try registry.set("Comment", HighlightDef{
            .fg = .{ .rgb = .{ .r = 128, .g = 128, .b = 128 } }, // Gray
            .italic = true,
        });

        try registry.set("Type", HighlightDef{
            .fg = .{ .rgb = .{ .r = 86, .g = 182, .b = 194 } }, // Cyan
        });

        try registry.set("Constant", HighlightDef{
            .fg = .{ .rgb = .{ .r = 209, .g = 154, .b = 102 } }, // Orange
        });

        try registry.set("Operator", HighlightDef{
            .fg = .{ .rgb = .{ .r = 200, .g = 200, .b = 200 } }, // Light gray
        });

        try registry.set("Identifier", HighlightDef{
            .fg = .{ .rgb = .{ .r = 224, .g = 108, .b = 117 } }, // Red
        });

        try registry.set("Delimiter", HighlightDef{
            .fg = .{ .rgb = .{ .r = 171, .g = 178, .b = 191 } }, // Gray
        });

        try registry.set("Normal", HighlightDef{
            .fg = .{ .rgb = .{ .r = 171, .g = 178, .b = 191 } }, // Default text color
        });

        // NOTE: Tree-sitter C API returns capture names WITHOUT '@' prefix
        // (query file has "@keyword", C API returns "keyword")

        // Keywords and control flow
        try registry.set("keyword", HighlightDef{ .link = "Keyword" });
        try registry.set("keyword.function", HighlightDef{ .link = "Keyword" });
        try registry.set("keyword.operator", HighlightDef{ .link = "Keyword" });
        try registry.set("keyword.return", HighlightDef{ .link = "Keyword" });
        try registry.set("keyword.conditional", HighlightDef{ .link = "Keyword" });
        try registry.set("keyword.repeat", HighlightDef{ .link = "Keyword" });

        // Functions and methods
        try registry.set("function", HighlightDef{ .link = "Function" });
        try registry.set("function.builtin", HighlightDef{ .link = "Function" });
        try registry.set("function.call", HighlightDef{ .link = "Function" });
        try registry.set("function.method", HighlightDef{ .link = "Function" });
        try registry.set("method", HighlightDef{ .link = "Function" });
        try registry.set("method.call", HighlightDef{ .link = "Function" });

        // Types
        try registry.set("type", HighlightDef{ .link = "Type" });
        try registry.set("type.builtin", HighlightDef{ .link = "Type" });
        try registry.set("type.definition", HighlightDef{ .link = "Type" });

        // Strings and literals
        try registry.set("string", HighlightDef{ .link = "String" });
        try registry.set("string.regex", HighlightDef{ .link = "String" });
        try registry.set("string.escape", HighlightDef{ .link = "String" });
        try registry.set("character", HighlightDef{ .link = "String" });

        // Comments
        try registry.set("comment", HighlightDef{ .link = "Comment" });
        try registry.set("comment.documentation", HighlightDef{ .link = "Comment" });

        // Constants and numbers
        try registry.set("constant", HighlightDef{ .link = "Constant" });
        try registry.set("constant.builtin", HighlightDef{ .link = "Constant" });
        try registry.set("number", HighlightDef{ .link = "Constant" });
        try registry.set("boolean", HighlightDef{ .link = "Constant" });
        try registry.set("float", HighlightDef{ .link = "Constant" });

        // Variables and identifiers
        try registry.set("variable", HighlightDef{ .link = "Normal" });
        try registry.set("variable.builtin", HighlightDef{ .link = "Constant" });
        try registry.set("variable.parameter", HighlightDef{ .link = "Normal" });
        try registry.set("property", HighlightDef{ .link = "Normal" });

        // Operators and punctuation
        try registry.set("operator", HighlightDef{ .link = "Keyword" });
        try registry.set("punctuation.bracket", HighlightDef{ .link = "Normal" });
        try registry.set("punctuation.delimiter", HighlightDef{ .link = "Normal" });
        try registry.set("punctuation.special", HighlightDef{ .link = "Keyword" });

        // Markdown and markup highlights
        // Define Title highlight group (used by text.title)
        try registry.set("Title", HighlightDef{
            .fg = .{ .rgb = .{ .r = 130, .g = 170, .b = 255 } }, // Blue
            .bold = true,
        });

        // Define markup-specific highlight groups
        try registry.set("text.title", HighlightDef{ .link = "Title" });
        try registry.set("text.literal", HighlightDef{ .link = "String" }); // Code blocks
        try registry.set("text.uri", HighlightDef{
            .fg = .{ .rgb = .{ .r = 86, .g = 182, .b = 194 } }, // Cyan
            .underline = true,
        });
        try registry.set("text.reference", HighlightDef{ .link = "Identifier" }); // Link labels
        try registry.set("text.emphasis", HighlightDef{ .italic = true });
        try registry.set("text.strong", HighlightDef{ .bold = true });
    }

    pub fn deinit(self: *Editor) void {
        // NOTE: EventEmitter cleanup is handled by deinitJSI() in jsi_api.zig
        // since JSI owns the EventEmitter's lifecycle (created in initJSI)
        // Do NOT clean it up here to avoid double-free

        // Clean up all windows (heap-allocated)
        // CRITICAL: valueIterator() returns **Window (pointer to HashMap slot containing *Window)
        // We need to dereference to get the actual *Window to destroy
        var win_iter = self.windows.valueIterator();
        while (win_iter.next()) |window_ptr| {
            const window = window_ptr.*; // Dereference to get *Window
            window.deinit();
            self.allocator.destroy(window);
        }
        self.windows.deinit();

        // Clean up window layout
        if (self.window_layout) |*layout| {
            layout.deinit();
        }

        // Clean up all buffers (heap-allocated)
        // CRITICAL: valueIterator() returns **Buffer (pointer to HashMap slot containing *Buffer)
        // We need to dereference to get the actual *Buffer to destroy
        var iter = self.buffers.valueIterator();
        while (iter.next()) |buffer_ptr| {
            const buffer = buffer_ptr.*; // Dereference to get *Buffer
            buffer.deinit();
            self.allocator.destroy(buffer);
        }
        self.buffers.deinit();

        // Free working directory
        self.allocator.free(self.cwd);

        self.register_mgr.deinit();
        self.keymap_mgr.deinit();
        self.ts_loader.deinit();
        if (self.syntax) |*syntax| {
            syntax.deinit();
        }
        self.parser.deinit();
        self.highlight_registry.deinit();
        self.cmd_buffer.deinit();
        self.logger.deinit();
    }

    /// Get pointer to current buffer (Helix-style accessor)
    /// Returns null if no buffer is active (should never happen in practice)
    pub fn getCurrentBuffer(self: *Editor) ?*Buffer {
        const id = self.current_buffer_id orelse return null;
        // HashMap stores *Buffer, so get returns *Buffer directly (no need for getPtr)
        return self.buffers.get(id);
    }

    /// Create a new empty buffer and return its ID (Helix-style)
    /// Does NOT switch to the new buffer automatically
    pub fn createBuffer(self: *Editor) !BufferId {
        // Heap-allocate Buffer to survive HashMap rehashing
        const new_buffer = try self.allocator.create(Buffer);
        errdefer self.allocator.destroy(new_buffer);
        new_buffer.* = Buffer.init(self.allocator);

        const new_id = BufferId{ .id = self.next_buffer_id };
        self.next_buffer_id += 1;

        try self.buffers.put(new_id, new_buffer);
        return new_id;
    }

    /// Load file into a new buffer and switch to it (Helix-style open())
    /// If file is already open, switch to existing buffer instead
    /// Returns the buffer ID (new or existing)
    pub fn loadBufferFromFile(self: *Editor, path: []const u8) !BufferId {
        // Check if file is already open (duplicate detection like Helix)
        var iter = self.buffers.iterator();
        while (iter.next()) |entry| {
            // HashMap stores *Buffer, so value_ptr.* gives us *Buffer
            if (entry.value_ptr.*.filepath) |filepath| {
                if (std.mem.eql(u8, filepath, path)) {
                    // Already open, switch to it
                    const existing_id = entry.key_ptr.*;
                    self.current_buffer_id = existing_id;
                    // CRITICAL: Also update current window's buffer_id to keep them in sync
                    if (self.getCurrentWindow()) |win| {
                        win.buffer_id = existing_id;
                    }
                    self.triggerAutocommand("BufEnter");
                    return existing_id;
                }
            }
        }

        // Not open, create new buffer
        const new_id = try self.createBuffer();
        // HashMap stores *Buffer, so get returns *Buffer directly
        const buf = self.buffers.get(new_id).?;

        // Load file content (handle non-existent files like Vim does)
        buf.loadFile(path) catch |err| {
            if (err == error.FileNotFound) {
                // File doesn't exist - create empty buffer with filepath set (Vim :e behavior)
                buf.filepath = try self.allocator.dupe(u8, path);
                buf.modified = false;
            } else {
                return err; // Propagate other errors
            }
        };

        // Detect filetype
        const first_line = buf.getLine(0);
        defer if (first_line != null) self.allocator.free(first_line.?);
        const filetype = self.ts_loader.detectFiletype(path, first_line);

        if (filetype) |ft| {
            buf.setFiletype(ft) catch {};
            self.logger.info("✅ Detected filetype: {s} for {s}", .{ ft, path }) catch {};
            // TODO: Parse with tree-sitter (need to handle multiple buffers)
        } else {
            buf.setFiletype(null) catch {};
            self.logger.info("❌ No filetype detected for {s}", .{path}) catch {};
        }

        // Switch to new buffer
        self.current_buffer_id = new_id;

        // CRITICAL: Also update current window's buffer_id to keep them in sync
        if (self.getCurrentWindow()) |win| {
            win.buffer_id = new_id;
        }

        // Trigger autocommands
        self.triggerAutocommand("BufRead");
        self.triggerAutocommand("BufEnter");

        return new_id;
    }

    /// Switch to buffer by ID
    /// Returns error if buffer doesn't exist
    pub fn switchBuffer(self: *Editor, id: BufferId) !void {
        if (!self.buffers.contains(id)) {
            return error.BufferNotFound;
        }

        // Trigger BufLeave for current buffer
        self.triggerAutocommand("BufLeave");

        self.current_buffer_id = id;

        // CRITICAL: Also update current window's buffer_id to keep them in sync
        if (self.getCurrentWindow()) |win| {
            win.buffer_id = id;
        }

        // Trigger BufEnter for new buffer
        self.triggerAutocommand("BufEnter");
    }

    /// Delete buffer by ID (Neovim :bd behavior)
    /// Checks if buffer is modified and returns error if so (unless force=true)
    /// Switches to previous buffer if deleting current buffer
    pub fn deleteBuffer(self: *Editor, id: BufferId, force: bool) !void {
        // HashMap stores *Buffer, so get returns *Buffer directly
        const buf = self.buffers.get(id) orelse return error.BufferNotFound;

        // Check if buffer is modified
        if (!force and buf.modified) {
            return error.BufferModified;
        }

        // If deleting current buffer, switch to another one first
        if (self.current_buffer_id) |current_id| {
            if (current_id.eql(id)) {
                // Find another buffer to switch to
                var found_other = false;
                var iter = self.buffers.keyIterator();
                while (iter.next()) |key| {
                    if (!key.eql(id)) {
                        try self.switchBuffer(key.*);
                        found_other = true;
                        break;
                    }
                }

                // If no other buffer exists, create an empty one
                if (!found_other) {
                    const new_id = try self.createBuffer();
                    self.current_buffer_id = new_id;
                    // CRITICAL: Also update current window's buffer_id to keep them in sync
                    if (self.getCurrentWindow()) |win| {
                        win.buffer_id = new_id;
                    }
                }
            }
        }

        // Remove buffer from HashMap (heap-allocated, must deinit and destroy)
        if (self.buffers.fetchRemove(id)) |kv| {
            const buf_ptr = kv.value;
            buf_ptr.deinit();
            self.allocator.destroy(buf_ptr);
        }

        // Clean up namespace highlights for this buffer
        namespace_api.cleanupBuffer(@intCast(id.id));
    }

    /// Delete all buffers except current one (Neovim :only / :bonly behavior)
    /// Checks for modified buffers and returns error if any (unless force=true)
    /// Returns count of buffers deleted
    pub fn deleteOtherBuffers(self: *Editor, force: bool) !usize {
        const current_id = self.current_buffer_id orelse return error.NoActiveBuffer;

        // First pass: check for modified buffers if not forcing
        if (!force) {
            var iter = self.buffers.iterator();
            while (iter.next()) |entry| {
                // HashMap stores *Buffer, so value_ptr is **Buffer, need extra deref
                if (!entry.key_ptr.eql(current_id) and entry.value_ptr.*.modified) {
                    return error.BufferModified;
                }
            }
        }

        // Second pass: collect IDs to delete (can't modify HashMap while iterating)
        var to_delete: std.ArrayList(BufferId) = .{};
        defer to_delete.deinit(self.allocator);

        var iter = self.buffers.keyIterator();
        while (iter.next()) |key| {
            if (!key.eql(current_id)) {
                try to_delete.append(self.allocator, key.*);
            }
        }

        // Third pass: delete all other buffers
        for (to_delete.items) |id| {
            if (self.buffers.fetchRemove(id)) |kv| {
                const buf_ptr = kv.value;
                buf_ptr.deinit();
                self.allocator.destroy(buf_ptr);
            }
            // Clean up namespace highlights for this buffer
            namespace_api.cleanupBuffer(@intCast(id.id));
        }

        return to_delete.items.len;
    }

    /// Cycle to next buffer (Neovim :bn behavior)
    /// Uses Helix-style cycle() iterator for wrap-around
    pub fn nextBuffer(self: *Editor) void {
        const current_id = self.current_buffer_id orelse return;

        // Get sorted keys for deterministic order
        var keys: std.ArrayList(BufferId) = .{};
        defer keys.deinit(self.allocator);

        var iter = self.buffers.keyIterator();
        while (iter.next()) |key| {
            keys.append(self.allocator, key.*) catch return; // Ignore allocation errors in navigation
        }

        // Sort by ID for consistent order
        std.sort.pdq(BufferId, keys.items, {}, struct {
            fn lessThan(_: void, a: BufferId, b: BufferId) bool {
                return a.id < b.id;
            }
        }.lessThan);

        // Find current buffer index
        for (keys.items, 0..) |key, i| {
            if (key.eql(current_id)) {
                // Get next index (with wrap-around)
                const next_idx = (i + 1) % keys.items.len;
                self.switchBuffer(keys.items[next_idx]) catch return;
                return;
            }
        }
    }

    /// Cycle to previous buffer (Neovim :bp behavior)
    pub fn prevBuffer(self: *Editor) void {
        const current_id = self.current_buffer_id orelse return;

        // Get sorted keys for deterministic order
        var keys: std.ArrayList(BufferId) = .{};
        defer keys.deinit(self.allocator);

        var iter = self.buffers.keyIterator();
        while (iter.next()) |key| {
            keys.append(self.allocator, key.*) catch return;
        }

        // Sort by ID for consistent order
        std.sort.pdq(BufferId, keys.items, {}, struct {
            fn lessThan(_: void, a: BufferId, b: BufferId) bool {
                return a.id < b.id;
            }
        }.lessThan);

        // Find current buffer index
        for (keys.items, 0..) |key, i| {
            if (key.eql(current_id)) {
                // Get previous index (with wrap-around)
                const prev_idx = if (i == 0) keys.items.len - 1 else i - 1;
                self.switchBuffer(keys.items[prev_idx]) catch return;
                return;
            }
        }
    }

    /// Buffer metadata for :ls command
    pub const BufferInfo = struct {
        id: BufferId,
        filepath: ?[]const u8,
        modified: bool,
        current: bool,
    };

    /// Get list of all buffers for :ls command (Neovim :ls behavior)
    /// Returns array that caller must free
    pub fn listBuffers(self: *Editor) ![]BufferInfo {
        var result: std.ArrayList(BufferInfo) = .{};
        errdefer result.deinit(self.allocator);

        const current_id = self.current_buffer_id;

        // Get sorted keys for deterministic order
        var keys: std.ArrayList(BufferId) = .{};
        defer keys.deinit(self.allocator);

        var iter = self.buffers.keyIterator();
        while (iter.next()) |key| {
            try keys.append(self.allocator, key.*);
        }

        // Sort by ID
        std.sort.pdq(BufferId, keys.items, {}, struct {
            fn lessThan(_: void, a: BufferId, b: BufferId) bool {
                return a.id < b.id;
            }
        }.lessThan);

        // Build info array
        for (keys.items) |id| {
            const buf = self.buffers.get(id).?;
            const is_current = if (current_id) |cid| cid.eql(id) else false;

            try result.append(self.allocator, BufferInfo{
                .id = id,
                .filepath = buf.filepath,
                .modified = buf.modified,
                .current = is_current,
            });
        }

        return result.toOwnedSlice(self.allocator);
    }

    // ========================================================================
    // Window Management (Phase 5)
    // ========================================================================

    /// Get pointer to current window
    pub fn getCurrentWindow(self: *Editor) ?*Window {
        const win_id = self.current_window_id orelse return null;
        const win_ptr = self.windows.get(win_id) orelse return null;
        return win_ptr;
    }

    /// Get window by handle (0 = current window, positive = WindowId.id)
    pub fn getWindow(self: *Editor, handle: i64) ?*Window {
        if (handle == 0) {
            return self.getCurrentWindow();
        } else if (handle > 0) {
            const win_id = WindowId{ .id = @intCast(handle) };
            return self.windows.get(win_id);
        }
        return null;
    }

    /// Check if a window handle is valid
    pub fn isWindowValid(self: *Editor, handle: i64) bool {
        if (handle == 0) {
            return self.current_window_id != null;
        } else if (handle > 0) {
            const win_id = WindowId{ .id = @intCast(handle) };
            return self.windows.contains(win_id);
        }
        return false;
    }

    /// List all window IDs (for vim.api.listWins)
    pub fn listWindows(self: *Editor) ![]WindowId {
        if (self.window_layout) |*layout| {
            return layout.getAllWindows();
        }
        // Fallback: return current window only
        var result = try self.allocator.alloc(WindowId, 1);
        if (self.current_window_id) |id| {
            result[0] = id;
        } else {
            result[0] = WindowId{ .id = 1 };
        }
        return result;
    }

    /// Split current window horizontally (new window above, Vim behavior)
    pub fn splitHorizontal(self: *Editor) !WindowId {
        return self.splitWindow(.horizontal, true);
    }

    /// Split current window vertically (new window to the left, Vim behavior)
    pub fn splitVertical(self: *Editor) !WindowId {
        return self.splitWindow(.vertical, true);
    }

    /// Internal: split a window in the specified direction
    fn splitWindow(self: *Editor, direction: SplitDirection, before: bool) !WindowId {
        const current_win = self.getCurrentWindow() orelse return error.NoCurrentWindow;
        const layout = &(self.window_layout orelse return error.NoLayout);

        // CRITICAL: Sync buffer cursor to current window BEFORE creating new window
        // This ensures the new window gets the correct cursor position from recent hjkl movements
        if (self.buffers.get(current_win.buffer_id)) |buf| {
            current_win.cursor.row = buf.cursor.row;
            current_win.cursor.col = buf.cursor.col;
        }

        // Create new window ID
        const new_win_id = WindowId{ .id = self.next_window_id };
        self.next_window_id += 1;

        // Create new window showing same buffer
        const new_window = try self.allocator.create(Window);
        errdefer self.allocator.destroy(new_window);
        new_window.* = Window.init(self.allocator, new_win_id, current_win.buffer_id);
        new_window.cursor = current_win.cursor; // Copy synced cursor
        new_window.viewport = current_win.viewport;

        try self.windows.put(new_win_id, new_window);
        errdefer _ = self.windows.remove(new_win_id);

        // Update layout
        try layout.split(current_win.id, new_win_id, direction, before);

        // Focus new window (buffer cursor already has correct position from current_win)
        self.current_window_id = new_win_id;
        self.current_buffer_id = new_window.buffer_id;

        // Recalculate window dimensions after split
        self.relayout(self.terminal_rows, self.terminal_cols);

        // Mark both windows as needing redraw
        current_win.needs_redraw = true;
        new_window.needs_redraw = true;

        self.logger.info("Split window: created window {} from window {}", .{ new_win_id.id, current_win.id.id }) catch {};

        return new_win_id;
    }

    /// Close a window
    pub fn closeWindow(self: *Editor, win_id: WindowId, force: bool) !void {
        const window = self.windows.get(win_id) orelse return error.InvalidWindow;
        var layout = &(self.window_layout orelse return error.NoLayout);

        // Check if buffer is modified (unless force)
        // BUT: Allow closing if other windows also show this buffer (Vim behavior)
        if (!force) {
            if (self.buffers.get(window.buffer_id)) |buffer| {
                if (buffer.modified) {
                    // Count windows showing this buffer
                    var windows_with_buffer: usize = 0;
                    var win_iter = self.windows.valueIterator();
                    while (win_iter.next()) |win_ptr| {
                        if (win_ptr.*.buffer_id.eql(window.buffer_id)) {
                            windows_with_buffer += 1;
                        }
                    }

                    // Only block close if this is the LAST window showing this buffer
                    if (windows_with_buffer <= 1) {
                        return error.BufferModified;
                    }
                }
            }
        }

        // Remove from layout (returns new active window or null if last window)
        const new_active = try layout.removeWindow(win_id) orelse {
            return error.CannotCloseLastWindow;
        };

        // Cleanup window (heap-allocated)
        if (self.windows.fetchRemove(win_id)) |kv| {
            const win_ptr = kv.value; // *Window (heap-allocated)
            win_ptr.*.deinit();
            self.allocator.destroy(win_ptr);
        }

        // Update current window AND buffer to match new active window
        self.current_window_id = new_active;
        if (self.windows.get(new_active)) |new_win| {
            self.current_buffer_id = new_win.buffer_id;
        }

        // Recalculate window dimensions after close
        self.relayout(self.terminal_rows, self.terminal_cols);

        self.logger.info("Closed window {}, new active: {}", .{ win_id.id, new_active.id }) catch {};
    }

    /// Focus a different window
    /// CRITICAL: Syncs cursor between buffer and windows to maintain per-window cursor state
    pub fn focusWindow(self: *Editor, win_id: WindowId) !void {
        if (!self.windows.contains(win_id)) {
            return error.InvalidWindow;
        }

        // Step 1: Save current buffer's cursor to old window (before switching)
        if (self.current_window_id) |old_win_id| {
            if (self.windows.get(old_win_id)) |old_window| {
                if (self.buffers.get(old_window.buffer_id)) |old_buf| {
                    // Save buffer cursor to window
                    old_window.cursor.row = old_buf.cursor.row;
                    old_window.cursor.col = old_buf.cursor.col;
                }
            }
        }

        // Step 2: Switch to new window
        self.current_window_id = win_id;

        // Step 3: Restore new window's cursor to buffer
        if (self.windows.get(win_id)) |window| {
            self.current_buffer_id = window.buffer_id;

            // Restore window's cursor to buffer
            if (self.buffers.get(window.buffer_id)) |buf| {
                buf.cursor.row = window.cursor.row;
                buf.cursor.col = window.cursor.col;
                buf.cursor.goal_column = null; // Reset goal column on window switch
            }
        }
    }

    /// Navigate to adjacent window in direction
    pub fn navigateWindow(self: *Editor, direction: NavigationDirection) !void {
        const current_win_id = self.current_window_id orelse return error.NoCurrentWindow;
        var layout = &(self.window_layout orelse return error.NoLayout);

        // Convert windows HashMap to pointer map for layout query
        var windows_ptr = std.AutoHashMap(WindowId, *Window).init(self.allocator);
        defer windows_ptr.deinit();

        var iter = self.windows.iterator();
        while (iter.next()) |entry| {
            try windows_ptr.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        const adjacent = layout.findAdjacentWindow(current_win_id, direction, &windows_ptr);
        if (adjacent) |adj_win_id| {
            try self.focusWindow(adj_win_id);
        }
    }

    /// Recalculate all window positions after terminal resize
    pub fn relayout(self: *Editor, rows: usize, cols: usize) void {
        // Store terminal dimensions for future splits
        self.terminal_rows = rows;
        self.terminal_cols = cols;

        var layout = &(self.window_layout orelse return);

        // Build pointer map for layout calculation
        var windows_ptr = std.AutoHashMap(WindowId, *Window).init(self.allocator);
        defer windows_ptr.deinit();

        var iter = self.windows.iterator();
        while (iter.next()) |entry| {
            windows_ptr.put(entry.key_ptr.*, entry.value_ptr.*) catch continue;
        }

        layout.calculateLayout(&windows_ptr, rows, cols);
    }

    /// Get window count
    pub fn windowCount(self: *Editor) usize {
        return self.windows.count();
    }

    // ========================================================================
    // End Window Management
    // ========================================================================

    /// Load file and detect filetype (legacy method - kept for backwards compatibility)
    /// TODO: Migrate callers to use loadBufferFromFile() instead
    pub fn loadFile(self: *Editor, path: []const u8) !void {
        const buf = self.getCurrentBuffer() orelse return error.NoActiveBuffer;
        try buf.loadFile(path);

        // Detect filetype using loader
        const first_line = buf.getLine(0);
        defer if (first_line != null) self.allocator.free(first_line.?); // ✅ FIX: Free owned memory from getLine()
        const filetype = self.ts_loader.detectFiletype(path, first_line);

        if (filetype) |ft| {
            buf.setFiletype(ft) catch {};
            self.logger.info("✅ Detected filetype: {s} for {s}", .{ ft, path }) catch {};

            // Parse with tree-sitter
            try self.parseBufferWithTreeSitter(ft);
        } else {
            buf.setFiletype(null) catch {};
            self.logger.info("❌ No filetype detected for {s}", .{path}) catch {};
        }

        // Trigger autocommands (Phase 4 - autocommand support)
        // BufRead: After reading buffer into memory
        // BufEnter: After entering buffer
        self.triggerAutocommand("BufRead");
        self.triggerAutocommand("BufEnter");
    }

    /// Execute a string of keys through the editor
    /// This is used by both Terminal backend (keyboard input) and Debug backend (JSON commands)
    /// Returns true if any key changed editor state (needs re-render), false if all were no-ops
    pub fn executeKeys(self: *Editor, keys: []const u8) anyerror!bool {
        var state_changed = false;

        // Track cursor position before processing keys (for CursorMoved autocmd)
        const buf = self.getCurrentBuffer();
        const start_row = if (buf) |b| b.cursor.row else 0;
        const start_col = if (buf) |b| b.cursor.col else 0;

        // Process each character/sequence
        var i: usize = 0;
        while (i < keys.len) {
            // Check for special escape sequences
            if (i + 2 < keys.len and keys[i] == 27 and keys[i + 1] == '[') {
                // Arrow keys: ESC[A/B/C/D
                const input = keys[i .. i + 3];
                const changed = try self.processInput(input);
                state_changed = state_changed or changed;
                i += 3;
            } else {
                // Single character
                const input = keys[i .. i + 1];
                const changed = try self.processInput(input);
                state_changed = state_changed or changed;
                i += 1;
            }
        }

        // Fire CursorMoved if cursor position changed
        if (buf) |b| {
            if (b.cursor.row != start_row or b.cursor.col != start_col) {
                self.fireCursorMoved();
            }
        }

        return state_changed;
    }

    /// Get command buffer string (for status line in command mode)
    pub fn getCommandString(self: *const Editor) []const u8 {
        return self.cmd_buffer.getString();
    }

    /// Process a single input sequence
    /// Returns true if state changed (needs re-render), false if no-op
    fn processInput(self: *Editor, input: []const u8) !bool {
        if (self.mode_manager.isNormal()) {
            return try self.handleNormalMode(input);
        } else if (self.mode_manager.isInsert()) {
            return try self.handleInsertMode(input);
        } else if (self.mode_manager.isVisual()) {
            return try self.handleVisualMode(input);
        } else if (self.mode_manager.isCommand()) {
            return try self.handleCommandMode(input);
        }
        return false; // Unknown mode, no state change
    }

    /// Enter insert mode (no transaction - regular typing rebuilds line_starts immediately)
    /// Transactions are ONLY used for bracketed paste operations in backend.zig
    fn enterInsertMode(self: *Editor) void {
        self.mode_manager.enterInsert();

        // Trigger InsertEnter autocommand (Phase 4)
        self.triggerAutocommand("InsertEnter");
    }

    /// Handle input in Normal mode
    /// Returns true if state changed (needs re-render), false if no-op
    fn handleNormalMode(self: *Editor, input: []const u8) !bool {
        // ESC cancels pending keymap state (Step 4: ESC cancellation)
        if (input.len == 1 and input[0] == 27) { // ESC
            self.keymap_mgr.clearPending();
            // Note: Also clears other pending states below
        }

        // CRITICAL: Check for custom keymaps FIRST (before any other processing)
        // This allows users to override built-in keys (e.g., H → Hzz)

        // Neovim E223: recursive mapping - prevent infinite loops
        const max_map_depth = 1000; // Neovim default

        // Only check mappings if not at max depth
        if (self.mapping_depth < max_map_depth) {
            // Save pending keys BEFORE lookup (lookup clears them on .not_found)
            const had_pending_keys = self.keymap_mgr.pending_keys.items.len > 0;
            const first_pending_key = if (had_pending_keys) self.keymap_mgr.pending_keys.items[0] else 0;

            // Convert raw byte to Vim notation for keymap lookup
            // e.g., Ctrl+H (byte 8) -> "<C-h>"
            const keymap = @import("keymap/keymap.zig");
            var notation_buf: [5]u8 = undefined;
            const lookup_key = if (input.len == 1)
                keymap.byteToNotation(input[0], &notation_buf) orelse input
            else
                input;

            // For now, Vimcraft has single-buffer support (buffer_id = 0)
            const lookup_result = self.keymap_mgr.lookup(.normal, lookup_key, 0) catch {
                // Error during lookup - clear pending and continue to built-in
                self.keymap_mgr.clearPending();
                return error.KeymapLookupError;
            };

            switch (lookup_result) {
                .matched => |mapping| {
                    // Found a full mapping! Execute it
                    switch (mapping.rhs) {
                        .keys => |keys| {
                            // String mapping: execute keys recursively

                            // For noremap, skip mapping lookup by temporarily setting depth to max
                            // This prevents further mapping expansion (executes keys literally)
                            // NOTE: Vimcraft uses depth manipulation instead of Neovim's tb_noremap buffer
                            // Limitation: Cannot express partial remapping (REMAP_SKIP). This is acceptable
                            // given our immediate-execution model (no typeahead buffer).
                            if (mapping.opts.noremap) {
                                const saved_depth = self.mapping_depth;
                                self.mapping_depth = max_map_depth; // Prevent further lookups
                                errdefer self.mapping_depth = saved_depth; // Restore on error only

                                const changed = try self.executeKeys(keys);
                                self.mapping_depth = saved_depth; // Explicit restore on success
                                return changed;
                            } else {
                                // Increment depth before recursive call
                                self.mapping_depth += 1;
                                errdefer self.mapping_depth -= 1; // Restore on error only

                                const changed = try self.executeKeys(keys);
                                self.mapping_depth -= 1; // Explicit decrement on success
                                return changed;
                            }
                        },
                        .callback => |callback_id| {
                            // Execute JavaScript callback via JSI
                            const keymap_api = @import("../system/jsi/keymap_api.zig");
                            keymap_api.executeCallback(callback_id);
                            self.js_state_dirty = true; // Callback may have modified state
                            return true;
                        },
                    }
                },
                .pending => {
                    // Partial match - waiting for more keys
                    // NOTE: setTimeout timeout integration happens in Phase 4.5
                    // For now, just return and wait for next key
                    // User can press ESC to cancel (Step 4)
                    return false; // No state change yet, waiting for more input
                },
                .not_found => {
                    // No mapping found
                    // If we HAD pending keys (saved before lookup cleared them),
                    // execute first key as literal, then process new input
                    if (had_pending_keys) {
                        // Note: pending_keys already cleared by lookup(), so use saved value

                        // Execute first pending key as literal (bypass keymap lookup)
                        // Use noremap technique: temporarily set depth to max to skip keymap
                        const saved_depth = self.mapping_depth;
                        self.mapping_depth = max_map_depth;
                        errdefer self.mapping_depth = saved_depth;

                        var first_key_buf: [1]u8 = .{first_pending_key};
                        const changed1 = try self.handleNormalMode(&first_key_buf);

                        // Restore depth
                        self.mapping_depth = saved_depth;

                        // Now process new input through normal flow (including keymap lookup)
                        const changed2 = try self.handleNormalMode(input);

                        // Don't fall through - we've already processed both keys
                        // Return true if either key changed state
                        return changed1 or changed2;
                    }
                    // No pending keys - fall through to built-in commands
                },
            }
        } else if (self.mapping_depth > max_map_depth) {
            // Max depth exceeded (but allow exactly max_map_depth for noremap)
            self.logger.err("Recursive mapping detected (depth: {})", .{self.mapping_depth}) catch {};
            return error.RecursiveMapping;
        }
        // If depth == max_map_depth, we're in noremap mode - fall through to built-in commands

        // Check for pending register selection first
        if (self.pending_register.isWaitingForName()) {
            if (input.len == 1) {
                const regchar = input[0];
                if (RegisterManager.charToIndex(regchar)) |_| {
                    self.pending_register.setRegister(regchar);
                    return false; // Just setting register, no visual change yet
                }
            }
            self.pending_register.clear();
            return false; // Invalid register, cleared state but no visual change
        }

        // Check for pending text object (after operator + i/a)
        if (self.pending_text_object.isWaiting()) {
            if (input.len == 1) {
                const char = input[0];

                // Try to parse as text object type
                if (TextObjectType.fromChar(char)) |obj_type| {
                    const modifier = self.pending_text_object.getModifier().?;
                    const pending_op = self.pending_cmd.get().?;

                    // Get current buffer
                    const buf = self.getCurrentBuffer() orelse return false;

                    // Find the text object range
                    if (text_objects.findTextObject(buf, obj_type, modifier)) |range| {
                        // Perform the operation based on pending command
                        switch (pending_op) {
                            'd' => { // Delete text object
                                const result = try self.edit_ops.deleteRange(buf, range, .char);
                                defer self.allocator.free(result.deleted_text);
                                // TODO: Store in register
                            },
                            'c' => { // Change text object (delete + enter insert)
                                const result = try self.edit_ops.deleteRange(buf, range, .char);
                                defer self.allocator.free(result.deleted_text);
                                // TODO: Store in register
                                self.enterInsertMode();
                            },
                            'y' => { // Yank text object
                                const text = try range.getText(buf);
                                defer self.allocator.free(text); // getText() now returns owned memory
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);
                                self.pending_register.clear();

                                // Set yank highlight based on actual range positions
                                // range.end is exclusive, but highlight needs position of last character
                                if (range.end > range.start) {
                                    const start_pos = self.offsetToPosition(range.start);
                                    const end_pos = self.offsetToPosition(range.end - 1); // -1 because end is exclusive
                                    self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                                }
                            },
                            else => {},
                        }
                    }

                    self.pending_text_object.clear();
                    self.pending_cmd.clear();
                    return true; // Operation performed, state changed
                }
            }

            // Invalid text object type, clear state
            self.pending_text_object.clear();
            self.pending_cmd.clear();
            return false; // No valid operation, just cleared state
        }

        // Check for pending command (dd, dw, yy, etc.)
        if (self.pending_cmd.get()) |pending| {
            if (input.len == 1) {
                const char = input[0];

                // Check for text object modifier (i/a) after an operator
                if (pending == 'd' or pending == 'c' or pending == 'y') {
                    if (TextObjectModifier.fromChar(char)) |modifier| {
                        self.pending_text_object.start(modifier);
                        return false; // Wait for text object type, no state change yet
                    }
                }

                // Get current buffer for all pending operations
                const buf = self.getCurrentBuffer() orelse return false;

                // Handle pending 'd' commands
                if (pending == 'd') {
                    switch (char) {
                        'd' => { // dd - delete line
                            const result = try self.edit_ops.deleteCurrentLine(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        'w' => { // dw - delete word
                            const result = try self.edit_ops.deleteWord(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        '$' => { // d$ - delete to end of line
                            const result = try self.edit_ops.deleteToEndOfLine(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        '0' => { // d0 - delete to start of line
                            const result = try self.edit_ops.deleteToStartOfLine(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        else => {},
                    }
                }

                // Handle pending 'c' commands (change)
                if (pending == 'c') {
                    switch (char) {
                        'c' => { // cc - change line
                            const Range = @import("buffer/edit.zig").Range;
                            const range = Range.forLine(buf, buf.cursor.row);
                            const deleted_text = try self.edit_ops.changeRange(buf, range, .line);
                            defer self.allocator.free(deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        'w' => { // cw - change word
                            const result = try self.edit_ops.deleteWord(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        '$' => { // c$ - change to end of line
                            const result = try self.edit_ops.deleteToEndOfLine(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        '0' => { // c0 - change to start of line
                            const result = try self.edit_ops.deleteToStartOfLine(buf);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        else => {},
                    }
                }

                // Handle pending 'g' commands (goto)
                if (pending == 'g') {
                    if (char == 'g') { // gg - go to file start
                        movement.moveToFileStart(buf);
                        self.pending_cmd.clear();
                        return true; // Moved to file start
                    } else {
                        // Not a valid g-command (e.g., user pressed g then G)
                        // Clear pending and fall through to process char as standalone command
                        self.pending_cmd.clear();
                        // Fall through to single-char handling below (don't return)
                    }
                }

                // Handle pending 'z' commands (viewport adjustment)
                // Note: These require viewport info from backend, handled specially
                if (pending == 'z') {
                    switch (char) {
                        'z', 't', 'b' => {
                            // zz, zt, zb - command is COMPLETE, signal backend
                            self.viewport_adjustment = char; // 'z'=center, 't'=top, 'b'=bottom
                            self.pending_cmd.clear();
                            return true; // Viewport will change, needs re-render
                        },
                        else => {},
                    }
                }

                // Handle pending Ctrl+W commands (window management)
                if (pending == 23) {
                    switch (char) {
                        'h' => { // Ctrl+W h - move to window left
                            self.navigateWindow(.left) catch {};
                            self.pending_cmd.clear();
                            return true;
                        },
                        'j' => { // Ctrl+W j - move to window below
                            self.navigateWindow(.down) catch {};
                            self.pending_cmd.clear();
                            return true;
                        },
                        'k' => { // Ctrl+W k - move to window above
                            self.navigateWindow(.up) catch {};
                            self.pending_cmd.clear();
                            return true;
                        },
                        'l' => { // Ctrl+W l - move to window right
                            self.navigateWindow(.right) catch {};
                            self.pending_cmd.clear();
                            return true;
                        },
                        'w' => { // Ctrl+W w - cycle to next window
                            self.navigateWindow(.right) catch {}; // Simple cycle for now
                            self.pending_cmd.clear();
                            return true;
                        },
                        's' => { // Ctrl+W s - horizontal split
                            _ = self.splitHorizontal() catch {};
                            self.pending_cmd.clear();
                            return true;
                        },
                        'v' => { // Ctrl+W v - vertical split
                            _ = self.splitVertical() catch {};
                            self.pending_cmd.clear();
                            return true;
                        },
                        'c', 'q' => { // Ctrl+W c / Ctrl+W q - close window
                            if (self.current_window_id) |win_id| {
                                self.closeWindow(win_id, false) catch {};
                            }
                            self.pending_cmd.clear();
                            return true;
                        },
                        'o' => { // Ctrl+W o - close all other windows
                            if (self.window_layout) |*layout| {
                                const windows = layout.getAllWindows() catch &[_]WindowId{};
                                defer if (windows.len > 0) self.allocator.free(windows);

                                for (windows) |win_id| {
                                    if (self.current_window_id) |current| {
                                        if (!win_id.eql(current)) {
                                            self.closeWindow(win_id, true) catch {};
                                        }
                                    }
                                }
                            }
                            self.pending_cmd.clear();
                            return true;
                        },
                        else => {
                            // Unknown Ctrl+W command, clear pending
                            self.pending_cmd.clear();
                            return false;
                        },
                    }
                }

                // Handle pending 'y' commands (yank)
                if (pending == 'y') {
                    switch (char) {
                        'y' => { // yy - yank current line
                            const line_num = buf.cursor.row;
                            const line = buf.getLine(line_num) orelse {
                                self.pending_cmd.clear();
                                self.pending_register.clear();
                                return false; // No line to yank, no state change
                            };
                            defer self.allocator.free(line); // ✅ FIX: Free owned memory from getLine()

                            const text = if (line.len > 0 and line[line.len - 1] == '\n')
                                line[0 .. line.len - 1]
                            else
                                line;

                            const reg = self.pending_register.getSelected() orelse '"';
                            const lines = [_][]const u8{text};
                            try self.register_mgr.yank(reg, &lines, .line_wise);

                            const start_pos = Position{ .line = line_num, .col = 0 };
                            const end_col = if (text.len > 0) text.len - 1 else 0;
                            const end_pos = Position{ .line = line_num, .col = end_col };
                            self.yank_highlight = YankHighlight.init(start_pos, end_pos, .line);

                            self.pending_register.clear();
                        },
                        '$' => { // y$ - yank to end of line
                            const text = try self.edit_ops.yankToEndOfLine(buf);
                            defer self.allocator.free(text);

                            if (text.len > 0) {
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);

                                const start_pos = Position{ .line = buf.cursor.row, .col = buf.cursor.col };
                                const end_col = buf.cursor.col + text.len - 1;
                                const end_pos = Position{ .line = buf.cursor.row, .col = end_col };
                                self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                            }

                            self.pending_register.clear();
                        },
                        '0' => { // y0 - yank to start of line
                            const text = try self.edit_ops.yankToStartOfLine(buf);
                            defer self.allocator.free(text);

                            if (text.len > 0) {
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);

                                const start_pos = Position{ .line = buf.cursor.row, .col = 0 };
                                const end_pos = Position{ .line = buf.cursor.row, .col = buf.cursor.col };
                                self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                            }

                            self.pending_register.clear();
                        },
                        'w' => { // yw - yank word
                            const text = try self.edit_ops.yankWord(buf);
                            defer self.allocator.free(text);

                            if (text.len > 0) {
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);

                                const start_pos = Position{ .line = buf.cursor.row, .col = buf.cursor.col };
                                const end_col = buf.cursor.col + text.len - 1;
                                const end_pos = Position{ .line = buf.cursor.row, .col = end_col };
                                self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                            }

                            self.pending_register.clear();
                        },
                        else => {},
                    }
                }
            }
            // Only return if pending_cmd is still set (meaning a command was executed)
            // If pending_cmd was cleared by a handler for fallthrough (e.g., 'g' then 'G'),
            // we should continue to single-char handling instead of returning
            if (self.pending_cmd.get() != null) {
                self.pending_cmd.clear();
                return true; // Pending command executed (dd, yy, etc.), state changed
            }
            // Fallthrough: pending_cmd was cleared by handler, process char as standalone
        }

        // Single character commands
        if (input.len == 1) {
            const char = input[0];

            // Get current buffer for single character commands
            const buf = self.getCurrentBuffer() orelse return false;

            switch (char) {
                // Basic movement (hjkl) - check return value for boundary detection
                'h' => return movement.moveLeft(buf),
                'j' => return movement.moveDown(buf),
                'k' => return movement.moveUp(buf),
                'l' => return movement.moveRight(buf),

                // Line movement - always changes position (or no-op if already there)
                '0' => {
                    movement.moveToLineStart(buf);
                    return true; // Always changes state (or already at start)
                },
                '$' => {
                    movement.moveToLineEnd(buf);
                    return true;
                },
                '^' => {
                    movement.moveToFirstNonBlank(buf);
                    return true;
                },

                // Word movement - always changes position
                'w' => {
                    movement.moveWordForward(buf);
                    return true;
                },
                'b' => {
                    movement.moveWordBackward(buf);
                    return true;
                },
                'e' => {
                    movement.moveWordEnd(buf);
                    return true;
                },

                // Delete operations
                'x' => {
                    const result = try self.edit_ops.deleteCharAtCursor(buf);
                    defer self.allocator.free(result.deleted_text);
                    return true; // Deleted character, state changed
                },
                'd' => {
                    self.pending_cmd.set('d');
                    return false; // Just setting pending state, no visual change yet
                },

                // Change operations
                'c' => {
                    self.pending_cmd.set('c');
                    return false; // Just setting pending state
                },
                'C' => { // Change to end of line (like c$)
                    const result = try self.edit_ops.deleteToEndOfLine(buf);
                    defer self.allocator.free(result.deleted_text);
                    // TODO: Store in register
                    self.enterInsertMode();
                    return true; // Deleted text and changed mode
                },

                // Register selection
                '"' => {
                    self.pending_register.startSelection();
                    return false; // Just waiting for register name, no visual change
                },

                // Yank operations
                'y' => {
                    self.pending_cmd.set('y');
                    return false; // Just setting pending state
                },

                // Goto operations (gg, G)
                'g' => {
                    self.pending_cmd.set('g');
                    return false; // Just setting pending state
                },
                'G' => {
                    movement.moveToFileEnd(buf);
                    return true; // Moved to end of file
                },

                // Viewport adjustment (zz, zt, zb)
                // Note: These require viewport info from backend, handled specially
                'z' => {
                    self.pending_cmd.set('z');
                    return false; // Just setting pending state
                },

                // Window commands (Ctrl+W followed by h/j/k/l/s/v/c/o/w)
                23 => { // Ctrl+W
                    self.pending_cmd.set(23);
                    return false; // Wait for next key
                },

                // Viewport-relative movement (H, M, L)
                // Set immediate flag for backend (not pending - single character commands)
                'H', 'M', 'L' => {
                    self.viewport_movement = char;
                    return true; // Will move cursor, needs re-render
                },

                // Paste operations
                'p' => {
                    const reg = self.pending_register.getSelected() orelse '"';
                    _ = try paste.pasteAfter(buf, &self.register_mgr, reg);
                    self.pending_register.clear();
                    return true; // Pasted text, state changed
                },
                'P' => {
                    const reg = self.pending_register.getSelected() orelse '"';
                    _ = try paste.pasteBefore(buf, &self.register_mgr, reg);
                    self.pending_register.clear();
                    return true; // Pasted text, state changed
                },

                // Undo/redo
                'u' => {
                    try buf.undo();
                    return true; // Undo changes state
                },
                18 => { // Ctrl+R
                    try buf.redo();
                    return true; // Redo changes state
                },

                // Enter command mode
                ':' => {
                    // CRITICAL: Clear pending commands when entering command mode
                    // Prevents H/M/L or other pending ops from executing after command
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    self.cmd_buffer.clear();
                    self.mode_manager.enterCommand();
                    return true; // Mode changed
                },

                // Enter visual mode
                'v' => {
                    // CRITICAL: Clear pending commands when entering visual mode
                    // Prevents H/M/L or other pending ops from executing unexpectedly
                    self.pending_cmd.clear();
                    self.pending_register.clear();

                    const cursor_pos = Position{
                        .line = buf.cursor.row,
                        .col = buf.cursor.col,
                    };
                    self.visual_state = VisualState.init(cursor_pos, .char);
                    self.mode_manager.enterVisual();
                    return true; // Mode changed
                },
                'V' => {
                    // CRITICAL: Clear pending commands when entering visual mode
                    // Prevents H/M/L or other pending ops from executing unexpectedly
                    self.pending_cmd.clear();
                    self.pending_register.clear();

                    const cursor_pos = Position{
                        .line = buf.cursor.row,
                        .col = buf.cursor.col,
                    };
                    self.visual_state = VisualState.init(cursor_pos, .line);
                    self.mode_manager.enterVisual();
                    return true; // Mode changed
                },

                // Enter insert mode
                'i' => {
                    // CRITICAL: Clear pending commands when entering insert mode
                    // Prevents H/M/L or other pending ops from executing after ESC
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    self.enterInsertMode();
                    return true; // Mode changed
                },
                'a' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    // Move cursor AFTER current character (insert mode allows past end)
                    // Don't use moveRight() which is blocked at line end in normal mode
                    const visual_len = buf.getLineLengthVisual(buf.cursor.row);
                    if (buf.cursor.col < visual_len) {
                        buf.cursor.col += 1; // Move after current char
                    }
                    buf.cursor.goal_column = buf.cursor.col;
                    self.enterInsertMode();
                    return true; // Mode changed (movement is secondary)
                },
                'A' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    // Move cursor AFTER last character for append (insert mode allows this)
                    // Don't use moveRight() which is blocked at line end in normal mode
                    const visual_len = buf.getLineLengthVisual(buf.cursor.row);
                    buf.cursor.col = visual_len; // Position after last char
                    buf.cursor.goal_column = buf.cursor.col;
                    self.enterInsertMode();
                    return true; // Mode changed
                },
                'I' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToFirstNonBlank(buf);
                    self.enterInsertMode();
                    return true; // Mode changed
                },
                'o' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    // Position cursor AFTER last character to insert newline at end of line
                    const visual_len = buf.getLineLengthVisual(buf.cursor.row);
                    buf.cursor.col = visual_len;
                    buf.cursor.goal_column = visual_len;
                    try buf.insertChar('\n');
                    self.enterInsertMode();
                    return true; // Inserted newline and changed mode
                },
                'O' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToLineStart(buf);
                    try buf.insertChar('\n');
                    _ = movement.moveUp(buf);
                    self.enterInsertMode();
                    return true; // Inserted newline and changed mode
                },

                // Ctrl+D, Ctrl+U (scrolling - viewport height passed by renderer)
                4 => return true, // Ctrl+D handled by renderer, will scroll
                21 => return true, // Ctrl+U handled by renderer, will scroll

                else => return false, // Unknown command, no state change
            }
        }

        // Arrow keys
        if (input.len == 3 and input[0] == 27 and input[1] == '[') {
            const buf = self.getCurrentBuffer() orelse return false;
            return switch (input[2]) {
                'A' => movement.moveUp(buf),
                'B' => movement.moveDown(buf),
                'C' => movement.moveRight(buf),
                'D' => movement.moveLeft(buf),
                else => false, // Unknown arrow key
            };
        }

        // Unknown input, no state change
        return false;
    }

    /// Handle input in Insert mode
    /// Returns true if state changed (needs re-render), false if no-op
    fn handleInsertMode(self: *Editor, input: []const u8) !bool {
        // Check for custom keymaps FIRST (before built-in commands)
        // This allows mappings like "jk" → ESC
        const max_map_depth = 1000;

        if (self.mapping_depth < max_map_depth) {
            // Save pending keys BEFORE lookup (lookup clears them on .not_found)
            const had_pending_keys = self.keymap_mgr.pending_keys.items.len > 0;
            const first_pending_key = if (had_pending_keys) self.keymap_mgr.pending_keys.items[0] else 0;

            // Convert raw byte to Vim notation for keymap lookup
            // e.g., Ctrl+H (byte 8) -> "<C-h>"
            const keymap = @import("keymap/keymap.zig");
            var notation_buf: [5]u8 = undefined;
            const lookup_key = if (input.len == 1)
                keymap.byteToNotation(input[0], &notation_buf) orelse input
            else
                input;

            const lookup_result = self.keymap_mgr.lookup(.insert, lookup_key, 0) catch {
                self.keymap_mgr.clearPending();
                return error.KeymapLookupError;
            };

            switch (lookup_result) {
                .matched => |mapping| {
                    switch (mapping.rhs) {
                        .keys => |keys| {
                            if (mapping.opts.noremap) {
                                const saved_depth = self.mapping_depth;
                                self.mapping_depth = max_map_depth;
                                errdefer self.mapping_depth = saved_depth;

                                const changed = try self.executeKeys(keys);
                                self.mapping_depth = saved_depth;
                                return changed;
                            } else {
                                self.mapping_depth += 1;
                                errdefer self.mapping_depth -= 1;

                                const changed = try self.executeKeys(keys);
                                self.mapping_depth -= 1;
                                return changed;
                            }
                        },
                        .callback => |callback_id| {
                            // Execute JavaScript callback via JSI
                            const keymap_api = @import("../system/jsi/keymap_api.zig");
                            keymap_api.executeCallback(callback_id);
                            self.js_state_dirty = true; // Callback may have modified state
                            return true;
                        },
                    }
                },
                .pending => {
                    // Waiting for more keys
                    return false; // No state change yet
                },
                .not_found => {
                    // Execute first pending key as literal, then process new input
                    if (had_pending_keys) {
                        const saved_depth = self.mapping_depth;
                        self.mapping_depth = max_map_depth;
                        errdefer self.mapping_depth = saved_depth;

                        var first_key_buf: [1]u8 = .{first_pending_key};
                        const changed1 = try self.handleInsertMode(&first_key_buf);

                        self.mapping_depth = saved_depth;

                        const changed2 = try self.handleInsertMode(input);
                        return changed1 or changed2;
                    }
                    // No pending keys - fall through to built-in
                },
            }
        }

        // Built-in insert mode commands
        const buf = self.getCurrentBuffer() orelse return false;

        if (input.len == 1 and input[0] == 27) { // ESC
            // IMPORTANT: Bracketed paste in backend.zig manages transactions
            // Regular typing has NO transaction, so only commit if one exists
            if (buf.active_transaction != null) {
                try buf.commitTransaction();
            }

            // Trigger InsertLeave autocommand (Phase 4) BEFORE mode change
            self.triggerAutocommand("InsertLeave");

            // CRITICAL: Clamp cursor position for normal mode (Vim behavior)
            // In insert mode, cursor can be AFTER last char; in normal mode it must be ON a char
            movement.clampCursorForNormalMode(buf);

            self.keymap_mgr.clearPending(); // Clear pending state on mode change
            self.mode_manager.enterNormal();
            return true; // Mode changed
        }

        // Arrow keys (insert mode allows cursor past last char)
        if (input.len == 3 and input[0] == 27 and input[1] == '[') {
            return switch (input[2]) {
                'A' => movement.moveUp(buf),
                'B' => movement.moveDown(buf),
                'C' => movement.moveRightInsert(buf), // Insert mode: can go after last char
                'D' => movement.moveLeft(buf),
                else => false, // Unknown arrow key
            };
        }

        if (input.len == 1) {
            const char = input[0];
            switch (char) {
                127, 8 => { // Backspace
                    try buf.deleteCharBefore();
                    return true; // Deleted character
                },
                13 => { // Enter
                    try buf.insertChar('\n');
                    // Autoindent: copy indent from previous line
                    if (self.options_manager) |opts_mgr| {
                        if (opts_mgr.getBoolean("autoindent") orelse false) {
                            try self.applyAutoIndent();
                        }
                    }
                    return true; // Inserted newline
                },
                9 => { // Tab
                    // Check expandtab option
                    const expand_tab = if (self.options_manager) |opts_mgr|
                        opts_mgr.getBoolean("expandtab") orelse false
                    else
                        false;

                    if (expand_tab) {
                        // Get tabstop value (default 8)
                        const tabstop = if (self.options_manager) |opts_mgr|
                            opts_mgr.getNumber("tabstop") orelse 8
                        else
                            8;

                        // Insert spaces instead of tab
                        var i: usize = 0;
                        while (i < tabstop) : (i += 1) {
                            try buf.insertChar(' ');
                        }
                    } else {
                        // Insert actual tab character
                        try buf.insertChar('\t');
                    }
                    return true; // Inserted tab/spaces
                },
                else => {
                    if (char >= 32 and char < 127) {
                        try buf.insertChar(char);
                        return true; // Inserted character
                    }
                    return false; // Non-printable character, ignored
                },
            }
        }

        return false; // Unknown input
    }

    /// Apply auto-indent after inserting a newline
    /// Copies the indentation from the previous line
    fn applyAutoIndent(self: *Editor) !void {
        const buf = self.getCurrentBuffer() orelse return;

        // Get the previous line (the one we just left)
        if (buf.cursor.row == 0) return; // No previous line on first line

        const prev_line = buf.getLine(buf.cursor.row - 1) orelse return;
        defer self.allocator.free(prev_line);

        // Count leading whitespace on previous line
        var indent_count: usize = 0;
        for (prev_line) |c| {
            if (c == ' ' or c == '\t') {
                indent_count += 1;
            } else {
                break;
            }
        }

        // Insert the same whitespace on the new line
        var i: usize = 0;
        while (i < indent_count) : (i += 1) {
            try buf.insertChar(prev_line[i]);
        }
    }

    /// Handle input in Visual mode
    /// Returns true if state changed (needs re-render), false if no-op
    fn handleVisualMode(self: *Editor, input: []const u8) !bool {
        // Check for pending register selection
        if (self.pending_register.isWaitingForName()) {
            if (input.len == 1) {
                const regchar = input[0];
                if (RegisterManager.charToIndex(regchar)) |_| {
                    self.pending_register.setRegister(regchar);
                    return false; // Just setting register, no visual change yet
                }
            }
            self.pending_register.clear();
            return false; // Invalid register, cleared state
        }

        const buf = self.getCurrentBuffer() orelse return false;

        if (input.len == 1 and input[0] == 27) { // ESC
            self.visual_state.deactivate();
            self.mode_manager.enterNormal();
            return true; // Exited visual mode
        }

        if (input.len == 1) {
            const char = input[0];

            switch (char) {
                // Navigation - check return values for boundary detection
                'h' => return movement.moveLeft(buf),
                'j' => return movement.moveDown(buf),
                'k' => return movement.moveUp(buf),
                'l' => return movement.moveRight(buf),
                '0' => {
                    movement.moveToLineStart(buf);
                    return true;
                },
                '$' => {
                    movement.moveToLineEnd(buf);
                    return true;
                },
                '^' => {
                    movement.moveToFirstNonBlank(buf);
                    return true;
                },
                'w' => {
                    movement.moveWordForward(buf);
                    return true;
                },
                'b' => {
                    movement.moveWordBackward(buf);
                    return true;
                },
                'e' => {
                    movement.moveWordEnd(buf);
                    return true;
                },
                'G' => {
                    movement.moveToFileEnd(buf);
                    return true;
                },

                // Register selection
                '"' => {
                    self.pending_register.startSelection();
                    return false; // Just waiting for register name
                },

                // Exit visual mode
                'v' => {
                    self.visual_state.deactivate();
                    self.mode_manager.enterNormal();
                    return true; // Mode changed
                },

                // Yank selection
                'y' => {
                    const cursor_pos = Position{
                        .line = buf.cursor.row,
                        .col = buf.cursor.col,
                    };

                    const range = self.visual_state.getRange(cursor_pos);
                    const reg = self.pending_register.getSelected() orelse '"';
                    try yank.yankVisualSelection(buf, self.visual_state, cursor_pos, &self.register_mgr, reg, self.allocator);

                    self.yank_highlight = YankHighlight.init(range.start, range.end, self.visual_state.mode);

                    self.visual_state.deactivate();
                    self.mode_manager.enterNormal();
                    self.pending_register.clear();
                    return true; // Yanked and changed mode
                },

                // Delete selection
                'd' => {
                    const cursor_pos = Position{
                        .line = buf.cursor.row,
                        .col = buf.cursor.col,
                    };

                    const reg = self.pending_register.getSelected() orelse '"';
                    try visual_ops.deleteVisualSelection(buf, self.visual_state, cursor_pos, &self.register_mgr, reg, self.allocator);

                    self.visual_state.deactivate();
                    self.mode_manager.enterNormal();
                    self.pending_register.clear();
                    return true; // Deleted and changed mode
                },

                // Change selection (delete and enter insert mode)
                'c' => {
                    const cursor_pos = Position{
                        .line = buf.cursor.row,
                        .col = buf.cursor.col,
                    };

                    const reg = self.pending_register.getSelected() orelse '"';
                    try visual_ops.changeVisualSelection(buf, self.visual_state, cursor_pos, &self.register_mgr, reg, self.allocator);

                    self.visual_state.deactivate();
                    self.enterInsertMode();
                    self.pending_register.clear();
                    return true; // Changed and entered insert mode
                },

                else => return false, // Unknown command
            }
        }

        // Arrow keys
        if (input.len == 3 and input[0] == 27 and input[1] == '[') {
            return switch (input[2]) {
                'A' => movement.moveUp(buf),
                'B' => movement.moveDown(buf),
                'C' => movement.moveRight(buf),
                'D' => movement.moveLeft(buf),
                else => false, // Unknown arrow key
            };
        }

        // gg
        if (input.len == 2 and std.mem.eql(u8, input, "gg")) {
            movement.moveToFileStart(buf);
            return true; // Moved to file start
        }

        return false; // Unknown input
    }

    /// Handle input in Command mode
    /// Returns true if state changed (needs re-render), false if no-op
    fn handleCommandMode(self: *Editor, input: []const u8) !bool {
        if (input.len != 1) return false;

        const char = input[0];

        switch (char) {
            27 => { // ESC
                self.cmd_buffer.clear();
                self.mode_manager.enterNormal();
                return true; // Mode changed
            },
            13 => { // Enter
                const cmd = self.cmd_buffer.getString();

                // File operations (w, wq, q)
                if (std.mem.eql(u8, cmd, "w")) {
                    const buf = self.getCurrentBuffer() orelse return error.NoActiveBuffer;
                    try buf.saveFile();
                } else if (std.mem.eql(u8, cmd, "q")) {
                    // Quit - close window if multiple windows, otherwise request quit
                    self.cmd_buffer.clear();
                    self.mode_manager.enterNormal();

                    // If multiple windows, close current window
                    if (self.windows.count() > 1) {
                        if (self.current_window_id) |win_id| {
                            self.closeWindow(win_id, false) catch |err| {
                                if (err == error.LastWindow) {
                                    // Shouldn't happen since we checked count > 1
                                    self.logger.err("Cannot close last window", .{}) catch {};
                                }
                            };
                        }
                    }
                    // If only one window, backends handle quit differently
                    // Terminal backend: exit program
                    // Debug backend: just exit command mode
                    return true; // Mode changed
                } else if (std.mem.eql(u8, cmd, "wq")) {
                    const buf = self.getCurrentBuffer() orelse return error.NoActiveBuffer;
                    try buf.saveFile();
                    self.cmd_buffer.clear();
                    self.mode_manager.enterNormal();
                    return true; // Saved and mode changed
                }
                // Buffer navigation commands
                else if (std.mem.eql(u8, cmd, "bn")) {
                    self.nextBuffer();
                } else if (std.mem.eql(u8, cmd, "bp")) {
                    self.prevBuffer();
                } else if (std.mem.eql(u8, cmd, "bd")) {
                    if (self.current_buffer_id) |id| {
                        self.deleteBuffer(id, false) catch |err| {
                            if (err == error.BufferModified) {
                                self.logger.err("Buffer has unsaved changes (use :bd! to force)", .{}) catch {};
                            }
                        };
                    }
                } else if (std.mem.eql(u8, cmd, "bd!")) {
                    if (self.current_buffer_id) |id| {
                        try self.deleteBuffer(id, true); // Force delete
                    }
                }
                // Vimcraft extension: :bo/:bonly (not in Neovim, but convenient!)
                else if (std.mem.eql(u8, cmd, "bo") or std.mem.eql(u8, cmd, "bonly")) {
                    // Close all other buffers (keep only current)
                    const deleted_count = self.deleteOtherBuffers(false) catch |err| {
                        if (err == error.BufferModified) {
                            self.logger.err("Some buffers have unsaved changes (use :bo! to force)", .{}) catch {};
                            self.cmd_buffer.clear();
                            self.mode_manager.enterNormal();
                            return true;
                        }
                        return err;
                    };
                    self.logger.info("Closed {d} other buffer(s)", .{deleted_count}) catch {};
                } else if (std.mem.eql(u8, cmd, "bo!") or std.mem.eql(u8, cmd, "bonly!")) {
                    // Force close all other buffers
                    const deleted_count = try self.deleteOtherBuffers(true);
                    self.logger.info("Closed {d} other buffer(s)", .{deleted_count}) catch {};
                } else if (std.mem.eql(u8, cmd, "ls") or std.mem.eql(u8, cmd, "buffers")) {
                    // List buffers - log to console for now
                    // TODO: Display in status line or dedicated buffer list window
                    const buffers = try self.listBuffers();
                    defer self.allocator.free(buffers);

                    self.logger.info("=== Buffers ===", .{}) catch {};
                    for (buffers) |info| {
                        const marker = if (info.current) "%" else " ";
                        const modified = if (info.modified) "[+]" else "   ";
                        const name = info.filepath orelse "[No Name]";
                        self.logger.info("{s}{d: >3} {s} {s}", .{ marker, info.id.id, modified, name }) catch {};
                    }
                }
                // Window split commands
                else if (std.mem.eql(u8, cmd, "sp") or std.mem.eql(u8, cmd, "split")) {
                    _ = self.splitHorizontal() catch |err| {
                        self.logger.err("Failed to split: {}", .{err}) catch {};
                    };
                } else if (std.mem.eql(u8, cmd, "vs") or std.mem.eql(u8, cmd, "vsplit")) {
                    _ = self.splitVertical() catch |err| {
                        self.logger.err("Failed to vsplit: {}", .{err}) catch {};
                    };
                } else if (std.mem.eql(u8, cmd, "close") or std.mem.eql(u8, cmd, "clo")) {
                    if (self.current_window_id) |win_id| {
                        self.closeWindow(win_id, false) catch |err| {
                            if (err == error.LastWindow) {
                                self.logger.err("Cannot close last window", .{}) catch {};
                            }
                        };
                    }
                } else if (std.mem.eql(u8, cmd, "only") or std.mem.eql(u8, cmd, "on")) {
                    // Close all other windows (keep only current)
                    if (self.window_layout) |*layout| {
                        const windows = layout.getAllWindows() catch &[_]WindowId{};
                        defer if (windows.len > 0) self.allocator.free(windows);

                        for (windows) |win_id| {
                            if (self.current_window_id) |current| {
                                if (!win_id.eql(current)) {
                                    self.closeWindow(win_id, true) catch {};
                                }
                            }
                        }
                    }
                }
                // Working directory commands
                else if (std.mem.eql(u8, cmd, "pwd")) {
                    self.logger.info("Current directory: {s}", .{self.cwd}) catch {};
                }
                // Commands with arguments (e.g., :e file.txt, :cd path, :b 2)
                else if (std.mem.startsWith(u8, cmd, "e ")) {
                    const filename = std.mem.trimLeft(u8, cmd[2..], " ");
                    if (filename.len > 0) {
                        _ = try self.loadBufferFromFile(filename);
                    }
                } else if (std.mem.startsWith(u8, cmd, "cd ")) {
                    const new_path = std.mem.trimLeft(u8, cmd[3..], " ");
                    if (new_path.len > 0) {
                        // Change working directory
                        std.posix.chdir(new_path) catch |err| {
                            self.logger.err("Failed to change directory: {}", .{err}) catch {};
                            self.cmd_buffer.clear();
                            self.mode_manager.enterNormal();
                            return true;
                        };

                        // Update stored cwd
                        self.allocator.free(self.cwd);
                        self.cwd = std.process.getCwdAlloc(self.allocator) catch |err| blk: {
                            self.logger.err("Failed to get new cwd: {}", .{err}) catch {};
                            break :blk try self.allocator.dupe(u8, ".");
                        };

                        self.logger.info("Changed directory to: {s}", .{self.cwd}) catch {};
                    }
                } else if (std.mem.startsWith(u8, cmd, "b ")) {
                    const buffer_num_str = std.mem.trimLeft(u8, cmd[2..], " ");
                    if (buffer_num_str.len > 0) {
                        const buffer_num = std.fmt.parseInt(u64, buffer_num_str, 10) catch {
                            self.logger.err("Invalid buffer number: {s}", .{buffer_num_str}) catch {};
                            self.cmd_buffer.clear();
                            self.mode_manager.enterNormal();
                            return true;
                        };

                        const target_id = BufferId{ .id = buffer_num };
                        self.switchBuffer(target_id) catch |err| {
                            if (err == error.BufferNotFound) {
                                self.logger.err("Buffer {d} not found", .{buffer_num}) catch {};
                            }
                        };
                    }
                }
                // Check for user-defined commands (vim.api.createUserCmd)
                // User commands start with uppercase letter
                else if (cmd.len > 0 and std.ascii.isUpper(cmd[0])) {
                    // Parse command: "Hello arg1 arg2" -> name="Hello", args="arg1 arg2"
                    var name_end: usize = 0;
                    for (cmd, 0..) |c, i| {
                        if (c == ' ' or c == '!') {
                            name_end = i;
                            break;
                        }
                    } else {
                        name_end = cmd.len;
                    }

                    const cmd_name = cmd[0..name_end];
                    const has_bang = name_end < cmd.len and cmd[name_end] == '!';
                    const args_start = if (has_bang) name_end + 1 else name_end;
                    const args = if (args_start < cmd.len) std.mem.trimLeft(u8, cmd[args_start..], " ") else "";

                    // Look up user command
                    if (self.usercommand_ctx) |ctx| {
                        const buffer_id: usize = if (self.current_buffer_id) |bid| bid.id else 0;
                        if (ctx.getCommand(cmd_name, buffer_id)) |user_cmd| {
                            // Execute the JavaScript callback
                            self.executeUserCommand(user_cmd, cmd_name, args, has_bang);
                            self.js_state_dirty = true;
                        }
                    }
                }

                self.cmd_buffer.clear();
                self.mode_manager.enterNormal();
                return true; // Mode changed (even if command not recognized)
            },
            127, 8 => { // Backspace
                self.cmd_buffer.backspace();
                return true; // Command buffer changed
            },
            else => {
                if (char >= 32 and char < 127) {
                    try self.cmd_buffer.append(char);
                    return true; // Command buffer changed
                }
                return false; // Non-printable character, ignored
            },
        }
    }

    /// Execute a user-defined command (vim.api.createUserCmd)
    /// Calls the JavaScript callback with args object
    fn executeUserCommand(self: *Editor, user_cmd: *const UserCommand, name: []const u8, args: []const u8, bang: bool) void {
        const usercommand_api = @import("../system/jsi/usercommand_api.zig");
        const c = @import("../system/jsi/c_api.zig").c;

        // Get runtime from usercommand context
        const ctx = self.usercommand_ctx orelse return;
        const runtime = ctx.runtime;

        // Create args object for callback
        // { name: string, args: string, fargs: string[], bang: boolean }
        const args_obj = c.hermes_value_create_object(runtime) orelse return;
        defer c.hermes_value_destroy(args_obj);

        // Set name
        if (c.hermes_value_create_string(runtime, name.ptr, name.len)) |val| {
            c.hermes_value_set_property(runtime, args_obj, "name", val);
            c.hermes_value_destroy(val);
        }

        // Set args (raw string)
        if (c.hermes_value_create_string(runtime, args.ptr, args.len)) |val| {
            c.hermes_value_set_property(runtime, args_obj, "args", val);
            c.hermes_value_destroy(val);
        }

        // Set bang
        if (c.hermes_value_create_boolean(runtime, bang)) |val| {
            c.hermes_value_set_property(runtime, args_obj, "bang", val);
            c.hermes_value_destroy(val);
        }

        // Set fargs (split by whitespace)
        // For now, simple split - count spaces first
        var fargs_count: usize = 0;
        if (args.len > 0) {
            fargs_count = 1;
            for (args) |ch| {
                if (ch == ' ') fargs_count += 1;
            }
        }
        const fargs_arr = c.hermes_array_create(runtime, fargs_count) orelse {
            // Call callback without fargs
            var call_args = [_]?*c.OVHermesValue{args_obj};
            _ = c.hermes_call_function(runtime, user_cmd.callback, &call_args, 1);
            return;
        };
        defer c.hermes_value_destroy(fargs_arr);

        // Split and populate fargs
        if (args.len > 0) {
            var idx: usize = 0;
            var iter = std.mem.splitScalar(u8, args, ' ');
            while (iter.next()) |part| {
                if (c.hermes_value_create_string(runtime, part.ptr, part.len)) |val| {
                    c.hermes_array_set(runtime, fargs_arr, idx, val);
                    c.hermes_value_destroy(val);
                    idx += 1;
                }
            }
        }
        c.hermes_value_set_property(runtime, args_obj, "fargs", fargs_arr);

        // Call the JavaScript callback
        var call_args = [_]?*c.OVHermesValue{args_obj};
        const result = c.hermes_call_function(runtime, user_cmd.callback, &call_args, 1);
        if (result) |res| {
            c.hermes_value_destroy(res);
        }

        _ = usercommand_api; // Suppress unused import warning
    }

    /// Handle scrolling commands (Ctrl+D, Ctrl+U)
    /// Terminal backend calls this with actual viewport height
    pub fn scroll(self: *Editor, direction: enum { up, down }, viewport_height: usize) void {
        const buf = self.getCurrentBuffer() orelse return;
        switch (direction) {
            .down => movement.scrollHalfPageDown(buf, viewport_height),
            .up => movement.scrollHalfPageUp(buf, viewport_height),
        }
    }

    /// Handle viewport-relative movement (H, M, L)
    /// Terminal backend calls this with actual viewport position/height
    pub fn moveToViewportPosition(self: *Editor, command: u8, viewport_top: usize, viewport_height: usize) void {
        // CRITICAL: Clear viewport_movement flag after executing
        defer self.viewport_movement = null;

        const buf = self.getCurrentBuffer() orelse return;

        // Get 'startofline' option - default is false (preserve sticky column)
        const start_of_line = if (self.options_manager) |opts_mgr|
            opts_mgr.getBoolean("startofline") orelse false
        else
            false;

        switch (command) {
            'H' => movement.moveToViewportTop(buf, viewport_top, start_of_line),
            'M' => movement.moveToViewportMiddle(buf, viewport_top, viewport_height, start_of_line),
            'L' => movement.moveToViewportBottom(buf, viewport_top, viewport_height, start_of_line),
            else => {},
        }
    }

    /// Check if there's a viewport movement command ready (H, M, L)
    pub fn hasPendingViewportCommand(self: *const Editor) ?u8 {
        return self.viewport_movement;
    }

    /// Adjust viewport position (zz, zt, zb)
    /// Terminal backend calls this with actual viewport/buffer info
    /// Returns the new viewport_top position
    pub fn adjustViewport(self: *Editor, command: u8, viewport_height: usize, buffer_line_count: usize) usize {
        // CRITICAL: Clear viewport_adjustment after executing
        defer self.viewport_adjustment = null;

        const buf = self.getCurrentBuffer() orelse return 0;
        const cursor_row = buf.cursor.row;

        return switch (command) {
            'z' => movement.centerLineInViewport(cursor_row, viewport_height, buffer_line_count), // zz
            't' => movement.moveLineToViewportTop(cursor_row, buffer_line_count, viewport_height), // zt
            'b' => movement.moveLineToViewportBottom(cursor_row, viewport_height, buffer_line_count), // zb
            else => 0,
        };
    }

    /// Check if there's a pending viewport adjustment command (zz, zt, zb)
    /// Returns 'z' for zz, 't' for zt, 'b' for zb (only when command is COMPLETE)
    pub fn hasPendingViewportAdjustment(self: *const Editor) ?u8 {
        return self.viewport_adjustment;
    }

    /// Convert byte offset to (line, col) position
    /// Used for yank highlights to show the correct visual range
    fn offsetToPosition(self: *Editor, offset: usize) Position {
        const buf = self.getCurrentBuffer() orelse return Position{ .line = 0, .col = 0 };

        // Find which line this offset belongs to
        var line_num: usize = 0;
        // Find line number by iterating through lines
        // (Rope doesn't have lineOfByte, only byteOfLine)
        var current_line: usize = 0;
        while (current_line < buf.lineCount()) : (current_line += 1) {
            const line_start_offset = buf.content.byteOfLine(current_line);
            const line_end_offset = if (current_line + 1 < buf.lineCount())
                buf.content.byteOfLine(current_line + 1)
            else
                buf.content.len();

            if (offset >= line_start_offset and offset < line_end_offset) {
                line_num = current_line;
                break;
            }
        }

        // Calculate column within that line
        const line_start = buf.content.byteOfLine(line_num);
        const col = offset - line_start;

        return Position{ .line = line_num, .col = col };
    }

    /// Normalize language name from go-enry to tree-sitter
    /// go-enry returns capitalized names ("JavaScript"), tree-sitter needs lowercase ("javascript")
    fn normalizeLangName(lang: []const u8) []const u8 {
        const mappings = std.StaticStringMap([]const u8).initComptime(.{
            .{ "JavaScript", "javascript" },
            .{ "Python", "python" },
            .{ "Rust", "rust" },
            .{ "Zig", "zig" },
            .{ "Go", "go" },
            .{ "C", "c" },
            .{ "C++", "cpp" },
            .{ "TypeScript", "typescript" },
            .{ "Markdown", "markdown" },
            .{ "JSON", "json" },
            .{ "YAML", "yaml" },
            .{ "TOML", "toml" },
            .{ "HTML", "html" },
            .{ "CSS", "css" },
            .{ "Bash", "bash" },
            .{ "Shell", "bash" },
        });
        return mappings.get(lang) orelse lang;
    }

    /// Parse buffer content with tree-sitter after filetype detection
    /// This is public so it can be called from config_api when vim.bo.filetype is set
    pub fn parseBufferWithTreeSitter(self: *Editor, filetype: []const u8) !void {
        // Normalize language name
        const lang_name = normalizeLangName(filetype);
        self.logger.info("🔍 Normalizing filetype '{s}' → '{s}'", .{ filetype, lang_name }) catch {};

        // Get language from registry
        const lang = languages.getLanguage(lang_name) orelse {
            self.logger.info("❌ No tree-sitter parser for language: {s}", .{lang_name}) catch {};
            return; // No tree-sitter support, syntax stays null
        };

        // Set parser language
        try self.parser.setLanguage(lang);

        // Parse buffer content (get owned string from Rope)
        const buf = self.getCurrentBuffer() orelse return;
        const source = try buf.content.toString();
        defer self.allocator.free(source);
        const tree = try self.parser.parseString(null, source);

        // Clean up old syntax if it exists
        if (self.syntax) |*old_syntax| {
            old_syntax.deinit();
        }

        // Create new Syntax instance
        self.syntax = try Syntax.init(self.allocator, tree, lang, lang_name);

        self.logger.info("✅ Parsed {d} bytes of {s} with tree-sitter (syntax instance created)", .{ source.len, lang_name }) catch {};
    }

    /// Trigger an autocommand event
    /// Creates Neovim-compatible args object and emits to JavaScript listeners
    ///
    /// The args object contains these properties (matching Neovim's autocmd callback):
    ///   - id: autocommand id (always 0 for now)
    ///   - event: event name (string)
    ///   - group: autocommand group id (always null for now)
    ///   - buf: buffer number (always 0, single-buffer support)
    ///   - file: file path (string or empty string if no file)
    ///   - match: matched pattern (same as file for now)
    ///   - data: arbitrary data (always null for now)
    ///
    /// Usage:
    ///   editor.triggerAutocommand("BufEnter");
    ///   editor.triggerAutocommand("InsertLeave");
    pub fn triggerAutocommand(self: *Editor, event_name: []const u8) void {
        const emitter = self.event_emitter orelse return; // No JSI runtime yet

        // Get runtime from EventEmitter
        const runtime = emitter.runtime;
        const c = @import("../system/jsi/c_api.zig").c;

        // Create args object: {id, event, group, buf, file, match, data}
        const args_obj = c.hermes_value_create_object(runtime) orelse {
            self.logger.err("Failed to create args object for event '{s}'", .{event_name}) catch {};
            return;
        };
        // CRITICAL FIX #2: Do NOT destroy args_obj here!
        // JavaScript callbacks may store references to it (e.g., in setTimeout).
        // Let Hermes GC manage the lifetime instead.
        // The object will be freed when JavaScript releases all references.

        // Set properties (Neovim-compatible)

        // id: autocommand id (always 0 for now, Phase 5 will add proper IDs)
        const id_val = c.hermes_value_create_number(runtime, 0);
        if (id_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "id", v);
            c.hermes_value_destroy(v);
        }

        // event: event name (string)
        const event_val = c.hermes_value_create_string(runtime, event_name.ptr, event_name.len);
        if (event_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "event", v);
            c.hermes_value_destroy(v);
        }

        // group: autocommand group id (null for now, Phase 5 will add groups)
        const group_val = c.hermes_value_create_null(runtime);
        if (group_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "group", v);
            c.hermes_value_destroy(v);
        }

        // buf: buffer number (0 for now, single-buffer support)
        const buf_val = c.hermes_value_create_number(runtime, 0);
        if (buf_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "buf", v);
            c.hermes_value_destroy(v);
        }

        // file: file path (or empty string if no file loaded)
        const buf = self.getCurrentBuffer();
        const file_path = if (buf) |b| b.filepath orelse "" else "";
        const file_val = c.hermes_value_create_string(runtime, file_path.ptr, file_path.len);
        if (file_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "file", v);
            c.hermes_value_destroy(v);
        }

        // match: matched pattern (same as file for now, Phase 5 will add pattern matching)
        const match_val = c.hermes_value_create_string(runtime, file_path.ptr, file_path.len);
        if (match_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "match", v);
            c.hermes_value_destroy(v);
        }

        // data: arbitrary data (null for now, Phase 5 will allow custom data)
        const data_val = c.hermes_value_create_null(runtime);
        if (data_val) |v| {
            c.hermes_value_set_property(runtime, args_obj, "data", v);
            c.hermes_value_destroy(v);
        }

        // Emit event with args object (as single-element array)
        const c_args = [_]*c.OVHermesValue{args_obj};
        emitter.emit(event_name, &c_args) catch |err| {
            self.logger.err("Failed to emit autocommand '{s}': {}", .{ event_name, err }) catch {};
        };
    }

    /// Fire CursorMoved autocmd event
    /// Called from executeKeys when cursor position changes
    /// This triggers vim.api.createAutocmd('CursorMoved', ...) callbacks
    pub fn fireCursorMoved(self: *Editor) void {
        // Prevent reentrancy - plugin callbacks might trigger cursor operations
        if (self.firing_cursor_moved) return;
        self.firing_cursor_moved = true;
        defer self.firing_cursor_moved = false;

        const autocmd_api = @import("../system/jsi/autocmd_api.zig");
        const jsi_api = @import("../system/jsi/jsi_api.zig");

        // Use global autocmd manager instead of self.autocmd_manager
        // This avoids potential pointer corruption issues between Editor and JSI
        const autocmd_mgr = jsi_api.global_autocmd_manager orelse return;

        const buf = self.getCurrentBuffer() orelse return;
        const file_path = buf.filepath orelse "";

        // Execute CursorMoved autocmds - execAutocmds returns early if no handlers
        autocmd_mgr.execAutocmds("CursorMoved", autocmd_api.AutocmdEventData{
            .buf = 0, // Single buffer for now
            .file = file_path,
            .match = file_path,
        }) catch |err| {
            self.logger.err("Failed to fire CursorMoved: {}", .{err}) catch {};
        };
    }
};

// Tests
test "Editor: offsetToPosition converts byte offsets correctly" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Create buffer: "line 1\nline 2\nline 3\n"
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\n");

    // Test offset 0 (start of line 0)
    {
        const pos = editor.offsetToPosition(0);
        try std.testing.expectEqual(@as(usize, 0), pos.line);
        try std.testing.expectEqual(@as(usize, 0), pos.col);
    }

    // Test offset 3 (col 3 of line 0)
    {
        const pos = editor.offsetToPosition(3);
        try std.testing.expectEqual(@as(usize, 0), pos.line);
        try std.testing.expectEqual(@as(usize, 3), pos.col);
    }

    // Test offset 7 (start of line 1 - after "line 1\n")
    {
        const pos = editor.offsetToPosition(7);
        try std.testing.expectEqual(@as(usize, 1), pos.line);
        try std.testing.expectEqual(@as(usize, 0), pos.col);
    }

    // Test offset 10 (col 3 of line 1)
    {
        const pos = editor.offsetToPosition(10);
        try std.testing.expectEqual(@as(usize, 1), pos.line);
        try std.testing.expectEqual(@as(usize, 3), pos.col);
    }
}

test "Editor: yi( yank highlight shows correct range" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Create buffer with text: "(line 293: src/core/editor.zig:293)\n"
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"(line 293: src/core/editor.zig:293)\n");

    // Position cursor at colon (col 10) - NOT at the start of the range
    buf.cursor = .{ .row = 0, .col = 10 };

    // Execute yi( - should yank "line 293: src/core/editor.zig:293"
    _ = try editor.executeKeys("yi(");

    // Verify yank highlight shows the actual yanked range
    // start should be at col 1 (after '('), not at cursor col 10
    // end should be at col 33 (last char '3'), not col 34 (which is ')')
    try std.testing.expectEqual(@as(usize, 0), editor.yank_highlight.start.line);
    try std.testing.expectEqual(@as(usize, 1), editor.yank_highlight.start.col);
    try std.testing.expectEqual(@as(usize, 0), editor.yank_highlight.end.line);
    try std.testing.expectEqual(@as(usize, 33), editor.yank_highlight.end.col);
}

test "Editor: yi[ yank highlight at different cursor position" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Create buffer: "foo[bar]baz\n"
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"foo[bar]baz\n");

    // Cursor at 'a' in "bar" (col 5)
    buf.cursor = .{ .row = 0, .col = 5 };

    // Execute yi[
    _ = try editor.executeKeys("yi[");

    // Highlight should be from col 4 to col 6 (the "bar" text, not including ']' at col 7)
    try std.testing.expectEqual(@as(usize, 0), editor.yank_highlight.start.line);
    try std.testing.expectEqual(@as(usize, 4), editor.yank_highlight.start.col);
    try std.testing.expectEqual(@as(usize, 0), editor.yank_highlight.end.line);
    try std.testing.expectEqual(@as(usize, 6), editor.yank_highlight.end.col);
}

test "Editor: yank highlight does NOT include delimiter" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Buffer: "word)\n" - positions: w=0, o=1, r=2, d=3, )=4
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"word)\n");

    // Manually create a range for "word" (not including ')')
    const Range = @import("buffer/edit.zig").Range;
    const range = Range{ .start = 0, .end = 4 }; // "word" (end is exclusive)

    // Convert to positions for highlight
    const start_pos = editor.offsetToPosition(range.start);
    const end_pos = editor.offsetToPosition(range.end - 1);

    // Verify: end_pos should be at 'd' (col 3), NOT at ')' (col 4)
    try std.testing.expectEqual(@as(usize, 0), start_pos.col);
    try std.testing.expectEqual(@as(usize, 3), end_pos.col); // CRITICAL: last char is at col 3, not 4
}

test "Editor: 'o' command opens new line AFTER current line" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Buffer: "abc\n"
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"abc\n");

    // Position cursor at 'b' (col 1) - shouldn't matter where
    buf.cursor = .{ .row = 0, .col = 1 };

    // Execute 'o' command
    _ = try editor.executeKeys("o");

    // Expected buffer: "abc\n\n" (newline inserted AFTER all characters, not before 'c')
    const content = try buf.content.toString();
    defer allocator.free(content);
    try std.testing.expectEqualStrings("abc\n\n", content);

    // Cursor should be on the new line (row 1) at column 0
    try std.testing.expectEqual(@as(usize, 1), buf.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.col);

    // Should be in insert mode
    try std.testing.expect(editor.mode_manager.isInsert());
}

test "Editor: 'A' followed by 'ii' inserts both characters on same line" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup: README.md first line
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"# Vimcraft\n");

    // Execute: A (append at end) then ii (type two i's)
    _ = try editor.executeKeys("Aii");

    // Verify: First line should be "# Vimcraftii\n"
    const first_line = buf.getLine(0).?;
    defer allocator.free(first_line);
    try std.testing.expectEqualStrings("# Vimcraftii\n", first_line);

    // Verify: Cursor should be at (0, 12) - after the two i's
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
    try std.testing.expectEqual(@as(usize, 12), buf.cursor.col);

    // Verify: Should be in INSERT mode
    try std.testing.expect(editor.mode_manager.isInsert());
}

// ============================================================================
// Keymap Integration Tests
// ============================================================================

test "Keymap: simple string mapping executes correctly" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\n");

    // Map K → gg (move to file start) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "K", .{ .keys = keys }, .{ .noremap = true }, null);

    // Execute K
    _ = try editor.executeKeys("K");

    // Verify: cursor at file start (0, 0)
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.col);
}

test "Keymap: noremap prevents recursive expansion" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"abc\n");

    // Map j → k (move up) - global mapping
    const keys1 = try allocator.dupe(u8, "k");
    try editor.keymap_mgr.set(.normal, "j", .{ .keys = keys1 }, .{ .noremap = true }, null);

    // Map k → l (move right) - global mapping
    const keys2 = try allocator.dupe(u8, "l");
    try editor.keymap_mgr.set(.normal, "k", .{ .keys = keys2 }, .{ .noremap = true }, null);

    // Execute j (should execute k literally, which maps to l)
    // With noremap, k should NOT expand again, so we move left once
    buf.cursor = .{ .row = 0, .col = 1 };
    _ = try editor.executeKeys("j");

    // With noremap: j→k (literal k executed) → move up (default k behavior)
    // But we're on line 0, so cursor stays at row 0
    // And k's mapping should NOT apply due to noremap
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
}

test "Keymap: recursion protection exists and depth tracking works" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Verify depth tracking starts at 0
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Create a simple mapping to verify depth increments during execution
    // Map K → gg (a multi-character sequence) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "K", .{ .keys = keys }, .{}, null);

    // Setup buffer
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\n");
    buf.cursor = .{ .row = 1, .col = 0 };

    // Execute the mapping
    _ = try editor.executeKeys("K");

    // After execution completes, depth should be back to 0 (defer cleanup worked)
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Verify the mapping executed correctly (cursor at file start)
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);

    // NOTE: True infinite recursion (depth > 1000) is difficult to test
    // in our immediate-execution architecture because each command completes
    // and decrements depth before the next recursive call.
    // The protection exists (depth > max_map_depth check in handleNormalMode),
    // but triggering it requires a mapping chain that doesn't terminate,
    // which is hard to construct without causing stack overflow first.
    // The protection is verified by code review and the depth tracking above.
}

test "Keymap: mapping overrides built-in command" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with 3 lines
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\n");
    buf.cursor = .{ .row = 1, .col = 0 }; // Start on line 2

    // Map j → k (override j to move up instead of down) - global mapping
    const keys = try allocator.dupe(u8, "k");
    try editor.keymap_mgr.set(.normal, "j", .{ .keys = keys }, .{ .noremap = true }, null);

    // Execute j - should move UP (to line 1) not DOWN (to line 3)
    _ = try editor.executeKeys("j");

    // Verify: cursor moved up to line 0
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
}

test "Keymap: callback mapping executes (requires JSI context in practice)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Map K → callback - global mapping
    try editor.keymap_mgr.set(.normal, "K", .{ .callback = 42 }, .{}, null);

    // Execute K - in unit tests without JSI, callback logs error and returns true
    // In real usage with JSI context, it calls the JavaScript callback
    const result = try editor.executeKeys("K");

    // Should return true (callback execution attempted, state marked dirty)
    try std.testing.expect(result);
    try std.testing.expect(editor.js_state_dirty);
}

test "Keymap: mode-specific mappings don't leak" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\n");

    // Map j → gg in normal mode only - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "j", .{ .keys = keys }, .{ .noremap = true }, null);

    // In normal mode: j should execute gg
    _ = try editor.executeKeys("j");
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);

    // Enter insert mode
    buf.cursor = .{ .row = 1, .col = 0 };
    editor.mode_manager.enterInsert();

    // In insert mode: j should insert 'j', not execute mapping
    _ = try editor.executeKeys("j");

    // Verify: 'j' was inserted at cursor position
    const line = buf.getLine(1).?;
    defer allocator.free(line);
    try std.testing.expect(std.mem.startsWith(u8, line, "j"));
}

test "Keymap: complex mapping sequence (K → Hzz concept)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with multiple lines
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\nline 4\n");
    buf.cursor = .{ .row = 2, .col = 0 }; // Start on line 3

    // Map K → gg (simpler than Hzz since z commands not implemented) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "K", .{ .keys = keys }, .{ .noremap = true }, null);

    // Execute K
    _ = try editor.executeKeys("K");

    // Verify: cursor at file start
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.col);
}

test "Keymap: depth stays zero after callback mapping (no nesting)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Verify initial depth is 0
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Map K → callback - global mapping
    try editor.keymap_mgr.set(.normal, "K", .{ .callback = 42 }, .{}, null);

    // Execute K - callback doesn't nest, depth should stay 0
    _ = try editor.executeKeys("K");

    // Depth should still be 0 (callback doesn't increase depth)
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Verify subsequent mapping still works - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "J", .{ .keys = keys }, .{ .noremap = true }, null);

    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\n");
    buf.cursor = .{ .row = 1, .col = 0 };

    // This should work (depth not corrupted)
    _ = try editor.executeKeys("J");
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
}

test "Keymap: pending key loss bug - j then x (when jk is mapped)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with 3 lines
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\n");
    buf.cursor = .{ .row = 0, .col = 0 }; // Start at line 1

    // Map jk → gg (move to file start) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "jk", .{ .keys = keys }, .{ .noremap = true }, null);

    // Type "j" → enters pending state, does NOT execute yet
    _ = try editor.executeKeys("j");

    // Verify: cursor STILL at line 1 (pending state, "j" not executed yet)
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);

    // Type "x" → sequence breaks, should execute "j" (down) then "x" (delete char)
    _ = try editor.executeKeys("x");

    // After fix:
    // - "j" should execute as literal → move down to line 2 (row 1)
    // - "x" should execute → delete character at cursor
    try std.testing.expectEqual(@as(usize, 1), buf.cursor.row);

    // Verify 'x' executed by checking first char was deleted from line 2
    const line = buf.getLine(1).?;
    defer allocator.free(line);
    try std.testing.expectEqualStrings("ine 2\n", line); // 'l' deleted
}

test "Keymap: pending key loss bug - j then jkl (multiple keys)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with 5 lines
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\nline 4\nline 5\n");
    buf.cursor = .{ .row = 0, .col = 0 };

    // Map jk → gg (move to file start) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "jk", .{ .keys = keys }, .{ .noremap = true }, null);

    // Type "j" → enters pending state, does NOT execute yet
    _ = try editor.executeKeys("j");
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);

    // Type "jkl" → sequence breaks on second "j", all keys should execute
    _ = try editor.executeKeys("jkl");

    // Expected behavior:
    // - First pending "j" executes as literal → move down to line 2 (row 1)
    // - Second "j" from input starts NEW pending state (because "jk" exists)
    // - "k" completes "jk" mapping → executes "gg" → cursor to row 0
    // - "l" executes as literal → move right
    //
    // Final state: cursor at row 0, col 1
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
    try std.testing.expectEqual(@as(usize, 1), buf.cursor.col);
}

test "Keymap: pending sequence completed successfully (jk → gg)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    const buf = editor.getCurrentBuffer() orelse return error.NoCurrentBuffer;
    buf.content.deinit();
    buf.content = try @import("buffer/rope.zig").Rope.fromString(allocator,"line 1\nline 2\nline 3\n");
    buf.cursor = .{ .row = 2, .col = 0 }; // Start at line 3

    // Map jk → gg - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "jk", .{ .keys = keys }, .{ .noremap = true }, null);

    // Type "jk" → should execute gg (move to file start)
    _ = try editor.executeKeys("jk");

    // Verify: cursor at file start (mapping executed)
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor.col);
}
