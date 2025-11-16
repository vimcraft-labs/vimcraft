//! Input Handler - Neovim-style persistent buffer for terminal input parsing
//!
//! Architecture (based on Neovim's libtermkey):
//! 1. Persistent buffer: Accumulates bytes across stdin.read() calls
//! 2. Partial consumption: Only consumes bytes that form complete sequences
//! 3. No timeout hacks: Returns "incomplete" status instead of guessing
//!
//! Key insight from Neovim's handle_bracketed_paste() (input.c:533-572):
//! ```c
//! if (size >= 6 && starts_with(ptr, PASTE_START)) {
//!     // Complete sequence - process it
//!     return 6;
//! } else if (size < 6 && starts_with(PASTE_START, ptr)) {
//!     // Partial match - set incomplete flag, DON'T consume
//!     *incomplete = true;
//!     return 0;  // Leave bytes in buffer for next read
//! }
//! ```
//!
//! CURRENT LIMITATIONS (as of Phase 3):
//! - Only handles bracketed paste sequences (ESC[200~ / ESC[201~)
//! - Arrow keys, function keys, mouse events not yet implemented
//! - Will require refactoring to sequence table when adding more sequences (Phase 5)
//! - See: https://github.com/neovim/neovim/blob/master/src/nvim/tui/input.c for reference

const std = @import("std");

