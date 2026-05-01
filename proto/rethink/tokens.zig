const std = @import("std");

pub const Builtins = @import("builtins.zig").Builtins;

pub const Param = struct {
    name:?[]u8,
    type:Token.Types = .void,
    type_hint:?Token.TypeHint = null,

    pub fn skeleton(name:[]u8) Param {
        return .{ .name = name };
    }
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
                        const variable = tok.type.variable;
                        tok = switch (variable) {
                            .arg => |a| switch (a) {
                                .plain => |n| self.args.?[n],
                                .keyword => |key| switch (key) {
                                    .@"count" => Token.mk_num(usize, self.args.?.len),
                                    .@",,", .splat => @panic("TODO: splat args"),
                                },
                                else => unreachable,
                            },
                            .name => |name| blk: {
                                var match = self.namespace.get(name.name) orelse {
                                    std.debug.print("\n|{any}|\n", .{name});
                                    return error.UnknownVariable;
                                };
                                if (name.flag) |flag| {
                                    // TODO: stuff otherthan list indexing
                                    if (match.type == .list)
                                        match = try match.type.list.get_token(flag.list);
                                }
                                break :blk match;
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
            if (args.len > 0) if (args[0].type != .string)
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
    name:NamedVariable,

    pub const NamedVariable = struct {
        name:[]u8,
        flag:?Flag = null,

        pub const Flag = union(enum) {
            list:usize, //index into list
        };
    };

    pub fn make(raw:[]u8) !Variable {
        return
            if (Arg.make(raw)) |match| .{
                .arg = match
            } else blk: {
                var named:Variable = .{
                    .name = .{ .name = raw[if (raw[0] == '$') 1 else 0..] },
                };

                const first_half, var second_half = std.mem.cut(
                    u8, named.name.name, "["
                ) orelse
                    return named;

                if (second_half[second_half.len-1] == ']') {
                    named.name.name = @constCast(first_half);
                    second_half = second_half[0..second_half.len-1];
                    // TODO: stuff otherthan indexing a list
                    named.name.flag = .{
                        .list = try std.fmt.parseInt(usize, second_half, 10)
                    };
                } else
                    return error.InvalidVariableName;
                break :blk named;
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
        list:List,
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
                .string, .bool, .int, .uint, .void, .list => return lazy_match,
                else => return null,
            }
        }
    };

    pub const TypeHint = union(enum) {
        list:Types,
    };

    pub const Keywords = enum {
        @"fn",

        // TODO: everything after this line
        @"if", @"?",
        @"for",
        @"while",
        do, dowhile,
        onerr, //basically 'catch'
        onnull, //similar to 'orelse'

        pub fn _is(self:Keywords, check:Keywords) bool {
            return switch (check) {
                .@"if", .@"?" => self == .@"if" or self == .@"?",
                .do, .dowhile => self == .do or self == .dowhile,
                else => check == self
            };
        }
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

    pub fn make(raw:[]u8) !?Token {
        if (raw.len < 1) return null;

        if (to_symbol(raw)) |symbol|
            return .{ .type = .{ .symbol = symbol } };

        if (to_keyword(raw)) |keyword|
            return .{ .type = .{ .keyword = keyword } };

        if(raw.len > 1) {
            if (raw[0] == '$')
                return .{ .type = .{ .variable = try Variable.make(raw[1..]) } };

            if (raw[0] == '"' and raw[raw.len-1] == '"')
                return .{ .type = .{ .string = raw[1..raw.len-1] } };
        }

        return .{ .type = .{ .ident = raw } };
    }

    pub fn make_from_byte(b:u8) !?Token {
        return make(@constCast(&[_]u8{b}));
    }

    pub fn mk_void() Token {
        return .{ .type = .{ .void = {} } };
    }

    pub fn new(comptime T:type, value:T) Token {
        return switch (T) {
            []u8, []const u8 => .{ .type = .{ .string = value } },
            else => switch (@typeInfo(T)) {
                .Int, .Float, .ComptimeInt, .ComptimeFloat => mk_num(T, value),
                else => @compileError("unsupported type for new() helper")
            }
        };
    }
};

pub const List = struct {
    type:enum{ string, bool, int, uint },
    value:std.ArrayList(Token.TokenType) = .empty,

    pub fn append(
        self:*List,
        alloc:std.mem.Allocator,
        value:Token.TokenType
    ) !void {
        try self.value.append(alloc, value);
    }

    pub fn get_token(self:*List, i:usize) !Token {
        if (self.value.items.len <= i) return error.IndexOutOfBounds;
        return .{ .type = self.value.items[i] };
    }
};
