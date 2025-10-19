const std = @import("std");
pub const arg = @import("arg.zig");
pub const parse = @import("parse.zig");

const Cmd = arg.Cmd;
const Option = arg.Option;

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
    cli: *Cli = undefined,
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
        args: []const parse.ArgParse,
        app: *const arg.ArgsStructure,
    ) !void {
        const allocator = validator.allocator;
        const cli = validator.cli;
        try build_cli(validator, args, app);
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
    args: ?std.ArrayList(arg.Option) = null,
    global_args: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !*Cli {
        const cli = try allocator.create(Cli);
        cli.* = .{};
        return cli;
    }

    pub fn deinit(self: *Cli, allocator: std.mem.Allocator) void {
        if (self.args) |*args| {
            args.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn find_opt(self: *Cli, opt_name: []const u8) ?*arg.Option {
        if (self.args == null) return null;
        for (self.args.?.items) |*option| {
            if (std.mem.eql(u8, option.long_name, opt_name)) {
                return option;
            }
        }
        return null;
    }

    fn add_opt(self: *Cli, allocator: std.mem.Allocator, opt: arg.Option) !void {
        if (self.args == null) {
            self.args = try std.ArrayList(arg.Option).initCapacity(allocator, 5);
        }
        try self.args.?.append(allocator, opt);
    }

    fn add_unique(self: *Cli, allocator: std.mem.Allocator, opt: arg.Option) ArgsError!void {
        const option = self.find_opt(opt.long_name);
        if (option != null) return ArgsError.DuplicateOption;
        self.add_opt(allocator, opt) catch {};
    }
};

fn missing_required_opts(allocator: std.mem.Allocator, cli: *Cli, app: *const arg.ArgsStructure) !?[]*const arg.Option {
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

fn build_cli(
    validator: *Validator,
    args: []const parse.ArgParse,
    app: *const arg.ArgsStructure,
) !void {
    const allocator = validator.allocator;
    var cli = validator.cli;
    var opt_empty: ?arg.Option = null;
    var opt_type: ?parse.OptType = null;
    for (args, 0..) |a, i| {
        switch (a) {
            .option => {
                if (cli.cmd == null and app.cmd_required) {
                    return validator.create_error(ArgsError.NoCommand, "", .{});
                }
                if (opt_empty) |opt_e| {
                    if (!opt_e.arg.?.required) {
                        cli.add_unique(allocator, opt_e) catch |err| {
                            return validator.create_error(err, "{s}{s}", switch (opt_type.?) {
                                .long => .{ "--", opt_e.long_name },
                                .short => .{ "-", opt_e.short_name.? },
                            });
                        };
                        opt_empty = null;
                        opt_type = null;
                    } else {
                        return validator.create_error(ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                            .long => .{ "--", opt_e.long_name },
                            .short => .{ "-", opt_e.short_name orelse "" },
                        });
                    }
                }
                var opt = app.find_option(a.option.name, a.option.option_type) catch {
                    return validator.create_error(ArgsError.UnknownOption, "{s}{s}", .{ switch (a.option.option_type) {
                        .long => "--",
                        .short => "-",
                    }, a.option.name });
                };
                if (opt.arg) |*opt_arg| {
                    if (a.option.value == null) {
                        opt_empty = opt;
                        opt_type = a.option.option_type;
                    } else {
                        opt_arg.value = a.option.value;
                        cli.add_unique(allocator, opt) catch |err| {
                            return validator.create_error(err, "{s}{s}", .{
                                switch (a.option.option_type) {
                                    .long => "--",
                                    .short => "-",
                                },
                                a.option.name,
                            });
                        };
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
                cli.add_unique(allocator, opt) catch |err| {
                    return validator.create_error(err, "{s}{s}", .{
                        switch (a.option.option_type) {
                            .long => "--",
                            .short => "-",
                        },
                        a.option.name,
                    });
                };
            },
            .value => {
                if (cli.cmd == null and i == 0) {
                    const c = app.find_cmd(a.value) catch {
                        return validator.create_error(ArgsError.UnknownCommand, "{s}", .{a.value});
                    };
                    cli.cmd = c;
                } else if (opt_empty) |*opt_e| {
                    opt_e.arg.?.value = a.value;
                    cli.add_unique(allocator, opt_e.*) catch |err| {
                        return validator.create_error(err, "{s}{s}", switch (opt_type.?) {
                            .long => .{ "--", opt_e.long_name },
                            .short => .{ "-", opt_e.short_name orelse "" },
                        });
                    };
                    opt_empty = null;
                    opt_type = null;
                } else if (cli.global_args == null) {
                    cli.global_args = a.value;
                } else {
                    return validator.create_error(ArgsError.TooManyArgs, "{s}", .{a.value});
                }
            },
        }
    }
    if (opt_empty) |opt_e| {
        if (opt_e.arg.?.required) {
            return validator.create_error(ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                .long => .{ "--", opt_e.long_name },
                .short => .{ "-", opt_e.short_name orelse "" },
            });
        }
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
