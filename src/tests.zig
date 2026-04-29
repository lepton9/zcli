const std = @import("std");
const zcli = @import("zcli");

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

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
    const cli = try zcli.parseFrom(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(cli.cmd == null);
    try expect(cli.args.count() == 0);
    try expect(cli.positionals.items.len == 0);
}

test "help" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--help") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(cli.findOption("help") != null);
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
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(std.mem.eql(u8, cli.cmd.?.name, "test"));
    try std.testing.expect(
        std.mem.eql(u8, cli.findOption("text").?.value.?.string, "value"),
    );
    try std.testing.expect(
        std.mem.eql(u8, cli.findOption("any").?.value.?.string, "arg"),
    );
}

test "default" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("--default"),
        @constCast("--option"),
    };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try std.testing.expect(
        std.mem.eql(u8, cli.findOption("default").?.value.?.string, "value"),
    );
    try std.testing.expect(cli.findOption("option").?.value == null);
}

test "option_arg_bool_true" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("test"), @constCast("--bool=true") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("bool").?.value.?.bool == true);
}

test "option_arg_bool_false" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("test"), @constCast("--bool=false") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("bool").?.value.?.bool == false);
}

test "option_arg_bool_1" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("test"), @constCast("--bool=1") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("bool").?.value.?.bool == true);
}

test "option_arg_bool_0" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("test"), @constCast("--bool=0") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("bool").?.value.?.bool == false);
}

test "option_arg_bool_y" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("test"), @constCast("--bool=y") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("bool").?.value.?.bool == true);
}

test "option_arg_bool_n" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("test"), @constCast("--bool=n") };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("bool").?.value.?.bool == false);
}

test "option_arg_int" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--int=123"),
    };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("int").?.value.?.int == 123);
}

test "option_arg_float" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--float=1.23"),
    };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("float").?.value.?.float == 1.23);
}

test "option_arg_int_neg" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--int"),
        @constCast("-123"),
    };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("int").?.value.?.int == -123);
}

test "option_arg_float_neg" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--float"),
        @constCast("-1.23"),
    };
    const cli = try zcli.parseFrom(allocator, &app, &args);
    defer cli.deinit(allocator);
    try expect(cli.findOption("float").?.value.?.float == -1.23);
}

test "positional_arg" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("value"),
    };
    const cli = try zcli.parseFrom(allocator, &app, &args);
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
    const cli = try zcli.parseFrom(allocator, &app, &args);
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
    const cli = try zcli.parseFrom(allocator, &app_test, &args);
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
    const cli = try zcli.parseFrom(allocator, &app_test, &args);
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
    const cli = try zcli.parseFrom(allocator, &app_test, &args);
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
    const cli = try zcli.parseFrom(allocator, &app_test, &args);
    defer cli.deinit(allocator);
    try expect(std.mem.eql(u8, cli.cmd.?.name, "cmd"));
    try expect(cli.positionals.items.len == 2);
    try expect(std.mem.eql(u8, cli.positionals.items[0].name, "cmd_arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[0].value, "cmd_pos_arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].name, "global_arg"));
    try expect(std.mem.eql(u8, cli.positionals.items[1].value, "pos_arg"));
}

test "command_function" {
    const allocator = std.testing.allocator;

    const addOne = struct {
        fn addOne(ptr: *anyopaque) !void {
            const i: *u64 = @ptrCast(@alignCast(ptr));
            i.* += 1;
        }
    }.addOne;

    const app_test = CliApp{
        .commands = &[_]Cmd{.{
            .name = "add",
            .action = addOne,
        }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("add") };
    const cli = try zcli.parseFrom(allocator, &app_test, &args);
    defer cli.deinit(allocator);

    var value: u64 = 0;
    const cmd = cli.cmd orelse return error.NoCmd;
    const cmdFn = cmd.exec orelse return error.NoCmdFn;
    try cmdFn(&value);
    try std.testing.expect(value == 1);
    try cmdFn(&value);
    try std.testing.expect(value == 2);
    try cmdFn(&value);
    try std.testing.expect(value == 3);
}

test "positionals_by_name_iterator" {
    const gpa = std.testing.allocator;
    const app_test = CliApp{ .positionals = &[_]PosArg{
        .{ .name = "multiple", .required = true, .multiple = true },
    } };
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("one"),
        @constCast("two"),
        @constCast("three"),
    };
    const cli = try zcli.parseFrom(gpa, &app_test, &args);
    defer cli.deinit(gpa);

    var it = cli.positionalIterator("multiple");
    try expectEqualStrings("one", (it.next() orelse return error.TestExpectedEqual).value);
    try expectEqualStrings("two", (it.next() orelse return error.TestExpectedEqual).value);
    try expectEqualStrings("three", (it.next() orelse return error.TestExpectedEqual).value);
    try expect(it.next() == null);

    var it2 = cli.positionalIterator("does-not-exist");
    try expect(it2.next() == null);
}

