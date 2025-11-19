/// Event Emitter for Native → JavaScript async communication
/// Enables autocommands, event-driven plugins, and reactive patterns
///
/// Design: Observer pattern with hash map of event → callbacks
/// Inspired by: React Native JSI events, Node.js EventEmitter
///
/// Usage:
///   // JavaScript
///   vim.on('BufEnter', (bufnr) => console.log('Entered buffer', bufnr));
///
///   // Zig
///   editor.event_emitter.emit("BufEnter", &[_]*c.OVHermesValue{bufnr_val});
const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;

/// EventEmitter - manages event listeners and emission
/// Critical for Phase 4 autocommands
pub const EventEmitter = struct {
    /// Map of event name → list of callbacks
    /// Example: "BufEnter" → [callback1, callback2, ...]
    callbacks: std.StringHashMap(std.ArrayList(*c.OVHermesValue)),

    /// JSI runtime for calling callbacks
    runtime: *c.OVHermesRuntime,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize event emitter
    pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) Self {
        return .{
            .callbacks = std.StringHashMap(std.ArrayList(*c.OVHermesValue)).init(allocator),
            .runtime = runtime,
            .allocator = allocator,
        };
    }

    /// Register a callback for an event
    /// JavaScript: vim.on('BufEnter', callback)
    ///
    /// Note: Clones callback value to keep reference alive
    pub fn on(self: *Self, event_name: []const u8, callback: *c.OVHermesValue) !void {
        // Verify callback is a function
        if (!c.hermes_value_is_function(self.runtime, callback)) {
            return error.NotAFunction;
        }

        // Get or create callback list for this event
        const entry = try self.callbacks.getOrPut(event_name);
        if (!entry.found_existing) {
            // First listener for this event - create new list
            entry.value_ptr.* = .empty;
        }

        // Clone callback to keep reference alive
        // (JavaScript GC won't collect it while we hold the reference)
        const callback_clone = c.hermes_value_clone(self.runtime, callback) orelse return error.CloneFailed;
        try entry.value_ptr.append(self.allocator, callback_clone);
    }

    /// Remove a specific callback for an event
    /// JavaScript: vim.off('BufEnter', callback)
    ///
    /// TODO: Implement callback comparison (need value equality check in C API)
    /// For now, this removes ALL callbacks for the event (workaround)
    pub fn off(self: *Self, event_name: []const u8, callback: *c.OVHermesValue) !void {
        _ = callback; // TODO: Use for comparison when C API supports it

        const list = self.callbacks.getPtr(event_name) orelse return; // No listeners for this event

        // TODO: Find and remove only matching callback
        // For now, remove all callbacks for this event
        for (list.items) |cb| {
            c.hermes_value_destroy(cb);
        }
        list.clearAndFree(self.allocator);
    }

    /// Remove all callbacks for an event
    /// JavaScript: vim.removeAllListeners('BufEnter')
    pub fn removeAllListeners(self: *Self, event_name: []const u8) void {
        const list = self.callbacks.getPtr(event_name) orelse return;

        for (list.items) |callback| {
            c.hermes_value_destroy(callback);
        }
        list.clearAndFree(self.allocator);
        _ = self.callbacks.remove(event_name);
    }

    /// Emit an event with arguments
    /// Calls all registered callbacks for this event
    ///
    /// Error handling: If a callback throws, continue to next callback
    /// (Don't let one bad callback break all others)
    pub fn emit(self: *Self, event_name: []const u8, args: []const *c.OVHermesValue) !void {
        const list = self.callbacks.get(event_name) orelse {
            // No listeners for this event - not an error, just no-op
            return;
        };

        if (list.items.len == 0) {
            return; // No listeners
        }

        // Call each registered callback
        for (list.items) |callback| {
            // Cast args to C-style pointer for C API
            const c_args: [*c]?*c.OVHermesValue = @ptrCast(@constCast(args.ptr));
            const result = c.hermes_call_function(
                self.runtime,
                callback,
                c_args,
                args.len,
            );

            if (result == null) {
                // Callback threw an error - continue to next callback
                continue;
            }

            // Clean up return value (we don't use it)
            c.hermes_value_destroy(result);
        }
    }

    /// Count listeners for an event
    pub fn listenerCount(self: *Self, event_name: []const u8) usize {
        const list = self.callbacks.get(event_name) orelse return 0;
        return list.items.len;
    }

    /// Get all event names that have listeners
    pub fn eventNames(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        errdefer names.deinit();

        var iter = self.callbacks.keyIterator();
        while (iter.next()) |key| {
            try names.append(key.*);
        }

        return names.toOwnedSlice();
    }

    /// Remove all callbacks for all events
    /// Called on config reload to clean up old listeners
    pub fn removeAll(self: *Self) void {
        var iter = self.callbacks.valueIterator();
        while (iter.next()) |list| {
            // Destroy Hermes values (callbacks)
            for (list.items) |callback| {
                c.hermes_value_destroy(callback);
            }
            // Clear the ArrayList items, but don't deinit (HashMap owns it)
            list.clearAndFree(self.allocator);
        }
        // Now clear the HashMap (will free the ArrayLists)
        self.callbacks.clearAndFree();
    }

    /// Cleanup and free resources
    pub fn deinit(self: *Self) void {
        self.removeAll();
        // Note: removeAll() already calls callbacks.clearAndFree()
        // which deinitializes the HashMap, so no need to call deinit() again
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EventEmitter: init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Note: Can't test without actual Hermes runtime
    // These are structural tests to verify compilation
    _ = allocator;
}

test "EventEmitter: basic structure" {
    const testing = std.testing;

    // Verify EventEmitter has expected fields
    const has_callbacks = @hasField(EventEmitter, "callbacks");
    const has_runtime = @hasField(EventEmitter, "runtime");
    const has_allocator = @hasField(EventEmitter, "allocator");

    try testing.expect(has_callbacks);
    try testing.expect(has_runtime);
    try testing.expect(has_allocator);
}
