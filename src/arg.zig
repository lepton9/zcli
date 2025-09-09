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

pub fn parse_arg(arg: []const u8) ?ArgParse {
    if (arg.len == 0) return null;
    if (arg[0] == '-') {
        if (arg.len == 1) return .{ .value = arg };

        var name = arg[1..];
        var option_type: OptType = .short;
        if (arg[1] == '-') {
            if (arg.len == 2) return .{ .value = arg };
            name = arg[2..];
            option_type = .long;
        }

        if (std.mem.indexOfScalar(u8, name, '=')) |i| {
            const value = if (name.len <= i + 1) null else name[i + 1 ..];
            return .{
                .option = .{
                    .option_type = option_type,
                    .name = name[0..i],
                    .value = value,
                },
            };
        } else {
            return .{
                .option = .{
                    .option_type = option_type,
                    .name = name,
                },
            };
        }
    } else {
        return .{ .value = arg };
    }
}

pub fn parse_args(allocator: std.mem.Allocator, args_str: [][:0]u8) ![]ArgParse {
    var args = try std.ArrayList(ArgParse).initCapacity(allocator, 5);
    for (args_str) |token| {
        const arg: ?ArgParse = parse_arg(token);
        if (arg) |a| {
            try args.append(allocator, a);
        }
    }
    return args.toOwnedSlice(allocator);
}
