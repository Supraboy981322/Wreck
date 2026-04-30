const std = @import("std");
const hlp = @import("helpers.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

const ByteItr = hlp.ByteItr;

pub fn main(init:std.process.Init) !void {
    const alloc = init.gpa;

    const src:[]u8 = @constCast(@embedFile("test.wr"));
    var tokenizer:Tokenizer = .init(init.io, alloc);
    tokenizer.load_source(src);
    defer tokenizer.deinit();

    var toks = try tokenizer.do(); 
    defer toks.deinit(alloc);

    for (toks.items) |tok| std.debug.print(
        \\|{s}|
        \\  {s}
    ++ "\n", .{
        @tagName(tok),
        tok.format(init.arena.allocator()),
    });
}
