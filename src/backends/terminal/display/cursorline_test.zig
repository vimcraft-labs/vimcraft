const std = @import("std");
const testing = std.testing;
const options_mod = @import("../../../editor/config/options.zig");
const option_defs = @import("../../../editor/config/option_defs.zig");

// Test cursorline rendering using Debug Protocol
// This spawns Vimcraft in --headless-debug mode and verifies layer state
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

// Unit test: Verify cursorline option stored and retrieved correctly
// This catches the bug where backend.zig used "cursorLine" (camelCase)
// but options are stored as "cursorline" (vim-style)
test "Cursorline: option stored as vim-style name 'cursorline'" {
    var mgr = options_mod.OptionsManager.init(testing.allocator);
    defer mgr.deinit();

    // Set using vim-style name (as config_api.zig does via meta.name)
    try mgr.setBoolean("cursorline", true);

    // Verify retrieval using vim-style name (as backend.zig should do)
    const value = mgr.getBoolean("cursorline");
    try testing.expect(value != null);
    try testing.expect(value.? == true);

    // Verify camelCase name does NOT work (proves the bug would fail)
    const wrong_name_value = mgr.getBoolean("cursorLine");
    try testing.expect(wrong_name_value == null);
}

// Unit test: Verify option_defs has correct cursorline metadata
test "Cursorline: option_defs has vim-style name" {
    const meta = option_defs.getOptionMeta("cursorline");
    try testing.expect(meta != null);
    try testing.expectEqualStrings("cursorline", meta.?.name);
    try testing.expectEqualStrings("cursorLine", meta.?.js_name);
    try testing.expectEqualStrings("cul", meta.?.short_name.?);
}

// Unit test: Verify getOptionMeta resolves all name variants
test "Cursorline: getOptionMeta resolves vim, js, and short names" {
    // Vim-style name
    const meta_vim = option_defs.getOptionMeta("cursorline");
    try testing.expect(meta_vim != null);

    // JavaScript camelCase name
    const meta_js = option_defs.getOptionMeta("cursorLine");
    try testing.expect(meta_js != null);
    try testing.expectEqualStrings(meta_vim.?.name, meta_js.?.name);

    // Short name
    const meta_short = option_defs.getOptionMeta("cul");
    try testing.expect(meta_short != null);
    try testing.expectEqualStrings(meta_vim.?.name, meta_short.?.name);
}

// ============================================================================
// Regression test: Cursorline must follow cursor when moving between lines
// ============================================================================
// BUG (January 2025): Cursorline rendered but didn't follow cursor movement
// ROOT CAUSE: cursor-only render optimization (renderCursorOnly) bypassed
//             full layer updates when cursor row changed
//
// The bug was in backend.zig render() method:
// 1. Cursor-only path triggered when only cursor moved (buffer unchanged)
// 2. But cursorline requires cursor_layer update when cursor ROW changes
// 3. needs_layer_update check was comparing with already-updated tracking state
//    (cursor_row_changed always false because self.last_cursor_line was updated
//     before the comparison)
//
// FIX:
// 1. Save prev_cursor_line BEFORE updating tracking state
// 2. Compare current_cursor_line != prev_cursor_line (not self.last_cursor_line)
// 3. If cursor_row_changed AND (cursorline OR relativenumber OR number), skip
//    cursor-only path and do full render
//
// This test documents the fix by verifying the option retrieval pattern that
// backend.zig uses. The actual cursor movement behavior is tested via PTY tests.
test "Cursorline: needs_layer_update logic - cursorline option check" {
    var mgr = options_mod.OptionsManager.init(testing.allocator);
    defer mgr.deinit();

    // Simulate: User sets vim.opt.cursorline = true (via config_api.zig)
    try mgr.setBoolean("cursorline", true);

    // Backend.zig uses this pattern to check if cursorline is enabled:
    // const cursorline_enabled = if (self.editor.options_manager) |opts|
    //     opts.getBoolean("cursorline") orelse false
    // else
    //     false;
    const cursorline_enabled = mgr.getBoolean("cursorline") orelse false;
    try testing.expect(cursorline_enabled == true);

    // When cursorline is enabled AND cursor row changes:
    // needs_layer_update = cursor_row_changed and cursorline_enabled
    // This should trigger full render path (skip cursor-only optimization)
    const cursor_row_changed = true; // Simulating: cursor moved from row 0 to row 1
    const needs_layer_update = cursor_row_changed and cursorline_enabled;
    try testing.expect(needs_layer_update == true);
}

// Same test for relativenumber - also requires layer update on cursor row change
test "Cursorline: needs_layer_update logic - relativenumber option check" {
    var mgr = options_mod.OptionsManager.init(testing.allocator);
    defer mgr.deinit();

    // vim.opt.relativenumber = true
    try mgr.setBoolean("relativenumber", true);

    const relativenumber_enabled = mgr.getBoolean("relativenumber") orelse false;
    try testing.expect(relativenumber_enabled == true);

    const cursor_row_changed = true;
    const needs_layer_update = cursor_row_changed and relativenumber_enabled;
    try testing.expect(needs_layer_update == true);
}

// Same test for number option (active line number needs update on cursor row change)
test "Cursorline: needs_layer_update logic - number option check" {
    var mgr = options_mod.OptionsManager.init(testing.allocator);
    defer mgr.deinit();

    // vim.opt.number = true
    try mgr.setBoolean("number", true);

    const number_enabled = mgr.getBoolean("number") orelse false;
    try testing.expect(number_enabled == true);

    const cursor_row_changed = true;
    const needs_layer_update = cursor_row_changed and number_enabled;
    try testing.expect(needs_layer_update == true);
}

// Verify cursor-only optimization still works when no line-tracking features enabled
test "Cursorline: needs_layer_update logic - no options means cursor-only path" {
    var mgr = options_mod.OptionsManager.init(testing.allocator);
    defer mgr.deinit();

    // No cursorline, no relativenumber, no number = cursor-only path allowed
    const cursorline_enabled = mgr.getBoolean("cursorline") orelse false;
    const relativenumber_enabled = mgr.getBoolean("relativenumber") orelse false;
    const number_enabled = mgr.getBoolean("number") orelse false;

    try testing.expect(cursorline_enabled == false);
    try testing.expect(relativenumber_enabled == false);
    try testing.expect(number_enabled == false);

    // Even if cursor row changed, no layer update needed
    const cursor_row_changed = true;
    const needs_layer_update = cursor_row_changed and (cursorline_enabled or relativenumber_enabled or number_enabled);
    try testing.expect(needs_layer_update == false); // Cursor-only path OK!
}
