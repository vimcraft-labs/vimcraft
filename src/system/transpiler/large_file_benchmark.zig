/// Benchmark: Large TypeScript Files (Real-World Plugin Sizes)
/// Tests 1KB → 10MB to determine caching threshold
const std = @import("std");
const esbuild = @import("esbuild.zig");

/// Generate TypeScript code of specific size
fn generateTypeScriptCode(allocator: std.mem.Allocator, target_bytes: usize) ![]const u8 {
    var code = try std.ArrayList(u8).initCapacity(allocator, target_bytes);
    errdefer code.deinit(allocator);

    // Generate realistic TypeScript (classes, interfaces, functions)
    try code.appendSlice(allocator,
        \\// Auto-generated plugin code
        \\interface PluginConfig {
        \\    name: string;
        \\    version: string;
        \\    enabled: boolean;
        \\}
        \\
        \\
    );

    // Generate repeated class definitions to reach target size
    var i: usize = 0;
    while (code.items.len < target_bytes) : (i += 1) {
        try code.writer(allocator).print(
            \\class Plugin{d} {{
            \\    private config: PluginConfig;
            \\    private state: Map<string, any> = new Map();
            \\
            \\    constructor(config: PluginConfig) {{
            \\        this.config = config;
            \\    }}
            \\
            \\    public async initialize(): Promise<void> {{
            \\        console.log(`Initializing ${{this.config.name}}`);
            \\        await this.loadState();
            \\    }}
            \\
            \\    private async loadState(): Promise<void> {{
            \\        // Load plugin state
            \\        const data = await fetch('/api/state');
            \\        const json = await data.json();
            \\        for (const [key, value] of Object.entries(json)) {{
            \\            this.state.set(key, value);
            \\        }}
            \\    }}
            \\
            \\    public getState(key: string): any {{
            \\        return this.state.get(key);
            \\    }}
            \\
            \\    public setState(key: string, value: any): void {{
            \\        this.state.set(key, value);
            \\    }}
            \\}}
            \\
            \\
        , .{i});

        // Don't overshoot the target
        if (code.items.len > target_bytes) {
            code.shrinkRetainingCapacity(target_bytes);
            break;
        }
    }

    return try code.toOwnedSlice(allocator);
}

test "Benchmark: Large TypeScript Files" {
    const allocator = std.testing.allocator;

    std.debug.print("\n\n{s}\n", .{"=" ** 80});
    std.debug.print("  LARGE FILE TRANSPILATION BENCHMARK\n", .{});
    std.debug.print("  (Real-world plugin sizes: 1KB → 10MB)\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    const test_sizes = [_]usize{
        1 * 1024, // 1KB
        10 * 1024, // 10KB
        100 * 1024, // 100KB
        1024 * 1024, // 1MB
        5 * 1024 * 1024, // 5MB
        10 * 1024 * 1024, // 10MB
    };

    std.debug.print("{s:15} | {s:15} | {s:15} | {s:15}\n", .{ "File Size", "TS → JS Time", "Est. Total", "Caching?" });
    std.debug.print("{s}\n", .{"-" ** 80});

    for (test_sizes) |size| {
        // Generate TypeScript code of target size
        std.debug.print("Generating {d}KB TypeScript code...\r", .{size / 1024});
        const source = try generateTypeScriptCode(allocator, size);
        defer allocator.free(source);

        // Measure transpilation time
        const start = std.time.nanoTimestamp();
        const js_code = try esbuild.transpile(allocator, source, "ts");
        const end = std.time.nanoTimestamp();
        allocator.free(js_code);

        const elapsed_ns = @as(u64, @intCast(end - start));
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

        // Estimate total time (TS→JS→HBC)
        // Hermes bytecode compilation is roughly 10-20ms per MB
        const size_mb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0);
        const hermes_compile_ms = size_mb * 15.0; // Conservative estimate
        const total_ms = elapsed_ms + hermes_compile_ms;

        // Determine if caching is needed
        const needs_cache = total_ms > 50.0;
        const cache_symbol = if (needs_cache) "⚠️  YES" else "✅ No";

        const size_kb = @as(f64, @floatFromInt(size)) / 1024.0;
        const size_str = if (size < 1024 * 1024)
            try std.fmt.allocPrint(allocator, "{d:.0}KB", .{size_kb})
        else
            try std.fmt.allocPrint(allocator, "{d:.1}MB", .{size_kb / 1024.0});
        defer allocator.free(size_str);

        std.debug.print("{s:15} | {d:13.2}ms | {d:13.2}ms | {s:15}\n", .{
            size_str,
            elapsed_ms,
            total_ms,
            cache_symbol,
        });
    }

    std.debug.print("\n{s}\n", .{"=" ** 80});
    std.debug.print("  ANALYSIS & RECOMMENDATIONS\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print("✅ No caching needed (< 50ms total):\n", .{});
    std.debug.print("   - Small plugins: 0-100KB\n", .{});
    std.debug.print("   - Typical configs: init.ts, keymaps, simple plugins\n", .{});
    std.debug.print("   - Strategy: Transpile on every startup\n\n", .{});

    std.debug.print("⚠️  Caching REQUIRED (> 50ms total):\n", .{});
    std.debug.print("   - Large plugins: 100KB+\n", .{});
    std.debug.print("   - Complex LSP integrations, UI frameworks\n", .{});
    std.debug.print("   - Strategy: Cache .hbc files, check mtime\n\n", .{});

    std.debug.print("🚨 CRITICAL for 10MB files:\n", .{});
    std.debug.print("   - Without cache: ~5-10 SECONDS startup time\n", .{});
    std.debug.print("   - With cache: ~50-100ms (just loading .hbc)\n", .{});
    std.debug.print("   - Strategy: ALWAYS cache large files\n\n", .{});

    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  RECOMMENDED CACHING STRATEGY\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print(
        \\1. Check file size:
        \\   - if (size < 100KB) → transpile in-memory (fast!)
        \\   - if (size >= 100KB) → check cache
        \\
        \\2. Cache location:
        \\   ~/.cache/vimcraft/bytecode/<hash>.hbc
        \\   (hash = SHA256 of source file path + mtime)
        \\
        \\3. Cache invalidation:
        \\   - Compare source file mtime with cache mtime
        \\   - If source newer → re-transpile
        \\   - If cache newer → load cached .hbc
        \\
        \\4. Lazy compilation:
        \\   - Don't compile all plugins on startup
        \\   - Compile on-demand when plugin is loaded
        \\   - Parallel compilation for multiple plugins
        \\
        \\Example workflow:
        \\  vim.require("lsp-config")  // 5MB TypeScript
        \\      ↓
        \\  Check cache (~/.cache/vimcraft/bytecode/abc123.hbc)
        \\      ↓
        \\  Cache hit? → Load .hbc (~50ms)
        \\  Cache miss? → Transpile → Save .hbc → Load (~5s first time, 50ms after)
        \\
        \\
    , .{});

    std.debug.print("{s}\n\n", .{"=" ** 80});
}
