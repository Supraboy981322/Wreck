const std = @import("std");
const types = @import("types.zig");

const Token = types.Token;
const Variable = types.Variable;
const Block = types.Block;

pub fn main(init:std.process.Init) !void {
    // FIXME: deinit seg-faults
    //   defer _ = init.arena.deinit();

    const alloc = init.arena.allocator();

    var args = init.minimal.args;
    const file_name = blk: {
        var itr = try args.iterateAllocator(alloc);
        defer itr.deinit();
        _ = itr.skip();
        const ValidArgs = enum {
            run // TODO: maybe 'build'
        };
        while (itr.next()) |arg| {
            const match = std.meta.stringToEnum(ValidArgs, arg) orelse {
                std.debug.print("invalid arg: {s}\n", .{arg});
                std.process.abort();
            };
            switch (match) {
                .run => break :blk try alloc.dupe(u8, itr.next() orelse {
                    std.debug.print("no file given\n", .{});
                    std.process.abort();
                    unreachable;
                }),
            }
        }
        std.debug.print("no file given\n", .{});
        std.process.abort();
        unreachable;
    };

    var file = try std.Io.Dir.cwd().openFile(
        init.io, file_name, .{ .mode = .read_only }
    );
    defer file.close(init.io);
    var file_buf:[1024]u8 = undefined;
    var file_reader = file.reader(init.io, &file_buf);
    var reader = &file_reader.interface;

    var mem:std.ArrayList(u8) = .empty;
    defer mem.deinit(alloc);

    var res:Block = .init(alloc, null);
    defer res.deinit(alloc);

    var block:?Block = null;
    defer if (block) |*blk| @constCast(blk).deinit(alloc);

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
                    try @constCast(blk).code.append(alloc, str)
                else
                    try res.code.append(alloc, str);
            } else
                try mem.append(alloc, b);
            continue;
        }
        if (std.ascii.isWhitespace(b) or Token.byte_looks_like_symbol(b)) {
            if (mem.items.len > 0) {
                const raw = try mem.toOwnedSlice(alloc);
                if (block) |*blk|
                    try @constCast(blk).code.append(alloc, .{ .type =
                        if (raw[0] == '"' and raw[raw.len-1] == '"') .{
                            .string = raw[1..raw.len-1],
                        } else if (raw[0] == '$') .{
                            .variable = Variable.make(raw[1..]),
                        } else .{
                            .ident = raw,
                        }
                    })
                else
                    try res.code.append(alloc, .{ .type =
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
                    try @constCast(blk).code.append(alloc, new)
                 else
                    try res.code.append(alloc, new);
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
                block = .init(alloc, try mem.toOwnedSlice(alloc));
            },
            else => try mem.append(alloc, b),
        }
    }
    if (res.namespace.get("main")) |*entry| {
        if (entry.type == .label) {
            var itr = res.namespace.iterator();
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
}
