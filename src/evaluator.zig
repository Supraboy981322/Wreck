const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Token = tokenizer.Token;

pub const conditional = struct {
    fn split(alloc:std.mem.Allocator, in:[]Token) ![][3]Token {
        var mem = try std.ArrayList(Token).initCapacity(alloc, 0);
        var res = try std.ArrayList([3]Token).initCapacity(alloc, 0);
        defer {
            mem.deinit(alloc);
            res.deinit(alloc);
        }
        loop: for (in) |token| {
            if (token.type == .KEYWORD) if (mem.items.len == 3) {
                try res.append(alloc, b: {
                    const raw = try mem.toOwnedSlice(alloc);
                    break :b .{
                        raw[0],
                        raw[1],
                        raw[2],
                    };
                });
                mem.clearAndFree(alloc);
                continue :loop;
            } else {
                @panic("unexpected keyword in conditional.split() input");
            };
            switch (token.type) {
                .VALUE, .SYMBOL => try mem.append(alloc, token),
                else => @panic("invalid token type in conditional split input"),
            }
        }
        if (mem.items.len > 0) try res.append(alloc, b: {
            const raw = try mem.toOwnedSlice(alloc);
            break :b .{
                raw[0],
                raw[1],
                raw[2],
            };
        });
        return try res.toOwnedSlice(alloc);
    }
    fn eval(in:[3]Token) bool {
        const left_hand = in[0];
        const thing = in[1];
        const right_hand = in[2];
        return switch (thing.symbol_type.?) {
            .@"<" => left_hand.parsed_num.? < right_hand.parsed_num.?,
            .@">" => left_hand.parsed_num.? > right_hand.parsed_num.?,
            .@"==" => left_hand.parsed_num.? == right_hand.parsed_num.?,
            .@">=" => left_hand.parsed_num.? >= right_hand.parsed_num.?,
            .@"<=" => left_hand.parsed_num.? <= right_hand.parsed_num.?,
            else => @panic("invalid conditional symbol"),
        };
    }
    pub fn do(alloc:std.mem.Allocator, in:[]Token) !Token {
        var mem = try std.ArrayList(Token).initCapacity(alloc, 0);
        defer _ = mem.deinit(alloc);

        var final:Token = .{
            .raw = @constCast(""),
            .type = .VALUE,
            .value_type = .BOOL,
            .line_number = 0,
            .line_pos = 0,
        };

        var last_keyword:?tokenizer.Token.Keyword = null;

        var mem2 = try std.ArrayList(Token).initCapacity(alloc, 0); 
        defer _ = mem2.deinit(alloc);

        const start:usize = if (in[0].type == .SYMBOL) 1 else 0;

        for (in[start..]) |token| {
            switch (token.type) {
                .VALUE, .SYMBOL => try mem.append(alloc, token),
                .KEYWORD => {
                    if (mem.items.len > 0) @panic("unexpected keyword in conditional.do()");
                    last_keyword = token.keyword_type.?;
                },
                else => std.debug.panic(
                    "TODO: handle {s} in conditional",
                    .{ @tagName(token.type)}
                ),
            }
            if (mem.items.len == 3) {
                defer {
                    mem.clearAndFree(alloc);
                    last_keyword = null;
                }

                const new = eval(.{ mem.items[0], mem.items[1], mem.items[2] });

                if (last_keyword) |word| {
                    const one, const two = .{ final.bool_value.?, new };
                    switch (word) {
                        .@"and" => final.bool_value = one and two,
                        .@"or" => final.bool_value = one or two,
                        .@"xor" => final.bool_value = (
                            (!one and two) or (one and !two)
                        ),
                        else => std.debug.panic(
                            "TODO: handle {s} in conditional",
                            .{ @tagName(token.type)}
                        ),
                    }
                } else
                    final.bool_value = new;
            } 
        }
        return final;
    }
};
