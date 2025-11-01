const std = @import("std");
pub const arg = @import("arg.zig");
pub const parse = @import("parse.zig");

const Cmd = arg.Cmd;
const PosArg = arg.PosArg;
const Option = arg.Option;
const OptType = arg.OptType;

pub const ArgsError = error{
    NoCommand,
    UnknownOption,
    UnknownCommand,
    UnknownPositional,
    NoOptionValue,
    OptionHasNoArg,
    MissingOption,
    MissingPositional,
    DuplicateOption,
};

pub const Validator = struct {
    allocator: std.mem.Allocator,
    error_ctx: ?[]const u8 = null,
    opt_build: ?Option = null,
    opt_type: ?OptType = null,

    pub fn init(allocator: std.mem.Allocator) !*Validator {
        const parser = try allocator.create(Validator);
        parser.* = .{
            .allocator = allocator,
        };
        return parser;
    }

    pub fn deinit(self: *Validator) void {
        if (self.error_ctx) |e| self.allocator.free(e);
        self.allocator.destroy(self);
    }

    fn set_err_ctx(self: *Validator, err: []const u8) void {
        if (self.error_ctx) |e| self.allocator.free(e);
        self.error_ctx = err;
    }

    pub fn get_err_ctx(self: *Validator) []const u8 {
        return self.error_ctx orelse "";
    }

    fn create_error(
        self: *Validator,
        err: anyerror,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        if (std.fmt.allocPrint(self.allocator, fmt, args) catch null) |formatted| {
            self.set_err_ctx(formatted);
        }
        return err;
    }

    pub fn validate_cli(
        validator: *Validator,
        cli: *Cli,
        comptime app: *const arg.App,
    ) !void {
        if (cli.cmd == null and app.cli.cmd_required) {
            return validator.create_error(ArgsError.NoCommand, "", .{});
        }
        try check_options(validator, cli, app);
        try check_positionals(validator, cli, app);
    }

    fn check_options(
        validator: *Validator,
        cli: *Cli,
        comptime app: *const arg.App,
    ) !void {
        const allocator = validator.allocator;
        const missing_opts = try missing_options(allocator, cli, app);
        if (missing_opts) |missing| {
            defer allocator.free(missing);
            const slice_str = try format_slice(
                *const Option,
                allocator,
                missing,
                arg.option_fmt_name,
            );
            defer allocator.free(slice_str);
            return validator.create_error(
                ArgsError.MissingOption,
                "[{s}]",
                .{slice_str},
            );
        }
    }

    fn check_positionals(
        validator: *Validator,
        cli: *Cli,
        comptime app: *const arg.App,
    ) !void {
        const allocator = validator.allocator;
        const missing_args = try missing_positionals(allocator, cli, app);
        if (missing_args) |missing| {
            defer allocator.free(missing);
            const slice_str = try format_slice(
                *const PosArg,
                allocator,
                missing,
                struct {
                    fn f(p: *const PosArg, buf: []u8) []const u8 {
                        return std.fmt.bufPrint(buf, "'{s}'", .{p.name}) catch p.name;
                    }
                }.f,
            );
            defer allocator.free(slice_str);
            return validator.create_error(
                ArgsError.MissingPositional,
                "[{s}]",
                .{slice_str},
            );
        }
    }
};

