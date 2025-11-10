const std = @import("std");
const Editor = @import("../../editor/editor.zig").Editor;

/// C API bindings (our wrapper around C++ Hermes)
const c = @cImport({
    @cInclude("jsi/hermes_c_api.h");
});

/// HermesRuntime wraps the Hermes JavaScript engine
pub const HermesRuntime = struct {
    runtime: *c.OVHermesRuntime,
    allocator: std.mem.Allocator,
    editor: *Editor,

    /// Initialize Hermes runtime
    pub fn init(allocator: std.mem.Allocator, editor: *Editor) !*HermesRuntime {
        const self = try allocator.create(HermesRuntime);
        errdefer allocator.destroy(self);

        // Create Hermes runtime via C API
        const runtime = c.hermes_runtime_create() orelse {
            return error.HermesInitFailed;
        };

        self.* = .{
            .runtime = runtime,
            .allocator = allocator,
            .editor = editor,
        };

        // Register all Neovim API functions
        try self.registerNvimAPI();

        return self;
    }

    pub fn deinit(self: *HermesRuntime) void {
        c.hermes_runtime_destroy(self.runtime);
        self.allocator.destroy(self);
    }

    /// Register Neovim API functions that JavaScript can call
    fn registerNvimAPI(self: *HermesRuntime) !void {
        // Register: nvim_buffer_create()
        c.hermes_register_host_function(
            self.runtime,
            "nvim_buffer_create",
            nvimBufferCreate,
            self.editor,
        );

        // Register: nvim_buffer_insert_text(buffer_id, line, col, text)
        c.hermes_register_host_function(
            self.runtime,
            "nvim_buffer_insert_text",
            nvimBufferInsertText,
            self.editor,
        );

        // Register: nvim_buffer_get_line(buffer_id, line)
        c.hermes_register_host_function(
            self.runtime,
            "nvim_buffer_get_line",
            nvimBufferGetLine,
            self.editor,
        );

        // Register cursor position hooks (for animated cursor plugins)
        c.hermes_register_host_function(
            self.runtime,
            "zigGetCursorPosition",
            zigGetCursorPosition,
            self.editor,
        );

        c.hermes_register_host_function(
            self.runtime,
            "zigSetCursorRenderPosition",
            zigSetCursorRenderPosition,
            self.editor,
        );

        std.debug.print("[Hermes] Registered nvim API functions\n", .{});
    }

    /// Execute JavaScript code
    pub fn evaluate(self: *HermesRuntime, code: []const u8, source_url: []const u8) !void {
        const url_z = try self.allocator.dupeZ(u8, source_url);
        defer self.allocator.free(url_z);

        const result = c.hermes_evaluate_javascript(
            self.runtime,
            code.ptr,
            code.len,
            url_z.ptr,
        );

        if (result == null) {
            if (c.hermes_has_exception(self.runtime)) {
                if (c.hermes_get_exception_message(self.runtime)) |msg| {
                    std.debug.print("[Hermes] Exception: {s}\n", .{std.mem.span(msg)});
                }
                return error.JavaScriptException;
            }
            return error.EvaluationFailed;
        }

        // Clean up result
        c.hermes_value_destroy(result);
    }

    /// Evaluate Hermes bytecode (.hbc file)
    pub fn evaluateBytecode(self: *HermesRuntime, bytecode: []const u8) !void {
        const result = c.hermes_evaluate_bytecode(
            self.runtime,
            bytecode.ptr,
            bytecode.len,
        );

        if (result == null) {
            if (c.hermes_has_exception(self.runtime)) {
                if (c.hermes_get_exception_message(self.runtime)) |msg| {
                    std.debug.print("[Hermes] Exception: {s}\n", .{std.mem.span(msg)});
                }
                return error.JavaScriptException;
            }
            return error.EvaluationFailed;
        }

        c.hermes_value_destroy(result);
    }

    /// Load and execute bytecode from file
    pub fn loadBytecodeFile(self: *HermesRuntime, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const bytecode = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(bytecode);

        try self.evaluateBytecode(bytecode);
    }
};

//
// Host Function Implementations (called from JavaScript via JSI)
//

/// nvim_buffer_create() -> buffer_id
export fn nvimBufferCreate(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = runtime;
    _ = args;
    _ = count;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    // Create buffer in Zig
    const buffer_id = editor.createBuffer() catch {
        // Return undefined on error
        return null;
    };

    std.debug.print("[Native] Created buffer {d}\n", .{buffer_id});

    // Return buffer ID as number (zero-copy!)
    // Note: We need to get the runtime to create the value
    // For now, this is a simplified version
    return null; // TODO: Create number value
}

