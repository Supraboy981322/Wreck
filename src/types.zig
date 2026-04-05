const std = @import("std");
const globs = @import("globs.zig");

pub const State = struct {
    idents:[]*Token,

    pub fn find_ident(self:*State, needle:Token) !*Token {
        for (self.idents) |ident| {
            if (std.mem.eql(u8, ident.*.raw, needle.raw))
                return ident;
        }
        return error.IdentNotFound;
    }
};

pub const Function = struct {
    name:[]u8,
    content:[]Token,
};

pub const Tokenized = struct {
    tokens:[]Token,
    base_state:State,
    alloc:std.mem.Allocator,
    arena:std.heap.ArenaAllocator,
};

pub const Token = struct {
    raw: []u8,
    type: Token.Type,
    line_number:usize,
    line_pos:usize,

    type_info:struct {
        value:?Token.ValueType = null,
        thing:?Token.ThingType = null,
        symbol:?Token.Symbol = null,
        keyword:?Token.Keyword = null,
        ident:?Token.IdentType = null,
    } = .{},

    value:struct {
        num:?isize = null,
        bool:?bool = null,
        string:?[]u8 = null,
        ptr:?*Token = null,
    } = .{},

    pub const Type = enum {
        INVALID,
        FN,
        VALUE,
        SYMBOL,
        KEYWORD,
        IDENT,
    };

    pub const ValueType = enum {
        UNKNOWN,
        VOID,
        NUM,
        FLAG,
        STRING,
        COMMENT,
        BOOL,
        BUILTIN,
        TOKEN_PTR,
    };

    pub const IdentType = enum {
        @"fn",
        @"let",
        @"set",
    };

    pub const ThingType = enum {
        SHELL_CMD,
        BUILTIN,
        LOCAL,
        EXTERNAL,
    };

    pub const Symbol = enum {
        @"{",   @"}",
        @"(",   @")",
        @"<",   @">",
        @"=",   @"==",
        @">=",  @"<=",
        @";",
    };
    
    pub const Keyword = enum {
        @"?",   @"if",
        @"?!",  @"else",
        @"and", @"or", @"xor",
        @"fn",
        @"let", @"set",
    };

    pub const Errors = error {
        IsNotFlag,
    };

    pub fn is_value_type(self:*Token, value_type:@This().ValueType) bool {
        if (self.type != .VALUE) return false;
        return self.type_info.value.? == value_type;
    }

    pub fn is_symbol(self:*Token, check:Token.Symbol) bool {
        if (self.type != .SYMBOL) return false;
        return self.type_info.symbol.? == check;
    }

    pub fn is_keyword(self:*Token, check:Token.Keyword) bool {
        if (self.type != .KEYWORD) return false;
        return self.type_info.keyword.? == check;
    }

    pub fn is_oneof_keywords(self:*Token, check:[]Token.Keyword) bool {
        if (self.type != .KEYWORD) return false;
        for (check) |thing|
            if (self.is_keyword(thing)) return true;
        return false;
    }

    pub fn own(self:*Token, alloc:std.mem.Allocator) !Token {
        return .{
            .raw = try alloc.dupe(u8, self.raw),
            .type = self.type,

            .line_number = self.line_number,
            .line_pos = self.line_pos,

            .type_info =  .{
                .value = self.type_info.value,
                .thing = self.type_info.thing,
                .symbol = self.type_info.symbol,
                .keyword = self.type_info.keyword,
                .ident = self.type_info.ident,
            },

            .value = .{
                .num = self.value.num,
                .bool = self.value.bool,
                .string = self.value.string,
                .ptr = self.value.ptr,
            },
        };
    }

    pub fn expand_flag(self:*Token, alloc:std.mem.Allocator) ![]u8 {
        if (!self.is_value_type(.FLAG)) return Token.Errors.IsNotFlag;
        
        var res = try std.ArrayList(u8).initCapacity(alloc, 0);
        defer _ = res.deinit(alloc);

        try res.append(alloc, '-');
        if (self.raw.len > 1) try res.append(alloc, '-');
        try res.appendSlice(alloc, self.raw);

        return try res.toOwnedSlice(alloc);
    }

    pub fn free(self:*Token, alloc:std.mem.Allocator) void {
        alloc.free(self.raw);
    }

    pub fn print(self:*Token) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer _ = arena.deinit();
        const alloc = arena.allocator();

        var fmted = try std.ArrayList(u8).initCapacity(alloc, 0);
        defer _ = fmted.deinit(alloc);

        try fmted.print(
            alloc,
            "\x1b[0;3{d}mraw\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\n\t"
                ++ "\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\n\t"
                ++ "\x1b[1;3{d}m{s}\x1b[1;37m{{\x1b[0m{d}\x1b[1;37m}}\n\t"
                ++ "\x1b[1;3{d}m{s}\x1b[1;37m{{\x1b[0m{d}\x1b[1;37m}}\n",
            .{
                1, try @import("parser.zig").unescape(arena.allocator(), self.raw),
                2, @typeName(@TypeOf(self.type)), @tagName(self.type),
                7, "tokenizer.Token.line_pos", self.line_pos,
                7, "tokenizer.Token.line_number", self.line_number,
            }
        );

        //all this comptime and I can't even put predefined, similar enum types in an array?
        //  pretty stupid if you ask me
        
        if (self.type_info.value) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 3, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.type_info.thing) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 4, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.type_info.symbol) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 5, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.type_info.keyword) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 6, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.type_info.ident) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), @tagName(thing), }
        );

        if (self.value.num) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{d}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), thing, }
        );
        if (self.value.bool) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), thing, }
        );
        if (self.value.string) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), thing, }
        );
        if (self.value.ptr) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), std.mem.asBytes(thing), }
        );

        try globs.stdout.print("{s}", .{fmted.items}); 
    }
};
