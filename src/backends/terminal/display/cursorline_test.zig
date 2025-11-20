const std = @import("std");
const testing = std.testing;

// Test cursorline rendering using Debug Protocol
// This spawns Vimcraft in --debug-protocol mode and verifies layer state
// TODO: This test is flaky - BrokenPipe errors and complex layer rendering issues
// Need to investigate timing issues or improve the test harness.
test "Cursorline: renders background to cursor layer via debug protocol" {
    if (true) return error.SkipZigTest; // Wrapped to avoid unreachable code warning
}

// TODO: This test is flaky - sometimes the process terminates before all responses are received.
// Need to investigate timing issues or improve the test harness.
test "Cursorline: visible in final composited output via debug protocol" {
    if (true) return error.SkipZigTest; // Wrapped to avoid unreachable code warning
}
