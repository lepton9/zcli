const std = @import("std");
const OptType = @import("parse.zig").OptType;

pub const Cmd = struct {
    name: []const u8,
    desc: []const u8,
    options: ?[]const Option = null,
};

pub const Arg = struct {
    name: []const u8,
    value: ?[]const u8 = null,
    required: bool = true,
    default: ?[]const u8 = null,
};

pub const Option = struct {
    long_name: []const u8,
    short_name: ?[]const u8,
    desc: []const u8,
    required: bool = false,
    arg: ?Arg = null,

    pub fn get_format_name(self: *const Option, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "'--{s}'", .{self.long_name}) catch self.long_name;
    }

    pub fn format_arg_name(self: *const Option, buffer: []u8) ?[]const u8 {
        if (self.arg) |arg| {
            return std.fmt.bufPrint(buffer, "<{s}{s}>", .{
                if (arg.required) "" else "?",
                arg.name,
            }) catch arg.name;
        }
        return null;
    }
};

pub const ArgsStructure = struct {
    cmd_required: bool = false,
    commands: []const Cmd = &[_]Cmd{},
    options: []const Option = &[_]Option{},

    pub fn as_string(self: *const ArgsStructure, allocator: std.mem.Allocator) ![]const u8 {
        var line_buf: [256]u8 = undefined;
        var arg_buf: [32]u8 = undefined;
        var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "Commands:\n\n");

        for (self.commands) |cmd| {
            try buf.appendSlice(allocator, try std.fmt.bufPrint(
                &line_buf,
                "  {s:<40} {s}\n",
                .{ cmd.name, cmd.desc },
            ));
        }

        try buf.appendSlice(allocator, "\nOptions:\n\n");
        for (self.options) |opt| {
            if (opt.short_name) |short| {
                try buf.appendSlice(
                    allocator,
                    try std.fmt.bufPrint(&line_buf, "  -{s}, ", .{short}),
                );
            } else try buf.appendSlice(allocator, "      ");

            const arg_name = opt.format_arg_name(&arg_buf);
            try buf.appendSlice(allocator, try std.fmt.bufPrint(
                &line_buf,
                "--{s:<11} {s:<22} {s}",
                .{ opt.long_name, arg_name orelse "", opt.desc },
            ));

            if (opt.arg) |a| if (a.default) |d| {
                try buf.appendSlice(
                    allocator,
                    try std.fmt.bufPrint(&line_buf, " [default: {s}]", .{d}),
                );
            };
            try buf.append(allocator, '\n');
        }
        return buf.toOwnedSlice(allocator);
    }

    pub fn find_cmd(self: *const ArgsStructure, cmd: []const u8) !Cmd {
        for (self.commands) |c| {
            if (std.mem.eql(u8, c.name, cmd)) {
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
