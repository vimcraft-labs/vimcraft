/// Unicode Build Module
/// Configures Ghostty's uucode library and unicode table generation
const std = @import("std");

/// uucode build configuration (shared between native and cross-compilation)
const uucode_config =
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
;

/// Get uucode module for target compilation
pub fn getUucodeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .@"build_config.zig" = uucode_config,
    });
    return uucode_dep.module("uucode");
}

/// Generate unicode property tables at build time
/// Returns a LazyPath to the generated unicode_props.zig file
pub fn generateUnicodeTables(b: *std.Build) std.Build.LazyPath {
    // Build tools need a native version of uucode
    const uucode_native = b.dependency("uucode", .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .@"build_config.zig" = uucode_config,
    });

    // Create executable to generate unicode property tables
    const props_exe = b.addExecutable(.{
        .name = "props-unigen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("vendor/ghostty/src/unicode/props_uucode.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
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
    return wf.addCopyFile(props_run.captureStdOut(), "unicode_props.zig");
}

/// Create Ghostty grapheme module with all dependencies
pub fn createGraphemeModule(
    b: *std.Build,
    unicode_tables: std.Build.LazyPath,
) *std.Build.Module {
    const ghostty_unicode_path = "vendor/ghostty/src/unicode";

    // Create Properties module
    const properties_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/Properties.zig"),
    });

    // Create lut module
    const lut_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/lut.zig"),
    });

    // Create props_table module with dependencies
    const props_table_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/props_table.zig"),
    });
    props_table_mod.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });
    props_table_mod.addImport("lut.zig", lut_mod);
    props_table_mod.addImport("Properties.zig", properties_mod);

    // Create grapheme module
    const grapheme_mod = b.createModule(.{
        .root_source_file = b.path(ghostty_unicode_path ++ "/grapheme.zig"),
    });
    grapheme_mod.addImport("props_table.zig", props_table_mod);
    grapheme_mod.addImport("Properties.zig", properties_mod);

    return grapheme_mod;
}

/// Add unicode_tables as anonymous import to a module
pub fn addUnicodeTables(
    module: *std.Build.Module,
    unicode_tables: std.Build.LazyPath,
) void {
    module.addAnonymousImport("unicode_tables", .{
        .root_source_file = unicode_tables,
    });
}

/// Add unicode_tables build dependency to a step
pub fn addTablesDependency(
    step: *std.Build.Step,
    unicode_tables: std.Build.LazyPath,
) void {
    unicode_tables.addStepDependencies(step);
}
