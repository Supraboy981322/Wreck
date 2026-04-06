const std = @import("std");
const globs = @import("globs.zig");
const hlp = @import("helpers.zig");
const parser = @import("parser.zig");
const types = @import("types.zig");

const stdout = globs.stdout;
const stderr = globs.stderr;

// TODO: no printing, just return error
pub const Error = error {
    NAN,
    INVALID,
};

const ThingInNamespace = types.ThingInNamespace;
const Function = types.Function;
const Param = types.Function.Param;

pub const TokenIterator = hlp.TokenIterator;
pub const Tokenized = types.Tokenized;
pub const Token = types.Token;

pub const Tokenizer = struct {
    input:[]const u8,
    line_num:usize = 1,
    line_pos:usize = 0,
    comment_depth:usize,
    paren_depth:usize = 0,
    is_start_of_thing:bool,

    cur:u8,
    pos:?usize,
    escaping:bool,
    string_type:u8,
    alloc:std.mem.Allocator,
    thing_type:?Token.ThingType,

    expected_type:Token.Type,
    parsing_as:?Token.ValueType,

    mem:std.ArrayList(u8),
    res:std.ArrayList(Token),
    known_idents:std.ArrayList(Token),

    pub fn init(in:[]const u8, alloc:std.mem.Allocator) !Tokenizer {
        const offset = if (in[0] == '#' and in[1] == '!') b: {
            var i:usize = 0;
            while (in[i] != '\n') : (i += 1) {}
            break :b i;
        } else 0;
        return .{
            .input = in[offset..],
            .pos = null,
            .string_type = 0,
            .expected_type = .INVALID,
            .parsing_as = null,
            .cur = 0,
            .mem = try std.ArrayList(u8).initCapacity(alloc, 0),
            .res = try std.ArrayList(Token).initCapacity(alloc, 0),
            .known_idents = try std.ArrayList(Token).initCapacity(alloc, 0),
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
        _ = self.known_idents.deinit(self.alloc);
    }

    pub fn unexpected(self:*Tokenizer, thing:?[]u8) !void {
        try stdout.print(
            "\x1b[1;31munexpected token " 
                    ++ "\x1b[1;37m(|\x1b[0m{s}\x1b[1;37m|\x1b[0m "
                    ++ "\x1b[35mfrom\x1b[0m \x1b[36m{s}\x1b[0;35m while expecting "
                    ++ "\x1b[36m{s}\x1b[1;37m): byte{{\x1b[0m{c}\x1b[1;37m}} "
                    ++ "mem{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{
                if (thing) |uh| uh else self.mem.items,
                if (self.parsing_as) |as| @tagName(as) else "NOTHING",
                (if (self.expected_type != .INVALID)
                    @tagName(self.expected_type)
                else
                    "[unknown]"),
                self.cur,
                self.mem.items,
            }
        );

        if (self.pos) |p| if (p < self.input.len) {
            if (self.res.pop()) |*token| {
                try stderr.print("last valid token:\n", .{});
                try @constCast(token).print();
            }
            var offset, var end = .{ p, p };
            while (offset > 0) : (offset -= 1) {
                if (self.input[offset] == '\n') break;
            }
            while (end < self.input.len) : (end += 1) {
                if (self.input[end] == '\n') break;
            }
            offset += 1;

            if (self.mem.items.len > 0) end -= self.mem.items.len - 1;

            var arrow = try std.ArrayList(u8).initCapacity(self.alloc, 0);
            defer _ = arrow.deinit(self.alloc);

            for (0 .. self.pos.? - offset - self.mem.items.len) |_|
                    try arrow.append(self.alloc, ' ');
            try arrow.appendSlice(self.alloc, "\x1b[33m");
            for (0..self.mem.items.len) |_|
                    try arrow.append(self.alloc, '^');

            if (self.mem.items.len > 0) end += self.mem.items.len - 1;

            try stdout.print(
                "\x1b[32minvalid line:\x1b[0m\n\t{s}\n\t{s}\x1b[0m\n",
                .{ self.input[offset..end], arrow.items, }
            );
        };
        std.process.exit(1);
    }

    fn dump_mem(self:*Tokenizer) ![]u8 {
        defer _ = self.mem.clearAndFree(self.alloc);
        return try self.mem.toOwnedSlice(self.alloc);
    }

    fn add_if_mem(self:*Tokenizer) !void {
        if (self.mem.items.len > 0) {
            const tokenized:Token = self.new_who_knows_what() catch {
                std.debug.print("Tokenizer.add_if_mem()\n", .{});
                try self.unexpected(null);
                unreachable;
            };
            try self.res.append(self.alloc, tokenized);
        }
    }

    fn is_keyword(self:*Tokenizer) bool {
        _ = std.meta.stringToEnum(
            Token.Keyword, self.mem.items
        ) orelse
            return false;
        return true;
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

            .line_number = self.line_num,
            .line_pos = self.line_pos,

            .type_info = .{
                .value = parsing,
                .thing = self.thing_type,
            },
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

        if (symbol == .@"=") self.expected_type = .VALUE;

        return .{
            .raw = try self.alloc.dupe(u8, thing),
            .type = .SYMBOL,

            .line_number = self.line_num,
            .line_pos = self.line_pos,

            .type_info = .{
                .symbol = symbol,
            },
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

        if (keyword == .@"return")
            self.expected_type = .VALUE;

        return .{
            .raw = try self.alloc.dupe(u8, thing),
            .type = .KEYWORD,

            .line_number = self.line_num,
            .line_pos = self.line_pos,

            .type_info = .{
                .keyword = keyword,
            },
        };
    }

    fn new_num_token(self:*Tokenizer, thing:?[]u8) !Token {
        const literal = if (thing) |foo| foo else self.mem.items;
        const parsed = std.fmt.parseInt(isize, literal, 10) catch return Error.NAN;
        return .{
            .raw = try self.alloc.dupe(u8, literal),
            .type = .VALUE,

            .line_number = self.line_num,
            .line_pos = self.line_pos,

            .type_info = .{
                .value = .NUM,
            },
            
            .value = .{
                .num = parsed,
            },
        };
    }

    fn new_who_knows_what(self:*Tokenizer) !Token {
        var ok:bool = true;
        defer { if (ok) self.mem.clearAndFree(self.alloc); }
        const to_try = [_]*const @TypeOf(Tokenizer.new_keyword_token) {
            &Tokenizer.new_keyword_token,
            &Tokenizer.new_symbol_token,
            &Tokenizer.new_num_token,
        };
        loop: for (to_try) |f| {
            return f(self, self.mem.items) catch continue :loop;
        }
        if (self.expected_type == .IDENT) {

            var last_added = self.res.pop().?;
            var aux:?Token = null;
            defer { if (aux) |*a| @constCast(a).free(self.alloc); }
            if (last_added.type == .FN) {
                aux = last_added;
                last_added = self.res.pop().?;
            }

            const matched = std.meta.stringToEnum(
                Token.IdentType, last_added.raw
            ) orelse {
                try self.res.append(self.alloc, last_added);
                try self.unexpected(null);
                unreachable;
            };

            const name = if (aux) |a| a.raw else self.mem.items;

            const new:Token = .{
                .raw = try self.alloc.dupe(u8, name),
                .type = .IDENT,

                .line_number = self.line_num,
                .line_pos = self.line_pos,
                
                .type_info = .{
                    .ident = matched,
                },
            };
            self.expected_type = switch (matched) {
                .@"fn" => .INVALID,
                .@"let", .@"set" => .VALUE,
            };
            return new;
        } else if (self.expected_type == .VALUE) {
            //remove the symbol before
            var pre = self.res.pop().?;
            if (pre.is_oneof_keywords(
                &globs.keyword_sets_following_type.immediately
            )) {
                var value = try self.new_token(.VALUE, null);
                try self.populate_ident(&value);

                try self.res.append(self.alloc, pre);

                self.expected_type = .INVALID;
                return value;
            } else {
                defer pre.free(self.alloc);

                var identifier = self.res.pop().?;
                try self.populate_ident(&identifier);
                self.expected_type = .INVALID;

                return identifier;
            }
        } else for (self.known_idents.items) |*ident| {
            if (std.mem.eql(u8, ident.raw, self.mem.items)) {
                return try @constCast(ident).own(self.alloc);
            }
        }

        ok = false;
        return Error.INVALID;
    }

    fn populate_ident(self:*Tokenizer, ident:*Token) !void {
        const value =
            if (ident.type == .VALUE)
                try self.alloc.dupe(u8, ident.raw)
            else
                try self.alloc.dupe(u8, self.mem.items);
        defer self.alloc.free(value);

        if (value.len < 1) return Error.INVALID;

        const is_num = for (value) |b| {
            if (!hlp.is_num(b)) break false;
        } else true;

        const is_str = if (!is_num and value.len > 1) switch (value[0]) {
            '"', '\'' => value[value.len-1] == value[0],
            else => false,
        } else false;

        const is_bool = if (!is_str and !is_num) b: {
            _ = std.meta.stringToEnum(
                enum { @"true", @"false" }, value
            ) orelse break :b false;
            break :b true;
        } else false;

        const is_builtin = if (!is_str and !is_num and !is_bool) 
            value[0] == '#' 
        else false;

        ident.type_info.value = if (is_num)
            .NUM
        else if (is_str)
            .STRING
        else if (is_bool)
            .BOOL
        else if (is_builtin)
            .BUILTIN
        else
            return Error.INVALID;

        if (is_num)
            ident.value.num = std.fmt.parseInt(isize, value, 10) catch return Error.NAN;
        if (is_str)
            ident.value.string = try self.alloc.dupe(u8, value[1..value.len-1]);
        if (is_bool) {
            const sentenial = try self.alloc.dupeZ(u8, value);
            defer self.alloc.free(sentenial);
            ident.value.bool = std.zon.parse.fromSlice(
                bool,
                self.alloc,
                sentenial,
                null,
            .{}) catch unreachable;
        }

        var tracked = try ident.own(self.alloc);
        tracked.value.ptr = ident;
        tracked.value.string = if (is_str)
            try self.alloc.dupe(u8, value[1..value.len-1])
        else
            null;

        std.debug.print("ident names: {s} and {s}\n", .{tracked.raw, ident.raw});
        if (ident.type != .VALUE) 
            try self.known_idents.append(self.alloc, tracked);
    }

    pub fn do(self:*Tokenizer) !Tokenized {
        //defer self.known_idents.clearAndFree(self.alloc);

        loop: while (self.next()) |b| {
            if (std.ascii.isWhitespace(b)) if (self.mem.items.len > 0 and !self.is_string()) {

                defer self.mem.clearAndFree(self.alloc);
                var tokenized:Token = self.new_who_knows_what() catch {
                    try stdout.print("TODO: remove this print\n", .{});
                    try self.unexpected(null);
                    unreachable;
                };

                try self.res.append(self.alloc, tokenized);

                if (tokenized.is_oneof_keywords(
                    &globs.keyword_sets_following_type.ident
                )) self.expected_type = .IDENT;

                continue :loop;
            } else
                if (!self.is_string())
                    continue :loop;

            switch (b) {
                '(', ')' => if (self.mem.items.len > 0 and b == '(' and !self.is_keyword()) {
                    if (self.thing_type) |_| {} else {
                        self.thing_type = .LOCAL;
                    }

                    const pre = self.res.pop();
                    if (pre) |p| {
                        try self.res.append(self.alloc, p);
                    }

                    const func = try self.new_token(.FN, null);
                    self.thing_type = null;
                    try self.res.append(self.alloc, func);
                    
                    const pre_is_fn_declaration =
                        if (pre) |*p|
                            @constCast(p).is_keyword(.@"fn")
                        else
                            false;

                    if (pre_is_fn_declaration) {
                        std.debug.print("TODO: function declaration params\n", .{}); 
                        // for now, the function params are ignored, TODO: tokenize them
                        while (self.next() != null and self.cur != ')') {}
                    } else if (!try self.get_args()) {
                        try stderr.print("\x1b[5;3;1;33mfailed to get args\x1b[0m\n", .{});
                        try self.unexpected(null);
                    }
                } else {
                    try self.add_if_mem();

                    if (b == '(') self.paren_depth += 1;
                    // TODO: handle integer "overflow" (under flow)
                    if (b == ')') self.paren_depth -= 1;

                    const new = try self.new_symbol_token(@constCast(&[_]u8{b}));
                    try self.res.append(self.alloc, new);
                },
                ';', '{', '}' => {
                    try self.add_if_mem();

                    const new = try self.new_symbol_token(@constCast(&[_]u8{b}));
                    try self.res.append(self.alloc, new);
                },
                else => try self.mem.append(self.alloc, b),
            }
        }
        try self.add_if_mem();
        try self.context_pass();
        return try self.finalize();
    }

    fn can_be_start_of_thing(self:*Tokenizer) bool {
        const is_eox = switch (self.cur) {
            ';', '}' => true,
            else => false,
        };
        const no_mem = self.mem.items.len < 1;
        const not_string = (!self.is_string() and self.cur != '"' and self.cur != '\'');
        const is_whitespace = std.ascii.isWhitespace(self.cur);
        return no_mem and not_string and (is_whitespace or is_eox);
    }

    fn next(self:*Tokenizer) ?u8 {
        if (self.cur == '\n') {
            self.line_num += 1;
            self.line_pos = 0;
        }
        self.line_pos += 1;

        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.pos.? >= self.input.len) return null;
        self.cur = self.input[self.pos.?];

        const is_comment = self.cur == '#' and self.peek() == '(' and !self.is_string();
        if (is_comment) if (self.parsing_as) |as| {
            if (as != .COMMENT) self.comment();
        } else
            self.comment();

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
        if (self.pos) |p| {
            if (p < 1) return 0;
            return self.input[p-1];
        } else
            return 0;
    }

    fn is_string(self:*Tokenizer) bool {
        return if (self.parsing_as) |t| t == .STRING else false;
    }

    fn get_args(self:*Tokenizer) !bool {
        if (self.mem.items.len > 0) {
            try stderr.print("error attempting to parse args: (mem not empty)\n", .{});
            std.process.exit(1);
        }
        loop: while (
            self.next() != null and (
                (self.cur != ')' and self.cur != ';') or self.is_string()
            )
        ) {
            if (std.ascii.isWhitespace(self.cur)) if (self.parsing_as) |as| {
                if (as == .STRING)
                    try self.mem.append(self.alloc, self.cur)
                else {
                    try stderr.print(
                        "unexpected space (parsing as {s})\n", .{@tagName(as)}
                    );
                    std.process.exit(1);
                }
                continue :loop;
            };
            if (self.escaping) {
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
                continue :loop;
            }
            switch (self.cur) {
                '"', '\'' => {
                    if (self.parsing_as) |t| {
                        if (t == .STRING and self.string_type == self.cur) {
                            if (self.end_of_thing(null)) {
                                self.parsing_as = null;
                                self.string_type = 0;
                                const new = try self.new_token(.VALUE, t);
                                try self.res.append(self.alloc, new);
                            } else
                                std.debug.panic(
                                    "TODO: 'else {{}}' (|{s}| {s} line{{{d}}})",
                                .{&[_]u8{self.cur, self.peek()}, @tagName(t), self.line_num}
                                );
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
                        std.debug.print(
                            "Tokenizer.get_args() switch (self.cur) '[' => self.parsing_as", .{}
                        );
                        try self.unexpected(@constCast("["));
                    } else if (self.peek() == '[')
                        try self.consume_flags()
                    else
                        @panic("TODO: lists");
                } else try self.mem.append(self.alloc, self.cur),

                '\\' => self.escaping = !self.escaping,

                else => if (self.is_string()) {
                    try self.mem.append(self.alloc, self.cur);
                } else if (hlp.is_num(self.cur)) {
                    try self.consume_num();
                    const new = try self.new_token(.VALUE, .NUM);
                    try self.res.append(self.alloc, new);
                } else if (self.end_of_thing(false) and self.mem.items.len > 0) {
                    try self.mem.append(self.alloc, self.cur);
                    self.parsing_as = null;
                    self.string_type = 0;
                    const new = self.new_who_knows_what() catch {
                        std.debug.print(
                            "Tokenizer.get_args() switch self.cur else => "
                                    ++ "else if (self.end_of_thing(false) ....) {{\n",
                            .{}
                        );
                        try self.unexpected(null);
                        unreachable;
                    };
                    try self.res.append(self.alloc, new);
                } else if (!self.is_string() and !std.ascii.isWhitespace(self.cur)) {
                    try self.mem.append(self.alloc, self.cur); 
                } else if (!std.ascii.isWhitespace(self.cur)) {
                    std.debug.print(
                        "Tokenizer.get_args() switch self.cur else => else {{\n", .{}
                    );
                    try self.unexpected(null);
                },
            }
        }
        try self.add_if_mem();
        return self.peek() != 0 and (self.cur != ')' or self.cur != ';');
    }
    
    fn end_of_thing(self:*Tokenizer, can_be_string:?bool) bool {
        var res = self.peek() == ')' or self.peek() == ' ' or self.peek() == ';';
        if (can_be_string) |check|
            res = res and (self.is_string() == check);
        return res;
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

    pub fn context_pass(self:*Tokenizer) !void {
        for (self.res.items) |*token| switch (token.type) {
            .FN => {
                token.type_info.thing = switch (token.raw[0]) {
                    '#' => .BUILTIN,
                    '$' => .SHELL_CMD,
                    '@' => .EXTERNAL,
                    else => .LOCAL,
                };
                if (token.type_info.thing != .LOCAL) {
                    token.raw = token.raw[1..];
                }
            },
            else => {}
        };
    }

    pub fn finalize(self:*Tokenizer) !Tokenized {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer {
            _ = arena.reset(.free_all);
            _ = arena.deinit();
        }
        const process_alloc = arena.allocator();

        var finalized:Tokenized = .{
            .tokens = undefined,
            .global_namespace = undefined,
            .alloc = undefined,
            .arena = std.heap.ArenaAllocator.init(self.alloc),
        };
        finalized.alloc = finalized.arena.allocator();
        finalized.global_namespace = std.StringHashMap(ThingInNamespace).init(finalized.alloc);

        var itr = TokenIterator.init(self.res.items, .{ .use_void = true });

        var current_fn_mem:?Function = null;
        var mem = try std.ArrayList(Token).initCapacity(process_alloc, 0);
        var res = try std.ArrayList(Token).initCapacity(process_alloc, 0);
        var cur_fn_pos:struct {
            line:?usize = null,
            pos:?usize = null,
        } = .{};

        var depth:usize = 0;

        while (try itr.next()) |*token| {
            if (depth == 0) if (@constCast(token).is_ident(.@"fn")) {
                if (current_fn_mem) |_|
                    @panic("function mem not cleared");
                defer depth += 1;
                cur_fn_pos = .{
                    .line = token.line_number,
                    .pos = token.line_pos,
                };
                const fn_params = b: {
                    var blk_mem = try std.ArrayList(Param).initCapacity(process_alloc, 0);
                    defer {
                        _ = blk_mem.deinit(process_alloc);
                        _ = itr.back();
                    }
                    while (try itr.next() != null and !itr.cur.is_symbol(.@"{")) {
                        const param:Param = .{
                            .name = try finalized.alloc.dupe(u8, itr.cur.raw),
                            .type = itr.cur.type_info.value orelse .VOID,
                            .value = null,
                        };
                        try blk_mem.append(process_alloc, param);
                    }
                    break :b try blk_mem.toOwnedSlice(process_alloc);
                };
                
                current_fn_mem = .{
                    .name = try finalized.alloc.dupe(u8, token.raw),
                    .code = undefined,
                    .params = fn_params,
                    .return_template = globs.void_token,
                };
            } else {

                // TODO: other globals

                try res.append(
                    process_alloc,
                    try @constCast(token).own(finalized.alloc),
                );
            } else {
                if (mem.items.len > 0) {
                    defer _ = mem.clearAndFree(process_alloc);
                    if (current_fn_mem) |*fn_mem| {
                        defer current_fn_mem = null;
                        fn_mem.code = mem.items;
                        try finalized.global_namespace.put(
                            fn_mem.name.?,
                            .{ .function = current_fn_mem, },
                        );
                    }
                } else {
                    try mem.append(
                        process_alloc,
                        try @constCast(token).own(finalized.alloc)
                    );
                }
            }
        }
        
        finalized.tokens = res.items;

        return finalized;
    }
};

//pub fn dupe(alloc:std.mem.Allocator, in:[]Token) ![]Token {
//    var tokens = try std.ArrayList(Token).initCapacity(alloc, 0);
//    defer _ = tokens.deinit(alloc);
//    for (in) |token| try tokens.append(alloc, try @constCast(&token).own(alloc));
//    return try tokens.toOwnedSlice(alloc);
//}

pub fn free(alloc:std.mem.Allocator, tokens:[]Token) void {
    for (tokens) |t| alloc.free(t.raw);
}
