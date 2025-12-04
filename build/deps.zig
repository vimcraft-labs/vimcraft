/// Build Dependencies Module
/// Centralizes all external dependency configuration (Hermes, libuv, tree-sitter, etc.)
const std = @import("std");

/// Common dependency configuration shared across executables
pub const DepsConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    is_linux: bool,
    cdp_flags: []const []const u8,
    enry_lib_path: []const u8,
    esbuild_dylib_filename: []const u8,
};

/// Initialize dependency configuration based on target
pub fn initConfig(_: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) DepsConfig {
    const is_linux = target.result.os.tag == .linux;

    // CDP debugger flags (OpenSSL headers on Linux)
    const cdp_flags = if (is_linux)
        &[_][]const u8{ "-std=c++17", "-fno-sanitize=all", "-isystem", "/usr/include", "-isystem", "/usr/include/x86_64-linux-gnu" }
    else
        &[_][]const u8{ "-std=c++17", "-fno-sanitize=all" };

    // Platform-specific go-enry library path
    const enry_lib_path = if (target.result.os.tag == .linux)
        "vendor/go-enry/.shared/linux"
    else if (target.result.os.tag == .windows)
        "vendor/go-enry/.shared/windows"
    else
        "vendor/go-enry/.shared/darwin";

    // Platform-specific esbuild library filename
    const esbuild_dylib_filename = getEsbuildFilename(target);

    return .{
        .target = target,
        .optimize = optimize,
        .is_linux = is_linux,
        .cdp_flags = cdp_flags,
        .enry_lib_path = enry_lib_path,
        .esbuild_dylib_filename = esbuild_dylib_filename,
    };
}

fn getEsbuildFilename(target: std.Build.ResolvedTarget) []const u8 {
    const os_tag = target.result.os.tag;
    const arch = target.result.cpu.arch;

    if (os_tag == .macos) {
        if (arch == .aarch64) return "libesbuild_darwin_arm64.dylib";
        if (arch == .x86_64) return "libesbuild_darwin_x86_64.dylib";
    } else if (os_tag == .linux) {
        if (arch == .x86_64) return "libesbuild_linux_x86_64.so";
        if (arch == .aarch64) return "libesbuild_linux_aarch64.so";
    } else if (os_tag == .windows) {
        if (arch == .x86_64) return "libesbuild_windows_x86_64.dll";
    }

    @panic("Unsupported platform for esbuild");
}

// ============================================================================
// Hermes + JSI
// ============================================================================

/// Add Hermes C++ source files to a compile step
pub fn addHermesCppSources(b: *std.Build, step: *std.Build.Step.Compile, config: DepsConfig) void {
    // JSI wrapper
    step.addCSourceFile(.{
        .file = b.path("src/system/jsi/hermes_c_api.cpp"),
        .flags = &[_][]const u8{ "-std=c++17", "-fno-sanitize=all" },
    });

    // JSI implementation
    step.addCSourceFile(.{
        .file = b.path("vendor/hermes/API/jsi/jsi/jsi.cpp"),
        .flags = &[_][]const u8{ "-std=c++17", "-fno-sanitize=all" },
    });

    // CDP debugger
    step.addCSourceFile(.{
        .file = b.path("src/backends/headless/websocket_server.cpp"),
        .flags = config.cdp_flags,
    });

    step.addCSourceFile(.{
        .file = b.path("src/backends/headless/cdp_debugger.cpp"),
        .flags = &[_][]const u8{ "-std=c++17", "-fno-sanitize=all" },
    });
}

/// Add Hermes include paths
pub fn addHermesIncludePaths(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.addIncludePath(b.path("src"));
    step.addIncludePath(b.path("vendor/hermes/API"));
    step.addIncludePath(b.path("vendor/hermes/API/jsi"));
    step.addIncludePath(b.path("vendor/hermes/public"));
}

/// Link Hermes libraries
pub fn linkHermes(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    step.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    step.linkSystemLibrary("hermes_lean");
    step.linkSystemLibrary("jsi");
}

/// Add Hermes RPATH for development
pub fn addHermesRPath(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.addRPath(b.path("vendor/hermes/build/API/hermes"));
    step.addRPath(b.path("vendor/hermes/build/jsi"));
}

// ============================================================================
// libuv
// ============================================================================

pub fn addLibuv(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.addIncludePath(b.path("vendor/libuv/include"));
    step.addObjectFile(b.path("vendor/libuv/build/libuv.a"));
}

// ============================================================================
// libgit2
// ============================================================================

pub fn addLibgit2(b: *std.Build, step: *std.Build.Step.Compile, config: DepsConfig) void {
    step.addIncludePath(b.path("vendor/libgit2/include"));
    step.addObjectFile(b.path("vendor/libgit2/build/libgit2.a"));

    // Platform-specific dependencies
    if (config.target.result.os.tag == .macos) {
        step.linkFramework("Security");
        step.linkFramework("CoreFoundation");
        step.linkSystemLibrary("iconv");
        step.linkSystemLibrary("z");
    } else if (config.is_linux) {
        step.linkSystemLibrary("z");
    }
}

