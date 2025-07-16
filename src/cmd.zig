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
    .commands = .{
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
    .options = .{
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

pub fn validate_parsed_args(args: []const arg.ArgParse) ![]arg.ArgParse {
    for (args) |a| {
        switch (a) {
            .option => {},
            .value => {},
        }
    }
}