pub const InputHandler = struct {
    allocator: std.mem.Allocator,

    // Persistent buffer (Neovim-style) - survives across stdin.read() calls
    buffer: std.ArrayList(u8),
    buffer_start: usize = 0,  // Start of unconsumed data

    pub fn init(allocator: std.mem.Allocator) InputHandler {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *InputHandler) void {
        self.buffer.deinit(self.allocator);
    }

    /// Feed bytes from stdin (Neovim pattern: APPEND to persistent buffer)
    pub fn pushBytes(self: *InputHandler, bytes: []const u8) !void {
        // Consolidate buffer if we've consumed more than half
        if (self.buffer_start > self.buffer.items.len / 2) {
            const unconsumed_len = self.buffer.items.len - self.buffer_start;
            if (unconsumed_len > 0) {
                std.mem.copyForwards(
                    u8,
                    self.buffer.items[0..unconsumed_len],
                    self.buffer.items[self.buffer_start..]
                );
            }
            self.buffer.shrinkRetainingCapacity(unconsumed_len);
            self.buffer_start = 0;
        }

        // APPEND new bytes (critical: don't replace!)
        try self.buffer.appendSlice(self.allocator, bytes);
    }

    /// Result of parsing attempt
    pub const ParseResult = union(enum) {
        /// Complete sequence parsed, consume N bytes
        complete: struct {
            bytes: []const u8,  // The bytes that formed this sequence
            kind: SequenceKind,
        },
        /// Incomplete sequence, need more bytes
        incomplete: void,
        /// No input available
        none: void,
    };

    pub const SequenceKind = enum {
        bracketed_paste_start,  // ESC[200~
        bracketed_paste_end,    // ESC[201~
        arrow_up,               // ESC[A
        arrow_down,             // ESC[B
        arrow_right,            // ESC[C
        arrow_left,             // ESC[D
        normal_char,            // Any other byte(s)
    };

    /// Try to parse next sequence from buffer (Neovim-style)
    /// Returns complete/incomplete/none based on buffer state
    pub fn nextSequence(self: *InputHandler) ParseResult {
        const unconsumed = self.buffer.items[self.buffer_start..];
        if (unconsumed.len == 0) return .{ .none = {} };

        // OPTIMIZATION: Fast path for non-ESC characters (normal typing)
        // This avoids checking escape sequences for regular letters (4x performance win)
        if (unconsumed[0] != '\x1b') {
            return self.parseNormalChar(unconsumed);
        }

        // Check for escape sequences (only if starts with ESC)

        // Arrow keys (ESC[A, ESC[B, ESC[C, ESC[D)
        if (unconsumed.len >= 3) {
            if (unconsumed[1] == '[') {
                switch (unconsumed[2]) {
                    'A' => {
                        const bytes = unconsumed[0..3];
                        self.buffer_start += 3;
                        return .{ .complete = .{ .bytes = bytes, .kind = .arrow_up } };
                    },
                    'B' => {
                        const bytes = unconsumed[0..3];
                        self.buffer_start += 3;
                        return .{ .complete = .{ .bytes = bytes, .kind = .arrow_down } };
                    },
                    'C' => {
                        const bytes = unconsumed[0..3];
                        self.buffer_start += 3;
                        return .{ .complete = .{ .bytes = bytes, .kind = .arrow_right } };
                    },
                    'D' => {
                        const bytes = unconsumed[0..3];
                        self.buffer_start += 3;
                        return .{ .complete = .{ .bytes = bytes, .kind = .arrow_left } };
                    },
                    else => {},
                }
            }
        }

        // Partial arrow key? (ESC or ESC[)
        if (unconsumed.len < 3) {
            if (unconsumed.len == 1 or (unconsumed.len == 2 and unconsumed[1] == '[')) {
                // Could be start of arrow key - wait for more bytes
                return .{ .incomplete = {} };
            }
        }

        // Bracketed paste sequences
        const paste_start = "\x1b[200~";
        const paste_end = "\x1b[201~";

        // Complete paste start?
        if (unconsumed.len >= paste_start.len) {
            if (std.mem.startsWith(u8, unconsumed, paste_start)) {
                const bytes = unconsumed[0..paste_start.len];
                self.buffer_start += paste_start.len;
                return .{ .complete = .{ .bytes = bytes, .kind = .bracketed_paste_start } };
            }
        }

        // Partial paste start? (Neovim pattern: leave in buffer!)
        if (unconsumed.len < paste_start.len) {
            if (std.mem.startsWith(u8, paste_start, unconsumed)) {
                // Incomplete! Wait for more bytes
                return .{ .incomplete = {} };
            }
        }

        // Complete paste end?
        if (unconsumed.len >= paste_end.len) {
            if (std.mem.startsWith(u8, unconsumed, paste_end)) {
                const bytes = unconsumed[0..paste_end.len];
                self.buffer_start += paste_end.len;
                return .{ .complete = .{ .bytes = bytes, .kind = .bracketed_paste_end } };
            }
        }

        // Partial paste end?
        if (unconsumed.len < paste_end.len) {
            if (std.mem.startsWith(u8, paste_end, unconsumed)) {
                return .{ .incomplete = {} };
            }
        }

        // Not a paste sequence - return first byte as normal char
        // (This handles ESC followed by non-sequence characters)
        return self.parseNormalChar(unconsumed);
    }

    /// Parse a normal character (non-escape-sequence) with UTF-8 validation
    /// CRITICAL: Validates multi-byte UTF-8 to avoid splitting characters across reads
    fn parseNormalChar(self: *InputHandler, unconsumed: []const u8) ParseResult {
        // Determine UTF-8 sequence length from first byte
        const utf8_len = std.unicode.utf8ByteSequenceLength(unconsumed[0]) catch {
            // Invalid UTF-8 start byte - consume it and return replacement character
            self.buffer_start += 1;
            return .{ .complete = .{ .bytes = "�", .kind = .normal_char } };
        };

        // Check if we have the complete UTF-8 sequence in buffer
        if (unconsumed.len < utf8_len) {
            // Partial UTF-8 sequence (e.g., first byte of 'ñ' arrived but second byte hasn't)
            // CRITICAL: Don't consume! Wait for more bytes to avoid splitting UTF-8 characters
            return .{ .incomplete = {} };
        }

        // Validate the UTF-8 sequence
        const codepoint = std.unicode.utf8Decode(unconsumed[0..utf8_len]) catch {
            // Invalid UTF-8 sequence - consume bad bytes and return replacement character
            self.buffer_start += utf8_len;
            return .{ .complete = .{ .bytes = "�", .kind = .normal_char } };
        };
        _ = codepoint; // Validation successful, codepoint not needed

        // Return the complete UTF-8 character
        self.buffer_start += utf8_len;
        return .{ .complete = .{
            .bytes = unconsumed[0..utf8_len],
            .kind = .normal_char,
        } };
    }

    /// Get number of unconsumed bytes in buffer
    pub fn unconsumedBytes(self: *InputHandler) usize {
        return self.buffer.items.len - self.buffer_start;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "input handler: single character" {
    const testing = std.testing;
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();

    try handler.pushBytes("a");

    const result = handler.nextSequence();
    try testing.expect(result == .complete);
    try testing.expectEqual(InputHandler.SequenceKind.normal_char, result.complete.kind);
    try testing.expectEqualStrings("a", result.complete.bytes);
}

test "input handler: bracketed paste start complete" {
    const testing = std.testing;
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();

    try handler.pushBytes("\x1b[200~");

    const result = handler.nextSequence();
    try testing.expect(result == .complete);
    try testing.expectEqual(InputHandler.SequenceKind.bracketed_paste_start, result.complete.kind);
}

test "input handler: bracketed paste start incomplete" {
    const testing = std.testing;
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();

    // Feed incomplete sequence byte-by-byte
    try handler.pushBytes("\x1b");
    {
        const result = handler.nextSequence();
        try testing.expect(result == .incomplete);  // Needs more bytes!
    }

    try handler.pushBytes("[200~");  // Complete it
    {
        const result = handler.nextSequence();
        try testing.expect(result == .complete);
        try testing.expectEqual(InputHandler.SequenceKind.bracketed_paste_start, result.complete.kind);
    }
}

test "input handler: persistent buffer across multiple pushes" {
    const testing = std.testing;
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();

    // Simulate byte-by-byte input (like terminal does with tab paste)
    try handler.pushBytes("\x1b");
    try testing.expect(handler.nextSequence() == .incomplete);

    try handler.pushBytes("[");
    try testing.expect(handler.nextSequence() == .incomplete);

    try handler.pushBytes("2");
    try testing.expect(handler.nextSequence() == .incomplete);

    try handler.pushBytes("0");
    try testing.expect(handler.nextSequence() == .incomplete);

    try handler.pushBytes("0");
    try testing.expect(handler.nextSequence() == .incomplete);

    try handler.pushBytes("~");
    // NOW it's complete!
    const result = handler.nextSequence();
    try testing.expect(result == .complete);
    try testing.expectEqual(InputHandler.SequenceKind.bracketed_paste_start, result.complete.kind);
}

test "input handler: normal chars don't trigger incomplete" {
    const testing = std.testing;
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();

    try handler.pushBytes("hello");

    for ("hello") |expected| {
        const result = handler.nextSequence();
        try testing.expect(result == .complete);
        try testing.expectEqual(InputHandler.SequenceKind.normal_char, result.complete.kind);
        try testing.expectEqual(expected, result.complete.bytes[0]);
    }
}
