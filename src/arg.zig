const std = @import("std");
pub const OptType = @import("parse.zig").OptType;

pub const ArgType = enum {
    Any,
    Path,
    Text,
};

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
    type: ArgType = .Any,
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

    fn get_help_line(
        opt: *const Option,
        buffer: []u8,
        comptime opt_width: comptime_int,
        comptime arg_width: comptime_int,
    ) ![]const u8 {
        var arg_buf: [64]u8 = undefined;
        var used: usize = 0;
        if (opt.short_name) |short| {
            _ = try appendFmt(buffer, &used, "  -{s}, ", .{short});
        } else _ = try appendFmt(buffer, &used, "      ", .{});

        const arg_name = opt.format_arg_name(&arg_buf);
        _ = try appendFmt(
            buffer,
            &used,
            "--{[opt]s:<[optw]} {[arg]s:<[argw]} {[desc]s}",
            .{
                .opt = opt.long_name,
                .optw = opt_width,
                .arg = arg_name orelse "",
                .argw = arg_width,
                .desc = opt.desc,
            },
        );

        if (opt.arg) |a| if (a.default) |d| {
            _ = try appendFmt(buffer, &used, " [default: {s}]", .{d});
        };
        _ = try appendFmt(buffer, &used, "\n", .{});
        return buffer[0..used];
    }
};

pub const CliApp = struct {
    exe_name: ?[]const u8 = null,
    cmd_required: bool = false,
    commands: []const Cmd = &[_]Cmd{},
    options: []const Option = &[_]Option{},
};

pub const CmdVal = struct {
    cmd: *const Cmd,
    options: ?std.StaticStringMap(*const Option),
};

pub const App = struct {
    cli: *const CliApp,
    commands: std.StaticStringMap(CmdVal),
    options: std.StaticStringMap(*const Option),

    fn initComptime(
        comptime args: *const CliApp,
    ) App {
        const cmds = comptime blk: {
            var cmds_s: [args.commands.len]struct { []const u8, CmdVal } = undefined;
            for (args.commands, 0..) |*cmd, i| {
                const opts = if (cmd.options) |cmd_opts|
                    optionHashMap(cmd_opts)
                else
                    null;
                cmds_s[i] = .{ cmd.name, .{
                    .cmd = cmd,
                    .options = opts,
                } };
            }
            break :blk cmds_s;
        };

        return .{
            .cli = args,
            .options = optionHashMap(args.options),
            .commands = std.StaticStringMap(CmdVal).initComptime(cmds),
        };
    }

    pub fn find_cmd(comptime self: *const App, cmd: []const u8) !*const Cmd {
        return if (self.commands.get(cmd)) |res| res.cmd else error.InvalidCommand;
    }

    pub fn find_option(comptime self: *const App, opt: []const u8) !*const Option {
        return self.options.get(opt) orelse error.InvalidOption;
    }
};

fn optionHashMap(
    comptime options: []const Option,
) std.StaticStringMap(*const Option) {
    const opts = comptime blk: {
        var count = 0;
        var opts_s: [options.len * 2]struct { []const u8, *const Option } = undefined;
        for (options) |*opt| {
            opts_s[count] = .{ opt.long_name, opt };
            count += 1;
            if (opt.short_name) |s| {
                opts_s[count] = .{ s, opt };
                count += 1;
            }
        }
        break :blk opts_s[0..count];
    };
    return std.StaticStringMap(*const Option).initComptime(opts);
}

