const std = @import("std");

pub const Shell = enum {
    bash,
    zsh,
    fish,
};

pub const AddGeneratorOptions = struct {
    /// The zcli dependency.
    zcli_dep: *std.Build.Dependency,
    /// Module which must export a `zcli.CliApp` value (see `app_decl_name`).
    app_module: *std.Build.Module,
    /// Decl name inside `app_module` which contains the `zcli.CliApp` value.
    app_decl_name: []const u8 = "cli_app",
    /// Optimization mode for the generator executable.
    optimize: std.builtin.OptimizeMode,
    /// Optional name for the generator artifact.
    name: []const u8 = "zcli-gen-completions",
};

/// Builds the completion generator executable.
pub fn addGenerator(b: *std.Build, opts: AddGeneratorOptions) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = opts.name,
        .root_module = b.createModule(.{
            .root_source_file = opts.zcli_dep.path("build/gen_completion.zig"),
            .target = b.graph.host,
            .optimize = opts.optimize,
        }),
    });

    const gen_options = b.addOptions();
    gen_options.addOption([]const u8, "app_decl_name", opts.app_decl_name);
    exe.root_module.addOptions("zcli_gen_options", gen_options);

    exe.root_module.addImport("zcli", opts.zcli_dep.module("zcli"));
    exe.root_module.addImport("app", opts.app_module);
    return exe;
}

pub const AddGenerateOptions = struct {
    /// Which shells to generate.
    shells: []const Shell = &.{},
    /// Basename for the build-cache output directory.
    out_basename: []const u8 = "zcli-completions",
};

pub const Generated = struct {
    run: *std.Build.Step.Run,
    out_dir: std.Build.LazyPath,
};

/// Adds a build step that runs the generator and produces a directory.
pub fn addGenerate(
    b: *std.Build,
    generator_exe: *std.Build.Step.Compile,
    opts: AddGenerateOptions,
) Generated {
    const run = b.addRunArtifact(generator_exe);
    const out_dir = run.addPrefixedOutputDirectoryArg("--out-dir=", opts.out_basename);
    for (opts.shells) |shell| {
        run.addArgs(&.{ "--shell", @tagName(shell) });
    }
    return .{ .run = run, .out_dir = out_dir };
}

pub const AddInstallDirOptions = struct {
    /// Where to install. Default: into the install prefix.
    install_dir: std.Build.InstallDir = .prefix,
    /// Directory under the install prefix to install into.
    install_subdir: []const u8 = "",
};

/// Adds an install-dir step for the generated completion scripts.
pub fn addInstallDir(
    b: *std.Build,
    generated: Generated,
    opts: AddInstallDirOptions,
) *std.Build.Step.InstallDir {
    const inst = b.addInstallDirectory(.{
        .source_dir = generated.out_dir,
        .install_dir = opts.install_dir,
        .install_subdir = opts.install_subdir,
    });
    inst.step.dependOn(&generated.run.step);
    return inst;
}
