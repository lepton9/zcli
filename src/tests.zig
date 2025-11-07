const std = @import("std");
const zcli = @import("zcli");

const expect = std.testing.expect;

pub const Cli = zcli.Cli;
pub const Cmd = zcli.Cmd;
pub const PosArg = zcli.PosArg;
pub const Opt = zcli.Opt;
pub const CliApp = zcli.CliApp;
pub const ArgsError = zcli.ArgsError;

const app: CliApp = .{
    .config = .{
        .cmd_required = false,
        .auto_help = true,
    },
    .commands = &commands,
    .options = &options,
    .positionals = &positionals,
};

test "empty" {
    const allocator = std.testing.allocator;
    const app_test: CliApp = .{};
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = try zcli.parse_from(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(cli.cmd == null);
    try expect(cli.args.count() == 0);
    try expect(cli.positionals.items.len == 0);
}

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
        std.mem.eql(u8, cli.find_opt("text").?.value.?.string, "value"),
    );
    try std.testing.expect(
        std.mem.eql(u8, cli.find_opt("any").?.value.?.string, "arg"),
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
        std.mem.eql(u8, cli.find_opt("default").?.value.?.string, "value"),
    );
    try std.testing.expect(cli.find_opt("option").?.value == null);
}

test "positional_arg" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("value"),
    };
    const cli = try zcli.parse_from(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(
        std.mem.eql(u8, cli.positionals.items[0].value, "value"),
    );
}

test "double_dash_positional" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("--"),
        @constCast("--help"),
    };
    const cli = try zcli.parse_from(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(
        std.mem.eql(u8, cli.positionals.items[0].value, "--help"),
    );
}

test "multiple_positional_values" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .positionals = &[_]PosArg{.{ .name = "arg", .multiple = true }},
    };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("value1"),
        @constCast("value2"),
        @constCast("value3"),
    };
    const cli = try zcli.parse_from(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(cli.positionals.items.len == 3);
    try expect(std.mem.eql(u8, cli.positionals.items[0].value, "value1"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].value, "value2"));
    try expect(std.mem.eql(u8, cli.positionals.items[2].value, "value3"));
}

test "multiple_positionals" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .positionals = &[_]PosArg{
        .{ .name = "arg1", .multiple = false },
        .{ .name = "arg2", .multiple = true },
    } };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("value1"),
        @constCast("value2"),
        @constCast("value3"),
    };
    const cli = try zcli.parse_from(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(cli.positionals.items.len == 3);
    try expect(std.mem.eql(u8, cli.positionals.items[0].name, "arg1"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].name, "arg2"));
    try expect(std.mem.eql(u8, cli.positionals.items[2].name, "arg2"));
}

test "command_specific_positionals" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .commands = &[_]Cmd{
        .{
            .name = "cmd",
            .positionals = &[_]PosArg{
                .{ .name = "arg", .required = true, .multiple = true },
            },
        },
    } };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("cmd"),
        @constCast("value1"),
        @constCast("value2"),
    };
    const cli = try zcli.parse_from(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(std.mem.eql(u8, cli.cmd.?.name, "cmd"));
    try expect(cli.positionals.items.len == 2);
    try expect(std.mem.eql(u8, cli.positionals.items[0].name, "arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[0].value, "value1"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].name, "arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].value, "value2"));
}

test "command_and_general_positionals" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .config = .{ .cmd_required = true },
        .commands = &[_]Cmd{
            .{
                .name = "cmd",
                .positionals = &[_]PosArg{
                    .{ .name = "cmd_arg", .required = true, .multiple = false },
                },
            },
        },
        .positionals = &[_]PosArg{
            .{ .name = "global_arg", .required = true, .multiple = false },
        },
    };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("cmd"),
        @constCast("cmd_pos_arg"),
        @constCast("pos_arg"),
    };
    const cli = try zcli.parse_from(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(std.mem.eql(u8, cli.cmd.?.name, "cmd"));
    try expect(cli.positionals.items.len == 2);
    try expect(std.mem.eql(u8, cli.positionals.items[0].name, "cmd_arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[0].value, "cmd_pos_arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].name, "global_arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].value, "pos_arg"));
}

test "invalid_command" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .config = .{ .cmd_required = true },
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
        .config = .{ .cmd_required = true },
        .commands = &[_]Cmd{.{ .name = "test" }},
    };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.NoCommand);
}

