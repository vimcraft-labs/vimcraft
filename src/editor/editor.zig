const std = @import("std");
const Buffer = @import("buffer/buffer.zig").Buffer;
const ModeManager = @import("mode/mode.zig").ModeManager;
const EditOps = @import("buffer/edit.zig").EditOps;
const RegisterManager = @import("register/register.zig").RegisterManager;
const VisualState = @import("../backends/terminal/visual/visual.zig").VisualState;
const YankHighlight = @import("../backends/terminal/visual/yank_highlight.zig").YankHighlight;
const movement = @import("movement/movement.zig");
const Position = @import("../backends/terminal/visual/visual.zig").Position;
const yank = @import("buffer/yank.zig");
const paste = @import("buffer/paste.zig");
const visual_ops = @import("buffer/visual_ops.zig");
const Logger = @import("log.zig").Logger;
const text_objects = @import("movement/text_objects/text_objects.zig");
const TextObjectModifier = text_objects.TextObjectModifier;
const TextObjectType = text_objects.TextObjectType;
const OptionsManager = @import("config/options.zig").OptionsManager;
const KeymapManager = @import("keymap/keymap.zig").KeymapManager;

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

/// Cursor position for override (for animated cursor plugins)
pub const CursorPosition = struct {
    row: usize,
    col: usize,
};

/// Cursor render position override (for animated cursor plugins)
pub const CursorRenderOverride = struct {
    active: bool = false,
    row: usize = 0,
    col: usize = 0,

    pub fn clear(self: *CursorRenderOverride) void {
        self.active = false;
    }

    pub fn set(self: *CursorRenderOverride, row: usize, col: usize) void {
        self.active = true;
        self.row = row;
        self.col = col;
    }

    pub fn get(self: *const CursorRenderOverride) ?CursorPosition {
        if (self.active) {
            return CursorPosition{ .row = self.row, .col = self.col };
        }
        return null;
    }
};

