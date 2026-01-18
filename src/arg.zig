const std = @import("std");
pub const OptType = @import("parse.zig").OptType;

pub const ArgType = enum {
    Any,
    Path,
    Text,
    Bool,
    Int,
    Float,
};

pub const CmdFn = *const fn (*anyopaque) anyerror!void;

pub const Cmd = struct {
    name: []const u8,
    desc: []const u8 = "",
    options: ?[]const Opt = null,
    positionals: ?[]const PosArg = null,
    action: ?CmdFn = null,
};

pub const PosArg = struct {
    name: []const u8,
    desc: []const u8 = "",
    required: bool = true,
    multiple: bool = false,
};

pub const Arg = struct {
    name: []const u8,
    required: bool = true,
    default: ?[]const u8 = null,
    type: ArgType = .Any,
};

pub const Opt = struct {
    long_name: []const u8,
    short_name: ?[]const u8 = null,
    desc: []const u8 = "",
    required: bool = false,
    arg: ?Arg = null,
};

pub const CliConfig = struct {
    name: ?[]const u8 = null, // Name of the executable
    description: ?[]const u8 = null, // About text
    cmd_required: bool = false,
    suggestions: bool = false, // Turn on suggestions for typos
    auto_help: bool = false, // Handle '--help' option
    auto_version: bool = false, // Handle '--version' option
    help_max_width: usize = 80, // Max amount of text on a line
};

pub const CliApp = struct {
    config: CliConfig = .{},
    commands: []const Cmd = &[_]Cmd{},
    options: []const Opt = &[_]Opt{},
    positionals: []const PosArg = &[_]PosArg{},
};

pub const CmdVal = struct {
    cmd: *const Cmd,
    options: ?std.StaticStringMap(*const Opt),
};

pub const App = struct {
    cli: *const CliApp,
    commands: std.StaticStringMap(CmdVal),
    options: std.StaticStringMap(*const Opt),

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

    pub fn find_option(comptime self: *const App, opt: []const u8) !*const Opt {
        return self.options.get(opt) orelse error.InvalidOption;
    }
};

