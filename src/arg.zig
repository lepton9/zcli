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

    pub fn init_from(option: *const Option, allocator: std.mem.Allocator) !*Option {
        const opt = try allocator.create(Option);
        opt.* = option.*;
        if (option.arg) |arg| if (arg.value) |value| {
            opt.arg.?.value = try allocator.dupe(u8, value);
        };
        return opt;
    }

    pub fn deinit(self: *Option, allocator: std.mem.Allocator) void {
        if (self.arg) |arg| if (arg.value) |value| {
            allocator.free(value);
        };
        allocator.destroy(self);
    }

    pub fn get_format_name(self: *const Option, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "'--{s}'", .{self.long_name}) catch self.long_name;
    }

    fn format_arg_name(self: *const Option, buffer: []u8) ?[]const u8 {
        if (self.arg) |arg| {
            return std.fmt.bufPrint(buffer, "<{s}{s}>", .{
                if (arg.required) "" else "?",
                arg.name,
            }) catch arg.name;
        }
        return null;
    }

    fn get_help_line(opt: *const Option, buffer: []u8) ![]const u8 {
        var arg_buf: [64]u8 = undefined;
        var used: usize = 0;
        if (opt.short_name) |short| {
            _ = try appendFmt(buffer, &used, "  -{s}, ", .{short});
        } else _ = try appendFmt(buffer, &used, "      ", .{});

        const arg_name = opt.format_arg_name(&arg_buf);
        _ = try appendFmt(
            buffer,
            &used,
            "--{s:<11} {s:<22} {s}",
            .{ opt.long_name, arg_name orelse "", opt.desc },
        );

        if (opt.arg) |a| if (a.default) |d| {
            _ = try appendFmt(buffer, &used, " [default: {s}]", .{d});
        };
        _ = try appendFmt(buffer, &used, "\n", .{});
        return buffer[0..used];
    }
};

pub const ArgsStructure = struct {
    exe_name: ?[]const u8 = null,
    cmd_required: bool = false,
    commands: []const Cmd = &[_]Cmd{},
    options: []const Option = &[_]Option{},

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

pub fn get_help(
    allocator: std.mem.Allocator,
    comptime app: *const ArgsStructure,
    exe_path: [:0]u8,
) ![]const u8 {
    var line_buf: [512]u8 = undefined;
    var arg_buf: [64]u8 = undefined;
    var usage_buf = try std.ArrayList(u8).initCapacity(allocator, 2048);
    errdefer usage_buf.deinit(allocator);
    var buf = try std.ArrayList(u8).initCapacity(allocator, 2048);
    defer buf.deinit(allocator);

    try usage_buf.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Usage: {s}", .{
            app.exe_name orelse std.fs.path.basename(std.mem.span(exe_path.ptr)),
        }),
    );

    if (app.commands.len > 0) {
        try usage_buf.appendSlice(allocator, " [command]");
        try buf.appendSlice(allocator, "\n\nCommands:\n\n");

        for (app.commands) |cmd| {
            try buf.appendSlice(allocator, try std.fmt.bufPrint(
                &line_buf,
                "  {s:<40} {s}\n",
                .{ cmd.name, cmd.desc },
            ));
        }
    } else try buf.append(allocator, '\n');

    if (app.options.len > 0) {
        try usage_buf.appendSlice(allocator, " [options]");
        try buf.appendSlice(allocator, "\nOptions:\n\n");
        for (app.options) |opt| {
            try buf.appendSlice(
                allocator,
                try opt.get_help_line(&line_buf),
            );

            if (opt.required) {
                try usage_buf.appendSlice(
                    allocator,
                    try std.fmt.bufPrint(&line_buf, " --{s}", .{opt.long_name}),
                );

                const arg_name = opt.format_arg_name(&arg_buf);
                if (arg_name) |name| try usage_buf.appendSlice(
                    allocator,
                    try std.fmt.bufPrint(&line_buf, " {s}", .{name}),
                );
            }
        }
    }
    try usage_buf.appendSlice(allocator, buf.items);

    return usage_buf.toOwnedSlice(allocator);
}

fn appendFmt(
    buffer: []u8,
    written: *usize,
    comptime fmt: []const u8,
    args: anytype,
) ![]u8 {
    const out = buffer[written.*..];
    const printed = try std.fmt.bufPrint(out, fmt, args);
    written.* += printed.len;
    return buffer[0..written.*];
}

pub fn validate_args_struct(comptime app: *const ArgsStructure) void {
    const opt_names = validate_commands(app.commands);
    const long_names = ensureUniqueStrings(
        Option,
        "long_name",
        app.options,
        opt_names,
    );
    _ = ensureUniqueStrings(Option, "short_name", app.options, long_names);
}

fn validate_commands(comptime cmds: []const Cmd) [][]const u8 {
    var opt_names: [][]const u8 = &[_][]const u8{};
    inline for (cmds, 0..) |cmd_i, i| {
        if (cmd_i.options) |cmd_opts| {
            const long_names = ensureUniqueStrings(
                Option,
                "long_name",
                cmd_opts,
                opt_names,
            );
            opt_names = ensureUniqueStrings(Option, "short_name", cmd_opts, long_names);
        }
        inline for (cmds[(i + 1)..]) |cmd_j| {
            if (std.mem.eql(u8, cmd_i.name, cmd_j.name)) {
                @compileError("Duplicate command name: " ++ cmd_i.name);
            }
        }
    }
    return opt_names;
}

fn ensureUniqueStrings(
    comptime T: type,
    comptime field_name: []const u8,
    comptime items: []const T,
    comptime existing_strings: [][]const u8,
) [][]const u8 {
    const len = items.len + existing_strings.len;
    comptime var names: [len][]const u8 = undefined;
    comptime var count: usize = 0;
    std.mem.copyForwards([]const u8, &names, existing_strings);
    count += existing_strings.len;

    inline for (items) |item| {
        const field_value = @field(item, field_name);
        const info = @typeInfo(@TypeOf(field_value));
        if (info == .optional) {
            if (field_value) |v| {
                names[count] = v;
                count += 1;
            }
        } else {
            names[count] = field_value;
            count += 1;
        }
    }
    const slice = names[0..count];

    std.mem.sort([]const u8, slice, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    inline for (slice[1..], 1..) |name, i| {
        if (std.mem.eql(u8, slice[i - 1], name)) {
            @compileError("Duplicate " ++ field_name ++ " value found: \"" ++ name ++ "\"");
        }
    }

    return slice;
}
