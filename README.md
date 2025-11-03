# zcli

Command Line Argument parser for Zig

[![Zig](https://img.shields.io/badge/v0.15.2(stable)-orange?logo=Zig&logoColor=Orange&label=Zig&labelColor=Orange)](https://ziglang.org/download/)
[![Licence](https://img.shields.io/badge/MIT-silver?label=License)](https://github.com/lepton9/zcli/blob/master/LICENSE)

## Features

- Subcommands, options, positional arguments
- Compile-time CLI definition validation
- Help generation
- User error handling
- Shell completion generation (bash, zsh, fish)

## Usage
```
zig fetch --save git+https://github.com/lepton9/zcli
```

In `build.zig`

``` zig
const zcli = b.dependency("zcli", .{ .target = target, .optimize = optimize });
const zcli_mod = zcli.module("zcli");

// Add optional version info
const version = @import("build.zig.zon").version;
@import("zcli").add_version_info(b, zcli_mod, version);

exe.root_module.addImport("zcli", zcli_mod);
```

## Defining the CLI

```zig
const zcli = @import("zcli");

const app: zcli.CliApp = .{
    .config = .{
        .name = "demo",
        .cmd_required = false,
        .auto_help = true,
        .auto_version = true,
    },
    .commands = &[_]zcli.Cmd{
        .{ .name = "command", .desc = "Description", .options = null, .positionals = null },
    },
    .options = &[_]zcli.Opt{
        .{ .long_name = "option", .short_name = "o", .desc = "Description", .arg = .{ .name = "arg" } },
        .{ .long_name = "version", .short_name = "V", .desc = "Print version" },
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

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const cli: *zcli.Cli = try zcli.parse_args(allocator, &app);
    defer cli.deinit(allocator);

    // Find options
    if (cli.find_opt("option")) |option| {
        std.debug.print(
            "Option '{s}' value was: '{s}'\n",
            .{ option.long_name, option.arg.?.value.? },
        );
    }

    // Generate shell completion scripts
    var buffer: [4096]u8 = undefined;
    const completions = try zcli.complete.getCompletion(
        &buffer,
        &app,
        app.name,
        "bash",
    );
}
```

Handling the CLI parsing errors yourself:

```zig
// ...

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cli: *zcli.Cli = try zcli.parse_from(allocator, &app, args);
    defer cli.deinit(allocator);
}
```
