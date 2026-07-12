const std = @import("std");
const zcli = @import("zcli");
const app_mod = @import("app");
const gen_opts = @import("zcli_gen_options");

const app_decl_name: []const u8 = gen_opts.app_decl_name;

comptime {
    if (app_decl_name.len == 0) {
        @compileError("zcli completion generator: app_decl_name must not be empty");
    }
    if (!@hasDecl(app_mod, app_decl_name)) {
        @compileError(
            "zcli completion generator: the imported module does not export the configured CliApp decl",
        );
    }

    const app_val = @field(app_mod, app_decl_name);
    if (@TypeOf(app_val) != zcli.CliApp) {
        @compileError(
            "zcli completion generator: configured decl must have type `zcli.CliApp`",
        );
    }
    if (app_val.config.name == null) {
        @compileError(
            "zcli completions require `CliApp.config.name` to be set (used for completion file names)",
        );
    }
}

const app_spec: zcli.CliApp = @field(app_mod, app_decl_name);
const app_name: []const u8 = app_spec.config.name.?;

const Shell = zcli.complete.Shell;

fn parseShell(s: []const u8) ?Shell {
    return std.meta.stringToEnum(Shell, s);
}

fn usage() []const u8 {
    return
    \\Usage: gen_completion --out-dir <dir> [--shell bash|zsh|fish]...
    \\Generates shell completion files for the app.
    \\
    ;
}

fn writeCompletionFile(
    io: std.Io,
    arena: std.mem.Allocator,
    out_dir: []const u8,
    shell: Shell,
) !void {
    const file_name = try switch (shell) {
        .bash => std.fmt.allocPrint(arena, "{s}", .{app_name}),
        .zsh => std.fmt.allocPrint(arena, "_{s}", .{app_name}),
        .fish => std.fmt.allocPrint(arena, "{s}.fish", .{app_name}),
    };
    const cwd = std.Io.Dir.cwd();

    const path = try std.fs.path.join(arena, &.{ out_dir, file_name });
    try cwd.createDirPath(io, out_dir);

    var f = try cwd.createFile(io, path, .{ .truncate = true });
    defer f.close(io);

    var buf: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(f, io, &buf);
    const w = &writer.interface;

    try zcli.complete.writeCompletion(w, &app_spec, app_name, shell);
    try w.flush();
}

fn getOptionValue(
    it: *std.process.Args.Iterator,
    arg: []const u8,
    option: []const u8,
) !?[]const u8 {
    if (!std.mem.startsWith(u8, arg, option)) return null;
    if (arg.len >= option.len + 1 and arg[option.len] == '=') {
        return arg[option.len + 1 ..];
    }
    return it.next() orelse return error.InvalidArgs;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var out_dir: ?[]const u8 = null;
    var shells: std.ArrayListUnmanaged(Shell) = .empty;

    var it = try init.minimal.args.iterateAllocator(gpa);
    defer it.deinit();
    _ = it.skip();

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.log.err("{s}", .{usage()});
            return error.InvalidArgs;
        }

        if (try getOptionValue(&it, arg, "--out-dir")) |value| {
            out_dir = value;
            continue;
        }
        if (try getOptionValue(&it, arg, "--shell")) |value| {
            const sh = parseShell(value) orelse return error.InvalidArgs;
            try shells.append(arena, sh);
            continue;
        }

        std.log.err("unknown arg: {s}\n{s}", .{ arg, usage() });
        return error.InvalidArgs;
    }

    const out = out_dir orelse {
        std.log.err("missing --out-dir\n{s}", .{usage()});
        return error.InvalidArgs;
    };

    try std.Io.Dir.cwd().createDirPath(io, out);

    for (shells.items) |sh| try writeCompletionFile(io, arena, out, sh);
}
