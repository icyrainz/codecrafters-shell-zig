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

    const stdout = std.io.getStdOut().writer();
    if (std.mem.eql(u8, cmd, "hello")) {
        try stdout.writeAll("Hello, world!\n");
        return .cont;
    } else if (std.mem.eql(u8, cmd, "exit")) {
        return .success;
    } else if (std.mem.eql(u8, cmd, "echo")) {
        const echo_string = try std.mem.join(allocator, " ", args.items);
        try stdout.print("{s}\n", .{echo_string});
        return .cont;
    } else if (std.mem.eql(u8, cmd, "type")) {
        if (args.items.len == 0) {
            try stdout.print("Must provide a command to check type\n", .{});
            return .cont;
        }

        const typeCmd = args.items[0];
        for (supportedCommands) |supportedCommand| {
            if (std.mem.eql(u8, supportedCommand, typeCmd)) {
                try stdout.print("{s} is a shell builtin\n", .{typeCmd});
                return .cont;
            }
        }

        try stdout.print("{s}: not found\n", .{typeCmd});
        return .cont;
    } else {
        try stdout.print("{s}: command not found\n", .{cmd});
        return .cont;
    }
}

pub fn main() !void {
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

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
