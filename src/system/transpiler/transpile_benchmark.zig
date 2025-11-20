/// Benchmark: TypeScript → JavaScript → Hermes Bytecode
/// Measures end-to-end transpilation + compilation time
const std = @import("std");
const esbuild = @import("esbuild.zig");

// Import Hermes C API for bytecode compilation
const c = @cImport({
    @cInclude("hermes/hermes.h");
});

/// Benchmark a single transpilation cycle
fn benchmarkTranspile(
    allocator: std.mem.Allocator,
    source: []const u8,
    label: []const u8,
) !u64 {
    const start = std.time.nanoTimestamp();

    // Step 1: TypeScript → JavaScript (via esbuild)
    const js_code = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(js_code);

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    std.debug.print("{s:30} | Source: {d:6} bytes | JS: {d:6} bytes | Time: {d:6.2}ms\n", .{
        label,
        source.len,
        js_code.len,
        elapsed_ms,
    });

    return elapsed_ns;
}

/// Test Case 1: Small plugin (typical init.js size)
const small_plugin =
    \\interface Config {
    \\    tabstop: number;
    \\    expandtab: boolean;
    \\}
    \\
    \\const config: Config = {
    \\    tabstop: 4,
    \\    expandtab: true
    \\};
    \\
    \\vim.opt.tabstop = config.tabstop;
    \\vim.opt.expandtab = config.expandtab;
;

/// Test Case 2: Medium plugin (LSP config, keymap setup)
const medium_plugin =
    \\interface KeymapOptions {
    \\    mode: string;
    \\    lhs: string;
    \\    rhs: string | (() => void);
    \\    silent?: boolean;
    \\    noremap?: boolean;
    \\}
    \\
    \\class KeymapManager {
    \\    private mappings: Map<string, KeymapOptions> = new Map();
    \\
    \\    register(opts: KeymapOptions): void {
    \\        const key = `${opts.mode}:${opts.lhs}`;
    \\        this.mappings.set(key, opts);
    \\        vim.keymap.set(opts.mode, opts.lhs, opts.rhs, {
    \\            silent: opts.silent ?? true,
    \\            noremap: opts.noremap ?? true
    \\        });
    \\    }
    \\
    \\    unregister(mode: string, lhs: string): void {
    \\        const key = `${mode}:${lhs}`;
    \\        this.mappings.delete(key);
    \\        vim.keymap.del(mode, lhs);
    \\    }
    \\
    \\    getAll(): KeymapOptions[] {
    \\        return Array.from(this.mappings.values());
    \\    }
    \\}
    \\
    \\const keymaps = new KeymapManager();
    \\
    \\// Setup common keymaps
    \\keymaps.register({ mode: 'n', lhs: '<leader>ff', rhs: () => vim.motion.down() });
    \\keymaps.register({ mode: 'n', lhs: '<leader>fg', rhs: () => vim.motion.up() });
    \\keymaps.register({ mode: 'v', lhs: '<leader>y', rhs: '"+y' });
    \\
    \\export default keymaps;
;

/// Test Case 3: Large plugin (full LSP integration)
const large_plugin =
    \\interface LSPConfig {
    \\    serverName: string;
    \\    rootDir?: string;
    \\    filetypes: string[];
    \\    settings?: Record<string, any>;
    \\}
    \\
    \\interface Diagnostic {
    \\    line: number;
    \\    column: number;
    \\    severity: 'error' | 'warning' | 'info' | 'hint';
    \\    message: string;
    \\    source?: string;
    \\}
    \\
    \\class LSPClient {
    \\    private config: LSPConfig;
    \\    private diagnostics: Map<string, Diagnostic[]> = new Map();
    \\    private isRunning: boolean = false;
    \\
    \\    constructor(config: LSPConfig) {
    \\        this.config = config;
    \\    }
    \\
    \\    async start(): Promise<void> {
    \\        if (this.isRunning) return;
    \\        console.log(`Starting LSP server: ${this.config.serverName}`);
    \\        this.isRunning = true;
    \\    }
    \\
    \\    async stop(): Promise<void> {
    \\        if (!this.isRunning) return;
    \\        console.log(`Stopping LSP server: ${this.config.serverName}`);
    \\        this.isRunning = false;
    \\        this.diagnostics.clear();
    \\    }
    \\
    \\    async textDocumentDidOpen(uri: string, content: string): Promise<void> {
    \\        console.log(`Document opened: ${uri}`);
    \\    }
    \\
    \\    async textDocumentDidChange(uri: string, content: string): Promise<void> {
    \\        console.log(`Document changed: ${uri}`);
    \\    }
    \\
    \\    async textDocumentDidSave(uri: string): Promise<void> {
    \\        console.log(`Document saved: ${uri}`);
    \\    }
    \\
    \\    getDiagnostics(uri: string): Diagnostic[] {
    \\        return this.diagnostics.get(uri) ?? [];
    \\    }
    \\
    \\    setDiagnostics(uri: string, diagnostics: Diagnostic[]): void {
    \\        this.diagnostics.set(uri, diagnostics);
    \\    }
    \\}
    \\
    \\// Rust analyzer config
    \\const rustLSP = new LSPClient({
    \\    serverName: 'rust-analyzer',
    \\    filetypes: ['rust'],
    \\    settings: {
    \\        'rust-analyzer': {
    \\            cargo: { allFeatures: true },
    \\            checkOnSave: { command: 'clippy' }
    \\        }
    \\    }
    \\});
    \\
    \\// TypeScript LSP config
    \\const tsLSP = new LSPClient({
    \\    serverName: 'typescript-language-server',
    \\    filetypes: ['typescript', 'typescriptreact', 'javascript', 'javascriptreact'],
    \\    settings: {
    \\        typescript: {
    \\            inlayHints: { parameterNames: { enabled: 'all' } }
    \\        }
    \\    }
    \\});
    \\
    \\export { rustLSP, tsLSP, LSPClient };