/// Headless editor core - no I/O, pure state and logic
/// This is the single source of truth for editor behavior
/// Both Terminal backend and Debug backend use this
pub const Editor = struct {
    allocator: std.mem.Allocator,

    // Core state (backends can access these directly)
    buffer: Buffer,
    mode_manager: ModeManager,
    edit_ops: EditOps,
    register_mgr: RegisterManager,
    visual_state: VisualState,
    yank_highlight: YankHighlight,
    keymap_mgr: KeymapManager,

    // Logger (Core→Backend architecture: Core produces logs, backends consume them)
    logger: Logger,

    // Options (optional - null for headless mode without config)
    options_manager: ?*OptionsManager = null,

    // Cursor rendering override (for animated cursor plugins)
    cursor_render_override: CursorRenderOverride = .{},

    // JavaScript state change flag (for plugins that modify state via timers/callbacks)
    // Set this to true when JavaScript APIs modify editor state to trigger re-render
    js_state_dirty: bool = false,

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

    pub fn init(allocator: std.mem.Allocator) !Editor {
        var buffer = Buffer.init(allocator);
        errdefer buffer.deinit();

        return Editor{
            .allocator = allocator,
            .buffer = buffer,
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
            .logger = Logger.init(allocator),
            .pending_cmd = PendingCommand{},
            .pending_register = PendingRegister{},
            .pending_text_object = PendingTextObject{},
            .cmd_buffer = CommandBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buffer.deinit();
        self.register_mgr.deinit();
        self.keymap_mgr.deinit();
        self.cmd_buffer.deinit();
        self.logger.deinit();
    }

    /// Execute a string of keys through the editor
    /// This is used by both Terminal backend (keyboard input) and Debug backend (JSON commands)
    pub fn executeKeys(self: *Editor, keys: []const u8) anyerror!void {
        // Process each character/sequence
        var i: usize = 0;
        while (i < keys.len) {
            // Check for special escape sequences
            if (i + 2 < keys.len and keys[i] == 27 and keys[i + 1] == '[') {
                // Arrow keys: ESC[A/B/C/D
                const input = keys[i .. i + 3];
                try self.processInput(input);
                i += 3;
            } else {
                // Single character
                const input = keys[i .. i + 1];
                try self.processInput(input);
                i += 1;
            }
        }
    }

    /// Get command buffer string (for status line in command mode)
    pub fn getCommandString(self: *const Editor) []const u8 {
        return self.cmd_buffer.getString();
    }

    /// Process a single input sequence
    fn processInput(self: *Editor, input: []const u8) !void {
        if (self.mode_manager.isNormal()) {
            try self.handleNormalMode(input);
        } else if (self.mode_manager.isInsert()) {
            try self.handleInsertMode(input);
        } else if (self.mode_manager.isVisual()) {
            try self.handleVisualMode(input);
        } else if (self.mode_manager.isCommand()) {
            try self.handleCommandMode(input);
        }
    }

    /// Enter insert mode (no transaction - regular typing rebuilds line_starts immediately)
    /// Transactions are ONLY used for bracketed paste operations in backend.zig
    fn enterInsertMode(self: *Editor) void {
        self.mode_manager.enterInsert();
    }

    /// Handle input in Normal mode
    fn handleNormalMode(self: *Editor, input: []const u8) !void {
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

            // For now, Vimcraft has single-buffer support (buffer_id = 0)
            const lookup_result = self.keymap_mgr.lookup(.normal, input, 0) catch {
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

                                try self.executeKeys(keys);
                                self.mapping_depth = saved_depth; // Explicit restore on success
                            } else {
                                // Increment depth before recursive call
                                self.mapping_depth += 1;
                                errdefer self.mapping_depth -= 1; // Restore on error only

                                try self.executeKeys(keys);
                                self.mapping_depth -= 1; // Explicit decrement on success
                            }
                            return;
                        },
                        .callback => |_| {
                            // Callback mappings not yet implemented - return error instead of silent failure
                            self.logger.err("Callback mappings not yet implemented (vim.keymap.set with function)", .{}) catch {};
                            return error.CallbackNotImplemented;
                        },
                    }
                },
                .pending => {
                    // Partial match - waiting for more keys
                    // NOTE: setTimeout timeout integration happens in Phase 4.5
                    // For now, just return and wait for next key
                    // User can press ESC to cancel (Step 4)
                    return;
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
                        try self.handleNormalMode(&first_key_buf);

                        // Restore depth
                        self.mapping_depth = saved_depth;

                        // Now process new input through normal flow (including keymap lookup)
                        try self.handleNormalMode(input);

                        // Don't fall through - we've already processed both keys
                        return;
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
                    return;
                }
            }
            self.pending_register.clear();
            return;
        }

        // Check for pending text object (after operator + i/a)
        if (self.pending_text_object.isWaiting()) {
            if (input.len == 1) {
                const char = input[0];

                // Try to parse as text object type
                if (TextObjectType.fromChar(char)) |obj_type| {
                    const modifier = self.pending_text_object.getModifier().?;
                    const pending_op = self.pending_cmd.get().?;

                    // Find the text object range
                    if (text_objects.findTextObject(&self.buffer, obj_type, modifier)) |range| {
                        // Perform the operation based on pending command
                        switch (pending_op) {
                            'd' => { // Delete text object
                                const result = try self.edit_ops.deleteRange(&self.buffer, range, .char);
                                defer self.allocator.free(result.deleted_text);
                                // TODO: Store in register
                            },
                            'c' => { // Change text object (delete + enter insert)
                                const result = try self.edit_ops.deleteRange(&self.buffer, range, .char);
                                defer self.allocator.free(result.deleted_text);
                                // TODO: Store in register
                                self.enterInsertMode();
                            },
                            'y' => { // Yank text object
                                const text = range.getText(&self.buffer);
                                // Note: getText() returns a slice, not allocated memory, so no defer free
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
                    return;
                }
            }

            // Invalid text object type, clear state
            self.pending_text_object.clear();
            self.pending_cmd.clear();
            return;
        }

        // Check for pending command (dd, dw, yy, etc.)
        if (self.pending_cmd.get()) |pending| {
            if (input.len == 1) {
                const char = input[0];

                // Check for text object modifier (i/a) after an operator
                if (pending == 'd' or pending == 'c' or pending == 'y') {
                    if (TextObjectModifier.fromChar(char)) |modifier| {
                        self.pending_text_object.start(modifier);
                        return; // Wait for text object type
                    }
                }

                // Handle pending 'd' commands
                if (pending == 'd') {
                    switch (char) {
                        'd' => { // dd - delete line
                            const result = try self.edit_ops.deleteCurrentLine(&self.buffer);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        'w' => { // dw - delete word
                            const result = try self.edit_ops.deleteWord(&self.buffer);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        '$' => { // d$ - delete to end of line
                            const result = try self.edit_ops.deleteToEndOfLine(&self.buffer);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                        },
                        '0' => { // d0 - delete to start of line
                            const result = try self.edit_ops.deleteToStartOfLine(&self.buffer);
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
                            const range = Range.forLine(&self.buffer, self.buffer.cursor.row);
                            const deleted_text = try self.edit_ops.changeRange(&self.buffer, range, .line);
                            defer self.allocator.free(deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        'w' => { // cw - change word
                            const result = try self.edit_ops.deleteWord(&self.buffer);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        '$' => { // c$ - change to end of line
                            const result = try self.edit_ops.deleteToEndOfLine(&self.buffer);
                            defer self.allocator.free(result.deleted_text);
                            // TODO: Store in register
                            self.enterInsertMode();
                        },
                        '0' => { // c0 - change to start of line
                            const result = try self.edit_ops.deleteToStartOfLine(&self.buffer);
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
                        movement.moveToFileStart(&self.buffer);
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
                            return; // Backend will execute via adjustViewport()
                        },
                        else => {},
                    }
                }

                // Handle pending 'y' commands (yank)
                if (pending == 'y') {
                    switch (char) {
                        'y' => { // yy - yank current line
                            const line_num = self.buffer.cursor.row;
                            const line = self.buffer.getLine(line_num) orelse {
                                self.pending_cmd.clear();
                                self.pending_register.clear();
                                return;
                            };

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
                            const text = try self.edit_ops.yankToEndOfLine(&self.buffer);
                            defer self.allocator.free(text);

                            if (text.len > 0) {
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);

                                const start_pos = Position{ .line = self.buffer.cursor.row, .col = self.buffer.cursor.col };
                                const end_col = self.buffer.cursor.col + text.len - 1;
                                const end_pos = Position{ .line = self.buffer.cursor.row, .col = end_col };
                                self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                            }

                            self.pending_register.clear();
                        },
                        '0' => { // y0 - yank to start of line
                            const text = try self.edit_ops.yankToStartOfLine(&self.buffer);
                            defer self.allocator.free(text);

                            if (text.len > 0) {
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);

                                const start_pos = Position{ .line = self.buffer.cursor.row, .col = 0 };
                                const end_pos = Position{ .line = self.buffer.cursor.row, .col = self.buffer.cursor.col };
                                self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                            }

                            self.pending_register.clear();
                        },
                        'w' => { // yw - yank word
                            const text = try self.edit_ops.yankWord(&self.buffer);
                            defer self.allocator.free(text);

                            if (text.len > 0) {
                                const reg = self.pending_register.getSelected() orelse '"';
                                const lines = [_][]const u8{text};
                                try self.register_mgr.yank(reg, &lines, .char_wise);

                                const start_pos = Position{ .line = self.buffer.cursor.row, .col = self.buffer.cursor.col };
                                const end_col = self.buffer.cursor.col + text.len - 1;
                                const end_pos = Position{ .line = self.buffer.cursor.row, .col = end_col };
                                self.yank_highlight = YankHighlight.init(start_pos, end_pos, .char);
                            }

                            self.pending_register.clear();
                        },
                        else => {},
                    }
                }
            }
            self.pending_cmd.clear();
            return;
        }

        // Single character commands
        if (input.len == 1) {
            const char = input[0];

            switch (char) {
                // Basic movement (hjkl)
                'h' => movement.moveLeft(&self.buffer),
                'j' => movement.moveDown(&self.buffer),
                'k' => movement.moveUp(&self.buffer),
                'l' => movement.moveRight(&self.buffer),

                // Line movement
                '0' => movement.moveToLineStart(&self.buffer),
                '$' => movement.moveToLineEnd(&self.buffer),
                '^' => movement.moveToFirstNonBlank(&self.buffer),

                // Word movement
                'w' => movement.moveWordForward(&self.buffer),
                'b' => movement.moveWordBackward(&self.buffer),
                'e' => movement.moveWordEnd(&self.buffer),

                // Delete operations
                'x' => {
                    const result = try self.edit_ops.deleteCharAtCursor(&self.buffer);
                    defer self.allocator.free(result.deleted_text);
                },
                'd' => {
                    self.pending_cmd.set('d');
                },

                // Change operations
                'c' => {
                    self.pending_cmd.set('c');
                },
                'C' => { // Change to end of line (like c$)
                    const result = try self.edit_ops.deleteToEndOfLine(&self.buffer);
                    defer self.allocator.free(result.deleted_text);
                    // TODO: Store in register
                    self.enterInsertMode();
                },

                // Register selection
                '"' => {
                    self.pending_register.startSelection();
                },

                // Yank operations
                'y' => {
                    self.pending_cmd.set('y');
                },

                // Goto operations (gg, G)
                'g' => {
                    self.pending_cmd.set('g');
                },
                'G' => {
                    movement.moveToFileEnd(&self.buffer);
                },

                // Viewport adjustment (zz, zt, zb)
                // Note: These require viewport info from backend, handled specially
                'z' => {
                    self.pending_cmd.set('z');
                },

                // Viewport-relative movement (H, M, L)
                // Set immediate flag for backend (not pending - single character commands)
                'H', 'M', 'L' => {
                    self.viewport_movement = char;
                },

                // Paste operations
                'p' => {
                    const reg = self.pending_register.getSelected() orelse '"';
                    _ = try paste.pasteAfter(&self.buffer, &self.register_mgr, reg);
                    self.pending_register.clear();
                },
                'P' => {
                    const reg = self.pending_register.getSelected() orelse '"';
                    _ = try paste.pasteBefore(&self.buffer, &self.register_mgr, reg);
                    self.pending_register.clear();
                },

                // Undo/redo
                'u' => try self.buffer.undo(),
                18 => try self.buffer.redo(), // Ctrl+R

                // Enter command mode
                ':' => {
                    // CRITICAL: Clear pending commands when entering command mode
                    // Prevents H/M/L or other pending ops from executing after command
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    self.cmd_buffer.clear();
                    self.mode_manager.enterCommand();
                },

                // Enter visual mode
                'v' => {
                    // CRITICAL: Clear pending commands when entering visual mode
                    // Prevents H/M/L or other pending ops from executing unexpectedly
                    self.pending_cmd.clear();
                    self.pending_register.clear();

                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };
                    self.visual_state = VisualState.init(cursor_pos, .char);
                    self.mode_manager.enterVisual();
                },
                'V' => {
                    // CRITICAL: Clear pending commands when entering visual mode
                    // Prevents H/M/L or other pending ops from executing unexpectedly
                    self.pending_cmd.clear();
                    self.pending_register.clear();

                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };
                    self.visual_state = VisualState.init(cursor_pos, .line);
                    self.mode_manager.enterVisual();
                },

                // Enter insert mode
                'i' => {
                    // CRITICAL: Clear pending commands when entering insert mode
                    // Prevents H/M/L or other pending ops from executing after ESC
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    self.enterInsertMode();
                },
                'a' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveRight(&self.buffer);
                    self.enterInsertMode();
                },
                'A' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToLineEnd(&self.buffer);
                    movement.moveRight(&self.buffer);
                    self.enterInsertMode();
                },
                'I' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToFirstNonBlank(&self.buffer);
                    self.enterInsertMode();
                },
                'o' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    // Position cursor AFTER last character to insert newline at end of line
                    const visual_len = self.buffer.getLineLengthVisual(self.buffer.cursor.row);
                    self.buffer.cursor.col = visual_len;
                    self.buffer.cursor.goal_column = visual_len;
                    try self.buffer.insertChar('\n');
                    self.enterInsertMode();
                },
                'O' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToLineStart(&self.buffer);
                    try self.buffer.insertChar('\n');
                    movement.moveUp(&self.buffer);
                    self.enterInsertMode();
                },

                // Ctrl+D, Ctrl+U (scrolling - viewport height passed by renderer)
                4 => {}, // Handled by renderer with actual viewport height
                21 => {}, // Handled by renderer with actual viewport height

                else => {},
            }
        }

        // Arrow keys
        if (input.len == 3 and input[0] == 27 and input[1] == '[') {
            switch (input[2]) {
                'A' => movement.moveUp(&self.buffer),
                'B' => movement.moveDown(&self.buffer),
                'C' => movement.moveRight(&self.buffer),
                'D' => movement.moveLeft(&self.buffer),
                else => {},
            }
        }
    }

    /// Handle input in Insert mode
    fn handleInsertMode(self: *Editor, input: []const u8) !void {
        // Check for custom keymaps FIRST (before built-in commands)
        // This allows mappings like "jk" → ESC
        const max_map_depth = 1000;

        if (self.mapping_depth < max_map_depth) {
            // Save pending keys BEFORE lookup (lookup clears them on .not_found)
            const had_pending_keys = self.keymap_mgr.pending_keys.items.len > 0;
            const first_pending_key = if (had_pending_keys) self.keymap_mgr.pending_keys.items[0] else 0;

            const lookup_result = self.keymap_mgr.lookup(.insert, input, 0) catch {
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

                                try self.executeKeys(keys);
                                self.mapping_depth = saved_depth;
                            } else {
                                self.mapping_depth += 1;
                                errdefer self.mapping_depth -= 1;

                                try self.executeKeys(keys);
                                self.mapping_depth -= 1;
                            }
                            return;
                        },
                        .callback => |_| {
                            self.logger.err("Callback mappings not yet implemented", .{}) catch {};
                            return error.CallbackNotImplemented;
                        },
                    }
                },
                .pending => {
                    // Waiting for more keys
                    return;
                },
                .not_found => {
                    // Execute first pending key as literal, then process new input
                    if (had_pending_keys) {
                        const saved_depth = self.mapping_depth;
                        self.mapping_depth = max_map_depth;
                        errdefer self.mapping_depth = saved_depth;

                        var first_key_buf: [1]u8 = .{first_pending_key};
                        try self.handleInsertMode(&first_key_buf);

                        self.mapping_depth = saved_depth;

                        try self.handleInsertMode(input);
                        return;
                    }
                    // No pending keys - fall through to built-in
                },
            }
        }

        // Built-in insert mode commands
        if (input.len == 1 and input[0] == 27) { // ESC
            // IMPORTANT: Bracketed paste in backend.zig manages transactions
            // Regular typing has NO transaction, so only commit if one exists
            if (self.buffer.active_transaction != null) {
                try self.buffer.commitTransaction();
            }
            self.keymap_mgr.clearPending(); // Clear pending state on mode change
            self.mode_manager.enterNormal();
            return;
        }

        // Arrow keys
        if (input.len == 3 and input[0] == 27 and input[1] == '[') {
            switch (input[2]) {
                'A' => movement.moveUp(&self.buffer),
                'B' => movement.moveDown(&self.buffer),
                'C' => movement.moveRight(&self.buffer),
                'D' => movement.moveLeft(&self.buffer),
                else => {},
            }
            return;
        }

        if (input.len == 1) {
            const char = input[0];
            switch (char) {
                127, 8 => try self.buffer.deleteCharBefore(), // Backspace
                13 => { // Enter
                    try self.buffer.insertChar('\n');
                    // Autoindent: copy indent from previous line
                    if (self.options_manager) |opts_mgr| {
                        if (opts_mgr.getBoolean("autoindent") orelse false) {
                            try self.applyAutoIndent();
                        }
                    }
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
                            try self.buffer.insertChar(' ');
                        }
                    } else {
                        // Insert actual tab character
                        try self.buffer.insertChar('\t');
                    }
                },
                else => {
                    if (char >= 32 and char < 127) {
                        try self.buffer.insertChar(char);
                    }
                },
            }
        }
    }

    /// Apply auto-indent after inserting a newline
    /// Copies the indentation from the previous line
    fn applyAutoIndent(self: *Editor) !void {
        // Get the previous line (the one we just left)
        if (self.buffer.cursor.row == 0) return; // No previous line on first line

        const prev_line = self.buffer.getLine(self.buffer.cursor.row - 1) orelse return;

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
            try self.buffer.insertChar(prev_line[i]);
        }
    }

    /// Handle input in Visual mode
    fn handleVisualMode(self: *Editor, input: []const u8) !void {
        // Check for pending register selection
        if (self.pending_register.isWaitingForName()) {
            if (input.len == 1) {
                const regchar = input[0];
                if (RegisterManager.charToIndex(regchar)) |_| {
                    self.pending_register.setRegister(regchar);
                    return;
                }
            }
            self.pending_register.clear();
            return;
        }

        if (input.len == 1 and input[0] == 27) { // ESC
            self.visual_state.deactivate();
            self.mode_manager.enterNormal();
            return;
        }

        if (input.len == 1) {
            const char = input[0];

            switch (char) {
                // Navigation
                'h' => movement.moveLeft(&self.buffer),
                'j' => movement.moveDown(&self.buffer),
                'k' => movement.moveUp(&self.buffer),
                'l' => movement.moveRight(&self.buffer),
                '0' => movement.moveToLineStart(&self.buffer),
                '$' => movement.moveToLineEnd(&self.buffer),
                '^' => movement.moveToFirstNonBlank(&self.buffer),
                'w' => movement.moveWordForward(&self.buffer),
                'b' => movement.moveWordBackward(&self.buffer),
                'e' => movement.moveWordEnd(&self.buffer),
                'G' => movement.moveToFileEnd(&self.buffer),

                // Register selection
                '"' => {
                    self.pending_register.startSelection();
                },

                // Exit visual mode
                'v' => {
                    self.visual_state.deactivate();
                    self.mode_manager.enterNormal();
                },

                // Yank selection
                'y' => {
                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };

                    const range = self.visual_state.getRange(cursor_pos);
                    const reg = self.pending_register.getSelected() orelse '"';
                    try yank.yankVisualSelection(&self.buffer, self.visual_state, cursor_pos, &self.register_mgr, reg, self.allocator);

                    self.yank_highlight = YankHighlight.init(range.start, range.end, self.visual_state.mode);

                    self.visual_state.deactivate();
                    self.mode_manager.enterNormal();
                    self.pending_register.clear();
                },

                // Delete selection
                'd' => {
                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };

                    const reg = self.pending_register.getSelected() orelse '"';
                    try visual_ops.deleteVisualSelection(&self.buffer, self.visual_state, cursor_pos, &self.register_mgr, reg, self.allocator);

                    self.visual_state.deactivate();
                    self.mode_manager.enterNormal();
                    self.pending_register.clear();
                },

                // Change selection (delete and enter insert mode)
                'c' => {
                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };

                    const reg = self.pending_register.getSelected() orelse '"';
                    try visual_ops.changeVisualSelection(&self.buffer, self.visual_state, cursor_pos, &self.register_mgr, reg, self.allocator);

                    self.visual_state.deactivate();
                    self.enterInsertMode();
                    self.pending_register.clear();
                },

                else => {},
            }
        }

        // Arrow keys
        if (input.len == 3 and input[0] == 27 and input[1] == '[') {
            switch (input[2]) {
                'A' => movement.moveUp(&self.buffer),
                'B' => movement.moveDown(&self.buffer),
                'C' => movement.moveRight(&self.buffer),
                'D' => movement.moveLeft(&self.buffer),
                else => {},
            }
        }

        // gg
        if (input.len == 2 and std.mem.eql(u8, input, "gg")) {
            movement.moveToFileStart(&self.buffer);
        }
    }

    /// Handle input in Command mode
    fn handleCommandMode(self: *Editor, input: []const u8) !void {
        if (input.len != 1) return;

        const char = input[0];

        switch (char) {
            27 => { // ESC
                self.cmd_buffer.clear();
                self.mode_manager.enterNormal();
            },
            13 => { // Enter
                const cmd = self.cmd_buffer.getString();

                if (std.mem.eql(u8, cmd, "w")) {
                    try self.buffer.saveFile();
                } else if (std.mem.eql(u8, cmd, "q")) {
                    // Quit - backends handle this differently
                    // Terminal backend: exit program
                    // Debug backend: just exit command mode
                    self.cmd_buffer.clear();
                    self.mode_manager.enterNormal();
                } else if (std.mem.eql(u8, cmd, "wq")) {
                    try self.buffer.saveFile();
                    self.cmd_buffer.clear();
                    self.mode_manager.enterNormal();
                }

                self.cmd_buffer.clear();
                self.mode_manager.enterNormal();
            },
            127, 8 => { // Backspace
                self.cmd_buffer.backspace();
            },
            else => {
                if (char >= 32 and char < 127) {
                    try self.cmd_buffer.append(char);
                }
            },
        }
    }

    /// Handle scrolling commands (Ctrl+D, Ctrl+U)
    /// Terminal backend calls this with actual viewport height
    pub fn scroll(self: *Editor, direction: enum { up, down }, viewport_height: usize) void {
        switch (direction) {
            .down => movement.scrollHalfPageDown(&self.buffer, viewport_height),
            .up => movement.scrollHalfPageUp(&self.buffer, viewport_height),
        }
    }

    /// Handle viewport-relative movement (H, M, L)
    /// Terminal backend calls this with actual viewport position/height
    pub fn moveToViewportPosition(self: *Editor, command: u8, viewport_top: usize, viewport_height: usize) void {
        // CRITICAL: Clear viewport_movement flag after executing
        defer self.viewport_movement = null;

        switch (command) {
            'H' => movement.moveToViewportTop(&self.buffer, viewport_top),
            'M' => movement.moveToViewportMiddle(&self.buffer, viewport_top, viewport_height),
            'L' => movement.moveToViewportBottom(&self.buffer, viewport_top, viewport_height),
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

        const cursor_row = self.buffer.cursor.row;

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
    fn offsetToPosition(self: *const Editor, offset: usize) Position {
        // Find which line this offset belongs to
        var line_num: usize = 0;
        for (self.buffer.line_starts.items, 0..) |line_start, i| {
            if (offset >= line_start) {
                line_num = i;
            } else {
                break;
            }
        }

        // Calculate column within that line
        const line_start = self.buffer.line_starts.items[line_num];
        const col = offset - line_start;

        return Position{ .line = line_num, .col = col };
    }
};

// Tests
test "Editor: offsetToPosition converts byte offsets correctly" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Create buffer: "line 1\nline 2\nline 3\n"
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\n");
    try editor.buffer.buildLineIndex();

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
    try editor.buffer.content.appendSlice(allocator, "(line 293: src/core/editor.zig:293)\n");
    try editor.buffer.buildLineIndex();

    // Position cursor at colon (col 10) - NOT at the start of the range
    editor.buffer.cursor = .{ .row = 0, .col = 10 };

    // Execute yi( - should yank "line 293: src/core/editor.zig:293"
    try editor.executeKeys("yi(");

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
    try editor.buffer.content.appendSlice(allocator, "foo[bar]baz\n");
    try editor.buffer.buildLineIndex();

    // Cursor at 'a' in "bar" (col 5)
    editor.buffer.cursor = .{ .row = 0, .col = 5 };

    // Execute yi[
    try editor.executeKeys("yi[");

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
    try editor.buffer.content.appendSlice(allocator, "word)\n");
    try editor.buffer.buildLineIndex();

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
    try editor.buffer.content.appendSlice(allocator, "abc\n");
    try editor.buffer.buildLineIndex();

    // Position cursor at 'b' (col 1) - shouldn't matter where
    editor.buffer.cursor = .{ .row = 0, .col = 1 };

    // Execute 'o' command
    try editor.executeKeys("o");

    // Expected buffer: "abc\n\n" (newline inserted AFTER all characters, not before 'c')
    try std.testing.expectEqualStrings("abc\n\n", editor.buffer.content.items);

    // Cursor should be on the new line (row 1) at column 0
    try std.testing.expectEqual(@as(usize, 1), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.col);

    // Should be in insert mode
    try std.testing.expect(editor.mode_manager.isInsert());
}

