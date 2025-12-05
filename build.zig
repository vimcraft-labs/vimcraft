const std = @import("std");

// Modular build components
const deps = @import("build/deps.zig");
const exe_helpers = @import("build/exe.zig");
const runtime_build = @import("build/runtime.zig");
const unicode = @import("build/unicode.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Initialize dependency configuration
    const config = deps.initConfig(b, target, optimize);

    // ============================================================================
    // Security: /tmp/ Loading Control (TypeScript Transpiler)
    // ============================================================================
    const enable_tmp_loading = b.option(
        bool,
        "enable-tmp-loading",
        "Allow loading TypeScript modules from /tmp/ (testing only, disable in production)",
    ) orelse true;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tmp_loading", enable_tmp_loading);

    // ============================================================================
    // Unicode Support: Ghostty's uucode library + grapheme module
    // ============================================================================
    const uucode_module = unicode.getUucodeModule(b, target, optimize);
    const unicode_tables = unicode.generateUnicodeTables(b);
    const ghostty_grapheme_mod = unicode.createGraphemeModule(b, unicode_tables);

    // Animation module
    const animation_module = exe_helpers.createAnimationModule(b);

    // ============================================================================
    // Runtime.ts -> Runtime.js Transpilation (build-time)
    // ============================================================================
    // Transpile TypeScript runtime to JavaScript for embedding
    // Pipeline: runtime.ts (ES2020) -> esbuild (ES2015) -> hermesc (runtime) -> HBC
    // The generated JS is embedded via @embedFile and wrapped with user config
    // before being compiled to Hermes bytecode at runtime
    const runtime_js = runtime_build.buildRuntimeJs(b);

    // Standard modules shared by all Vimcraft executables
    const vimcraft_modules = exe_helpers.VimcraftModules{
        .uucode = uucode_module,
        .build_options = build_options.createModule(),
        .animation = animation_module,
        .ghostty_grapheme = ghostty_grapheme_mod,
        .unicode_tables = unicode_tables,
        .runtime_js = runtime_js,
    };

    // ============================================================================
    // Main Vimcraft executable
    // ============================================================================
    const exe = b.addExecutable(.{
        .name = "vimc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Configure with all dependencies
    exe_helpers.configureVimcraftStep(b, exe, config);
    exe_helpers.addGhosttyInclude(b, exe);
    exe_helpers.addDevelopmentRPaths(b, exe);
    exe_helpers.addVimcraftImports(exe.root_module, vimcraft_modules);
    exe_helpers.addVimcraftStepDependencies(&exe.step, vimcraft_modules);

    // esbuild (TypeScript Transpiler)
    deps.addEsbuild(b, exe, config);

    b.installArtifact(exe);

    // ============================================================================
    // Benchmark Suite
    // ============================================================================
    const bench_root_module = b.createModule(.{
        .root_source_file = b.path("src/tools/benchmark/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    // Create vimcraft module for benchmark
    const vimcraft_module_for_bench = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    exe_helpers.addVimcraftImports(vimcraft_module_for_bench, vimcraft_modules);

    // Add C include paths to vimcraft module for @cImport
    addVimcraftModuleIncludes(b, vimcraft_module_for_bench);

    bench_root_module.addImport("vimcraft", vimcraft_module_for_bench);

    const bench = b.addExecutable(.{
        .name = "vimc-bench",
        .root_module = bench_root_module,
    });

    // Configure with all dependencies
    exe_helpers.configureVimcraftStep(b, bench, config);
    exe_helpers.addGhosttyInclude(b, bench);
    bench.root_module.addImport("uucode", uucode_module);
    exe_helpers.addVimcraftStepDependencies(&bench.step, vimcraft_modules);

    b.installArtifact(bench);

    const run_bench = b.addRunArtifact(bench);
    run_bench.step.dependOn(b.getInstallStep());

    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);

    // ============================================================================
    // Run command
    // ============================================================================
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Vimcraft");
    run_step.dependOn(&run_cmd.step);

    // ============================================================================
    // Tests
    // ============================================================================
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Configure with all dependencies
    exe_helpers.configureVimcraftStep(b, unit_tests, config);
    exe_helpers.addGhosttyInclude(b, unit_tests);
    exe_helpers.addVimcraftImports(unit_tests.root_module, vimcraft_modules);
    exe_helpers.addVimcraftStepDependencies(&unit_tests.step, vimcraft_modules);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ============================================================================
    // JSI HostObject Performance Benchmark
    // ============================================================================
    const jsi_bench = b.addExecutable(.{
        .name = "jsi-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/jsi_bench_main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    // Configure with all dependencies
    exe_helpers.configureVimcraftStep(b, jsi_bench, config);
    exe_helpers.addGhosttyInclude(b, jsi_bench);
    exe_helpers.addDevelopmentRPaths(b, jsi_bench);
    exe_helpers.addVimcraftImports(jsi_bench.root_module, vimcraft_modules);
    exe_helpers.addVimcraftStepDependencies(&jsi_bench.step, vimcraft_modules);

    b.installArtifact(jsi_bench);

    const run_jsi_bench = b.addRunArtifact(jsi_bench);
    run_jsi_bench.step.dependOn(b.getInstallStep());

    const jsi_bench_step = b.step("jsi-bench", "Run JSI HostObject performance benchmark");
    jsi_bench_step.dependOn(&run_jsi_bench.step);

}

/// Add C include paths to a module for @cImport to work
fn addVimcraftModuleIncludes(b: *std.Build, module: *std.Build.Module) void {
    module.addIncludePath(b.path("vendor/ghostty/src"));
    module.addIncludePath(b.path("src"));
    module.addIncludePath(b.path("vendor/hermes/API"));
    module.addIncludePath(b.path("vendor/hermes/API/jsi"));
    module.addIncludePath(b.path("vendor/hermes/public"));
    module.addIncludePath(b.path("vendor/libuv/include"));
    module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    module.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Tree-sitter language parser include paths
    module.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    module.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    module.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    module.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    module.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    module.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    module.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));

    // POSIX macros
    module.addCMacro("_POSIX_C_SOURCE", "200112L");
    module.addCMacro("_DEFAULT_SOURCE", "");
    module.addCMacro("_DARWIN_C_SOURCE", "");
}
