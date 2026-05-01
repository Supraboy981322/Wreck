const std = @import("std");

pub const Builtins = @import("builtins.zig").Builtins;

pub const Param = struct {
    name:?[]u8,
    type:Token.Types,
};

pub const Block = struct {
    params:[]Param,
    args:?[]Token = null,
    name:?[]u8, //null for root
    code:std.ArrayList(Token), //so I can iterate backwords, popping off of it as I go
    namespace:std.StringHashMap(Token),
    alloc:std.mem.Allocator,
    arena:std.heap.ArenaAllocator,
    is_label:bool = true,
    pub fn init(alloc:std.mem.Allocator, name:?[]u8, params:?[]Param, is_fn:bool) Block {
        return .{
            .namespace = .init(alloc),
            .alloc = alloc,
            .arena = .init(alloc),
            .name = name,
            .code = .empty,
            .params = params orelse @constCast(&[_]Param{}),
            .is_label = !is_fn,
        };
    }
    pub fn to_namespace(self:*Block, name:[]u8, thing:Token) !void {
        try self.namespace.put(try self.alloc.dupe(u8, name), thing);
    }
    pub fn deinit(self:*Block, alloc:std.mem.Allocator) void {
        self.code.deinit(alloc);
        self.namespace.deinit();
        _ = self.arena.deinit();
    }

    pub fn run(self:*Block, args:[]Token) !?Token {
        try self.load_args(args);
        var i:usize = 0;
        while (i < self.code.items.len) : (i += 1) {
            const tok = self.code.items[i];
            switch (tok.type) {

                .ident => |ident| {
                    const passed_args = try self.collect_args(&i, tok);
                    defer self.alloc.free(passed_args);
                    _ = Builtins.run(ident, passed_args) catch |e| {
                        if (e == error.InvalidBuiltin) {
                            if (self.namespace.get(ident)) |*func| {
                                if (func.type != .block)
                                    return error.NotFunction
                                else if (func.type.block.name) |_|
                                    _ = try @constCast(func).type.block.run(passed_args)
                                else
                                    return error.NotFunction;
                            } else {
                                std.debug.print("\n|{s}|\n", .{ident});
                                return error.UnknownIdentifier;
                            }
                        } else
                            return e;
                    };
                },

                .block => |*block| {
                    var blk = block.*;
                    var itr = self.namespace.iterator();
                    while (itr.next()) |entry|
                        try blk.to_namespace(@constCast(entry.key_ptr.*), entry.value_ptr.*);
                    _ = try blk.run(@constCast(&[_]Token{}));
                },

                .symbol => |symbol| if (symbol != .@";") {
                    std.debug.print("{any}\n", .{symbol});
                    return error.MissplacedSymbol;
                },

                else => std.debug.panic("{any}", .{tok.type}), //Block.run()
            }
        }
        return null;
    }

    pub fn collect_args(self:*Block, start_pos:*usize, start_tok:Token) ![]Token {
        var mem:std.ArrayList(Token) = .empty;
        defer mem.deinit(self.alloc);
        var i = start_pos.*+1;
        defer {
            const start = start_pos.*;
            start_pos.* += i - start;
        }
        var tok = start_tok;
        var depth:u8 = 0;
        while (i < self.code.items.len) : (i += 1) {
            tok = self.code.items[i];
            if (tok.type == .symbol) {
                switch (tok.type.symbol) {
                    .@"(" => depth += 1,
                    .@")" => depth -= 1,
                    else => return error.MissplacedSymbol,
                }
                if (depth == 0)
                    return try mem.toOwnedSlice(self.alloc);
                continue;
            }
            switch (tok.type) {
                .variable => {
                    while (tok.type == .variable) {
                        tok = switch (tok.type.variable) {
                            .arg => |a| switch (a) {
                                .plain => |n| self.args.?[n],
                                .keyword => |key| switch (key) {
                                    .@"count" => Token.mk_num(usize, self.args.?.len),
                                    .@",,", .splat => @panic("TODO: splat args"),
                                },
                                else => unreachable,
                            },
                            .name => |name| self.namespace.get(name) orelse {
                                std.debug.print("\n|{s}|\n", .{name});
                                return error.UnknownVariable;
                            },
                        };
                    }
                },
                .ident => unreachable,
                .block => @panic("TODO: nested function calls"),
                else => {},
            }
            try mem.append(self.alloc, tok);
        }
        return mem.toOwnedSlice(self.alloc);
    }

    pub fn load_args(self:*Block, args_raw:?[]Token) !void {
        if (self.name == null or self.is_label) {
            self.args = args_raw;
            return;
        }

        if (args_raw == null) {
            if (self.params.len > 0)
                return error.WrongArgCount;
            return;
        }

        const args = args_raw.?;
        if (args.len < 1) return;

        if (std.mem.eql(u8, "main", self.name.?)) {
            if (args.len == 1) if (args[0].type == .void) return;
            if (args.len > 0)
                @panic("TODO: \"juicy main\" as the rest of the Zig community calls it");
        }

        if (self.params.len != args.len) return error.WrongArgCount;

        self.args = try self.arena.allocator().alloc(Token, args.len);

        for (self.params, 0..) |param, i| switch (param.type) {
            .string, .bool, .void => {
                if (args[i].type == param.type)
                    try self.to_namespace(param.name orelse unreachable, args[i])
                else
                    return error.ArgTypeMissmatch;
            },
            .int, .uint => {
                if (args[i].type != .number)
                    return error.ArgTypeMissmatch;
                const expect = @tagName(args[i].type.number);
                const have = @tagName(param.type);
                if (std.mem.eql(u8, expect, have))
                    try self.to_namespace(param.name orelse unreachable, args[i])
                else
                    return error.ArgTypeMissmatch;
            },
            else => unreachable,
        };
    }
};

