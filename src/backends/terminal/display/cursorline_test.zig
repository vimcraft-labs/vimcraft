const std = @import("std");
const testing = std.testing;

// Test cursorline rendering using Debug Protocol
// This spawns Vimcraft in --debug-protocol mode and verifies layer state

test "Cursorline: renders background to cursor layer via debug protocol" {
    const allocator = testing.allocator;

    // Create test file
    const test_file_path = "/tmp/test_cursorline_zig.txt";
    const test_file = try std.fs.cwd().createFile(test_file_path, .{});
    defer std.fs.cwd().deleteFile(test_file_path) catch {};
    try test_file.writeAll("Line 1\nLine 2\nLine 3\n");
    test_file.close();

    // Spawn Vimcraft in debug protocol mode
    var child = std.process.Child.init(&[_][]const u8{
        "./zig-out/bin/vimcraft",
        "--debug-protocol",
    }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    defer {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }

    const stdin = child.stdin.?;
    const stdout = child.stdout.?;

    // Give it time to initialize
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Send commands via JSON protocol
    // 1. Load file
    try stdin.writeAll("{\"cmd\":\"load_file\",\"args\":{\"path\":\"/tmp/test_cursorline_zig.txt\"},\"id\":\"1\"}\n");

    // 2. Move cursor to line 2 (execute 'j')
    try stdin.writeAll("{\"cmd\":\"execute_keys\",\"args\":{\"keys\":\"j\"},\"id\":\"2\"}\n");

    // 3. Get cursor layer cells
    try stdin.writeAll("{\"cmd\":\"get_layer_cells\",\"args\":{\"name\":\"cursor\"},\"id\":\"3\"}\n");

    // 4. Shutdown
    try stdin.writeAll("{\"cmd\":\"shutdown\",\"args\":{},\"id\":\"99\"}\n");

    // Read responses
    var buf: [65536]u8 = undefined;
    var total_read: usize = 0;

    // Read all output (with timeout)
    var attempts: u32 = 0;
    while (attempts < 50) : (attempts += 1) {
        const bytes_read = stdout.read(buf[total_read..]) catch break;
        if (bytes_read == 0) break;
        total_read += bytes_read;
        if (total_read >= buf.len - 1) break;
    }

    const output = buf[0..total_read];

    // Parse JSON responses line by line
    var line_iter = std.mem.splitScalar(u8, output, '\n');
    var found_layer_cells = false;
    var has_background = false;

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            line,
            .{},
        ) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;

        const obj = root.object;
        const id = obj.get("id") orelse continue;
        if (id != .string) continue;

        // Check if this is the get_layer_cells response (id="3")
        if (std.mem.eql(u8, id.string, "3")) {
            found_layer_cells = true;

            const status = obj.get("status") orelse continue;
            if (status != .string) continue;
            try testing.expectEqualStrings("ok", status.string);

            const result = obj.get("result") orelse continue;
            if (result != .object) continue;

            const cells = result.object.get("cells") orelse continue;
            if (cells != .array) continue;

            // Check cells on row 1 (cursor line after 'j')
            var row1_bg_count: usize = 0;
            for (cells.array.items) |cell| {
                if (cell != .object) continue;
                const cell_obj = cell.object;

                const row = cell_obj.get("row") orelse continue;
                if (row != .integer) continue;
                if (row.integer != 1) continue; // Check row 1 (cursor line)

                // Check if this cell has background
                const bg = cell_obj.get("bg");
                if (bg != null and bg.? != .null) {
                    row1_bg_count += 1;
                    has_background = true;

                    // Verify the background color values exist
                    if (bg.? == .object) {
                        const bg_obj = bg.?.object;
                        const r = bg_obj.get("r");
                        const g = bg_obj.get("g");
                        const b = bg_obj.get("b");

                        // Just verify they exist and are integers
                        try testing.expect(r != null);
                        try testing.expect(g != null);
                        try testing.expect(b != null);
                    }
                }
            }

            // Verify we found background cells on cursor line
            try testing.expect(row1_bg_count > 0);
        }
    }

    // Ensure we got the response we were looking for
    try testing.expect(found_layer_cells);
    try testing.expect(has_background);
}

test "Cursorline: visible in final composited output via debug protocol" {
    const allocator = testing.allocator;

    // Create test file
    const test_file_path = "/tmp/test_cursorline_output.txt";
    const test_file = try std.fs.cwd().createFile(test_file_path, .{});
    defer std.fs.cwd().deleteFile(test_file_path) catch {};
    try test_file.writeAll("Line 1\nLine 2\nLine 3\n");
    test_file.close();

    // Spawn Vimcraft
    var child = std.process.Child.init(&[_][]const u8{
        "./zig-out/bin/vimcraft",
        "--debug-protocol",
    }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    defer {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }

    const stdin = child.stdin.?;
    const stdout = child.stdout.?;

    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Send commands
    try stdin.writeAll("{\"cmd\":\"load_file\",\"args\":{\"path\":\"/tmp/test_cursorline_output.txt\"},\"id\":\"1\"}\n");
    try stdin.writeAll("{\"cmd\":\"execute_keys\",\"args\":{\"keys\":\"j\"},\"id\":\"2\"}\n");
    try stdin.writeAll("{\"cmd\":\"get_output_grid\",\"args\":{},\"id\":\"3\"}\n");
    try stdin.writeAll("{\"cmd\":\"shutdown\",\"args\":{},\"id\":\"99\"}\n");

    // Read output
    var buf: [65536]u8 = undefined;
    var total_read: usize = 0;
    var attempts: u32 = 0;
    while (attempts < 50) : (attempts += 1) {
        const bytes_read = stdout.read(buf[total_read..]) catch break;
        if (bytes_read == 0) break;
        total_read += bytes_read;
        if (total_read >= buf.len - 1) break;
    }

    const output = buf[0..total_read];

    // Parse responses
    var line_iter = std.mem.splitScalar(u8, output, '\n');
    var found_output_grid = false;
    var has_cursorline_bg = false;

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            line,
            .{},
        ) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;

        const obj = root.object;
        const id = obj.get("id") orelse continue;
        if (id != .string) continue;

        if (std.mem.eql(u8, id.string, "3")) {
            found_output_grid = true;

            const status = obj.get("status") orelse continue;
            if (status != .string) continue;
            try testing.expectEqualStrings("ok", status.string);

            const result = obj.get("result") orelse continue;
            if (result != .object) continue;

            const cells = result.object.get("cells") orelse continue;
            if (cells != .array) continue;

            // Check that row 1 (cursor line) has background in final output
            for (cells.array.items) |cell| {
                if (cell != .object) continue;
                const cell_obj = cell.object;

                const row = cell_obj.get("row") orelse continue;
                if (row != .integer) continue;
                if (row.integer != 1) continue;

                const bg = cell_obj.get("bg");
                if (bg != null and bg.? != .null) {
                    has_cursorline_bg = true;
                    break;
                }
            }
        }
    }

    try testing.expect(found_output_grid);
    try testing.expect(has_cursorline_bg);
}
