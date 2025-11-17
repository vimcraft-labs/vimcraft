/// Unix Domain Socket Debug Server for Terminal Backend
/// Allows querying editor state without interfering with terminal I/O
const std = @import("std");
const Display = @import("display/display.zig").Display;
const Editor = @import("../../editor/editor.zig").Editor;
const highlights = @import("../../editor/config/highlights.zig");
const protocol = @import("../debug/protocol.zig");
const json = @import("../debug/json.zig");
const handlers = @import("../debug/handlers.zig");

/// Debug socket server that runs alongside terminal backend
pub const DebugSocket = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    server: std.net.Server,
    thread: ?std.Thread = null,
    running: bool = false,

    // References to editor state (read-only access)
    editor: *Editor,
    display: *Display,
    highlight_config: *highlights.HighlightConfig,

    pub fn init(
        allocator: std.mem.Allocator,
        socket_path: []const u8,
        editor: *Editor,
        display: *Display,
        highlight_config: *highlights.HighlightConfig,
    ) !DebugSocket {
        // Remove old socket if it exists
        std.fs.deleteFileAbsolute(socket_path) catch {};

        // Create Unix domain socket
        const address = try std.net.Address.initUnix(socket_path);
        const server = try address.listen(.{});

        return .{
            .allocator = allocator,
            .socket_path = socket_path,
            .server = server,
            .editor = editor,
            .display = display,
            .highlight_config = highlight_config,
        };
    }

    pub fn deinit(self: *DebugSocket) void {
        self.running = false;
        if (self.thread) |thread| {
            thread.join();
        }
        self.server.deinit();
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
    }

    /// Start the debug server in a background thread
    pub fn start(self: *DebugSocket) !void {
        self.running = true;
        self.thread = try std.Thread.spawn(.{}, serverLoop, .{self});
    }

    /// Server loop (runs in background thread)
    fn serverLoop(self: *DebugSocket) void {
        while (self.running) {
            // Accept connection (with timeout)
            const connection = self.server.accept() catch continue;
            defer connection.stream.close();

            // Handle one request
            self.handleRequest(connection.stream) catch {};
        }
    }

    /// Handle a single debug protocol request
    fn handleRequest(self: *DebugSocket, stream: std.net.Stream) !void {
        var buf: [8192]u8 = undefined;
        const len = try stream.read(&buf);
        if (len == 0) return;

        const request = std.mem.trim(u8, buf[0..len], " \t\r\n");

        // Parse command using debug protocol JSON parser
        var cmd = json.parseCommand(request, self.allocator) catch |err| {
            const err_str = try std.fmt.allocPrint(self.allocator, "Parse error: {}", .{err});
            defer self.allocator.free(err_str);

            const response = try json.createErrorResponse(self.allocator, "unknown", err_str, 0);
            defer {
                var mut_response = response;
                mut_response.deinit(self.allocator);
            }

            const response_json = try json.serializeResponse(response, self.allocator);
            defer self.allocator.free(response_json);

            try stream.writeAll(response_json);
            return;
        };
        defer cmd.deinit(self.allocator);

        const start_time = std.time.nanoTimestamp();

        // Execute command by reading current editor state
        const result = self.executeCommand(cmd) catch |err| {
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
            const err_str = try std.fmt.allocPrint(self.allocator, "Command failed: {}", .{err});
            defer self.allocator.free(err_str);

            const response = try json.createErrorResponse(self.allocator, cmd.id, err_str, duration);
            defer {
                var mut_response = response;
                mut_response.deinit(self.allocator);
            }

            const response_json = try json.serializeResponse(response, self.allocator);
            defer self.allocator.free(response_json);

            try stream.writeAll(response_json);
            return;
        };

        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
        const response = try json.createSuccessResponse(self.allocator, cmd.id, result, duration);
        defer {
            var mut_response = response;
            mut_response.deinit(self.allocator);
        }

        const response_json = try json.serializeResponse(response, self.allocator);
        defer self.allocator.free(response_json);

        try stream.writeAll(response_json);
    }

    /// Execute a command and return the result
    /// Snapshots the current Terminal editor state for read-only query
    fn executeCommand(self: *DebugSocket, cmd: protocol.Command) !protocol.ResponseResult {
        return switch (cmd.cmd) {
            .ping => .{ .pong = .{ .version = try self.allocator.dupe(u8, protocol.PROTOCOL_VERSION) } },

            .shutdown => .{ .none = {} }, // Socket doesn't control Terminal lifecycle

            .get_state => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = self.display,
                };
                return try handlers.handleGetState(ctx);
            },

            .get_cursor => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = self.display,
                };
                return try handlers.handleGetCursor(ctx);
            },

            .get_mode => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = self.display,
                };
                return try handlers.handleGetMode(ctx);
            },

            .get_gutter_state => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = self.display,
                };
                return try handlers.handleGetGutterState(ctx);
            },

            .get_terminal_updates => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = self.display,
                };
                return try handlers.handleGetTerminalUpdates(ctx);
            },

            // Read-only socket - these commands not supported
            .execute_keys,
            .load_file,
            .save_file,
            .set_buffer,
            .set_cursor,
            .set_mode,
            .set_option,
            .get_visual,
            .get_registers,
            .get_register,
            .get_buffer,
            .get_layers,
            .get_layer,
            .get_layer_cells,
            .get_output_grid,
            .get_undo_stack,
            .get_redo_stack,
            .get_transaction,
            .get_buffer_info,
            .get_logs,
            .assert_cursor,
            .assert_mode,
            .assert_visual_active,
            .assert_visual_mode,
            .assert_register,
            .assert_line,
            => return error.CommandNotSupported,
        };
    }
};
