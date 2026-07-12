const std = @import("std");

/// Build-time shell completion generation.
pub const completions = @import("build/completions.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zcli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const version_tag = b.option(
        []const u8,
        "version_tag",
        "Version tag for the program",
    ) orelse null;

    const options = b.addOptions();
    mod.addOptions("options", options);
    options.addOption(?[]const u8, "version_tag", version_tag);

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zcli", .module = mod }},
        }),
    });
    const root_tests = b.addTest(.{ .root_module = mod });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_root_tests = b.addRunArtifact(root_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_root_tests.step);

    const check_step = b.step("check", "Check for compile errors");
    const test_exe = b.addExecutable(.{
        .name = "zcli-test",
        .root_module = lib_tests.root_module,
    });
    check_step.dependOn(&test_exe.step);
    check_step.dependOn(&lib_tests.step);
    check_step.dependOn(&root_tests.step);
}
