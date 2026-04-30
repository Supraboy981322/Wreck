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
        if (block.namespace.get("main")) |*entry| {
            if (entry.type == .label) {
                var itr = block.namespace.iterator();
                while (itr.next()) |name_entry| {
                    try @constCast(entry).type.label.to_namespace(
                        @constCast(name_entry.key_ptr.*),
                        name_entry.value_ptr.*
                    );
                }
                _ = try @constCast(entry).type.label.run(@constCast(&[_]Token{}));
            } else
                @panic("main not a label");
        } else
            @panic("no main");
        return null;
    }
};
