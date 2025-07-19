const std = @import("std");
const cmd = @import("cmd");
const arg = @import("arg");

pub const Cli = struct {
    cmd: ?cmd.Cmd = null,
    args: ?std.ArrayList(cmd.Option) = null,
    global_args: ?[]const u8 = null,
};

pub const ArgsError = error{ NoCommand, NoGlobalArgs };

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

pub fn validate_parsed_args(args: []const arg.ArgParse, app: *const cmd.ArgsStructure) ArgsError!Cli {
    var cli = Cli{};
    var opt_empty: ?cmd.Option = null;
    for (args, 0..) |a, i| {
        switch (a) {
            .option => {},
            .value => {},
        }
    }
    if (cli.cmd == null) {
        return ArgsError.NoCommand;
    }
    if (cli.global_args == null) {
        return ArgsError.NoGlobalArgs;
    }
    return cli;
}
