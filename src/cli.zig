const std = @import("std");
pub const cmd = @import("cmd.zig");
pub const arg = @import("arg.zig");
const result = @import("result");
const utils = @import("utils");

pub const Cmd = cmd.Cmd;
pub const Option = cmd.Option;

const ErrorWrap = result.ErrorWrap;
pub const ResultCli = result.Result(*Cli, ErrorWrap);

pub const ArgsError = error{
    NoCommand,
    NoGlobalArgs,
    UnknownOption,
    UnknownCommand,
    NoOptionValue,
    OptionHasNoArg,
    NoRequiredOption,
    TooManyArgs,
    DuplicateOption,
};

pub const Cli = struct {
    cmd: ?cmd.Cmd = null,
    args: ?std.ArrayList(cmd.Option) = null,
    global_args: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !*Cli {
        const cli = try allocator.create(Cli);
        cli.* = .{};
        return cli;
    }

    pub fn deinit(self: *Cli, allocator: std.mem.Allocator) void {
        if (self.args) |*args| {
            args.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn find_opt(self: *Cli, opt_name: []const u8) ?*cmd.Option {
        if (self.args == null) return null;
        for (self.args.?.items) |*option| {
            if (std.mem.eql(u8, option.long_name, opt_name)) {
                return option;
            }
        }
        return null;
    }

    fn add_opt(self: *Cli, allocator: std.mem.Allocator, opt: cmd.Option) !void {
        if (self.args == null) {
            self.args = try std.ArrayList(cmd.Option).initCapacity(allocator, 5);
        }
        try self.args.?.append(allocator, opt);
    }

    fn add_unique(self: *Cli, allocator: std.mem.Allocator, opt: cmd.Option) ArgsError!void {
        const option = self.find_opt(opt.long_name);
        if (option != null) return ArgsError.DuplicateOption;
        self.add_opt(allocator, opt) catch {};
    }
};

fn missing_required_opts(allocator: std.mem.Allocator, cli: *Cli, app: *const cmd.ArgsStructure) !?[]*const cmd.Option {
    var missing_opts = try std.ArrayList(*const cmd.Option).initCapacity(allocator, 5);
    defer missing_opts.deinit(allocator);
    for (app.options) |*opt| {
        if (!opt.required) continue;
        var found = false;
        if (cli.args == null) {
            missing_opts.append(allocator, opt) catch {};
            continue;
        }
        for (cli.args.?.items) |o| {
            if (std.mem.eql(u8, o.long_name, opt.long_name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            missing_opts.append(allocator, opt) catch {};
        }
    }
    if (missing_opts.items.len == 0) return null;
    return missing_opts.toOwnedSlice(allocator) catch return null;
}

pub fn validate_parsed_args(allocator: std.mem.Allocator, args: []const arg.ArgParse, app: *const cmd.ArgsStructure) !ResultCli {
    var cli = try Cli.init(allocator);
    var opt_empty: ?cmd.Option = null;
    var opt_type: ?arg.OptType = null;
    for (args, 0..) |a, i| {
        switch (a) {
            .option => {
                if (cli.cmd == null and app.cmd_required) {
                    return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.NoCommand, "", .{}));
                }
                if (opt_empty) |opt_e| {
                    if (!opt_e.arg.?.required) {
                        cli.add_unique(allocator, opt_e) catch |err| {
                            return ResultCli.wrap_err(ErrorWrap.create(allocator, err, "{s}{s}", switch (opt_type.?) {
                                .long => .{ "--", opt_e.long_name },
                                .short => .{ "-", opt_e.short_name.? },
                            }));
                        };
                        opt_empty = null;
                        opt_type = null;
                    } else {
                        return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                            .long => .{ "--", opt_e.long_name },
                            .short => .{ "-", opt_e.short_name orelse "" },
                        }));
                    }
                }
                var opt = app.find_option(a.option.name, a.option.option_type) catch {
                    return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.UnknownOption, "{s}{s}", .{ switch (a.option.option_type) {
                        .long => "--",
                        .short => "-",
                    }, a.option.name }));
                };
                if (opt.arg) |*opt_arg| {
                    if (a.option.value == null) {
                        opt_empty = opt;
                        opt_type = a.option.option_type;
                    } else {
                        opt_arg.value = a.option.value;
                        cli.add_unique(allocator, opt) catch |err| {
                            return ResultCli.wrap_err(ErrorWrap.create(allocator, err, "{s}{s}", .{
                                switch (a.option.option_type) {
                                    .long => "--",
                                    .short => "-",
                                },
                                a.option.name,
                            }));
                        };
                    }
                    continue;
                }
                if (a.option.value) |_| {
                    return ResultCli.wrap_err(ErrorWrap.create(
                        allocator,
                        ArgsError.OptionHasNoArg,
                        "{s}{s}",
                        .{ switch (a.option.option_type) {
                            .long => "--",
                            .short => "-",
                        }, a.option.name },
                    ));
                }
                cli.add_unique(allocator, opt) catch |err| {
                    return ResultCli.wrap_err(ErrorWrap.create(allocator, err, "{s}{s}", .{
                        switch (a.option.option_type) {
                            .long => "--",
                            .short => "-",
                        },
                        a.option.name,
                    }));
                };
            },
            .value => {
                if (cli.cmd == null and i == 0) {
                    const c = app.find_cmd(a.value) catch {
                        return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.UnknownCommand, "{s}", .{a.value}));
                    };
                    cli.cmd = c;
                } else if (opt_empty) |*opt_e| {
                    opt_e.arg.?.value = a.value;
                    cli.add_unique(allocator, opt_e.*) catch |err| {
                        return ResultCli.wrap_err(ErrorWrap.create(allocator, err, "{s}{s}", switch (opt_type.?) {
                            .long => .{ "--", opt_e.long_name },
                            .short => .{ "-", opt_e.short_name orelse "" },
                        }));
                    };
                    opt_empty = null;
                    opt_type = null;
                } else if (cli.global_args == null) {
                    cli.global_args = a.value;
                } else {
                    return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.TooManyArgs, "{s}", .{a.value}));
                }
            },
        }
    }
    if (cli.cmd == null and app.cmd_required) {
        return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.NoCommand, "", .{}));
    }
    if (opt_empty) |opt_e| {
        if (opt_e.arg.?.required) {
            return ResultCli.wrap_err(ErrorWrap.create(allocator, ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                .long => .{ "--", opt_e.long_name },
                .short => .{ "-", opt_e.short_name orelse "" },
            }));
        }
        cli.add_unique(allocator, opt_e) catch |err| {
            return ResultCli.wrap_err(ErrorWrap.create(allocator, err, "{s}{s}", switch (opt_type.?) {
                .long => .{ "--", opt_e.long_name },
                .short => .{ "-", opt_e.short_name orelse "" },
            }));
        };
    }
    const missing_opts = try missing_required_opts(allocator, cli, app);
    if (missing_opts != null) {
        return ResultCli.wrap_err(ErrorWrap.create(
            allocator,
            ArgsError.NoRequiredOption,
            "[{s}]",
            .{try utils.format_slice(
                *const cmd.Option,
                missing_opts.?,
                allocator,
                cmd.Option.get_format_name,
            )},
        ));
    }
    return ResultCli.wrap_ok(cli);
}
