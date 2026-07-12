const std = @import("std");
const arg = @import("arg.zig");

const Cmd = arg.Cmd;
const Opt = arg.Opt;
const CliApp = arg.CliApp;

pub const Shell = enum {
    bash,
    zsh,
    fish,
};

/// Write the generated shell completion script using the given writer.
pub fn writeCompletion(
    writer: *std.Io.Writer,
    comptime spec: *const CliApp,
    app_name: []const u8,
    shell: Shell,
) std.Io.Writer.Error!void {
    comptime {
        const branch_quota = 200_000;
        @setEvalBranchQuota(branch_quota);
    }

    return switch (shell) {
        .bash => writeBashCompletion(writer, spec, app_name),
        .zsh => writeZshCompletion(writer, spec, app_name),
        .fish => writeFishCompletion(writer, spec, app_name),
    };
}

/// Generate and write the shell completion script to the provided buffer.
pub fn getCompletion(
    buffer: []u8,
    comptime spec: *const CliApp,
    app_name: []const u8,
    shell: Shell,
) error{NoSpaceLeft}![]const u8 {
    var w: std.Io.Writer = .fixed(buffer);
    writeCompletion(&w, spec, app_name, shell) catch |e| switch (e) {
        error.WriteFailed => return error.NoSpaceLeft,
    };
    return w.buffered();
}

/// Generate and allocate the shell completion script.
pub fn getCompletionOwned(
    allocator: std.mem.Allocator,
    comptime spec: *const CliApp,
    app_name: []const u8,
    shell: Shell,
) error{OutOfMemory}![]u8 {
    var w: std.Io.Writer.Allocating = .init(allocator);
    errdefer w.deinit();

    writeCompletion(&w.writer, spec, app_name, shell) catch |e| switch (e) {
        error.WriteFailed => return error.OutOfMemory,
    };
    return try w.toOwnedSlice();
}

