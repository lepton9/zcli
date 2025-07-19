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
};

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
