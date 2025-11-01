const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "openvim",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();

    b.installArtifact(exe);

    // Integration demo executable
    const demo_exe = b.addExecutable(.{
        .name = "openvim-demo",
        .root_source_file = b.path("src/demo_integration.zig"),
        .target = target,
        .optimize = optimize,
    });

    demo_exe.linkLibC();

    b.installArtifact(demo_exe);

    // JSI demo - shows how Hermes+JSI will work
    const jsi_demo_exe = b.addExecutable(.{
        .name = "openvim-jsi-demo",
        .root_source_file = b.path("src/jsi_demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    jsi_demo_exe.linkLibC();

    b.installArtifact(jsi_demo_exe);

    // Run command for main
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Run command for demo
    const demo_cmd = b.addRunArtifact(demo_exe);
    demo_cmd.step.dependOn(b.getInstallStep());

    const demo_step = b.step("demo", "Run integration demo");
    demo_step.dependOn(&demo_cmd.step);

    // Run command for JSI demo
    const jsi_cmd = b.addRunArtifact(jsi_demo_exe);
    jsi_cmd.step.dependOn(b.getInstallStep());

    const jsi_step = b.step("jsi", "Explain Hermes+JSI integration");
    jsi_step.dependOn(&jsi_cmd.step);

    // NOTE: Hermes+JSI demo is built using Makefile.hermes instead of zig build
    // Reason: Zig's MachO linker crashes when parsing C++ exception handling metadata
    //         in the hermes_c_api.o wrapper. This is a Zig linker bug, not an issue
    //         with our integration (which works perfectly with clang++).
    //
    // To build and run Hermes integration:
    //   make -f Makefile.hermes all    # Build test-hermes and hermesc
    //   make -f Makefile.hermes test   # Run the integration test
    //   make -f Makefile.hermes clean  # Clean build artifacts
    //
    // The integration is fully working - see test results in /tmp/HERMES_SUCCESS.md

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
