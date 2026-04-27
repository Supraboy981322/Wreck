const std = @import("std");
const hlp = @import("helpers.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

const ByteItr = hlp.ByteItr;

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .retain_metadata = true,
        .never_unmap = true,
        .verbose_log = false,
    }){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    const src:[]u8 = @constCast(@embedFile("test.wr"));
    var tokenizer = try Tokenizer.init(&alloc, src);
    defer tokenizer.deinit();

    const toks = try tokenizer.do(); 
    defer alloc.free(toks);

    for (toks) |*tok| {
        std.debug.print(
            \\tok:
            \\  raw |{s}|
            \\  type {s}
            \\  keyword {s}
            \\  symbol {s}
            ++ "\n",
        .{
            tok.raw,
            @tagName(tok.type),
            if (tok.type == .KEYWORD) @tagName(tok.keyword) else "[undefined]",
            if (tok.type == .SYMBOL) @tagName(tok.symbol) else "[undefined]",
        });
        @constCast(tok).deinit();
    }
}
