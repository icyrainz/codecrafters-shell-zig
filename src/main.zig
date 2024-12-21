const std = @import("std");

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

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

fn processCommand(input: []const u8) !ExitCode {
    var commandItems = std.mem.tokenizeAny(u8, input, " ");
    const cmd = commandItems.next() orelse return .cont;

    var args = std.ArrayList([]const u8).init(allocator);
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
        return runType(args.items);
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
    const echo_string = try std.mem.join(allocator, " ", args);
    try stdout.print("{s}\n", .{echo_string});
    return .cont;
}

fn runType(args: []const []const u8) !ExitCode {
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

    try stdout.print("{s}: not found\n", .{typeCmd});
    return .cont;
}

pub fn main() !void {
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    allocator = arena.allocator();

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
