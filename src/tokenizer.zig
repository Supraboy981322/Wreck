const std = @import("std");
const globs = @import("globs.zig");
const hlp = @import("helpers.zig");
const parser = @import("parser.zig");

const stdout = globs.stdout;
const stderr = globs.stderr;

pub const Token = struct {
    raw: []u8,
    type: @This().Type,
    value_type: ?@This().ValueType,
    fn_type:?@This().FnType,

    pub const Type = enum {
        INVALID,
        FN,
        VALUE,
        EOX,
    };
    pub const ValueType = enum {
        UNKNOWN,
        VOID,
        NUM,
        FLAG,
        STRING,
        COMMENT,
    };
    pub const FnType = enum {
        SHELL_CMD,
        BUILTIN,
        LOCAL,
    };

    pub fn print(self:*Token) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer _ = arena.deinit();
        try stdout.print(
            "\x1b[0;33mraw\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}} "
                ++ "\x1b[0;34mtype\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}} "
                ++ "\x1b[0;35mvalue_type\x1b[1;37m{{\x1b[0m{s}\x1b[1;37m}}\x1b[0m\n",
            .{
                try parser.unescape(arena.allocator(), self.raw),
                @tagName(self.type),
                @tagName(if (self.value_type) |t| t else .VOID),
            }
        );
    }

    pub fn is_flag(self:*Token) bool {
        if (self.type != .VALUE) return false;
        return self.value_type.? == .FLAG;
    }

    pub fn own(self:*Token, alloc:std.mem.Allocator) !Token {
        return .{
            .raw = try alloc.dupe(u8, self.raw),
            .type = self.type,
            .value_type = self.value_type,
            .fn_type = self.fn_type,
        };
    }
};

// TODO: no printing, just return error
pub const Error = error {
    NAN,
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
    escaping:bool,
    comment_depth:usize,
    is_start_of_thing:bool,
    fn_type:?Token.FnType,

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
            .fn_type = null,
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
        if (raw.len < 1) {
            try stderr.print(
                "unexpected token (mem empty from {s}): |{c}|\n",
                .{if (parsing) |as| @tagName(as) else "NOTHING", self.cur}
            );
            std.process.exit(1);
        }
        return .{
            .raw  = raw,
            .type = expecting,
            .value_type = parsing,
            .fn_type = self.fn_type,
        };
    }

    fn new_symbol_token(
        self:*Tokenizer,
        comptime literal:[]const u8,
        token_type:Token.Type,
    ) Token {
        _ = self;
        return .{
            .raw = @constCast(literal),
            .type = token_type,
            .value_type = null,
            .fn_type = null,
        };
    }

    pub fn do(self:*Tokenizer) ![]Token {
        loop: while (self.next()) |b| {
            if (std.ascii.isWhitespace(b)) continue :loop;

            switch (b) {
                '(' => {
                    const func = try self.new_token(.FN, null);
                    try self.res.append(self.alloc, func);
                    if (!try self.get_args()) {
                        try stderr.print("failed to get args\n", .{});
                        std.process.exit(1);
                    }
                },
                ';' => {
                    defer self.is_start_of_thing = true;

                    if (self.mem.items.len > 0) {
                        try stderr.print(
                            "unexpected token (mem not empty |{s}| from {s}): {c}\n",
                            .{
                                self.mem.items,
                                if (self.parsing_as) |as| @tagName(as) else "NOTHING",
                                self.cur
                            }
                        );
                        std.process.exit(1);
                    }
                    try self.res.append(self.alloc, self.new_symbol_token(";", .EOX));
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
            self.fn_type = switch (self.cur) {
                else => null,
            };
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
                        try stderr.print(
                            "unexpected '[' while parsing args (expected {?t})\n",
                            .{ self.parsing_as }
                        );
                        std.process.exit(1);
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

        while (self.comment_depth > 0 and self.next() != null) {
            if (self.cur == '(')
                self.comment_depth += 1
            else if (self.cur == ')')
                self.comment_depth -= 1;
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
