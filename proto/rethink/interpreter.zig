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

    pub fn do(_:*Interpreter, base:std.process.Init.Minimal, block:Block) !?Token {
        const alloc = block.alloc;
        if (block.namespace.get("main")) |*entry| {
            if (entry.type == .block) {
                var main = entry.type.block;
                var args:std.ArrayList(Token) = .empty;
                defer args.deinit(alloc);
                if (main.params.len > 0) blk: {
                    if (main.params.len == 1 and main.params[0].type == .void) break :blk;
                    for (main.params) |param| switch (param.type) {
                        .list => {
                            _ = std.meta.stringToEnum(
                                enum{ argv, args, @"_" }, param.name.?
                            ) orelse
                                return error.UnsupportedMainArg;

                            if (param.type_hint == null)
                                return error.WrongMainArgType;
                            if (param.type_hint.?.list != .string)
                                return error.WrongMainArgType;

                            var list:types.List = .{ .type = .string };

                            var itr = base.args.iterate();
                            while (itr.next()) |arg|
                                try list.append(alloc, .{ .string  = try alloc.dupe(u8, arg) });
                            try main.to_namespace(@constCast("args"), .{
                                .type = .{ .list = list }
                            });
                        },
                        else => @panic("invalid main arg"),
                    };
                }
                var itr = block.namespace.iterator();
                while (itr.next()) |name_entry| {
                    try main.to_namespace(
                        @constCast(name_entry.key_ptr.*),
                        name_entry.value_ptr.*
                    );
                }
                _ = try main.run(args.items);
            } else
                @panic("main not a label");
        } else
            @panic("no main");
        return null;
    }
};