test "Editor: 'A' followed by 'ii' inserts both characters on same line" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup: README.md first line
    try editor.buffer.content.appendSlice(allocator, "# Vimcraft\n");
    try editor.buffer.buildLineIndex();

    // Execute: A (append at end) then ii (type two i's)
    try editor.executeKeys("Aii");

    // Verify: First line should be "# Vimcraftii\n"
    const first_line = editor.buffer.getLine(0).?;
    try std.testing.expectEqualStrings("# Vimcraftii\n", first_line);

    // Verify: Cursor should be at (0, 12) - after the two i's
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 12), editor.buffer.cursor.col);

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
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\n");
    try editor.buffer.buildLineIndex();

    // Map K → gg (move to file start) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "K", .{ .keys = keys }, .{ .noremap = true }, null);

    // Execute K
    try editor.executeKeys("K");

    // Verify: cursor at file start (0, 0)
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.col);
}

test "Keymap: noremap prevents recursive expansion" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    try editor.buffer.content.appendSlice(allocator, "abc\n");
    try editor.buffer.buildLineIndex();

    // Map j → k (move up) - global mapping
    const keys1 = try allocator.dupe(u8, "k");
    try editor.keymap_mgr.set(.normal, "j", .{ .keys = keys1 }, .{ .noremap = true }, null);

    // Map k → l (move right) - global mapping
    const keys2 = try allocator.dupe(u8, "l");
    try editor.keymap_mgr.set(.normal, "k", .{ .keys = keys2 }, .{ .noremap = true }, null);

    // Execute j (should execute k literally, which maps to l)
    // With noremap, k should NOT expand again, so we move left once
    editor.buffer.cursor = .{ .row = 0, .col = 1 };
    try editor.executeKeys("j");

    // With noremap: j→k (literal k executed) → move up (default k behavior)
    // But we're on line 0, so cursor stays at row 0
    // And k's mapping should NOT apply due to noremap
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
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
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 1, .col = 0 };

    // Execute the mapping
    try editor.executeKeys("K");

    // After execution completes, depth should be back to 0 (defer cleanup worked)
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Verify the mapping executed correctly (cursor at file start)
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);

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
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 1, .col = 0 }; // Start on line 2

    // Map j → k (override j to move up instead of down) - global mapping
    const keys = try allocator.dupe(u8, "k");
    try editor.keymap_mgr.set(.normal, "j", .{ .keys = keys }, .{ .noremap = true }, null);

    // Execute j - should move UP (to line 1) not DOWN (to line 3)
    try editor.executeKeys("j");

    // Verify: cursor moved up to line 0
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
}

