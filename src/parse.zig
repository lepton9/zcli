const std = @import("std");

pub const OptType = enum {
    long,
    short,
};

pub const OptionParse = struct {
    option_type: OptType,
    name: []const u8,
    value: ?[]const u8 = null,
};

pub const ArgParse = union(enum) {
    option: OptionParse,
    value: []const u8,
    end_of_options,
};

pub const ArgParser = struct {
    /// Arguments to parse.
    args: []const [:0]const u8,
    /// Current argument index.
    cur: usize = 0,
    /// Force argument to be a positional.
    force_positional: bool = false,

    pub fn init(args: []const [:0]const u8) ArgParser {
        return .{ .args = args };
    }

    /// Get and parse the next argument.
    pub fn next(self: *ArgParser) ?ArgParse {
        const items = self.args;
        if (self.cur >= items.len) return null;
        const token = items[self.cur];
        self.cur += 1;
        const arg = parseArg(token, self.force_positional) orelse return null;
        if (arg == .end_of_options) self.force_positional = true;
        return arg;
    }
};

fn parseArg(arg: []const u8, force_positional: bool) ?ArgParse {
    if (arg.len > 0 and !force_positional and arg[0] == '-') {
        if (arg.len == 1) return .{ .value = arg };

        var name = arg[1..];
        var option_type: OptType = .short;
        if (arg[1] == '-') {
            if (arg.len == 2) return .end_of_options;
            name = arg[2..];
            option_type = .long;
        } else if (std.ascii.isDigit(arg[1])) {
            return .{ .value = arg };
        }
        if (std.mem.indexOfScalar(u8, name, '=')) |i| {
            const value = if (name.len <= i + 1) null else name[i + 1 ..];
            return .{ .option = .{
                .option_type = option_type,
                .name = name[0..i],
                .value = value,
            } };
        } else {
            return .{ .option = .{ .option_type = option_type, .name = name } };
        }
    } else return .{ .value = arg };
}
