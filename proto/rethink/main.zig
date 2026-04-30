const std = @import("std");

pub const Builtins = enum {
    print,

    pub fn run(name:[]u8, args:[]Token) !void {
        const matched = std.meta.stringToEnum(
            Builtins, name
        ) orelse return error.InvalidBuiltin;
        switch (matched) {
            .print => try print(args),
        }
    }

};

pub const Block = struct {
    args:?[]Token = null,
    name:?[]u8, //null for root
    code:std.ArrayList(Token), //so I can iterate backwords, popping off of it as I go
    namespace:std.StringHashMap(Token),
    alloc:std.mem.Allocator,
    arena:std.heap.ArenaAllocator,
    pub fn init(alloc:std.mem.Allocator, name:?[]u8) Block {
        return .{
            .namespace = .init(alloc),
            .alloc = alloc,
            .arena = .init(alloc),
            .name = name,
            .code = .empty,
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
        self.args = args;
        var i:usize = 0;
        while (i < self.code.items.len) : (i += 1) {
            const tok = self.code.items[i];
            switch (tok.type) {
                .symbol => {},
                .variable => {},
                .string => {},
                .ident => |ident| {
                    const passed_args = try self.collect_args(i, tok);
                    defer self.alloc.free(passed_args);
                    _ = Builtins.run(ident, passed_args) catch |e| {
                        if (e == error.InvalidBuiltin) {
                            if (self.namespace.get(ident)) |*func| {
                                if (func.type != .label)
                                    return error.NotFunction
                                else
                                    _ = try @constCast(func).type.label.run(passed_args);
                            } else {
                                std.debug.print("\n|{s}|\n", .{ident});
                                return error.UnknownIdentifier;
                            }
                        }
                    };
                    
                },
                else => unreachable,
            }
        }
        return null;
    }

    pub fn collect_args(self:*Block, start_pos:usize, start_tok:Token) ![]Token {
        var mem:std.ArrayList(Token) = .empty;
        defer mem.deinit(self.alloc);
        var i = start_pos+1;
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
                .label => @panic("TODO: nested function calls"),
                else => {},
            }
            try mem.append(self.alloc, tok);
        }
        return mem.toOwnedSlice(self.alloc);
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

    pub const TokenType = union(enum) {
        string:[]u8,
        label:Block,
        ident:[]u8,
        symbol:Symbols,
        variable:Variable,
        number:union(enum) {
            int:i256,
            uint:u256,
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
        return std.meta.stringToEnum(Symbols, @constCast(&[_]u8{b}));
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
};

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

pub fn print(args:[]Token) !void {
    for (args) |a| {
        switch (a.type) {
            .string => |str| std.debug.print("{s} ", .{str}),
            .number => |num| switch (num) {
                inline .uint, .int => |n| std.debug.print("{d} ", .{n}),
            },
            else => unreachable,
        }
    }
}
