# zcli

Command Line Argument parser for Zig

[![Zig](https://img.shields.io/badge/v0.16.0-orange?logo=Zig&logoColor=Orange&label=Zig&labelColor=Orange)](https://ziglang.org/download/)
[![Licence](https://img.shields.io/badge/MIT-silver?label=License)](https://github.com/lepton9/zcli/blob/master/LICENSE)

## Features

- Commands, subcommands, options, positional arguments, argument groups
- Compile-time CLI definition validation
- Help generation
- User error handling
- Shell completion generation (bash, zsh, fish)
- Suggestions for typos

## Usage
```
zig fetch --save git+https://github.com/lepton9/zcli
```

In `build.zig`

``` zig
const zcli = b.dependency("zcli", .{
    .target = target,
    .optimize = optimize,
    .version_tag = @import("build.zig.zon").version,
});
const zcli_mod = zcli.module("zcli");

exe.root_module.addImport("zcli", zcli_mod);
```

## Defining the CLI

```zig
const zcli = @import("zcli");

const app: zcli.CliApp = .{
    .config = .{
        .name = "demo",
        .description = null,  // About text
        .suggestions = false, // Turn on suggestions for typos
        .auto_help = true,    // Handle '--help' option
        .auto_version = true, // Handle '--version' option
        .help_max_width = 80, // Max amount of text on a line
    },
    .commands = &[_]zcli.Cmd{.{
        .name = "command",
        .desc = "Description",
        .options = null,
        .positionals = null,
        .action = null,
    }},
    .options = &[_]zcli.Opt{
        .{ .long_name = "option", .short_name = "o", .desc = "Description", .arg = .{ .name = "arg" } },
        .{ .long_name = "version", .short_name = "v", .desc = "Print version" },
        .{ .long_name = "help", .short_name = "h", .desc = "Print help" },
    },
    .positionals = &[_]zcli.PosArg{
        .{ .name = "positional", .desc = "Description", .required = true, .multiple = false },
    },
};
```
<details>
<summary>Generated help text</summary>

```
$ demo --help
Usage: demo [command] [options]

Commands:

  command                Description

Options:

  -o, --option   <arg>   Description
  -V, --version          Print version
  -h, --help             Print help
```
</details>

## Example

```zig
const std = @import("std");
const zcli = @import("zcli");

const app: zcli.CliApp = .{
    // ...
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    // const cli: *zcli.Cli = try zcli.parseInit(init, &app);
    const cli: *zcli.Cli = try zcli.parseArgs(io, gpa, init.minimal.args, &app);
    defer cli.deinit(gpa);

    // Find options
    if (cli.findOption("option")) |option| {
        std.debug.print(
            "Option '{s}' value was: '{s}'\n",
            .{ option.name, option.value.?.string },
        );
    }

    // Execute the command callback function
    var ctx = .{cli};
    try cli.run(&ctx);

    // Generate shell completion scripts
    const completions = try zcli.complete.getCompletionOwned(gpa, &app, .bash);
}
```

Handling the CLI parsing errors manually:

```zig
// ...

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(gpa);
    const cli: *zcli.Cli = try zcli.parseFrom(gpa, args, &app);
    defer cli.deinit(gpa);
}
```

## Build-Time Completions

You can generate and install shell completion files as part of `zig build`.

In your program's `build.zig`:

```zig
const std = @import("std");
const zcli_build = @import("zcli");

pub fn build(b: *std.Build) void {
    // ...

    const zcli_dep = b.dependency("zcli", .{ .target = target, .optimize = optimize });

    // Module that defines a `zcli.CliApp` value.
    const app_module = b.createModule(.{ .root_source_file = b.path("src/cli.zig") });

    const zcli = @import("zcli");
    const gen = zcli.completions.addGenerator(b, .{
        .zcli_dep = zcli_dep,
        .app_module = app_module,
        .app_decl_name = "app", // The decl name of the `zcli.CliApp`
        .optimize = .ReleaseFast,
    });

    // Generating completions for bash.
    const generated_bash = zcli.completions.addGenerate(b, gen, .{ .shells = &.{.bash} });
    const install_dir_bash = zcli.completions.addInstallDir(b, generated_bash, .{
        .install_dir = .prefix,
        .install_subdir = "share/bash-completion/completions",
    });

    const completions_step = b.step("completions", "Generate/install shell completions");
    completions_step.dependOn(&install_dir.step);
}
```
