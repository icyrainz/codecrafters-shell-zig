const std = @import("std");

fn processCommand(input: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    if (std.mem.eql(u8, input, "hello")) {
        try stdout.writeAll("Hello, world!\n");
    } else {
        try stdout.print("{s}: command not found\n", .{input});
    }
}

pub fn main() !void {
    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;
        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        try processCommand(user_input);
    }
}
