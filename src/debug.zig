// Unified debug module - re-exports all debug components
pub const protocol = @import("backends/headless/protocol.zig");
pub const json = @import("backends/headless/json.zig");
pub const state = @import("backends/headless/state.zig");
pub const Editor = @import("editor/editor.zig").Editor;
