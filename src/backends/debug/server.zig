const std = @import("std");
const protocol = @import("protocol.zig");
const json = @import("json.zig");
const state = @import("state.zig");
const EditorContext = @import("editor_context.zig").EditorContext;
const ListChars = @import("../../editor/config/listchars.zig").ListChars;
const handlers = @import("handlers.zig");

/// Debug server configuration
pub const ServerConfig = struct {
    socket_path: ?[]const u8 = null, // Unix socket path (e.g., "/tmp/vimcraft-debug.sock")
    use_stdio: bool = true, // Use stdin/stdout for communication
};

/// Debug server instance
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    running: bool,
    editor: *EditorContext, // Reference to editor context (includes Display for visual debugging)

    pub fn init(
        allocator: std.mem.Allocator,
        config: ServerConfig,
        editor: *EditorContext,
    ) Server {
        return .{
            .allocator = allocator,
            .config = config,
            .running = false,
            .editor = editor,
        };
    }

    pub fn deinit(self: *Server) void {
        _ = self;
        // Cleanup resources if needed
    }

    /// Start the debug server
    pub fn start(self: *Server) !void {
        self.running = true;

        if (self.config.use_stdio) {
            try self.runStdio();
        } else if (self.config.socket_path) |socket_path| {
            try self.runSocket(socket_path);
        } else {
            return error.InvalidConfiguration;
        }
    }

    /// Stop the debug server
    pub fn stop(self: *Server) void {
        self.running = false;
    }

    /// Run server using stdin/stdout with event loop integration
    fn runStdio(self: *Server) !void {
        const EventLoopProcessor = @import("../../system/event_loop/processor.zig").EventLoopProcessor;

        // Import fcntl.h for O_NONBLOCK constant
        const c = @cImport({
            @cInclude("fcntl.h");
        });

        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();

        var line_buffer: [8192]u8 = undefined;
        var line_pos: usize = 0;

        // Make stdin non-blocking
        const stdin_fd = stdin.handle;
        const flags = try std.posix.fcntl(stdin_fd, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(stdin_fd, std.posix.F.SETFL, flags | c.O_NONBLOCK);

        var event_processor = EventLoopProcessor.init(self.allocator);

        while (self.running) {
            // Process event loop: libuv + timers + animation frames
            _ = event_processor.tick();

            // Check if stdin has data available (non-blocking poll)
            var poll_fds = [_]std.posix.pollfd{
                .{
                    .fd = stdin_fd,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };

            // Poll with 10ms timeout to allow event loop to run frequently
            const poll_result = std.posix.poll(&poll_fds, 10) catch |err| {
                if (err == error.Interrupted) continue;
                return err;
            };

            // If no data available, continue event loop
            if (poll_result == 0) continue;

            // Read one byte at a time (non-blocking)
            var char_buf: [1]u8 = undefined;
            const bytes_read = stdin.read(&char_buf) catch |err| {
                if (err == error.EndOfStream) break;
                if (err == error.WouldBlock) continue;
                return err;
            };

            if (bytes_read == 0) break; // EOF

            const ch = char_buf[0];

            if (ch == '\n') {
                // End of line - process the command
                const line_str = line_buffer[0..line_pos];

                // Skip empty lines and whitespace-only lines
                const trimmed = std.mem.trim(u8, line_str, " \t\r");
                if (trimmed.len == 0) {
                    line_pos = 0;
                    continue;
                }

                // Parse command (use trimmed line)
                var cmd = json.parseCommand(trimmed, self.allocator) catch |err| {
                    // Send error response for parse failure
                    const err_str = try std.fmt.allocPrint(self.allocator, "Failed to parse command: {}", .{err});
                    defer self.allocator.free(err_str);

                    const response = try json.createErrorResponse(
                        self.allocator,
                        "unknown",
                        err_str,
                        0,
                    );
                    defer {
                        var mut_response = response;
                        mut_response.deinit(self.allocator);
                    }

                    const response_json = try json.serializeResponse(response, self.allocator);
                    defer self.allocator.free(response_json);

                    try stdout.writeAll(response_json);
                    try stdout.writeAll("\n");
                    line_pos = 0; // Reset for next line
                    continue;
                };
                defer cmd.deinit(self.allocator);

                // Handle command and get response
                var response = try self.handleCommand(cmd);
                defer response.deinit(self.allocator);

                // Serialize and send response
                const response_json = try json.serializeResponse(response, self.allocator);
                defer self.allocator.free(response_json);

                try stdout.writeAll(response_json);
                try stdout.writeAll("\n");

                // Reset line buffer for next line
                line_pos = 0;
            } else {
                // Accumulate character into line buffer
                if (line_pos < line_buffer.len) {
                    line_buffer[line_pos] = ch;
                    line_pos += 1;
                } else {
                    // Line too long - send error and reset
                    const err_str = "Line too long (max 8192 bytes)";
                    const response = try json.createErrorResponse(
                        self.allocator,
                        "unknown",
                        err_str,
                        0,
                    );
                    defer {
                        var mut_response = response;
                        mut_response.deinit(self.allocator);
                    }

                    const response_json = try json.serializeResponse(response, self.allocator);
                    defer self.allocator.free(response_json);

                    try stdout.writeAll(response_json);
                    try stdout.writeAll("\n");

                    line_pos = 0; // Reset for next line
                }
            }
        }
    }

    /// Run server using Unix socket (non-blocking, integrates with event loop)
    fn runSocket(self: *Server, socket_path: []const u8) !void {
        const EventLoopProcessor = @import("../../system/event_loop/processor.zig").EventLoopProcessor;

        // Validate socket path length (Unix domain sockets have a 108-byte limit on macOS/Linux)
        if (socket_path.len >= 104) {  // Leave some margin
            return error.SocketPathTooLong;
        }

        // Remove old socket if it exists (with proper error handling)
        std.fs.deleteFileAbsolute(socket_path) catch |err| {
            // Only ignore "file not found" errors, report others
            if (err != error.FileNotFound) {
                // Log warning but continue - socket might be cleaned up anyway
            }
        };

        // Create Unix domain socket
        const address = try std.net.Address.initUnix(socket_path);
        var server = address.listen(.{}) catch |err| {
            // If socket creation fails, try to clean up and provide better error
            std.fs.deleteFileAbsolute(socket_path) catch {};
            return err;
        };

        // Ensure socket is ALWAYS cleaned up, even on error
        defer {
            server.deinit();
            std.fs.deleteFileAbsolute(socket_path) catch {};
        }

        // Set restrictive permissions on socket file (owner read/write only: 0600)
        // This prevents other users from connecting to our debug socket
        // Note: We open the socket file and call chmod on the file handle, not the path
        if (std.fs.openFileAbsolute(socket_path, .{})) |socket_file| {
            defer socket_file.close();
            socket_file.chmod(0o600) catch {
                // chmod failed - continue anyway (socket is still usable)
            };
        } else |_| {
            // openFile failed - continue anyway (socket is still usable)
            // This can happen on some filesystems or if socket was deleted between creation and chmod
        }

        var event_processor = EventLoopProcessor.init(self.allocator);

        // Accept connections and handle requests (one at a time)
        while (self.running) {
            // Process event loop: libuv + timers + animation frames
            _ = event_processor.tick();

            // Poll for incoming connections (non-blocking with 10ms timeout)
            var poll_fds = [_]std.posix.pollfd{
                .{
                    .fd = server.stream.handle,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };

            const poll_result = std.posix.poll(&poll_fds, 10) catch |err| {
                if (err == error.Interrupted) continue;
                return err;
            };

            // If no connection available, continue event loop
            if (poll_result == 0) continue;

            // Accept connection
            const connection = server.accept() catch continue;
            defer connection.stream.close();

            // Read JSON command (line-delimited)
            var buf: [8192]u8 = undefined;
            const len = connection.stream.read(&buf) catch continue;
            if (len == 0) continue;

            const request = std.mem.trim(u8, buf[0..len], " \t\r\n");
            if (request.len == 0) continue;

            // Parse command
            var cmd = json.parseCommand(request, self.allocator) catch |err| {
                const err_str = try std.fmt.allocPrint(self.allocator, "Failed to parse command: {}", .{err});
                defer self.allocator.free(err_str);

                const response = try json.createErrorResponse(
                    self.allocator,
                    "unknown",
                    err_str,
                    0,
                );
                defer {
                    var mut_response = response;
                    mut_response.deinit(self.allocator);
                }

                const response_json = try json.serializeResponse(response, self.allocator);
                defer self.allocator.free(response_json);

                _ = connection.stream.write(response_json) catch {};
                continue;
            };
            defer cmd.deinit(self.allocator);

            // Handle command and get response
            var response = try self.handleCommand(cmd);
            defer response.deinit(self.allocator);

            // Serialize and send response
            const response_json = try json.serializeResponse(response, self.allocator);
            defer self.allocator.free(response_json);

            _ = connection.stream.write(response_json) catch {};
        }
    }

    /// Handle a command and return a response
    fn handleCommand(self: *Server, cmd: protocol.Command) !protocol.Response {
        const start_time = std.time.nanoTimestamp();

        const result = self.executeCommand(cmd) catch |err| {
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
            const err_str = try std.fmt.allocPrint(self.allocator, "Command failed: {}", .{err});
            defer self.allocator.free(err_str);
            return json.createErrorResponse(self.allocator, cmd.id, err_str, duration);
        };

        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
        return json.createSuccessResponse(self.allocator, cmd.id, result, duration);
    }

    /// Execute a command and return the result
    /// This is where the actual command logic is implemented
    fn executeCommand(self: *Server, cmd: protocol.Command) !protocol.ResponseResult {
        return switch (cmd.cmd) {
            .ping => .{ .pong = .{ .version = try self.allocator.dupe(u8, protocol.PROTOCOL_VERSION) } },

            .shutdown => {
                self.stop();
                return .{ .none = {} };
            },

            // State queries - get full editor state snapshot
            .get_state => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = &self.editor.display,
                };
                return try handlers.handleGetState(ctx);
            },

            .get_cursor => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = &self.editor.display,
                };
                return try handlers.handleGetCursor(ctx);
            },

            .get_mode => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = &self.editor.display,
                };
                return try handlers.handleGetMode(ctx);
            },

            .get_visual => {
                const visual = &self.editor.visual_state;
                const cursor = self.editor.buffer.cursor;

                if (!visual.active) {
                    return .{ .visual = .{
                        .active = false,
                        .mode = try self.allocator.dupe(u8, "none"),
                        .anchor = .{ .line = 0, .col = 0 },
                        .head = .{ .line = 0, .col = 0 },
                        .text = &[_][]const u8{},
                    } };
                }

                const mode_str = switch (visual.mode) {
                    .char => "char",
                    .line => "line",
                    .block => "block",
                };

                const range = visual.getRange(.{ .line = cursor.row, .col = cursor.col });

                // Get selected text lines
                var text_lines = std.ArrayList([]const u8).empty;
                defer text_lines.deinit(self.allocator);

                for (range.start.line..range.end.line + 1) |line_idx| {
                    const line = self.editor.buffer.getLine(line_idx) orelse continue;
                    defer self.allocator.free(line);
                    const owned = try self.allocator.dupe(u8, line);
                    try text_lines.append(self.allocator, owned);
                }

                return .{ .visual = .{
                    .active = true,
                    .mode = try self.allocator.dupe(u8, mode_str),
                    .anchor = .{ .line = visual.anchor.line, .col = visual.anchor.col },
                    .head = .{ .line = cursor.row, .col = cursor.col },
                    .text = try text_lines.toOwnedSlice(self.allocator),
                } };
            },

            .get_registers => {
                const reg_mgr = &self.editor.register_mgr;
                var register_states = std.ArrayList(protocol.RegisterState).empty;
                defer register_states.deinit(self.allocator);

                // Iterate all 39 registers
                for (&reg_mgr.registers, 0..) |*reg, idx| {
                    if (reg.isEmpty()) continue; // Skip empty registers

                    const name = @import("../../editor/register/register.zig").RegisterManager.indexToChar(idx);
                    const motion_type_str = reg.motion_type.toString();

                    // Duplicate register lines
                    var lines_copy = std.ArrayList([]const u8).empty;
                    defer lines_copy.deinit(self.allocator);

                    for (reg.lines.items) |line| {
                        const owned = try self.allocator.dupe(u8, line);
                        try lines_copy.append(self.allocator, owned);
                    }

                    try register_states.append(self.allocator, protocol.RegisterState{
                        .name = name,
                        .lines = try lines_copy.toOwnedSlice(self.allocator),
                        .type = try self.allocator.dupe(u8, motion_type_str),
                        .width = reg.width,
                        .timestamp = reg.timestamp,
                    });
                }

                const count = register_states.items.len;
                const owned_registers = try register_states.toOwnedSlice(self.allocator);
                return .{ .registers = .{
                    .registers = owned_registers,
                    .count = count,
                } };
            },

            .get_register => {
                const reg_name = cmd.args.get_register.name;
                const reg_mgr = &self.editor.register_mgr;
                const reg = reg_mgr.get(reg_name) orelse return error.RegisterNotFound;

                if (reg.isEmpty()) {
                    return .{ .register = .{
                        .name = reg_name,
                        .lines = &[_][]const u8{},
                        .type = try self.allocator.dupe(u8, "char"),
                        .width = 0,
                        .timestamp = 0,
                    } };
                }

                const motion_type_str = reg.motion_type.toString();

                // Duplicate register lines
                var lines_copy = std.ArrayList([]const u8).empty;
                defer lines_copy.deinit(self.allocator);

                for (reg.lines.items) |line| {
                    const owned = try self.allocator.dupe(u8, line);
                    try lines_copy.append(self.allocator, owned);
                }

                return .{ .register = .{
                    .name = reg_name,
                    .lines = try lines_copy.toOwnedSlice(self.allocator),
                    .type = try self.allocator.dupe(u8, motion_type_str),
                    .width = reg.width,
                    .timestamp = reg.timestamp,
                } };
            },

            .get_buffer => {
                // TODO: Get buffer state from editor
                return error.NotImplemented;
            },

            .get_layers => {
                // CRITICAL FIX: Trigger headless render to get FRESH layer state
                // Same fix as get_output_grid - ensures layers show current state
                const list_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("list") orelse false
                else
                    false;

                const listchars = if (self.editor.options_manager) |opts| blk: {
                    const lcs_str = opts.getString("listchars") orelse "tab:> ,trail:-,nbsp:+";
                    break :blk try ListChars.parse(self.allocator, lcs_str);
                } else
                    ListChars{};

                // Get cursorline option
                const cursorline_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("cursorLine") orelse false
                else
                    false;

                try self.editor.display.renderHeadless(
                    self.editor,
                    self.editor.mode_manager.getModeString(),
                    cursorline_enabled,
                    &self.editor.visual_state,
                    &self.editor.yank_highlight,
                    list_enabled,
                    &listchars,
                );

                // Now get FRESH layer state
                const display = &self.editor.display;
                const layer_mgr = &display.layer_manager;
                const compositor = &display.compositor;

                // Collect layer states
                var layer_states = try std.ArrayList(protocol.LayerState).initCapacity(
                    self.allocator,
                    layer_mgr.layers.items.len,
                );
                defer layer_states.deinit(self.allocator);

                for (layer_mgr.layers.items, 0..) |layer, i| {
                    try layer_states.append(self.allocator, protocol.LayerState{
                        .id = i,
                        .name = try self.allocator.dupe(u8, layer.name),
                        .z_index = layer.z_index,
                        .enabled = layer.enabled,
                        .opacity = layer.opacity,
                        .dirty = layer.dirty,
                        .width = layer.grid.width,
                        .height = layer.grid.height,
                    });
                }

                // Get compositor stats
                const stats = compositor.getStats();
                const comp_stats = protocol.CompositorStats{
                    .layers_composited = stats.layers_composited,
                    .layers_skipped = stats.layers_skipped,
                    .layers_cached = stats.layers_cached,
                    .cells_blended = stats.cells_blended,
                    .cells_skipped = stats.cells_skipped,
                    .cells_from_cache = stats.cells_from_cache,
                    .composite_time_ns = stats.composite_time_ns,
                };

                return .{ .layers = .{
                    .layers = try layer_states.toOwnedSlice(self.allocator),
                    .compositor_stats = comp_stats,
                } };
            },

            .get_layer => {
                const layer_name = cmd.args.get_layer.name;
                const display = &self.editor.display;
                const layer_mgr = &display.layer_manager;

                // Find layer by name
                for (layer_mgr.layers.items, 0..) |layer, i| {
                    if (std.mem.eql(u8, layer.name, layer_name)) {
                        return .{ .layer = protocol.LayerState{
                            .id = i,
                            .name = try self.allocator.dupe(u8, layer.name),
                            .z_index = layer.z_index,
                            .enabled = layer.enabled,
                            .opacity = layer.opacity,
                            .dirty = layer.dirty,
                            .width = layer.grid.width,
                            .height = layer.grid.height,
                        } };
                    }
                }

                return error.LayerNotFound;
            },

            .get_layer_cells => {
                const layer_name = cmd.args.get_layer_cells.name;

                // CRITICAL FIX: Trigger headless render to get FRESH layer state
                // Same as get_layers - ensures layers show current state
                const list_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("list") orelse false
                else
                    false;

                const listchars = if (self.editor.options_manager) |opts| blk: {
                    const lcs_str = opts.getString("listchars") orelse "tab:> ,trail:-,nbsp:+";
                    break :blk try ListChars.parse(self.allocator, lcs_str);
                } else
                    ListChars{};

                // Get cursorline option
                const cursorline_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("cursorLine") orelse false
                else
                    false;

                try self.editor.display.renderHeadless(
                    self.editor,
                    self.editor.mode_manager.getModeString(),
                    cursorline_enabled,
                    &self.editor.visual_state,
                    &self.editor.yank_highlight,
                    list_enabled,
                    &listchars,
                );

                // Now get FRESH layer state
                const display = &self.editor.display;
                const layer_mgr = &display.layer_manager;

                // Find layer
                for (layer_mgr.layers.items, 0..) |layer, layer_id| {
                    if (std.mem.eql(u8, layer.name, layer_name)) {
                        var cells: std.ArrayList(protocol.OutputCell) = .empty;
                        defer cells.deinit(self.allocator);

                        // Iterate layer cells and collect non-empty ones
                        var dirty_count: usize = 0;
                        for (0..layer.grid.height) |row| {
                            for (0..layer.grid.width) |col| {
                                const cell = layer.grid.getCell(row, col) orelse continue;

                                // Skip empty cells
                                if (cell.char == 0 and cell.fg == null and cell.bg == null) continue;

                                try cells.append(self.allocator, protocol.OutputCell{
                                    .row = row,
                                    .col = col,
                                    .char = cell.char,
                                    .fg = if (cell.fg) |fg| protocol.Color{
                                        .r = fg.r,
                                        .g = fg.g,
                                        .b = fg.b,
                                    } else null,
                                    .bg = if (cell.bg) |bg| protocol.Color{
                                        .r = bg.r,
                                        .g = bg.g,
                                        .b = bg.b,
                                    } else null,
                                });

                                if (layer.dirty) dirty_count += 1;
                            }
                        }

                        return .{ .layer_cells = .{
                            .layer_name = try self.allocator.dupe(u8, layer_name),
                            .layer_id = layer_id,
                            .cells = try cells.toOwnedSlice(self.allocator),
                            .dirty_count = dirty_count,
                        } };
                    }
                }

                return error.LayerNotFound;
            },

            .get_output_grid => {
                // CRITICAL FIX: Trigger headless render to get FRESH compositor output
                // Without this, we return stale data from the last load_file call.
                // This ensures debug protocol shows live, current rendering state.
                const list_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("list") orelse false
                else
                    false;

                const listchars = if (self.editor.options_manager) |opts| blk: {
                    const lcs_str = opts.getString("listchars") orelse "tab:> ,trail:-,nbsp:+";
                    break :blk try ListChars.parse(self.allocator, lcs_str);
                } else
                    ListChars{};

                // Get cursorline option
                const cursorline_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("cursorLine") orelse false
                else
                    false;

                try self.editor.display.renderHeadless(
                    self.editor,
                    self.editor.mode_manager.getModeString(),
                    cursorline_enabled,
                    &self.editor.visual_state,
                    &self.editor.yank_highlight,
                    list_enabled,
                    &listchars,
                );

                // Now compositor has FRESH data - get it
                const display = &self.editor.display;
                const compositor = &display.compositor;
                const output = compositor.getOutput();

                var cells: std.ArrayList(protocol.OutputCell) = .empty;
                defer cells.deinit(self.allocator);

                // Iterate final output grid
                for (0..output.height) |row| {
                    for (0..output.width) |col| {
                        const cell = output.getCell(row, col) orelse continue;

                        // Include ALL cells (even empty for complete picture)
                        try cells.append(self.allocator, protocol.OutputCell{
                            .row = row,
                            .col = col,
                            .char = cell.char,
                            .fg = if (cell.fg) |fg| protocol.Color{
                                .r = fg.r,
                                .g = fg.g,
                                .b = fg.b,
                            } else null,
                            .bg = if (cell.bg) |bg| protocol.Color{
                                .r = bg.r,
                                .g = bg.g,
                                .b = bg.b,
                            } else null,
                        });
                    }
                }

                return .{ .output_grid = .{
                    .cells = try cells.toOwnedSlice(self.allocator),
                    .width = output.width,
                    .height = output.height,
                    .cell_count = cells.items.len,
                } };
            },

            .get_undo_stack => {
                const undo_stack = &self.editor.buffer.undo_stack;
                const redo_stack = &self.editor.buffer.redo_stack;

                var entries = std.ArrayList(protocol.UndoEntry).empty;
                defer entries.deinit(self.allocator);

                for (undo_stack.items) |change| {
                    try entries.append(self.allocator, protocol.UndoEntry{
                        .offset = change.offset,
                        .deleted_text = try self.allocator.dupe(u8, change.deleted_text),
                        .inserted_text = try self.allocator.dupe(u8, change.inserted_text),
                        .cursor_before = .{
                            .line = change.cursor_before.row,
                            .col = change.cursor_before.col,
                        },
                        .cursor_after = .{
                            .line = change.cursor_after.row,
                            .col = change.cursor_after.col,
                        },
                    });
                }

                const position = undo_stack.items.len -| redo_stack.items.len;

                return .{ .undo_stack = .{
                    .entries = try entries.toOwnedSlice(self.allocator),
                    .count = undo_stack.items.len,
                    .position = position,
                } };
            },

            .get_redo_stack => {
                const redo_stack = &self.editor.buffer.redo_stack;

                var entries = std.ArrayList(protocol.UndoEntry).empty;
                defer entries.deinit(self.allocator);

                for (redo_stack.items) |change| {
                    try entries.append(self.allocator, protocol.UndoEntry{
                        .offset = change.offset,
                        .deleted_text = try self.allocator.dupe(u8, change.deleted_text),
                        .inserted_text = try self.allocator.dupe(u8, change.inserted_text),
                        .cursor_before = .{
                            .line = change.cursor_before.row,
                            .col = change.cursor_before.col,
                        },
                        .cursor_after = .{
                            .line = change.cursor_after.row,
                            .col = change.cursor_after.col,
                        },
                    });
                }

                return .{ .redo_stack = .{
                    .entries = try entries.toOwnedSlice(self.allocator),
                    .count = redo_stack.items.len,
                } };
            },

            .get_transaction => {
                const active = self.editor.buffer.active_transaction != null;
                const text_buffer = if (self.editor.buffer.active_transaction) |trans|
                    try self.allocator.dupe(u8, trans.text_buffer.items)
                else
                    try self.allocator.alloc(u8, 0);

                const cursor_start = if (self.editor.buffer.active_transaction) |trans|
                    protocol.Position{ .line = trans.cursor_start.row, .col = trans.cursor_start.col }
                else
                    protocol.Position{ .line = 0, .col = 0 };

                const cursor_end = if (self.editor.buffer.active_transaction) |trans|
                    protocol.Position{ .line = trans.cursor_end.row, .col = trans.cursor_end.col }
                else
                    protocol.Position{ .line = 0, .col = 0 };

                return .{ .transaction = .{
                    .active = active,
                    .text_buffer = text_buffer,
                    .cursor_start = cursor_start,
                    .cursor_end = cursor_end,
                } };
            },

            .get_buffer_info => {
                return .{ .buffer_info = .{
                    .modified = self.editor.buffer.modified,
                    .filepath = if (self.editor.buffer.filepath) |fp| try self.allocator.dupe(u8, fp) else null,
                    .size = self.editor.buffer.content.len(),
                    .line_count = self.editor.buffer.lineCount(),
                } };
            },

            .get_gutter_state => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = &self.editor.display,
                };
                return try handlers.handleGetGutterState(ctx);
            },

            .get_terminal_updates => {
                const ctx = handlers.HandlerContext{
                    .allocator = self.allocator,
                    .buffer = &self.editor.buffer,
                    .mode_manager = &self.editor.mode_manager,
                    .visual_state = &self.editor.visual_state,
                    .display = &self.editor.display,
                };
                return try handlers.handleGetTerminalUpdates(ctx);
            },

            .save_file => {
                // Save old path to restore on error
                const old_path = self.editor.buffer.filepath;

                // If path is specified, set it as buffer filepath first
                if (cmd.args.save_file.path) |path| {
                    const new_path = try self.editor.buffer.allocator.dupe(u8, path);
                    self.editor.buffer.filepath = new_path;
                }

                // Verify we have a filepath
                if (self.editor.buffer.filepath == null) {
                    return error.NoFilePath;
                }

                // Try to save, restore old path on error
                self.editor.buffer.saveFile() catch |err| {
                    // Restore old state on error
                    if (cmd.args.save_file.path != null) {
                        if (self.editor.buffer.filepath) |fp| {
                            self.editor.buffer.allocator.free(fp);
                        }
                    }
                    self.editor.buffer.filepath = old_path;
                    return err;
                };

                // Success - free old path if we replaced it
                if (cmd.args.save_file.path != null) {
                    if (old_path) |op| {
                        self.editor.buffer.allocator.free(op);
                    }
                }

                return .{ .file_saved = .{ .bytes_written = self.editor.buffer.content.len() } };
            },

            .set_buffer => {
                const lines = cmd.args.set_buffer.lines;
                const cursor_pos = cmd.args.set_buffer.cursor;
                const Rope = @import("../../editor/buffer/rope.zig").Rope;

                // Build new buffer content string (temporarily in ArrayList)
                var content_builder = std.ArrayList(u8).empty;
                errdefer content_builder.deinit(self.editor.buffer.allocator);

                // Build new buffer content (Vim buffers always end lines with \n)
                for (lines) |line| {
                    try content_builder.appendSlice(self.editor.buffer.allocator, line);
                    if (line.len == 0 or line[line.len - 1] != '\n') {
                        try content_builder.append(self.editor.buffer.allocator, '\n');
                    }
                }

                // Create new Rope from content string
                const new_content = try Rope.fromString(self.editor.buffer.allocator, content_builder.items);
                content_builder.deinit(self.editor.buffer.allocator); // Free temporary builder

                // Replace buffer content
                self.editor.buffer.content.deinit();
                self.editor.buffer.content = new_content;

                // Clear undo/redo stacks
                for (self.editor.buffer.undo_stack.items) |*change| {
                    change.deinit(self.editor.buffer.allocator);
                }
                self.editor.buffer.undo_stack.clearRetainingCapacity();

                for (self.editor.buffer.redo_stack.items) |*change| {
                    change.deinit(self.editor.buffer.allocator);
                }
                self.editor.buffer.redo_stack.clearRetainingCapacity();

                // Set cursor position if specified
                if (cursor_pos) |pos| {
                    self.editor.buffer.cursor.row = pos.line;
                    self.editor.buffer.cursor.col = pos.col;
                } else {
                    self.editor.buffer.cursor.row = 0;
                    self.editor.buffer.cursor.col = 0;
                }

                // Mark as not modified (test setup)
                self.editor.buffer.modified = false;

                return .{ .none = {} };
            },

            .set_cursor => {
                const pos = cmd.args.set_cursor;
                const line_count = self.editor.buffer.lineCount();

                // MEDIUM: Validate cursor position is within buffer bounds
                if (line_count == 0) {
                    return error.EmptyBuffer;
                }
                if (pos.line >= line_count) {
                    return error.CursorOutOfBounds;
                }

                const line = self.editor.buffer.getLine(pos.line) orelse return error.InvalidLine;
                defer self.allocator.free(line); // ✅ FIX: Free owned memory from getLine()
                const line_len = if (line.len > 0 and line[line.len - 1] == '\n')
                    line.len - 1
                else
                    line.len;

                // BUG #5 FIX: Vim cursor in normal mode must be ON a character, not past it
                // For empty lines (len=0), only col=0 is valid
                // For non-empty lines, col must be < line_len (on a character, not after last char)
                if (line_len == 0) {
                    if (pos.col > 0) {
                        return error.CursorOutOfBounds;
                    }
                } else {
                    if (pos.col >= line_len) {
                        return error.CursorOutOfBounds;
                    }
                }

                self.editor.buffer.cursor.row = pos.line;
                self.editor.buffer.cursor.col = pos.col;
                return .{ .none = {} };
            },

            .set_mode => {
                const mode_str = cmd.args.set_mode.mode;
                if (std.mem.eql(u8, mode_str, "NORMAL")) {
                    self.editor.mode_manager.enterNormal();
                } else if (std.mem.eql(u8, mode_str, "INSERT")) {
                    self.editor.mode_manager.enterInsert();
                } else if (std.mem.eql(u8, mode_str, "VISUAL")) {
                    self.editor.mode_manager.enterVisual();
                } else if (std.mem.eql(u8, mode_str, "COMMAND")) {
                    self.editor.mode_manager.enterCommand();
                } else {
                    return error.InvalidMode;
                }
                return .{ .none = {} };
            },

            .set_option => {
                // Check if options_manager is available
                const opts_mgr = self.editor.options_manager orelse return error.OptionsNotAvailable;

                const opt_name = cmd.args.set_option.name;
                const opt_value = cmd.args.set_option.value;

                // Set the option based on value type
                switch (opt_value) {
                    .boolean => |b| try opts_mgr.setBoolean(opt_name, b),
                    .number => |n| try opts_mgr.setNumber(opt_name, n),
                    .string => |s| try opts_mgr.setString(opt_name, s),
                }

                return .{ .none = {} };
            },

            .get_logs => {
                const CoreLogLevel = @import("../../editor/log.zig").LogLevel;
                const logger = &self.editor.logger;
                const args = cmd.args.get_logs;

                // Get all logs from ring buffer
                const all_logs = logger.buffer.getAll();
                const total_in_buffer = all_logs.len;

                // Filter by level if specified
                const filter_level: ?CoreLogLevel = if (args.level) |level_str| blk: {
                    if (std.mem.eql(u8, level_str, "debug")) break :blk CoreLogLevel.debug;
                    if (std.mem.eql(u8, level_str, "info")) break :blk CoreLogLevel.info;
                    if (std.mem.eql(u8, level_str, "warning")) break :blk CoreLogLevel.warning;
                    if (std.mem.eql(u8, level_str, "err")) break :blk CoreLogLevel.err;
                    break :blk null;
                } else null;

                // Collect filtered logs with size tracking
                var log_entries = std.ArrayList(protocol.LogEntry).empty;
                defer log_entries.deinit(self.allocator);

                var bytes_used: usize = 0;
                var truncated = false;
                const max_bytes = args.max_bytes orelse std.math.maxInt(usize);

                // Start from most recent and work backwards (respecting count if specified)
                const start_idx = if (args.count) |count|
                    if (all_logs.len > count) all_logs.len - count else 0
                else
                    0;

                for (all_logs[start_idx..]) |core_entry| {
                    // Filter by level if specified
                    if (filter_level) |fl| {
                        if (core_entry.level != fl) continue;
                    }

                    // Calculate approximate size of this entry (message + level string + timestamp)
                    const entry_size = core_entry.message.len + 20; // ~20 bytes for level + timestamp overhead

                    // Check if adding this entry would exceed max_bytes
                    if (bytes_used + entry_size > max_bytes) {
                        truncated = true;
                        break;
                    }

                    // Convert core LogLevel to string
                    const level_str = switch (core_entry.level) {
                        .debug => "debug",
                        .info => "info",
                        .warning => "warning",
                        .err => "err",
                    };

                    // Create protocol log entry (duplicate strings for ownership)
                    const entry = protocol.LogEntry{
                        .message = try self.allocator.dupe(u8, core_entry.message),
                        .level = try self.allocator.dupe(u8, level_str),
                        .timestamp_ms = core_entry.timestamp_ms,
                    };

                    try log_entries.append(self.allocator, entry);
                    bytes_used += entry_size;
                }

                return .{ .logs = .{
                    .logs = try log_entries.toOwnedSlice(self.allocator),
                    .count = log_entries.items.len,
                    .total_in_buffer = total_in_buffer,
                    .truncated = truncated,
                    .bytes_used = bytes_used,
                } };
            },

            .get_options => {
                const ext_ctx = handlers.ExtendedHandlerContext{
                    .base = handlers.HandlerContext{
                        .allocator = self.allocator,
                        .buffer = &self.editor.buffer,
                        .mode_manager = &self.editor.mode_manager,
                        .visual_state = &self.editor.visual_state,
                        .display = &self.editor.display,
                    },
                    .editor_context = self.editor,
                };
                return try handlers.handleGetOptions(ext_ctx, cmd.args.get_options.names);
            },

            .get_module_cache => {
                const ext_ctx = handlers.ExtendedHandlerContext{
                    .base = handlers.HandlerContext{
                        .allocator = self.allocator,
                        .buffer = &self.editor.buffer,
                        .mode_manager = &self.editor.mode_manager,
                        .visual_state = &self.editor.visual_state,
                        .display = &self.editor.display,
                    },
                    .editor_context = self.editor,
                };
                return try handlers.handleGetModuleCache(ext_ctx);
            },

            .get_render_stats => {
                const stats = &self.editor.display.render_stats;

                // Convert nanosecond timings to milliseconds
                const last_render_ms = stats.getLastRenderDurationMs();
                const avg_render_ms = stats.getAverageRenderDurationMs();
                const max_render_ms = stats.getMaxRenderDurationMs();

                // Calculate performance assessment
                const assessment_str = if (avg_render_ms < 20.0)
                    "EXCELLENT"
                else if (avg_render_ms < 50.0)
                    "ACCEPTABLE"
                else if (avg_render_ms < 100.0)
                    "SLUGGISH"
                else
                    "CRITICAL";

                // Generate recommendations based on detected issues
                var recommendations = std.ArrayList([]const u8).empty;
                defer recommendations.deinit(self.allocator);

                // Check for excessive cursor codes
                const total_cursor_codes = stats.cursor_hide_codes + stats.cursor_show_codes +
                                          stats.cursor_shape_codes + stats.cursor_position_codes;
                if (total_cursor_codes > stats.total_renders * 3) {
                    try recommendations.append(self.allocator,
                        try self.allocator.dupe(u8, "Excessive cursor escape codes detected - check cursor state tracking"));
                }

                // Check for slow renders
                if (avg_render_ms > 50.0) {
                    try recommendations.append(self.allocator,
                        try self.allocator.dupe(u8, "Average render time >50ms - consider optimizing compositor or diff algorithm"));
                }

                // Check for missing synchronized updates
                if (stats.total_renders > 10 and stats.sync_update_begin_codes == 0) {
                    try recommendations.append(self.allocator,
                        try self.allocator.dupe(u8, "Synchronized updates not working - terminal may not support DCS sequences"));
                }

                // Check for mismatched sync updates
                if (stats.sync_update_begin_codes != stats.sync_update_end_codes) {
                    try recommendations.append(self.allocator,
                        try std.fmt.allocPrint(self.allocator, "Mismatched sync updates: {} begin / {} end",
                            .{stats.sync_update_begin_codes, stats.sync_update_end_codes}));
                }

                // Add success message if no issues detected
                if (recommendations.items.len == 0) {
                    try recommendations.append(self.allocator,
                        try self.allocator.dupe(u8, "No performance issues detected - rendering pipeline is healthy"));
                }

                return .{ .render_stats = .{
                    .last_render_duration_ms = last_render_ms,
                    .avg_render_duration_ms = avg_render_ms,
                    .max_render_duration_ms = max_render_ms,
                    .total_renders = stats.total_renders,
                    .throttle_max_fps = 60, // TODO: Get from main.zig RenderThrottle if accessible
                    .throttle_enabled = true, // TODO: Get from main.zig RenderThrottle if accessible
                    .renders_throttled = 0, // TODO: Get from main.zig RenderThrottle if accessible
                    .renders_executed = stats.total_renders,
                    .cursor_hide_codes = stats.cursor_hide_codes,
                    .cursor_show_codes = stats.cursor_show_codes,
                    .cursor_shape_codes = stats.cursor_shape_codes,
                    .cursor_position_codes = stats.cursor_position_codes,
                    .sync_update_begin_codes = stats.sync_update_begin_codes,
                    .sync_update_end_codes = stats.sync_update_end_codes,
                    .input_poll_timeout_ms = 1, // TODO: Get from main.zig if accessible
                    .keys_processed_total = 0, // TODO: Track in editor if needed
                    .layers_composited_last = stats.layers_composited_last,
                    .cells_updated_last = stats.cells_updated_last,
                    .cells_blended_last = stats.cells_blended_last,
                    .performance_assessment = try self.allocator.dupe(u8, assessment_str),
                    .recommendations = try recommendations.toOwnedSlice(self.allocator),
                } };
            },

            // Commands - execute keys in the editor
            .execute_keys => {
                const keys = cmd.args.execute_keys.keys;
                try self.editor.executeKeys(keys);

                // PERFORMANCE FIX: Don't render after every execute_keys!
                // Rendering is deferred until compositor output is queried (get_output_grid, get_layers).
                // This prevents 400× renderHeadless() calls when pasting 400 characters.
                // Old code was calling renderHeadless() here - massive performance bug.

                return .{ .execute_keys = .{ .keys_processed = keys.len } };
            },

            .execute_keys_with_render_trace => {
                const keys = cmd.args.execute_keys_with_render_trace.keys;

                // Create extended context with Editor access
                const ext_ctx = handlers.ExtendedHandlerContext{
                    .base = handlers.HandlerContext{
                        .allocator = self.allocator,
                        .buffer = &self.editor.buffer,
                        .mode_manager = &self.editor.mode_manager,
                        .visual_state = &self.editor.visual_state,
                        .display = &self.editor.display,
                    },
                    .editor_context = self.editor,
                };

                return try handlers.handleExecuteKeysWithRenderTrace(ext_ctx, keys);
            },

            .load_file => {
                const path = cmd.args.load_file.path;
                try self.editor.loadFile(path);

                // Get list/listchars options for rendering
                const list_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("list") orelse false
                else
                    false;

                const listchars = if (self.editor.options_manager) |opts| blk: {
                    const lcs_str = opts.getString("listchars") orelse "tab:> ,trail:-,nbsp:+";
                    break :blk try ListChars.parse(self.allocator, lcs_str);
                } else
                    ListChars{};

                // Get cursorline option
                const cursorline_enabled = if (self.editor.options_manager) |opts|
                    opts.getBoolean("cursorLine") orelse false
                else
                    false;

                // CRITICAL: Use headless render to update compositor WITHOUT stdout pollution
                try self.editor.display.renderHeadless(
                    self.editor,
                    self.editor.mode_manager.getModeString(),
                    cursorline_enabled,
                    &self.editor.visual_state,
                    &self.editor.yank_highlight,
                    list_enabled,
                    &listchars,
                );

                return .{ .none = {} };
            },

            // Assertions - verify editor state matches expectations
            .assert_cursor => {
                const expected_line = cmd.args.assert_cursor.line;
                const expected_col = cmd.args.assert_cursor.col;
                const actual_line = self.editor.buffer.cursor.row;
                const actual_col = self.editor.buffer.cursor.col;

                const match = (expected_line == actual_line and expected_col == actual_col);

                if (!match) {
                    const expected = try std.fmt.allocPrint(self.allocator, "({d},{d})", .{ expected_line, expected_col });
                    const actual = try std.fmt.allocPrint(self.allocator, "({d},{d})", .{ actual_line, actual_col });
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected ({d},{d}), got ({d},{d})", .{ expected_line, expected_col, actual_line, actual_col });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },

            .assert_mode => {
                const expected_mode = cmd.args.assert_mode.mode;
                const actual_mode = self.editor.mode_manager.getModeString();

                const match = std.mem.eql(u8, expected_mode, actual_mode);

                if (!match) {
                    const expected = try self.allocator.dupe(u8, expected_mode);
                    const actual = try self.allocator.dupe(u8, actual_mode);
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected '{s}', got '{s}'", .{ expected_mode, actual_mode });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },

            .assert_visual_active => {
                const expected_active = cmd.args.assert_visual_active.active;
                const actual_active = self.editor.visual_state.active;

                const match = (expected_active == actual_active);

                if (!match) {
                    const expected = try std.fmt.allocPrint(self.allocator, "{}", .{expected_active});
                    const actual = try std.fmt.allocPrint(self.allocator, "{}", .{actual_active});
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected visual active={}, got {}", .{ expected_active, actual_active });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },

            .assert_visual_mode => {
                const expected_mode = cmd.args.assert_visual_mode.mode;
                const visual = &self.editor.visual_state;

                if (!visual.active) {
                    const expected = try self.allocator.dupe(u8, expected_mode);
                    const actual = try self.allocator.dupe(u8, "none");
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected visual mode '{s}', but visual mode is not active", .{expected_mode});

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                const actual_mode = switch (visual.mode) {
                    .char => "char",
                    .line => "line",
                    .block => "block",
                };

                const match = std.mem.eql(u8, expected_mode, actual_mode);

                if (!match) {
                    const expected = try self.allocator.dupe(u8, expected_mode);
                    const actual = try self.allocator.dupe(u8, actual_mode);
                    const diff = try std.fmt.allocPrint(self.allocator, "Expected visual mode '{s}', got '{s}'", .{ expected_mode, actual_mode });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },

            .assert_register => {
                const reg_name = cmd.args.assert_register.name;
                const expected_text = cmd.args.assert_register.text;
                const reg_mgr = &self.editor.register_mgr;
                const reg = reg_mgr.get(reg_name) orelse return error.RegisterNotFound;

                // Get register text as single string
                const actual_text = try reg.getText(self.allocator);
                defer self.allocator.free(actual_text);

                // Trim trailing newline if present (for comparison)
                const actual_trimmed = if (actual_text.len > 0 and actual_text[actual_text.len - 1] == '\n')
                    actual_text[0 .. actual_text.len - 1]
                else
                    actual_text;

                const match = std.mem.eql(u8, expected_text, actual_trimmed);

                if (!match) {
                    const expected = try self.allocator.dupe(u8, expected_text);
                    const actual = try self.allocator.dupe(u8, actual_trimmed);
                    const diff = try std.fmt.allocPrint(self.allocator, "Register '{c}': Expected [{s}], got [{s}]", .{ reg_name, expected_text, actual_trimmed });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },

            .assert_line => {
                const line_num = cmd.args.assert_line.line;
                const expected_text = cmd.args.assert_line.text;

                const line = self.editor.buffer.getLine(line_num) orelse {
                    const diff = try std.fmt.allocPrint(self.allocator, "Line {d} does not exist", .{line_num});
                    return .{ .assertion = .{
                        .match = false,
                        .expected = try self.allocator.dupe(u8, expected_text),
                        .actual = try self.allocator.dupe(u8, "(line does not exist)"),
                        .diff = diff,
                    } };
                };
                defer self.allocator.free(line); // ✅ FIX: Free owned memory from getLine()

                // Remove trailing newline if present
                const actual_text = if (line.len > 0 and line[line.len - 1] == '\n')
                    line[0 .. line.len - 1]
                else
                    line;

                const match = std.mem.eql(u8, expected_text, actual_text);

                if (!match) {
                    const expected = try self.allocator.dupe(u8, expected_text);
                    const actual = try self.allocator.dupe(u8, actual_text);
                    const diff = try std.fmt.allocPrint(self.allocator, "Line {d}: Expected [{s}], got [{s}]", .{ line_num, expected_text, actual_text });

                    return .{ .assertion = .{
                        .match = false,
                        .expected = expected,
                        .actual = actual,
                        .diff = diff,
                    } };
                }

                return .{ .assertion = .{
                    .match = true,
                    .expected = null,
                    .actual = null,
                    .diff = null,
                } };
            },
        };
    }
};

// Tests
test "Server: init and deinit" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    try std.testing.expect(!server.running);
}

test "Server: handle ping command" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    var cmd = try protocol.Command.init(
        allocator,
        "test-1",
        .ping,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    var response = try server.handleCommand(cmd);
    defer response.deinit(allocator);

    try std.testing.expectEqual(protocol.ResponseStatus.ok, response.status);
    try std.testing.expect(response.result != null);
    try std.testing.expect(response.result.?.pong.version.len > 0);
}

test "Server: handle shutdown command" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    server.running = true;

    var cmd = try protocol.Command.init(
        allocator,
        "test-2",
        .shutdown,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    var response = try server.handleCommand(cmd);
    defer response.deinit(allocator);

    try std.testing.expectEqual(protocol.ResponseStatus.ok, response.status);
    try std.testing.expect(!server.running); // Should be stopped
}

test "Server: handle unimplemented command" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator, .{});
    defer server.deinit();

    var cmd = try protocol.Command.init(
        allocator,
        "test-3",
        .get_state,
        .{ .none = {} },
    );
    defer cmd.deinit(allocator);

    var response = try server.handleCommand(cmd);
    defer response.deinit(allocator);

    // Should return error since get_state is not yet implemented
    try std.testing.expectEqual(protocol.ResponseStatus.@"error", response.status);
    try std.testing.expect(response.@"error" != null);
}
