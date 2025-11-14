const std = @import("std");
const arg = @import("arg.zig");

const Arg = arg.Arg;
const Cmd = arg.Cmd;
const Opt = arg.Opt;
const CliApp = arg.CliApp;

const appendFmt = arg.appendFmt;
fn appendBuf(
    buffer: []u8,
    written: *usize,
    comptime fmt: []const u8,
    args: anytype,
) std.fmt.BufPrintError!void {
    _ = try appendFmt(buffer, written, fmt, args);
}

pub fn getCompletion(
    buffer: []u8,
    comptime args: *const CliApp,
    app_name: []const u8,
    shell: []const u8,
) error{ UnsupportedShell, NoSpaceLeft }![]const u8 {
    if (std.mem.eql(u8, shell, "bash")) {
        return try bashCompletion(buffer, args, app_name);
    } else if (std.mem.eql(u8, shell, "zsh")) {
        return try zshCompletion(buffer, args, app_name);
    } else if (std.mem.eql(u8, shell, "fish")) {
        return try fishCompletion(buffer, args, app_name);
    }
    return error.UnsupportedShell;
}

pub fn bashCompletion(
    buffer: []u8,
    comptime args: *const CliApp,
    app_name: []const u8,
) std.fmt.BufPrintError![]const u8 {
    var written: usize = 0;

    try appendBuf(buffer, &written, "# Completions for {s}\n\n", .{app_name});
    try appendBuf(buffer, &written, "_{s}()\n{{\n", .{app_name});
    try appendBuf(buffer, &written, "    local cur prev opts cmds general_opts cmd_opts\n", .{});
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
    try appendBuf(buffer, &written, "\"\n\n", .{});

    // Command-specific options
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
    try appendBuf(buffer, &written, "    esac\n\n", .{});

    try appendBuf(buffer, &written, "    opts=\"${{general_opts}} ${{cmd_opts}}\"\n\n", .{});

    const handle_opt_arg_type = struct {
        fn f(opt: Opt, buf: []u8, used: *usize) !void {
            if (opt.arg) |a| if (a.required) switch (a.type) {
                .Any => {},
                .Path => {
                    try appendBuf(buf, used, "        ", .{});
                    if (opt.short_name) |s| try appendBuf(buf, used, "-{s}|", .{s});
                    try appendBuf(
                        buf,
                        used,
                        "--{s}) COMPREPLY=( $(compgen -f -- \"$cur\") ); return 0 ;;\n",
                        .{opt.long_name},
                    );
                },
                else => {
                    try appendBuf(buf, used, "        ", .{});
                    if (opt.short_name) |s| try appendBuf(buf, used, "-{s}|", .{s});
                    try appendBuf(buf, used, "--{s}) return 0 ;;\n", .{opt.long_name});
                },
            };
        }
    }.f;

    // Option-specific arguments
    try appendBuf(buffer, &written, "    case \"$prev\" in\n", .{});
    for (args.options) |opt| try handle_opt_arg_type(opt, buffer, &written);
    for (args.commands) |cmd| if (cmd.options) |cmd_opts| for (cmd_opts) |opt|
        try handle_opt_arg_type(opt, buffer, &written);
    try appendBuf(buffer, &written, "    esac\n\n", .{});

    return try appendFmt(buffer, &written,
        \\    if [[ "$cur" == */* || -d "$cur" ]]; then
        \\        COMPREPLY=( $(compgen -f -- ${{cur}}) )
        \\        return 0
        \\    fi
        \\
        \\    if [[ ${{COMP_CWORD}} -eq 1 ]] ; then
        \\        COMPREPLY=( $(compgen -f -W "${{cmds}} ${{general_opts}}" -- ${{cur}}) )
        \\        return 0
        \\    fi
        \\
        \\    if [[ "$cur" == -* ]]; then
        \\        COMPREPLY=( $(compgen -f -W "${{opts}}" -- ${{cur}}) )
        \\        return 0
        \\    fi
        \\    COMPREPLY=( $(compgen -f -- ${{cur}}) )
        \\}}
        \\
        \\complete -o filenames -F _{0s} {0s}
    , .{app_name});
}

pub fn zshCompletion(
    buffer: []u8,
    comptime args: *const CliApp,
    app_name: []const u8,
) std.fmt.BufPrintError![]const u8 {
    var written: usize = 0;
    try appendBuf(buffer, &written, "#compdef _{0s} {0s}\n\n", .{app_name});

    try appendBuf(buffer, &written, "function _{s}() {{\n", .{app_name});
    try appendBuf(buffer, &written, "    local cur prev\n", .{});
    try appendBuf(buffer, &written, "    cur=${{words[CURRENT]}}\n", .{});
    try appendBuf(buffer, &written, "    prev=${{words[CURRENT-1]}}\n\n", .{});

    // Commands
    try appendBuf(buffer, &written, "    local -a cmds=(\n", .{});
    for (args.commands) |cmd| {
        try appendBuf(buffer, &written, "        '{s}:{s}'\n", .{
            cmd.name,
            cmd.desc,
        });
    }
    try appendBuf(buffer, &written, "    )\n\n", .{});

    // Options
    try appendBuf(buffer, &written, "    declare -a general_opts\n", .{});
    try appendBuf(buffer, &written, "    general_opts=(\n", .{});
    for (args.options) |opt| {
        try appendBuf(buffer, &written, "        ", .{});
        if (opt.short_name) |s| {
            try appendBuf(buffer, &written, "{{-{s},--{s}}}", .{ s, opt.long_name });
        } else try appendBuf(buffer, &written, "--{s}", .{opt.long_name});
        try appendBuf(buffer, &written, "'[{s}]'\n", .{opt.desc});
    }
    try appendBuf(buffer, &written, "    )\n\n", .{});

    // Command-specific options
    try appendBuf(buffer, &written, "    declare -a cmd_opts\n", .{});
    try appendBuf(buffer, &written, "    case ${{words[2]}} in\n", .{});
    for (args.commands) |cmd| {
        _ = try appendBuf(buffer, &written, "        {s})\n", .{cmd.name});
        _ = try appendBuf(buffer, &written, "            cmd_opts=(", .{});
        if (cmd.options) |cmd_opts| for (cmd_opts) |opt| {
            _ = try appendBuf(buffer, &written, "\n                ", .{});
            if (opt.short_name) |s| {
                try appendBuf(buffer, &written, "{{-{s},--{s}}}", .{ s, opt.long_name });
            } else try appendBuf(buffer, &written, "--{s}", .{opt.long_name});
            try appendBuf(buffer, &written, "'[{s}]'", .{opt.desc});
        };
        _ = try appendBuf(buffer, &written, ") ;;\n", .{});
    }
    try appendBuf(buffer, &written, "        *) cmd_opts=() ;;\n", .{});
    try appendBuf(buffer, &written, "    esac\n\n", .{});

    const handle_opt_arg_type = struct {
        fn f(opt: Opt, buf: []u8, used: *usize) !void {
            if (opt.arg) |a| if (a.required) switch (a.type) {
                .Any => {},
                .Path => {
                    try appendBuf(buf, used, "        ", .{});
                    if (opt.short_name) |s| try appendBuf(buf, used, "-{s}|", .{s});
                    try appendBuf(buf, used, "--{s}) _files; return ;;\n", .{opt.long_name});
                },
                else => {
                    try appendBuf(buf, used, "        ", .{});
                    if (opt.short_name) |s| try appendBuf(buf, used, "-{s}|", .{s});
                    try appendBuf(buf, used, "--{s}) return ;;\n", .{opt.long_name});
                },
            };
        }
    }.f;

    // Option-specific arguments
    try appendBuf(buffer, &written, "    case $prev in\n", .{});
    for (args.options) |opt| try handle_opt_arg_type(opt, buffer, &written);
    for (args.commands) |cmd| if (cmd.options) |cmd_opts| for (cmd_opts) |opt|
        try handle_opt_arg_type(opt, buffer, &written);
    try appendBuf(buffer, &written, "    esac\n", .{});

    try appendBuf(buffer, &written,
        \\
        \\    if (( CURRENT == 2 )); then
        \\         _describe -t commands '{s} command' cmds || compadd "$@"
        \\    fi
        \\
        \\
    , .{app_name});

    try appendBuf(buffer, &written, "    _arguments -S \\\n", .{});
    try appendBuf(buffer, &written, "        $general_opts \\\n", .{});
    try appendBuf(buffer, &written, "        $cmd_opts \\\n", .{});
    try appendBuf(buffer, &written, "        '*:filename:_files'\n", .{});
    return try appendFmt(buffer, &written, "}}\n", .{});
}

pub fn fishCompletion(
    buffer: []u8,
    comptime args: *const CliApp,
    app_name: []const u8,
) std.fmt.BufPrintError![]const u8 {
    var written: usize = 0;
    try appendBuf(buffer, &written, "# Completions for {s}\n", .{app_name});

    // Commands
    try appendBuf(buffer, &written, "\n# Commands\n", .{});
    for (args.commands) |cmd| {
        try appendBuf(
            buffer,
            &written,
            "complete -c {s} -n __fish_use_subcommand -a {s} -d \"{s}\"\n",
            .{ app_name, cmd.name, cmd.desc },
        );
    }

    const opt_line = struct {
        fn f(opt: Opt, buf: []u8, used: *usize) !void {
            if (opt.short_name) |s| try appendBuf(buf, used, " -s {s}", .{s});
            try appendBuf(buf, used, " -l {s}", .{opt.long_name});
            if (opt.arg) |a| {
                switch (a.type) {
                    .Any => {},
                    .Path => try appendBuf(buf, used, " --force-files", .{}),
                    else => try appendBuf(buf, used, " --no-files", .{}),
                }
                if (a.required) try appendBuf(buf, used, " -r", .{});
            } else try appendBuf(buf, used, " --no-files", .{});
            try appendBuf(buf, used, " -d \"{s}\"\n", .{opt.desc});
        }
    }.f;

    // Options
    try appendBuf(buffer, &written, "\n# Options\n", .{});
    for (args.options) |opt| {
        try appendBuf(buffer, &written, "complete -c {s}", .{app_name});
        try opt_line(opt, buffer, &written);
    }

    // Command-specific options
    for (args.commands) |cmd| if (cmd.options) |cmd_opts| for (cmd_opts) |opt| {
        try appendBuf(
            buffer,
            &written,
            "complete -c {s} -n \"__fish_seen_subcommand_from {s}\"",
            .{ app_name, cmd.name },
        );
        try opt_line(opt, buffer, &written);
    };

    return buffer[0..written];
}
