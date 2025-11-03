const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zcli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const options = b.addOptions();
    mod.addOptions("options", options);
    options.addOption(?[]const u8, "VERSION", null);

    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zcli", .module = mod }},
        }),
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

pub fn add_version_info(
    b: *std.Build,
    mod: *std.Build.Module,
    version: ?[]const u8,
) void {
    const options = b.addOptions();
    options.addOption(?[]const u8, "VERSION", version);
    mod.addOptions("options", options);
}
