const std = @import("std");
const types = @import("types.zig");
const hlp = @import("helpers.zig");

const Token = types.Token;
const Variable = types.Variable;
const Arg = types.Arg;
const Block = types.Block;

pub const TokenizerError = error {
} || std.mem.Allocator.Error;

pub const Tokenizer = struct {
    mem:std.ArrayList(u8) = .empty,
    alloc:std.mem.Allocator,
    reader:?*std.Io.Reader = null,
    arena:std.heap.ArenaAllocator,

    pub fn init(alloc:std.mem.Allocator) !Tokenizer {
        const foo:Tokenizer = .{
            .alloc = alloc,
            .reader = null,
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
        return foo;
    }

    pub fn deinit(self:*Tokenizer) void {
        self.mem.deinit(self.alloc);
        _ = self.arena.deinit();
    }

    pub fn recurse(self:*Tokenizer, name:?[]u8) !Block {
        var tokenizer:Tokenizer = try .init(self.alloc);
        return try tokenizer.do(self.reader.?, name);
    }

    pub fn do(self:*Tokenizer, reader:*std.Io.Reader, name:?[]u8) TokenizerError!Block {
        // TODO:  helpers to dupe result so arena can be reset
        // defer self.arena.reset(.free_all);
        const alloc = self.arena.allocator();
        if (self.reader == null) self.reader = reader;

        var mem:std.ArrayList(u8) = .empty;
        defer mem.deinit(alloc);

        var res:Block = .init(self.alloc, name, null, true);

        var function:?Block = null;
        _ = &function; // NOTE: may need this

        var depth_tracker:hlp.DepthTracker(u8) = try .init();
        _ = &depth_tracker; // NOTE: may need this

        var esc:bool = false;
        var label_name:?[]u8 = null;
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
                    try res.code.append(self.alloc, str);
                } else
                    try mem.append(alloc, b);
                continue;
            }
            if (std.ascii.isWhitespace(b) or Token.byte_looks_like_symbol(b)) {
                if (mem.items.len > 0) {
                    const raw = try mem.toOwnedSlice(alloc);
                    try res.code.append(self.alloc, .make(raw));
                }

                if (Token.byte_looks_like_symbol(b)) {
                    const new:Token = .{ .type = .{
                        .symbol = Token.byte_to_symbol(b) orelse unreachable, }
                    };
                    try res.code.append(self.alloc, new);
                }

                if (Token.byte_looks_like_symbol(b))
                    try res.code.append(self.alloc, Token.make(@constCast(&[_]u8{b})).?);

                continue;
            }
            switch (b) {
                '"' => string = b,
                '\\' => esc = true,
                '{' => {
                    defer {
                        if (label_name) |_| label_name = null;
                    }
                    var block = try self.recurse(label_name);
                    block.is_label = label_name != null;
                    const as_token:Token = .{
                        .type = .{ .block = block }
                    };
                    if (label_name) |label|
                        try res.to_namespace(label, as_token)
                    else
                        try res.code.append(self.alloc, as_token);
                },
                '}' => return res,
                ':' => {
                    if (label_name) |_|
                        @panic("missplaced colon");
                    label_name = try mem.toOwnedSlice(self.alloc);
                },
                else => try mem.append(alloc, b),
            }
        }
        return res;
    }
};
