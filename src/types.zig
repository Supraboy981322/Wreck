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
    type: @This().Type,
    value_type: ?@This().ValueType = null,
    thing_type:?@This().ThingType = null,
    symbol_type:?@This().Symbol = null,
    keyword_type:?@This().Keyword = null,
    parsed_num:?usize = null, // TODO: other number types
    bool_value:?bool = null,
    ident_type:?@This().IdentType = null,
    string_value:?[]u8 = null,

    token_ptr:?*Token = null,

    line_number:usize,
    line_pos:usize,

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

        if (self.value_type) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 3, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.thing_type) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 4, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.symbol_type) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 5, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.keyword_type) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 6, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.keyword_type) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.parsed_num) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{d}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), thing, }
        );
        if (self.bool_value) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), thing, }
        );
        if (self.ident_type) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), @tagName(thing), }
        );
        if (self.string_value) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), thing, }
        );
        if (self.token_ptr) |thing| try fmted.print(
            alloc,
            "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{ 7, @typeName(@TypeOf(thing)), std.mem.asBytes(thing), }
        );

        try globs.stdout.print("{s}", .{fmted.items}); 
    }

    pub fn is_value_type(self:*Token, value_type:@This().ValueType) bool {
        if (self.type != .VALUE) return false;
        return self.value_type.? == value_type;
    }

    pub fn is_symbol(self:*Token, check:@This().Symbol) bool {
        if (self.type != .SYMBOL) return false;
        return self.symbol_type.? == check;
    }

    pub fn is_keyword(self:*Token, check:@This().Keyword) bool {
        if (self.type != .KEYWORD) return false;
        return self.keyword_type.? == check;
    }

    pub fn is_oneof_keywords(self:*Token, check:[]@This().Keyword) bool {
        if (self.type != .KEYWORD) return false;
        for (check) |thing|
            if (self.is_keyword(thing)) return true;
        return false;
    }

    pub fn own(self:*Token, alloc:std.mem.Allocator) !Token {
        return .{
            .raw = try alloc.dupe(u8, self.raw),
            .type = self.type,
            .value_type = self.value_type,
            .thing_type = self.thing_type,
            .symbol_type = self.symbol_type,
            .keyword_type = self.keyword_type,
            .parsed_num = self.parsed_num,
            .bool_value = self.bool_value,
            .line_number = self.line_number,
            .line_pos = self.line_pos,
        };
    }

    pub fn expand_flag(self:*Token, alloc:std.mem.Allocator) ![]u8 {
        if (!self.is_value_type(.FLAG)) return @This().Errors.IsNotFlag;
        
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
};
