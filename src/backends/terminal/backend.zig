const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const Display = @import("display/display.zig").Display;
const highlights = @import("../../editor/config/highlights.zig");

/// Terminal backend for interactive editor
/// Wraps the headless Editor core and adds terminal I/O
pub const TerminalBackend = struct {
    allocator: std.mem.Allocator,
    editor: *Editor,
    display: *Display,
    highlight_config: *highlights.HighlightConfig,

    // Bracketed paste state
    in_paste: bool = false,
    paste_buffer: std.ArrayList(u8),

    pub fn init(
        allocator: std.mem.Allocator,
        editor: *Editor,
        display: *Display,
        highlight_config: *highlights.HighlightConfig,
    ) TerminalBackend {
        return .{
            .allocator = allocator,
            .editor = editor,
            .display = display,
            .highlight_config = highlight_config,
            .in_paste = false,
            .paste_buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *TerminalBackend) void {
        self.paste_buffer.deinit(self.allocator);
    }

    /// Handle input with timeout
    /// Returns false to quit, sets needs_render if state changed
    pub fn handleInput(self: *TerminalBackend, timeout_ms: ?i64, needs_render: *bool) !bool {
        const stdin = std.fs.File.stdin();
        var buf: [16]u8 = undefined;

        // Use poll() to wait for input with timeout
        const posix = std.posix;
        var poll_fds = [_]posix.pollfd{
            .{
                .fd = stdin.handle,
                .events = posix.POLL.IN,
                .revents = 0,
            },
        };

        // Convert timeout to milliseconds for poll()
        const poll_timeout: i32 = if (timeout_ms) |t|
            @intCast(@min(t, std.math.maxInt(i32)))
        else
            100;

        const poll_result = try posix.poll(&poll_fds, poll_timeout);

        // If no input available (timeout or no data), return true (continue)
        if (poll_result == 0 or poll_fds[0].revents == 0) {
            return true; // No input, no state change
        }

        // Read input (non-blocking)
        const bytes_read = try stdin.read(&buf);
        if (bytes_read == 0) {
            return true; // No actual data
        }

        // We have input - state will change, need to render
        needs_render.* = true;

        const input = buf[0..bytes_read];

        // Handle terminal-specific features first

        // 0. Bracketed paste mode (ESC[200~ ... ESC[201~)
        if (try self.handleBracketedPaste(input, needs_render)) {
            return true; // Still collecting paste or paste was processed
        }

        // 1. Mouse clicks (terminal-specific, not in core editor)
        if (try self.handleMouseEvent(input)) {
            return true; // Mouse event handled
        }

        // 2. Check for quit command (terminal-specific)
        if (input.len == 1 and input[0] == 'q' and self.editor.mode_manager.isNormal()) {
            return false; // Quit
        }

        // 3. Handle Ctrl+D/U with actual viewport height (terminal-specific)
        if (input.len == 1) {
            const char = input[0];
            if (char == 4 and self.editor.mode_manager.isNormal()) { // Ctrl+D
                const viewport_height = self.display.terminal_rows - 1;
                self.editor.scroll(.down, viewport_height);
                return true;
            } else if (char == 21 and self.editor.mode_manager.isNormal()) { // Ctrl+U
                const viewport_height = self.display.terminal_rows - 1;
                self.editor.scroll(.up, viewport_height);
                return true;
            }
        }

        // 4. Handle :q and :wq commands (quit is terminal-specific)
        if (self.editor.mode_manager.isCommand()) {
            if (input.len == 1 and input[0] == 13) { // Enter in command mode
                const cmd = self.editor.getCommandString();
                if (std.mem.eql(u8, cmd, "q") or std.mem.eql(u8, cmd, "wq")) {
                    // Execute the command in core (saves file if wq)
                    try self.editor.executeKeys(input);
                    // Then quit (terminal-specific)
                    return false;
                }
            }
        }

        // 5. All other input: delegate to Editor core
        try self.editor.executeKeys(input);

        // 6. CRITICAL: If a viewport command (H/M/L) is pending, we need to execute it with up-to-date viewport info
        // The challenge: display.viewport_top is updated during render(), but we haven't rendered yet
        // Solution: Do a quick "dry run" render to update viewport_top, then execute the command
        if (self.editor.mode_manager.isNormal()) {
            if (self.editor.hasPendingViewportCommand()) |cmd| {
                // Force viewport_top calculation by calling the internal viewport adjustment logic
                // This mirrors what display.render() does at lines 478-483 (keep cursor visible)
                // CRITICAL: Protect against integer underflow when terminal_rows = 0 or 1
                const text_rows = if (self.display.terminal_rows > 1)
                    self.display.terminal_rows - 1
                else
                    1;

                // Ensure cursor is in viewport (same logic as display.render())
                if (self.editor.buffer.cursor.row < self.display.viewport_top) {
                    self.display.viewport_top = self.editor.buffer.cursor.row;
                } else if (self.editor.buffer.cursor.row >= self.display.viewport_top + text_rows) {
                    // CRITICAL: Use saturating arithmetic to prevent underflow
                    // If cursor.row < text_rows, non-saturating would wrap to MAX_USIZE
                    self.display.viewport_top = self.editor.buffer.cursor.row -| text_rows +| 1;
                }

                // NOW execute with fresh viewport_top
                const viewport_height = text_rows;
                const viewport_top = self.display.viewport_top;
                self.editor.moveToViewportPosition(cmd, viewport_top, viewport_height);
                // needs_render already true from line 74, no need to set again
            }
        }

        return true; // Continue running
    }

    /// Handle bracketed paste sequences (ESC[200~ ... ESC[201~)
    /// Returns true if input was part of a paste sequence (handled or accumulating)
    fn handleBracketedPaste(self: *TerminalBackend, input: []const u8, needs_render: *bool) !bool {
        // Bracketed paste start: ESC[200~
        const paste_start = "\x1b[200~";
        // Bracketed paste end: ESC[201~
        const paste_end = "\x1b[201~";

        // Check if we're starting a paste
        if (!self.in_paste and input.len >= paste_start.len) {
            if (std.mem.startsWith(u8, input, paste_start)) {
                self.in_paste = true;
                self.paste_buffer.clearRetainingCapacity();

                // Accumulate any remaining bytes after the start sequence
                const remaining = input[paste_start.len..];
                if (remaining.len > 0) {
                    try self.paste_buffer.appendSlice(self.allocator, remaining);
                }

                return true; // Handled - started paste mode
            }
        }

        // If we're in paste mode, accumulate bytes
        if (self.in_paste) {
            try self.paste_buffer.appendSlice(self.allocator, input);

            // Check if paste ended
            if (self.paste_buffer.items.len >= paste_end.len) {
                // Look for paste end sequence
                if (std.mem.endsWith(u8, self.paste_buffer.items, paste_end)) {
                    // Remove the end sequence from buffer
                    const content_len = self.paste_buffer.items.len - paste_end.len;
                    const paste_content = self.paste_buffer.items[0..content_len];

                    // Process the paste at current cursor position
                    if (paste_content.len > 0) {
                        const Change = @import("../../editor/buffer/buffer.zig").Change;

                        // If in visual mode, delete the selection first (paste replaces selection)
                        var deletion_undo: ?Change = null;
                        if (self.editor.mode_manager.isVisual() and self.editor.visual_state.active) {
                            const visual_ops = @import("../../editor/buffer/visual_ops.zig");
                            const Position = @import("visual/visual.zig").Position;

                            const cursor_pos = Position{
                                .line = self.editor.buffer.cursor.row,
                                .col = self.editor.buffer.cursor.col,
                            };
                            const reg = '"'; // Use default register for deleted text

                            // Delete the visual selection (creates an undo entry)
                            try visual_ops.deleteVisualSelection(
                                &self.editor.buffer,
                                self.editor.visual_state,
                                cursor_pos,
                                &self.editor.register_mgr,
                                reg,
                                self.allocator,
                            );

                            // Pop the undo entry - we'll create a combined one
                            if (self.editor.buffer.undo_stack.items.len > 0) {
                                deletion_undo = self.editor.buffer.undo_stack.pop();
                            }

                            // Deactivate visual mode
                            self.editor.visual_state.deactivate();
                            self.editor.mode_manager.enterNormal();
                        }

                        // Enter insert mode if not already in it (starts transaction)
                        const was_insert = self.editor.mode_manager.isInsert();
                        if (!was_insert) {
                            self.editor.mode_manager.enterInsert();
                            self.editor.buffer.beginTransaction();
                        }

                        // Insert each character at the current position
                        for (paste_content) |char| {
                            try self.editor.buffer.insertChar(char);
                        }

                        // If we had a visual deletion, create combined undo entry
                        if (deletion_undo) |del_change| {
                            // Don't commit the transaction normally - create combined entry
                            if (self.editor.buffer.active_transaction) |trans| {
                                // Create single undo entry for delete+paste operation
                                const combined_change = Change{
                                    .offset = del_change.offset,
                                    .deleted_text = del_change.deleted_text, // What was deleted (keep ownership)
                                    .inserted_text = try self.allocator.dupe(u8, trans.text_buffer.items), // What was pasted
                                    .cursor_before = del_change.cursor_before,
                                    .cursor_after = trans.cursor_end,
                                };
                                try self.editor.buffer.undo_stack.append(self.allocator, combined_change);

                                // Free the empty inserted_text from deletion change
                                self.allocator.free(del_change.inserted_text);

                                // Clear redo stack (change was made)
                                for (self.editor.buffer.redo_stack.items) |*c| {
                                    c.deinit(self.allocator);
                                }
                                self.editor.buffer.redo_stack.clearRetainingCapacity();

                                // Discard transaction without committing it
                                self.editor.buffer.discardTransaction();
                            }
                        }
                        // else: Normal paste (no visual deletion) - transaction will be committed on ESC

                        // Stay in insert mode - user can press ESC to exit normally
                        // (Matches Vim behavior: paste enters insert mode, replaces visual selection)
                    }

                    // Reset paste state
                    self.in_paste = false;
                    self.paste_buffer.clearRetainingCapacity();
                    needs_render.* = true;

                    return true; // Paste completed
                }
            }

            return true; // Still accumulating paste
        }

        return false; // Not a paste sequence
    }

    /// Handle mouse events (terminal-specific feature)
    fn handleMouseEvent(self: *TerminalBackend, input: []const u8) !bool {
        // Check for SGR mouse events: ESC[<button;col;row;M or ESC[<button;col;row;m
        if (input.len < 6 or input[0] != 27 or input[1] != '[' or input[2] != '<') {
            return false; // Not a mouse event
        }

        // Parse mouse event
        var button: usize = 0;
        var col: usize = 0;
        var row: usize = 0;
        var is_press = false;

        var idx: usize = 3; // Skip "ESC[<"
        var num_start = idx;

        // Parse button number
        while (idx < input.len and input[idx] != ';') : (idx += 1) {}
        if (idx < input.len) {
            button = std.fmt.parseInt(usize, input[num_start..idx], 10) catch 0;
            idx += 1;
            num_start = idx;
        }

        // Parse column number
        while (idx < input.len and input[idx] != ';') : (idx += 1) {}
        if (idx < input.len) {
            col = std.fmt.parseInt(usize, input[num_start..idx], 10) catch 0;
            idx += 1;
            num_start = idx;
        }

        // Parse row number
        while (idx < input.len and input[idx] != 'M' and input[idx] != 'm') : (idx += 1) {}
        if (idx < input.len) {
            row = std.fmt.parseInt(usize, input[num_start..idx], 10) catch 0;
            is_press = (input[idx] == 'M');
        }

        // Only handle left button press (button 0) in normal mode
        if (is_press and button == 0 and self.editor.mode_manager.isNormal()) {
            // Convert 1-indexed terminal coordinates to 0-indexed
            const screen_row = if (row > 0) row - 1 else 0;
            const screen_col = if (col > 0) col - 1 else 0;

            // Account for gutter width (line numbers, signs, etc.)
            const gutter_width = self.display.gutter_manager.getTotalWidth();

            // Calculate buffer position from screen position
            const buffer_row = self.display.viewport_top + screen_row;
            const text_col = if (screen_col >= gutter_width)
                screen_col - gutter_width
            else
                0;
            const buffer_col = self.display.viewport_left + text_col;

            // Move cursor to clicked position (clamped to buffer bounds)
            if (buffer_row < self.editor.buffer.lineCount()) {
                const line = self.editor.buffer.getLine(buffer_row).?;
                const line_len = if (line.len > 0 and line[line.len - 1] == '\n')
                    line.len - 1
                else
                    line.len;

                self.editor.buffer.cursor.row = buffer_row;
                self.editor.buffer.cursor.col = @min(buffer_col, line_len);
            }
        }

        return true; // Mouse event handled
    }

    /// Render the editor state to terminal
    pub fn render(self: *TerminalBackend) !void {
        // Check if yank highlight has expired and deactivate it (passive timer approach)
        // This matches Neovim's pattern: check during render, deactivate when expired
        if (self.editor.yank_highlight.active and !self.editor.yank_highlight.isVisible()) {
            self.editor.yank_highlight.deactivate();
        }

        // Build status string based on mode
        const status = if (self.editor.mode_manager.isCommand())
            try std.fmt.allocPrint(self.allocator, ":{s}", .{self.editor.getCommandString()})
        else if (self.editor.mode_manager.isVisual() and self.editor.visual_state.active)
            try self.allocator.dupe(u8, self.editor.visual_state.mode.toString())
        else
            try self.allocator.dupe(u8, self.editor.mode_manager.getModeString());
        defer self.allocator.free(status);

        // Get cursor override if active (for animated cursor plugins)
        const cursor_override = self.editor.cursor_render_override.get();

        // Render to display
        try self.display.render(
            &self.editor.buffer,
            status,
            self.highlight_config,
            &self.editor.visual_state,
            &self.editor.yank_highlight,
            cursor_override,
        );

        // Set cursor shape based on mode
        if (self.editor.mode_manager.isInsert()) {
            try self.display.setCursorBar(); // Thin bar in insert mode
        } else {
            try self.display.setCursorBlock(); // Block in normal/command mode
        }

        try self.display.flush();
    }
};
