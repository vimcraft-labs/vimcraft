// Unified debug module - re-exports all debug components
pub const protocol = @import("debug/protocol.zig");
pub const json = @import("debug/json.zig");
pub const state = @import("debug/state.zig");
pub const server = @import("debug/server.zig");
