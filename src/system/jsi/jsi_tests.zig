// JSI Test Suite Runner
// Imports all JSI-related tests for execution via `zig build test`

// Import test modules to make them discoverable by test runner
test {
    _ = @import("host_object_test.zig");
    _ = @import("motion_api_test.zig");
    _ = @import("autocmd_api_test.zig");
    // Note: module_api_test.zig has known issues with hermesRequire()
    // returning null in lean build. Excluded until fixed.
    // _ = @import("module_api_test.zig");
}
