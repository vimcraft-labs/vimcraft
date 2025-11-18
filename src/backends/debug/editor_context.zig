const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const ModeManager = @import("../../editor/mode/mode.zig").ModeManager;
const EditOps = @import("../../editor/buffer/edit.zig").EditOps;
const RegisterManager = @import("../../editor/register/register.zig").RegisterManager;
const VisualState = @import("../../backends/terminal/visual/visual.zig").VisualState;
const YankHighlight = @import("../../backends/terminal/visual/yank_highlight.zig").YankHighlight;
const Logger = @import("../../editor/log.zig").Logger;
const OptionsManager = @import("../../editor/config/options.zig").OptionsManager;
const KeymapManager = @import("../../editor/keymap/keymap.zig").KeymapManager;
const Loader = @import("../../editor/treesitter/loader.zig").Loader;
const movement = @import("../../editor/movement/movement.zig");
const Position = @import("../../backends/terminal/visual/visual.zig").Position;
const yank = @import("../../editor/buffer/yank.zig");
const paste = @import("../../editor/buffer/paste.zig");

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

/// Complete editor context for headless operation
/// This is what the debug protocol controls
pub const EditorContext = struct {
    allocator: std.mem.Allocator,

    // Core components
    buffer: Buffer,
    display: Display,
    mode_manager: ModeManager,
    edit_ops: EditOps,
    register_mgr: RegisterManager,
    visual_state: VisualState,
    yank_highlight: YankHighlight,
    logger: Logger,
    options_manager: ?*OptionsManager = null,
    keymap_mgr: KeymapManager,
    ts_loader: Loader,

    // Internal state
    pending_cmd: PendingCommand,
    pending_register: PendingRegister,
    cmd_buffer: CommandBuffer,
    mapping_depth: usize = 0,

    // Viewport commands - set when ready for execution
    viewport_movement: ?u8 = null, // H/M/L - move cursor to viewport top/middle/bottom
    viewport_adjustment: ?u8 = null, // zz/zt/zb - adjust viewport to center/top/bottom current line

    pub fn init(allocator: std.mem.Allocator) !EditorContext {
        var buffer = Buffer.init(allocator);
        errdefer buffer.deinit();

        var display = try Display.init(allocator);
        errdefer display.deinit();

        var keymap_mgr = KeymapManager.init(allocator);
        errdefer keymap_mgr.deinit();

        var ts_loader = try Loader.init(allocator);
        errdefer ts_loader.deinit();

        // Note: Display won't actually render since we never call flush() in headless mode

        return EditorContext{
            .allocator = allocator,
            .buffer = buffer,
            .display = display,
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
            .keymap_mgr = keymap_mgr,
            .ts_loader = ts_loader,
            .pending_cmd = PendingCommand{},
            .pending_register = PendingRegister{},
            .cmd_buffer = CommandBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *EditorContext) void {
        self.buffer.deinit();
        self.display.deinit();
        self.register_mgr.deinit();
        self.keymap_mgr.deinit();
        self.ts_loader.deinit();
        self.cmd_buffer.deinit();
        self.logger.deinit();
    }

    /// Execute pending viewport command (H/M/L) or viewport adjustment (zz/zt/zb) if one exists
    /// Returns true if a viewport command was executed
    fn executeViewportCommand(self: *EditorContext) bool {
        if (!self.mode_manager.isNormal()) return false;

        // Check for viewport movement commands (H/M/L)
        if (self.viewport_movement) |cmd| {
            const text_rows = if (self.display.terminal_rows > 1)
                self.display.terminal_rows - 1
            else
                1;

            // CRITICAL FIX: Update viewport_top BEFORE using it (same as terminal backend)
            // This prevents race condition where we use stale viewport_top from previous frame
            // Mirrors display.render() logic at display.zig:478-483
            if (self.buffer.cursor.row < self.display.viewport_top) {
                self.display.viewport_top = self.buffer.cursor.row;
            } else if (self.buffer.cursor.row >= self.display.viewport_top + text_rows) {
                // CRITICAL: Use saturating arithmetic to prevent underflow (matches terminal backend)
                // If cursor.row < text_rows, non-saturating would wrap to MAX_USIZE
                self.display.viewport_top = self.buffer.cursor.row -| text_rows +| 1;
            }

            // NOW execute with fresh viewport_top
            const viewport_height = text_rows;
            const viewport_top = self.display.viewport_top;

            switch (cmd) {
                'H' => movement.moveToViewportTop(&self.buffer, viewport_top),
                'M' => movement.moveToViewportMiddle(&self.buffer, viewport_top, viewport_height),
                'L' => movement.moveToViewportBottom(&self.buffer, viewport_top, viewport_height),
                else => {},
            }

            self.viewport_movement = null;
            return true;
        }

        // Check for viewport adjustment commands (zz/zt/zb)
        // Only execute when viewport_adjustment is set (command is COMPLETE)
        if (self.viewport_adjustment) |adj| {
            const text_rows = if (self.display.terminal_rows > 1)
                self.display.terminal_rows - 1
            else
                1;

            const cursor_row = self.buffer.cursor.row;
            const buffer_line_count = self.buffer.lineCount();

            // Calculate new viewport_top based on command
            const new_viewport_top = switch (adj) {
                'z' => movement.centerLineInViewport(cursor_row, text_rows, buffer_line_count), // zz
                't' => movement.moveLineToViewportTop(cursor_row, buffer_line_count, text_rows), // zt
                'b' => movement.moveLineToViewportBottom(cursor_row, text_rows, buffer_line_count), // zb
                else => self.display.viewport_top,
            };

            // Update viewport and clear the adjustment flag
            self.display.viewport_top = new_viewport_top;
            self.viewport_adjustment = null;
            return true;
        }

        return false;
    }

    /// Execute a string of keys through the editor
    /// This is the main function for debug protocol testing
    pub fn executeKeys(self: *EditorContext, keys: []const u8) !void {
        // Process each character/sequence
        var i: usize = 0;
        while (i < keys.len) {
            // CRITICAL: Check for pending viewport command BEFORE processing next input
            // This allows H/M/L to execute on the next iteration (same pattern as terminal backend)
            if (self.executeViewportCommand()) {
                continue; // Don't process input this iteration
            }

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

        // CRITICAL: After processing all input, check one more time for pending viewport command
        // This handles the case where H/M/L was the LAST key pressed
        _ = self.executeViewportCommand();
    }

    /// Process a single input sequence
    fn processInput(self: *EditorContext, input: []const u8) !void {
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
    fn handleNormalMode(self: *EditorContext, input: []const u8) !void {
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

        // Check for pending command (dd, dw, yy, gg, etc.)
        if (self.pending_cmd.get()) |pending| {
            if (input.len == 1) {
                const char = input[0];

                // Handle pending 'g' commands (goto)
                if (pending == 'g') {
                    if (char == 'g') { // gg - go to file start
                        movement.moveToFileStart(&self.buffer);
                    }
                    self.pending_cmd.clear();
                    return;
                }

                // Handle pending 'z' commands (viewport adjustment)
                // Note: Actual execution happens in executeViewportCommand() on next iteration
                if (pending == 'z') {
                    if (char == 'z' or char == 't' or char == 'b') {
                        // zz, zt, zb - command is COMPLETE, signal for execution
                        self.viewport_adjustment = char; // 'z'=center, 't'=top, 'b'=bottom
                        self.pending_cmd.clear();
                        return; // Will be processed on next iteration
                    }
                    self.pending_cmd.clear();
                    return;
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

                // Viewport-relative movement (H, M, L)
                // Set immediate flag for execution (not pending - single character commands)
                'H', 'M', 'L' => {
                    self.viewport_movement = char;
                },

                // Viewport adjustment (zz, zt, zb)
                // Note: Execution happens on NEXT processInput() call when pending command is detected
                'z' => {
                    self.pending_cmd.set('z');
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
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    self.mode_manager.enterInsert();
                },
                'a' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveRight(&self.buffer);
                    self.mode_manager.enterInsert();
                },
                'A' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToLineEnd(&self.buffer);
                    movement.moveRight(&self.buffer);
                    self.mode_manager.enterInsert();
                },
                'I' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToFirstNonBlank(&self.buffer);
                    self.mode_manager.enterInsert();
                },
                'o' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToLineEnd(&self.buffer);
                    try self.buffer.insertChar('\n');
                    self.mode_manager.enterInsert();
                },
                'O' => {
                    self.pending_cmd.clear();
                    self.pending_register.clear();
                    movement.moveToLineStart(&self.buffer);
                    try self.buffer.insertChar('\n');
                    movement.moveUp(&self.buffer);
                    self.mode_manager.enterInsert();
                },

                // Ctrl+D, Ctrl+U (scrolling - use dummy viewport height)
                4 => movement.scrollHalfPageDown(&self.buffer, 20),
                21 => movement.scrollHalfPageUp(&self.buffer, 20),

                else => {},
            }
        }

        // Multi-character commands
        if (input.len == 2 and std.mem.eql(u8, input, "gg")) {
            movement.moveToFileStart(&self.buffer);
        } else if (input.len == 1 and input[0] == 'G') {
            movement.moveToFileEnd(&self.buffer);
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
    fn handleInsertMode(self: *EditorContext, input: []const u8) anyerror!void {
        // Check for custom keymaps FIRST (before built-in commands)
        // This allows mappings like "jk" → ESC
        const max_map_depth = 1000;

        if (self.mapping_depth < max_map_depth) {
            const had_pending_keys = self.keymap_mgr.pending_keys.items.len > 0;
            const first_pending_key = if (had_pending_keys) self.keymap_mgr.pending_keys.items[0] else 0;

            const lookup_result = self.keymap_mgr.lookup(.insert, input, 0) catch {
                self.keymap_mgr.clearPending();
                return error.KeymapLookupError;
            };

            switch (lookup_result) {
                .matched => |mapping| {
                    // Execute mapping
                    const saved_depth = self.mapping_depth;
                    self.mapping_depth += 1;
                    errdefer self.mapping_depth = saved_depth;

                    try self.executeKeys(mapping.rhs.keys);

                    self.mapping_depth = saved_depth;
                    return;
                },
                .pending => {
                    // Waiting for more keys
                    return;
                },
                .not_found => {
                    // FIX: Execute first pending key as literal, then new input
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
                    // Fall through to built-in insert mode commands
                },
            }
        }

        // Built-in insert mode commands (when no keymap match)
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
    fn applyAutoIndent(self: *EditorContext) !void {
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
    fn handleVisualMode(self: *EditorContext, input: []const u8) !void {
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
    fn handleCommandMode(self: *EditorContext, input: []const u8) !void {
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
                    // Quit - in headless mode, just exit command mode
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
};
