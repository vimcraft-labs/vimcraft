/// Buffer API Module
/// Exposes buffer content via ArrayBuffer (zero-copy, but use-after-free risk)
/// Works with current ArrayList-based buffer (will upgrade to Rope later)
///
/// ⚠️  SAFETY: Version tracking is implemented and exposed via getChangedTick()
/// - Buffer has version: u64 field, incremented on ALL modifications
/// - JavaScript CAN check version via vim.buffer.getChangedTick()
/// - ArrayBuffers become invalid on any buffer modification (insert/delete/undo/redo/paste/loadFile)
/// - USE-AFTER-FREE is still possible if JavaScript ignores changedtick checks
///
/// Safe usage pattern (Neovim-compatible):
///   const ab = vim.buffer.getContent();
///   const tick = vim.buffer.getChangedTick();
///   // ... later ...
///   if (vim.buffer.getChangedTick() === tick) { /* safe to use ab */ }
///
/// Future enhancements:
/// - Add version context to finalizers for owned ArrayBuffers
/// - Implement detach-on-reallocation for automatic invalidation
/// - Add runtime validation via Proxy wrappers in JavaScript
const std = @import("std");
const Buffer = @import("../../editor/buffer/buffer.zig").Buffer;
const helpers = @import("helpers.zig");

// Import shared Hermes C API
const c_api = @import("c_api.zig");
const c = c_api.c;

/// vim.buffer.getContent() -> ArrayBuffer
/// Returns buffer content as External ArrayBuffer (zero-copy!)
///
/// JavaScript usage:
///   const ab = vim.buffer.getContent();          // ArrayBuffer
///   const view = new Uint8Array(ab);             // View into native memory
///   const text = new TextDecoder().decode(view); // Convert to string if needed
///
/// ⚠️  IMPORTANT: This is a SNAPSHOT! ArrayBuffer is invalidated when:
///    - Buffer is modified (insert/delete/undo/redo)
///    - Buffer is reallocated (grows beyond capacity)
///    - Buffer version changes (buffer.version incremented on ANY modification)
///
/// ⚠️  SAFETY: Version tracking available via getChangedTick() - JavaScript CAN detect staleness!
///    - Use-after-free is POSSIBLE if you IGNORE changedtick checks
///    - Always capture tick when getting ArrayBuffer, validate before use
///
/// Safe patterns:
///   // Option 1: Check version before use (Neovim-compatible)
///   const ab = vim.buffer.getContent();
///   const tick = vim.buffer.getChangedTick();
///   // ... later ...
///   if (vim.buffer.getChangedTick() === tick) { /* safe to use ab */ }
///
///   // Option 2: Immediate copy (slower but safe)
///   const snapshot = new Uint8Array(vim.buffer.getContent()).slice();
pub export fn getBufferContent(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    // Get current buffer content as contiguous string (Rope → owned slice)
    // NOTE: This allocates memory! We need a finalizer to free it.
    const content = buffer.content.toString() catch return c.hermes_value_create_null(rt);

    // Create finalizer context (allocator to free the string)
    const FreeContext = struct {
        slice: []u8,
        allocator: std.mem.Allocator,
    };
    const free_ctx = buffer.allocator.create(FreeContext) catch {
        buffer.allocator.free(content);
        return c.hermes_value_create_null(rt);
    };
    free_ctx.* = .{
        .slice = content,
        .allocator = buffer.allocator,
    };

    // Finalizer function
    const finalizer = struct {
        fn free(data: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) void {
            _ = data;
            const free_context: *FreeContext = @ptrCast(@alignCast(ctx.?));
            free_context.allocator.free(free_context.slice);
            free_context.allocator.destroy(free_context);
        }
    }.free;

    // Return External ArrayBuffer with finalizer
    // Finalizer will be called when JavaScript GC collects the ArrayBuffer
    return c.hermes_value_create_arraybuffer_external(
        rt,
        @ptrCast(@constCast(content.ptr)),
        content.len,
        finalizer,
        @ptrCast(free_ctx),
    );
}

