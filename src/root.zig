const std = @import("std");
const cli = @import("cli.zig");
const parse = @import("parse.zig");
const arg = @import("arg.zig");

test {
    std.testing.refAllDecls(@This());
}

pub const complete = @import("completion.zig");

pub const ArgsError = cli.ArgsError;
pub const Cli = cli.Cli;
pub const Command = cli.Command;
pub const Option = cli.Option;
pub const Positional = cli.Positional;
pub const OptionValue = cli.OptionValue;
pub const ExclusiveArg = cli.ExclusiveArg;
pub const PosArg = arg.PosArg;
pub const Arg = arg.Arg;
pub const Cmd = arg.Cmd;
pub const Opt = arg.Opt;
pub const CliApp = arg.CliApp;
pub const CliConfig = arg.CliConfig;

const Validator = cli.Validator;

/// Parses the CLI arguments and handles parse errors.
///
/// Handles options `help` and `version` if enabled in `CliConfig`.
pub fn parseInit(init: std.process.Init, comptime app: *const arg.CliApp) !*Cli {
    return parseArgs(init.io, init.gpa, init.minimal.args, app);
}

/// Parses the CLI arguments and handles parse errors.
///
/// Handles options `help` and `version` if enabled in `CliConfig`.
pub fn parseArgs(
    io: std.Io,
    gpa: std.mem.Allocator,
    args: std.process.Args,
    comptime app: *const arg.CliApp,
) !*Cli {
    const cli_app = comptime arg.validate_args_struct(app);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const args_slice = try args.toSlice(arena.allocator());

    const app_name = app.config.name orelse std.fs.path.basename(
        std.mem.span(args_slice[0].ptr),
    );
    var validator: Validator = .{ .allocator = gpa };

    const cli_ = parse_cli(gpa, args_slice, &validator, &cli_app) catch |err|
        try handle_err(gpa, &cli_app, &validator, null, app_name, err);
    errdefer cli_.deinit(gpa);

    try handle_cli(io, gpa, cli_, &cli_app, app_name);

    validator.validate_cli(cli_, &cli_app) catch |err|
        try handle_err(gpa, &cli_app, &validator, cli_.cmd, app_name, err);

    return cli_;
}

/// Parses the command-line interface (CLI) arguments.
///
/// This function provides more control over the parsing errors.
pub fn parseFrom(
    gpa: std.mem.Allocator,
    args: []const [:0]const u8,
    comptime app: *const arg.CliApp,
) !*Cli {
    const cli_app = comptime arg.validate_args_struct(app);
    var validator: Validator = .{ .allocator = gpa };
    const cli_ = try parse_cli(gpa, args, &validator, &cli_app);
    errdefer cli_.deinit(gpa);
    try validator.validate_cli(cli_, &cli_app);
    return cli_;
}

fn parse_cli(
    gpa: std.mem.Allocator,
    args: []const [:0]const u8,
    validator: *Validator,
    comptime app: *const arg.App,
) !*Cli {
    std.debug.assert(args.len > 0);
    const parsed_args = try parse.parse_args(gpa, args[1..]);
    defer gpa.free(parsed_args);

    var cli_ = try Cli.init(gpa);
    errdefer cli_.deinit(gpa);
    try cli.build_cli(validator, cli_, parsed_args, app);
    return cli_;
}

fn handle_cli(
    io: std.Io,
    gpa: std.mem.Allocator,
    cli_: *Cli,
    comptime app: *const arg.App,
    app_name: []const u8,
) !void {
    if (app.cli.config.auto_help) if (cli_.findOption("help")) |_| {
        defer cli_.deinit(gpa);
        try help(io, gpa, app, cli_.cmd, app_name, .{});
        std.process.exit(0);
    };
    if (app.cli.config.auto_version) if (cli_.findOption("version")) |_| {
        if (@import("options").version_tag) |version| {
            var buf: [32]u8 = undefined;
            try write(io, try std.fmt.bufPrint(&buf, "{s}\n", .{version}), .{});
            std.process.exit(0);
        }
    };
}

fn help(
    io: std.Io,
    gpa: std.mem.Allocator,
    comptime app: *const arg.App,
    command: ?Command,
    app_name: []const u8,
    opts: WriteOptions,
) !void {
    const cmd = if (command) |cmd| try app.find_cmd(cmd.name) else null;
    const usage = try arg.get_help(gpa, app.cli, cmd, app_name);
    defer gpa.free(usage);
    try write(io, usage, opts);
}

/// Write to stdout with format
fn fmtWrite(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const stdout = &writer.interface;
    try stdout.print(fmt, args);
    try stdout.flush();
}

const WriteOptions = struct {
    newline_end: bool = false,
};

/// Write all the data to stdout
fn write(io: std.Io, bytes: []const u8, opts: WriteOptions) !void {
    return fmtWrite(io, "{s}{s}", .{ bytes, if (opts.newline_end) "\n" else "" });
}

fn handle_err(
    allocator: std.mem.Allocator,
    comptime app: *const arg.App,
    validator: *Validator,
    command: ?Command,
    app_name: []const u8,
    err: anyerror,
) !noreturn {
    if (app.cli.config.help_on_error) {
        help(allocator, app, command, app_name, .{ .newline_end = true }) catch {};
    }

    switch (err) {
        cli.ArgsError.UnknownCommand => {
            if (validator.suggestion) |sug| {
                std.log.err("Unknown command: '{s}'. Did you mean '{s}'?\n", .{
                    validator.get_err_ctx(),
                    sug,
                });
            } else std.log.err("Unknown command: '{s}'", .{validator.get_err_ctx()});
        },
        cli.ArgsError.UnknownOption => {
            if (validator.suggestion) |sug| {
                std.log.err("Unknown option: '{s}'. Did you mean '{s}'?\n", .{
                    validator.get_err_ctx(),
                    sug,
                });
            } else std.log.err("Unknown option: '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.UnknownPositional => {
            std.log.err("Unknown argument: '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.NoCommand => {
            std.log.err("No command given\n", .{});
        },
        cli.ArgsError.MissingOptionValue => {
            std.log.err("No option value given for '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.OptionHasNoArg => {
            std.log.err("Option doesn't take arguments: '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.InvalidOptionArgType => {
            std.log.err("Invalid option value: {s}\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.DuplicateOption => {
            std.log.err("Duplicate option: '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.MutuallyExclusive => {
            std.log.err("Mutually exclusive arguments: {s}\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.MissingOption => {
            std.log.err("Required options not given: {s}\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.MissingPositional => {
            std.log.err("Missing positional arguments: {s}\n", .{validator.get_err_ctx()});
        },
        else => return err,
    }
    std.process.exit(1);
}
