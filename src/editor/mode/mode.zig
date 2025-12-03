const std = @import("std");

/// Editor modes (Vim-compatible)
pub const Mode = enum {
    normal,
    insert,
    visual,
    command,
    search,

    pub fn toString(self: Mode) []const u8 {
        return switch (self) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .visual => "VISUAL",
            .command => "COMMAND",
            .search => "SEARCH",
        };
    }
};

/// Mode manager handles mode transitions
pub const ModeManager = struct {
    current_mode: Mode,

    pub fn init() ModeManager {
        return .{
            .current_mode = .normal,
        };
    }

    /// Enter Normal mode
    pub fn enterNormal(self: *ModeManager) void {
        self.current_mode = .normal;
    }

    /// Enter Insert mode
    pub fn enterInsert(self: *ModeManager) void {
        self.current_mode = .insert;
    }

    /// Enter Visual mode
    pub fn enterVisual(self: *ModeManager) void {
        self.current_mode = .visual;
    }

    /// Enter Command mode
    pub fn enterCommand(self: *ModeManager) void {
        self.current_mode = .command;
    }

    /// Enter Search mode
    pub fn enterSearch(self: *ModeManager) void {
        self.current_mode = .search;
    }

    /// Check if in Normal mode
    pub fn isNormal(self: *const ModeManager) bool {
        return self.current_mode == .normal;
    }

    /// Check if in Insert mode
    pub fn isInsert(self: *const ModeManager) bool {
        return self.current_mode == .insert;
    }

    /// Check if in Visual mode
    pub fn isVisual(self: *const ModeManager) bool {
        return self.current_mode == .visual;
    }

    /// Check if in Command mode
    pub fn isCommand(self: *const ModeManager) bool {
        return self.current_mode == .command;
    }

    /// Check if in Search mode
    pub fn isSearch(self: *const ModeManager) bool {
        return self.current_mode == .search;
    }

    /// Get current mode as string
    pub fn getModeString(self: *const ModeManager) []const u8 {
        return self.current_mode.toString();
    }
};

// Tests
test "Mode: transitions" {
    var mode_mgr = ModeManager.init();

    try std.testing.expect(mode_mgr.isNormal());

    mode_mgr.enterInsert();
    try std.testing.expect(mode_mgr.isInsert());
    try std.testing.expectEqualStrings("INSERT", mode_mgr.getModeString());

    mode_mgr.enterVisual();
    try std.testing.expect(mode_mgr.isVisual());

    mode_mgr.enterNormal();
    try std.testing.expect(mode_mgr.isNormal());
    try std.testing.expectEqualStrings("NORMAL", mode_mgr.getModeString());
}
