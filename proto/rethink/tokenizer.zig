const std = @import("std");
const types = @import("types.zig");

const Token = types.Token;
const Variable = types.Variable;
const Arg = types.Arg;
const Block = types.Block;

pub const Tokenizer = struct {
    mem:std.ArrayList(u8) = .empty,
    res:Block,
    alloc:std.mem.Allocator,
    reader:*std.Io.Reader,
    arena:std.heap.ArenaAllocator,

    pub fn init(alloc:std.mem.Allocator) !Tokenizer {
        const foo:Tokenizer = .{
            .alloc = alloc,
            .reader = undefined,
            .res = Block.init(alloc, null),
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
        return foo;
    }

    pub fn deinit(self:*Tokenizer) void {
        self.mem.deinit(self.alloc);
        _ = self.arena.deinit();
    }

    pub fn recurse(self:*Tokenizer) !Block {
        var tokenizer:Tokenizer = .init(self.alloc);
        return try tokenizer.do(self.reader);
    }

    pub fn do(self:*Tokenizer, reader:*std.Io.Reader) !Block {
        // TODO:  helpers to dupe result so arena can be reset
        // defer self.arena.reset(.free_all);
        const alloc = self.arena.allocator();
        self.reader = reader;

        var mem:std.ArrayList(u8) = .empty;
        defer mem.deinit(alloc);

        var res:Block = .init(self.alloc, null);

        var block:?Block = null;

        var esc:bool = false;
        var string:?u8 = null;
        while (reader.takeByte() catch null) |b| {
            if (esc) {
                esc = false;
                try mem.append(alloc, b);
                continue;
            }
            if (string) |s| {
                if (b == s) {
                    string = null;
                    const str:Token = .{ .type = .{ .string = try mem.toOwnedSlice(alloc) } };
                    if (block) |*blk|
                        try @constCast(blk).code.append(self.alloc, str)
                    else
                        try res.code.append(self.alloc, str);
                } else
                    try mem.append(alloc, b);
                continue;
            }
            if (std.ascii.isWhitespace(b) or Token.byte_looks_like_symbol(b)) {
                if (mem.items.len > 0) {
                    const raw = try mem.toOwnedSlice(alloc);
                    if (block) |*blk|
                        try @constCast(blk).code.append(self.alloc, .{ .type =
                            if (raw[0] == '"' and raw[raw.len-1] == '"') .{
                                .string = raw[1..raw.len-1],
                            } else if (raw[0] == '$') .{
                                .variable = Variable.make(raw[1..]),
                            } else .{
                                .ident = raw,
                            }
                        })
                    else
                        try res.code.append(self.alloc, .{ .type =
                            if (raw[0] == '"' and raw[raw.len-1] == '"') .{
                                .string = raw[1..raw.len-1],
                            } else if (raw[0] == '$') .{
                                .variable = Variable.make(raw[1..]),
                            } else .{
                                .ident = raw,
                            }
                        });
                }

                if (Token.byte_looks_like_symbol(b)) {
                    const new:Token = .{ .type = .{
                        .symbol = Token.byte_to_symbol(b) orelse unreachable, }
                    };
                    if (block) |*blk|
                        try @constCast(blk).code.append(self.alloc, new)
                     else
                        try res.code.append(self.alloc, new);
                }
                continue;
            }
            switch (b) {
                '"' => string = b,
                '\\' => esc = true,
                '{' => {}, // TODO: unlabled block
                '}' => {
                    if (block == null)
                        @panic("closing paren outside of block");
                    try res.to_namespace(
                        block.?.name orelse @panic("block name null"),
                        .{ .type = .{ .label = block.? } }
                    );
                    block = null;
                },
                ':' => {
                    if (mem.items.len < 1)
                        @panic("invalid label, mem empty");
                    if (block) |_|
                        @panic("labeled blocks cannot be nested");
                    block = .init(self.alloc, try mem.toOwnedSlice(self.alloc));
                },
                else => try mem.append(alloc, b),
            }
        }
        return res;
    }
};