test "invalid_command" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .config = .{ .cmd_required = true },
        .commands = &[_]Cmd{.{ .name = "test" }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("invalid") };
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownCommand);
}

test "invalid_option" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--invalid") };
    const cli = zcli.parseFrom(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "cmd_option" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--any") };
    const cli = zcli.parseFrom(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "missing_command" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .config = .{ .cmd_required = true },
        .commands = &[_]Cmd{.{ .name = "test" }},
    };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.NoCommand);
}

test "missing_option" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .required = true }},
    };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parseFrom(allocator, &app_test, &args);
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
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.MissingOptionValue);
}

test "option_arg_null" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .arg = null }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--option=value") };
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.OptionHasNoArg);
}

test "invalid_option_arg_bool" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--bool=asd"),
    };
    const cli = zcli.parseFrom(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.InvalidOptionArgType);
}

test "invalid_option_arg_int" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--float=1.2a"),
    };
    const cli = zcli.parseFrom(allocator, &app, &args);
    try std.testing.expect(cli == ArgsError.InvalidOptionArgType);
}

test "invalid_option_arg_float" {
    const allocator = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("test"),
        @constCast("--int=1a"),
    };
    const cli = zcli.parseFrom(allocator, &app, &args);
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
    const cli = zcli.parseFrom(allocator, &app_test, &args);
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
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.DuplicateOption);
}

test "exclusive_group_opt_opt" {
    const gpa = std.testing.allocator;
    const group = "group_tag";
    const cmds = &[_]Cmd{.{ .name = "cmd", .options = &[_]Opt{
        .{
            .long_name = "id",
            .arg = .{ .name = "ID", .type = .Text },
            .exclusive_group = group,
        },
        .{
            .long_name = "path",
            .arg = .{ .name = "PATH", .type = .Path },
            .exclusive_group = group,
        },
    } }};
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("cmd"),
        @constCast("--id"),
        @constCast("abc"),
        @constCast("--path"),
        @constCast("file.yml"),
    };

    const app_bitset: CliApp = .{ .commands = cmds, .config = .{
        .exclusive_group_mode = .bitset,
    } };
    try std.testing.expect(
        zcli.parseFrom(gpa, &app_bitset, &args) == ArgsError.MutuallyExclusive,
    );
    const app_hashmap: CliApp = .{ .commands = cmds, .config = .{
        .exclusive_group_mode = .hashmap,
    } };
    try std.testing.expect(
        zcli.parseFrom(gpa, &app_hashmap, &args) == ArgsError.MutuallyExclusive,
    );
    const app_combined: CliApp = .{ .commands = cmds, .config = .{
        .exclusive_group_mode = .combined,
    } };
    try std.testing.expect(
        zcli.parseFrom(gpa, &app_combined, &args) == ArgsError.MutuallyExclusive,
    );
}

test "exclusive_group_opt_positional" {
    const gpa = std.testing.allocator;
    const group = "group_tag";
    const cmds = &[_]Cmd{.{
        .name = "cmd",
        .options = &[_]Opt{.{
            .long_name = "id",
            .arg = .{ .name = "ID", .type = .Text },
            .exclusive_group = group,
        }},
        .positionals = &[_]PosArg{.{
            .name = "path",
            .required = false,
            .exclusive_group = group,
        }},
    }};
    var args = [_][:0]u8{
        @constCast("zcli"),
        @constCast("cmd"),
        @constCast("--id"),
        @constCast("abc"),
        @constCast("file.yml"),
    };

    const app_bitset: CliApp = .{ .commands = cmds, .config = .{
        .exclusive_group_mode = .bitset,
    } };
    try std.testing.expect(
        zcli.parseFrom(gpa, &app_bitset, &args) == ArgsError.MutuallyExclusive,
    );
    const app_hashmap: CliApp = .{ .commands = cmds, .config = .{
        .exclusive_group_mode = .hashmap,
    } };
    try std.testing.expect(
        zcli.parseFrom(gpa, &app_hashmap, &args) == ArgsError.MutuallyExclusive,
    );
    const app_combined: CliApp = .{ .commands = cmds, .config = .{
        .exclusive_group_mode = .combined,
    } };
    try std.testing.expect(
        zcli.parseFrom(gpa, &app_combined, &args) == ArgsError.MutuallyExclusive,
    );
}