pub fn get_help(
    allocator: std.mem.Allocator,
    comptime app: *const CliApp,
    command: ?Cmd,
    app_name: []const u8,
) ![]const u8 {
    var line_buf: [512]u8 = undefined;
    var usage_buf = try std.ArrayList(u8).initCapacity(allocator, 2048);
    errdefer usage_buf.deinit(allocator);
    var buf = try std.ArrayList(u8).initCapacity(allocator, 2048);
    defer buf.deinit(allocator);

    const fmt_widths = comptime get_fmt_widths(app);
    const opt_fmt_width = fmt_widths.@"0";
    const arg_fmt_width = fmt_widths.@"1";

    try usage_buf.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Usage: {s}", .{app_name}),
    );

    if (app.commands.len > 0) {
        try usage_buf.appendSlice(allocator, " [command]");
        try buf.appendSlice(allocator, "\n\nCommands:\n\n");

        for (app.commands) |cmd| {
            try buf.appendSlice(allocator, try std.fmt.bufPrint(
                &line_buf,
                "  {[name]s:<[width]} {[desc]s}\n",
                .{
                    .name = cmd.name,
                    .width = opt_fmt_width + arg_fmt_width + 7,
                    .desc = cmd.desc,
                },
            ));
        }
    } else try buf.append(allocator, '\n');

    if (app.options.len > 0) {
        try usage_buf.appendSlice(allocator, " [options]");
        try buf.appendSlice(allocator, "\nOptions:\n\n");
        for (app.options) |opt| {
            try buf.appendSlice(
                allocator,
                try opt.get_help_line(&line_buf, opt_fmt_width, arg_fmt_width),
            );

            if (opt.required) {
                try usage_buf.appendSlice(
                    allocator,
                    try std.fmt.bufPrint(&line_buf, " --{s}", .{opt.long_name}),
                );

                var arg_buf: [64]u8 = undefined;
                const arg_name = opt.format_arg_name(&arg_buf);
                if (arg_name) |name| try usage_buf.appendSlice(
                    allocator,
                    try std.fmt.bufPrint(&line_buf, " {s}", .{name}),
                );
            }
        }
    }

    if (command) |cmd| if (cmd.options) |opts| {
        try buf.appendSlice(
            allocator,
            try std.fmt.bufPrint(&line_buf, "\nOptions for command '{s}':\n\n", .{cmd.name}),
        );
        for (opts) |opt| try buf.appendSlice(
            allocator,
            try opt.get_help_line(&line_buf, opt_fmt_width, arg_fmt_width),
        );
    };

    try usage_buf.appendSlice(allocator, buf.items);
    return usage_buf.toOwnedSlice(allocator);
}

fn get_fmt_widths(comptime app: *const CliApp) struct { comptime_int, comptime_int } {
    var checker = struct {
        opt_width: comptime_int = 0,
        arg_width: comptime_int = 0,
        fn check_widths(self: *@This(), opt: Option) void {
            if (opt.long_name.len > self.opt_width)
                self.opt_width = opt.long_name.len;
            if (opt.arg) |arg| if (arg.name.len > self.arg_width) {
                self.arg_width = arg.name.len;
            };
        }
    }{};
    for (app.options) |opt| checker.check_widths(opt);
    for (app.commands) |cmd| if (cmd.options) |opts| for (opts) |opt| {
        checker.check_widths(opt);
    };
    return .{ checker.opt_width + 1, checker.arg_width + 4 };
}

pub fn appendFmt(
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

pub fn validate_args_struct(comptime app: *const CliApp) App {
    const opt_names = validate_commands(app.commands);

    // Check for duplicate option names
    const long_names = ensureUniqueStrings(
        Option,
        "long_name",
        app.options,
        opt_names,
    );
    _ = ensureUniqueStrings(Option, "short_name", app.options, long_names);

    return App.initComptime(app);
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

    comptime {
        const log2_n: comptime_int = @intFromFloat(std.math.log2(@as(f64, len)));
        const quota = 4 * len * len * log2_n;
        const min_quota = 1000;
        const max_quota = 100_000_000;
        const branch_quota = std.math.clamp(quota, min_quota, max_quota);
        @setEvalBranchQuota(branch_quota);
    }

    std.mem.sort([]const u8, slice, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    }.lessThan);

    if (slice.len > 1) inline for (slice[1..], 1..) |name, i| {
        if (std.mem.eql(u8, slice[i - 1], name)) {
            @compileError("Duplicate " ++ field_name ++ " value found: \"" ++ name ++ "\"");
        }
    };
    return slice;
}
