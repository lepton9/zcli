const std = @import("std");
const arg = @import("arg");

pub const ArgsStructure = struct {
    commands: []const Cmd,
    options: []const Option,
};

pub const Cmd = struct {
    name: ?[]const u8,
    desc: []const u8,
    options: ?[]const Option = null,
};

pub const Option = struct {
    long_name: []const u8,
    short_name: []const u8,
    desc: []const u8,
    required: bool = false,
    arg_name: ?[]const u8,
};

const app = ArgsStructure{
    .commands = &[_]Cmd{
        .{
            .name = "size",
            .desc = "Show size of the image",
            .options = null,
        },
        .{
            .name = "ascii",
            .desc = "Convert to ascii",
            .options = null,
        },
        .{
            .name = "compress",
            .desc = "Compress image",
            .options = null,
        },
    },
    .options = &[_]Option{
        .{
            .long_name = "help",
            .short_name = "h",
            .desc = "Show help",
            .required = false,
            .arg_name = null,
        },
        .{
            .long_name = "out",
            .short_name = "o",
            .desc = "Path of output file",
            .required = false,
            .arg_name = "filename",
        },
        .{
            .long_name = "width",
            .short_name = "w",
            .desc = "Width of wanted image",
            .required = false,
            .arg_name = "int",
        },
        .{
            .long_name = "height",
            .short_name = "h",
            .desc = "Height of wanted image",
            .required = false,
            .arg_name = "int",
        },
    },
};

pub fn print_commands() void {
    std.debug.print("Commands:\n\n", .{});
    for (app.commands) |cmd| {
        std.debug.print("  {s:<30} {s}\n", .{ cmd.name orelse "", cmd.desc });
    }
    std.debug.print("\nOptions:\n\n", .{});
    for (app.options) |opt| {
        std.debug.print("  -{s}, --{s:<10} {s:<13} {s}\n", .{ opt.short_name, opt.long_name, opt.arg_name orelse "", opt.desc });
    }
}
