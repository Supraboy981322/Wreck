const std = @import("std");
const globs = @import("globs.zig");
const hlp = @import("helpers.zig");

const TokenIterator = hlp.TokenIterator;

// TODO: remove this
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
    //tokenized code 
    code:[]Token,
    //depth (nested; determines the scope, 0 for global scope)
    depth:usize = undefined,
    //name of the function
    name:?[]u8 = null, //only non-null briefly *during* finalizing stage for internal tracking, after used
    //source code of function (for debug mode) TODO: debug mode
    source:[]u8 = undefined,
    //template token for return
    return_template:Token,
    //parameter slots
    params:[]Param,

    //param type
    pub const Param = struct {
        //name (ident)
        name:[]u8,
        //type of value
        type:Token.ValueType,
        //value (set during runtime)
        value:?*Token,
        
        //helper to free a param
        pub fn free(self:*Param, alloc:std.mem.Allocator) void {
            alloc.free(self.name);
            if (self.value) |v|
                @constCast(v).free(alloc);
        }

        //helper to create an owned (duped) param
        pub fn own(self:*Param, alloc:std.mem.Allocator) !Param {
            return .{
                .name = try alloc.dupe(u8, self.name),
                .type = self.type,
                .value =
                    if (self.value) |v|
                        @constCast(&(try @constCast(v).own(alloc)))
                    else
                        null,
            };
        }
    };

    //helper to free an entire function
    pub fn free(self:*Function, alloc:std.mem.Allocator) void {
        if (self.name) |n| alloc.free(n);

        for (self.code) |*t|
            @constCast(t).free(alloc);

        for (self.params) |*p|
            @constCast(p).free(alloc);
    }

    // TODO: remove this
    pub fn own_and_free(self:*Function, alloc:std.mem.Allocator) !Function {
        defer self.free(alloc);

        var code = try std.ArrayList(Token).initCapacity(alloc, 0); 
        defer _ = code.deinit(alloc);
        for (self.code) |t|
            try code.append(alloc, t);

        var params = try std.ArrayList(Param).initCapacity(alloc, 0); 
        defer _ = params.deinit(alloc);
        for (self.params) |p|
            try params.append(alloc, p);

        return .{
            .code = try code.toOwnedSlice(alloc),
            .source = undefined, // TODO: dupe if I decide to add it 
            .return_template = try self.return_template.own(alloc),
            .params = try params.toOwnedSlice(alloc),
        };
    }
};

pub const Tokenized = struct {
    //resulting (parsed and finalized) tokens
    tokens:[]Token,

    //itr:TokenIterator,
    
    //namespace
    namespace:std.StringHashMap(ThingInNamespace),

    // TODO: can these be moved?
    alloc:*std.mem.Allocator,
    arena:*std.heap.ArenaAllocator,

    //helper free the result of tokenization
    pub fn free(self:*Tokenized, alloc:std.mem.Allocator) void {
        _ = .{ self, alloc };
        //for (self.tokens) |*token|
        //    @constCast(token).free(alloc);
        //var itr = self.namespace.iterator();
        //while (itr.next()) |kv| {
        //    alloc.free(kv.key_ptr.*);
        //    const value = kv.value_ptr.*;
        //    if (value.function) |*f|
        //        @constCast(f).free(alloc);
        //    if (value.variable) |*v|
        //        @constCast(v).free(alloc);
        //}
    }
};

pub const ThingInNamespace = struct {
    function:?Function = null,
    variable:?Token = null,

    //helper to check if a namespace entry is a function
    pub fn is_fn(self:*ThingInNamespace) bool {
        if (self.function != null and self.variable != null)
            @panic("ThingInNamespace appears to be both a function and a variable");
        return self.function != null;
    }

    //helper to check if a namespace entry is a variable
    pub fn is_var(self:*ThingInNamespace) bool {
        if (self.function != null and self.variable != null)
            @panic("ThingInNamespace appears to be both a variable and a function");
        return self.variable != null;
    }
};