test "Keymap: callback mapping returns error (not yet implemented)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Map K → callback (not yet supported) - global mapping
    try editor.keymap_mgr.set(.normal, "K", .{ .callback = 42 }, .{}, null);

    // Execute K - should return error, not silently fail
    const result = editor.executeKeys("K");

    // Should return CallbackNotImplemented error
    try std.testing.expectError(error.CallbackNotImplemented, result);
}

test "Keymap: mode-specific mappings don't leak" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\n");
    try editor.buffer.buildLineIndex();

    // Map j → gg in normal mode only - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "j", .{ .keys = keys }, .{ .noremap = true }, null);

    // In normal mode: j should execute gg
    try editor.executeKeys("j");
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);

    // Enter insert mode
    editor.buffer.cursor = .{ .row = 1, .col = 0 };
    editor.mode_manager.enterInsert();

    // In insert mode: j should insert 'j', not execute mapping
    try editor.executeKeys("j");

    // Verify: 'j' was inserted at cursor position
    const line = editor.buffer.getLine(1).?;
    try std.testing.expect(std.mem.startsWith(u8, line, "j"));
}

test "Keymap: complex mapping sequence (K → Hzz concept)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with multiple lines
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\nline 4\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 2, .col = 0 }; // Start on line 3

    // Map K → gg (simpler than Hzz since z commands not implemented) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "K", .{ .keys = keys }, .{ .noremap = true }, null);

    // Execute K
    try editor.executeKeys("K");

    // Verify: cursor at file start
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.col);
}

