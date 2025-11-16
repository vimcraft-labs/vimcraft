const std = @import("std");

/// Debug protocol version
pub const PROTOCOL_VERSION = "1.0.0";

/// Message ID (for request/response correlation)
pub const MessageId = []const u8;

/// Command types
pub const CommandType = enum {
    // State queries
    get_state,
    get_cursor,
    get_mode,
    get_visual,
    get_registers,
    get_register,
    get_buffer,
    get_layers, // Get layer system state
    get_layer, // Get specific layer state
    get_layer_cells, // NEW: Get cells from specific layer
    get_output_grid, // NEW: Get final composited output grid
    get_logs, // Get log entries from editor.logger
    get_undo_stack, // NEW: Get undo stack entries (Phase 3)
    get_redo_stack, // NEW: Get redo stack entries (Phase 3)
    get_transaction, // NEW: Get active transaction state (Phase 3)
    get_buffer_info, // NEW: Get buffer metadata (modified flag, path, size)

    // Commands
    execute_keys,
    load_file,
    save_file, // NEW: Save buffer to file
    set_buffer, // NEW: Set buffer content and cursor (test setup)
    set_cursor, // NEW: Set cursor position directly
    set_mode, // NEW: Set mode directly (NORMAL/INSERT/VISUAL/COMMAND)
    set_option, // NEW: Set vim option (Phase 4)

    // Assertions
    assert_cursor,
    assert_mode,
    assert_visual_active,
    assert_visual_mode,
    assert_register,
    assert_line,

    // Control
    ping,
    shutdown,

    pub fn fromString(s: []const u8) ?CommandType {
        const type_info = @typeInfo(CommandType);
        inline for (type_info.@"enum".fields) |field| {
            if (std.mem.eql(u8, s, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }

    pub fn toString(self: CommandType) []const u8 {
        return @tagName(self);
    }
};

/// Position in buffer
pub const Position = struct {
    line: usize,
    col: usize,
};

/// Option value (for set_option command)
pub const OptionValue = union(enum) {
    boolean: bool,
    number: i64,
    string: []const u8,
};

/// Command arguments (union based on command type)
pub const CommandArgs = union(enum) {
    none: void,
    get_register: struct { name: u8 },
    get_layer: struct { name: []const u8 },
    get_layer_cells: struct { name: []const u8, region: ?GridRegion }, // NEW
    get_output_grid: struct { region: ?GridRegion }, // NEW
    get_logs: struct {
        count: ?usize, // Number of recent logs (null = all, but limited by max_bytes)
        level: ?[]const u8, // Filter by level: "debug", "info", "warning", "err" (null = all)
        max_bytes: ?usize, // Maximum response size in bytes (null = unlimited, but recommended for LLM: 4096-8192)
    },
    execute_keys: struct { keys: []const u8 },
    load_file: struct { path: []const u8 },
    save_file: struct { path: ?[]const u8 }, // NEW: optional path (null = use buffer.filepath)
    set_buffer: struct { lines: []const []const u8, cursor: ?Position }, // NEW: set buffer content
    set_cursor: Position, // NEW: set cursor position directly
    set_mode: struct { mode: []const u8 }, // NEW: set mode directly
    set_option: struct { name: []const u8, value: OptionValue }, // NEW: set vim option
    assert_cursor: Position,
    assert_mode: struct { mode: []const u8 },
    assert_visual_active: struct { active: bool },
    assert_visual_mode: struct { mode: []const u8 }, // "char", "line", "block"
    assert_register: struct { name: u8, text: []const u8 },
    assert_line: struct { line: usize, text: []const u8 },
};

/// Command message
pub const Command = struct {
    id: MessageId,
    cmd: CommandType,
    args: CommandArgs,
    timestamp: i64,

    pub fn init(allocator: std.mem.Allocator, id: MessageId, cmd: CommandType, args: CommandArgs) !Command {
        return Command{
            .id = try allocator.dupe(u8, id),
            .cmd = cmd,
            .args = args,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        // Free args based on type
        switch (self.args) {
            .execute_keys => |a| allocator.free(a.keys),
            .load_file => |a| allocator.free(a.path),
            .save_file => |a| {
                if (a.path) |p| allocator.free(p);
            },
            .set_buffer => |a| {
                for (a.lines) |line| {
                    allocator.free(line);
                }
                allocator.free(a.lines);
            },
            .set_mode => |a| allocator.free(a.mode),
            .set_option => |a| {
                allocator.free(a.name);
                switch (a.value) {
                    .string => |s| allocator.free(s),
                    else => {},
                }
            },
            .get_layer => |a| allocator.free(a.name),
            .get_layer_cells => |a| allocator.free(a.name),
            .get_logs => |a| {
                if (a.level) |level| allocator.free(level);
            },
            .assert_mode => |a| allocator.free(a.mode),
            .assert_visual_mode => |a| allocator.free(a.mode),
            .assert_register => |a| {
                allocator.free(a.text);
            },
            .assert_line => |a| {
                allocator.free(a.text);
            },
            else => {},
        }
    }
};

/// Response status
pub const ResponseStatus = enum {
    ok,
    @"error",

    pub fn toString(self: ResponseStatus) []const u8 {
        return @tagName(self);
    }
};

/// Response result (union based on command type)
pub const ResponseResult = union(enum) {
    none: void,
    state: EditorState,
    cursor: Position,
    mode: struct { mode: []const u8 },
    visual: VisualState,
    registers: RegistersState,
    register: RegisterState,
    buffer: BufferState,
    layers: LayersState,
    layer: LayerState,
    layer_cells: LayerCells, // NEW: Layer cell data
    output_grid: OutputGrid, // NEW: Final composited output
    logs: LogsState, // NEW: Log entries from editor.logger
    undo_stack: UndoStackState, // NEW: Undo stack entries (Phase 3)
    redo_stack: RedoStackState, // NEW: Redo stack entries (Phase 3)
    transaction: TransactionState, // NEW: Active transaction state (Phase 3)
    buffer_info: BufferInfo, // NEW: Buffer metadata
    file_saved: struct { bytes_written: usize }, // NEW: File save confirmation
    execute_keys: struct { keys_processed: usize },
    assertion: AssertionResult,
    pong: struct { version: []const u8 },
};

/// Response message
pub const Response = struct {
    id: MessageId,
    status: ResponseStatus,
    result: ?ResponseResult,
    @"error": ?[]const u8,
    timestamp: i64,
    duration_ns: u64,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.@"error") |err| {
            allocator.free(err);
        }

        // Free result fields that are heap-allocated
        if (self.result) |result| {
            switch (result) {
                .state => |s| {
                    // Free mode string
                    allocator.free(s.mode);
                    // Free buffer fields
                    if (s.buffer.path) |p| allocator.free(p);
                    for (s.buffer.lines) |line| {
                        allocator.free(line);
                    }
                    allocator.free(s.buffer.lines);
                    // Free visual state if present
                    if (s.visual) |v| {
                        allocator.free(v.mode);
                        for (v.text) |line| {
                            allocator.free(line);
                        }
                        allocator.free(v.text);
                    }
                    // Free registers (CRITICAL: PE found this was leaked!)
                    for (s.registers.registers) |reg| {
                        allocator.free(reg.type);
                        for (reg.lines) |line| {
                            allocator.free(line);
                        }
                        allocator.free(reg.lines);
                    }
                    allocator.free(s.registers.registers);
                },
                .mode => |m| allocator.free(m.mode),
                .pong => |p| {
                    // Only free if it's not a string literal
                    // String literals from protocol.PROTOCOL_VERSION don't need freeing
                    // but duped strings from client parsing do
                    allocator.free(p.version);
                },
                .assertion => |a| {
                    if (a.expected) |exp| allocator.free(exp);
                    if (a.actual) |act| allocator.free(act);
                    if (a.diff) |d| allocator.free(d);
                },
                .register => |r| {
                    allocator.free(r.type);
                    for (r.lines) |line| {
                        allocator.free(line);
                    }
                    allocator.free(r.lines);
                },
                .visual => |v| {
                    allocator.free(v.mode);
                    for (v.text) |line| {
                        allocator.free(line);
                    }
                    allocator.free(v.text);
                },
                .buffer => |b| {
                    if (b.path) |p| allocator.free(p);
                    for (b.lines) |line| {
                        allocator.free(line);
                    }
                    allocator.free(b.lines);
                },
                .logs => |l| {
                    for (l.logs) |entry| {
                        allocator.free(entry.message);
                        allocator.free(entry.level);
                    }
                    allocator.free(l.logs);
                },
                .layers => |l| {
                    // Free each layer's name string
                    for (l.layers) |layer| {
                        allocator.free(layer.name);
                    }
                    // Free the layers slice itself
                    allocator.free(l.layers);
                },
                .layer => |layer| allocator.free(layer.name),
                .layer_cells => |lc| {
                    allocator.free(lc.layer_name);
                    allocator.free(lc.cells);
                },
                .output_grid => |og| allocator.free(og.cells),
                .undo_stack => |us| {
                    for (us.entries) |entry| {
                        allocator.free(entry.deleted_text);
                        allocator.free(entry.inserted_text);
                    }
                    allocator.free(us.entries);
                },
                .redo_stack => |rs| {
                    for (rs.entries) |entry| {
                        allocator.free(entry.deleted_text);
                        allocator.free(entry.inserted_text);
                    }
                    allocator.free(rs.entries);
                },
                .transaction => |t| {
                    allocator.free(t.text_buffer);
                },
                .buffer_info => |bi| {
                    if (bi.filepath) |fp| allocator.free(fp);
                },
                // Other types either don't allocate or have different ownership
                else => {},
            }
        }
    }
};

/// Event types
pub const EventType = enum {
    mode_changed,
    buffer_changed,
    register_changed,
    cursor_moved,
    visual_changed,

    pub fn toString(self: EventType) []const u8 {
        return @tagName(self);
    }
};

/// Event data (union based on event type)
pub const EventData = union(enum) {
    mode_changed: struct {
        old_mode: []const u8,
        new_mode: []const u8,
    },
    buffer_changed: struct {
        line: usize,
        old_text: ?[]const u8,
        new_text: []const u8,
    },
    register_changed: struct {
        register: u8,
    },
    cursor_moved: struct {
        old_pos: Position,
        new_pos: Position,
    },
    visual_changed: struct {
        active: bool,
        mode: ?[]const u8,
    },
};

/// Event message
pub const Event = struct {
    type: EventType,
    data: EventData,
    timestamp: i64,
};

/// Editor state snapshot
pub const EditorState = struct {
    mode: []const u8, // "NORMAL", "INSERT", "VISUAL", etc.
    cursor: Position,
    buffer: BufferState,
    visual: ?VisualState,
    registers: RegistersState,
    viewport: ?ViewportState, // NEW: Viewport information for debugging H/M/L
};

/// Viewport state (for debugging display and scrolling)
pub const ViewportState = struct {
    top: usize, // First visible line (viewport_top)
    left: usize, // First visible column (viewport_left)
    height: usize, // Visible lines (terminal_rows - 1)
    width: usize, // Visible columns (terminal_cols)
};

/// Visual selection state
pub const VisualState = struct {
    active: bool,
    mode: []const u8, // "char", "line", "block"
    anchor: Position,
    head: Position,
    text: []const []const u8, // Selected text lines
};

/// Buffer state
pub const BufferState = struct {
    path: ?[]const u8,
    lines: []const []const u8,
    modified: bool,
    line_count: usize,
};

/// Single register state
pub const RegisterState = struct {
    name: u8,
    lines: []const []const u8,
    type: []const u8, // "char", "line", "block"
    width: usize,
    timestamp: i64,
};

/// All registers state
pub const RegistersState = struct {
    registers: []const RegisterState,
    count: usize,
};

/// Assertion result
pub const AssertionResult = struct {
    match: bool,
    expected: ?[]const u8,
    actual: ?[]const u8,
    diff: ?[]const u8,
};

/// Color (RGB)
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// Single cell in output grid
pub const OutputCell = struct {
    row: usize,
    col: usize,
    char: u21,
    fg: ?Color,
    bg: ?Color,
};

/// Grid region (for querying specific area)
pub const GridRegion = struct {
    row: usize,
    col: usize,
    height: usize,
    width: usize,
};

/// Final compositor output grid
pub const OutputGrid = struct {
    cells: []const OutputCell,
    width: usize,
    height: usize,
    cell_count: usize,
};

/// Layer cell data
pub const LayerCells = struct {
    layer_name: []const u8,
    layer_id: usize,
    cells: []const OutputCell,
    dirty_count: usize,
};

/// Single layer state
pub const LayerState = struct {
    id: usize,
    name: []const u8,
    z_index: i32,
    enabled: bool,
    opacity: f32,
    dirty: bool,
    width: usize,
    height: usize,
};

/// All layers state
pub const LayersState = struct {
    layers: []const LayerState,
    compositor_stats: CompositorStats,
};

/// Compositor statistics
pub const CompositorStats = struct {
    layers_composited: usize,
    layers_skipped: usize,
    layers_cached: usize,
    cells_blended: usize,
    cells_skipped: usize,
    cells_from_cache: usize,
    composite_time_ns: i64,
};

/// Log entry from editor.logger
pub const LogEntry = struct {
    message: []const u8,
    level: []const u8, // "debug", "info", "warning", "err"
    timestamp_ms: i64,
};

/// Logs response (multiple log entries)
pub const LogsState = struct {
    logs: []const LogEntry,
    count: usize,
    total_in_buffer: usize, // Total logs available in ring buffer
    truncated: bool, // Whether response was truncated due to max_bytes limit
    bytes_used: usize, // Approximate bytes used by returned logs
};

/// Single undo entry
pub const UndoEntry = struct {
    offset: usize,
    deleted_text: []const u8,
    inserted_text: []const u8,
    cursor_before: Position,
    cursor_after: Position,
};

/// Undo stack state
pub const UndoStackState = struct {
    entries: []const UndoEntry,
    count: usize,
    position: usize, // Current position in undo history
};

/// Redo stack state
pub const RedoStackState = struct {
    entries: []const UndoEntry,
    count: usize,
};

/// Active transaction state
pub const TransactionState = struct {
    active: bool,
    text_buffer: []const u8, // Accumulated text in current transaction
    cursor_start: Position,
    cursor_end: Position,
};

/// Buffer metadata
pub const BufferInfo = struct {
    modified: bool,
    filepath: ?[]const u8,
    size: usize, // Total bytes in buffer
    line_count: usize,
};

// Tests
test "Protocol: CommandType from/to string" {
    const cmd = CommandType.get_state;
    const str = cmd.toString();
    try std.testing.expectEqualStrings("get_state", str);

    const parsed = CommandType.fromString("get_state").?;
    try std.testing.expectEqual(CommandType.get_state, parsed);
}

test "Protocol: Response status" {
    try std.testing.expectEqualStrings("ok", ResponseStatus.ok.toString());
    try std.testing.expectEqualStrings("error", ResponseStatus.@"error".toString());
}
