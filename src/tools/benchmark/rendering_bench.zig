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
const MockEditor = struct {
    buffer: Buffer,
    highlight_registry: vimcraft.__HighlightRegistry,
};

/// Create a test file with N lines
fn createTestFile(path: []const u8, lines: usize) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var i: usize = 0;
    while (i < lines) : (i += 1) {
        try writer.print("Line {d:4}: The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.\n", .{i});
    }

    try file.writeAll(fbs.getWritten());
}

/// Benchmark: Single render (tests synchronized updates + base performance)
fn benchSingleRender(
    display: *Display,
    editor: *MockEditor,
    status: []const u8,
    cursorline_enabled: bool,
    visual_state: *VisualState,
    yank_highlight: *YankHighlight,
) !void {
    const listchars = ListChars{};
    try display.render(editor, status, cursorline_enabled, visual_state, yank_highlight, false, &listchars, 2);
}

/// Benchmark: Rapid sequential renders (tests throttling + batching)
fn benchRapidRenders(
    display: *Display,
    editor: *MockEditor,
    status: []const u8,
    cursorline_enabled: bool,
    visual_state: *VisualState,
    yank_highlight: *YankHighlight,
    count: usize,
) !void {
    const listchars = ListChars{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try display.render(editor, status, cursorline_enabled, visual_state, yank_highlight, false, &listchars, 2);
    }
}

/// Benchmark: Render with cursor position changes (tests cursor tracking optimization)
fn benchCursorMovements(
    display: *Display,
    editor: *MockEditor,
    status: []const u8,
    cursorline_enabled: bool,
    visual_state: *VisualState,
    yank_highlight: *YankHighlight,
    movements: usize,
) !void {
    const listchars = ListChars{};
    var i: usize = 0;
    while (i < movements) : (i += 1) {
        // Move cursor right, wrapping to next line
        editor.buffer.cursor.col += 1;
        if (editor.buffer.cursor.col > 80) {
            editor.buffer.cursor.col = 0;
            editor.buffer.cursor.row += 1;
        }
        try display.render(editor, status, cursorline_enabled, visual_state, yank_highlight, false, &listchars, 2);
    }
    // Reset cursor
    editor.buffer.cursor.row = 0;
    editor.buffer.cursor.col = 0;
}

/// Benchmark: Scrolling (tests scroll region optimization)
fn benchScrolling(
    display: *Display,
    editor: *MockEditor,
    status: []const u8,
    cursorline_enabled: bool,
    visual_state: *VisualState,
    yank_highlight: *YankHighlight,
    scroll_steps: usize,
) !void {
    const listchars = ListChars{};
    var i: usize = 0;
    while (i < scroll_steps) : (i += 1) {
        // Simulate scrolling down
        display.viewport_top += 1;
        editor.buffer.cursor.row = display.viewport_top + 10;
        try display.render(editor, status, cursorline_enabled, visual_state, yank_highlight, false, &listchars, 2);
    }
    // Reset viewport
    display.viewport_top = 0;
    editor.buffer.cursor.row = 0;
}

/// Benchmark: Visual mode rendering (tests multi-layer composition)
fn benchVisualMode(
    display: *Display,
    editor: *MockEditor,
    status: []const u8,
    cursorline_enabled: bool,
    visual_state: *VisualState,
    yank_highlight: *YankHighlight,
) !void {
    const listchars = ListChars{};
    // Enable visual mode
    visual_state.active = true;
    visual_state.mode = .char;
    visual_state.anchor = .{ .line = 5, .col = 10 };
    editor.buffer.cursor.row = 10;
    editor.buffer.cursor.col = 50;

    try display.render(editor, status, cursorline_enabled, visual_state, yank_highlight, false, &listchars, 2);

    // Disable visual mode
    visual_state.active = false;
    editor.buffer.cursor.row = 0;
    editor.buffer.cursor.col = 0;
}

