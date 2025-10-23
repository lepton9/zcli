const std = @import("std");
const arg = @import("arg.zig");

pub const Arg = arg.Arg;
pub const Cmd = arg.Cmd;
pub const Option = arg.Option;
pub const ArgsStructure = arg.ArgsStructure;

const appendFmt = arg.appendFmt;
fn appendBuf(buffer: []u8, written: *usize, comptime fmt: []const u8, args: anytype) !void {
    _ = try appendFmt(buffer, written, fmt, args);
}

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

    try appendBuf(buffer, &written, "_{s}()\n{{\n", .{app_name});
    try appendBuf(buffer, &written, "    local cur prev opts cmds\n", .{});
    try appendBuf(buffer, &written, "    COMPREPLY=()\n", .{});
    try appendBuf(buffer, &written, "    cur=\"${{COMP_WORDS[COMP_CWORD]}}\"\n", .{});
    try appendBuf(buffer, &written, "    prev=\"${{COMP_WORDS[COMP_CWORD-1]}}\"\n", .{});

    // Commands
    try appendBuf(buffer, &written, "    cmds=\"", .{});
    for (args.commands) |cmd| {
        try appendBuf(buffer, &written, "{s} ", .{cmd.name});
    }
    try appendBuf(buffer, &written, "\"\n", .{});

    // Options
    try appendBuf(buffer, &written, "    general_opts=\"", .{});
    for (args.options) |opt| {
        if (opt.short_name) |s| _ = try appendBuf(buffer, &written, "-{s} ", .{s});
        try appendBuf(buffer, &written, "--{s} ", .{opt.long_name});
    }
    try appendBuf(buffer, &written, "\"\n", .{});

    // Command specific options
    try appendBuf(buffer, &written, "    case \"${{COMP_WORDS[1]}}\" in\n", .{});
    for (args.commands) |cmd| {
        _ = try appendBuf(buffer, &written, "        {s})\n", .{cmd.name});
        _ = try appendBuf(buffer, &written, "            cmd_opts=\"", .{});
        if (cmd.options) |cmd_opts| for (cmd_opts) |opt| {
            if (opt.short_name) |s| _ = try appendBuf(buffer, &written, "-{s} ", .{s});
            _ = try appendBuf(buffer, &written, "--{s} ", .{opt.long_name});
        };
        _ = try appendBuf(buffer, &written, "\"            ;;\n", .{});
    }
    try appendBuf(buffer, &written, "        *) cmd_opts=\"\" ;;\n", .{});
    try appendBuf(buffer, &written, "    esac\n", .{});

    try appendBuf(buffer, &written, "    opts=\"${{general_opts}} ${{cmd_opts}}\"\n", .{});

    return try appendFmt(buffer, &written,
        \\    if [[ ${{COMP_CWORD}} -eq 1 ]] ; then
        \\        COMPREPLY=( $(compgen -W "${{cmds}} ${{general_opts}}" -- ${{cur}}) )
        \\        return 0
        \\    fi
        \\    COMPREPLY=( $(compgen -W "${{opts}}" -- ${{cur}}) )
        \\    return 0
        \\}}
        \\complete -F _{0s} {0s}
    , .{app_name});
}
