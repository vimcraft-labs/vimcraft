const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;
const Display = @import("display/display.zig").Display;
const highlights = @import("../../editor/config/highlights.zig");
const ListChars = @import("../../editor/config/listchars.zig").ListChars;
const InputHandler = @import("input_handler.zig").InputHandler;

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
    paste_start_time: i64 = 0, // Timestamp when paste started (for timeout)

    // Input handler (Neovim-style persistent buffer - NO timeouts!)
    input_handler: InputHandler,

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
            .paste_buffer = .{},
            .input_handler = InputHandler.init(allocator),
        };
    }

    pub fn deinit(self: *TerminalBackend) void {
        self.paste_buffer.deinit(self.allocator);
        self.input_handler.deinit();
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

        // Only read stdin if poll indicated data is available
        if (poll_result > 0 and poll_fds[0].revents != 0) {
            // CRITICAL: Drain ALL available stdin data before processing sequences
            // This prevents slow byte-by-byte paste accumulation (GitHub issue: paste performance)
            // Keep reading until stdin is empty (read() returns 0 or would block)
            while (true) {
                const bytes_read = try stdin.read(&buf);
                if (bytes_read == 0) break; // EOF or would block

                // Feed bytes to input handler (Neovim pattern: append to persistent buffer)
                try self.input_handler.pushBytes(buf[0..bytes_read]);

                // Check if more data is available (0ms timeout poll)
                poll_fds[0].revents = 0;
                const quick_poll = try posix.poll(&poll_fds, 0);
                if (quick_poll == 0 or poll_fds[0].revents == 0) break; // No more data
            }
        }

        // CRITICAL: Process ALL complete sequences in buffer (may be multiple keys!)
        // InputHandler returns one sequence at a time, so loop until buffer is drained
        while (true) {
            const parse_result = self.input_handler.nextSequence();

            switch (parse_result) {
                .incomplete => {
                    // Partial sequence in buffer - wait for more bytes
                    // NO timeout needed! InputHandler tells us when sequence is incomplete.
                    return true; // Don't render, no state change yet
                },
                .none => {
                    // Buffer empty - all sequences processed
                    return true; // Render already triggered if we processed anything
                },
                .complete => |sequence| {
                    // We have a complete sequence - process it!
                    needs_render.* = true;
                    const input = sequence.bytes;

                    // Handle terminal-specific features first

                    // 0. Bracketed paste mode (ESC[200~ ... ESC[201~)
                    // CRITICAL: handleBracketedPaste returns TRUE if it needs more data from stdin
                    // (e.g., paste started but content/end hasn't arrived yet)
                    // In that case, we must RETURN to wait for next stdin.read()
                    // Otherwise CONTINUE to process remaining sequences in InputHandler buffer
                    if (try self.handleBracketedPaste(input, needs_render)) {
                        return true; // Waiting for more paste data from stdin
                    }

                    // 1. Arrow keys (terminal-specific handling based on mode)
                    if (try self.handleArrowKeys(sequence.kind)) {
                        continue; // Arrow key handled, process next sequence
                    }

                    // 2. Mouse clicks (terminal-specific, not in core editor)
                    if (try self.handleMouseEvent(input)) {
                        continue; // Mouse event handled, process next sequence
                    }

                    // 3. Check for quit command (terminal-specific)
                    if (input.len == 1 and input[0] == 'q' and self.editor.mode_manager.isNormal()) {
                        return false; // Quit
                    }

                    // 3. Ignore Ctrl+V (literal quote key - not yet implemented)
                    // This prevents freezing when user presses Ctrl+V
                    if (input.len == 1 and input[0] == 22) { // Ctrl+V
                        // TODO: Implement literal quote functionality (inserts next char literally)
                        continue; // Ignore and process next sequence
                    }

                    // 4. Handle Ctrl+D/U with actual viewport height (terminal-specific)
                    if (input.len == 1) {
                        const char = input[0];
                        if (char == 4 and self.editor.mode_manager.isNormal()) { // Ctrl+D
                            const viewport_height = self.display.terminal_rows - 1;
                            self.editor.scroll(.down, viewport_height);
                            continue; // Process next sequence
                        } else if (char == 21 and self.editor.mode_manager.isNormal()) { // Ctrl+U
                            const viewport_height = self.display.terminal_rows - 1;
                            self.editor.scroll(.up, viewport_height);
                            continue; // Process next sequence
                        }
                    }

                    // 5. Handle :q and :wq commands (quit is terminal-specific)
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

                    // 6. All other input: delegate to Editor core
                    try self.editor.executeKeys(input);

                    // 7. CRITICAL: If a viewport command (H/M/L) is pending, we need to execute it with up-to-date viewport info
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
                            // needs_render already true from line 100, no need to set again
                        }
                    }

                    // Continue to next sequence in buffer
                },
            }
        }
    }

    /// Handle bracketed paste sequences (ESC[200~ ... ESC[201~)
    /// Returns true if input was part of a paste sequence (handled or accumulating)
    fn handleBracketedPaste(self: *TerminalBackend, input: []const u8, needs_render: *bool) !bool {
        // Limit paste size to prevent memory exhaustion (10MB maximum)
        const max_paste_size = 10 * 1024 * 1024;

        // Bracketed paste start: ESC[200~
        const paste_start = "\x1b[200~";
        // Bracketed paste end: ESC[201~
        const paste_end = "\x1b[201~";

        // Check if we're starting a paste
        if (!self.in_paste and input.len >= paste_start.len) {
            if (std.mem.startsWith(u8, input, paste_start)) {
                self.editor.logger.debug("PASTE: Got paste start sequence!", .{}) catch {};
                self.in_paste = true;
                self.paste_start_time = std.time.milliTimestamp(); // Record start time for timeout
                // Reset state if allocation fails
                errdefer self.in_paste = false;

                self.paste_buffer.clearRetainingCapacity();

                // Accumulate any remaining bytes after the start sequence
                const remaining = input[paste_start.len..];
                if (remaining.len > 0) {
                    self.editor.logger.debug("PASTE: {} bytes after start seq", .{remaining.len}) catch {};
                    try self.paste_buffer.appendSlice(self.allocator, remaining);

                    // CRITICAL: Check if end sequence is already in buffer!
                    // If terminal sends everything at once (ESC[200~TAB ESC[201~),
                    // we have the complete paste in one read
                    if (self.paste_buffer.items.len >= paste_end.len) {
                        if (std.mem.endsWith(u8, self.paste_buffer.items, paste_end)) {
                            self.editor.logger.debug("PASTE: Got complete paste in one read!", .{}) catch {};
                            // Don't return - fall through to paste processing below!
                            // in_paste is already true, paste_buffer has complete content
                        } else {
                            self.editor.logger.debug("PASTE: Waiting for end seq...", .{}) catch {};
                            return true; // Wait for more data
                        }
                    } else {
                        self.editor.logger.debug("PASTE: Waiting for more data...", .{}) catch {};
                        return true; // Wait for more data
                    }
                } else {
                    self.editor.logger.debug("PASTE: Waiting for paste content...", .{}) catch {};
                    return true; // Wait for content
                }
                // NOTE: If we reach here, we have complete paste - process it!
            }
        }

        // If we're in paste mode, accumulate bytes
        if (self.in_paste) {
            self.editor.logger.debug("PASTE: In paste mode, accumulating {} bytes", .{input.len}) catch {};

            // Check for timeout (5 seconds) - prevents infinite wait if paste end never arrives
            const elapsed = std.time.milliTimestamp() - self.paste_start_time;
            if (elapsed > 5000) {
                self.editor.logger.debug("PASTE: TIMEOUT! Aborting paste", .{}) catch {};
                // Timeout - abort paste and reset state
                self.in_paste = false;
                self.paste_buffer.clearRetainingCapacity();
                // Return false to allow input to be processed normally
                // (e.g., if Ctrl+V triggered paste start but no actual paste happened)
                return false;
            }

            // Check size limit before accumulating to prevent DoS
            if (self.paste_buffer.items.len + input.len > max_paste_size) {
                // Paste too large - abort and reset state
                self.in_paste = false;
                self.paste_buffer.clearRetainingCapacity();
                return error.PasteTooLarge;
            }

            try self.paste_buffer.appendSlice(self.allocator, input);

            // Check if paste ended
            if (self.paste_buffer.items.len >= paste_end.len) {
                // Look for paste end sequence
                if (std.mem.endsWith(u8, self.paste_buffer.items, paste_end)) {
                    // Remove the end sequence from buffer
                    const content_len = self.paste_buffer.items.len - paste_end.len;
                    const paste_content = self.paste_buffer.items[0..content_len];

                    // Process the paste at current cursor position
                    self.editor.logger.debug("PASTE: Processing {} bytes of content", .{paste_content.len}) catch {};
                    if (paste_content.len > 0) {
                        const Change = @import("../../editor/buffer/buffer.zig").Change;

                        // If in visual mode, delete the selection first (paste replaces selection)
                        var deletion_undo: ?Change = null;
                        // Save visual state before modifying to enable rollback on error
                        const had_visual_selection = self.editor.mode_manager.isVisual() and self.editor.visual_state.active;
                        const saved_visual_state = if (had_visual_selection)
                            self.editor.visual_state
                        else
                            undefined;

                        if (had_visual_selection) {
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

                        // Rollback transaction and mode on error
                        // Note: Conditional mode restore prevents conflict with inner errdefer
                        errdefer {
                            if (!was_insert) {
                                self.editor.buffer.discardTransaction();
                                // Only restore NORMAL mode if there wasn't a visual selection
                                // (the inner errdefer restores VISUAL mode in that case)
                                if (!had_visual_selection) {
                                    self.editor.mode_manager.enterNormal();
                                }
                            }
                        }

                        // Restore deletion and visual state if paste fails
                        errdefer {
                            if (deletion_undo) |del_change| {
                                // Put deletion back on undo stack so user can still undo it
                                self.editor.buffer.undo_stack.append(self.allocator, del_change) catch {};
                            }
                            if (had_visual_selection) {
                                self.editor.visual_state = saved_visual_state;
                                self.editor.mode_manager.enterVisual();
                            }
                        }

                        // PERFORMANCE FIX: Insert all paste content at once instead of char-by-char
                        // Single insertSlice() is O(N) vs N×insert() which is O(N²) due to memory shifting
                        const start_offset = if (self.editor.buffer.active_transaction) |trans|
                            trans.current_offset
                        else
                            self.editor.buffer.getCursorOffset();

                        // Insert entire paste content at once
                        try self.editor.buffer.content.insertSlice(self.allocator, start_offset, paste_content);

                        // Update transaction state and cursor manually (since we bypassed insertChar loop)
                        if (self.editor.buffer.active_transaction) |*trans| {
                            try trans.text_buffer.appendSlice(self.allocator, paste_content);

                            // Calculate final cursor position after paste
                            var cursor_row = self.editor.buffer.cursor.row;
                            var cursor_col = self.editor.buffer.cursor.col;
                            for (paste_content) |char| {
                                if (char == '\n') {
                                    cursor_row += 1;
                                    cursor_col = 0;
                                } else {
                                    cursor_col += 1;
                                }
                            }
                            self.editor.buffer.cursor.row = cursor_row;
                            self.editor.buffer.cursor.col = cursor_col;
                            trans.cursor_end = self.editor.buffer.cursor;
                            trans.current_offset = start_offset + paste_content.len;
                        }

                        self.editor.buffer.modified = true;

                        // PERFORMANCE FIX: Only rebuild line index if paste contains newlines
                        // buildLineIndex() scans ENTIRE file (O(N) where N = file size)
                        // For single-char pastes (like tabs), this causes massive freeze on large files
                        // ROOT CAUSE: README.md is 4,423 bytes - pasting ONE tab scanned all 4,423 bytes!
                        const contains_newline = std.mem.indexOfScalar(u8, paste_content, '\n') != null;
                        if (contains_newline) {
                            try self.editor.buffer.buildLineIndex();
                        }

                        // CRITICAL FIX: Clamp cursor after paste (transaction still active, line_starts NOW FRESH)
                        // During transaction, cursor.row may have been incremented for newlines,
                        // but line_starts wasn't rebuilt. If cursor.row >= lineCount(), rendering will fail.
                        // Clamp cursor to valid range NOW, before rendering.
                        if (self.editor.buffer.cursor.row >= self.editor.buffer.lineCount()) {
                            if (self.editor.buffer.lineCount() > 0) {
                                self.editor.buffer.cursor.row = self.editor.buffer.lineCount() - 1;
                                const line_len = self.editor.buffer.getLineLengthVisual(self.editor.buffer.cursor.row);
                                self.editor.buffer.cursor.col = line_len;
                            } else {
                                self.editor.buffer.cursor.row = 0;
                                self.editor.buffer.cursor.col = 0;
                            }
                        }

                        // If we had a visual deletion, create combined undo entry
                        if (deletion_undo) |del_change| {
                            // Don't commit the transaction normally - create combined entry
                            if (self.editor.buffer.active_transaction) |trans| {
                                // Allocate inserted_text first (with errdefer cleanup if append fails)
                                const inserted_text = try self.allocator.dupe(u8, trans.text_buffer.items);
                                errdefer self.allocator.free(inserted_text);

                                // Note: Don't free deleted_text here! If append() fails, the outer
                                // errdefer restores del_change to undo_stack, which owns deleted_text.
                                // Freeing it here would cause use-after-free.

                                // Create single undo entry for delete+paste operation
                                const combined_change = Change{
                                    .offset = del_change.offset,
                                    .deleted_text = del_change.deleted_text,
                                    .inserted_text = inserted_text,
                                    .cursor_before = del_change.cursor_before,
                                    .cursor_after = trans.cursor_end,
                                };
                                try self.editor.buffer.undo_stack.append(self.allocator, combined_change);

                                // Free old inserted_text if non-empty (deletion operations have empty inserted_text)
                                if (del_change.inserted_text.len > 0) {
                                    self.allocator.free(del_change.inserted_text);
                                }

                                // Clear redo stack (change was made)
                                for (self.editor.buffer.redo_stack.items) |*c| {
                                    c.deinit(self.allocator);
                                }
                                self.editor.buffer.redo_stack.clearRetainingCapacity();

                                // Discard transaction without committing it
                                self.editor.buffer.discardTransaction();
                            }
                        } else {
                            // Normal paste (no visual deletion) - commit transaction immediately
                            // This allows single ESC to exit insert mode (Vim behavior)
                            if (!was_insert) {
                                self.editor.buffer.commitTransaction() catch {};
                            }
                        }

                        // Exit insert mode automatically (match Vim's bracketed paste behavior)
                        // In Vim, bracketed paste commits immediately and returns to previous mode
                        if (!was_insert) {
                            self.editor.mode_manager.enterNormal();
                        }
                    }

                    // Reset paste state
                    self.in_paste = false;
                    self.paste_buffer.clearRetainingCapacity();
                    needs_render.* = true;

                    self.editor.logger.debug("PASTE: Complete!", .{}) catch {};

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

            // Use saturating addition to prevent integer overflow
            const buffer_row = self.display.viewport_top +| screen_row;
            const text_col = if (screen_col >= gutter_width)
                screen_col - gutter_width
            else
                0;
            const buffer_col = self.display.viewport_left +| text_col;

            // Move cursor to clicked position (clamped to buffer bounds)
            if (buffer_row < self.editor.buffer.lineCount()) {
                const line = self.editor.buffer.getLine(buffer_row) orelse return true;
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

    /// Handle arrow keys (ESC[A/B/C/D)
    /// Returns true if arrow key was handled
    fn handleArrowKeys(self: *TerminalBackend, kind: InputHandler.SequenceKind) !bool {
        const movement_module = @import("../../editor/movement/movement.zig");

        // In insert mode, arrow keys move the cursor (call movement functions directly)
        if (self.editor.mode_manager.isInsert()) {
            switch (kind) {
                .arrow_up => {
                    movement_module.moveUp(&self.editor.buffer);
                    return true;
                },
                .arrow_down => {
                    movement_module.moveDown(&self.editor.buffer);
                    return true;
                },
                .arrow_left => {
                    movement_module.moveLeft(&self.editor.buffer);
                    return true;
                },
                .arrow_right => {
                    movement_module.moveRight(&self.editor.buffer);
                    return true;
                },
                else => return false,
            }
        }

        // In normal mode, arrow keys already work via hjkl mapping
        // So we don't need special handling
        return false;
    }

    /// Render the editor state to terminal
    pub fn render(self: *TerminalBackend) !void {

        // Check if yank highlight has expired and deactivate it (passive timer approach)
        // This matches Neovim's pattern: check during render, deactivate when expired
        if (self.editor.yank_highlight.active and !self.editor.yank_highlight.isVisible()) {
            self.editor.yank_highlight.deactivate();
        }

        // CRITICAL: Sync tab width from vim.opt.tabstop (default 8 to match Vim)
        const char_width = @import("display/char_width.zig");
        const tabstop = if (self.editor.options_manager) |opts|
            @as(usize, @intCast(opts.getNumber("tabstop") orelse 8))
        else
            8;
        char_width.setTabWidth(tabstop);

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

        // Get list/listchars options (for invisible character display)
        const list_enabled = if (self.editor.options_manager) |opts|
            opts.getBoolean("list") orelse false
        else
            false;

        const listchars = if (self.editor.options_manager) |opts| blk: {
            const lcs_str = opts.getString("listchars") orelse "tab:> ,trail:-,nbsp:+";
            break :blk try ListChars.parse(self.allocator, lcs_str);
        } else
            ListChars{};

        // Render to display
        try self.display.render(
            &self.editor.buffer,
            status,
            self.highlight_config,
            &self.editor.visual_state,
            &self.editor.yank_highlight,
            cursor_override,
            list_enabled,
            &listchars,
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
