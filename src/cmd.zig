const std = @import("std");
const arg = @import("arg");

pub const ArgsStructure = struct {
    cmd_required: bool,
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
    arg_value: ?[]const u8 = null,

    pub fn get_format_name(self: *const Option, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "'--{s}'", .{self.long_name}) catch self.long_name;
    }
};

pub const app = ArgsStructure{
    .cmd_required = true,
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
        .{
            .name = "help",
            .desc = "Print help",
            .options = null,
        },
    },
    .options = &[_]Option{
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
        .{
            .long_name = "scale",
            .short_name = "s",
            .desc = "Scale the image to size",
            .required = false,
            .arg_name = "float",
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

pub fn find_cmd(structure: *const ArgsStructure, cmd: []const u8) !Cmd {
    for (structure.commands) |c| {
        if (std.mem.eql(u8, c.name orelse "", cmd)) {
            return c;
        }
    }
    return error.InvalidOption;
}

pub fn find_option(structure: *const ArgsStructure, opt: []const u8, opt_type: arg.OptType) !Option {
    for (structure.options) |o| {
        const name = if (opt_type == arg.OptType.short)
            o.short_name
        else
            o.long_name;
        if (std.mem.eql(u8, name, opt)) {
            return o;
        }
    }
    return error.InvalidOption;
}
