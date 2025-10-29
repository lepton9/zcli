const std = @import("std");
const zcli = @import("zcli");

pub const Cli = zcli.Cli;
pub const Cmd = zcli.Cmd;
pub const Option = zcli.Option;
pub const CliApp = zcli.CliApp;
pub const ArgsError = zcli.ArgsError;

const app = CliApp{
    .cmd_required = false,
    .commands = &commands,
    .options = &options,
};

test "help" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--help") };
    const cli = try zcli.parse_from(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(cli.find_opt("help") != null);
}

test "cmd" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--text"),
        @constCast("value"),
        @constCast("--any"),
        @constCast("arg"),
    };
    const cli = try zcli.parse_from(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(std.mem.eql(u8, cli.cmd.?.name, "test"));
    try std.testing.expect(
        std.mem.eql(u8, cli.find_opt("text").?.arg.?.value.?, "value"),
    );
    try std.testing.expect(
        std.mem.eql(u8, cli.find_opt("any").?.arg.?.value.?, "arg"),
    );
}

test "default" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("--default"),
        @constCast("--option"),
    };
    const cli = try zcli.parse_from(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(
        std.mem.eql(u8, cli.find_opt("default").?.arg.?.value.?, "value"),
    );
    try std.testing.expect(cli.find_opt("option").?.arg.?.value == null);
}

test "global_arg" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("value"),
    };
    const cli = try zcli.parse_from(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(
        std.mem.eql(u8, cli.global_arg.?, "value"),
    );
}

test "invalid_command" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .cmd_required = true,
        .commands = &[_]Cmd{.{ .name = "test" }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("invalid") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownCommand);
}

test "invalid_option" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--invalid") };
    const cli = zcli.parse_from(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "cmd_option" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--any") };
    const cli = zcli.parse_from(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "missing_command" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .cmd_required = true,
        .commands = &[_]Cmd{.{ .name = "test" }},
    };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.NoCommand);
}

test "missing_option" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Option{.{ .long_name = "option", .required = true }},
    };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.NoRequiredOption);
}

const commands = [_]Cmd{
    .{
        .name = "test",
        .desc = "Testing command",
        .options = &[_]Option{
            .{
                .long_name = "any",
                .short_name = "a",
                .desc = "Any input",
                .required = false,
                .arg = .{ .name = "any", .type = .Any },
            },
            .{
                .long_name = "text",
                .short_name = "t",
                .desc = "Text input",
                .required = false,
                .arg = .{ .name = "text", .type = .Text },
            },
            .{
                .long_name = "path",
                .short_name = "p",
                .desc = "Path input",
                .required = false,
                .arg = .{ .name = "path", .type = .Path },
            },
        },
    },
};

const options = [_]Option{
    .{
        .long_name = "default",
        .short_name = null,
        .desc = "Default value",
        .required = false,
        .arg = .{ .name = "arg", .default = "value" },
    },
    .{
        .long_name = "option",
        .short_name = "o",
        .desc = "Option",
        .required = false,
        .arg = .{ .name = "arg", .required = false },
    },
    .{
        .long_name = "help",
        .short_name = "h",
        .desc = "Print help",
        .required = false,
        .arg = null,
    },
};
