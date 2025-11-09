const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const ModeManager = @import("../mode/mode.zig").ModeManager;
const EditOps = @import("../buffer/edit.zig").EditOps;
const RegisterManager = @import("../register/register.zig").RegisterManager;
const VisualState = @import("../visual/visual.zig").VisualState;
const YankHighlight = @import("../visual/yank_highlight.zig").YankHighlight;
const movement = @import("../movement/movement.zig");
const Position = @import("../visual/visual.zig").Position;
const yank = @import("../buffer/yank.zig");
const paste = @import("../buffer/paste.zig");
const Logger = @import("log.zig").Logger;

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

    // Logger (Core→Backend architecture: Core produces logs, backends consume them)
    logger: Logger,

    // Cursor rendering override (for animated cursor plugins)
    cursor_render_override: CursorRenderOverride = .{},

    // Internal state
    pending_cmd: PendingCommand,
    pending_register: PendingRegister,
    cmd_buffer: CommandBuffer,

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
            .logger = Logger.init(allocator),
            .pending_cmd = PendingCommand{},
            .pending_register = PendingRegister{},
            .cmd_buffer = CommandBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buffer.deinit();
        self.register_mgr.deinit();
        self.cmd_buffer.deinit();
        self.logger.deinit();
    }

    /// Execute a string of keys through the editor
    /// This is used by both Terminal backend (keyboard input) and Debug backend (JSON commands)
    pub fn executeKeys(self: *Editor, keys: []const u8) !void {
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

    /// Handle input in Normal mode
    fn handleNormalMode(self: *Editor, input: []const u8) !void {
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

        // Check for pending command (dd, dw, yy, etc.)
        if (self.pending_cmd.get()) |pending| {
            if (input.len == 1) {
                const char = input[0];

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

                // Handle pending 'g' commands (goto)
                if (pending == 'g') {
                    if (char == 'g') { // gg - go to file start
                        movement.moveToFileStart(&self.buffer);
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
                    self.cmd_buffer.clear();
                    self.mode_manager.enterCommand();
                },

                // Enter visual mode
                'v' => {
                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };
                    self.visual_state = VisualState.init(cursor_pos, .char);
                    self.mode_manager.enterVisual();
                },
                'V' => {
                    const cursor_pos = Position{
                        .line = self.buffer.cursor.row,
                        .col = self.buffer.cursor.col,
                    };
                    self.visual_state = VisualState.init(cursor_pos, .line);
                    self.mode_manager.enterVisual();
                },

                // Enter insert mode
                'i' => self.mode_manager.enterInsert(),
                'a' => {
                    movement.moveRight(&self.buffer);
                    self.mode_manager.enterInsert();
                },
                'A' => {
                    movement.moveToLineEnd(&self.buffer);
                    movement.moveRight(&self.buffer);
                    self.mode_manager.enterInsert();
                },
                'I' => {
                    movement.moveToFirstNonBlank(&self.buffer);
                    self.mode_manager.enterInsert();
                },
                'o' => {
                    movement.moveToLineEnd(&self.buffer);
                    try self.buffer.insertChar('\n');
                    self.mode_manager.enterInsert();
                },
                'O' => {
                    movement.moveToLineStart(&self.buffer);
                    try self.buffer.insertChar('\n');
                    movement.moveUp(&self.buffer);
                    self.mode_manager.enterInsert();
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
        if (input.len == 1 and input[0] == 27) { // ESC
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
                13 => try self.buffer.insertChar('\n'), // Enter
                else => {
                    if (char >= 32 and char < 127) {
                        try self.buffer.insertChar(char);
                    }
                },
            }
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
};
