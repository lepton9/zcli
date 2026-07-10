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
    comptime {
        const branch_quota = 200_000;
        @setEvalBranchQuota(branch_quota);
    }

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
    try appendBuf(buffer, &written, "    local cur prev opts cmds general_opts cmd_opts opts_with_args\n", .{});
    try appendBuf(buffer, &written, "    local path w i expect_arg\n", .{});
    try appendBuf(buffer, &written, "    COMPREPLY=()\n", .{});
    try appendBuf(buffer, &written, "    cur=\"${{COMP_WORDS[COMP_CWORD]}}\"\n", .{});
    try appendBuf(buffer, &written, "    prev=\"${{COMP_WORDS[COMP_CWORD-1]}}\"\n\n", .{});

    // Options that consume the next token as an argument.
    try appendBuf(buffer, &written, "    opts_with_args=\"", .{});
    inline for (args.options) |opt| {
        if (opt.arg != null) {
            if (opt.short_name) |s| _ = try appendBuf(buffer, &written, "-{s} ", .{s});
            try appendBuf(buffer, &written, "--{s} ", .{opt.long_name});
        }
    }
    const emit_opts_with_args = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd) !void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    if (opt.arg != null) {
                        if (opt.short_name) |s| _ = try appendBuf(buf, used, "-{s} ", .{s});
                        _ = try appendBuf(buf, used, "--{s} ", .{opt.long_name});
                    }
                };
                if (cmd.subcommands) |subs| try f(buf, used, subs);
            }
        }
    }.f;
    try emit_opts_with_args(buffer, &written, args.commands);
    try appendBuf(buffer, &written, "\"\n", .{});

    // Global options
    try appendBuf(buffer, &written, "    general_opts=\"", .{});
    for (args.options) |opt| {
        if (opt.short_name) |s| _ = try appendBuf(buffer, &written, "-{s} ", .{s});
        try appendBuf(buffer, &written, "--{s} ", .{opt.long_name});
    }
    try appendBuf(buffer, &written, "\"\n\n", .{});

    // Resolve selected command path by scanning previous words
    try appendBuf(buffer, &written,
        \\
        \\    path=""
        \\    expect_arg=0
        \\    i=1
        \\    while [[ $i -lt $COMP_CWORD ]]; do
        \\        w="${{COMP_WORDS[$i]}}"
        \\        if [[ $expect_arg -eq 1 ]]; then
        \\            expect_arg=0
        \\            i=$((i+1))
        \\            continue
        \\        fi
        \\        if [[ "$w" == "--" ]]; then
        \\            break
        \\        fi
        \\        if [[ "$w" == --*=* ]]; then
        \\            i=$((i+1))
        \\            continue
        \\        fi
        \\        if [[ "$w" == -* ]]; then
        \\            if [[ " $opts_with_args " == *" $w "* ]]; then
        \\                expect_arg=1
        \\            fi
        \\            i=$((i+1))
        \\            continue
        \\        fi
        \\        case "$path" in
    , .{});

    const emit_select_cases = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            if (prefix.len == 0) {
                try appendBuf(buf, used, "            \"\") case \"$w\" in ", .{});
                inline for (cmds, 0..) |cmd, idx| {
                    if (idx != 0) try appendBuf(buf, used, "|", .{});
                    try appendBuf(buf, used, "{s}", .{cmd.name});
                }
                try appendBuf(buf, used, ") path=\"$w\" ;; *) break ;; esac ;;\n", .{});
            }

            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    try appendBuf(buf, used, "            \"{s}\") case \"$w\" in ", .{p});
                    inline for (subs, 0..) |sub, idx| {
                        if (idx != 0) try appendBuf(buf, used, "|", .{});
                        try appendBuf(buf, used, "{s}", .{sub.name});
                    }
                    try appendBuf(buf, used, ") path=\"$path $w\" ;; *) break ;; esac ;;\n", .{});
                    try f(buf, used, subs, p);
                } else {
                    try appendBuf(buf, used, "            \"{s}\") break ;;\n", .{p});
                }
            }
        }
    }.f;
    try emit_select_cases(buffer, &written, args.commands, "");

    try appendBuf(buffer, &written,
        \\
        \\            *) break ;;
        \\        esac
        \\        i=$((i+1))
        \\    done
        \\
    , .{});

    // Available subcommands at current path.
    try appendBuf(buffer, &written, "    case \"$path\" in\n", .{});
    try appendBuf(buffer, &written, "        \"\") cmds=\"", .{});
    for (args.commands) |cmd| {
        try appendBuf(buffer, &written, "{s} ", .{cmd.name});
    }
    try appendBuf(buffer, &written, "\" ;;\n", .{});
    const emit_cmds_case = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try appendBuf(buf, used, "        \"{s}\") cmds=\"", .{p});
                if (cmd.subcommands) |subs| {
                    inline for (subs) |sub| {
                        try appendBuf(buf, used, "{s} ", .{sub.name});
                    }
                }
                try appendBuf(buf, used, "\" ;;\n", .{});
                if (cmd.subcommands) |subs| try f(buf, used, subs, p);
            }
        }
    }.f;
    try emit_cmds_case(buffer, &written, args.commands, "");
    try appendBuf(buffer, &written, "        *) cmds=\"\" ;;\n    esac\n\n", .{});

    // Options for the current command node.
    try appendBuf(buffer, &written, "    case \"$path\" in\n", .{});
    try appendBuf(buffer, &written, "        \"\") cmd_opts=\"\" ;;\n", .{});
    const emit_cmd_opts_case = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try appendBuf(buf, used, "        \"{s}\") cmd_opts=\"", .{p});
                if (cmd.options) |opts| {
                    inline for (opts) |opt| {
                        if (opt.short_name) |s| _ = try appendBuf(buf, used, "-{s} ", .{s});
                        _ = try appendBuf(buf, used, "--{s} ", .{opt.long_name});
                    }
                }
                try appendBuf(buf, used, "\" ;;\n", .{});
                if (cmd.subcommands) |subs| try f(buf, used, subs, p);
            }
        }
    }.f;
    try emit_cmd_opts_case(buffer, &written, args.commands, "");
    try appendBuf(buffer, &written, "        *) cmd_opts=\"\" ;;\n    esac\n\n", .{});

    try appendBuf(buffer, &written, "    opts=\"$general_opts $cmd_opts\"\n\n", .{});

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
    const emit_opt_arg_types = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd) !void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    try handle_opt_arg_type(opt, buf, used);
                };
                if (cmd.subcommands) |subs| try f(buf, used, subs);
            }
        }
    }.f;
    try emit_opt_arg_types(buffer, &written, args.commands);
    try appendBuf(buffer, &written, "    esac\n\n", .{});

    return try appendFmt(buffer, &written,
        \\    if [[ "$cur" == */* || -d "$cur" ]]; then
        \\        COMPREPLY=( $(compgen -f -- $cur) )
        \\        return 0
        \\    fi
        \\
        \\    if [[ $COMP_CWORD -eq 1 ]] ; then
        \\        COMPREPLY=( $(compgen -f -W "$cmds $general_opts" -- $cur) )
        \\        return 0
        \\    fi
        \\
        \\    if [[ "$cur" == -* ]]; then
        \\        COMPREPLY=( $(compgen -f -W "$opts" -- $cur) )
        \\        return 0
        \\    fi
        \\    if [[ -n "$cmds" ]]; then
        \\        COMPREPLY=( $(compgen -f -W "$cmds" -- $cur) )
        \\        return 0
        \\    fi
        \\    COMPREPLY=( $(compgen -f -- $cur) )
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
    try appendBuf(buffer, &written, "    local cur prev path w i expect_arg\n", .{});
    try appendBuf(buffer, &written, "    cur=$words[CURRENT]\n", .{});
    try appendBuf(buffer, &written, "    prev=$words[CURRENT-1]\n", .{});
    try appendBuf(buffer, &written, "    path=\"\"\n", .{});
    try appendBuf(buffer, &written, "    expect_arg=0\n\n", .{});

    // Options that consume the next token as an argument
    try appendBuf(buffer, &written, "    local -a opts_with_args=( ", .{});
    inline for (args.options) |opt| {
        if (opt.arg != null) {
            if (opt.short_name) |s| _ = try appendBuf(buffer, &written, "-{s} ", .{s});
            try appendBuf(buffer, &written, "--{s} ", .{opt.long_name});
        }
    }
    const emit_opts_with_args = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd) !void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    if (opt.arg != null) {
                        if (opt.short_name) |s| _ = try appendBuf(buf, used, "-{s} ", .{s});
                        _ = try appendBuf(buf, used, "--{s} ", .{opt.long_name});
                    }
                };
                if (cmd.subcommands) |subs| try f(buf, used, subs);
            }
        }
    }.f;
    try emit_opts_with_args(buffer, &written, args.commands);
    try appendBuf(buffer, &written, ")\n\n", .{});

    // Walk words before CURRENT to resolve the selected command path
    try appendBuf(buffer, &written,
        \\
        \\    i=2
        \\    while (( i < CURRENT )); do
        \\        w=$words[i]
        \\        if (( expect_arg )); then
        \\            expect_arg=0
        \\            (( i++ ))
        \\            continue
        \\        fi
        \\        if [[ "$w" == "--" ]]; then
        \\            break
        \\        fi
        \\        if [[ "$w" == --*=* ]]; then
        \\            (( i++ ))
        \\            continue
        \\        fi
        \\        if [[ "$w" == -* ]]; then
        \\            if (( $opts_with_args[(Ie)$w] )); then
        \\                expect_arg=1
        \\            fi
        \\            (( i++ ))
        \\            continue
        \\        fi
        \\        case "$path" in
    , .{});

    const emit_select_cases = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            if (prefix.len == 0) {
                try appendBuf(buf, used, "            \"\") case \"$w\" in ", .{});
                inline for (cmds, 0..) |cmd, idx| {
                    if (idx != 0) try appendBuf(buf, used, "|", .{});
                    try appendBuf(buf, used, "{s}", .{cmd.name});
                }
                try appendBuf(buf, used, ") path=\"$w\" ;; *) break ;; esac ;;\n", .{});
            }

            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    try appendBuf(buf, used, "            \"{s}\") case \"$w\" in ", .{p});
                    inline for (subs, 0..) |sub, idx| {
                        if (idx != 0) try appendBuf(buf, used, "|", .{});
                        try appendBuf(buf, used, "{s}", .{sub.name});
                    }
                    try appendBuf(buf, used, ") path=\"$path $w\" ;; *) break ;; esac ;;\n", .{});
                    try f(buf, used, subs, p);
                } else {
                    try appendBuf(buf, used, "            \"{s}\") break ;;\n", .{p});
                }
            }
        }
    }.f;
    try emit_select_cases(buffer, &written, args.commands, "");

    try appendBuf(buffer, &written,
        \\
        \\            *) break ;;
        \\        esac
        \\        (( i++ ))
        \\    done
        \\
    , .{});

    // Commands at the current node
    try appendBuf(buffer, &written, "    local -a cmds\n", .{});
    try appendBuf(buffer, &written, "    case \"$path\" in\n", .{});
    try appendBuf(buffer, &written, "        \"\") cmds=(\n", .{});
    inline for (args.commands) |cmd| {
        try appendBuf(buffer, &written, "            {s}\n", .{comptime zshDescribeItem(cmd.name, cmd.desc)});
    }
    try appendBuf(buffer, &written, "        ) ;;\n", .{});
    const emit_cmds_case = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try appendBuf(buf, used, "        \"{s}\") cmds=(\n", .{p});
                if (cmd.subcommands) |subs| {
                    inline for (subs) |sub| {
                        try appendBuf(buf, used, "            {s}\n", .{comptime zshDescribeItem(sub.name, sub.desc)});
                    }
                }
                try appendBuf(buf, used, "        ) ;;\n", .{});
                if (cmd.subcommands) |subs| try f(buf, used, subs, p);
            }
        }
    }.f;
    try emit_cmds_case(buffer, &written, args.commands, "");
    try appendBuf(buffer, &written, "        *) cmds=() ;;\n    esac\n\n", .{});

    try appendBuf(buffer, &written,
        \\
        \\    if [[ "$cur" != -* && $#cmds -gt 0 ]]; then
        \\        _describe -t commands '{s} command' cmds || compadd "$@"
        \\        return
        \\    fi
        \\
    , .{app_name});

    // Options
    try appendBuf(buffer, &written, "    declare -a general_opts\n", .{});
    try appendBuf(buffer, &written, "    general_opts=(\n", .{});
    inline for (args.options) |opt| {
        try appendBuf(buffer, &written, "        ", .{});
        if (opt.short_name) |s| {
            try appendBuf(buffer, &written, "{{-{s},--{s}}}", .{ s, opt.long_name });
        } else try appendBuf(buffer, &written, "--{s}", .{opt.long_name});
        try appendBuf(buffer, &written, "{s}\n", .{comptime zshArgumentsDesc(opt.desc)});
    }
    try appendBuf(buffer, &written, "    )\n\n", .{});

    // Command-specific options
    try appendBuf(buffer, &written, "    declare -a cmd_opts\n", .{});
    try appendBuf(buffer, &written, "    case \"$path\" in\n", .{});
    try appendBuf(buffer, &written, "        \"\") cmd_opts=() ;;\n", .{});
    const emit_cmd_opts_case = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try appendBuf(buf, used, "        \"{s}\") cmd_opts=(", .{p});
                if (cmd.options) |opts| inline for (opts) |opt| {
                    _ = try appendBuf(buf, used, "\n            ", .{});
                    if (opt.short_name) |s| {
                        try appendBuf(buf, used, "{{-{s},--{s}}}", .{ s, opt.long_name });
                    } else try appendBuf(buf, used, "--{s}", .{opt.long_name});
                    try appendBuf(buf, used, "{s}", .{comptime zshArgumentsDesc(opt.desc)});
                };
                try appendBuf(buf, used, ") ;;\n", .{});
                if (cmd.subcommands) |subs| try f(buf, used, subs, p);
            }
        }
    }.f;
    try emit_cmd_opts_case(buffer, &written, args.commands, "");
    try appendBuf(buffer, &written, "        *) cmd_opts=() ;;\n    esac\n\n", .{});

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
    const emit_opt_arg_types = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd) !void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    try handle_opt_arg_type(opt, buf, used);
                };
                if (cmd.subcommands) |subs| try f(buf, used, subs);
            }
        }
    }.f;
    try emit_opt_arg_types(buffer, &written, args.commands);
    try appendBuf(buffer, &written, "    esac\n\n", .{});

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

    // Resolve the leaf command path
    try appendBuf(buffer, &written, "\n# Helpers\n", .{});
    try appendBuf(buffer, &written, "function __{s}_leaf_path_tokens\n", .{app_name});
    try appendBuf(buffer, &written, "    set -l words (commandline -opc)\n", .{});
    try appendBuf(buffer, &written, "    set -l path\n", .{});
    try appendBuf(buffer, &written, "    set -l expect_arg 0\n", .{});

    try appendBuf(buffer, &written, "    set -l opts_with_args ", .{});
    inline for (args.options) |opt| {
        if (opt.arg != null) {
            if (opt.short_name) |s| _ = try appendBuf(buffer, &written, "-{s} ", .{s});
            try appendBuf(buffer, &written, "--{s} ", .{opt.long_name});
        }
    }
    const emit_opts_with_args = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd) !void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    if (opt.arg != null) {
                        if (opt.short_name) |s| _ = try appendBuf(buf, used, "-{s} ", .{s});
                        _ = try appendBuf(buf, used, "--{s} ", .{opt.long_name});
                    }
                };
                if (cmd.subcommands) |subs| try f(buf, used, subs);
            }
        }
    }.f;
    try emit_opts_with_args(buffer, &written, args.commands);
    try appendBuf(buffer, &written, "\n", .{});

    try appendBuf(buffer, &written,
        \\
        \\    for w in $words[2..-1]
        \\        if test $expect_arg -eq 1
        \\            set expect_arg 0
        \\            continue
        \\        end
        \\        if test "$w" = "--"
        \\            break
        \\        end
        \\        if string match -qr '^--.+=.+' -- $w
        \\            continue
        \\        end
        \\        if string match -qr '^-' -- $w
        \\            if contains -- $w $opts_with_args
        \\                set expect_arg 1
        \\            end
        \\            continue
        \\        end
        \\
        \\        set -l p (string join ' ' $path)
        \\        switch $p
    , .{});

    const emit_select_cases = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8) !void {
            if (prefix.len == 0) {
                try appendBuf(buf, used, "            case ''\n", .{});
                try appendBuf(buf, used, "                switch $w\n", .{});
                try appendBuf(buf, used, "                    case ", .{});
                inline for (cmds) |cmd| {
                    try appendBuf(buf, used, "{s} ", .{cmd.name});
                }
                try appendBuf(buf, used, "\n                        set path $w\n", .{});
                try appendBuf(buf, used, "                    case '*'\n                        break\n                end\n", .{});
            }

            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    try appendBuf(buf, used, "            case '{s}'\n", .{p});
                    try appendBuf(buf, used, "                switch $w\n", .{});
                    try appendBuf(buf, used, "                    case ", .{});
                    inline for (subs) |sub| {
                        try appendBuf(buf, used, "{s} ", .{sub.name});
                    }
                    try appendBuf(buf, used, "\n                        set path $path $w\n", .{});
                    try appendBuf(buf, used, "                    case '*'\n                        break\n                end\n", .{});
                    try f(buf, used, subs, p);
                } else {
                    try appendBuf(buf, used, "            case '{s}'\n                break\n", .{p});
                }
            }
        }
    }.f;
    try emit_select_cases(buffer, &written, args.commands, "");

    try appendBuf(buffer, &written,
        \\
        \\            case '*'
        \\                break
        \\        end
        \\    end
        \\    echo $path
        \\end
        \\
        \\function __{0s}_at_root
        \\    test (count (__{0s}_leaf_path_tokens)) -eq 0
        \\end
        \\
        \\function __{0s}_is_path
        \\    set -l have (__{0s}_leaf_path_tokens)
        \\    set -l want $argv
        \\    if test (count $have) -ne (count $want)
        \\        return 1
        \\    end
        \\    for i in (seq 1 (count $want))
        \\        if test $have[$i] != $want[$i]
        \\            return 1
        \\        end
        \\    end
        \\    return 0
        \\end
        \\
    , .{app_name});

    // Commands
    try appendBuf(buffer, &written, "\n# Commands\n", .{});
    for (args.commands) |cmd| {
        try appendBuf(
            buffer,
            &written,
            "complete -c {s} -n __{s}_at_root -a {s} -d \"{s}\"\n",
            .{ app_name, app_name, cmd.name, cmd.desc },
        );
    }
    const emit_subcommands = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8, app: []const u8) !void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    inline for (subs) |sub| {
                        try appendBuf(
                            buf,
                            used,
                            "complete -c {s} -n \"__{s}_is_path {s}\" -a {s} -d \"{s}\"\n",
                            .{ app, app, p, sub.name, sub.desc },
                        );
                    }
                    try f(buf, used, subs, p, app);
                }
            }
        }
    }.f;
    try emit_subcommands(buffer, &written, args.commands, "", app_name);

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
    const emit_cmd_opts = struct {
        fn f(buf: []u8, used: *usize, comptime cmds: []const Cmd, comptime prefix: []const u8, app: []const u8) !void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.options) |cmd_opts| for (cmd_opts) |opt| {
                    try appendBuf(
                        buf,
                        used,
                        "complete -c {s} -n \"__{s}_is_path {s}\"",
                        .{ app, app, p },
                    );
                    try opt_line(opt, buf, used);
                };
                if (cmd.subcommands) |subs| try f(buf, used, subs, p, app);
            }
        }
    }.f;
    try emit_cmd_opts(buffer, &written, args.commands, "", app_name);

    return buffer[0..written];
}

/// Build a zsh `_arguments` description token (`'[desc]'`) with safe escaping.
fn zshArgumentsDesc(comptime desc: []const u8) []const u8 {
    var out: []const u8 = "'[";
    for (desc) |c| {
        out = out ++ switch (c) {
            '\\', '[', ']' => &[_]u8{ '\\', c },
            '\'' => "'\\''",
            else => &[_]u8{c},
        };
    }
    out = out ++ "]'";
    return out;
}

/// Format and sanitize entries like 'name:description'.
fn zshDescribeItem(comptime name: []const u8, comptime desc: []const u8) []const u8 {
    var out: []const u8 = "'";
    for (name) |c| {
        out = out ++ switch (c) {
            ':' => "\\:",
            '\\' => "\\\\", // Prevent backslashes from acting as escape prefixes.
            '\'' => "'\\''",
            else => &[_]u8{c},
        };
    }
    out = out ++ ":";
    for (desc) |c| {
        out = out ++ switch (c) {
            '\\' => "\\\\",
            '\'' => "'\\''",
            else => &[_]u8{c},
        };
    }
    out = out ++ "'";
    return out;
}
