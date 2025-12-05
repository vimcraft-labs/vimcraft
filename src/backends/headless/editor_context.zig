const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const Display = @import("../../backends/terminal/display/display.zig").Display;
const Editor = @import("../../editor/editor.zig").Editor;
const VisualState = @import("../../editor/visual/visual.zig").VisualState;
const YankHighlight = @import("../../editor/visual/yank_highlight.zig").YankHighlight;
const Logger = @import("../../editor/log.zig").Logger;
const OptionsManager = @import("../../editor/config/options.zig").OptionsManager;
const KeymapManager = @import("../../editor/keymap/keymap.zig").KeymapManager;
const Loader = @import("../../editor/treesitter/loader.zig").Loader;
const HighlightRegistry = @import("../../system/jsi/highlight_api.zig").HighlightRegistry;
const movement = @import("../../editor/movement/movement.zig");
const Position = @import("../../editor/visual/visual.zig").Position;
const ModeManager = @import("../../editor/mode/mode.zig").ModeManager;
const RegisterManager = @import("../../editor/register/register.zig").RegisterManager;
const Syntax = @import("../../editor/treesitter/syntax.zig").Syntax;
const Parser = @import("../../editor/treesitter/parser.zig").Parser;

/// Complete editor context for headless operation
/// This wraps the core Editor and adds Display for viewport calculations
/// The debug protocol controls this
pub const EditorContext = struct {
    allocator: std.mem.Allocator,

    /// Core editor (owns buffer, mode_manager, register_mgr, etc.)
    /// All command execution is delegated to this
    editor: Editor,

    /// Display for viewport calculations (headless - no actual rendering)
    /// Required for H/M/L viewport-relative commands
    display: Display,

    pub fn init(allocator: std.mem.Allocator) !EditorContext {
        var editor = try Editor.init(allocator);
        errdefer editor.deinit();

        var display = try Display.init(allocator);
        errdefer display.deinit();

        var ctx = EditorContext{
            .allocator = allocator,
            .editor = editor,
            .display = display,
        };

        // CRITICAL: Sync terminal dimensions from Display to Editor
        // This ensures splitWindow/relayout use correct dimensions from start
        ctx.syncTerminalDimensions();

        return ctx;
    }

    pub fn deinit(self: *EditorContext) void {
        self.editor.deinit();
        self.display.deinit();
    }

    // =========================================================================
    // Convenience Accessors (delegate to Editor or its components)
    // =========================================================================

    /// Get current buffer (convenience accessor)
    pub fn buffer(self: *EditorContext) *Buffer {
        return self.editor.getCurrentBuffer() orelse unreachable; // Editor always has at least one buffer
    }

    /// Get mode manager (convenience accessor)
    pub fn mode_manager(self: *EditorContext) *ModeManager {
        return &self.editor.mode_manager;
    }

    /// Get register manager (convenience accessor)
    pub fn register_mgr(self: *EditorContext) *RegisterManager {
        return &self.editor.register_mgr;
    }

    /// Get visual state (convenience accessor)
    pub fn visual_state(self: *EditorContext) *VisualState {
        return &self.editor.visual_state;
    }

    /// Get yank highlight (convenience accessor)
    pub fn yank_highlight(self: *EditorContext) *YankHighlight {
        return &self.editor.yank_highlight;
    }

    /// Get logger (convenience accessor)
    pub fn logger(self: *EditorContext) *Logger {
        return &self.editor.logger;
    }

    /// Get options manager (convenience accessor)
    pub fn options_manager(self: *EditorContext) ?*OptionsManager {
        return self.editor.options_manager;
    }

    /// Set options manager
    pub fn setOptionsManager(self: *EditorContext, opts_mgr: *OptionsManager) void {
        self.editor.options_manager = opts_mgr;
    }

    /// Get keymap manager (convenience accessor)
    pub fn keymap_mgr(self: *EditorContext) *KeymapManager {
        return &self.editor.keymap_mgr;
    }

    /// Get tree-sitter loader (convenience accessor)
    pub fn ts_loader(self: *EditorContext) *Loader {
        return &self.editor.ts_loader;
    }

    /// Get highlight registry (convenience accessor)
    pub fn highlight_registry(self: *EditorContext) *HighlightRegistry {
        return &self.editor.highlight_registry;
    }

    /// Get tree-sitter parser (convenience accessor)
    pub fn parser(self: *EditorContext) *Parser {
        return &self.editor.parser;
    }

    /// Get syntax from current buffer (per-buffer syntax following Neovim architecture)
    pub fn syntax(self: *EditorContext) ?*Syntax {
        const buf = self.editor.getCurrentBuffer() orelse return null;
        return buf.syntax;
    }

    // =========================================================================
    // Core Operations (delegate to Editor with viewport tracking)
    // =========================================================================

    /// Execute pending viewport command (H/M/L) or viewport adjustment (zz/zt/zb) if one exists
    /// Returns true if a viewport command was executed
    fn executeViewportCommand(self: *EditorContext) bool {
        if (!self.editor.mode_manager.isNormal()) return false;

        const buf = self.buffer();

        // Check for viewport movement commands (H/M/L)
        if (self.editor.viewport_movement) |cmd| {
            const text_rows = if (self.display.terminal_rows > 1)
                self.display.terminal_rows - 1
            else
                1;

            // Use Editor's window viewport as the canonical source
            var viewport_top = self.editor.getViewportTop();

            // CRITICAL FIX: Update viewport_top BEFORE using it (same as terminal backend)
            // This prevents race condition where we use stale viewport_top from previous frame
            if (buf.cursor.row < viewport_top) {
                viewport_top = buf.cursor.row;
                self.editor.setViewportTop(viewport_top);
            } else if (buf.cursor.row >= viewport_top + text_rows) {
                // CRITICAL: Use saturating arithmetic to prevent underflow
                viewport_top = buf.cursor.row -| text_rows +| 1;
                self.editor.setViewportTop(viewport_top);
            }

            // NOW execute with fresh viewport_top
            const viewport_height = text_rows;

            // Get 'startofline' option - default is false (preserve sticky column)
            const start_of_line = if (self.editor.options_manager) |opts_mgr|
                opts_mgr.getBoolean("startofline") orelse false
            else
                false;

            switch (cmd) {
                'H' => movement.moveToViewportTop(buf, viewport_top, start_of_line),
                'M' => movement.moveToViewportMiddle(buf, viewport_top, viewport_height, start_of_line),
                'L' => movement.moveToViewportBottom(buf, viewport_top, viewport_height, start_of_line),
                else => {},
            }

            self.editor.viewport_movement = null;
            return true;
        }

        // Check for viewport adjustment commands (zz/zt/zb)
        if (self.editor.viewport_adjustment) |adj| {
            const text_rows = if (self.display.terminal_rows > 1)
                self.display.terminal_rows - 1
            else
                1;

            const cursor_row = buf.cursor.row;
            const buffer_line_count = buf.lineCount();

            // Calculate new viewport_top based on command
            const new_viewport_top = switch (adj) {
                'z' => movement.centerLineInViewport(cursor_row, text_rows, buffer_line_count), // zz
                't' => movement.moveLineToViewportTop(cursor_row, buffer_line_count, text_rows), // zt
                'b' => movement.moveLineToViewportBottom(cursor_row, text_rows, buffer_line_count), // zb
                else => self.editor.getViewportTop(),
            };

            // Update viewport using Editor's canonical setter
            self.editor.setViewportTop(new_viewport_top);

            // Also update Window viewport to match
            if (self.editor.getCurrentWindow()) |win| {
                win.viewport.top_line = new_viewport_top;
            }

            // CRITICAL: Set flag to skip ensureCursorVisible in render
            self.editor.skip_ensure_cursor_visible = true;

            self.editor.viewport_adjustment = null;
            return true;
        }

        return false;
    }

    /// Sync terminal dimensions from Display to Editor
    /// CRITICAL: Editor.terminal_rows/cols are used by splitWindow/relayout
    /// Without this sync, window splits use default 24x80 dimensions
    pub fn syncTerminalDimensions(self: *EditorContext) void {
        self.display.syncDimensionsToEditor(&self.editor);
    }

    /// Execute a string of keys through the editor
    /// This is the main function for debug protocol testing
    pub fn executeKeys(self: *EditorContext, keys: []const u8) !void {
        // CRITICAL: Sync terminal dimensions before processing commands
        // Commands like :vsplit use Editor.terminal_rows/cols for layout calculation
        self.syncTerminalDimensions();

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
                _ = try self.editor.executeKeys(input);
                i += 3;
            } else {
                const char = keys[i];

                // Handle Ctrl+D (4) and Ctrl+U (21) - scroll commands
                // These are handled by the renderer in terminal backend, so we need to handle them here
                if (char == 4 or char == 21) {
                    const text_rows = if (self.display.terminal_rows > 1)
                        self.display.terminal_rows - 1
                    else
                        1;

                    if (char == 4) {
                        // Ctrl+D - scroll half page down
                        self.editor.scroll(.down, text_rows);
                    } else {
                        // Ctrl+U - scroll half page up
                        self.editor.scroll(.up, text_rows);
                    }
                    i += 1;
                    continue;
                }

                // Single character
                const input = keys[i .. i + 1];
                _ = try self.editor.executeKeys(input);
                i += 1;
            }
        }

        // CRITICAL: After processing all input, check one more time for pending viewport command
        // This handles the case where H/M/L was the LAST key pressed
        _ = self.executeViewportCommand();

        // Update viewport to keep cursor visible (simulates terminal backend render)
        // This is safe because ensureCursorVisibleInViewport only adjusts viewport
        // if cursor is outside visible bounds - it won't override zz/zt/zb centering
        // if the cursor is already visible in the centered position
        self.updateViewportForCursor();
    }

    /// Update viewport_top to keep cursor visible within viewport bounds
    /// This simulates what happens in terminal backend's render() function
    fn updateViewportForCursor(self: *EditorContext) void {
        const text_rows = if (self.display.terminal_rows > 1)
            self.display.terminal_rows - 1
        else
            1;

        // Use Editor's canonical ensureCursorVisibleInViewport
        self.editor.ensureCursorVisibleInViewport(text_rows);
    }

    /// Load file and detect filetype (delegates to Editor)
    pub fn loadFile(self: *EditorContext, path: []const u8) !void {
        try self.editor.loadFile(path);
    }
};

// Include viewport scroll tests for test discovery
test {
    _ = @import("viewport_scroll_tests.zig");
}
