const std = @import("std");

const EXIT_0: u8 = 0;
const CONTINUE: u8 = 100;

const ExitCode = enum(u8) {
    success = 0,
    cont = 100,
};

fn processCommand(input: []const u8) !ExitCode {
    const stdout = std.io.getStdOut().writer();
    if (std.mem.eql(u8, input, "hello")) {
        try stdout.writeAll("Hello, world!\n");
        return .cont;
    } else if (std.mem.eql(u8, input, "exit 0")) {
        return .success;
    } else {
        try stdout.print("{s}: command not found\n", .{input});
        return .cont;
    }
}

pub fn main() !void {
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
