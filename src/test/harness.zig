const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;
const Display = @import("../display/display.zig").Display;
const ModeManager = @import("../mode/mode.zig").ModeManager;
const movement = @import("../movement/movement.zig");
const EditOps = @import("../buffer/edit.zig").EditOps;

/// Test harness for headless testing
/// Allows scripting editor commands and seeing visual output
pub const TestHarness = struct {
    buffer: *Buffer,
    display: *Display,
    mode_manager: *ModeManager,
    edit_ops: *EditOps,
    pending_cmd: ?u8 = null,
    allocator: std.mem.Allocator,
    output_file: std.fs.File,
    output_buf: [4096]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        buffer: *Buffer,
        display: *Display,
        mode_manager: *ModeManager,
        edit_ops: *EditOps,
        output_file: std.fs.File,
    ) TestHarness {
        return .{
            .buffer = buffer,
            .display = display,
            .mode_manager = mode_manager,
            .edit_ops = edit_ops,
            .allocator = allocator,
            .output_file = output_file,
            .output_buf = undefined,
        };
    }

    fn write(self: *TestHarness, bytes: []const u8) !void {
        return self.output_file.writeAll(bytes);
    }

    fn print(self: *TestHarness, comptime format: []const u8, args: anytype) !void {
        var w = self.output_file.writer(&self.output_buf);
        const writer = &w.interface;
        return writer.print(format, args);
    }

    /// Execute a command string (like "j", "A", "hello", "ESC")
    pub fn executeCommand(self: *TestHarness, cmd: []const u8) !void {
        try self.print("\n=== COMMAND: '{s}' ===\n", .{cmd});

        // Special commands
        if (std.mem.eql(u8, cmd, "ESC")) {
            try self.handleInput(&[_]u8{27}); // ESC key
        } else if (std.mem.eql(u8, cmd, "ENTER")) {
            try self.handleInput(&[_]u8{13}); // Enter key
        } else if (std.mem.eql(u8, cmd, "BACKSPACE")) {
            try self.handleInput(&[_]u8{127}); // Backspace
        } else if (std.mem.startsWith(u8, cmd, ":")) {
            // Command mode - send : then each character
            try self.handleInput(&[_]u8{':'});
            for (cmd[1..]) |c| {
                try self.handleInput(&[_]u8{c});
            }
            try self.handleInput(&[_]u8{13}); // Enter to execute
        } else {
            // Send each character
            for (cmd) |c| {
                try self.handleInput(&[_]u8{c});
            }
        }

        // Show state after command
        try self.dumpState();
    }

    /// Handle single input character
    fn handleInput(self: *TestHarness, input: []const u8) !void {
        if (self.mode_manager.isNormal()) {
            try self.handleNormalMode(input);
        } else if (self.mode_manager.isInsert()) {
            try self.handleInsertMode(input);
        } else if (self.mode_manager.isCommand()) {
            try self.handleCommandMode(input);
        }
    }

    fn handleNormalMode(self: *TestHarness, input: []const u8) !void {
        // Check for pending command
        if (self.pending_cmd) |pending| {
            if (input.len == 1) {
                const char = input[0];
                if (pending == 'd') {
                    switch (char) {
                        'd' => { // dd - delete line
                            const result = try self.edit_ops.deleteCurrentLine(self.buffer);
                            defer self.allocator.free(result.deleted_text);
                        },
                        'w' => { // dw - delete word
                            const result = try self.edit_ops.deleteWord(self.buffer);
                            defer self.allocator.free(result.deleted_text);
                        },
                        else => {},
                    }
                }
            }
            self.pending_cmd = null;
            return;
        }

        if (input.len == 1) {
            const char = input[0];
            switch (char) {
                'h' => movement.moveLeft(self.buffer),
                'j' => movement.moveDown(self.buffer),
                'k' => movement.moveUp(self.buffer),
                'l' => movement.moveRight(self.buffer),
                '0' => movement.moveToLineStart(self.buffer),
                '$' => movement.moveToLineEnd(self.buffer),
                'w' => movement.moveWordForward(self.buffer),
                'b' => movement.moveWordBackward(self.buffer),
                'x' => { // x - delete character under cursor
                    const result = try self.edit_ops.deleteCharAtCursor(self.buffer);
                    defer self.allocator.free(result.deleted_text);
                },
                'd' => self.pending_cmd = 'd',
                'u' => try self.buffer.undo(),
                'i' => self.mode_manager.enterInsert(),
                'a' => {
                    movement.moveRight(self.buffer);
                    self.mode_manager.enterInsert();
                },
                'A' => {
                    movement.moveToLineEnd(self.buffer);
                    self.mode_manager.enterInsert();
                },
                'o' => {
                    movement.moveToLineEnd(self.buffer);
                    try self.buffer.insertChar('\n');
                    self.mode_manager.enterInsert();
                },
                ':' => self.mode_manager.enterCommand(),
                else => {},
            }
        } else if (input.len == 2 and std.mem.eql(u8, input, "gg")) {
            movement.moveToFileStart(self.buffer);
        }
    }

    fn handleInsertMode(self: *TestHarness, input: []const u8) !void {
        if (input.len == 1 and input[0] == 27) { // ESC
            self.mode_manager.enterNormal();
            return;
        }

        if (input.len == 1) {
            const char = input[0];
            switch (char) {
                127, 8 => try self.buffer.deleteCharBefore(),
                13 => try self.buffer.insertChar('\n'),
                else => {
                    if (char >= 32 and char < 127) {
                        try self.buffer.insertChar(char);
                    }
                },
            }
        }
    }

    fn handleCommandMode(self: *TestHarness, input: []const u8) !void {
        // Simplified - just track the command
        _ = self;
        _ = input;
    }

    /// Dump current editor state in visual format
    pub fn dumpState(self: *TestHarness) !void {
        try self.write("\n");
        try self.print("Mode: {s}\n", .{self.mode_manager.getModeString()});
        try self.print("Cursor: row={}, col={}\n", .{
            self.buffer.cursor.row,
            self.buffer.cursor.col
        });
        try self.print("Lines: {}\n", .{self.buffer.lineCount()});
        try self.write("\n--- BUFFER CONTENT ---\n");

        // Show each line with line numbers
        for (0..self.buffer.lineCount()) |i| {
            const line = self.buffer.getLine(i).?;
            const line_clean = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;

            // Mark cursor line
            const marker = if (i == self.buffer.cursor.row) ">" else " ";
            try self.print("{s}{d:3} | {s}\n", .{ marker, i + 1, line_clean });

            // Show cursor position on this line
            if (i == self.buffer.cursor.row) {
                try self.write("      ");
                var col: usize = 0;
                while (col < self.buffer.cursor.col) : (col += 1) {
                    try self.write(" ");
                }
                try self.write("^\n");
            }
        }

        try self.write("--- END BUFFER ---\n");
        try self.write("\n");
    }

    /// Render what the display would show
    pub fn dumpDisplay(self: *TestHarness, terminal_cols: usize) !void {
        try self.print("\n--- DISPLAY (width={}) ---\n", .{terminal_cols});

        for (0..self.buffer.lineCount()) |i| {
            const line = self.buffer.getLine(i).?;
            const line_clean = if (line.len > 0 and line[line.len - 1] == '\n')
                line[0 .. line.len - 1]
            else
                line;

            // Simulate horizontal scroll on cursor line
            const is_cursor_line = (i == self.buffer.cursor.row);
            const h_offset = if (is_cursor_line and self.buffer.cursor.col >= terminal_cols)
                self.buffer.cursor.col - terminal_cols + 1
            else
                0;

            const start = @min(h_offset, line_clean.len);
            const remaining = line_clean[start..];
            const visible = if (remaining.len > terminal_cols)
                remaining[0..terminal_cols]
            else
                remaining;

            // Show what would be rendered
            try self.print("{s}", .{visible});

            // Fill rest of line with spaces (to terminal width)
            if (visible.len < terminal_cols) {
                var spaces = terminal_cols - visible.len;
                while (spaces > 0) : (spaces -= 1) {
                    try self.write(" ");
                }
            }
            try self.write("|\n"); // | marks edge of terminal

            // Show cursor position on this line
            if (is_cursor_line) {
                const cursor_screen_col = if (self.buffer.cursor.col >= h_offset)
                    self.buffer.cursor.col - h_offset
                else
                    0;

                var col: usize = 0;
                while (col < cursor_screen_col) : (col += 1) {
                    try self.write(" ");
                }
                try self.write("^\n");
            }
        }

        try self.write("--- END DISPLAY ---\n\n");
    }

    /// Assert cursor position
    pub fn assertCursor(self: *TestHarness, row: usize, col: usize) !void {
        if (self.buffer.cursor.row != row or self.buffer.cursor.col != col) {
            try self.print("\n❌ ASSERTION FAILED: Cursor position\n", .{});
            try self.print("  Expected: row={}, col={}\n", .{ row, col });
            try self.print("  Actual:   row={}, col={}\n", .{ self.buffer.cursor.row, self.buffer.cursor.col });
            return error.AssertionFailed;
        }
        try self.print("✓ ASSERT: Cursor at ({}, {})\n", .{ row, col });
    }

    /// Assert line content
    pub fn assertLine(self: *TestHarness, line_num: usize, expected: []const u8) !void {
        const line = self.buffer.getLine(line_num) orelse {
            try self.print("\n❌ ASSERTION FAILED: Line {} does not exist\n", .{line_num});
            return error.AssertionFailed;
        };

        const line_clean = if (line.len > 0 and line[line.len - 1] == '\n')
            line[0 .. line.len - 1]
        else
            line;

        if (!std.mem.eql(u8, line_clean, expected)) {
            try self.print("\n❌ ASSERTION FAILED: Line {} content\n", .{line_num});
            try self.print("  Expected: [{s}]\n", .{expected});
            try self.print("  Actual:   [{s}]\n", .{line_clean});
            return error.AssertionFailed;
        }
        try self.print("✓ ASSERT: Line {} = [{s}]\n", .{ line_num, expected });
    }

    /// Assert line count
    pub fn assertLineCount(self: *TestHarness, expected: usize) !void {
        const actual = self.buffer.lineCount();
        if (actual != expected) {
            try self.print("\n❌ ASSERTION FAILED: Line count\n", .{});
            try self.print("  Expected: {}\n", .{expected});
            try self.print("  Actual:   {}\n", .{actual});
            return error.AssertionFailed;
        }
        try self.print("✓ ASSERT: Line count = {}\n", .{expected});
    }

    /// Assert mode
    pub fn assertMode(self: *TestHarness, expected: []const u8) !void {
        const actual = self.mode_manager.getModeString();
        if (!std.mem.eql(u8, actual, expected)) {
            try self.print("\n❌ ASSERTION FAILED: Mode\n", .{});
            try self.print("  Expected: {s}\n", .{expected});
            try self.print("  Actual:   {s}\n", .{actual});
            return error.AssertionFailed;
        }
        try self.print("✓ ASSERT: Mode = {s}\n", .{expected});
    }
};
