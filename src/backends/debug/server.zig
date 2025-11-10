const std = @import("std");
const protocol = @import("protocol.zig");
const json = @import("json.zig");
const state = @import("state.zig");
const EditorContext = @import("editor_context.zig").EditorContext;

/// Debug server configuration
pub const ServerConfig = struct {
    socket_path: ?[]const u8 = null, // Unix socket path (e.g., "/tmp/openvim-debug.sock")
    use_stdio: bool = true, // Use stdin/stdout for communication
};

/// Debug server instance
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    running: bool,
    editor: *EditorContext, // Reference to editor context (includes Display for visual debugging)
    highlight_config: *const @import("../../editor/config/highlights.zig").HighlightConfig, // For rendering

    pub fn init(
        allocator: std.mem.Allocator,
        config: ServerConfig,
        editor: *EditorContext,
        highlight_config: *const @import("../../editor/config/highlights.zig").HighlightConfig,
    ) Server {
        return .{
            .allocator = allocator,
            .config = config,
            .running = false,
            .editor = editor,
            .highlight_config = highlight_config,
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
        } else if (self.config.socket_path) |_| {
            // TODO: Implement Unix socket server
            return error.NotImplemented;
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
            .ping => .{ .pong = .{ .version = protocol.PROTOCOL_VERSION } },

            .shutdown => {
                self.stop();
                return .{ .none = {} };
            },

            // State queries - these need to be hooked up to actual editor state
            .get_state => {
                // TODO: Get actual editor state from editor core
                return error.NotImplemented;
            },

            .get_cursor => {
                return .{ .cursor = .{
                    .line = self.editor.buffer.cursor.row,
                    .col = self.editor.buffer.cursor.col,
                } };
            },

            .get_mode => {
                const mode_str = try self.allocator.dupe(u8, self.editor.mode_manager.getModeString());
                return .{ .mode = .{ .mode = mode_str } };
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

            // Commands - execute keys in the editor
            .execute_keys => {
                const keys = cmd.args.execute_keys.keys;
                try self.editor.executeKeys(keys);

                // CRITICAL: Use headless render to update compositor WITHOUT stdout pollution
                // This updates layers for inspection while keeping JSON responses clean
                try self.editor.display.renderHeadless(
                    &self.editor.buffer,
                    self.editor.mode_manager.getModeString(),
                    self.highlight_config,
                    &self.editor.visual_state,
                    &self.editor.yank_highlight,
                );

                return .{ .execute_keys = .{ .keys_processed = keys.len } };
            },

            .load_file => {
                const path = cmd.args.load_file.path;
                try self.editor.buffer.loadFile(path);

                // CRITICAL: Use headless render to update compositor WITHOUT stdout pollution
                try self.editor.display.renderHeadless(
                    &self.editor.buffer,
                    self.editor.mode_manager.getModeString(),
                    self.highlight_config,
                    &self.editor.visual_state,
                    &self.editor.yank_highlight,
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
