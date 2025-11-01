# zcli

Command Line Argument parser for Zig

## Usage

Add to `build.zig.zon`
```
zig fetch --save git+https://github.com/lepton9/zcli
```

In `build.zig`

``` zig
const zcli = b.dependency("zcli", .{ .target = target, .optimize = optimize });
const zcli_mod = zcli.module("zcli");
exe.root_module.addImport("zcli", zcli_mod);
```

## Features

- Subcommands, options, positional arguments
- Compile-time CLI definition validation
- Help generation
- User error handling
- Shell completion generation (bash, zsh, fish)

## Defining the CLI

```zig
const zcli = @import("zcli");

const app: CliApp = .{
    .config = .{
        .exe_name = "program",
        .cmd_required = false,
    },
    .commands = &[_]zcli.Cmd{
        .{
            .name = "command",
            .desc = "Description",
            .options = null,
            .positionals = null,
        },
    },
    .options = &[_]zcli.Option{
        .{
            .long_name = "option",
            .short_name = "o",
            .desc = "Description",
            .arg = .{ .name = "arg" },
        },
    },
    .positionals = &[_].zcli.PosArg{
        .{
            .name = "positional",
            .desc = "Description",
            .required = true,
            .multiple = false,
        },
    },
};
```

## Example

```zig
const std = @import("std");
const zcli = @import("zcli");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const cli = try zcli.parse_args(allocator, &app);
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
        app.exe_name,
        "bash",
    );
}
```

