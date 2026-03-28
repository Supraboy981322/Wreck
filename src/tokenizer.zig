const std = @import("std");
const globs = @import("globs.zig");

const stdout = globs.stdout;
const stderr = globs.stderr;

pub const Token = struct {
    raw: []u8,
    type: @This().Type,
    value_type: ?@This().ValueType,

    pub const Type = enum {
        INVALID,
        FN,
        VALUE,
        EOX,
    };
    pub const ValueType = enum {
        UNKNOWN,
        NUM,
        STRING,
    };
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
    arena:std.heap.ArenaAllocator,

    pub fn init(in:[]const u8, arena:*std.heap.ArenaAllocator) !Tokenizer {
        const alloc = arena.*.allocator();
        return .{
            .input = in,
            .pos = null,
            .expected_type = .INVALID,
            .parsing_as = null,
            .cur = 0,
            .mem = try std.ArrayList(u8).initCapacity(alloc, 0),
            .res = try std.ArrayList(Token).initCapacity(alloc, 0),
            .arena = arena.*,
            .alloc = alloc,
        };
    }
    pub fn deinit(self:*Tokenizer) !void {
        _ = self.mem.clearAndFree(self.alloc); 
        for (self.res.items) |token|
            self.alloc.free(token.raw);
        _ = self.res.clearAndFree(self.alloc); 
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
        const raw = try self.dump_mem();
        if (raw.len < 1) {
            try stderr.print("unexpected token (mem empty): {c}\n", .{self.cur});
            std.process.exit(1);
        }
        return .{
            .raw  = raw,
            .type = expecting,
            .value_type = parsing,
        };
    }

    pub fn do(self:*Tokenizer) ![]Token {
        while (self.next()) |b| {
            switch (b) {
                '(' => {
                    try self.res.append(self.alloc, try self.new_token(.FN, null));
                    if (!try self.get_args()) {
                        try stderr.print("failed to get args", .{});
                        std.process.exit(1);
                    }
                },
                ';' => {
                    if (self.mem.items.len > 0) {
                        try stderr.print(
                            "unexpected token (mem not empty |{s}|): {c}\n",
                            .{self.mem.items, self.cur}
                        );
                        std.process.exit(1);
                    }
                    try self.res.append(self.alloc, .{
                        .raw = try self.alloc.dupe(u8, ";"),
                        .type = .EOX,
                        .value_type = null,
                    });
                },
                else => {
                    try self.mem.append(self.alloc, b);
                },
            }
        }
        return self.res.items;
    }

    fn next(self:*Tokenizer) ?u8 {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.pos.? >= self.input.len)
            return null;
        self.cur = self.input[self.pos.?];
        return self.cur;
    }

    fn peek(self:*Tokenizer) u8 {
        if (self.pos.?+1 >= self.input.len)
            return 0;
        return self.input[self.pos.?+1];
    }

    fn get_args(self:*Tokenizer) !bool {
        if (self.mem.items.len > 0) {
            try stderr.print("error attempting to parse args: (mem not empty)", .{});
            std.process.exit(1);
        }
        while (self.next() != null and self.cur != ')') {
            switch (self.cur) {
                ' ' => if (self.parsing_as.? == .STRING) {
                    try self.res.append(self.alloc, try self.new_token(.VALUE, self.parsing_as));
                },
                '"' => {
                    if (self.parsing_as) |t| {
                        if (t == .STRING) if (self.peek() == ')') {
                            self.parsing_as = null;
                            try self.res.append(
                                self.alloc, try self.new_token(.VALUE, .STRING)
                            );
                        } else {} else {
                            try stderr.print(
                                "unexpected '\"' while parsing args (expected {?t})",
                                .{ self.parsing_as }
                            );
                            std.process.exit(1);
                        }
                    } else
                        self.parsing_as = .STRING;
                },
                else => try self.mem.append(self.alloc, self.cur),
            }
        }
        if (self.next()) |_| {
            self.pos.? -= 1;
            self.cur = self.input[self.pos.?];
            return true;
        } else if (self.cur != ')') {
            return false;
        } else {
            return true;
        }
    }
};
