const std = @import("std");

pub const NamespaceEntry = struct {
    type:BasicTok.KeyWords,
    alloc:*std.mem.Allocator,
    fn_stuff:FnStuff = undefined,
    var_stuff:VarStuff = undefined,

    pub const FnStuff = struct {
        paramTemplate:[]Param,
        content:[]BasicTok, //content:[]RichTok,
        local_namespace:std.StringHashMap(BasicTok),

        pub const Param = struct {
            name:[]u8,
            type:ValueType,

            pub fn init(tok:BasicTok, value_type:ValueType) Param {
                return .{
                    .name = tok.raw,
                    .type = value_type,
                };
            }
        };
    };

    pub const VarStuff = struct {
        type:ValueType,
        value:struct {
            string:[]u8 = undefined,
            number:isize = undefined,
            byte:u8 = undefined,
        }
    };
};

pub const ValueType = enum {
    Str,
    Num,
    B,
};

pub const BasicTok = struct {
    raw:[]u8,
    type:Type,

    keyword:KeyWords = undefined,
    symbol:Symbols = undefined,
    ident_info:IdentInfo = undefined,
    type_info:TypeInfo = undefined,

    alloc:*std.mem.Allocator,

    pub const KeyWords = enum {
        @"set",
        @"let",
        @"fn",
    };

    pub const Symbols = enum {
        @"{", @"}",
        @"(", @")",
        @";",
        @"=",
    };

    pub const Type = enum {
        STRING,
        IDENT,
        KEYWORD,
        SYMBOL,
        TYPE,
    };

    const IdentInfo = struct {
        type:IdentType,
        fn_params:[]BasicTok = undefined, //fn_params:[]*BasicTok = undefined,

        pub const IdentType = enum {
            @"fn",
            @"set",
            @"let",
        };
    };

    pub const TypeInfo = struct {
        type:ValueType,
    };

    pub fn deinit(self:*BasicTok) void {
        self.alloc.free(self.raw);
    }

    pub fn looks_like_symbol(check:[]u8) bool {
        _ = std.meta.stringToEnum(
            BasicTok.Symbols, check
        ) orelse
            return false;
        return true;
    }

    pub fn is_symbol(self:*BasicTok, symbol:Symbols) bool {
        if (!self.type == .SYMBOL) return false;
        return self.symbol == symbol;
    }
};