pub const Arg = union(enum) {
    plain:usize,
    keyword:ArgKeyword,
    complex:[]u8, //parsed when used  TODO: advanced arg stuff
    pub const ArgKeyword = enum {
        @",,", splat, //splat
        count, 
    };

    pub fn is_splat(self:Arg) !bool {
        if (self != .keyword)
            return error.ArgNotKeyword;
        return self.keyword == .@",," or self.keyword == .@"splat";
    }

    pub fn byte_to_keyword(b:u8) ?Arg {
        return Arg.to_keyword(@constCast(&[_]u8{b}));
    }
    pub fn to_keyword(str:[]u8) ?Arg {
        return .{ .keyword = std.meta.stringToEnum(ArgKeyword, str) orelse return null };
    }

    pub fn make(raw:[]u8) ?Arg {
        if (std.fmt.parseInt(usize, raw, 10)) |int| 
            return .{ .plain = int }
        else |_| {}

        if (raw[0] == '[' and raw[raw.len-1] == ']') {
            return
                if (Arg.to_keyword(raw[1..raw.len-1])) |match|
                    match
                else 
                    .{ .complex = raw, };
        }
        return null;
    }
};

pub const Variable = union(enum) {
    arg:Arg,
    name:[]u8,

    pub fn make(raw:[]u8) Variable {
        return
            if (Arg.make(raw)) |match| .{
                .arg = match
            } else .{
                .name = raw[1..],
            };
    }
};

pub const Token = union(enum) {
    type:TokenType,


    pub const Types = std.meta.Tag(TokenType);
    pub const TokenType = union(enum) {
        string:[]u8,
        block:Block,
        ident:[]u8,
        symbol:Symbols,
        variable:Variable,
        keyword:Keywords,
        bool:bool,
        number:union(enum) {
            int:i256,
            uint:u256,
        },

        //these exist to match a literal 'int' (for example) to a type
        int:void,
        uint:void,
        void:void,

        pub fn make(raw:[]u8) ?Types {
            const lazy_match = std.meta.stringToEnum(
                Types, raw
            ) orelse return null;
            switch (lazy_match) {
                .string, .bool, .int, .uint, .void => return lazy_match,
                else => return null,
            }
        }
    };

    pub const Keywords = enum {
        @"fn",
    };

    pub const Symbols = enum {
        @";",
        @"(", @")",

        @"@", @"#", // TODO: identifier for builtins and calling external code
    };

    pub fn byte_looks_like_symbol(b:u8) bool {
        return byte_to_symbol(b) != null;
    }

    pub fn byte_to_symbol(b:u8) ?Symbols {
        return to_symbol(@constCast(&[_]u8{b}));
    }

    pub fn to_symbol(raw:[]u8) ?Symbols {
        return std.meta.stringToEnum(Symbols, raw);
    }

    pub fn to_keyword(raw:[]u8) ?Keywords {
        return std.meta.stringToEnum(Keywords, raw);
    }

    pub fn mk_num(comptime T:type, n:T) Token {
        return .{
            .type = .{ .number = switch (@typeInfo(T)) {
                .int => |info|
                    if (info.signedness == .signed) .{
                        .int = @intCast(n),
                    } else .{
                        .uint = @intCast(n),
                    },
                else => unreachable,
            }},
        };
    }

    pub fn make(raw:[]u8) ?Token {
        if (raw.len < 1) return null;

        if (to_symbol(raw)) |symbol|
            return .{ .type = .{ .symbol = symbol } };

        if (to_keyword(raw)) |keyword|
            return .{ .type = .{ .keyword = keyword } };

        if (raw[0] == '$')
            return .{ .type = .{ .variable = Variable.make(raw[1..]) } };

        if (raw[0] == '"' and raw[raw.len-1] == '"')
            return .{ .type = .{ .string = raw[1..raw.len-1] } };

        return .{ .type = .{ .ident = raw } };
    }

    pub fn mk_void() Token {
        return .{ .type = .{ .void = {} } };
    }
};