fn writeBashCompletion(
    writer: *std.Io.Writer,
    comptime spec: *const CliApp,
    app_name: []const u8,
) std.Io.Writer.Error!void {
    comptime {
        const branch_quota = 200_000;
        @setEvalBranchQuota(branch_quota);
    }

    try writer.print("# Completions for {s}\n\n", .{app_name});
    try writer.print("_{s}()\n{{\n", .{app_name});
    try writer.print("    local cur prev opts cmds general_opts cmd_opts opts_with_args\n", .{});
    try writer.print("    local path w i expect_arg\n", .{});
    try writer.print("    COMPREPLY=()\n", .{});
    try writer.print("    cur=\"${{COMP_WORDS[COMP_CWORD]}}\"\n", .{});
    try writer.print("    prev=\"${{COMP_WORDS[COMP_CWORD-1]}}\"\n\n", .{});

    // Options that consume the next token as an argument.
    try writer.print("    opts_with_args=\"", .{});
    inline for (spec.options) |opt| {
        if (opt.arg != null) {
            if (opt.short_name) |s| try writer.print("-{s} ", .{s});
            try writer.print("--{s} ", .{opt.long_name});
        }
    }
    const emit_opts_with_args = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    if (opt.arg != null) {
                        if (opt.short_name) |s| try w.print("-{s} ", .{s});
                        try w.print("--{s} ", .{opt.long_name});
                    }
                };
                if (cmd.subcommands) |subs| try f(w, subs);
            }
        }
    }.f;
    try emit_opts_with_args(writer, spec.commands);
    try writer.print("\"\n", .{});

    // Global options
    try writer.print("    general_opts=\"", .{});
    for (spec.options) |opt| {
        if (opt.short_name) |s| try writer.print("-{s} ", .{s});
        try writer.print("--{s} ", .{opt.long_name});
    }
    try writer.print("\"\n\n", .{});

    // Resolve selected command path by scanning previous words
    try writer.print(
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
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            if (prefix.len == 0) {
                try w.print("            \"\") case \"$w\" in ", .{});
                inline for (cmds, 0..) |cmd, idx| {
                    if (idx != 0) try w.print("|", .{});
                    try w.print("{s}", .{cmd.name});
                }
                try w.print(") path=\"$w\" ;; *) break ;; esac ;;\n", .{});
            }

            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    try w.print("            \"{s}\") case \"$w\" in ", .{p});
                    inline for (subs, 0..) |sub, idx| {
                        if (idx != 0) try w.print("|", .{});
                        try w.print("{s}", .{sub.name});
                    }
                    try w.print(") path=\"$path $w\" ;; *) break ;; esac ;;\n", .{});
                    try f(w, subs, p);
                } else {
                    try w.print("            \"{s}\") break ;;\n", .{p});
                }
            }
        }
    }.f;
    try emit_select_cases(writer, spec.commands, "");

    try writer.print(
        \\
        \\            *) break ;;
        \\        esac
        \\        i=$((i+1))
        \\    done
        \\
    , .{});

    // Available subcommands at current path.
    try writer.print("    case \"$path\" in\n", .{});
    try writer.print("        \"\") cmds=\"", .{});
    for (spec.commands) |cmd| {
        try writer.print("{s} ", .{cmd.name});
    }
    try writer.print("\" ;;\n", .{});
    const emit_cmds_case = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try w.print("        \"{s}\") cmds=\"", .{p});
                if (cmd.subcommands) |subs| {
                    inline for (subs) |sub| {
                        try w.print("{s} ", .{sub.name});
                    }
                }
                try w.print("\" ;;\n", .{});
                if (cmd.subcommands) |subs| try f(w, subs, p);
            }
        }
    }.f;
    try emit_cmds_case(writer, spec.commands, "");
    try writer.print("        *) cmds=\"\" ;;\n    esac\n\n", .{});

    // Options for the current command node.
    try writer.print("    case \"$path\" in\n", .{});
    try writer.print("        \"\") cmd_opts=\"\" ;;\n", .{});
    const emit_cmd_opts_case = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try w.print("        \"{s}\") cmd_opts=\"", .{p});
                if (cmd.options) |opts| {
                    inline for (opts) |opt| {
                        if (opt.short_name) |s| try w.print("-{s} ", .{s});
                        try w.print("--{s} ", .{opt.long_name});
                    }
                }
                try w.print("\" ;;\n", .{});
                if (cmd.subcommands) |subs| try f(w, subs, p);
            }
        }
    }.f;
    try emit_cmd_opts_case(writer, spec.commands, "");
    try writer.print("        *) cmd_opts=\"\" ;;\n    esac\n\n", .{});

    try writer.print("    opts=\"$general_opts $cmd_opts\"\n\n", .{});

    const handle_opt_arg_type = struct {
        fn f(opt: Opt, w: *std.Io.Writer) std.Io.Writer.Error!void {
            if (opt.arg) |a| if (a.required) switch (a.type) {
                .Any => {},
                .Path => {
                    try w.print("        ", .{});
                    if (opt.short_name) |s| try w.print("-{s}|", .{s});
                    try w.print(
                        "--{s}) COMPREPLY=( $(compgen -f -- \"$cur\") ); return 0 ;;\n",
                        .{opt.long_name},
                    );
                },
                else => {
                    try w.print("        ", .{});
                    if (opt.short_name) |s| try w.print("-{s}|", .{s});
                    try w.print("--{s}) return 0 ;;\n", .{opt.long_name});
                },
            };
        }
    }.f;

    // Option-specific arguments
    try writer.print("    case \"$prev\" in\n", .{});
    for (spec.options) |opt| try handle_opt_arg_type(opt, writer);
    const emit_opt_arg_types = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    try handle_opt_arg_type(opt, w);
                };
                if (cmd.subcommands) |subs| try f(w, subs);
            }
        }
    }.f;
    try emit_opt_arg_types(writer, spec.commands);
    try writer.print("    esac\n\n", .{});

    try writer.print(
        \\    if [[ \"$cur\" == */* || -d \"$cur\" ]]; then
        \\        COMPREPLY=( $(compgen -f -- $cur) )
        \\        return 0
        \\    fi
        \\
        \\    if [[ $COMP_CWORD -eq 1 ]] ; then
        \\        COMPREPLY=( $(compgen -f -W \"$cmds $general_opts\" -- $cur) )
        \\        return 0
        \\    fi
        \\
        \\    if [[ \"$cur\" == -* ]]; then
        \\        COMPREPLY=( $(compgen -f -W \"$opts\" -- $cur) )
        \\        return 0
        \\    fi
        \\    if [[ -n \"$cmds\" ]]; then
        \\        COMPREPLY=( $(compgen -f -W \"$cmds\" -- $cur) )
        \\        return 0
        \\    fi
        \\    COMPREPLY=( $(compgen -f -- $cur) )
        \\}}
        \\
        \\complete -o filenames -F _{0s} {0s}
    , .{app_name});
}

fn writeZshCompletion(
    writer: *std.Io.Writer,
    comptime spec: *const CliApp,
    app_name: []const u8,
) std.Io.Writer.Error!void {
    comptime {
        const branch_quota = 200_000;
        @setEvalBranchQuota(branch_quota);
    }

    try writer.print("#compdef _{0s} {0s}\n\n", .{app_name});

    try writer.print("function _{s}() {{\n", .{app_name});
    try writer.print("    local cur prev path w i expect_arg\n", .{});
    try writer.print("    cur=$words[CURRENT]\n", .{});
    try writer.print("    prev=$words[CURRENT-1]\n", .{});
    try writer.print("    path=\"\"\n", .{});
    try writer.print("    expect_arg=0\n\n", .{});

    // Options that consume the next token as an argument.
    try writer.print("    local -a opts_with_args=( ", .{});
    inline for (spec.options) |opt| {
        if (opt.arg != null) {
            if (opt.short_name) |s| try writer.print("-{s} ", .{s});
            try writer.print("--{s} ", .{opt.long_name});
        }
    }
    const emit_opts_with_args = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    if (opt.arg != null) {
                        if (opt.short_name) |s| try w.print("-{s} ", .{s});
                        try w.print("--{s} ", .{opt.long_name});
                    }
                };
                if (cmd.subcommands) |subs| try f(w, subs);
            }
        }
    }.f;
    try emit_opts_with_args(writer, spec.commands);
    try writer.print(")\n\n", .{});

    // Walk words before CURRENT to resolve the selected command path.
    try writer.print(
        \\
        \\    i=2
        \\    while (( i < CURRENT )); do
        \\        w=$words[i]
        \\        if (( expect_arg )); then
        \\            expect_arg=0
        \\            (( i++ ))
        \\            continue
        \\        fi
        \\        if [[ \"$w\" == \"--\" ]]; then
        \\            break
        \\        fi
        \\        if [[ \"$w\" == --*=* ]]; then
        \\            (( i++ ))
        \\            continue
        \\        fi
        \\        if [[ \"$w\" == -* ]]; then
        \\            if (( $opts_with_args[(Ie)$w] )); then
        \\                expect_arg=1
        \\            fi
        \\            (( i++ ))
        \\            continue
        \\        fi
        \\        case \"$path\" in
    , .{});

    const emit_select_cases = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            if (prefix.len == 0) {
                try w.print("            \"\") case \"$w\" in ", .{});
                inline for (cmds, 0..) |cmd, idx| {
                    if (idx != 0) try w.print("|", .{});
                    try w.print("{s}", .{cmd.name});
                }
                try w.print(") path=\"$w\" ;; *) break ;; esac ;;\n", .{});
            }

            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    try w.print("            \"{s}\") case \"$w\" in ", .{p});
                    inline for (subs, 0..) |sub, idx| {
                        if (idx != 0) try w.print("|", .{});
                        try w.print("{s}", .{sub.name});
                    }
                    try w.print(") path=\"$path $w\" ;; *) break ;; esac ;;\n", .{});
                    try f(w, subs, p);
                } else {
                    try w.print("            \"{s}\") break ;;\n", .{p});
                }
            }
        }
    }.f;
    try emit_select_cases(writer, spec.commands, "");

    try writer.print(
        \\
        \\            *) break ;;
        \\        esac
        \\        (( i++ ))
        \\    done
        \\
    , .{});

    // Commands at the current node.
    try writer.print("    local -a cmds\n", .{});
    try writer.print("    case \"$path\" in\n", .{});
    try writer.print("        \"\") cmds=(\n", .{});
    inline for (spec.commands) |cmd| {
        try writer.print("            {s}\n", .{comptime zshDescribeItem(cmd.name, cmd.desc)});
    }
    try writer.print("        ) ;;\n", .{});
    const emit_cmds_case = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try w.print("        \"{s}\") cmds=(\n", .{p});
                if (cmd.subcommands) |subs| {
                    inline for (subs) |sub| {
                        try w.print("            {s}\n", .{comptime zshDescribeItem(sub.name, sub.desc)});
                    }
                }
                try w.print("        ) ;;\n", .{});
                if (cmd.subcommands) |subs| try f(w, subs, p);
            }
        }
    }.f;
    try emit_cmds_case(writer, spec.commands, "");
    try writer.print("        *) cmds=() ;;\n    esac\n\n", .{});

    try writer.print(
        \\
        \\    if [[ \"$cur\" != -* && $#cmds -gt 0 ]]; then
        \\        _describe -t commands '{s} command' cmds || compadd \"$@\"
        \\        return
        \\    fi
        \\
    , .{app_name});

    // Options
    try writer.print("    declare -a general_opts\n", .{});
    try writer.print("    general_opts=(\n", .{});
    inline for (spec.options) |opt| {
        try writer.print("        ", .{});
        if (opt.short_name) |s| {
            try writer.print("{{-{s},--{s}}}", .{ s, opt.long_name });
        } else {
            try writer.print("--{s}", .{opt.long_name});
        }
        try writer.print("{s}\n", .{comptime zshArgumentsDesc(opt.desc)});
    }
    try writer.print("    )\n\n", .{});

    // Command-specific options
    try writer.print("    declare -a cmd_opts\n", .{});
    try writer.print("    case \"$path\" in\n", .{});
    try writer.print("        \"\") cmd_opts=() ;;\n", .{});
    const emit_cmd_opts_case = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                try w.print("        \"{s}\") cmd_opts=(", .{p});
                if (cmd.options) |opts| inline for (opts) |opt| {
                    try w.print("\n            ", .{});
                    if (opt.short_name) |s| {
                        try w.print("{{-{s},--{s}}}", .{ s, opt.long_name });
                    } else {
                        try w.print("--{s}", .{opt.long_name});
                    }
                    try w.print("{s}", .{comptime zshArgumentsDesc(opt.desc)});
                };
                try w.print(") ;;\n", .{});
                if (cmd.subcommands) |subs| try f(w, subs, p);
            }
        }
    }.f;
    try emit_cmd_opts_case(writer, spec.commands, "");
    try writer.print("        *) cmd_opts=() ;;\n    esac\n\n", .{});

    const handle_opt_arg_type = struct {
        fn f(opt: Opt, w: *std.Io.Writer) std.Io.Writer.Error!void {
            if (opt.arg) |a| if (a.required) switch (a.type) {
                .Any => {},
                .Path => {
                    try w.print("        ", .{});
                    if (opt.short_name) |s| try w.print("-{s}|", .{s});
                    try w.print("--{s}) _files; return ;;\n", .{opt.long_name});
                },
                else => {
                    try w.print("        ", .{});
                    if (opt.short_name) |s| try w.print("-{s}|", .{s});
                    try w.print("--{s}) return ;;\n", .{opt.long_name});
                },
            };
        }
    }.f;

    // Option-specific arguments
    try writer.print("    case $prev in\n", .{});
    for (spec.options) |opt| try handle_opt_arg_type(opt, writer);
    const emit_opt_arg_types = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    try handle_opt_arg_type(opt, w);
                };
                if (cmd.subcommands) |subs| try f(w, subs);
            }
        }
    }.f;
    try emit_opt_arg_types(writer, spec.commands);
    try writer.print("    esac\n\n", .{});

    try writer.print("    _arguments -S \\\n", .{});
    try writer.print("        $general_opts \\\n", .{});
    try writer.print("        $cmd_opts \\\n", .{});
    try writer.print("        '*:filename:_files'\n", .{});
    try writer.print("}}\n", .{});
}

