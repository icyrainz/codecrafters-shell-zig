const std = @import("std");
const Term = std.process.Child.Term;

const enable_debug = true;
const debug_print = if (enable_debug) std.debug.print else void_print;
fn void_print(comptime _: []const u8, _: anytype) void {}

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

var arenaAllocator: std.mem.Allocator = undefined;

const Command = struct {
    name: []const u8,
    execute: *const fn ([]const []const u8, std.mem.Allocator) anyerror!void,
};

const Shell = struct {
    allocator: std.mem.Allocator,
    commands: std.StringHashMap(*const Command),

    const Self = @This();

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .commands = std.StringHashMap(*const Command).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.commands.deinit();
    }

    fn registerCommand(self: *Self, command: *const Command) !void {
        try self.commands.put(command.name, command);
    }

    fn processCommand(self: *Self, input: []const u8) !void {
        var cmd_iter = std.mem.tokenizeAny(u8, input, " ");
        const cmd_name = cmd_iter.next() orelse return;

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        while (cmd_iter.next()) |arg| {
            try args.append(arg);
        }

        if (self.commands.get(cmd_name)) |command| {
            try command.execute(args.items, self.allocator);
            return;
        }

        try self.runExternalCommand(cmd_name, args.items);
    }

    fn runExternalCommand(self: *Self, cmd: []const u8, args: []const []const u8) !void {
        const full_path = try findFullPath(cmd) orelse {
            try stdout.print("{s}: command not found\n", .{cmd});
            return;
        };

        const exe_path = try std.fmt.allocPrint(arenaAllocator, "{s}/{s}", .{ full_path, cmd });

        var process_args = std.ArrayList([]const u8).init(self.allocator);
        defer process_args.deinit();
        try process_args.append(exe_path);
        try process_args.appendSlice(args);

        var child = std.process.Child.init(process_args.items, self.allocator);
        _ = try child.spawnAndWait();
    }
};

const PwdCommand = Command{
    .name = "pwd",
    .execute = struct {
        fn execute(_: []const []const u8, allocator: std.mem.Allocator) anyerror!void {
            const cwd = try std.process.getCwdAlloc(allocator);
            try stdout.print("{s}\n", .{cwd});
        }
    }.execute,
};

const ExitCommand = Command{
    .name = "exit",
    .execute = struct {
        fn execute(_: []const []const u8, _: std.mem.Allocator) anyerror!void {
            std.process.exit(0);
        }
    }.execute,
};

const EchoCommand = Command{
    .name = "echo",
    .execute = struct {
        fn execute(args: []const []const u8, _: std.mem.Allocator) anyerror!void {
            const echo_string = try std.mem.join(arenaAllocator, " ", args);
            try stdout.print("{s}\n", .{echo_string});
        }
    }.execute,
};

const TypeCommand = Command{
    .name = "type",
    .execute = struct {
        fn execute(args: []const []const u8, _: std.mem.Allocator) anyerror!void {
            if (args.len == 0) {
                try stdout.print("type: missing argument\n", .{});
                return;
            }

            const cmd = args[0];
            for (BuiltInCommands) |command| {
                if (std.mem.eql(u8, command.name, cmd)) {
                    try stdout.print("{s} is a shell builtin\n", .{cmd});
                    return;
                }
            }

            if (try findFullPath(cmd)) |base_path| {
                try stdout.print("{s} is {s}/{s}\n", .{ cmd, base_path, cmd });
            } else {
                try stdout.print("{s}: not found\n", .{cmd});
            }
        }
    }.execute,
};

const CdCommand = Command{ .name = "cd", .execute = struct {
    fn execute(args: []const []const u8, _: std.mem.Allocator) anyerror!void {
        if (args.len == 0) {
            try std.process.changeCurDir("/");
            return;
        }
        if (args.len > 1) {
            try stdout.print("cd: too many arguments\n", .{});
            return;
        }
        std.process.changeCurDir(args[0]) catch {
            try stdout.print("cd: {s}: No such file or directory\n", .{args[0]});
        };
    }
}.execute };

fn findFullPath(cmd: []const u8) !?[]const u8 {
    var envs = try std.process.getEnvMap(arenaAllocator);
    defer envs.deinit();

    const path = envs.get("PATH") orelse "";
    // debug_print("PATH value: {s}\n", .{path});

    const home_path = envs.get("HOME") orelse "";

    var path_values = std.mem.splitAny(u8, path, ":");
    while (path_values.next()) |path_value| {
        // debug_print("Checking path: {s}\n", .{path_value});
        const real_path = if (std.mem.startsWith(u8, path_value, "~/"))
            try std.fmt.allocPrint(arenaAllocator, "{s}{s}", .{ home_path, path_value[1..] })
        else
            path_value;
        // debug_print("After expanding path: {s}\n", .{real_path});

        // NOTE: the accessAbsolute and openDirAboslute functions have an assert
        // to check if path is absolute but do not return a union error type.
        // So we need to check up-front.
        if (!std.fs.path.isAbsolute(real_path)) continue;
        std.fs.accessAbsolute(real_path, .{}) catch continue;

        if (std.fs.openDirAbsolute(real_path, .{ .iterate = true })) |items| {
            var walker = items.walk(arenaAllocator) catch continue;
            defer walker.deinit();

            while (walker.next() catch continue) |item| {
                if (std.mem.eql(u8, item.basename, cmd)) {
                    // debug_print("found {s} in {s}\n", .{ cmd, real_path });
                    return try arenaAllocator.dupe(u8, real_path);
                }
            }
        } else |_| continue;
    }
    return null;
}

const BuiltInCommands = [_]*const Command{
    &ExitCommand,
    &EchoCommand,
    &TypeCommand,
    &PwdCommand,
    &CdCommand,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    arenaAllocator = arena.allocator();

    var shell = Shell.init(arenaAllocator);
    defer shell.deinit();

    for (BuiltInCommands) |command| {
        try shell.registerCommand(command);
    }

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("$ ", .{});

        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');
        try shell.processCommand(user_input);
    }
}
