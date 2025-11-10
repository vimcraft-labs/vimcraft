// Unified debug module - re-exports all debug components
pub const protocol = @import("backends/debug/protocol.zig");
pub const json = @import("backends/debug/json.zig");
pub const state = @import("backends/debug/state.zig");
pub const server = @import("backends/debug/server.zig");
// Note: EditorContext is deprecated - use editor/editor.zig Editor instead
pub const Editor = @import("editor/editor.zig").Editor;
