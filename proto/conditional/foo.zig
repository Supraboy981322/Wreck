const std = @import("std");

const Symbol = enum {
    @"(", @")",
    @"<", @">",
    @"=", @"==",
    @">=", @"<=",
};

const Keyword = enum {
    @"and", @"or", @"xor",
};

const TokenType = enum {
    VALUE,
    SYMBOL,
    KEYWORD,
};

const Token = struct {
    type:TokenType,
    symbol:?Symbol = null,
    keyword:?Keyword = null,
    parsed_num:?usize = null,
    value_type:?ValueType = null,
    bool_value:?bool = null,
};
const ValueType = enum {
    NUM,
    BOOLEAN
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer {
        _ = arena.reset(.free_all);
        _ = arena.deinit();
    }
    const alloc = arena.allocator();

    const tokens = [_]Token {
        .{ .type = .SYMBOL, .symbol = .@"(" },

        .{ .type = .VALUE, .value_type = .NUM, .parsed_num = 1 },
        .{ .type = .SYMBOL, .symbol = .@">" },
        .{ .type = .VALUE, .value_type = .NUM, .parsed_num = 2 },

        .{ .type = .KEYWORD, .keyword = .@"xor" },

        .{ .type = .VALUE, .value_type = .NUM, .parsed_num = 1 },
        .{ .type = .SYMBOL, .symbol = .@"<" },
        .{ .type = .VALUE, .value_type = .NUM, .parsed_num = 2 },
        
        .{ .type = .SYMBOL, .symbol = .@")" },
    };

    std.debug.print("\n{}\n", .{(try conditional.do(alloc, @constCast(&tokens))).bool_value.?});
}