/// vim.buffer.getContentCopy() -> ArrayBuffer
/// ⚠️ DEPRECATED: Misleading name - doesn't actually copy, returns same External ArrayBuffer
/// This function is identical to getContent() but kept for legacy compatibility
/// TODO: Remove in future version - use getContent() instead
///
/// JavaScript usage (DEPRECATED):
///   const ab = vim.buffer.getContentCopy();      // ArrayBuffer (misleading name!)
///   const view = new Uint8Array(ab);             // View into native memory
pub export fn getBufferContentCopy(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    // ⚠️ MISLEADING: This doesn't copy, it's identical to getContent()
    // Kept only for backwards compatibility with legacy code
    return getBufferContent(runtime, context, args, count);
}

/// vim.buffer.getLineContent(line_num) -> ArrayBuffer
/// Returns a single line as External ArrayBuffer (zero-copy!)
///
/// JavaScript usage:
///   const ab = vim.buffer.getLineContent(5);     // ArrayBuffer for line 5
///   const view = new Uint8Array(ab);             // View into native memory
///   const text = new TextDecoder().decode(view); // Convert to string if needed
///
/// ⚠️  IMPORTANT: This is a SNAPSHOT! ArrayBuffer is invalidated on buffer modifications.
pub export fn getLineContent(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    if (count < 1) return c.hermes_value_create_null(rt);

    const line_num_val = args[0] orelse return c.hermes_value_create_null(rt);
    const line_num = @as(usize, @intFromFloat(c.hermes_value_get_number(line_num_val)));

    // Get line slice (now returns OWNED memory after Rope migration)
    const line = buffer.getLine(line_num) orelse return c.hermes_value_create_null(rt);

    // ✅ FIX: Create finalizer context (allocator to free the line)
    const FreeContext = struct {
        slice: []const u8,
        allocator: std.mem.Allocator,
    };
    const free_ctx = buffer.allocator.create(FreeContext) catch {
        buffer.allocator.free(line); // Clean up on allocation failure
        return c.hermes_value_create_null(rt);
    };
    free_ctx.* = .{
        .slice = line,
        .allocator = buffer.allocator,
    };

    // ✅ FIX: Finalizer function to free line when JS GC collects ArrayBuffer
    const finalizer = struct {
        fn free(data: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) void {
            _ = data;
            const free_context: *FreeContext = @ptrCast(@alignCast(ctx.?));
            free_context.allocator.free(free_context.slice);
            free_context.allocator.destroy(free_context);
        }
    }.free;

    // Return External ArrayBuffer WITH finalizer (memory will be freed by JS GC)
    return c.hermes_value_create_arraybuffer_external(
        rt,
        @ptrCast(@constCast(line.ptr)),
        line.len,
        finalizer, // ✅ FIX: Finalizer added
        @ptrCast(free_ctx), // ✅ FIX: Context added
    );
}

/// vim.buffer.getLength() -> number
/// Returns buffer content length in bytes
pub export fn getBufferLength(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    return c.hermes_value_create_number(rt, @floatFromInt(buffer.content.len()));
}

/// vim.buffer.getLineCount() -> number
/// Returns number of lines in buffer
pub export fn getBufferLineCount(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    return c.hermes_value_create_number(rt, @floatFromInt(buffer.lineCount()));
}

/// vim.buffer.getChangedTick() -> number
/// Returns buffer modification counter (Neovim-compatible)
///
/// This is a monotonically increasing counter that increments on EVERY buffer modification.
/// Use it to detect when cached data (like ArrayBuffers) has become stale.
///
/// JavaScript usage:
///   const ab = vim.buffer.getContent();
///   const tick = vim.buffer.getChangedTick();    // Capture current tick
///
///   // ... later ...
///   if (vim.buffer.getChangedTick() === tick) {
///     // Safe: buffer hasn't changed, ArrayBuffer still valid
///   } else {
///     // Unsafe: buffer changed, ArrayBuffer is stale, get new one
///   }
///
/// Neovim compatibility:
///   This is equivalent to nvim_buf_get_changedtick() and b:changedtick
///
/// See: https://neovim.io/doc/user/api.html#nvim_buf_get_changedtick()
pub export fn getBufferChangedTick(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = args;
    _ = count;

    const rt = runtime orelse return null;
    const buffer: *Buffer = @ptrCast(@alignCast(context.?));

    return c.hermes_value_create_number(rt, @floatFromInt(buffer.version));
}

