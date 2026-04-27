const std = @import("std");
const hlp = @import("helpers.zig");
const types = @import("types.zig");

const BasicTok = types.BasicTok;

const Contextualized = struct {
    namespace:std.StringHashMap(types.NamespaceEntry),
    tokens:[]BasicTok,
    alloc:*std.mem.Allocator,
};

pub const Context = struct {
    itr:hlp.GenericItr(BasicTok),
    namespace:std.StringHashMap(types.NamespaceEntry),

    alloc:*std.mem.Allocator,

    pub fn init(alloc:*std.mem.Allocator) !Context {
        var foo:Context = .{
            .itr = hlp.GenericItr(BasicTok),
            .alloc = alloc,
            .namespace = undefined,
        };
        foo.namespace = std.StringHashMap.init(foo.alloc);
        return foo;
    }

    pub fn next_is_symbol(self:*Context, symbol:BasicTok.Symbols) bool {
        if (self.itr.peek()) |*next|
            return @constCast(next).is_symbol(symbol);
        return false;
    }

    pub fn collect_with(self:*Context, tok:*BasicTok, open:BasicTok.Symbols, close:BasicTok.Symbols) ![]BasicTok {
        var arr = std.ArrayList(*BasicTok).initCapacity(tok.alloc.*, 0);
        defer _ = arr.deinit(tok.alloc.*);

        var depth:usize = 0;
        if (self.itr.cur.is_symbol(open)) depth += 1;

        while (self.itr.next()) |*token| {
            if (@constCast(token).is_symbol(open))
                depth += 1
            else if (@constCast(token).is_symbol(close))
                depth -= 1;
            if (depth == 0) break;
            try arr.append(tok.alloc.*, token);
        }
        return try arr.toOwnedSlice(tok.alloc.*);
    }

    pub fn do(self:*Context) Contextualized {
        while (self.itr.next()) |*token| switch (token.type) {
            .KEYWORD => switch (token.keyword) {
                .@"fn" => {
                    const name = self.itr.next() orelse unreachable; // TODO: error here
                    const params = try self.collect_with(token, .@"(", .@")");
                    var template = try std.ArrayList(types.NamespaceEntry.FnStuff.Param).initCapacity(token.alloc.*, 0);
                    defer _ = template.deinit(token.alloc.*);
                    var i:usize = 0;
                    const Param = types.NamespaceEntry.FnStuff.Param;
                    while (i < params.len) : (i += 1) {
                        const matched_type = std.meta.stringToEnum(
                            types.ValueType, params[i+1].raw
                        ) orelse unreachable;
                        const new = Param.init(params[i], matched_type);
                        try template.append(token.alloc.*, new);
                    }
                    const info:types.NamespaceEntry.FnStuff = .{
                        .paramTemplate = template.toOwnedSlice(token.alloc.*),
                        .alloc = token.alloc,

                    };
                    const FnStuff = struct {
                        paramTemplate:[]Param,
                        content:[]BasicTok,
                        local_namespace:std.StringHashMap(types.NamespaceEntry),
                        pub const Param = struct {
                            name:[]u8,
                            type:ValueType,
                        };
                    };
                },
                .@"let", .@"set" => {},
            },
            .IDENT => {
                if (self.next_is_symbol(.@"(")) {
                    const params = self.collect_with(token, .@"(", .@")");
                    token.ident_info = .{
                        .type = .@"fn",
                        .params = params,
                    };
                }
            },
            else => {},
        };
        return .{
        };
    }
};
