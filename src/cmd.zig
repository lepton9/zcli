const std = @import("std");
const OptType = @import("arg.zig").OptType;

pub const Cmd = struct {
    name: ?[]const u8,
    desc: []const u8,
    options: ?[]const Option = null,
};

pub const Option = struct {
    long_name: []const u8,
    short_name: ?[]const u8,
    desc: []const u8,
    required: bool = false,
    arg_name: ?[]const u8,
    arg_value: ?[]const u8 = null,

    pub fn get_format_name(self: *const Option, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "'--{s}'", .{self.long_name}) catch self.long_name;
    }

    pub fn format_arg_name(self: *const Option, buffer: []u8) ?[]const u8 {
        if (self.arg_name) |arg_name| {
            return std.fmt.bufPrint(buffer, "<{s}>", .{arg_name}) catch self.arg_name;
        }
        return null;
    }
};

pub const ArgsStructure = struct {
    cmd_required: bool = false,
    commands: []const Cmd = &[_]Cmd{},
    options: []const Option = &[_]Option{},

    pub fn init(allocator: *std.mem.Allocator) !*ArgsStructure {
        const args_structure = try allocator.create(ArgsStructure);
        args_structure.* = ArgsStructure{
            .commands = &[_]Cmd{},
            .options = &[_]Option{},
        };
        return args_structure;
    }

    pub fn deinit(self: *ArgsStructure, allocator: *std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn set_commands(self: *ArgsStructure, commands: []const Cmd) void {
        self.commands = commands;
    }

    pub fn set_options(self: *ArgsStructure, options: []const Option) void {
        self.options = options;
    }

    pub fn args_structure_string(self: *ArgsStructure, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: [256]u8 = undefined;
        var arg_buf: [32]u8 = undefined;
        var buf = std.ArrayList(u8).init(allocator);
        try buf.appendSlice("Commands:\n\n");
        for (self.commands) |cmd| {
            try buf.appendSlice(try std.fmt.bufPrint(
                &buffer,
                "  {s:<30} {s}\n",
                .{ cmd.name orelse "", cmd.desc },
            ));
        }
        try buf.appendSlice("\nOptions:\n\n");
        for (self.options) |opt| {
            const arg_name = opt.format_arg_name(&arg_buf);
            const line = blk: {
                if (opt.short_name) |short| {
                    break :blk try std.fmt.bufPrint(
                        &buffer,
                        "  -{s}, --{s:<12} {s:<13} {s}\n",
                        .{ short, opt.long_name, arg_name orelse "", opt.desc },
                    );
                } else {
                    break :blk try std.fmt.bufPrint(
                        &buffer,
                        "      --{s:<12} {s:<13} {s}\n",
                        .{ opt.long_name, arg_name orelse "", opt.desc },
                    );
                }
            };
            try buf.appendSlice(line);
        }
        return buf.toOwnedSlice();
    }

    pub fn find_cmd(self: *const ArgsStructure, cmd: []const u8) !Cmd {
        for (self.commands) |c| {
            if (std.mem.eql(u8, c.name orelse "", cmd)) {
                return c;
            }
        }
        return error.InvalidCommand;
    }

    pub fn find_option(self: *const ArgsStructure, opt: []const u8, opt_type: OptType) !Option {
        for (self.options) |o| {
            const name = switch (opt_type) {
                OptType.short => o.short_name orelse continue,
                OptType.long => o.long_name,
            };
            if (std.mem.eql(u8, name, opt)) {
                return o;
            }
        }
        return error.InvalidOption;
    }
};