test "missing_option" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .required = true }},
    };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.MissingOption);
}

test "missing_opt_value" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .options = &[_]Opt{
        .{ .long_name = "option", .arg = .{
            .name = "arg",
            .required = true,
        } },
    } };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--option") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.MissingOptionValue);
}

test "option_arg_null" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .arg = null }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--option=value") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.OptionHasNoArg);
}

test "invalid_option_arg_bool" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--bool=asd"),
    };
    const cli = zcli.parse_from(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.InvalidOptionArgType);
}

test "invalid_option_arg_int" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--float=1.2a"),
    };
    const cli = zcli.parse_from(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.InvalidOptionArgType);
}

test "invalid_option_arg_float" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--int=1a"),
    };
    const cli = zcli.parse_from(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.InvalidOptionArgType);
}

test "duplicate_option" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .options = &[_]Opt{.{ .long_name = "option" }} };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("--option"),
        @constCast("--option"),
    };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.DuplicateOption);
}

test "duplicate_option_short" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .options = &[_]Opt{
        .{ .long_name = "option", .short_name = "o" },
    } };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("--option"),
        @constCast("-o"),
    };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.DuplicateOption);
}

test "unknown_option_long" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .short_name = "o" }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--o") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "unknown_option_short" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .short_name = "o" }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("-option") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "invalid_positional" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{};
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("argument") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownPositional);
}

test "missing_positional" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .positionals = &[_]PosArg{.{
        .name = "arg",
        .required = true,
    }} };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.MissingPositional);
}

test "missing_command_positional" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .commands = &[_]Cmd{.{
        .name = "cmd",
        .positionals = &[_]PosArg{
            .{ .name = "arg", .required = true },
        },
    }} };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("cmd") };
    const cli = zcli.parse_from(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.MissingPositional);
}

const commands = [_]Cmd{
    .{
        .name = "test",
        .desc = "Testing command",
        .options = &[_]Opt{
            .{
                .long_name = "any",
                .short_name = "a",
                .desc = "Any input",
                .arg = .{ .name = "any", .type = .Any },
            },
            .{
                .long_name = "text",
                .short_name = "t",
                .desc = "Text input",
                .arg = .{ .name = "text", .type = .Text },
            },
            .{
                .long_name = "path",
                .short_name = "p",
                .desc = "Path input",
                .arg = .{ .name = "path", .type = .Path },
            },
            .{
                .long_name = "bool",
                .short_name = "b",
                .arg = .{ .name = "bool", .type = .Bool },
            },
            .{
                .long_name = "int",
                .short_name = "i",
                .arg = .{ .name = "int", .type = .Int },
            },
            .{
                .long_name = "float",
                .short_name = "f",
                .arg = .{ .name = "float", .type = .Float },
            },
        },
        .positionals = null,
    },
};

const options = [_]Opt{
    .{
        .long_name = "option",
        .short_name = "o",
        .desc = "Option",
        .required = false,
        .arg = .{ .name = "arg", .required = false },
    },
    .{
        .long_name = "default",
        .short_name = null,
        .desc = "Default value",
        .required = false,
        .arg = .{ .name = "arg", .default = "value" },
    },
    .{
        .long_name = "help",
        .short_name = "h",
        .desc = "Print help",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "version",
        .short_name = "V",
        .desc = "Print version",
        .required = false,
        .arg = null,
    },
};

const positionals = [_]PosArg{
    .{
        .name = "positional",
        .required = false,
    },
};