// ============================================================================
// HostObject Implementation (Zero-Copy JSI)
// ============================================================================

/// vim.buffer HostObject getter - routes property access to methods
pub export fn bufferHostObjectGet(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    prop_name: [*c]const u8,
) callconv(.c) ?*c.OVHermesValue {
    const rt = runtime orelse return null;
    const name = std.mem.span(prop_name);

    // Use StaticStringMap for O(1) property dispatch
    // Note: getContentCopy removed from HostObject interface (misleading name)
    // It's still available via legacy registration for backwards compatibility
    const PropertyMap = std.StaticStringMap(*const fn (
        ?*c.OVHermesRuntime,
        ?*anyopaque,
        [*c]?*c.OVHermesValue,
        usize,
    ) callconv(.c) ?*c.OVHermesValue).initComptime(.{
        .{ "getContent", getBufferContent },
        .{ "getLineContent", getLineContent },
        .{ "getLength", getBufferLength },
        .{ "getLineCount", getBufferLineCount },
        .{ "getChangedTick", getBufferChangedTick },
    });

    const func = PropertyMap.get(name) orelse return null;

    // Return function value (wrapped by C++ CustomHostObject)
    return c.hermes_create_function(rt, prop_name, func, context);
}

/// vim.buffer HostObject enumerator - returns array of method names
/// Note: getContentCopy deliberately excluded (deprecated, misleading name)
pub export fn bufferHostObjectEnumerator(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;
    const rt = runtime orelse return null;

    const method_names = [_][]const u8{
        "getContent",
        "getLineContent",
        "getLength",
        "getLineCount",
        "getChangedTick",
    };

    const arr = c.hermes_array_create(rt, method_names.len) orelse return null;

    for (method_names, 0..) |name, i| {
        const str = c.hermes_value_create_string(rt, name.ptr, name.len) orelse continue;
        c.hermes_array_set(rt, arr, i, str);
        c.hermes_value_destroy(str);
    }

    return arr;
}

// ============================================================================
// Registration
// ============================================================================

/// Register buffer API as HostObject (zero-copy ArrayBuffer access)
/// JavaScript usage: vim.buffer.getContent(), vim.buffer.getLineContent(5)
/// Note: getContentCopy deliberately NOT exposed (misleading name, deprecated)
pub fn register(runtime: *c.OVHermesRuntime, buffer: *Buffer) void {
    c.hermes_register_host_object(
        runtime,
        "vimBuffer",
        bufferHostObjectGet,
        null, // No setter (read-only methods for now)
        bufferHostObjectEnumerator,
        @ptrCast(buffer),
    );
}

/// Legacy registration (backwards compatibility)
/// ⚠️ DEPRECATED: getBufferContentCopy has misleading name (doesn't copy)
/// TODO: Remove after all examples/tests updated to use HostObject API
pub fn registerLegacy(runtime: *c.OVHermesRuntime, buffer: *Buffer) void {
    c.hermes_register_host_function(
        runtime,
        "getBufferContent",
        getBufferContent,
        @ptrCast(buffer),
    );
    c.hermes_register_host_function(
        runtime,
        "getBufferContentCopy",
        getBufferContentCopy, // ⚠️ DEPRECATED: Misleading name
        @ptrCast(buffer),
    );
    c.hermes_register_host_function(
        runtime,
        "getLineContent",
        getLineContent,
        @ptrCast(buffer),
    );
}
