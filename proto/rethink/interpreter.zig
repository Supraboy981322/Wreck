const std = @import("std");
const types = @import("types.zig");

const Block = types.Block;
const Token = types.Token;

pub const Interpreter = struct {
    alloc:std.mem.Allocator,
    io:std.Io,

    pub fn init(io:std.Io, alloc:std.mem.Allocator) !Interpreter {
        return .{
            .io = io,
            .alloc = alloc,
        };
    }

    pub fn do(_:*Interpreter, block:Block) !?Token {
        const alloc = block.alloc;
        if (block.namespace.get("main")) |*entry| {
            if (entry.type == .block) {
                const main = entry.type.block;
                var args:std.ArrayList(Token) = .empty;
                defer args.deinit(alloc);
                if (main.params.len > 0) blk: {
                    if (main.params.len == 1 and main.params[0].type == .void) break :blk;
                    for (main.params) |param| switch (param.type) {
                        .string => {
                            try args.append(alloc, Token.make(@constCast("\"argv1\"")).?);
                        },
                        else => @panic("invalid main arg"),
                    };
                }
                var itr = block.namespace.iterator();
                while (itr.next()) |name_entry| {
                    try @constCast(entry).type.block.to_namespace(
                        @constCast(name_entry.key_ptr.*),
                        name_entry.value_ptr.*
                    );
                }
                _ = try @constCast(entry).type.block.run(args.items);
            } else
                @panic("main not a label");
        } else
            @panic("no main");
        return null;
    }
};