fn writeFishCompletion(
    writer: *std.Io.Writer,
    comptime spec: *const CliApp,
    app_name: []const u8,
) std.Io.Writer.Error!void {
    comptime {
        const branch_quota = 200_000;
        @setEvalBranchQuota(branch_quota);
    }

    try writer.print("# Completions for {s}\n", .{app_name});

    // Resolve the leaf command path (tokens) according to zcli parsing rules.
    try writer.print("\n# Helpers\n", .{});
    try writer.print("function __{s}_leaf_path_tokens\n", .{app_name});
    try writer.print("    set -l words (commandline -opc)\n", .{});
    try writer.print("    set -l path\n", .{});
    try writer.print("    set -l expect_arg 0\n", .{});

    try writer.print("    set -l opts_with_args ", .{});
    inline for (spec.options) |opt| {
        if (opt.arg != null) {
            if (opt.short_name) |s| try writer.print("-{s} ", .{s});
            try writer.print("--{s} ", .{opt.long_name});
        }
    }
    const emit_opts_with_args = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                if (cmd.options) |opts| inline for (opts) |opt| {
                    if (opt.arg != null) {
                        if (opt.short_name) |s| try w.print("-{s} ", .{s});
                        try w.print("--{s} ", .{opt.long_name});
                    }
                };
                if (cmd.subcommands) |subs| try f(w, subs);
            }
        }
    }.f;
    try emit_opts_with_args(writer, spec.commands);
    try writer.print("\n", .{});

    try writer.print(
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
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8) std.Io.Writer.Error!void {
            if (prefix.len == 0) {
                try w.print("            case ''\n", .{});
                try w.print("                switch $w\n", .{});
                try w.print("                    case ", .{});
                inline for (cmds) |cmd| {
                    try w.print("{s} ", .{cmd.name});
                }
                try w.print("\n                        set path $w\n", .{});
                try w.print("                    case '*'\n                        break\n                end\n", .{});
            }

            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    try w.print("            case '{s}'\n", .{p});
                    try w.print("                switch $w\n", .{});
                    try w.print("                    case ", .{});
                    inline for (subs) |sub| {
                        try w.print("{s} ", .{sub.name});
                    }
                    try w.print("\n                        set path $path $w\n", .{});
                    try w.print("                    case '*'\n                        break\n                end\n", .{});
                    try f(w, subs, p);
                } else {
                    try w.print("            case '{s}'\n                break\n", .{p});
                }
            }
        }
    }.f;
    try emit_select_cases(writer, spec.commands, "");

    try writer.print(
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
    try writer.print("\n# Commands\n", .{});
    for (spec.commands) |cmd| {
        try writer.print(
            "complete -c {s} -n __{s}_at_root -a {s} -d \"{s}\"\n",
            .{ app_name, app_name, cmd.name, cmd.desc },
        );
    }
    const emit_subcommands = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8, app: []const u8) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.subcommands) |subs| {
                    inline for (subs) |sub| {
                        try writer.print(
                            "complete -c {s} -n \"__{s}_is_path {s}\" -a {s} -d \"{s}\"\n",
                            .{ app, app, p, sub.name, sub.desc },
                        );
                    }
                    try f(w, subs, p, app);
                }
            }
        }
    }.f;
    try emit_subcommands(writer, spec.commands, "", app_name);

    const opt_line = struct {
        fn f(opt: Opt, w: *std.Io.Writer) std.Io.Writer.Error!void {
            if (opt.short_name) |s| try w.print(" -s {s}", .{s});
            try w.print(" -l {s}", .{opt.long_name});
            if (opt.arg) |a| {
                switch (a.type) {
                    .Any => {},
                    .Path => try w.print(" --force-files", .{}),
                    else => try w.print(" --no-files", .{}),
                }
                if (a.required) try w.print(" -r", .{});
            } else {
                try w.print(" --no-files", .{});
            }
            try w.print(" -d \"{s}\"\n", .{opt.desc});
        }
    }.f;

    // Options
    try writer.print("\n# Options\n", .{});
    for (spec.options) |opt| {
        try writer.print("complete -c {s}", .{app_name});
        try opt_line(opt, writer);
    }

    // Command-specific options
    const emit_cmd_opts = struct {
        fn f(w: *std.Io.Writer, comptime cmds: []const Cmd, comptime prefix: []const u8, app: []const u8) std.Io.Writer.Error!void {
            inline for (cmds) |cmd| {
                const p = if (prefix.len == 0) cmd.name else (prefix ++ " " ++ cmd.name);
                if (cmd.options) |cmd_opts| for (cmd_opts) |opt| {
                    try w.print(
                        "complete -c {s} -n \"__{s}_is_path {s}\"",
                        .{ app, app, p },
                    );
                    try opt_line(opt, w);
                };
                if (cmd.subcommands) |subs| try f(w, subs, p, app);
            }
        }
    }.f;
    try emit_cmd_opts(writer, spec.commands, "", app_name);
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
