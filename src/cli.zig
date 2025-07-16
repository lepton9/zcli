const cmd = @import("cmd");
const arg = @import("arg");

pub const Cli = struct {
    cmd: ?cmd.Cmd = null,
    args: ?[]cmd.Option = null,
    global_args: ?[]const u8 = null,
};

pub const ArgsError = error{ NoCommand, NoGlobalArgs };

pub fn validate_parsed_args(args: []const arg.ArgParse) ArgsError!Cli {
    const cli = Cli{};
    for (args) |a| {
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
