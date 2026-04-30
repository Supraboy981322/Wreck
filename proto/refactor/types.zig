const std = @import("std");
const hlp = @import("helpers.zig");
const builtins = @import("builtins.zig");

pub const TokenType = std.meta.Tag(Token);
pub const Token = union(enum) {
    literal:Value,
    ident:Ident,
    symbol:Symbol,
    keyword:Keyword,
    type:Type,

    pub const PossibleTokens = std.meta.Tag(Token);
    pub const Keyword = enum {
        @"if", @"?",
        @"else", @"?!",
        @"elif", @"?!?", // TODO: maybe change ?!?

        set, let,
        @"fn",

        pub fn is_else(self:*Keyword) bool {
            return self == .@"else" or self == .@"?!";
        }

        pub fn is_else_if(self:*Keyword) bool {
            return self == .@"elif" or self == .@"?!?";
        }

        pub fn is_if(self:*Keyword) bool {
            return self == .@"if" or self == .@"?";
        }
    };

    pub const Builtin = enum {
        print,
        //goto = @panic("TODO: goto"),

        const functions:[1]*const fn([]Token) builtins.Error!Token = .{
            &builtins.print,
        };
        pub fn run(self:*Builtin) builtins.Error!Token {
            const match = functions[@intFromEnum(self)];
            return try match();
        }
    };


    pub const Ident = struct {
        name:[]u8,
        builtin:?Builtin,
        type:Ident.Type,
        pub fn init(alloc:std.mem.Allocator, name:[]u8, hint:MakeHint) !void {
            _ = hint;
            return .{
                .name = try alloc.dupe(u8, name),
                .builtin = false,
                .type = .@"fn",
            };
        }
        pub const Type = enum {
            set, let,
            @"fn",
            pub fn is_variable(self:*Ident.Type) bool {
                return self == .set or self == .let;
            }
        };
    };

    pub const Type = std.meta.Tag(Value);
    pub const Value = union(enum) {
        string:[]u8,
        int:i256,
        void:void,
        bool:bool,

        uint:u256,
        list:void, // TODO: lists
    };

    pub const Symbol = enum {
        @"{", @"}",
        @"(", @")",
        @"<",   @">",

        @";",
        @"=",

        //basic logical comparison
        @"==", @"!=", @">=", @"<=",

        @"ifnull", @"or", @"xor", @"and", @"nor",

        // TODO: everything that follows this comment

        //basic bitwise
        @"&", @"|", @"^", @">>", @"<<",

        //bitwise assignment
        @"&=", @"|=", @"^=", @"<<=", @">>=", @"<<|=", @">>|=",

        //basic operators
        @"*", @"+",  @"/", @"%", @"-",

        //basic assignment
        @"-=", @"+=", @"*=", @"/=", @"%=",
        
        //basic symbols 
        @"[", @"]",

        //non-standard
        @"~=",  //loose equality (ignores type; eg: "1" ~= 1 would be true)
        @"#=",  //contains (lists, strings)
        @"++",  //join (lists, strings)
        @"**",  //glob
        @"..",  //range
        @"...", //expand
        @",,",  //splat
    };

    pub fn parse_literal(alloc:std.mem.Allocator, raw:[]u8, hint:?Type) !?Token {
        const expect:ExpectType = @as(ExpectType, hint orelse .unknown);
        // TODO: list
        return .{
            .value = if (hlp.is_num(raw) or expect.num()) .{
                // TODO: uint
                .int = std.fmt.parseInt(isize, raw, 10) catch unreachable,
            } else if (hlp.parse_bool(raw) or expect == .bool) |v| .{
                .bool = v
            } else if (std.mem.eql(u8, raw, "_") or expect == .void) .{
                .void = {},
            } else if (expect == .string) .{
                .string = try alloc.dupe(u8, raw),
            } else
                return null,
        };
    }


    pub const ExpectType = enum {
        unknown,
        pub fn num(self:*ExpectType) bool {
            return self == .int or self == .uint;
        }
    } || Type;

    pub const MakeHint = struct {
        expected:?PossibleTokens = null,
        type:?Type = null,
    };

    pub fn make(alloc:std.mem.Allocator, raw:[]u8, hint:MakeHint) Token {
        return 
            if (std.meta.stringToEnum(Symbol, raw)) |symbol| return .{
                .symbol = symbol,
            } else if (std.meta.stringToEnum(Keyword, raw)) |keyword| .{
                .keyword = keyword,
            } else if (std.meta.stringToEnum(Type, raw)) |t| .{
                .type = t,
            } else if (parse_literal(alloc, raw, hint.type)) |matched|
                matched
            else .{
                .ident = .init(raw, hint),
            };
    }

    pub fn mk_builtin(alloc:std.mem.Allocator, raw:[]u8) !Token {
        const matched = std.meta.stringToEnum(Builtin, raw) orelse return error.UnknownBuiltin;
        return .{
            .ident = .{
                .type = .@"fn",
                .builtin = matched,
                .name = try alloc.dupe(u8, raw),
            }
        };
    }
};
