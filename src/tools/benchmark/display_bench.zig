const std = @import("std");
const vimcraft = @import("vimcraft");
const Buffer = vimcraft.__Buffer;
const Display = vimcraft.__Display;
const VisualState = vimcraft.__VisualState;
const YankHighlight = vimcraft.__YankHighlight;
const highlights = vimcraft.__highlights;
const ListChars = vimcraft.__ListChars;
const benchmark = @import("benchmark.zig");

/// Minimal mock editor for benchmarking
/// Contains only fields needed by render() (buffer and highlight_registry)
const MockEditor = struct {
    buffer: Buffer,
    // No syntax field - benchmarks run without syntax highlighting
    highlight_registry: vimcraft.__HighlightRegistry,
};

/// Create a test file with N lines
fn createTestFile(path: []const u8, lines: usize) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var writer = file.writer(&buf);

    var i: usize = 0;
    while (i < lines) : (i += 1) {
        try writer.interface.print("Line {d:4}: The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.\n", .{i});
    }
}

/// Benchmark: Render full screen
fn benchRender(
    display: *Display,
    editor: *MockEditor,
    status: []const u8,
    cursorline_enabled: bool,
    visual_state: *VisualState,
    yank_highlight: *YankHighlight,
) !void {
    const listchars = ListChars{};
    try display.render(editor, status, cursorline_enabled, visual_state, yank_highlight, false, &listchars);
}

/// Run display rendering benchmarks
pub fn runDisplayBenchmarks(allocator: std.mem.Allocator) !void {
    var suite = benchmark.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    benchmark.warmup();

    std.debug.print("\n=== Display Rendering Benchmarks ===\n\n", .{});

    // Create test files
    const small_file = "/tmp/bench_display_small.txt";
    const medium_file = "/tmp/bench_display_medium.txt";
    const large_file = "/tmp/bench_display_large.txt";

    try createTestFile(small_file, 50);
    try createTestFile(medium_file, 500);
    try createTestFile(large_file, 5000);

    defer {
        std.fs.cwd().deleteFile(small_file) catch {};
        std.fs.cwd().deleteFile(medium_file) catch {};
        std.fs.cwd().deleteFile(large_file) catch {};
    }

    // Initialize display (simulated terminal size)
    var display = try Display.init(allocator);
    defer display.deinit();

    // Set reasonable terminal dimensions for benchmarking
    display.terminal_rows = 40;
    display.terminal_cols = 120;
    try display.setLineNumbers(true);

    // Initialize highlight config with some colors
    var config = highlights.HighlightConfig.init(allocator);
    defer config.deinit();

    const bg_color = try highlights.Color.fromHex("#1A1B26");
    const fg_color = try highlights.Color.fromHex("#ABB2BF");
    const cursor_color = try highlights.Color.fromHex("#1E202F");

    config.normal = highlights.Highlight{ .bg = bg_color, .fg = fg_color };
    config.cursorline = highlights.Highlight{ .bg = cursor_color };
    config.cursorline_enabled = true;

    var visual_state = VisualState{
        .active = false,
        .mode = .char,
        .anchor = .{ .line = 0, .col = 0 },
    };

    var yank_highlight = YankHighlight{};

    const status = "NORMAL";

    // Benchmark rendering with different file sizes
    {
        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(small_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };
        const result = try benchmark.benchmark(
            allocator,
            "Render small file (50 lines)",
            500,
            benchRender,
            .{ &display, &editor, status, false, &visual_state, &yank_highlight },
        );
        try suite.add(result);
    }

    {
        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(medium_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };
        const result = try benchmark.benchmark(
            allocator,
            "Render medium file (500 lines)",
            200,
            benchRender,
            .{ &display, &editor, status, false, &visual_state, &yank_highlight },
        );
        try suite.add(result);
    }

    {
        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(large_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };
        const result = try benchmark.benchmark(
            allocator,
            "Render large file (5000 lines)",
            100,
            benchRender,
            .{ &display, &editor, status, false, &visual_state, &yank_highlight },
        );
        try suite.add(result);
    }

    // Benchmark with visual mode active
    {
        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(medium_file);

        visual_state.active = true;
        visual_state.mode = .char;
        visual_state.anchor = .{ .line = 5, .col = 10 };
        buffer.cursor.row = 10;
        buffer.cursor.col = 20;

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };
        const result = try benchmark.benchmark(
            allocator,
            "Render with visual selection",
            200,
            benchRender,
            .{ &display, &editor, status, false, &visual_state, &yank_highlight },
        );
        try suite.add(result);

        visual_state.active = false;
    }

    // Benchmark scrolling (viewport changes)
    {
        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(large_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };

        // Test rendering at different viewport positions
        var scroll_test_count: usize = 0;
        const start = std.time.nanoTimestamp();

        const listchars = ListChars{};
        while (scroll_test_count < 100) : (scroll_test_count += 1) {
            // Simulate scrolling by changing viewport
            display.viewport_top = scroll_test_count * 10;
            editor.buffer.cursor.row = display.viewport_top + 10;
            try display.render(&editor, status, false, &visual_state, &yank_highlight, false, &listchars);
        }

        const end = std.time.nanoTimestamp();
        const total_ns: u64 = @intCast(end - start);
        const avg_ns = total_ns / 100;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        try suite.add(benchmark.BenchmarkResult{
            .name = "Render with scrolling (100 positions)",
            .iterations = 100,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .min_ns = avg_ns, // Approximation
            .max_ns = avg_ns, // Approximation
            .avg_ms = avg_ms,
        });

        display.viewport_top = 0;
    }

    suite.printSummary();
}
