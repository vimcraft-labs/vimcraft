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
        };
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

        return true; // Continue running
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