pub const Token = struct {
    //literal in source code (ident name, string literal, unparsed number, etc.)
    raw: []u8,

    //type of the token
    type: Token.Type,

    //how many blocks deep the token is
    //  (will be used for garbage collection, once I start working on that)
    depth:usize = undefined,

    //for finding a token in the source code
    line_number:usize,
    line_pos:usize,

    //for when I get around to cleaning-up the memory handling
    free_called:bool = false,

    //holds the type of the token
    type_info:struct {
        value:?Token.ValueType = null,
        thing:?Token.ThingType = null,
        symbol:?Token.Symbol = null,
        keyword:?Token.Keyword = null,
        ident:?Token.IdentType = null,
    } = .{},

    //holds the value of a token (variable, number, bool, etc.)
    value:struct {
        //set all to 'null' to have null value
        num:?isize = null,
        bool:?bool = null,
        string:?[]u8 = null,
        ptr:?*Token = null,
    } = .{},

    //token types
    pub const Type = enum {
        INVALID, //used internally, TODO: parse result for these before interpreting
        FN,      //functions
        VALUE,   //values (literals)
        SYMBOL,  //symbols (eg: '~=')
        KEYWORD, //keywords (eg: 'goto')
        IDENT,   //identifier (vairables)
    };

    pub const ValueType = enum {
        UNKNOWN,   //used internally, TODO: parse result for these before interpreting
        VOID,      //void (empty) token
        NUM,       //number TODO: number typess (eg: float, u8, u32, u64, i8, i32, i64)
        FLAG,      //flags ( eg: [[ foo bar ]] )
        STRING,    //string
        COMMENT,   //comment (used briefly by tokenizer, but never present in resulting tokens)
        BOOL,      //boolean
        BUILTIN,   //builtin (likely a type or something like #pipe)
        TOKEN_PTR, //might remove this TODO: pointers
        TYPE,      // TODO: types
    };

    //types of identifiers
    pub const IdentType = enum {
        @"fn",  //function (declaration should be parsed out of final tokens)
        @"let", //variable
        @"set", //constant
    };

    //general scope-related stuff
    pub const ThingType = enum {
        SHELL_CMD,
        BUILTIN,
        LOCAL,
        EXTERNAL,
    };

    //symbols
    pub const Symbol = enum {
        //braces
        @"{",   @"}",

        //parentheses
        @"(",   @")",

        //angle brackets
        @"<",   @">",

        //variations of equal
        @"=",   @"==",
        @">=",  @"<=",

        //for easier parsing
        @";",
    };
    
    //keywords
    pub const Keyword = enum {
        //conditionals
        @"?",   @"if",
        @"?!",  @"else",

        //conditional operators
        @"and", @"or", @"xor",
        @"fn",
        @"let", @"set",
        @"return",
    };

    pub const Errors = error {
        IsNotFlag,
        InvalidOperation
    };

    // TODO: possibly remove this
    pub fn resolve_var(self:*Token) !*Token {
        if (self.type != .IDENT)
            return Token.Errors.InvalidOperation;
        if (self.value.ptr) |ptr|
            return ptr
        else
            return Token.Errors.InvalidOperation;
    }

    // TODO: possibly remove this
    pub fn set_value(self:*Token, comptime T:type, value:T) !void {
        if (self.type != .IDENT)
            return Token.Errors.InvalidOperation;
        var thing = if (self.value.ptr) |ptr| ptr else self; 
        switch (T) {
            []u8 => if (thing.is_value_type(.STRING)) {
                    thing.value.string = value;
                } else
                    return Token.Errors.InvalidOperation,

            isize => if (self.is_value_type(.NUM)) {
                    thing.value.num = value;
                } else
                    return Token.Errors.InvalidOperation,

            bool => if (self.is_value_type(.BOOL)) {
                    thing.value.bool = value;
                } else
                    return Token.Errors.InvalidOperation,

            else => std.debug.panic("TODO: Token.set_value(...) for type {t}\n", .{T}),
        }
    }

    //helper to check if a value type matches
    pub fn is_value_type(self:*Token, value_type:@This().ValueType) bool {
        if (self.type != .VALUE) return false;
        return self.type_info.value.? == value_type;
    }

    //helper to check if a token is a specific symbol
    pub fn is_symbol(self:*Token, check:Token.Symbol) bool {
        if (self.type != .SYMBOL) return false;
        return self.type_info.symbol.? == check;
    }

    //helper to check if a token is a specific keyword
    pub fn is_keyword(self:*Token, check:Token.Keyword) bool {
        if (self.type != .KEYWORD) return false;
        return self.type_info.keyword.? == check;
    }

    //helper to check if a token is one of a set of specific keywords
    pub fn is_oneof_keywords(self:*Token, check:[]Token.Keyword) bool {
        if (self.type != .KEYWORD) return false;
        for (check) |thing|
            if (self.is_keyword(thing)) return true;
        return false;
    }

    //helper to check if a token is one of a set of specific symbols
    pub fn is_oneof_symbols(self:*Token, check:[]Token.Symbol) bool {
        if (self.type != .SYMBOL) return false;
        return for (check) |thing| {
            if (self.is_symbol(thing)) break true;
        } else
            false;
    }

    //helper to check if a token is a specific ident type
    pub fn is_ident(self:*Token, check:Token.IdentType) bool {
        if (self.type != .IDENT) return false;
        return self.type_info.ident.? == check;
    }

    //helper get an owned (duped) token from current
    pub fn own(self:*Token, alloc:std.mem.Allocator) !Token {
        return .{
            .raw = try alloc.dupe(u8, self.raw),
            .type = self.type,
            .depth = self.depth,

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
                .string = if (self.value.string) |str|
                        try alloc.dupe(u8, str)
                    else
                        null,
                .ptr = self.value.ptr,
            },
        };
    }

    //helper to expand flag type value (eg: 'foo' to '--foo')
    //  TODO: syntax for flipping default bahavior
    pub fn expand_flag(self:*Token, alloc:std.mem.Allocator) ![]u8 {
        if (!self.is_value_type(.FLAG)) return Token.Errors.IsNotFlag;
        
        var res = try std.ArrayList(u8).initCapacity(alloc, 0);
        defer _ = res.deinit(alloc);

        try res.append(alloc, '-');
        if (self.raw.len > 1) try res.append(alloc, '-');
        try res.appendSlice(alloc, try alloc.dupe(u8, self.raw));

        return try res.toOwnedSlice(alloc);
    }

    //helper to free a token
    pub fn free(self:*Token, alloc:std.mem.Allocator) void {
        if (self.free_called) return; //just in case
        defer self.free_called = true;

        if (!self.is_value_type(.VOID))
            alloc.free(self.raw);
        if (self.value.string) |str|
            alloc.free(str);
    }

    //helper to print a token
    pub fn print(self:*Token) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer _ = arena.deinit();
        const alloc = arena.allocator();

        //result is stored in an array_list
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
        //if (self.value.ptr) |thing| try fmted.print(
        //    alloc,
        //    "\t\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{b64}\x1b[1;37m}}\x1b[0m\n",
        //    .{ 7, @typeName(@TypeOf(thing)), std.mem.asBytes(thing), }
        //);

        try globs.stdout.print("{s}", .{fmted.items}); 
    }
};