pub const Cli = struct {
    cmd: ?arg.Cmd = null,
    args: std.StringArrayHashMap(*Option),
    positionals: std.ArrayList(*PosArg),

    pub fn init(allocator: std.mem.Allocator) !*Cli {
        const cli = try allocator.create(Cli);
        cli.* = .{
            .args = std.StringArrayHashMap(*Option).init(allocator),
            .positionals = try std.ArrayList(*PosArg).initCapacity(allocator, 5),
        };
        return cli;
    }

    pub fn deinit(self: *Cli, allocator: std.mem.Allocator) void {
        var it = self.args.iterator();
        while (it.next()) |e| {
            e.value_ptr.*.deinit(allocator);
        }
        self.args.deinit();
        for (self.positionals.items) |pos| {
            pos.deinit(allocator);
        }
        self.positionals.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn find_opt(self: *Cli, opt_name: []const u8) ?*Option {
        return self.args.get(opt_name);
    }

    pub fn find_positional(self: *Cli, name: []const u8) ?*PosArg {
        for (self.positionals.items) |pos| {
            if (std.mem.eql(u8, pos.name, name)) {
                return pos;
            }
        }
        return null;
    }

    fn add_unique(
        self: *Cli,
        allocator: std.mem.Allocator,
        opt: *const arg.Option,
    ) !void {
        const option = try Option.init_from(opt, allocator);
        errdefer option.deinit(allocator);
        const entry = try self.args.getOrPut(option.long_name);
        if (entry.found_existing) return ArgsError.DuplicateOption;
        entry.value_ptr.* = option;
    }

    fn add_positional(
        self: *Cli,
        allocator: std.mem.Allocator,
        comptime app: *const arg.App,
        value: []const u8,
    ) !void {
        const add_pos = struct {
            fn f(
                alloc: std.mem.Allocator,
                cli: *Cli,
                pos_arg: *const PosArg,
                val: []const u8,
            ) !void {
                var pos = try PosArg.init_from(pos_arg, alloc);
                pos.value = try alloc.dupe(u8, val);
                return try cli.positionals.append(alloc, pos);
            }
        }.f;

        var cmd_positionals: usize = 0;
        if (self.cmd) |command| {
            const cmd = app.commands.get(command.name).?;
            if (cmd.cmd.positionals) |ps| {
                cmd_positionals = ps.len;
                for (ps, 0..) |positional, i| {
                    if (!positional.multiple and self.positionals.items.len > i)
                        continue;
                    return try add_pos(allocator, self, &positional, value);
                }
            }
        }
        for (app.cli.positionals, 0..) |positional, i| {
            if (!positional.multiple and
                self.positionals.items.len - cmd_positionals > i) continue;
            return try add_pos(allocator, self, &positional, value);
        }
        return ArgsError.UnknownPositional;
    }
};

fn missing_options(
    allocator: std.mem.Allocator,
    cli: *Cli,
    comptime app: *const arg.App,
) !?[]*const Option {
    var missing_opts = try std.ArrayList(*const Option).initCapacity(allocator, 5);

    if (cli.cmd) |command| {
        const cmd = app.commands.get(command.name).?;
        if (cmd.cmd.options) |opts| for (opts) |*opt| {
            if (!opt.required) continue;
            if (cli.find_opt(opt.long_name) == null) {
                try missing_opts.append(allocator, opt);
            }
        };
    }
    for (app.cli.options) |*opt| {
        if (!opt.required) continue;
        if (cli.find_opt(opt.long_name) == null) {
            try missing_opts.append(allocator, opt);
        }
    }

    if (missing_opts.items.len == 0) {
        missing_opts.deinit(allocator);
        return null;
    }
    return try missing_opts.toOwnedSlice(allocator);
}

fn missing_positionals(
    allocator: std.mem.Allocator,
    cli: *Cli,
    comptime app: *const arg.App,
) !?[]*const PosArg {
    var missing_args = try std.ArrayList(*const PosArg).initCapacity(allocator, 5);

    if (cli.cmd) |command| {
        const cmd = app.commands.get(command.name).?;
        if (cmd.cmd.positionals) |ps| for (ps) |*positional| {
            if (!positional.required) continue;
            if (cli.find_positional(positional.name) == null) {
                try missing_args.append(allocator, positional);
            }
        };
    }
    for (app.cli.positionals) |*positional| {
        if (!positional.required) continue;
        if (cli.find_positional(positional.name) == null) {
            try missing_args.append(allocator, positional);
        }
    }

    if (missing_args.items.len == 0) {
        missing_args.deinit(allocator);
        return null;
    }
    return try missing_args.toOwnedSlice(allocator);
}

fn find_option(
    cli: *Cli,
    comptime app: *const arg.App,
    option: *const parse.OptionParse,
) !*const Option {
    const opt = blk: {
        if (cli.cmd) |cmd| {
            const c = app.commands.get(cmd.name).?;
            if (c.options) |opts| if (opts.get(option.name)) |opt|
                break :blk opt;
        }
        break :blk try app.find_option(option.name);
    };
    const opt_name = switch (option.option_type) {
        .long => opt.long_name,
        .short => opt.short_name,
    };
    if (opt_name) |name| if (name.len == option.name.len) return opt;
    return error.InvalidOption;
}

pub fn build_cli(
    validator: *Validator,
    cli: *Cli,
    args: []const parse.ArgParse,
    comptime app: *const arg.App,
) !void {
    for (args, 0..) |a, i| switch (a) {
        .option => try interpret_option(validator, cli, app, &a.option),
        .value => try interpret_value(validator, cli, app, i == 0, a.value),
    };
    if (validator.opt_build) |*opt_b| {
        if (opt_b.arg.?.required and opt_b.arg.?.default == null) {
            return validator.create_error(
                ArgsError.NoOptionValue,
                "{s}{s}",
                switch (validator.opt_type.?) {
                    .long => .{ "--", opt_b.long_name },
                    .short => .{ "-", opt_b.short_name orelse "" },
                },
            );
        }
        opt_b.arg.?.value = opt_b.arg.?.default;
        cli.add_unique(validator.allocator, opt_b) catch |err| {
            return validator.create_error(err, "{s}{s}", switch (validator.opt_type.?) {
                .long => .{ "--", opt_b.long_name },
                .short => .{ "-", opt_b.short_name orelse "" },
            });
        };
        validator.opt_build = null;
        validator.opt_type = null;
    }
}

fn interpret_option(
    validator: *Validator,
    cli: *Cli,
    comptime app: *const arg.App,
    option: *const parse.OptionParse,
) !void {
    const allocator = validator.allocator;
    if (validator.opt_build) |*opt_b| {
        if (!opt_b.arg.?.required or opt_b.arg.?.default != null) {
            opt_b.arg.?.value = opt_b.arg.?.default;
            cli.add_unique(allocator, opt_b) catch |err| {
                return validator.create_error(err, "{s}{s}", switch (validator.opt_type.?) {
                    .long => .{ "--", opt_b.long_name },
                    .short => .{ "-", opt_b.short_name.? },
                });
            };
            validator.opt_build = null;
            validator.opt_type = null;
        } else {
            return validator.create_error(ArgsError.NoOptionValue, "{s}{s}", switch (validator.opt_type.?) {
                .long => .{ "--", opt_b.long_name },
                .short => .{ "-", opt_b.short_name orelse "" },
            });
        }
    }
    const opt = find_option(cli, app, option) catch {
        return validator.create_error(ArgsError.UnknownOption, "{s}{s}", .{ switch (option.option_type) {
            .long => "--",
            .short => "-",
        }, option.name });
    };
    validator.opt_build = opt.*;
    if (opt.arg) |_| {
        if (option.value == null) {
            validator.opt_type = option.option_type;
        } else {
            validator.opt_build.?.arg.?.value = option.value;
            cli.add_unique(allocator, &validator.opt_build.?) catch |err| {
                return validator.create_error(err, "{s}{s}", .{
                    switch (option.option_type) {
                        .long => "--",
                        .short => "-",
                    },
                    option.name,
                });
            };
            validator.opt_build = null;
        }
        return;
    }
    if (option.value) |_| {
        return validator.create_error(
            ArgsError.OptionHasNoArg,
            "{s}{s}",
            .{ switch (option.option_type) {
                .long => "--",
                .short => "-",
            }, option.name },
        );
    }
    cli.add_unique(allocator, &validator.opt_build.?) catch |err| {
        return validator.create_error(err, "{s}{s}", .{
            switch (option.option_type) {
                .long => "--",
                .short => "-",
            },
            option.name,
        });
    };
    validator.opt_build = null;
}

fn interpret_value(
    validator: *Validator,
    cli: *Cli,
    comptime app: *const arg.App,
    is_command: bool,
    value: []const u8,
) !void {
    const allocator = validator.allocator;
    if (is_command) {
        const c = app.find_cmd(value) catch {
            if (app.cli.cmd_required) return validator.create_error(
                ArgsError.UnknownCommand,
                "{s}",
                .{value},
            );
            cli.add_positional(allocator, app, value) catch |err| {
                return validator.create_error(err, "{s}", .{value});
            };
            return;
        };
        cli.cmd = c.*;
    } else if (validator.opt_build) |*opt_b| {
        opt_b.arg.?.value = value;
        cli.add_unique(allocator, opt_b) catch |err| {
            return validator.create_error(err, "{s}{s}", switch (validator.opt_type.?) {
                .long => .{ "--", opt_b.long_name },
                .short => .{ "-", opt_b.short_name orelse "" },
            });
        };
        validator.opt_build = null;
        validator.opt_type = null;
    } else cli.add_positional(allocator, app, value) catch |err| {
        return validator.create_error(err, "{s}", .{value});
    };
}

fn format_slice(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
    field_fn: fn (item: T, buf: []u8) []const u8,
) ![]u8 {
    var item_buf: [64]u8 = undefined;
    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    errdefer buf.deinit(allocator);
    for (items, 0..) |item, i| {
        if (i != 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, field_fn(item, &item_buf));
    }
    return try buf.toOwnedSlice(allocator);
}