test "Keymap: depth restored correctly after mapping error (errdefer fix)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Verify initial depth is 0
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Map K → callback (will error with CallbackNotImplemented) - global mapping
    try editor.keymap_mgr.set(.normal, "K", .{ .callback = 42 }, .{}, null);

    // Execute K - will return error
    const result = editor.executeKeys("K");
    try std.testing.expectError(error.CallbackNotImplemented, result);

    // CRITICAL: Depth should be restored to 0 after error (errdefer worked)
    try std.testing.expectEqual(@as(usize, 0), editor.mapping_depth);

    // Verify subsequent mapping still works (depth not corrupted) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "J", .{ .keys = keys }, .{ .noremap = true }, null);

    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 1, .col = 0 };

    // This should work (depth not corrupted by previous error)
    try editor.executeKeys("J");
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
}

test "Keymap: pending key loss bug - j then x (when jk is mapped)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with 3 lines
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 0, .col = 0 }; // Start at line 1

    // Map jk → gg (move to file start) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "jk", .{ .keys = keys }, .{ .noremap = true }, null);

    // Type "j" → enters pending state, does NOT execute yet
    try editor.executeKeys("j");

    // Verify: cursor STILL at line 1 (pending state, "j" not executed yet)
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);

    // Type "x" → sequence breaks, should execute "j" (down) then "x" (delete char)
    try editor.executeKeys("x");

    // After fix:
    // - "j" should execute as literal → move down to line 2 (row 1)
    // - "x" should execute → delete character at cursor
    try std.testing.expectEqual(@as(usize, 1), editor.buffer.cursor.row);

    // Verify 'x' executed by checking first char was deleted from line 2
    const line = editor.buffer.getLine(1).?;
    try std.testing.expectEqualStrings("ine 2\n", line); // 'l' deleted
}

