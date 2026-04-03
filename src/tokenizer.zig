const std = @import("std");
const globs = @import("globs.zig");
const hlp = @import("helpers.zig");
const parser = @import("parser.zig");

const stdout = globs.stdout;
const stderr = globs.stderr;

pub const Token = struct {
    raw: []u8,
    type: @This().Type,
    value_type: ?@This().ValueType = null,
    thing_type:?@This().ThingType = null,
    symbol_type:?@This().Symbol = null,
    keyword_type:?@This().Keyword = null,
    parsed_num:?usize = null, // TODO: other number types
    bool_value:?bool = null,

    pub const Type = enum {
        INVALID,
        FN,
        VALUE,
        SYMBOL,
        KEYWORD,
    };

    pub const ValueType = enum {
        UNKNOWN,
        VOID,
        NUM,
        FLAG,
        STRING,
        COMMENT,
        BOOL,
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
        @"and", @"or", @"xor",
        @"fn",
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
                ++ "\x1b[0;3{d}m{s}\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\n",
            .{
                1, try parser.unescape(arena.allocator(), self.raw),
                2, @typeName(@TypeOf(self.type)), @tagName(self.type)
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

        try stdout.print("{s}", .{fmted.items}); 
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
};

// TODO: no printing, just return error
pub const Error = error {
    NAN,
    INVALID,
};

pub const Tokenizer = struct {
    input:[]const u8,
    cur:u8,
    pos:?usize,
    expected_type:Token.Type,
    parsing_as:?Token.ValueType,
    mem:std.ArrayList(u8),
    res:std.ArrayList(Token),
    alloc:std.mem.Allocator,
    string_type:u8,
    paren_depth:usize = 0,
    escaping:bool,
    comment_depth:usize,
    is_start_of_thing:bool,
    thing_type:?Token.ThingType,

    pub fn init(in:[]const u8, alloc:std.mem.Allocator) !Tokenizer {
        return .{
            .input = in,
            .pos = null,
            .string_type = 0,
            .expected_type = .INVALID,
            .parsing_as = null,
            .cur = 0,
            .mem = try std.ArrayList(u8).initCapacity(alloc, 0),
            .res = try std.ArrayList(Token).initCapacity(alloc, 0),
            .alloc = alloc,
            .escaping = false,
            .comment_depth = 0,
            .is_start_of_thing = true,
            .thing_type = null,
        };
    }
    pub fn deinit(self:*Tokenizer) void {
        _ = self.mem.deinit(self.alloc);
        _ = self.res.deinit(self.alloc);
    }

    fn dump_mem(self:*Tokenizer) ![]u8 {
        defer _ = self.mem.clearAndFree(self.alloc);
        return try self.mem.toOwnedSlice(self.alloc);
    }

    fn new_token(
        self:*Tokenizer,
        expecting:Token.Type,
        parsing:?Token.ValueType
    ) !Token {
        defer {
            self.mem.clearAndFree(self.alloc);
            self.parsing_as = null;
        }
        const raw = try self.dump_mem();

        if (raw.len < 1)
            try self.unexpected(null);

        return .{
            .raw  = raw,
            .type = expecting,
            .value_type = parsing,
            .thing_type = self.thing_type,
        };
    }

    fn new_symbol_token(
        self:*Tokenizer,
        literal:?[]u8,
    ) !Token {
        const thing = if (literal) |foo| foo else self.mem.items;
        //const thing = if (literal.len > 0) literal else self.mem.items;
        const symbol = std.meta.stringToEnum(
            Token.Symbol, thing
        ) orelse return Error.INVALID;
        return .{
            .raw = try self.alloc.dupe(u8, thing),
            .type = .SYMBOL,
            .symbol_type = symbol,
        };
    }
    
    fn new_keyword_token(
        self:*Tokenizer,
        literal:?[]u8,
    ) !Token {
        const thing = if (literal) |foo| foo else self.mem.items;
        //const thing = if (literal.len > 0) literal else self.mem.items;
        const keyword = std.meta.stringToEnum(
            Token.Keyword, thing
        ) orelse return Error.INVALID;

        return .{
            .raw = try self.alloc.dupe(u8, thing),
            .type = .KEYWORD,
            .keyword_type = keyword,
        };
    }

    pub fn unexpected(self:*Tokenizer, thing:?[]u8) !void {
        try stdout.print(
            "unexpected token (|{s}| from {s}): |{c}|\n",
            .{
                if (thing) |uh| uh else self.mem.items,
                if (self.parsing_as) |as| @tagName(as) else "NOTHING",
                self.cur
            }
        );
        std.process.exit(1);
    }

    fn is_keyword(self:*Tokenizer) bool {
        _ = std.meta.stringToEnum(
            Token.Keyword, self.mem.items
        ) orelse
            return false;
        return true;
    }

    fn new_num_token(self:*Tokenizer, thing:?[]u8) !Token {
        const literal = if (thing) |foo| foo else self.mem.items;
        const parsed = std.fmt.parseInt(usize, literal, 10) catch return Error.NAN;
        return .{
            .raw = try self.alloc.dupe(u8, literal),
            .type = .VALUE,
            .value_type = .NUM,
            .parsed_num = parsed,
        };
    }

    fn new_who_knows_what(self:*Tokenizer) !Token {
        defer self.mem.clearAndFree(self.alloc);
        const to_try = [_]*const @TypeOf(Tokenizer.new_keyword_token) {
            &Tokenizer.new_keyword_token,
            &Tokenizer.new_symbol_token,
            &Tokenizer.new_num_token,
        };
        loop: for (to_try) |f| {
            return f(self, self.mem.items) catch continue :loop;
        }
        return Error.INVALID;
    }

    pub fn do(self:*Tokenizer) ![]Token {
        loop: while (self.next()) |b| {
            if (std.ascii.isWhitespace(b)) if (self.mem.items.len > 0 and !self.is_string()) {

                defer self.mem.clearAndFree(self.alloc);
                const tokenized:Token = self.new_who_knows_what() catch {
                    try self.unexpected(null);
                    unreachable;
                };
                try self.res.append(self.alloc, tokenized);

                continue :loop;
            } else if (!self.is_string()) continue :loop;

            switch (b) {
                '(', ')' => if (self.mem.items.len > 0 and b == '(' and !self.is_keyword()) {
                    if (self.thing_type) |_| {} else {
                        self.thing_type = .LOCAL;
                    }
                    const func = try self.new_token(.FN, null);
                    self.thing_type = null;
                    try self.res.append(self.alloc, func);
                    if (!try self.get_args()) {
                        try stderr.print("failed to get args\n", .{});
                        std.process.exit(1);
                    }
                } else {
                    if (self.mem.items.len > 0) {
                        const tokenized:Token = self.new_who_knows_what() catch {
                            try self.unexpected(null);
                            unreachable;
                        };
                        try self.res.append(self.alloc, tokenized);
                    }

                    if (b == '(') self.paren_depth += 1;
                    // TODO: handle integer "overflow" (under flow)
                    if (b == ')') self.paren_depth -= 1;

                    const new = try self.new_symbol_token(@constCast(&[_]u8{b}));
                    try self.res.append(self.alloc, new);
                },
                ';', '{', '}' => {
                    defer self.is_start_of_thing = true;

                    if (self.mem.items.len > 0)
                        try self.unexpected(null);
                    const new = try self.new_symbol_token(@constCast(&[_]u8{b}));
                    try self.res.append(self.alloc, new);
                },
                else => try self.mem.append(self.alloc, b),
            }
        }
        return self.res.toOwnedSlice(self.alloc);
    }

    fn next(self:*Tokenizer) ?u8 {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.pos.? >= self.input.len) return null;
        self.cur = self.input[self.pos.?];

        const is_comment = self.cur == '#' and self.peek() == '(' and !self.is_string();
        if (is_comment) if (self.parsing_as) |as| {
            if (as != .COMMENT) self.comment();
        } else
            self.comment();

        if (self.is_start_of_thing and !std.ascii.isWhitespace(self.cur)) {
            self.thing_type = switch (self.cur) {
                '#' => .BUILTIN,
                '$' => .SHELL_CMD,
                '@' => .EXTERNAL,
                else => null,
            };
            self.is_start_of_thing = false;
            return self.next();
        }

        return self.cur;
    }

    fn back(self:*Tokenizer) ?u8 {
        self.pos = if (self.pos) |p| p - 1 else 0;
        if (self.pos.? < 1) return null;
        self.cur = self.input[self.pos.?];
        return self.cur;
    }

    fn peek(self:*Tokenizer) u8 {
        if (self.pos.?+1 >= self.input.len) return 0;
        return self.input[self.pos.?+1];
    }
    fn previous(self:*Tokenizer) u8 {
        if (self.pos.? < 1) return 0;
        return self.input[self.pos.?-1];
    }

    fn is_string(self:*Tokenizer) bool {
        return if (self.parsing_as) |t| t == .STRING else false;
    }

    fn get_args(self:*Tokenizer) !bool {
        if (self.mem.items.len > 0) {
            try stderr.print("error attempting to parse args: (mem not empty)\n", .{});
            std.process.exit(1);
        }
        while (self.next() != null and (self.cur != ')' or self.is_string())) {
            if (std.ascii.isWhitespace(self.cur)) if (self.parsing_as) |as| {
                if (as == .STRING)
                    try self.mem.append(self.alloc, self.cur)
                else {
                    try stderr.print(
                        "unexpected space (parsing as {s})\n", .{@tagName(as)}
                    );
                    std.process.exit(1);
                }
            } else {} else if (self.escaping) {
                try self.mem.append(
                    self.alloc, switch (self.cur) {
                        // TODO: octal, decimal, hex, and string interpolation 
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        'e' => '\x1b',
                        'a' => '\x07',
                        'b' => '\x08',
                        'f' => '\x0c',
                        'v' => '\x0b',
                        else => self.cur,
                    }
                );
                self.escaping = !self.escaping;
            } else switch (self.cur) {
                '"', '\'' => {
                    if (self.parsing_as) |t| {
                        if (t == .STRING and self.string_type == self.cur) {
                            if (self.peek() == ')' or self.peek() == ' ') {
                                self.parsing_as = null;
                                self.string_type = 0;
                                const new = try self.new_token(.VALUE, t);
                                try self.res.append(self.alloc, new);
                            } else
                                @panic("TODO: 'else {}'");
                        } else
                            try self.mem.append(self.alloc, self.cur);
                    } else {
                        self.string_type = self.cur;
                        self.parsing_as = .STRING;
                    }
                },
                // TODO: lists
                '[' => if (!self.is_string()) {
                    if (self.parsing_as) |_| {
                        try self.unexpected(@constCast("["));
                    } else if (self.peek() == '[')
                        try self.consume_flags()
                    else
                        @panic("TODO: lists");
                } else try self.mem.append(self.alloc, self.cur),

                '\\' => self.escaping = !self.escaping,

                else => if (hlp.is_num(self.cur) and !self.is_string()) {
                    try self.consume_num();
                    const new = try self.new_token(.VALUE, .NUM);
                    try self.res.append(self.alloc, new);
                } else {
                    try self.mem.append(self.alloc, self.cur);
                },
            }
        }
        return self.peek() != 0 or self.cur != ')';
    }

    pub fn print(self:*Tokenizer, tokens:[]Token) !void {
        _ = self;
        for (tokens) |*token| try token.print();
    }

    fn consume_num(self:*Tokenizer) !void {
        self.parsing_as = .NUM;
        defer _ = self.back();
        _ = self.back();
        while (self.next()) |b| {
            if (std.ascii.isWhitespace(b) or b == ')') return;
            if (hlp.is_num(b))
                try self.mem.append(self.alloc, b)
            else
                return Error.NAN;
        }
    }

    fn consume_flags(self:*Tokenizer) !void {
        self.parsing_as = .FLAG;

        if (self.mem.items.len > 0) @panic("consume_arg: MEM GREATER THAN 0");

        defer _ = self.mem.clearAndFree(self.alloc);

        //skip second '[' and ']'
        _ = self.next();
        defer _ = self.next();

        loop: while (self.next()) |b| {
            if (std.ascii.isWhitespace(b) or (b == ']' and self.peek() == ']')) {
                if (self.mem.items.len > 0) {
                    const new = try self.new_token(.VALUE, .FLAG);
                    try self.res.append(self.alloc, new);
                }
                if (b == ']' and self.peek() == ']') return else continue :loop;
            }

            // TODO: handle invalid symbol in flag

            try self.mem.append(self.alloc, b);
        }
    }

    fn builtin(self:*Tokenizer) !void {
        if (self.peek() == '(') return self.comment();
        @panic("TODO: builtins");
    }

    fn comment(self:*Tokenizer) void {
        self.comment_depth = 1;
        _ = self.next();
        defer _ = self.next();

        const was_parsing = if (self.parsing_as) |as| as else null;
        self.parsing_as = .COMMENT;
        defer self.parsing_as = was_parsing;

        loop: while (self.comment_depth > 0 and self.next() != null) {
            if (self.escaping) {
                self.escaping = false;
                continue :loop;
            }
            switch (self.cur) {
                '(' => self.comment_depth += 1,
                ')' => self.comment_depth -= 1,
                '\\' => self.escaping = true,
                else => {},
            }
        }
    }

    pub fn free(self:*Tokenizer, tokens:[]Token) void {
        for (tokens) |t| self.alloc.free(t.raw);
    }
};

pub fn dupe(alloc:std.mem.Allocator, in:[]Token) ![]Token {
    var tokens = try std.ArrayList(Token).initCapacity(alloc, 0);
    defer _ = tokens.deinit(alloc);
    for (in) |token| try tokens.append(alloc, try @constCast(&token).own(alloc));
    return try tokens.toOwnedSlice(alloc);
}

pub fn free(alloc:std.mem.Allocator, tokens:[]Token) void {
    for (tokens) |t| alloc.free(t.raw);
}
