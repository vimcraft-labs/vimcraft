/// Runtime Build Module
/// Transpiles runtime.ts to JavaScript at build time for embedding
///
/// Pipeline: runtime.ts (ES2020) -> esbuild (ES2015) -> @embedFile -> hermesc (runtime) -> HBC
///
/// The JS is embedded at compile time. User config is prepended, then compiled to
/// Hermes bytecode at runtime (allows user config to be part of the same bytecode unit).
const std = @import("std");

/// Runtime transpilation configuration
pub const RuntimeConfig = struct {
    /// Source TypeScript file (relative to project root)
    source_file: []const u8 = "src/system/jsi/runtime.ts",
    /// Output JavaScript file name
    js_output: []const u8 = "runtime.js",
    /// esbuild target - transpile to ES2015 (Hermes's target ECMAScript version)
    target: []const u8 = "es2015",
};

/// Generate runtime JavaScript from TypeScript at build time
/// Uses esbuild CLI (requires Node.js with npx)
pub fn transpileRuntimeTs(b: *std.Build, config: RuntimeConfig) std.Build.LazyPath {
    // esbuild flags:
    // --bundle: Include all imports in output
    // --format=cjs: CommonJS output (Hermes compatible)
    // --target: ES2015 (Hermes's target ECMAScript version)
    // --platform=neutral: Not Node.js or browser specific
    const esbuild_step = b.addSystemCommand(&.{
        "npx",
        "esbuild",
    });
    esbuild_step.addFileArg(b.path(config.source_file));
    esbuild_step.addArgs(&.{
        "--bundle",
        "--format=cjs",
        b.fmt("--target={s}", .{config.target}),
        "--platform=neutral",
    });

    // Capture stdout as the transpiled JavaScript
    const wf = b.addWriteFiles();
    return wf.addCopyFile(esbuild_step.captureStdOut(), config.js_output);
}

/// Build runtime JavaScript (entry point)
pub fn buildRuntimeJs(b: *std.Build) std.Build.LazyPath {
    return transpileRuntimeTs(b, .{});
}

/// Add runtime JavaScript as an anonymous import to a module
/// The JavaScript can then be accessed via @embedFile("runtime_js")
pub fn addRuntimeJs(
    module: *std.Build.Module,
    runtime_js: std.Build.LazyPath,
) void {
    module.addAnonymousImport("runtime_js", .{
        .root_source_file = runtime_js,
    });
}

/// Add runtime JavaScript build dependency to a step
pub fn addRuntimeJsDependency(
    step: *std.Build.Step,
    runtime_js: std.Build.LazyPath,
) void {
    runtime_js.addStepDependencies(step);
}