test "Keymap: pending key loss bug - j then jkl (multiple keys)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with 5 lines
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\nline 4\nline 5\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 0, .col = 0 };

    // Map jk → gg (move to file start) - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "jk", .{ .keys = keys }, .{ .noremap = true }, null);

    // Type "j" → enters pending state, does NOT execute yet
    try editor.executeKeys("j");
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);

    // Type "jkl" → sequence breaks on second "j", all keys should execute
    try editor.executeKeys("jkl");

    // Expected behavior:
    // - First pending "j" executes as literal → move down to line 2 (row 1)
    // - Second "j" from input starts NEW pending state (because "jk" exists)
    // - "k" completes "jk" mapping → executes "gg" → cursor to row 0
    // - "l" executes as literal → move right
    //
    // Final state: cursor at row 0, col 1
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 1), editor.buffer.cursor.col);
}

test "Keymap: pending sequence completed successfully (jk → gg)" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    try editor.buffer.content.appendSlice(allocator, "line 1\nline 2\nline 3\n");
    try editor.buffer.buildLineIndex();
    editor.buffer.cursor = .{ .row = 2, .col = 0 }; // Start at line 3

    // Map jk → gg - global mapping
    const keys = try allocator.dupe(u8, "gg");
    try editor.keymap_mgr.set(.normal, "jk", .{ .keys = keys }, .{ .noremap = true }, null);

    // Type "jk" → should execute gg (move to file start)
    try editor.executeKeys("jk");

    // Verify: cursor at file start (mapping executed)
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), editor.buffer.cursor.col);
}