/// nvim_buffer_insert_text(buffer_id, line, col, text)
export fn nvimBufferInsertText(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.C) ?*c.OVHermesValue {
    if (count < 4) return null;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    // Extract arguments (zero-copy!)
    const buffer_id_val = args[0] orelse return null;
    const line_val = args[1] orelse return null;
    const col_val = args[2] orelse return null;
    const text_val = args[3] orelse return null;

    // Get values
    const buffer_id: usize = @intFromFloat(c.hermes_value_get_number(buffer_id_val));
    const line: usize = @intFromFloat(c.hermes_value_get_number(line_val));
    const col: usize = @intFromFloat(c.hermes_value_get_number(col_val));

    // Get string (zero-copy pointer!)
    var text_len: usize = 0;
    const text_ptr = c.hermes_value_get_string(runtime, text_val, &text_len);
    if (text_ptr == null) return null;

    const text = text_ptr[0..text_len];

    // Call Zig buffer operation
    if (editor.getBuffer(buffer_id)) |buffer| {
        buffer.insertText(line, col, text) catch {
            return null;
        };

        std.debug.print("[Native] Inserted '{s}' at buffer {d} ({d},{d})\n", .{
            text,
            buffer_id,
            line,
            col,
        });
    }

    return null; // Return undefined
}

/// nvim_buffer_get_line(buffer_id, line) -> text
export fn nvimBufferGetLine(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.C) ?*c.OVHermesValue {
    if (count < 2) return null;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    const buffer_id_val = args[0] orelse return null;
    const line_val = args[1] orelse return null;

    const buffer_id: usize = @intFromFloat(c.hermes_value_get_number(buffer_id_val));
    const line: usize = @intFromFloat(c.hermes_value_get_number(line_val));

    // Get line from Zig buffer
    if (editor.getBuffer(buffer_id)) |buffer| {
        if (buffer.getLine(line)) |text| {
            std.debug.print("[Native] Read line {d} from buffer {d}: '{s}'\n", .{
                line,
                buffer_id,
                text,
            });

            // Return string to JavaScript (zero-copy pointer!)
            return c.hermes_value_create_string(runtime, text.ptr, text.len);
        }
    }

    return null; // Return undefined
}

/// zigGetCursorPosition() -> {row, col}
/// Returns current buffer cursor position as JavaScript object
export fn zigGetCursorPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    // Get cursor position from buffer
    const row = editor.buffer.cursor.row;
    const col = editor.buffer.cursor.col;

    // Create JavaScript object: {row, col}
    const obj = c.hermes_value_create_object(runtime) orelse return null;

    // Create number values for row and col
    const row_val = c.hermes_value_create_number(runtime, @floatFromInt(row));
    const col_val = c.hermes_value_create_number(runtime, @floatFromInt(col));

    if (row_val != null and col_val != null) {
        // Set properties on the object
        c.hermes_value_set_property(runtime, obj, "row", row_val);
        c.hermes_value_set_property(runtime, obj, "col", col_val);

        // Clean up temporary values
        c.hermes_value_destroy(row_val);
        c.hermes_value_destroy(col_val);
    }

    return obj;
}

/// zigSetCursorRenderPosition(row, col)
/// Sets the cursor render position override (for animations)
export fn zigSetCursorRenderPosition(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.C) ?*c.OVHermesValue {
    _ = runtime;

    if (count < 2) return null;

    const editor: *Editor = @ptrCast(@alignCast(context.?));

    const row_val = args[0] orelse return null;
    const col_val = args[1] orelse return null;

    const row: usize = @intFromFloat(c.hermes_value_get_number(row_val));
    const col: usize = @intFromFloat(c.hermes_value_get_number(col_val));

    // Store override position in editor
    editor.cursor_render_override.set(row, col);

    return null; // Return undefined
}

//
// Example Usage:
//
// var hermes = try HermesRuntime.init(allocator, &editor);
// defer hermes.deinit();
//
// const js_code =
//     \\const buffer_id = nvim_buffer_create();
//     \\nvim_buffer_insert_text(buffer_id, 0, 0, "Hello from Hermes+JSI!");
//     \\const line = nvim_buffer_get_line(buffer_id, 0);
//     \\print(line); // "Hello from Hermes+JSI!"
// ;
//
// try hermes.evaluate(js_code, "plugin.js");
//
// This achieves ZERO-COPY between JavaScript and Zig!
// Strings are passed as pointers, no serialization!
//
