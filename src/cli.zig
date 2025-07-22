const std = @import("std");
const cmd = @import("cmd");
const arg = @import("arg");
const result = @import("result");

const ErrorWrap = result.ErrorWrap;
const ResultCli = result.Result(Cli, ErrorWrap);

pub const ArgsError = error{
    NoCommand,
    NoGlobalArgs,
    UnknownOption,
    UnknownCommand,
    NoOptionValue,
    NoRequiredOption,
    TooManyArgs,
    DuplicateOption,
};

pub const Cli = struct {
    cmd: ?cmd.Cmd = null,
    args: ?std.ArrayList(cmd.Option) = null,
    global_args: ?[]const u8 = null,
};

pub fn add_opt(cli: *Cli, opt: cmd.Option) void {
    if (cli.args == null) {
        cli.args = std.ArrayList(cmd.Option).init(std.heap.page_allocator);
    }
    cli.args.?.append(opt) catch {};
}

pub fn find_opt(cli: *Cli, opt_name: []const u8) ?*cmd.Option {
    if (cli.args == null) return null;
    for (cli.args.?.items) |*option| {
        if (std.mem.eql(u8, option.long_name, opt_name)) {
            return option;
        }
    }
    return null;
}

pub fn add_unique(cli: *Cli, opt: cmd.Option) ArgsError!void {
    const option = find_opt(cli, opt.long_name);
    if (option != null) return ArgsError.DuplicateOption;
    add_opt(cli, opt);
}

pub fn validate_required_options(cli: *Cli, app: *const cmd.ArgsStructure) bool {
    for (app.options) |opt| {
        if (!opt.required) continue;
        if (cli.args == null) return false;
        var found = false;
        for (cli.args.?.items) |o| {
            if (std.mem.eql(u8, o.long_name, opt.long_name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

pub fn validate_parsed_args(args: []const arg.ArgParse, app: *const cmd.ArgsStructure) ResultCli {
    var cli = Cli{};
    var opt_empty: ?cmd.Option = null;
    for (args, 0..) |a, i| {
        switch (a) {
            .option => {
                if (cli.cmd == null and app.cmd_required) {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoCommand, "No command given", .{}));
                }
                if (opt_empty != null) {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoOptionValue, "No value for option {s}", .{opt_empty.?.long_name}));
                }
                const opt = cmd.find_option(app, a.option.name, a.option.option_type) catch {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.UnknownOption, "{s}", .{a.option.name}));
                };
                if (a.option.value == null and opt.arg_name != null) {
                    opt_empty = opt;
                } else {
                    add_unique(&cli, opt) catch |err| {
                        return ResultCli.wrap_err(ErrorWrap.create(err, "{s}", .{opt.long_name}));
                    };
                }
            },
            .value => {
                if (cli.cmd == null and i == 0) {
                    const c = cmd.find_cmd(app, a.value) catch {
                        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.UnknownCommand, "{s}", .{a.value}));
                    };
                    cli.cmd = c;
                } else if (opt_empty != null) {
                    opt_empty.?.arg_value = a.value;
                    add_unique(&cli, opt_empty.?) catch |err| {
                        return ResultCli.wrap_err(ErrorWrap.create(err, "{s}", .{opt_empty.?.long_name}));
                    };
                    opt_empty = null;
                } else if (cli.global_args == null) {
                    cli.global_args = a.value;
                } else {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.TooManyArgs, "{s}", .{a.value}));
                }
            },
        }
    }
    if (cli.cmd == null and app.cmd_required) {
        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoCommand, "", .{}));
    }
    if (opt_empty != null) {
        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoOptionValue, "{s}", .{opt_empty.?.long_name}));
    }
    if (!validate_required_options(&cli, app)) {
        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoRequiredOption, "", .{}));
    }
    return ResultCli.wrap_ok(cli);
}
