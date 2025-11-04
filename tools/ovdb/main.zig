const std = @import("std");
const client = @import("client.zig");
const script = @import("script.zig");
const reporter = @import("reporter.zig");

const usage =
    \\Usage: ovdb [command] [arguments]
    \\
    \\Commands:
    \\  connect <path>        Connect to OpenVim and enter interactive mode
    \\  run <script.ovdb>     Run a test script
    \\  ping <path>           Ping OpenVim to check if debug server responds
    \\
    \\Examples:
    \\  ovdb connect ./zig-out/bin/openvim
    \\  ovdb run test_visual.ovdb
    \\  ovdb ping ./zig-out/bin/openvim
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.io.getStdErr().writeAll(usage);
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "connect")) {
        if (args.len < 3) {
            try std.io.getStdErr().writeAll("Error: connect requires OpenVim path\n\n");
            try std.io.getStdErr().writeAll(usage);
            std.process.exit(1);
        }
        try connectCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "run")) {
        if (args.len < 3) {
            try std.io.getStdErr().writeAll("Error: run requires script path\n\n");
            try std.io.getStdErr().writeAll(usage);
            std.process.exit(1);
        }
        try runCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "ping")) {
        if (args.len < 3) {
            try std.io.getStdErr().writeAll("Error: ping requires OpenVim path\n\n");
            try std.io.getStdErr().writeAll(usage);
            std.process.exit(1);
        }
        try pingCommand(allocator, args[2]);
    } else {
        try std.io.getStdErr().writer().print("Error: unknown command '{s}'\n\n", .{command});
        try std.io.getStdErr().writeAll(usage);
        std.process.exit(1);
    }
}

/// Connect to OpenVim and enter interactive REPL mode
fn connectCommand(allocator: std.mem.Allocator, openvim_path: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print("Connecting to OpenVim at {s}...\n", .{openvim_path});

    var ovdb_client = client.Client.init(allocator, .{});
    defer ovdb_client.deinit();

    try ovdb_client.connect(openvim_path);
    try stdout.writeAll("Connected! Type 'help' for commands, 'quit' to exit.\n\n");

    // Interactive REPL
    var buf_reader = std.io.bufferedReader(stdin);
    var in_stream = buf_reader.reader();

    while (true) {
        try stdout.writeAll("ovdb> ");

        var line_buffer: [4096]u8 = undefined;
        const line = in_stream.readUntilDelimiterOrEof(&line_buffer, '\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        } orelse break;

        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // Handle built-in commands
        if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
            break;
        } else if (std.mem.eql(u8, trimmed, "help")) {
            try stdout.writeAll(
                \\Available commands:
                \\  ping                    - Ping the server
                \\  get_state               - Get full editor state
                \\  get_cursor              - Get cursor position
                \\  get_mode                - Get current mode
                \\  execute_keys <keys>     - Execute key sequence
                \\  quit                    - Exit REPL
                \\
            );
            continue;
        }

        // Parse and execute command
        try executeReplCommand(allocator, &ovdb_client, trimmed, stdout);
    }

    try stdout.writeAll("\nDisconnecting...\n");
}

