const std = @import("std");
const cli = @import("cli.zig");
const parse = @import("parse.zig");
const arg = @import("arg.zig");

pub const complete = @import("completion.zig");

pub const ArgsError = cli.ArgsError;
pub const Cli = cli.Cli;
pub const Arg = arg.Arg;
pub const Cmd = arg.Cmd;
pub const Option = arg.Option;
pub const ArgsStructure = arg.ArgsStructure;

const Validator = cli.Validator;

pub fn parse_args(
    allocator: std.mem.Allocator,
    comptime app: *const arg.ArgsStructure,
) !*Cli {
    const args_cli = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args_cli);
    return parse_from(allocator, app, args_cli);
}

pub fn parse_from(
    allocator: std.mem.Allocator,
    comptime app: *const arg.ArgsStructure,
    args_cli: [][:0]u8,
) !*Cli {
    comptime arg.validate_args_struct(app);
    const args = try parse.parse_args(allocator, args_cli[1..]);
    defer allocator.free(args);

    var validator = try Validator.init(allocator);
    defer validator.deinit();
    var cli_ = try Cli.init(allocator);

    validator.validate_parsed_args(cli_, args, app) catch {
        cli_.deinit(allocator);
        std.process.exit(1);
    };

    return cli_;
}
