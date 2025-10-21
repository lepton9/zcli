const std = @import("std");
pub const arg = @import("arg.zig");
pub const parse = @import("parse.zig");

const Cmd = arg.Cmd;
const Option = arg.Option;
const OptType = arg.OptType;

pub const ArgsError = error{
    NoCommand,
    UnknownOption,
    UnknownCommand,
    NoOptionValue,
    OptionHasNoArg,
    NoRequiredOption,
    TooManyArgs,
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
        err: ArgsError,
        comptime fmt: []const u8,
        args: anytype,
    ) ArgsError!void {
        if (std.fmt.allocPrint(self.allocator, fmt, args) catch null) |formatted| {
            self.set_err_ctx(formatted);
        }
        return err;
    }

    pub fn validate_parsed_args(
        validator: *Validator,
        cli: *Cli,
        args: []const parse.ArgParse,
        app: *const arg.ArgsStructure,
    ) !void {
        const allocator = validator.allocator;
        try build_cli(validator, cli, args, app);
        if (cli.cmd == null and app.cmd_required) {
            return validator.create_error(ArgsError.NoCommand, "", .{});
        }
        const missing_opts = try missing_required_opts(allocator, cli, app);
        if (missing_opts) |missing| {
            const slice_str = try format_slice(
                *const arg.Option,
                allocator,
                missing,
                arg.Option.get_format_name,
            );
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
    args: ?std.ArrayList(*arg.Option) = null,
    global_args: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !*Cli {
        const cli = try allocator.create(Cli);
        cli.* = .{};
        return cli;
    }

    pub fn deinit(self: *Cli, allocator: std.mem.Allocator) void {
        if (self.args) |*args| {
            for (args.items) |a| {
                a.deinit(allocator);
            }
            args.deinit(allocator);
        }
        if (self.global_args) |ga| allocator.free(ga);
        allocator.destroy(self);
    }

    fn find_opt(self: *Cli, opt_name: []const u8) ?*arg.Option {
        if (self.args == null) return null;
        for (self.args.?.items) |option| {
            if (std.mem.eql(u8, option.long_name, opt_name)) {
                return option;
            }
        }
        return null;
    }

    fn add_opt(self: *Cli, allocator: std.mem.Allocator, opt: *const arg.Option) !void {
        if (self.args == null) {
            self.args = try std.ArrayList(*arg.Option).initCapacity(allocator, 5);
        }
        try self.args.?.append(allocator, try Option.init_from(opt, allocator));
    }

    fn add_unique(
        self: *Cli,
        allocator: std.mem.Allocator,
        opt: *const arg.Option,
    ) ArgsError!void {
        const option = self.find_opt(opt.long_name);
        if (option != null) return ArgsError.DuplicateOption;
        self.add_opt(allocator, opt) catch {};
    }
};

fn missing_required_opts(
    allocator: std.mem.Allocator,
    cli: *Cli,
    app: *const arg.ArgsStructure,
) !?[]*const arg.Option {
    var missing_opts = try std.ArrayList(*const arg.Option).initCapacity(allocator, 5);
    defer missing_opts.deinit(allocator);
    for (app.options) |*opt| {
        if (!opt.required) continue;
        var found = false;
        if (cli.args == null) {
            missing_opts.append(allocator, opt) catch {};
            continue;
        }
        for (cli.args.?.items) |o| {
            if (std.mem.eql(u8, o.long_name, opt.long_name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            missing_opts.append(allocator, opt) catch {};
        }
    }
    if (missing_opts.items.len == 0) return null;
    return missing_opts.toOwnedSlice(allocator) catch return null;
}

fn find_option(
    cli: *Cli,
    app: *const arg.ArgsStructure,
    opt_name: []const u8,
    opt_type: OptType,
) !Option {
    if (cli.cmd) |cmd| if (cmd.find_option(opt_name, opt_type)) |opt|
        return opt;
    return app.find_option(opt_name, opt_type);
}

fn build_cli(
    validator: *Validator,
    cli: *Cli,
    args: []const parse.ArgParse,
    app: *const arg.ArgsStructure,
) !void {
    const allocator = validator.allocator;
    var opt_build: ?arg.Option = null;
    var opt_type: ?parse.OptType = null;
    for (args, 0..) |a, i| switch (a) {
        .option => {
            if (cli.cmd == null and app.cmd_required) {
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
            const opt = find_option(cli, app, a.option.name, a.option.option_type) catch {
                return validator.create_error(ArgsError.UnknownOption, "{s}{s}", .{ switch (a.option.option_type) {
                    .long => "--",
                    .short => "-",
                }, a.option.name });
            };
            opt_build = opt;
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
                    return validator.create_error(ArgsError.UnknownCommand, "{s}", .{a.value});
                };
                cli.cmd = c;
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
            } else if (cli.global_args == null) {
                cli.global_args = try allocator.dupe(u8, a.value);
            } else {
                return validator.create_error(ArgsError.TooManyArgs, "{s}", .{a.value});
            }
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