/// Run rendering optimization benchmarks
pub fn runRenderingOptimizationBenchmarks(allocator: std.mem.Allocator) !void {
    var suite = benchmark.BenchmarkSuite.init(allocator);
    defer suite.deinit();

    benchmark.warmup();

    std.debug.print("\n=== Rendering Optimization Benchmarks ===\n\n", .{});

    // Create test files
    const small_file = "/tmp/bench_render_opt_small.txt";
    const medium_file = "/tmp/bench_render_opt_medium.txt";
    const large_file = "/tmp/bench_render_opt_large.txt";

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

    display.terminal_rows = 40;
    display.terminal_cols = 120;
    try display.setLineNumbers(true);

    // Initialize highlight config
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

    // ============================================================================
    // Benchmark 1: Single Render Performance (Synchronized Updates Impact)
    // ============================================================================
    // Tests: DCS sequences overhead, basic render path
    {
        std.debug.print("1. Single Render Performance (Synchronized Updates)\n", .{});

        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(medium_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };

        const result = try benchmark.benchmark(
            allocator,
            "Single render (medium file, sync updates enabled)",
            1000,
            benchSingleRender,
            .{ &display, &editor, status, false, &visual_state, &yank_highlight },
        );
        try suite.add(result);
        std.debug.print("   Avg: {d:.3}ms | Target: <16.67ms (60 FPS)\n\n", .{result.avg_ms});
    }

    // ============================================================================
    // Benchmark 2: Rapid Sequential Renders (Render Throttling)
    // ============================================================================
    // Tests: Throttling logic overhead, frame skipping efficiency
    {
        std.debug.print("2. Rapid Sequential Renders (Throttling)\n", .{});

        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(small_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };

        // Benchmark 10 rapid renders
        const start = std.time.nanoTimestamp();
        try benchRapidRenders(&display, &editor, status, false, &visual_state, &yank_highlight, 10);
        const end = std.time.nanoTimestamp();

        const total_ns: u64 = @intCast(end - start);
        const avg_ns = total_ns / 10;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;
        const fps = 1000.0 / avg_ms;

        try suite.add(benchmark.BenchmarkResult{
            .name = "10 rapid renders (throttling active)",
            .iterations = 10,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .min_ns = avg_ns,
            .max_ns = avg_ns,
            .avg_ms = avg_ms,
        });
        std.debug.print("   Avg: {d:.3}ms/render | Effective FPS: {d:.1} | Target: 60 FPS\n\n", .{ avg_ms, fps });
    }

    // ============================================================================
    // Benchmark 3: Cursor Position Changes (Cursor Tracking Optimization)
    // ============================================================================
    // Tests: Cursor position tracking, redundant escape code elimination
    {
        std.debug.print("3. Cursor Position Changes (Position Tracking)\n", .{});

        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(medium_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };

        const start = std.time.nanoTimestamp();
        try benchCursorMovements(&display, &editor, status, false, &visual_state, &yank_highlight, 50);
        const end = std.time.nanoTimestamp();

        const total_ns: u64 = @intCast(end - start);
        const avg_ns = total_ns / 50;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        try suite.add(benchmark.BenchmarkResult{
            .name = "50 cursor movements (position tracking)",
            .iterations = 50,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .min_ns = avg_ns,
            .max_ns = avg_ns,
            .avg_ms = avg_ms,
        });
        std.debug.print("   Avg: {d:.3}ms/movement | Target: <5ms\n\n", .{avg_ms});
    }

    // ============================================================================
    // Benchmark 4: Scrolling Performance (Scroll Region Optimization)
    // ============================================================================
    // Tests: Viewport changes, scroll region usage, incremental updates
    {
        std.debug.print("4. Scrolling Performance (Scroll Regions)\n", .{});

        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(large_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };

        const start = std.time.nanoTimestamp();
        try benchScrolling(&display, &editor, status, false, &visual_state, &yank_highlight, 100);
        const end = std.time.nanoTimestamp();

        const total_ns: u64 = @intCast(end - start);
        const avg_ns = total_ns / 100;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        try suite.add(benchmark.BenchmarkResult{
            .name = "100 scroll steps (scroll regions)",
            .iterations = 100,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .min_ns = avg_ns,
            .max_ns = avg_ns,
            .avg_ms = avg_ms,
        });
        std.debug.print("   Avg: {d:.3}ms/scroll | Target: <10ms\n\n", .{avg_ms});
    }

    // ============================================================================
    // Benchmark 5: Visual Mode Rendering (Multi-Layer Composition)
    // ============================================================================
    // Tests: Compositor layer blending, attribute tracking, color code generation
    {
        std.debug.print("5. Visual Mode Rendering (Multi-Layer Composition)\n", .{});

        var buffer = Buffer.init(allocator);
        defer buffer.deinit();
        try buffer.loadFile(medium_file);

        var registry = vimcraft.__HighlightRegistry.init(allocator);
        defer registry.deinit();
        var editor = MockEditor{ .buffer = buffer, .highlight_registry = registry };

        const result = try benchmark.benchmark(
            allocator,
            "Render with visual selection (layer composition)",
            500,
            benchVisualMode,
            .{ &display, &editor, status, false, &visual_state, &yank_highlight },
        );
        try suite.add(result);
        std.debug.print("   Avg: {d:.3}ms | Overhead vs normal: ~{d:.1}%\n\n", .{
            result.avg_ms,
            ((result.avg_ms - suite.results.items[0].avg_ms) / suite.results.items[0].avg_ms) * 100.0,
        });
    }

    // Print summary
    std.debug.print("\n=== Summary ===\n\n", .{});
    suite.printSummary();

    // Print optimization analysis
    std.debug.print("\n=== Optimization Analysis ===\n\n", .{});
    std.debug.print("✓ Synchronized Updates: ", .{});
    if (suite.results.items[0].avg_ms < 16.67) {
        std.debug.print("EXCELLENT (within 60 FPS budget)\n", .{});
    } else if (suite.results.items[0].avg_ms < 33.33) {
        std.debug.print("GOOD (within 30 FPS budget)\n", .{});
    } else {
        std.debug.print("NEEDS OPTIMIZATION (exceeds 30 FPS budget)\n", .{});
    }

    std.debug.print("✓ Render Throttling: ", .{});
    const throttle_fps = 1000.0 / suite.results.items[1].avg_ms;
    if (throttle_fps <= 60.0) {
        std.debug.print("EXCELLENT (throttled to ~{d:.1} FPS)\n", .{throttle_fps});
    } else if (throttle_fps <= 120.0) {
        std.debug.print("GOOD (throttled to ~{d:.1} FPS)\n", .{throttle_fps});
    } else {
        std.debug.print("NEEDS OPTIMIZATION (excessive renders: ~{d:.1} FPS)\n", .{throttle_fps});
    }

    std.debug.print("✓ Cursor Tracking: ", .{});
    if (suite.results.items[2].avg_ms < 5.0) {
        std.debug.print("EXCELLENT (<5ms per movement)\n", .{});
    } else if (suite.results.items[2].avg_ms < 10.0) {
        std.debug.print("GOOD (<10ms per movement)\n", .{});
    } else {
        std.debug.print("NEEDS OPTIMIZATION (>10ms per movement)\n", .{});
    }

    std.debug.print("✓ Scroll Regions: ", .{});
    if (suite.results.items[3].avg_ms < 10.0) {
        std.debug.print("EXCELLENT (<10ms per scroll)\n", .{});
    } else if (suite.results.items[3].avg_ms < 20.0) {
        std.debug.print("GOOD (<20ms per scroll)\n", .{});
    } else {
        std.debug.print("NEEDS OPTIMIZATION (>20ms per scroll)\n", .{});
    }

    std.debug.print("✓ Layer Composition: ", .{});
    const overhead = ((suite.results.items[4].avg_ms - suite.results.items[0].avg_ms) / suite.results.items[0].avg_ms) * 100.0;
    if (overhead < 10.0) {
        std.debug.print("EXCELLENT (<10% overhead)\n", .{});
    } else if (overhead < 25.0) {
        std.debug.print("GOOD (<25% overhead)\n", .{});
    } else {
        std.debug.print("NEEDS OPTIMIZATION (>{d:.1}% overhead)\n", .{overhead});
    }

    std.debug.print("\n", .{});
}