fn optionHashMap(
    comptime options: []const Opt,
) std.StaticStringMap(*const Opt) {
    const opts = comptime blk: {
        var count = 0;
        var opts_s: [options.len * 2]struct { []const u8, *const Opt } = undefined;
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
    return std.StaticStringMap(*const Opt).initComptime(opts);
}

/// Generate help text
pub fn get_help(
    allocator: std.mem.Allocator,
    comptime app: *const CliApp,
    command: ?*const Cmd,
    app_name: []const u8,
) ![]const u8 {
    const Wrap: type = struct {
        start_col: usize = 0,
        width: usize = 0,
        fn set_col(self: *@This(), col: usize) void {
            self.start_col = col;
            self.width = col;
        }
    };
    var wrap: Wrap = .{};
    var line_buf: [2048]u8 = undefined;
    var usage_buf = try std.ArrayList(u8).initCapacity(allocator, 2048);
    errdefer usage_buf.deinit(allocator);
    var buf = try std.ArrayList(u8).initCapacity(allocator, 2048);
    defer buf.deinit(allocator);

    const fmt_widths = comptime get_fmt_widths(app);
    const opt_fmt_width = fmt_widths.@"0";
    const arg_fmt_width = fmt_widths.@"1";

    if (app.config.description) |desc| try usage_buf.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "{s}\n\n", .{desc}),
    );
    const usage_wrap_offset = usage_buf.items.len;

    try usage_buf.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Usage: {s}", .{app_name}),
    );

    if (command) |cmd| {
        try usage_buf.appendSlice(allocator, try std.fmt.bufPrint(
            &line_buf,
            " {s}",
            .{cmd.name},
        ));
        try buf.append(allocator, '\n');
    } else if (app.commands.len > 0) {
        try usage_buf.appendSlice(allocator, " [command]");
        try buf.appendSlice(allocator, "\n\nCommands:\n\n");
        for (app.commands) |cmd| {
            var used: usize = 0;
            _ = try appendFmt(&line_buf, &used, "  {[name]s:<[width]} ", .{
                .name = cmd.name,
                .width = opt_fmt_width + arg_fmt_width + 7,
            });
            _ = try write_description(
                &line_buf,
                &used,
                app.config.help_max_width,
                cmd.desc,
            );
            try buf.appendSlice(allocator, line_buf[0..used]);
            try buf.append(allocator, '\n');
        }
    }

    const add_padding = struct {
        fn f(gpa: std.mem.Allocator, usage: *std.ArrayList(u8), b: []u8, w: *Wrap) !void {
            try usage.appendSlice(gpa, try std.fmt.bufPrint(b, "\n{[c]s:<[w]}", .{
                .c = "",
                .w = w.start_col,
            }));
            w.width = w.start_col;
        }
    }.f;

    // Handles adding options to help
    const handle_opt = struct {
        fn f(
            gpa: std.mem.Allocator,
            main_buf: *std.ArrayList(u8),
            usage: *std.ArrayList(u8),
            line: []u8,
            w: *Wrap,
            comptime max_width: usize,
            opt: *const Opt,
        ) !void {
            try main_buf.appendSlice(
                gpa,
                try opt_help_line(opt, line, opt_fmt_width, arg_fmt_width, max_width),
            );
            if (opt.required) {
                var used: usize = 0;
                _ = try appendFmt(line, &used, " --{s}", .{opt.long_name});
                var buf_t: [max_width]u8 = undefined;
                if (option_fmt_arg(opt, &buf_t)) |name|
                    _ = try appendFmt(line, &used, "={s}", .{name});
                if (w.width != w.start_col and w.width + used > max_width)
                    try add_padding(gpa, usage, &buf_t, w);
                w.width += used;
                try usage.appendSlice(gpa, line[0..used]);
            }
        }
    }.f;

    // General options
    if (app.options.len > 0) {
        try usage_buf.appendSlice(allocator, " [options]");
        wrap.set_col(usage_buf.items.len - usage_wrap_offset);
        try buf.appendSlice(allocator, "\nOptions:\n\n");
        for (app.options) |*opt| {
            try handle_opt(
                allocator,
                &buf,
                &usage_buf,
                &line_buf,
                &wrap,
                app.config.help_max_width,
                opt,
            );
        }
    } else wrap.set_col(usage_buf.items.len - usage_wrap_offset);

    // Command-specific options
    if (command) |cmd| if (cmd.options) |opts| {
        for (opts) |*opt| try handle_opt(
            allocator,
            &buf,
            &usage_buf,
            &line_buf,
            &wrap,
            app.config.help_max_width,
            opt,
        );
    };

    // Positional arguments
    var used: usize = 0;
    for (app.positionals) |pos| if (pos.required) {
        defer used = 0;
        if (wrap.width != wrap.start_col and
            wrap.width + pos.name.len > app.config.help_max_width)
            try add_padding(allocator, &usage_buf, &line_buf, &wrap);
        _ = try appendFmt(&line_buf, &used, " <{s}>", .{pos.name});
        wrap.width += used;
        try usage_buf.appendSlice(allocator, line_buf[0..used]);
    };
    if (command) |cmd| if (cmd.positionals) |pargs| {
        for (pargs) |pos| if (pos.required) {
            defer used = 0;
            if (wrap.width != wrap.start_col and
                wrap.width + pos.name.len > app.config.help_max_width)
                try add_padding(allocator, &usage_buf, &line_buf, &wrap);
            _ = try appendFmt(&line_buf, &used, " <{s}>", .{pos.name});
            wrap.width += used;
            try usage_buf.appendSlice(allocator, line_buf[0..used]);
        };
    };

    try usage_buf.appendSlice(allocator, buf.items);
    return usage_buf.toOwnedSlice(allocator);
}