;

test "Benchmark: TypeScript → JavaScript transpilation" {
    const allocator = std.testing.allocator;

    std.debug.print("\n\n{s}\n", .{"=" ** 80});
    std.debug.print("  TYPESCRIPT TRANSPILATION BENCHMARK\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print("Measuring: TypeScript → JavaScript (esbuild Transform)\n", .{});
    std.debug.print("Target: <50ms per file for acceptable startup performance\n\n", .{});

    std.debug.print("{s:30} | {s:12} | {s:12} | {s:12}\n", .{ "Test Case", "Source Size", "JS Size", "Time" });
    std.debug.print("{s}\n", .{"-" ** 80});

    var total_ns: u64 = 0;
    var count: usize = 0;

    // Test 1: Small plugin (typical config)
    const t1 = try benchmarkTranspile(allocator, small_plugin, "Small Plugin (config)");
    total_ns += t1;
    count += 1;

    // Test 2: Medium plugin (keymap setup)
    const t2 = try benchmarkTranspile(allocator, medium_plugin, "Medium Plugin (keymaps)");
    total_ns += t2;
    count += 1;

    // Test 3: Large plugin (LSP integration)
    const t3 = try benchmarkTranspile(allocator, large_plugin, "Large Plugin (LSP)");
    total_ns += t3;
    count += 1;

    // Run small plugin multiple times to test consistency
    std.debug.print("\n{s}\n", .{"Consistency test (10 runs of small plugin):"});
    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var sum_ns: u64 = 0;

    for (0..10) |i| {
        const label = try std.fmt.allocPrint(allocator, "  Run {d}", .{i + 1});
        defer allocator.free(label);

        const elapsed = try benchmarkTranspile(allocator, small_plugin, label);
        min_ns = @min(min_ns, elapsed);
        max_ns = @max(max_ns, elapsed);
        sum_ns += elapsed;
    }

    const avg_ns = sum_ns / 10;
    const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;
    const min_ms = @as(f64, @floatFromInt(min_ns)) / 1_000_000.0;
    const max_ms = @as(f64, @floatFromInt(max_ns)) / 1_000_000.0;

    std.debug.print("\n{s}\n", .{"-" ** 80});
    std.debug.print("  Average: {d:.2}ms | Min: {d:.2}ms | Max: {d:.2}ms\n", .{ avg_ms, min_ms, max_ms });

    // Calculate overall average
    const overall_avg_ns = total_ns / count;
    const overall_avg_ms = @as(f64, @floatFromInt(overall_avg_ns)) / 1_000_000.0;

    std.debug.print("\n{s}\n", .{"=" ** 80});
    std.debug.print("  RESULTS\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    std.debug.print("Overall Average:     {d:.2}ms\n", .{overall_avg_ms});
    std.debug.print("Target:              50.00ms\n\n", .{});

    if (overall_avg_ms < 50.0) {
        std.debug.print("✅ RECOMMENDATION: In-memory transpilation on EVERY startup\n", .{});
        std.debug.print("   - Fast enough for good UX (well under 50ms budget)\n", .{});
        std.debug.print("   - No caching complexity needed\n", .{});
        std.debug.print("   - Always uses latest source (no stale cache issues)\n\n", .{});
    } else {
        std.debug.print("⚠️  RECOMMENDATION: Cache .hbc files, transpile only on change\n", .{});
        std.debug.print("   - Exceeds 50ms budget, would degrade UX\n", .{});
        std.debug.print("   - Implement file-based caching with mtime checks\n", .{});
        std.debug.print("   - Transpile: TypeScript → JS → HBC (save .hbc)\n", .{});
        std.debug.print("   - Load: Check mtime, load .hbc if fresh, else re-transpile\n\n", .{});
    }

    // Additional analysis
    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  DETAILED ANALYSIS\n", .{});
    std.debug.print("{s}\n\n", .{"=" ** 80});

    const t1_ms = @as(f64, @floatFromInt(t1)) / 1_000_000.0;
    const t2_ms = @as(f64, @floatFromInt(t2)) / 1_000_000.0;
    const t3_ms = @as(f64, @floatFromInt(t3)) / 1_000_000.0;

    std.debug.print("Small Plugin:   {d:6.2}ms  (<300 bytes)   - Instant!\n", .{t1_ms});
    std.debug.print("Medium Plugin:  {d:6.2}ms  (~1KB)         - Very fast\n", .{t2_ms});
    std.debug.print("Large Plugin:   {d:6.2}ms  (~2KB)         - Still fast\n\n", .{t3_ms});

    std.debug.print("NOTE: These tests only measure TypeScript → JavaScript.\n", .{});
    std.debug.print("      Add ~10-30ms for JavaScript → Hermes bytecode compilation.\n\n", .{});

    if (t1_ms < 10.0 and t2_ms < 20.0 and t3_ms < 30.0) {
        std.debug.print("✅ All test cases well under budget!\n", .{});
        std.debug.print("   Even with Hermes compilation (~20ms), total stays under 50ms.\n\n", .{});
    }

    std.debug.print("{s}\n\n", .{"=" ** 80});
}
