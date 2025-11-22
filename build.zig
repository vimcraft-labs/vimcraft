const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================================
    // Security: /tmp/ Loading Control (TypeScript Transpiler)
    // ============================================================================
    // PRODUCTION: Set to false to disable /tmp/ access (security hardening)
    // DEVELOPMENT: Set to true for testing (allows /tmp/ loading)
    // Default: true (for development convenience)
    const enable_tmp_loading = b.option(
        bool,
        "enable-tmp-loading",
        "Allow loading TypeScript modules from /tmp/ (testing only, disable in production)",
    ) orelse true; // Default: enabled for development

    // Create build options module for transpiler
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tmp_loading", enable_tmp_loading);

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
        .name = "vimc",
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

    // Add build_options module for transpiler security settings
    exe.root_module.addImport("build_options", build_options.createModule());

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
        .file = b.path("src/backends/headless/websocket_server.cpp"),
        .flags = cdp_flags,
    });

    exe.addCSourceFile(.{
        .file = b.path("src/backends/headless/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes dynamically (for both development and releases)
    // Release workflow replaces RPATHs with @executable_path/../lib (macOS) or $ORIGIN/../lib (Linux)
    exe.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    exe.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    exe.linkSystemLibrary("hermes_lean");
    exe.linkSystemLibrary("jsi");

    // Set RPATH to build directories for local development
    // Release workflow will replace these with @executable_path/../lib (macOS) or $ORIGIN/../lib (Linux)
    exe.addRPath(b.path("vendor/hermes/build/API/hermes"));
    exe.addRPath(b.path("vendor/hermes/build/jsi"));

    // ============================================================================
    // go-enry (Language Detection)
    // ============================================================================
    // Link go-enry shared library for filetype detection
    // Provides GitHub Linguist-based language detection (697 languages)
    // Replaces compile-time Neovim mappings with content-based detection
    //
    // Build instructions:
    //   macOS:   ./scripts/build-enry.sh darwin
    //   Linux:   ./scripts/build-enry.sh linux
    //   Windows: ./scripts/build-enry.sh windows
    //
    // Platform-specific library path
    const enry_lib_path = if (target.result.os.tag == .linux)
        "vendor/go-enry/.shared/linux"
    else if (target.result.os.tag == .windows)
        "vendor/go-enry/.shared/windows"
    else
        "vendor/go-enry/.shared/darwin"; // macOS default

    exe.addLibraryPath(b.path(enry_lib_path));
    exe.linkSystemLibrary("enry");

    // Set RPATH for go-enry dynamic library
    exe.addRPath(b.path(enry_lib_path));

    // ============================================================================
    // libuv (Event Loop & Async I/O)
    // ============================================================================
    exe.addIncludePath(b.path("vendor/libuv/include"));
    // Link directly to our vendored libuv to avoid Homebrew conflicts
    // On macOS, we build universal binaries (arm64 + x86_64) for cross-compilation
    exe.addObjectFile(b.path("vendor/libuv/build/libuv.a"));

    // ============================================================================
    // libgit2 (Git Operations)
    // ============================================================================
    // Pure C implementation of Git core methods (v1.9.0)
    // Exposes git functionality to JavaScript plugins via JSI
    // Used by: GitHub, VS Code, GitLab, SourceTree
    //
    // Build instructions:
    //   cd vendor/libgit2
    //   mkdir build && cd build
    //   cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DUSE_SSH=OFF -DBUILD_CLI=OFF
    //   cmake --build .
    //
    // Size: ~2MB static library (vs go-git ~15MB)
    exe.addIncludePath(b.path("vendor/libgit2/include"));
    exe.addObjectFile(b.path("vendor/libgit2/build/libgit2.a"));

    // libgit2 dependencies (platform-specific)
    if (target.result.os.tag == .macos) {
        // macOS: Security.framework for TLS, CoreFoundation for strings
        exe.linkFramework("Security");
        exe.linkFramework("CoreFoundation");
        exe.linkSystemLibrary("iconv");
        exe.linkSystemLibrary("z");
    } else if (target.result.os.tag == .linux) {
        // Linux: OpenSSL for TLS (already linked above for WebSocket)
        exe.linkSystemLibrary("z");
    }

    // ============================================================================
    // esbuild (TypeScript Transpiler) - Phase 4 - CROSS-PLATFORM
    // ============================================================================
    // esbuild Go library compiled to C shared library via -buildmode=c-shared
    // Provides in-process TypeScript→JavaScript transpilation (no child process overhead)
    // Performance: ~100x faster than spawning esbuild binary
    //
    // Build instructions:
    //   cd vendor/esbuild-wrapper
    //   ./build.sh  (requires Go 1.21+, takes 30-60s)
    //
    // Size impact: ~7MB to binary (smaller than standalone esbuild binary)
    //
    // Platform-specific library naming:
    //   macOS arm64:   libesbuild_darwin_arm64.dylib
    //   macOS x86_64:  libesbuild_darwin_x86_64.dylib
    //   Linux x86_64:  libesbuild_linux_x86_64.so
    //   Linux aarch64: libesbuild_linux_aarch64.so
    //   Windows x86_64: libesbuild_windows_x86_64.dll
    const esbuild_dylib_filename = blk: {
        const os_tag = target.result.os.tag;
        const arch = target.result.cpu.arch;

        if (os_tag == .macos) {
            if (arch == .aarch64) {
                break :blk "libesbuild_darwin_arm64.dylib";
            } else if (arch == .x86_64) {
                break :blk "libesbuild_darwin_x86_64.dylib";
            }
        } else if (os_tag == .linux) {
            if (arch == .x86_64) {
                break :blk "libesbuild_linux_x86_64.so";
            } else if (arch == .aarch64) {
                break :blk "libesbuild_linux_aarch64.so";
            }
        } else if (os_tag == .windows) {
            if (arch == .x86_64) {
                break :blk "libesbuild_windows_x86_64.dll";
            }
        }

        @panic("Unsupported platform for esbuild");
    };

    // Add include path for esbuild C headers
    exe.addIncludePath(b.path("vendor/esbuild-wrapper"));

    // Link esbuild library by linking the dylib directly as an object file
    // This avoids addLibraryPath() which automatically adds an unwanted rpath
    // We link from vendor/ at build time, but copy to bin/ and use @executable_path at runtime
    const esbuild_source_path = b.fmt("vendor/esbuild-wrapper/{s}", .{esbuild_dylib_filename});
    exe.addObjectFile(b.path(esbuild_source_path));

    // Copy dylib to output directory (next to executable)
    const esbuild_dest_path = b.fmt("bin/{s}", .{esbuild_dylib_filename});
    const install_esbuild_dylib = b.addInstallFile(
        b.path(esbuild_source_path),
        esbuild_dest_path,
    );
    exe.step.dependOn(&install_esbuild_dylib.step);

    // NOTE: The source dylib's install_name has been fixed to use @rpath/ prefix
    // This allows the @executable_path rpath to work correctly at runtime
    // If you rebuild the esbuild dylib, run:
    //   install_name_tool -id "@rpath/libesbuild_darwin_arm64.dylib" vendor/esbuild-wrapper/libesbuild_darwin_arm64.dylib

    // Set RPATH for runtime library search (platform-specific)
    // Since we're using addObjectFile instead of linkSystemLibrary, no automatic rpath is added
    // macOS: @executable_path (relative to executable)
    // Linux: $ORIGIN (relative to executable)
    // Windows: No rpath needed (searches current directory by default)
    if (target.result.os.tag == .macos) {
        exe.addRPath(.{ .cwd_relative = "@executable_path" });
    } else if (target.result.os.tag == .linux) {
        exe.addRPath(.{ .cwd_relative = "$ORIGIN" });
    }
    // Windows: No rpath configuration needed

    // ============================================================================
    // Tree-sitter (Incremental Syntax Parsing)
    // ============================================================================
    // Tree-sitter core library for parsing and querying syntax trees
    // Provides foundation for Phase 5 (Helix-style syntax highlighting)
    // Uses go-enry for language detection (697 languages) + tree-sitter parsers
    //
    // Architecture:
    // - Core Library: Parsing engine + query system (compiled from C sources)
    // - Language Parsers: Separate repos (tree-sitter-rust, etc.) added later
    // - Query Files: highlights.scm for each language (loaded at runtime)
    exe.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    exe.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Language parser include paths (for tree_sitter/parser.h in each parser)
    exe.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    exe.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    exe.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    exe.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    exe.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    exe.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    exe.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));

    // Add all C source files from tree-sitter lib (excluding lib.c for amalgamated builds)
    exe.addCSourceFiles(.{
        .root = b.path("vendor/tree-sitter/lib/src"),
        .files = &.{
            "alloc.c",
            "get_changed_ranges.c",
            "language.c",
            "lexer.c",
            "node.c",
            "parser.c",
            "point.c",
            "query.c",
            "stack.c",
            "subtree.c",
            "tree_cursor.c",
            "tree.c",
            "wasm_store.c",
        },
        .flags = &.{"-std=c11"},
    });

    // POSIX compatibility macros (required by tree-sitter on Unix-like systems)
    exe.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    exe.root_module.addCMacro("_DEFAULT_SOURCE", "");
    exe.root_module.addCMacro("_DARWIN_C_SOURCE", "");

    // ============================================================================
    // Tree-sitter Language Parsers (Bundled: C, Zig, JS/TS, Markdown)
    // ============================================================================
    // Bundled parsers (7 total from 5 submodules):
    // - C (tree-sitter-c)
    // - Zig (tree-sitter-zig)
    // - JavaScript (tree-sitter-javascript)
    // - TypeScript + TSX (tree-sitter-typescript)
    // - Markdown + Markdown Inline (tree-sitter-markdown)

    // C parser
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-c/src/parser.c"),
        .flags = &.{"-std=c11"},
    });

    // Zig parser
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });

    // JavaScript parser (has external scanner)
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });

    // TypeScript parsers (typescript + tsx, both have scanners)
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });

    // Markdown parsers (markdown + markdown_inline, both have scanners)
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    exe.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });

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
        .target = target,
        .optimize = .ReleaseFast, // Match bench optimization level
    });
    vimcraft_module_for_bench.addImport("uucode", uucode_module);
    vimcraft_module_for_bench.addImport("animation", animation_module);
    vimcraft_module_for_bench.addImport("ghostty_grapheme", ghostty_grapheme_mod);

    // Add unicode_tables for vimcraft module
    vimcraft_module_for_bench.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });

    // CRITICAL: Add C include paths to vimcraft module for @cImport to work
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/ghostty/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/hermes/API"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/hermes/API/jsi"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/hermes/public"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/libuv/include"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Add tree-sitter language parser include paths
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    vimcraft_module_for_bench.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));

    // Add POSIX macros (required for tree-sitter)
    vimcraft_module_for_bench.addCMacro("_POSIX_C_SOURCE", "200112L");
    vimcraft_module_for_bench.addCMacro("_DEFAULT_SOURCE", "");
    vimcraft_module_for_bench.addCMacro("_DARWIN_C_SOURCE", "");

    bench_root_module.addImport("vimcraft", vimcraft_module_for_bench);

    const bench = b.addExecutable(.{
        .name = "vimc-bench",
        .root_module = bench_root_module,
    });

    // Add unicode_tables build dependency
    unicode_tables.addStepDependencies(&bench.step);

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
        .file = b.path("src/backends/headless/websocket_server.cpp"),
        .flags = cdp_flags,
    });

    bench.addCSourceFile(.{
        .file = b.path("src/backends/headless/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes dynamically
    bench.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    bench.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    bench.linkSystemLibrary("hermes_lean");
    bench.linkSystemLibrary("jsi");

    bench.addIncludePath(b.path("vendor/libuv/include"));
    // Link directly to our vendored libuv to avoid Homebrew conflicts
    bench.addObjectFile(b.path("vendor/libuv/build/libuv.a"));

    // libgit2 for benchmarks
    bench.addIncludePath(b.path("vendor/libgit2/include"));
    bench.addObjectFile(b.path("vendor/libgit2/build/libgit2.a"));

    // libgit2 dependencies for benchmarks (platform-specific)
    if (target.result.os.tag == .macos) {
        bench.linkFramework("Security");
        bench.linkFramework("CoreFoundation");
        bench.linkSystemLibrary("iconv");
        bench.linkSystemLibrary("z");
    } else if (is_linux) {
        bench.linkSystemLibrary("z");
    }

    // Tree-sitter for benchmarks
    bench.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    bench.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Language parser include paths (for tree_sitter/parser.h in each parser)
    bench.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    bench.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    bench.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    bench.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    bench.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    bench.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    bench.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));
    bench.addCSourceFiles(.{
        .root = b.path("vendor/tree-sitter/lib/src"),
        .files = &.{
            "alloc.c",
            "get_changed_ranges.c",
            "language.c",
            "lexer.c",
            "node.c",
            "parser.c",
            "point.c",
            "query.c",
            "stack.c",
            "subtree.c",
            "tree_cursor.c",
            "tree.c",
            "wasm_store.c",
        },
        .flags = &.{"-std=c11"},
    });
    bench.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    bench.root_module.addCMacro("_DEFAULT_SOURCE", "");
    bench.root_module.addCMacro("_DARWIN_C_SOURCE", "");

    // Tree-sitter Language Parsers (same as main exe)
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-c/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });

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

    // Re-enabled after fixing display.render() API signature mismatch
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

    // Add build_options module for tests (transpiler security settings)
    unit_tests.root_module.addImport("build_options", build_options.createModule());

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
        .file = b.path("src/backends/headless/websocket_server.cpp"),
        .flags = cdp_flags,
    });

    unit_tests.addCSourceFile(.{
        .file = b.path("src/backends/headless/cdp_debugger.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes dynamically for tests
    unit_tests.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    unit_tests.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    unit_tests.linkSystemLibrary("hermes_lean");
    unit_tests.linkSystemLibrary("jsi");

    // libuv for tests
    unit_tests.addIncludePath(b.path("vendor/libuv/include"));
    // Link directly to our vendored libuv to avoid Homebrew conflicts
    unit_tests.addObjectFile(b.path("vendor/libuv/build/libuv.a"));

    // libgit2 for tests
    unit_tests.addIncludePath(b.path("vendor/libgit2/include"));
    unit_tests.addObjectFile(b.path("vendor/libgit2/build/libgit2.a"));

    // libgit2 dependencies for tests (platform-specific)
    if (target.result.os.tag == .macos) {
        unit_tests.linkFramework("Security");
        unit_tests.linkFramework("CoreFoundation");
        unit_tests.linkSystemLibrary("iconv");
        unit_tests.linkSystemLibrary("z");
    } else if (is_linux) {
        unit_tests.linkSystemLibrary("z");
    }

    // go-enry for tests (same platform as main exe)
    unit_tests.addLibraryPath(b.path(enry_lib_path));
    unit_tests.linkSystemLibrary("enry");
    unit_tests.addRPath(b.path(enry_lib_path));

    // Tree-sitter for tests
    unit_tests.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Language parser include paths (for tree_sitter/parser.h in each parser)
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    unit_tests.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));
    unit_tests.addCSourceFiles(.{
        .root = b.path("vendor/tree-sitter/lib/src"),
        .files = &.{
            "alloc.c",
            "get_changed_ranges.c",
            "language.c",
            "lexer.c",
            "node.c",
            "parser.c",
            "point.c",
            "query.c",
            "stack.c",
            "subtree.c",
            "tree_cursor.c",
            "tree.c",
            "wasm_store.c",
        },
        .flags = &.{"-std=c11"},
    });
    unit_tests.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    unit_tests.root_module.addCMacro("_DEFAULT_SOURCE", "");
    unit_tests.root_module.addCMacro("_DARWIN_C_SOURCE", "");

    // Tree-sitter Language Parsers (same as main exe)
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-c/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });

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
    // PTY Tests (Terminal Backend Integration Tests)
    // ============================================================================
    const pty_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/backends/terminal/tests/core_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_pty_tests = b.addRunArtifact(pty_tests);
    // PTY tests require vimc to be built first
    run_pty_tests.step.dependOn(b.getInstallStep());

    // Rendering optimization PTY tests
    const rendering_opt_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/backends/terminal/tests/rendering_optimization_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_rendering_opt_tests = b.addRunArtifact(rendering_opt_tests);
    run_rendering_opt_tests.step.dependOn(b.getInstallStep());

    const pty_test_step = b.step("pty_tests", "Run PTY integration tests (requires vimc built)");
    pty_test_step.dependOn(&run_pty_tests.step);
    pty_test_step.dependOn(&run_rendering_opt_tests.step);

    // ============================================================================
    // Performance Measurement Tool (PTY-based)
    // NOTE: Disabled by default in CI (requires libc headers not always available)
    // Use -Denable-pty-tools=true to enable locally
    // ============================================================================
    const enable_pty_tools = b.option(
        bool,
        "enable-pty-tools",
        "Build PTY-based development tools (perf_test, cursor_monitor). Requires libc headers.",
    ) orelse false; // Disabled by default

    if (enable_pty_tools) {
        const perf_test = b.addExecutable(.{
            .name = "perf_test",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tools/perf_test/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        // Add PTY module for spawning vimc in pseudoterminal
        perf_test.root_module.addAnonymousImport("pty", .{
            .root_source_file = b.path("src/backends/terminal/tests/pty.zig"),
        });

        b.installArtifact(perf_test);

        const run_perf_test = b.addRunArtifact(perf_test);
        // Performance test requires vimc to be built first
        run_perf_test.step.dependOn(b.getInstallStep());

        const perf_test_step = b.step("perf_test", "Run PTY-based performance measurement");
        perf_test_step.dependOn(&run_perf_test.step);
    }

    // ============================================================================
    // Cursor Escape Code Monitor (Debug cursor flickering)
    // NOTE: Disabled by default in CI (requires libc headers not always available)
    // Use -Denable-pty-tools=true to enable locally
    // ============================================================================
    if (enable_pty_tools) {
        const cursor_monitor = b.addExecutable(.{
            .name = "cursor_monitor",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tools/cursor_monitor/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        // Add PTY module for spawning vimc
        cursor_monitor.root_module.addAnonymousImport("pty", .{
            .root_source_file = b.path("src/backends/terminal/tests/pty.zig"),
        });

        b.installArtifact(cursor_monitor);

        const run_cursor_monitor = b.addRunArtifact(cursor_monitor);
        run_cursor_monitor.step.dependOn(b.getInstallStep());

        const cursor_monitor_step = b.step("cursor_monitor", "Monitor cursor escape codes during rapid movement");
        cursor_monitor_step.dependOn(&run_cursor_monitor.step);
    }

    // ============================================================================
    // JSI HostObject Performance Benchmark
    // ============================================================================
    const jsi_bench = b.addExecutable(.{
        .name = "jsi-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/jsi_bench_main.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Use optimized build for accurate benchmarks
        }),
    });

    // Link C and C++ for Hermes
    jsi_bench.linkLibC();
    jsi_bench.linkLibCpp();

    // Ghostty components (for Buffer dependencies)
    jsi_bench.addIncludePath(b.path("vendor/ghostty/src"));

    // Hermes include paths
    jsi_bench.addIncludePath(b.path("src"));
    jsi_bench.addIncludePath(b.path("vendor/hermes/API"));
    jsi_bench.addIncludePath(b.path("vendor/hermes/API/jsi"));
    jsi_bench.addIncludePath(b.path("vendor/hermes/public"));

    // Add uucode module (required by Buffer)
    jsi_bench.root_module.addImport("uucode", uucode_module);

    // Add unicode_tables import (required by grapheme)
    unicode_tables.addStepDependencies(&jsi_bench.step);
    jsi_bench.root_module.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });

    // Add ghostty_grapheme module (required by Buffer)
    jsi_bench.root_module.addImport("ghostty_grapheme", ghostty_grapheme_mod);

    // Add C++ source files
    jsi_bench.addCSourceFile(.{
        .file = b.path("src/system/jsi/hermes_c_api.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/hermes/API/jsi/jsi/jsi.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes dynamically
    jsi_bench.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    jsi_bench.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    jsi_bench.linkSystemLibrary("hermes_lean");
    jsi_bench.linkSystemLibrary("jsi");

    // Set RPATH for finding Hermes libraries at runtime
    jsi_bench.addRPath(b.path("vendor/hermes/build/API/hermes"));
    jsi_bench.addRPath(b.path("vendor/hermes/build/jsi"));

    // Tree-sitter for JSI benchmark
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter/lib/src"));

    // Language parser include paths (for tree_sitter/parser.h in each parser)
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-c/src"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-javascript/src"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-typescript/typescript/src"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-typescript/tsx/src"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src"));
    jsi_bench.addIncludePath(b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src"));
    jsi_bench.addCSourceFiles(.{
        .root = b.path("vendor/tree-sitter/lib/src"),
        .files = &.{
            "alloc.c",
            "get_changed_ranges.c",
            "language.c",
            "lexer.c",
            "node.c",
            "parser.c",
            "point.c",
            "query.c",
            "stack.c",
            "subtree.c",
            "tree_cursor.c",
            "tree.c",
            "wasm_store.c",
        },
        .flags = &.{"-std=c11"},
    });
    jsi_bench.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    jsi_bench.root_module.addCMacro("_DEFAULT_SOURCE", "");
    jsi_bench.root_module.addCMacro("_DARWIN_C_SOURCE", "");

    // Tree-sitter Language Parsers (same as main exe)
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-c/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-javascript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/typescript/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-typescript/tsx/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    jsi_bench.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"),
        .flags = &.{"-std=c11"},
    });

    b.installArtifact(jsi_bench);

    const run_jsi_bench = b.addRunArtifact(jsi_bench);
    run_jsi_bench.step.dependOn(b.getInstallStep());

    const jsi_bench_step = b.step("jsi-bench", "Run JSI HostObject performance benchmark");
    jsi_bench_step.dependOn(&run_jsi_bench.step);

    // ============================================================================
    // Hermes TypeScript Test Runner
    // ============================================================================
    // Runs TypeScript tests compiled to Hermes bytecode (HBC)
    // Pipeline: TypeScript → esbuild → JavaScript → hermesc → HBC → Hermes Runtime
    //
    // Usage: zig build hermes-tests
    //
    // Test files: tests/hermes/*.ts
    // Cache: .zig-cache/hermes-tests/*.hbc
    const hermes_tests = b.addExecutable(.{
        .name = "hermes-test-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/system/jsi/hermes_test_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Create transpiler modules for hermes-tests
    // Create esbuild module with proper include path
    const esbuild_mod_for_tests = b.createModule(.{
        .root_source_file = b.path("src/system/transpiler/esbuild.zig"),
        .target = target,
        .optimize = optimize,
    });
    esbuild_mod_for_tests.addIncludePath(b.path("vendor/esbuild-wrapper"));
    // cache.zig is imported internally by esbuild.zig

    // Create hermes_compiler module
    const hermes_compiler_mod_for_tests = b.createModule(.{
        .root_source_file = b.path("src/system/transpiler/hermes.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add transpiler modules
    hermes_tests.root_module.addImport("esbuild", esbuild_mod_for_tests);
    hermes_tests.root_module.addImport("hermes_compiler", hermes_compiler_mod_for_tests);

    // Link C and C++ for Hermes
    hermes_tests.linkLibC();
    hermes_tests.linkLibCpp();

    // Hermes include paths
    hermes_tests.addIncludePath(b.path("src"));
    hermes_tests.addIncludePath(b.path("vendor/hermes/API"));
    hermes_tests.addIncludePath(b.path("vendor/hermes/API/jsi"));
    hermes_tests.addIncludePath(b.path("vendor/hermes/public"));

    // Add esbuild include path for transpiler
    hermes_tests.addIncludePath(b.path("vendor/esbuild-wrapper"));

    // Add C++ source files for Hermes+JSI wrapper
    hermes_tests.addCSourceFile(.{
        .file = b.path("src/system/jsi/hermes_c_api.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    hermes_tests.addCSourceFile(.{
        .file = b.path("vendor/hermes/API/jsi/jsi/jsi.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=all",
        },
    });

    // Link Hermes dynamically (use hermes_lean for bytecode execution)
    hermes_tests.addLibraryPath(b.path("vendor/hermes/build/API/hermes"));
    hermes_tests.addLibraryPath(b.path("vendor/hermes/build/jsi"));
    hermes_tests.linkSystemLibrary("hermes_lean");
    hermes_tests.linkSystemLibrary("jsi");

    // Set RPATH for finding Hermes libraries at runtime
    hermes_tests.addRPath(b.path("vendor/hermes/build/API/hermes"));
    hermes_tests.addRPath(b.path("vendor/hermes/build/jsi"));

    // Link esbuild library for TypeScript transpilation
    hermes_tests.addObjectFile(b.path(esbuild_source_path));

    // Set RPATH for esbuild (platform-specific)
    if (target.result.os.tag == .macos) {
        hermes_tests.addRPath(.{ .cwd_relative = "@executable_path" });
    } else if (target.result.os.tag == .linux) {
        hermes_tests.addRPath(.{ .cwd_relative = "$ORIGIN" });
    }

    b.installArtifact(hermes_tests);

    const run_hermes_tests = b.addRunArtifact(hermes_tests);
    run_hermes_tests.step.dependOn(b.getInstallStep());

    const hermes_tests_step = b.step("hermes-tests", "Run TypeScript tests with full Hermes runtime (TS→JS→HBC→Hermes)");
    hermes_tests_step.dependOn(&run_hermes_tests.step);

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