test "find_exclusive_group" {
    const gpa = std.testing.allocator;
    const group_tag = "group";
    const app_test = CliApp{ .commands = &[_]Cmd{.{
        .name = "cmd",
        .options = &[_]Opt{ .{
            .long_name = "id",
            .arg = .{ .name = "ID", .type = .Text },
            .exclusive_group = group_tag,
        }, .{
            .long_name = "path",
            .arg = .{ .name = "PATH", .type = .Path },
            .exclusive_group = group_tag,
        } },
        .positionals = &[_]PosArg{.{
            .name = "path",
            .required = false,
            .exclusive_group = group_tag,
        }},
    }}, .config = .{ .exclusive_group_mode = .combined } };

    var args_opt = [_][:0]u8{
        @constCast("zcli"),
        @constCast("cmd"),
        @constCast("--id"),
        @constCast("abc"),
    };
    const cli_opt = try zcli.parseFrom(gpa, &app_test, &args_opt);
    defer cli_opt.deinit(gpa);
    const arg_opt = cli_opt.findGroupArg(group_tag) orelse return error.NoArg;
    switch (arg_opt) {
        .option => |o| try expect(std.mem.eql(u8, o.value.?.string, "abc")),
        .positional => return error.WrongArgKind,
    }
    try expect(cli_opt.findGroupArg("does-not-exist") == null);

    var args_pos = [_][:0]u8{
        @constCast("zcli"),
        @constCast("cmd"),
        @constCast("file.yml"),
    };
    const cli_pos = try zcli.parseFrom(gpa, &app_test, &args_pos);
    defer cli_pos.deinit(gpa);
    const arg_pos = cli_pos.findGroupArg(group_tag) orelse return error.NoArg;
    switch (arg_pos) {
        .option => return error.WrongArgKind,
        .positional => |p| try expect(std.mem.eql(u8, p.value, "file.yml")),
    }
    try expect(cli_pos.findGroupArg("does-not-exist") == null);
}

test "unknown_option_long" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .short_name = "o" }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("--o") };
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "unknown_option_short" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{
        .options = &[_]Opt{.{ .long_name = "option", .short_name = "o" }},
    };
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("-option") };
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownOption);
}

test "invalid_positional" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{};
    var args = [_][:0]u8{ @constCast("zcli"), @constCast("argument") };
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.UnknownPositional);
}

test "missing_positional" {
    const allocator = std.testing.allocator;
    const app_test = CliApp{ .positionals = &[_]PosArg{.{
        .name = "arg",
        .required = true,
    }} };
    var args = [_][:0]u8{@constCast("zcli")};
    const cli = zcli.parseFrom(allocator, &app_test, &args);
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
    const cli = zcli.parseFrom(allocator, &app_test, &args);
    try std.testing.expect(cli == ArgsError.MissingPositional);
}

test "generate_bash" {
    var buf: [2048]u8 = undefined;
    _ = try zcli.complete.getCompletion(&buf, &app, "zcli", "bash");
}

test "generate_zsh" {
    var buf: [2048]u8 = undefined;
    _ = try zcli.complete.getCompletion(&buf, &app, "zcli", "zsh");
}

test "generate_fish" {
    var buf: [2048]u8 = undefined;
    _ = try zcli.complete.getCompletion(&buf, &app, "zcli", "fish");
}

test "generate_unsupported" {
    var buf: [2048]u8 = undefined;
    const script = zcli.complete.getCompletion(&buf, &app, "zcli", "shell");
    try expect(script == error.UnsupportedShell);
}

test "generate_nospace" {
    var buf: [10]u8 = undefined;
    const script = zcli.complete.getCompletion(&buf, &app, "zcli", "bash");
    try expect(script == error.NoSpaceLeft);
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
        .arg = .{ .name = "arg", .default = "value", .required = false },
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
