const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================================
    // Unicode Support: Ghostty's uucode library
    // ============================================================================
    // Load uucode dependency for production-quality Unicode width calculations
    // Uses East Asian Width property (UAX #11) + grapheme boundary detection
    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .@"build_config.zig" =
            \\const config = @import("config.zig");
            \\const d = config.default;
            \\pub const tables = [_]config.Table{
            \\    .{
            \\        .fields = &.{
            \\            d.field("east_asian_width"),
            \\            d.field("grapheme_break"),
            \\            d.field("is_emoji_modifier"),
            \\            d.field("is_emoji_modifier_base"),
            \\        },
            \\    },
            \\};
        ,
    });
    const uucode_module = uucode_dep.module("uucode");

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
    // Main OpenVim executable
    // ============================================================================
    const exe = b.addExecutable(.{
        .name = "openvim",
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

    // Add C++ source files for Hermes+JSI wrapper
    exe.addCSourceFile(.{
        .file = b.path("src/jsi/hermes_c_api.cpp"),
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
    exe.addCSourceFile(.{
        .file = b.path("src/debug/websocket_server.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    exe.addCSourceFile(.{
        .file = b.path("src/debug/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes dynamic library (includes CDP debugger support)
    // The libhermes_lean.dylib contains all Hermes runtime + CDP API
    // Note: addLibraryPath automatically sets rpath for dynamic library loading
    exe.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    exe.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    exe.linkSystemLibrary("hermes_lean");
    exe.linkSystemLibrary("jsi");

    // ============================================================================
    // libuv (Event Loop & Async I/O)
    // ============================================================================
    exe.addIncludePath(b.path("vendor/libuv/include"));
    exe.addLibraryPath(b.path("vendor/libuv/build"));
    exe.linkSystemLibrary("uv");

    b.installArtifact(exe);

    // ============================================================================
    // ovdb (OpenVim Debugger) - Debug Client Tool
    // ============================================================================
    const ovdb = b.addExecutable(.{
        .name = "ovdb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/ovdb/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Provide unified debug module to ovdb
    ovdb.root_module.addAnonymousImport("debug", .{
        .root_source_file = b.path("src/debug.zig"),
    });

    b.installArtifact(ovdb);

    // ============================================================================
    // Run command
    // ============================================================================
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run OpenVim");
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

    // Add C++ source files for tests
    unit_tests.addCSourceFile(.{
        .file = b.path("src/jsi/hermes_c_api.cpp"),
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
        .file = b.path("src/debug/websocket_server.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    unit_tests.addCSourceFile(.{
        .file = b.path("src/debug/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes for tests (addLibraryPath handles rpath automatically)
    unit_tests.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));

    // libuv for tests
    unit_tests.addIncludePath(b.path("vendor/libuv/include"));
    unit_tests.addLibraryPath(b.path("vendor/libuv/build"));
    unit_tests.linkSystemLibrary("uv");
    unit_tests.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    unit_tests.linkSystemLibrary("hermes_lean");
    unit_tests.linkSystemLibrary("jsi");

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
    // JavaScript configuration is loaded from ~/.config/openvim/init.js
}
