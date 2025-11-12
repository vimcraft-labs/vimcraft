const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Option to use static Hermes linking (for release builds)
    const use_static_hermes = b.option(bool, "static-hermes", "Link Hermes statically for portable binaries") orelse false;

    // ============================================================================
    // Unicode Support: Ghostty's uucode library + grapheme module
    // ============================================================================
    // Load uucode dependency for production-quality Unicode width calculations
    // Uses East Asian Width property (UAX #11) + grapheme boundary detection
    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .@"build_config.zig" =
            \\const config = @import("config.zig");
            \\const config_x = @import("config.x.zig");
            \\const d = config.default;
            \\const wcwidth = config_x.wcwidth;
            \\
            \\fn computeWidth(
            \\    alloc: @import("std").mem.Allocator,
            \\    cp: u21,
            \\    data: anytype,
            \\    backing: anytype,
            \\    tracking: anytype,
            \\) @import("std").mem.Allocator.Error!void {
            \\    _ = alloc;
            \\    _ = cp;
            \\    _ = backing;
            \\    _ = tracking;
            \\    data.width = @intCast(@min(2, @max(0, data.wcwidth)));
            \\}
            \\
            \\const width = config.Extension{
            \\    .inputs = &.{"wcwidth"},
            \\    .compute = &computeWidth,
            \\    .fields = &.{
            \\        .{ .name = "width", .type = u2 },
            \\    },
            \\};
            \\
            \\pub const tables = [_]config.Table{
            \\    .{
            \\        .extensions = &.{ wcwidth, width },
            \\        .fields = &.{
            \\            width.field("width"),
            \\            d.field("grapheme_break"),
            \\            d.field("is_emoji"),
            \\            d.field("is_emoji_presentation"),
            \\            d.field("is_emoji_modifier"),
            \\            d.field("is_emoji_modifier_base"),
            \\        },
            \\    },
            \\};
        ,
    });
    const uucode_module = uucode_dep.module("uucode");

    // ============================================================================
    // Ghostty Unicode Tables Generation
    // ============================================================================
    // Generate unicode property tables at build time using Ghostty's table generator
    // This provides grapheme cluster boundary detection (emoji, ZWJ, modifiers, etc.)
    const unicode_tables = blk: {
        // Build tools need a native version of uucode
        const uucode_native = b.dependency("uucode", .{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .@"build_config.zig" =
                \\const config = @import("config.zig");
                \\const config_x = @import("config.x.zig");
                \\const d = config.default;
                \\const wcwidth = config_x.wcwidth;
                \\
                \\fn computeWidth(
                \\    alloc: @import("std").mem.Allocator,
                \\    cp: u21,
                \\    data: anytype,
                \\    backing: anytype,
                \\    tracking: anytype,
                \\) @import("std").mem.Allocator.Error!void {
                \\    _ = alloc;
                \\    _ = cp;
                \\    _ = backing;
                \\    _ = tracking;
                \\    data.width = @intCast(@min(2, @max(0, data.wcwidth)));
                \\}
                \\
                \\const width = config.Extension{
                \\    .inputs = &.{"wcwidth"},
                \\    .compute = &computeWidth,
                \\    .fields = &.{
                \\        .{ .name = "width", .type = u2 },
                \\    },
                \\};
                \\
                \\pub const tables = [_]config.Table{
                \\    .{
                \\        .extensions = &.{ wcwidth, width },
                \\        .fields = &.{
                \\            width.field("width"),
                \\            d.field("grapheme_break"),
                \\            d.field("is_emoji"),
                \\            d.field("is_emoji_presentation"),
                \\            d.field("is_emoji_modifier"),
                \\            d.field("is_emoji_modifier_base"),
                \\        },
                \\    },
                \\};
            ,
        });

        // Create executable to generate unicode property tables
        const props_exe = b.addExecutable(.{
            .name = "props-unigen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("vendor/ghostty/src/unicode/props_uucode.zig"),
                .target = b.graph.host,
                .optimize = .ReleaseFast, // Match uucode_native optimization
            }),
        });

        // Add native uucode dependency to the generator
        props_exe.root_module.addImport("uucode", uucode_native.module("uucode"));

        // Add lut.zig and Properties.zig from Ghostty
        props_exe.root_module.addAnonymousImport("lut.zig", .{
            .root_source_file = b.path("vendor/ghostty/src/unicode/lut.zig"),
        });
        props_exe.root_module.addAnonymousImport("Properties.zig", .{
            .root_source_file = b.path("vendor/ghostty/src/unicode/Properties.zig"),
        });

        // Run the generator and capture output
        const props_run = b.addRunArtifact(props_exe);
        const wf = b.addWriteFiles();
        const props_output = wf.addCopyFile(props_run.captureStdOut(), "unicode_props.zig");

        break :blk props_output;
    };

    // ============================================================================
    // C Library: libvterm (from Neovim) - DEFERRED
    // ============================================================================
    // NOTE: libvterm has dependencies on many Neovim internal headers
    // (grid.h, math.h, ascii_defs.h, auto/config.h, etc.)
    // It's tightly coupled to Neovim and cannot be easily extracted.
    //
    // For Phase 1+2 (text display + navigation), we don't need libvterm.
    // We're using raw ANSI escape codes for terminal control, which is sufficient.
    //
    // libvterm will be needed later for implementing :terminal command.
    // At that point, we can either:
    //   1. Use standalone libvterm from https://www.leonerd.org.uk/code/libvterm/
    //   2. Build full Neovim and link against its libvterm
    //   3. Implement minimal terminal emulation ourselves
    //
    // For now, skip it.

    // ============================================================================
    // Hermes+JSI Integration (C++ Object Files)
    // ============================================================================
    // In Zig 0.15.2, we compile C++ sources directly into the executable
    // rather than creating a separate static library

    // ============================================================================
    // Main Vimcraft executable
    // ============================================================================
    const exe = b.addExecutable(.{
        .name = "vc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link C and C++
    exe.linkLibC();
    exe.linkLibCpp(); // Required for Hermes C++ runtime

    // Ghostty components (referenced directly from submodule)
    exe.addIncludePath(b.path("vendor/ghostty/src"));

    // Hermes include paths (for Zig @cImport)
    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(b.path("vendor/hermes/API"));
    exe.addIncludePath(b.path("vendor/hermes/API/jsi"));
    exe.addIncludePath(b.path("vendor/hermes/public"));

    // Add uucode module for Unicode width calculations
    exe.root_module.addImport("uucode", uucode_module);

    // Add animation module
    const animation_module = b.createModule(.{
        .root_source_file = b.path("src/animation.zig"),
    });
    exe.root_module.addImport("animation", animation_module);

    // Add unicode_tables import for grapheme cluster detection
    unicode_tables.addStepDependencies(&exe.step);
    exe.root_module.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });

    // Add Ghostty's grapheme module with its dependencies
    const ghostty_unicode_path = "vendor/ghostty/src/unicode";

    // Create a single shared Properties module
    const properties_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/Properties.zig"),
    });

    // Create lut module (standalone)
    const lut_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/lut.zig"),
    });

    // Create props_table module with all its deps
    const props_table_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/props_table.zig"),
    });
    props_table_mod.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });
    props_table_mod.addImport("lut.zig", lut_mod);
    props_table_mod.addImport("Properties.zig", properties_mod);

    // Create grapheme module that imports props_table and Properties
    const ghostty_grapheme_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/grapheme.zig"),
    });
    ghostty_grapheme_mod.addImport("props_table.zig", props_table_mod);
    ghostty_grapheme_mod.addImport("Properties.zig", properties_mod);

    exe.root_module.addImport("ghostty_grapheme", ghostty_grapheme_mod);

    // Add C++ source files for Hermes+JSI wrapper
    exe.addCSourceFile(.{
        .file = b.path("src/system/jsi/hermes_c_api.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    exe.addCSourceFile(.{
        .file = b.path("vendor/hermes/API/jsi/jsi/jsi.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Add CDP debugger C++ files
    // On Linux, add OpenSSL headers via -isystem (lower priority than Zig's bundled headers)
    // Need both /usr/include and architecture-specific directory for OpenSSL headers
    const cdp_flags = if (target.result.os.tag == .linux)
        &[_][]const u8{ "-std=c++17", "-fno-sanitize=all", "-isystem", "/usr/include", "-isystem", "/usr/include/x86_64-linux-gnu" }
    else
        &[_][]const u8{ "-std=c++17", "-fno-sanitize=all" };

    exe.addCSourceFile(.{
        .file = b.path("src/backends/debug/websocket_server.cpp"),
        .flags = cdp_flags,
    });

    exe.addCSourceFile(.{
        .file = b.path("src/backends/debug/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes (conditional: static for releases, dynamic for local dev)
    if (use_static_hermes) {
        // Static linking for portable release binaries (no dylib dependencies)
        // Note: Hermes produces static libraries in lib/VM/ subdirectory
        exe.addObjectFile(b.path("vendor/hermes/build/lib/VM/libhermesVMRuntimeLean.a"));
        // JSI can be either static .a or shared .dylib depending on CMake flags
        // Try static first, fall back to shared if needed
        const jsi_static = b.path("vendor/hermes/build/jsi/libjsi.a");
        exe.addObjectFile(jsi_static);
    } else {
        // Dynamic linking for local development
        exe.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
        exe.addLibraryPath(b.path("vendor/hermes/build/jsi"));
        exe.linkSystemLibrary("hermes_lean");
        exe.linkSystemLibrary("jsi");
    }

    // ============================================================================
    // libuv (Event Loop & Async I/O)
    // ============================================================================
    exe.addIncludePath(b.path("vendor/libuv/include"));
    // Link directly to our vendored libuv to avoid Homebrew conflicts
    // On macOS, we build universal binaries (arm64 + x86_64) for cross-compilation
    exe.addObjectFile(b.path("vendor/libuv/build/libuv.a"));

    // ============================================================================
    // OpenSSL (Linux only - for WebSocket SHA1 hashing)
    // ============================================================================
    // macOS uses CommonCrypto, Linux uses OpenSSL
    // Link pthread/dl for ALL Linux builds (not just native - CI uses explicit targets)
    const is_linux = target.result.os.tag == .linux;

    if (is_linux) {
        // Add system library path for OpenSSL (required when using addLibraryPath)
        // Ubuntu/Debian: /usr/lib/x86_64-linux-gnu or /usr/lib/aarch64-linux-gnu
        const lib_dir = switch (target.result.cpu.arch) {
            .x86_64 => "/usr/lib/x86_64-linux-gnu",
            .aarch64 => "/usr/lib/aarch64-linux-gnu",
            else => "/usr/lib",
        };
        exe.addLibraryPath(.{ .cwd_relative = lib_dir });

        // Link OpenSSL first, then pthread/dl (ssl/crypto/uv all depend on pthread/dl)
        // Unix linker order: libraries that USE symbols come BEFORE libraries that PROVIDE them
        exe.linkSystemLibrary("ssl");
        exe.linkSystemLibrary("crypto");

        // pthread and dl must come LAST (after all libraries that depend on them)
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
    }

    b.installArtifact(exe);

    // ============================================================================
    // debug-grid - Grid Layout Debugging Tool
    // ============================================================================
    // TODO: Fix module imports - temporarily disabled
    // const debug_grid = b.addExecutable(.{
    //     .name = "debug-grid",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("tools/debug_grid.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //     }),
    // });

    // // Add uucode module for width calculations
    // debug_grid.root_module.addImport("uucode", uucode_module);

    // // Provide screen_grid module as an anonymous import
    // // Note: screen_grid.zig imports char_width.zig internally, so we need to ensure
    // // the import context allows relative file imports within src/display/
    // debug_grid.root_module.addAnonymousImport("screen_grid", .{
    //     .root_source_file = b.path("src/display/screen_grid.zig"),
    //     .imports = &.{
    //         .{ .name = "uucode", .module = uucode_module },
    //     },
    // });

    // b.installArtifact(debug_grid);

    // ============================================================================
    // Benchmark Suite
    // ============================================================================
    // Create a module for benchmark that can access all vimcraft modules
    const bench_root_module = b.createModule(.{
        .root_source_file = b.path("src/tools/benchmark/main.zig"),
        .target = target,
        .optimize = .ReleaseFast, // Use optimized build for benchmarks
    });

    // Add vimcraft modules as imports (with uucode dependency)
    const vimcraft_module_for_bench = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
    });
    vimcraft_module_for_bench.addImport("uucode", uucode_module);

    bench_root_module.addImport("vimcraft", vimcraft_module_for_bench);

    const bench = b.addExecutable(.{
        .name = "vc-bench",
        .root_module = bench_root_module,
    });

    // Link C and C++ for Hermes
    bench.linkLibC();
    bench.linkLibCpp();

    // Ghostty components
    bench.addIncludePath(b.path("vendor/ghostty/src"));

    // Hermes include paths
    bench.addIncludePath(b.path("src"));
    bench.addIncludePath(b.path("vendor/hermes/API"));
    bench.addIncludePath(b.path("vendor/hermes/API/jsi"));
    bench.addIncludePath(b.path("vendor/hermes/public"));

    // Add uucode module
    bench.root_module.addImport("uucode", uucode_module);

    // Add C++ source files
    bench.addCSourceFile(.{
        .file = b.path("src/system/jsi/hermes_c_api.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    bench.addCSourceFile(.{
        .file = b.path("vendor/hermes/API/jsi/jsi/jsi.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    bench.addCSourceFile(.{
        .file = b.path("src/backends/debug/websocket_server.cpp"),
        .flags = cdp_flags,
    });

    bench.addCSourceFile(.{
        .file = b.path("src/backends/debug/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes (conditional: static for releases, dynamic for local dev)
    if (use_static_hermes) {
        bench.addObjectFile(b.path("vendor/hermes/build/lib/VM/libhermesVMRuntimeLean.a"));
        bench.addObjectFile(b.path("vendor/hermes/build/jsi/libjsi.a"));
    } else {
        bench.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
        bench.addLibraryPath(b.path("vendor/hermes/build/jsi"));
        bench.linkSystemLibrary("hermes_lean");
        bench.linkSystemLibrary("jsi");
    }

    bench.addIncludePath(b.path("vendor/libuv/include"));
    // Link directly to our vendored libuv to avoid Homebrew conflicts
    bench.addObjectFile(b.path("vendor/libuv/build/libuv.a"));

    // OpenSSL for Linux (WebSocket SHA1 hashing) - all Linux builds
    if (is_linux) {
        const lib_dir = switch (target.result.cpu.arch) {
            .x86_64 => "/usr/lib/x86_64-linux-gnu",
            .aarch64 => "/usr/lib/aarch64-linux-gnu",
            else => "/usr/lib",
        };
        bench.addLibraryPath(.{ .cwd_relative = lib_dir });

        // Link OpenSSL first, then pthread/dl (ssl/crypto/uv all depend on pthread/dl)
        // Unix linker order: libraries that USE symbols come BEFORE libraries that PROVIDE them
        bench.linkSystemLibrary("ssl");
        bench.linkSystemLibrary("crypto");

        // pthread and dl must come LAST (after all libraries that depend on them)
        bench.linkSystemLibrary("pthread");
        bench.linkSystemLibrary("dl");
    }

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

    unit_tests.linkLibC();
    unit_tests.linkLibCpp();

    unit_tests.addIncludePath(b.path("vendor/ghostty/src"));

    // Hermes include paths for tests
    unit_tests.addIncludePath(b.path("src"));
    unit_tests.addIncludePath(b.path("vendor/hermes/API"));
    unit_tests.addIncludePath(b.path("vendor/hermes/API/jsi"));
    unit_tests.addIncludePath(b.path("vendor/hermes/public"));

    // Add uucode module for tests
    unit_tests.root_module.addImport("uucode", uucode_module);

    // Add animation module for tests
    unit_tests.root_module.addImport("animation", animation_module);

    // Add unicode_tables import for tests
    unicode_tables.addStepDependencies(&unit_tests.step);
    unit_tests.root_module.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });

    // Add ghostty_grapheme module for tests (same as main exe)
    unit_tests.root_module.addImport("ghostty_grapheme", ghostty_grapheme_mod);

    // Add C++ source files for tests
    unit_tests.addCSourceFile(.{
        .file = b.path("src/system/jsi/hermes_c_api.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/hermes/API/jsi/jsi/jsi.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    unit_tests.addCSourceFile(.{
        .file = b.path("src/backends/debug/websocket_server.cpp"),
        .flags = cdp_flags,
    });

    unit_tests.addCSourceFile(.{
        .file = b.path("src/backends/debug/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes for tests (conditional: static for releases, dynamic for local dev)
    if (use_static_hermes) {
        unit_tests.addObjectFile(b.path("vendor/hermes/build/lib/VM/libhermesVMRuntimeLean.a"));
        unit_tests.addObjectFile(b.path("vendor/hermes/build/jsi/libjsi.a"));
    } else {
        unit_tests.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
        unit_tests.addLibraryPath(b.path("vendor/hermes/build/jsi"));
        unit_tests.linkSystemLibrary("hermes_lean");
        unit_tests.linkSystemLibrary("jsi");
    }

    // libuv for tests
    unit_tests.addIncludePath(b.path("vendor/libuv/include"));
    // Link directly to our vendored libuv to avoid Homebrew conflicts
    unit_tests.addObjectFile(b.path("vendor/libuv/build/libuv.a"));

    // OpenSSL for Linux (WebSocket SHA1 hashing) - all Linux builds
    if (is_linux) {
        const lib_dir = switch (target.result.cpu.arch) {
            .x86_64 => "/usr/lib/x86_64-linux-gnu",
            .aarch64 => "/usr/lib/aarch64-linux-gnu",
            else => "/usr/lib",
        };
        unit_tests.addLibraryPath(.{ .cwd_relative = lib_dir });

        // Link OpenSSL first, then pthread/dl (ssl/crypto/uv all depend on pthread/dl)
        // Unix linker order: libraries that USE symbols come BEFORE libraries that PROVIDE them
        unit_tests.linkSystemLibrary("ssl");
        unit_tests.linkSystemLibrary("crypto");

        // pthread and dl must come LAST (after all libraries that depend on them)
        unit_tests.linkSystemLibrary("pthread");
        unit_tests.linkSystemLibrary("dl");
    }

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ============================================================================
    // NOTE: Hermes+JSI Integration
    // ============================================================================
    // Hermes is now fully integrated into the main build system!
    //
    // The previous Makefile.hermes workaround is no longer needed for the main
    // executable. It remains available for standalone demos/testing.
    //
    // JavaScript configuration is loaded from ~/.config/vimcraft/init.js
}
