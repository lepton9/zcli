const std = @import("std");
const cli = @import("cli.zig");
const parse = @import("parse.zig");
const arg = @import("arg.zig");

pub const complete = @import("completion.zig");

pub const ArgsError = cli.ArgsError;
pub const Cli = cli.Cli;
pub const PosArg = arg.PosArg;
pub const Arg = arg.Arg;
pub const Cmd = arg.Cmd;
pub const Option = arg.Option;
pub const CliApp = arg.CliApp;

const Validator = cli.Validator;

pub fn parse_args(
    allocator: std.mem.Allocator,
    comptime app: *const arg.CliApp,
) !*Cli {
    const args_cli = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args_cli);

    var validator = try Validator.init(allocator);
    defer validator.deinit();

    const cli_ = parse_cli(allocator, app, validator, args_cli) catch |err| {
        try handle_err(validator, err);
        std.process.exit(1);
    };

    if (cli_.find_opt("help")) |_| {
        defer cli_.deinit(allocator);
        const app_name = app.exe_name orelse std.fs.path.basename(
            std.mem.span(args_cli[0].ptr),
        );
        try help(allocator, app, cli_.cmd, app_name);
        std.process.exit(0);
    }
    return cli_;
}

pub fn parse_from(
    allocator: std.mem.Allocator,
    comptime app: *const arg.CliApp,
    args_cli: [][:0]u8,
) !*Cli {
    var validator = try Validator.init(allocator);
    defer validator.deinit();
    return parse_cli(allocator, app, validator, args_cli);
}

fn parse_cli(
    allocator: std.mem.Allocator,
    comptime app: *const arg.CliApp,
    validator: *Validator,
    args_cli: [][:0]u8,
) !*Cli {
    const cli_app = comptime arg.validate_args_struct(app);
    const args = try parse.parse_args(allocator, args_cli[1..]);
    defer allocator.free(args);
    var cli_ = try Cli.init(allocator);
    errdefer cli_.deinit(allocator);
    try validator.validate_parsed_args(cli_, args, &cli_app);
    return cli_;
}

fn help(
    allocator: std.mem.Allocator,
    comptime app: *const arg.CliApp,
    command: ?Cmd,
    app_name: []const u8,
) !void {
    const usage = try arg.get_help(allocator, app, command, app_name);
    defer allocator.free(usage);
    try write_stdout(usage);
}

fn write_stdout(data: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    const stdout = &writer.interface;
    try stdout.writeAll(data);
    try stdout.flush();
}

fn handle_err(validator: *Validator, err: anyerror) !void {
    switch (err) {
        cli.ArgsError.UnknownCommand => {
            std.log.err("Unknown command: '{s}'", .{validator.get_err_ctx()});
        },
        cli.ArgsError.UnknownOption => {
            std.log.err("Unknown option: '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.UnknownPositional => {
            std.log.err("Unknown positional argument: '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.NoCommand => {
            std.log.err("No command given\n", .{});
        },
        cli.ArgsError.NoOptionValue => {
            std.log.err("No option value for option '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.OptionHasNoArg => {
            std.log.err("Option doesn't take any arguments '{s}'\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.NoRequiredOption => {
            std.log.err("Required options not given: {s}\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.NoRequiredPositional => {
            std.log.err("Missing positional arguments: {s}\n", .{validator.get_err_ctx()});
        },
        cli.ArgsError.DuplicateOption => {
            std.log.err("Duplicate option: '{s}'\n", .{validator.get_err_ctx()});
        },
        else => return err,
    }
}