// ============================================================================
// go-enry (Language Detection)
// ============================================================================

pub fn addGoEnry(b: *std.Build, step: *std.Build.Step.Compile, config: DepsConfig) void {
    step.addLibraryPath(b.path(config.enry_lib_path));
    step.linkSystemLibrary("enry");
    step.addRPath(b.path(config.enry_lib_path));
}

// ============================================================================
// esbuild (TypeScript Transpiler)
// ============================================================================

pub fn addEsbuild(b: *std.Build, step: *std.Build.Step.Compile, config: DepsConfig) void {
    // Include path for esbuild C headers
    step.addIncludePath(b.path("vendor/esbuild-wrapper"));

    // Link esbuild library
    const esbuild_source_path = b.fmt("vendor/esbuild-wrapper/{s}", .{config.esbuild_dylib_filename});
    step.addObjectFile(b.path(esbuild_source_path));

    // Copy dylib to output directory
    const esbuild_dest_path = b.fmt("bin/{s}", .{config.esbuild_dylib_filename});
    const install_esbuild_dylib = b.addInstallFile(
        b.path(esbuild_source_path),
        esbuild_dest_path,
    );
    step.step.dependOn(&install_esbuild_dylib.step);

    // Set RPATH for runtime
    if (config.target.result.os.tag == .macos) {
        step.addRPath(.{ .cwd_relative = "@executable_path" });
    } else if (config.target.result.os.tag == .linux) {
        step.addRPath(.{ .cwd_relative = "$ORIGIN" });
    }
}

// ============================================================================
// OpenSSL (Linux only)
// ============================================================================

pub fn addOpenSSL(step: *std.Build.Step.Compile, config: DepsConfig) void {
    if (!config.is_linux) return;

    const lib_dir = switch (config.target.result.cpu.arch) {
        .x86_64 => "/usr/lib/x86_64-linux-gnu",
        .aarch64 => "/usr/lib/aarch64-linux-gnu",
        else => "/usr/lib",
    };
    step.addLibraryPath(.{ .cwd_relative = lib_dir });

    // Link order matters: libraries that USE symbols come BEFORE libraries that PROVIDE them
    step.linkSystemLibrary("ssl");
    step.linkSystemLibrary("crypto");
    step.linkSystemLibrary("pthread");
    step.linkSystemLibrary("dl");
}

// ============================================================================
// LMDB (Lightning Memory-Mapped Database) - AI Storage NoSQL backend
// ============================================================================

/// Compile and link LMDB (pure C library)
pub fn addLmdb(b: *std.Build, step: *std.Build.Step.Compile, config: DepsConfig) void {
    // Include path
    step.addIncludePath(b.path("vendor/lmdb/libraries/liblmdb"));

    // Compile LMDB sources (pure C)
    // Note: MDB_USE_ROBUST requires PTHREAD_MUTEX_ROBUST which is Linux-only
    // Must explicitly disable on macOS (MDB_USE_ROBUST=0) to prevent auto-detection
    const lmdb_flags = if (config.is_linux)
        &[_][]const u8{ "-DMDB_USE_POSIX_MUTEX", "-DMDB_USE_ROBUST=1" }
    else
        &[_][]const u8{ "-DMDB_USE_POSIX_MUTEX", "-DMDB_USE_ROBUST=0" };

    step.addCSourceFiles(.{
        .root = b.path("vendor/lmdb/libraries/liblmdb"),
        .files = &.{
            "mdb.c",
            "midl.c",
        },
        .flags = lmdb_flags,
    });

    // Link pthread for LMDB's locking
    step.linkSystemLibrary("pthread");
}

// ============================================================================
// usearch (Vector Similarity Search) - AI Storage vector backend
// ============================================================================

/// Compile and link usearch (C++ library with C API wrapper)
pub fn addUsearch(b: *std.Build, step: *std.Build.Step.Compile) void {
    // Include paths for C and C++ headers
    step.addIncludePath(b.path("vendor/usearch/c"));
    step.addIncludePath(b.path("vendor/usearch/include"));

    // Compile usearch C++ wrapper (requires C++17)
    step.addCSourceFile(.{
        .file = b.path("vendor/usearch/c/lib.cpp"),
        .flags = &.{
            "-std=c++17",
            "-fno-sanitize=all",
            "-DUSEARCH_USE_OPENMP=0",
            "-DUSEARCH_USE_FP16LIB=0",
            "-DUSEARCH_USE_SIMSIMD=0",
        },
    });

    // Link C++ standard library
    step.linkLibCpp();
}
