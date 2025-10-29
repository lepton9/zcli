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
    NoOptionValue,
    OptionHasNoArg,
    NoRequiredOption,
    UnknownPositional,
    DuplicateOption,
};

pub const Validator = struct {
    error_ctx: ?[]const u8 = null,
    allocator: std.mem.Allocator,

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

    pub fn create_error(
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

    pub fn validate_parsed_args(
        validator: *Validator,
        cli: *Cli,
        args: []const parse.ArgParse,
        comptime app: *const arg.App,
    ) !void {
        const allocator = validator.allocator;
        try build_cli(validator, cli, args, app);
        if (cli.cmd == null and app.cli.cmd_required) {
            return validator.create_error(ArgsError.NoCommand, "", .{});
        }
        const missing_opts = try missing_required_opts(allocator, cli, app);
        if (missing_opts) |missing| {
            defer allocator.free(missing);
            const slice_str = try format_slice(
                *const arg.Option,
                allocator,
                missing,
                arg.Option.get_format_name,
            );
            defer allocator.free(slice_str);
            return validator.create_error(
                ArgsError.NoRequiredOption,
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
        for (app.cli.positionals, 0..) |positional, i| {
            if (!positional.multiple and self.positionals.items.len > i) continue;
            var pos = try PosArg.init_from(&positional, allocator);
            pos.value = try allocator.dupe(u8, value);
            return try self.positionals.append(allocator, pos);
        }
        return ArgsError.UnknownPositional;
    }
};

fn missing_required_opts(
    allocator: std.mem.Allocator,
    cli: *Cli,
    comptime app: *const arg.App,
) !?[]*const arg.Option {
    var missing_opts = try std.ArrayList(*const arg.Option).initCapacity(allocator, 5);

    if (cli.cmd) |cmd| if (cmd.options) |opts| for (opts) |*opt| {
        if (!opt.required) continue;
        if (cli.find_opt(opt.long_name) == null) {
            try missing_opts.append(allocator, opt);
        }
    };
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

fn find_option(
    cli: *Cli,
    comptime app: *const arg.App,
    opt_name: []const u8,
) !*const Option {
    if (cli.cmd) |cmd| {
        const c = app.commands.get(cmd.name).?;
        if (c.options) |opts| if (opts.get(opt_name)) |opt|
            return opt;
    }
    return app.find_option(opt_name);
}

fn build_cli(
    validator: *Validator,
    cli: *Cli,
    args: []const parse.ArgParse,
    comptime app: *const arg.App,
) !void {
    const allocator = validator.allocator;
    var opt_build: ?Option = null;
    var opt_type: ?OptType = null;
    for (args, 0..) |a, i| switch (a) {
        .option => {
            if (cli.cmd == null and app.cli.cmd_required) {
                return validator.create_error(ArgsError.NoCommand, "", .{});
            }
            if (opt_build) |*opt_b| {
                if (!opt_b.arg.?.required or opt_b.arg.?.default != null) {
                    opt_b.arg.?.value = opt_b.arg.?.default;
                    cli.add_unique(allocator, opt_b) catch |err| {
                        return validator.create_error(err, "{s}{s}", switch (opt_type.?) {
                            .long => .{ "--", opt_b.long_name },
                            .short => .{ "-", opt_b.short_name.? },
                        });
                    };
                    opt_build = null;
                    opt_type = null;
                } else {
                    return validator.create_error(ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                        .long => .{ "--", opt_b.long_name },
                        .short => .{ "-", opt_b.short_name orelse "" },
                    });
                }
            }
            const opt = find_option(cli, app, a.option.name) catch {
                return validator.create_error(ArgsError.UnknownOption, "{s}{s}", .{ switch (a.option.option_type) {
                    .long => "--",
                    .short => "-",
                }, a.option.name });
            };
            opt_build = opt.*;
            if (opt.arg) |_| {
                if (a.option.value == null) {
                    opt_type = a.option.option_type;
                } else {
                    opt_build.?.arg.?.value = a.option.value;
                    cli.add_unique(allocator, &opt_build.?) catch |err| {
                        return validator.create_error(err, "{s}{s}", .{
                            switch (a.option.option_type) {
                                .long => "--",
                                .short => "-",
                            },
                            a.option.name,
                        });
                    };
                    opt_build = null;
                }
                continue;
            }
            if (a.option.value) |_| {
                return validator.create_error(
                    ArgsError.OptionHasNoArg,
                    "{s}{s}",
                    .{ switch (a.option.option_type) {
                        .long => "--",
                        .short => "-",
                    }, a.option.name },
                );
            }
            cli.add_unique(allocator, &opt_build.?) catch |err| {
                return validator.create_error(err, "{s}{s}", .{
                    switch (a.option.option_type) {
                        .long => "--",
                        .short => "-",
                    },
                    a.option.name,
                });
            };
            opt_build = null;
        },
        .value => {
            if (cli.cmd == null and i == 0) {
                const c = app.find_cmd(a.value) catch {
                    if (app.cli.cmd_required) return validator.create_error(
                        ArgsError.UnknownCommand,
                        "{s}",
                        .{a.value},
                    );
                    cli.add_positional(allocator, app, a.value) catch |err| {
                        return validator.create_error(err, "{s}", .{a.value});
                    };
                    continue;
                };
                cli.cmd = c.*;
            } else if (opt_build) |*opt_b| {
                opt_b.arg.?.value = a.value;
                cli.add_unique(allocator, opt_b) catch |err| {
                    return validator.create_error(err, "{s}{s}", switch (opt_type.?) {
                        .long => .{ "--", opt_b.long_name },
                        .short => .{ "-", opt_b.short_name orelse "" },
                    });
                };
                opt_build = null;
                opt_type = null;
            } else cli.add_positional(allocator, app, a.value) catch |err| {
                return validator.create_error(err, "{s}", .{a.value});
            };
        },
    };
    if (opt_build) |*opt_e| {
        if (opt_e.arg.?.required and opt_e.arg.?.default == null) {
            return validator.create_error(ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                .long => .{ "--", opt_e.long_name },
                .short => .{ "-", opt_e.short_name orelse "" },
            });
        }
        opt_e.arg.?.value = opt_e.arg.?.default;
        cli.add_unique(allocator, opt_e) catch |err| {
            return validator.create_error(err, "{s}{s}", switch (opt_type.?) {
                .long => .{ "--", opt_e.long_name },
                .short => .{ "-", opt_e.short_name orelse "" },
            });
        };
    }
}

fn format_slice(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
    field_fn: fn (item: T, buf: []u8) []const u8,
) ![]u8 {
    var item_buf: [32]u8 = undefined;
    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    errdefer buf.deinit(allocator);
    for (items, 0..) |item, i| {
        if (i != 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, field_fn(item, &item_buf));
    }
    return try buf.toOwnedSlice(allocator);
}
