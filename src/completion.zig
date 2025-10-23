const std = @import("std");
const arg = @import("arg.zig");

const appendFmt = arg.appendFmt;

pub const Arg = arg.Arg;
pub const Cmd = arg.Cmd;
pub const Option = arg.Option;
pub const ArgsStructure = arg.ArgsStructure;

pub fn getCompletion(
    comptime args: *const ArgsStructure,
    app_name: []const u8,
    shell: []const u8,
) !void {
    var buffer: [2048]u8 = undefined;
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const stdout = &stdout_writer.interface;

    if (std.mem.eql(u8, shell, "bash")) {
        const c = try bashCompletion(&buffer, args, app_name);
        std.debug.print("{s}\n", .{c});
    } else {
        try stdout.print("Unsupported shell: {s}\n", .{shell});
    }
}

fn bashCompletion(
    buffer: []u8,
    comptime args: *const ArgsStructure,
    app_name: []const u8,
) ![]const u8 {
    var written: usize = 0;

    _ = try appendFmt(buffer, &written, "_{s}()\n{{\n", .{app_name});
    _ = try appendFmt(buffer, &written, "    local cur prev opts cmds\n", .{});
    _ = try appendFmt(buffer, &written, "    COMPREPLY=()\n", .{});
    _ = try appendFmt(buffer, &written, "    cur=\"${{COMP_WORDS[COMP_CWORD]}}\"\n", .{});

    // Commands
    _ = try appendFmt(buffer, &written, "    cmds=\"", .{});
    for (args.commands) |cmd| {
        _ = try appendFmt(buffer, &written, "{s} ", .{cmd.name});
    }
    _ = try appendFmt(buffer, &written, "\"\n", .{});

    // Options
    _ = try appendFmt(buffer, &written, "    general_opts=\"", .{});
    for (args.options) |opt| {
        if (opt.short_name) |s| _ = try appendFmt(buffer, &written, "-{s} ", .{s});
        _ = try appendFmt(buffer, &written, "--{s} ", .{opt.long_name});
    }
    _ = try appendFmt(buffer, &written, "\"\n", .{});

    // Command specific options
    _ = try appendFmt(buffer, &written, "    case \"${{COMP_WORDS[1]}}\" in\n", .{});
    for (args.commands) |cmd| {
        _ = try appendFmt(buffer, &written, "        {s})\n", .{cmd.name});
        _ = try appendFmt(buffer, &written, "            cmd_opts=\"", .{});
        if (cmd.options) |cmd_opts| for (cmd_opts) |opt| {
            if (opt.short_name) |s| _ = try appendFmt(buffer, &written, "-{s} ", .{s});
            _ = try appendFmt(buffer, &written, "--{s} ", .{opt.long_name});
        };
        _ = try appendFmt(buffer, &written, "\"            ;;\n", .{});
    }
    _ = try appendFmt(buffer, &written, "        *) cmd_opts=\"\" ;;\n", .{});
    _ = try appendFmt(buffer, &written, "    esac\n", .{});

    _ = try appendFmt(buffer, &written, "    opts=\"${{general_opts}} ${{cmd_opts}}\"\n", .{});

    return try appendFmt(buffer, &written,
        \\    if [[ ${{cur}} == -* ]] ; then
        \\        COMPREPLY=( $(compgen -W "${{opts}}" -- ${{cur}}) )
        \\        return 0
        \\    fi
        \\    COMPREPLY=( $(compgen -W "${{cmds}}" -- ${{cur}}) )
        \\    return 0
        \\}}
        \\complete -F _{0s} {0s}
        \\
    , .{app_name});
}
