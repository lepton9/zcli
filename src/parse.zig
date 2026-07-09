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
};

fn parseArg(arg: []const u8, force_positional: *bool) ?ArgParse {
    if (arg.len > 0 and !force_positional.* and arg[0] == '-') {
        if (arg.len == 1) return .{ .value = arg };

        var name = arg[1..];
        var option_type: OptType = .short;
        if (arg[1] == '-') {
            if (arg.len == 2) {
                force_positional.* = true;
                return null;
            }
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

pub const ArgParser = struct {
    args: []const [:0]const u8,
    force_positional: bool = false,

    pub fn init(args: []const [:0]const u8) ArgParser {
        return .{ .args = args };
    }

    pub const Iterator = struct {
        parser: *ArgParser,
        cur: usize = 0,

        pub fn next(self: *Iterator) ?ArgParse {
            const items = self.parser.args;
            if (self.cur >= items.len) return null;
            const token = items[self.cur];
            self.cur += 1;
            return parseArg(token, &self.parser.force_positional);
        }
    };

    pub fn iterator(self: *@This()) Iterator {
        return .{ .parser = self };
    }
};
