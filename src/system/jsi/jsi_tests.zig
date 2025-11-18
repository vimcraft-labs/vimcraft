// JSI Test Suite Runner
// Imports all JSI-related tests for execution via `zig build test`

// Import test modules to make them discoverable by test runner
test {
    _ = @import("host_object_test.zig");
    _ = @import("motion_api_test.zig");
}
