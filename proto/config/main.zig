const std = @import("std");

const stdout = &@constCast(&std.fs.File.stdout().writer(&.{})).interface;

pub fn main() !void {
    const src = @embedFile("test.wreck_conf");
    try stdout.print(
        \\#+BEGIN_SRC
        \\{s}
        \\#+END_SRC
        \\
    , .{ src });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var tokenizer = try Tokenizer.init(alloc, @constCast(src));
    defer tokenizer.deinit();
    
    for (try tokenizer.do()) |token| {
        try stdout.print("({s}) |{s}|\n", .{@tagName(token.type), token.literal});
    }
}

const Token = struct {
    literal:[]u8,
    type: TokenType,

    // TODO: move to make more generic
    pub const TokenType = enum {
        INVALID,
        FLAG,
        STRING,
        NUMBER,
        OPEN_OBJ,
        CLOSE_OBJ,
    };

    pub fn init(literal:[]u8, token_type:@This().TokenType) Token {
        return .{
            .literal = literal,
            .type = token_type,
        };
    }

    pub fn deinit(self:*Token, alloc:std.mem.Allocator) void {
        alloc.free(self.literal);
    }
};

const Tokenizer = struct {
    mem:std.ArrayList(u8),
    cur:u8 = 0,
    res:std.ArrayList(Token),
    alloc:std.mem.Allocator,
    in:[]u8,
    pos:?usize = null,
    cur_type:Token.TokenType = .INVALID,
    str_type:u8 = 0,
    is_symbol:bool = false,

    pub fn init(alloc:std.mem.Allocator, in:[]u8) !Tokenizer {
        return .{
            .alloc = alloc,
            .mem = try std.ArrayList(u8).initCapacity(alloc, 0),
            .res = try std.ArrayList(Token).initCapacity(alloc, 0),
            .in = in,
        };
    }
    pub fn deinit(self:*Tokenizer) void {
        for (self.res.items) |*token| token.deinit(self.alloc);
        self.res.deinit(self.alloc);
        self.mem.deinit(self.alloc);
    }

    pub fn next(self:*Tokenizer) ?u8 {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.in.len <= self.pos.?) return null;
        self.cur = self.in[self.pos.?];
        return self.cur;
    }
    pub fn back(self:*Tokenizer) u8 {
        if (self.pos) |p| {
            if (p < 1) return 0;
            self.pos = p - 1;
            self.cur = self.in[self.pos.?];
            return self.cur;
        } else
            return 0;
    }
    pub fn peek(self:*Tokenizer) u8 {
        const pos = if (self.pos) |p| p + 1 else 1;
        if (pos >= self.in.len) return 0;
        return self.in[pos];
    }
    
    pub fn add_token(self:*Tokenizer) !void {
        defer self.mem.clearAndFree(self.alloc);
        if (self.mem.items.len > 0 or self.is_symbol) {
            if (self.cur_type == .INVALID) {
                self.cur_type = for (self.mem.items) |b| {
                    if (!std.ascii.isDigit(b)) break .INVALID;
                } else .NUMBER;
            }

            try self.res.append(
                self.alloc,
                Token.init(
                    try self.mem.toOwnedSlice(self.alloc),
                    self.cur_type
                ),
            );
        }
    }

    pub fn do(self:*Tokenizer) ![]Token {
        loop: while (self.next()) |b| {
            if (self.cur_type == .STRING) {
                if (b == self.str_type) {
                    try self.add_token();
                    self.cur_type = .INVALID;
                } else
                    try self.mem.append(self.alloc, b);
                continue :loop;
            }
            if (std.ascii.isWhitespace(b)) {
                try self.add_token();
                continue :loop;
            }
            switch (b) {
                '[' => {
                    try self.add_token();
                    if (self.peek() == '[') {
                        self.cur_type = .FLAG;
                        _ = self.next();
                    } else if (self.cur_type != .INVALID) {
                        // TODO: lists
                        std.debug.panic(
                            "unexpected byte (TODO: lists): {c} ({s})\n",
                            .{b, @tagName(self.cur_type)}
                        );
                    }
                },
                ']' => {
                    try self.add_token();
                    self.cur_type = .INVALID;
                    if (self.peek() == ']') _ = self.next();
                },
                '{', '}' => {
                    self.is_symbol = true;
                    self.cur_type = if (b == '{') .OPEN_OBJ else .CLOSE_OBJ;
                    try self.add_token();
                    self.is_symbol = false;
                },
                '"', '\'' => {
                    try self.add_token();
                    self.cur_type = .STRING;
                    self.str_type = b;
                },
                '#' => {
                    if (self.peek() == '(') {
                        var depth:usize = 0;
                        while (self.next()) |c| {
                            if (c == '(') depth += 1; 
                            if (c == ')') depth -= 1;
                            if (depth == 0 and c == ')') break;
                        }
                    } else
                        @panic("builtins are not supported in config form (but comments are)");
                },
                else => try self.mem.append(self.alloc, b),
            }
        }
        try self.add_token();
        return self.res.items;
    }
};
