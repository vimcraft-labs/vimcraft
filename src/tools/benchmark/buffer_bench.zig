const std = @import("std");
const vimcraft = @import("vimcraft");
const Buffer = vimcraft.__Buffer;
const RegisterManager = vimcraft.__RegisterManager;
const paste = vimcraft.__paste;
const benchmark = @import("benchmark.zig");

/// Create a test file with N lines
fn createTestFile(path: []const u8, lines: usize) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var writer = file.writer(&buf);

    var i: usize = 0;
    while (i < lines) : (i += 1) {
        try writer.interface.print("This is line {d} with some text content for testing\n", .{i});
    }
}

/// Benchmark: Load file
fn benchLoadFile(allocator: std.mem.Allocator, path: []const u8) !void {
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.loadFile(path);
}

/// Benchmark: Insert single character
fn benchInsertChar(buffer: *Buffer) !void {
    try buffer.insertChar('x');
}

/// Benchmark: Delete single character
fn benchDeleteChar(buffer: *Buffer) !void {
    try buffer.deleteChar();
}

/// Benchmark: Delete line
fn benchDeleteLine(buffer: *Buffer) !void {
    // Move to a valid position first
    if (buffer.lineCount() > 0) {
        buffer.cursor.row = @min(buffer.cursor.row, buffer.lineCount() - 1);
        try buffer.deleteLine();
    }
}

/// Benchmark: Yank line
fn benchYankLine(buffer: *Buffer, register_mgr: *RegisterManager) !void {
    const line_num = buffer.cursor.row;
    const line = buffer.getLine(line_num) orelse return;

    const text = if (line.len > 0 and line[line.len - 1] == '\n')
        line[0 .. line.len - 1]
    else
        line;

    const lines = [_][]const u8{text};
    try register_mgr.yank('"', &lines, .line_wise);
}

/// Benchmark: Paste line
fn benchPasteLine(buffer: *Buffer, register_mgr: *RegisterManager) !void {
    _ = try paste.pasteAfter(buffer, register_mgr, '"');
}

/// Benchmark: Move cursor (navigation)
fn benchMoveCursor(buffer: *Buffer) void {
    // Simulate typical navigation pattern
    buffer.cursor.col = @min(buffer.cursor.col + 1, 100);
    if (buffer.cursor.col >= 100) {
        buffer.cursor.col = 0;
        buffer.cursor.row = @min(buffer.cursor.row + 1, buffer.lineCount() - 1);
    }
}

/// Benchmark: Build line index
fn benchBuildLineIndex(buffer: *Buffer) !void {
    try buffer.buildLineIndex();
}

/// Run all buffer benchmarks
pub fn runBufferBenchmarks(allocator: std.mem.Allocator) !void {
    var suite = benchmark.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    benchmark.warmup();

    // Create test files of different sizes
    const small_file = "/tmp/bench_small.txt";
    const medium_file = "/tmp/bench_medium.txt";
    const large_file = "/tmp/bench_large.txt";

    try createTestFile(small_file, 100);
    try createTestFile(medium_file, 1000);
    try createTestFile(large_file, 10000);

    defer {
        std.fs.cwd().deleteFile(small_file) catch {};
        std.fs.cwd().deleteFile(medium_file) catch {};
        std.fs.cwd().deleteFile(large_file) catch {};
    }

    std.debug.print("=== Buffer Operations Benchmarks ===\n\n", .{});

    // Benchmark file loading
    {
        const result = try benchmark.benchmark(
            allocator,
            "Load small file (100 lines)",
            100,
            benchLoadFile,
            .{ allocator, small_file },
        );
        try suite.add(result);
    }

    {
        const result = try benchmark.benchmark(
            allocator,
            "Load medium file (1000 lines)",
            50,
            benchLoadFile,
            .{ allocator, medium_file },
        );
        try suite.add(result);
    }

    {
        const result = try benchmark.benchmark(
            allocator,
            "Load large file (10000 lines)",
            10,
            benchLoadFile,
            .{ allocator, large_file },
        );
        try suite.add(result);
    }

    // Benchmark operations on medium file
    {
        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(medium_file);

        // Insert character
        {
            const result = try benchmark.benchmark(
                allocator,
                "Insert character",
                1000,
                benchInsertChar,
                .{&buffer},
            );
            try suite.add(result);
        }

        // Rebuild buffer for next test
        buffer.deinit();
        buffer = Buffer.init(allocator);
        try buffer.loadFile(medium_file);

        // Delete character
        {
            const result = try benchmark.benchmark(
                allocator,
                "Delete character",
                1000,
                benchDeleteChar,
                .{&buffer},
            );
            try suite.add(result);
        }

        // Rebuild buffer for next test
        buffer.deinit();
        buffer = Buffer.init(allocator);
        try buffer.loadFile(medium_file);

        // Delete line
        {
            const result = try benchmark.benchmark(
                allocator,
                "Delete line",
                500,
                benchDeleteLine,
                .{&buffer},
            );
            try suite.add(result);
        }

        // Rebuild buffer for next test
        buffer.deinit();
        buffer = Buffer.init(allocator);
        try buffer.loadFile(medium_file);

        var register_mgr = RegisterManager.init(allocator);
        defer register_mgr.deinit();

        // Yank line
        {
            const result = try benchmark.benchmark(
                allocator,
                "Yank line",
                1000,
                benchYankLine,
                .{ &buffer, &register_mgr },
            );
            try suite.add(result);
        }

        // Paste line
        {
            const result = try benchmark.benchmark(
                allocator,
                "Paste line",
                1000,
                benchPasteLine,
                .{ &buffer, &register_mgr },
            );
            try suite.add(result);
        }

        // Rebuild buffer for next test
        buffer.deinit();
        buffer = Buffer.init(allocator);
        try buffer.loadFile(medium_file);

        // Move cursor
        {
            const result = try benchmark.benchmark(
                allocator,
                "Move cursor",
                10000,
                benchMoveCursor,
                .{&buffer},
            );
            try suite.add(result);
        }

        // Build line index
        {
            const result = try benchmark.benchmark(
                allocator,
                "Build line index (1000 lines)",
                100,
                benchBuildLineIndex,
                .{&buffer},
            );
            try suite.add(result);
        }
    }

    suite.printSummary();
}
