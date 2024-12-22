const std = @import("std");

const enable_debug = true;
const debug_print = if (enable_debug) std.debug.print else void_print;

fn void_print(comptime _: []const u8, _: anytype) void {}

const EXIT_0: u8 = 0;
const CONTINUE: u8 = 100;

const ExitCode = enum(u8) {
    success = 0,
    cont = 100,
};

const supportedCommands = [_][]const u8{
    "hello",
    "exit",
    "echo",
    "type",
    "pwd",
};

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

var arenaAllocator: std.mem.Allocator = undefined;

fn processCommand(input: []const u8) !ExitCode {
    var commandItems = std.mem.tokenizeAny(u8, input, " ");

    var cmd_and_args = std.ArrayList([]const u8).init(arenaAllocator);
    defer cmd_and_args.deinit();

    while (commandItems.next()) |arg| {
        try cmd_and_args.append(arg);
    }
    const cmd = cmd_and_args.items[0];
    const args = cmd_and_args.items[1..];

    if (std.mem.eql(u8, cmd, "hello")) {
        return runHello();
    } else if (std.mem.eql(u8, cmd, "exit")) {
        return runExit();
    } else if (std.mem.eql(u8, cmd, "echo")) {
        return runEcho(args);
    } else if (std.mem.eql(u8, cmd, "type")) {
        return runTypeBultin(args);
    } else if (std.mem.eql(u8, cmd, "pwd")) {
        return runPwd();
    } else {
        return runProgram(cmd_and_args.items);
    }
}

fn runHello() !ExitCode {
    try stdout.writeAll("Hello, world!\n");
    return .cont;
}

fn runExit() !ExitCode {
    return .success;
}

fn runEcho(args: []const []const u8) !ExitCode {
    const echo_string = try std.mem.join(arenaAllocator, " ", args);
    try stdout.print("{s}\n", .{echo_string});
    return .cont;
}

fn runPwd() !ExitCode {
    const cwd = try std.process.getCwdAlloc(arenaAllocator);
    try stdout.print("{s}\n", .{cwd});

    return .cont;
}

fn runTypeBultin(args: []const []const u8) !ExitCode {
    if (args.len == 0) {
        try stdout.print("Must provide a command to check type\n", .{});
        return .cont;
    }

    const typeCmd = args[0];
    for (supportedCommands) |supportedCommand| {
        if (std.mem.eql(u8, supportedCommand, typeCmd)) {
            try stdout.print("{s} is a shell builtin\n", .{typeCmd});
            return .cont;
        }
    }

    return runTypeFromPath(args);
}

fn runTypeFromPath(args: []const []const u8) !ExitCode {
    const cmd = args[0];

    if (try findFullPath(cmd)) |base_path| {
        try stdout.print("{s} is {s}/{s}\n", .{ cmd, base_path, cmd });
    } else {
        try stdout.print("{s}: not found\n", .{cmd});
    }

    return .cont;
}

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

fn runProgram(args: [][]const u8) !ExitCode {
    const cmd = args[0];
    const full_path = try findFullPath(cmd) orelse {
        try stdout.print("{s}: command not found\n", .{cmd});
        return .cont;
    };
    const exe_full_path = try std.fmt.allocPrint(arenaAllocator, "{s}/{s}", .{ full_path, cmd });

    args[0] = exe_full_path;

    var child_process = std.process.Child.init(args, arenaAllocator);

    _ = try child_process.spawnAndWait();
    return .cont;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    arenaAllocator = arena.allocator();

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("$ ", .{});

        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        const exit_code = try processCommand(user_input);
        switch (exit_code) {
            .success => return,
            else => {},
        }
    }
}