/// Execute a single REPL command
fn executeReplCommand(
    allocator: std.mem.Allocator,
    ovdb_client: *client.Client,
    command_line: []const u8,
    writer: anytype,
) !void {
    // Simple command parsing
    var iter = std.mem.splitScalar(u8, command_line, ' ');
    const cmd = iter.next() orelse return;

    if (std.mem.eql(u8, cmd, "ping")) {
        const alive = try ovdb_client.ping();
        if (alive) {
            try writer.writeAll("✓ Server is alive\n");
        } else {
            try writer.writeAll("✗ Server did not respond\n");
        }
    } else if (std.mem.eql(u8, cmd, "get_cursor")) {
        var response = try ovdb_client.sendCommand(.get_cursor, .{ .none = {} });
        defer response.deinit(allocator);

        if (response.status == .ok and response.result != null) {
            const pos = response.result.?.cursor;
            try writer.print("Cursor: line={d}, col={d}\n", .{ pos.line, pos.col });
        } else if (response.@"error") |err| {
            try writer.print("Error: {s}\n", .{err});
        }
    } else if (std.mem.eql(u8, cmd, "get_mode")) {
        var response = try ovdb_client.sendCommand(.get_mode, .{ .none = {} });
        defer response.deinit(allocator);

        if (response.status == .ok and response.result != null) {
            try writer.print("Mode: {s}\n", .{response.result.?.mode.mode});
        } else if (response.@"error") |err| {
            try writer.print("Error: {s}\n", .{err});
        }
    } else if (std.mem.eql(u8, cmd, "get_state")) {
        var response = try ovdb_client.sendCommand(.get_state, .{ .none = {} });
        defer response.deinit(allocator);

        if (response.@"error") |err| {
            try writer.print("Error: {s}\n", .{err});
        } else {
            try writer.writeAll("State query succeeded (complex output not yet implemented)\n");
        }
    } else if (std.mem.eql(u8, cmd, "execute_keys")) {
        const keys = iter.rest();
        if (keys.len == 0) {
            try writer.writeAll("Error: execute_keys requires key sequence\n");
            return;
        }

        const keys_owned = try allocator.dupe(u8, keys);
        var response = try ovdb_client.sendCommand(.execute_keys, .{
            .execute_keys = .{ .keys = keys_owned },
        });
        defer response.deinit(allocator);

        if (response.status == .ok) {
            try writer.writeAll("Keys executed\n");
        } else if (response.@"error") |err| {
            try writer.print("Error: {s}\n", .{err});
        }
    } else {
        try writer.print("Unknown command: {s}\n", .{cmd});
        try writer.writeAll("Type 'help' for available commands\n");
    }
}

/// Run a test script
fn runCommand(allocator: std.mem.Allocator, script_path: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Parse script
    var commands = script.parseScript(allocator, script_path) catch |err| {
        try stderr.print("Error parsing script '{s}': {}\n", .{ script_path, err });
        std.process.exit(1);
    };
    defer {
        for (commands.items) |*cmd| {
            cmd.deinit(allocator);
        }
        commands.deinit();
    }

    if (commands.items.len == 0) {
        try stderr.print("Error: script '{s}' contains no commands\n", .{script_path});
        std.process.exit(1);
    }

    // Determine OpenVim path (should be in PATH or provide default)
    const openvim_path = std.process.getEnvVarOwned(allocator, "OPENVIM_PATH") catch |err| blk: {
        if (err == error.EnvironmentVariableNotFound) {
            // Try default path
            break :blk try allocator.dupe(u8, "./zig-out/bin/openvim");
        }
        return err;
    };
    defer allocator.free(openvim_path);

    // Connect to OpenVim
    var ovdb_client = client.Client.init(allocator, .{});
    defer ovdb_client.deinit();

    ovdb_client.connect(openvim_path) catch |err| {
        try stderr.print("Error connecting to OpenVim at '{s}': {}\n", .{ openvim_path, err });
        try stderr.print("Make sure OpenVim is built and the path is correct.\n", .{});
        try stderr.print("You can set OPENVIM_PATH environment variable to specify the path.\n", .{});
        std.process.exit(1);
    };

    // Execute script
    var results = try script.executeScript(allocator, &ovdb_client, commands.items, script_path);
    defer results.deinit(allocator);

    // Report results (LLM-optimized compact format)
    try reporter.report(results, stdout);

    // Exit with error code if tests failed
    if (results.failed > 0 or results.errors > 0) {
        std.process.exit(1);
    }
}

/// Ping OpenVim to check if debug server responds
fn pingCommand(allocator: std.mem.Allocator, openvim_path: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Pinging OpenVim at {s}...\n", .{openvim_path});

    var ovdb_client = client.Client.init(allocator, .{});
    defer ovdb_client.deinit();

    try ovdb_client.connect(openvim_path);

    const alive = try ovdb_client.ping();
    if (alive) {
        try stdout.writeAll("✓ Debug server is responding\n");
    } else {
        try stdout.writeAll("✗ Debug server did not respond\n");
        std.process.exit(1);
    }
}
