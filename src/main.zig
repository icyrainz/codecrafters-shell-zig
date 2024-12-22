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
};

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

var arenaAllocator: std.mem.Allocator = undefined;

fn processCommand(input: []const u8) !ExitCode {
    var commandItems = std.mem.tokenizeAny(u8, input, " ");
    const cmd = commandItems.next() orelse return .cont;

    var args = std.ArrayList([]const u8).init(arenaAllocator);
    defer args.deinit();

    while (commandItems.next()) |arg| {
        try args.append(arg);
    }

    if (std.mem.eql(u8, cmd, "hello")) {
        return runHello();
    } else if (std.mem.eql(u8, cmd, "exit")) {
        return runExit();
    } else if (std.mem.eql(u8, cmd, "echo")) {
        return runEcho(args.items);
    } else if (std.mem.eql(u8, cmd, "type")) {
        return runTypeBultin(args.items);
    } else {
        try stdout.print("{s}: command not found\n", .{cmd});
        return .cont;
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
    if (args.len == 0) {
        try stdout.print("Must provide a command to check type\n", .{});
        return .cont;
    }

    const typeCmd = args[0];
    // debug_print("Checking: {s}\n", .{typeCmd});

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

        if (!std.fs.path.isAbsolute(real_path)) continue;
        std.fs.accessAbsolute(real_path, .{}) catch continue;

        if (std.fs.openDirAbsolute(real_path, .{ .iterate = true })) |items| {
            var walker = items.walk(arenaAllocator) catch continue;
            defer walker.deinit();

            while (walker.next() catch continue) |item| {
                if (std.mem.eql(u8, item.basename, typeCmd)) {
                    try stdout.print("{s} is {s}/{s}\n", .{ typeCmd, real_path, typeCmd });
                    return .cont;
                }
            }
        } else |_| continue;
    }

    try stdout.print("{s}: not found\n", .{typeCmd});
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
