/// Executable Build Module
/// Helper functions for configuring Vimcraft executables
const std = @import("std");
const deps = @import("deps.zig");
const tree_sitter = @import("tree_sitter.zig");
const unicode = @import("unicode.zig");
const runtime_build = @import("runtime.zig");

/// Configure a compile step with all Vimcraft dependencies
/// This is the standard configuration for main exe, tests, and benchmarks
pub fn configureVimcraftStep(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    config: deps.DepsConfig,
) void {
    // Link C and C++ (required for Hermes)
    step.linkLibC();
    step.linkLibCpp();

    // Add all dependencies
    deps.addHermesIncludePaths(b, step);
    deps.addHermesCppSources(b, step, config);
    deps.linkHermes(b, step);
    deps.addLibuv(b, step);
    deps.addLibgit2(b, step, config);
    deps.addGoEnry(b, step, config);
    deps.addOpenSSL(step, config);

    // AI Storage dependencies
    deps.addLmdb(b, step, config);
    deps.addUsearch(b, step);

    // Add tree-sitter
    tree_sitter.addAll(b, step);
}

/// Configure a compile step with Hermes RPATH for development
pub fn addDevelopmentRPaths(b: *std.Build, step: *std.Build.Step.Compile) void {
    deps.addHermesRPath(b, step);
}

/// Add Ghostty include path
pub fn addGhosttyInclude(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.addIncludePath(b.path("vendor/ghostty/src"));
}

/// Create animation module
pub fn createAnimationModule(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/animation.zig"),
    });
}

/// Standard module imports for Vimcraft executables
pub const VimcraftModules = struct {
    uucode: *std.Build.Module,
    build_options: *std.Build.Module,
    animation: *std.Build.Module,
    ghostty_grapheme: *std.Build.Module,
    unicode_tables: std.Build.LazyPath,
    runtime_js: std.Build.LazyPath,
};

/// Add all standard Vimcraft imports to a module
pub fn addVimcraftImports(module: *std.Build.Module, modules: VimcraftModules) void {
    module.addImport("uucode", modules.uucode);
    module.addImport("build_options", modules.build_options);
    module.addImport("animation", modules.animation);
    module.addImport("ghostty_grapheme", modules.ghostty_grapheme);
    unicode.addUnicodeTables(module, modules.unicode_tables);
    runtime_build.addRuntimeJs(module, modules.runtime_js);
}

/// Add all standard step dependencies for Vimcraft executables
pub fn addVimcraftStepDependencies(step: *std.Build.Step, modules: VimcraftModules) void {
    unicode.addTablesDependency(step, modules.unicode_tables);
    runtime_build.addRuntimeJsDependency(step, modules.runtime_js);
}