fn get_fmt_widths(comptime app: *const CliApp) struct { comptime_int, comptime_int } {
    var checker = struct {
        opt_width: comptime_int = 0,
        arg_width: comptime_int = 0,
        fn check_widths(self: *@This(), opt: Opt) void {
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

fn opt_help_line(
    opt: *const Opt,
    buffer: []u8,
    comptime opt_width: comptime_int,
    comptime arg_width: comptime_int,
    comptime max_width: comptime_int,
) ![]const u8 {
    var arg_buf: [64]u8 = undefined;
    var used: usize = 0;
    if (opt.short_name) |short| {
        _ = try appendFmt(buffer, &used, "  -{s}, ", .{short});
    } else _ = try appendFmt(buffer, &used, "      ", .{});

    const arg_name = option_fmt_arg(opt, &arg_buf);
    _ = try appendFmt(
        buffer,
        &used,
        "--{[opt]s:<[optw]} {[arg]s:<[argw]} ",
        .{
            .opt = opt.long_name,
            .optw = opt_width,
            .arg = arg_name orelse "",
            .argw = arg_width,
        },
    );

    _ = try write_description(buffer, &used, max_width, opt.desc);

    if (opt.arg) |a| if (a.default) |d| {
        _ = try appendFmt(buffer, &used, " [default: {s}]", .{d});
    };
    _ = try appendFmt(buffer, &used, "\n", .{});
    return buffer[0..used];
}

fn option_fmt_arg(option: *const Opt, buffer: []u8) ?[]const u8 {
    if (option.arg) |arg| {
        return std.fmt.bufPrint(buffer, "<{s}{s}>", .{
            if (arg.required) "" else "?",
            arg.name,
        }) catch arg.name;
    }
    return null;
}

pub fn option_fmt_name(option: *const Opt, buffer: []u8) []const u8 {
    return std.fmt.bufPrint(
        buffer,
        "'--{s}'",
        .{option.long_name},
    ) catch option.long_name;
}

fn write_description(
    buffer: []u8,
    used: *usize,
    comptime max_width: usize,
    desc: []const u8,
) ![]u8 {
    const desc_start_col = used.*;
    const desc_line_width = max_width - desc_start_col;
    var written: usize = 0;
    while (desc.len - written > desc_line_width) {
        const len: usize = blk: {
            const cut = @min(written + desc_line_width, desc.len);
            if (std.mem.lastIndexOfScalar(u8, desc[written..cut], ' ')) |i|
                if (i > 0) break :blk written + i + 1;
            if (std.mem.indexOfScalar(u8, desc[cut..], ' ')) |i|
                if (i > 0) break :blk written + desc_line_width + i + 1;
            break :blk desc.len;
        };
        _ = try appendFmt(buffer, used, "{[desc]s}\n{[c]s:<[w]}", .{
            .desc = desc[written..len],
            .c = "",
            .w = desc_start_col,
        });
        written += len - written;
    }
    return try appendFmt(buffer, used, "{s}", .{desc[written..]});
}

pub fn appendFmt(
    buffer: []u8,
    written: *usize,
    comptime fmt: []const u8,
    args: anytype,
) std.fmt.BufPrintError![]u8 {
    const out = buffer[written.*..];
    const printed = try std.fmt.bufPrint(out, fmt, args);
    written.* += printed.len;
    return buffer[0..written.*];
}

pub fn validate_args_struct(comptime app: *const CliApp) App {
    // Check for duplicate option names
    const long_names = ensureUniqueStrings(
        Opt,
        "long_name",
        app.options,
        &[_][]const u8{},
    );
    const opt_names = ensureUniqueStrings(
        Opt,
        "short_name",
        app.options,
        long_names,
    );

    // Check for duplicate positional arguments
    const positionals = ensureUniqueStrings(
        PosArg,
        "name",
        app.positionals,
        &[_][]const u8{},
    );

    validate_commands(app.commands, opt_names, positionals);
    return App.initComptime(app);
}

fn validate_commands(
    comptime cmds: []const Cmd,
    comptime options: [][]const u8,
    comptime positionals: [][]const u8,
) void {
    inline for (cmds, 0..) |cmd_i, i| {
        if (cmd_i.options) |cmd_opts| {
            const long_names = ensureUniqueStrings(
                Opt,
                "long_name",
                cmd_opts,
                options,
            );
            _ = ensureUniqueStrings(Opt, "short_name", cmd_opts, long_names);

            if (cmd_i.positionals) |cmd_positionals| {
                _ = ensureUniqueStrings(
                    PosArg,
                    "name",
                    cmd_positionals,
                    positionals,
                );
            }
        }
        inline for (cmds[(i + 1)..]) |cmd_j| {
            if (std.mem.eql(u8, cmd_i.name, cmd_j.name)) {
                @compileError("Duplicate command name: " ++ cmd_i.name);
            }
        }
    }
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
        const value = blk: {
            if (info == .optional) {
                if (field_value) |v| break :blk v;
                continue;
            } else break :blk field_value;
        };

        if (value.len == 0 or std.mem.indexOfScalar(u8, value, ' ') != null) {
            @compileError("Invalid " ++ @typeName(T) ++ "." ++ field_name ++
                " value: \"" ++ value ++ "\". \nCannot be empty or contain whitespace");
        }
        names[count] = value;
        count += 1;
    }
    const slice = names[0..count];

    comptime {
        const log2_n: comptime_int =
            if (len > 0) @intFromFloat(std.math.log2(@as(f64, len))) else 0;
        const quota = len * len * len * log2_n;
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
            @compileError("Duplicate " ++ @typeName(T) ++ "." ++ field_name ++
                " value found: \"" ++ name ++ "\"");
        }
    };
    return slice;
}
