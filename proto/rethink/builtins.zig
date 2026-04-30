const std = @import("std");
const types = @import("types.zig");

const Token = types.Token;
const Block = types.Block;

pub const Builtins = enum {
    print,

    pub fn run(name:[]u8, args:[]Token) !void {
        const matched = std.meta.stringToEnum(
            Builtins, name
        ) orelse return error.InvalidBuiltin;
        switch (matched) {
            .print => try print(args),
        }
    }

};

pub fn print(args:[]Token) !void {
    for (args) |a| {
        switch (a.type) {
            .string => |str| std.debug.print("{s} ", .{str}),
            .number => |num| switch (num) {
                inline .uint, .int => |n| std.debug.print("{d} ", .{n}),
            },
            else => unreachable,
        }
    }
}
