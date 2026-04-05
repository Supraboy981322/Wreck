const std = @import("std");
const globs = @import("globs.zig");

const stdout = globs.stdout;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

pub const Error = error {
    IsNotFlag
};

pub fn unescape(alloc:std.mem.Allocator, in:[]u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = out.deinit(alloc);
    for (in) |b| try out.appendSlice(alloc, switch (b) {
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
        '\x1b' => "\\e",
        '\x07' => "\\a",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\x0b' => "\\v",
        else => &[_]u8{b},
    });
    return try out.toOwnedSlice(alloc);
}
