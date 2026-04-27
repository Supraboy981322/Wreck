const std = @import("std");
const hlp = @import("helpers.zig");
const types = @import("types.zig");

const ByteItr = hlp.ByteItr;
const BasicTok = types.BasicTok;

pub fn to_tok_type(raw:[]u8) BasicTok.Type {
    if (raw.len == 0) @panic("empty token"); //fn to_tok_type(raw:[]u8) BasicTok.Type { ... }

    if (hlp.maybe_string(raw)) return .STRING;

    if (std.meta.stringToEnum(
        BasicTok.Symbols, raw
    )) |_|
        return .SYMBOL;

    if (std.meta.stringToEnum(
        BasicTok.KeyWords, raw
    )) |_|
        return .KEYWORD;

    return .IDENT;
}

pub const Tokenizer = struct {
    in:[]u8,
    itr:ByteItr,
    mem:std.ArrayList(u8),
    res:std.ArrayList(BasicTok),
    alloc:*std.mem.Allocator,

    string:u8 = 0,
    esc:bool = false,

    pub fn init(alloc:*std.mem.Allocator, in:[]u8) !Tokenizer {
        var tok_maker:Tokenizer = .{
            .mem = undefined,
            .res = undefined,
            .alloc = alloc,
            .in = in,
            .itr = ByteItr.init(in),
        };
        tok_maker.mem = try std.ArrayList(u8).initCapacity(tok_maker.alloc.*, 0);
        tok_maker.res = try std.ArrayList(BasicTok).initCapacity(tok_maker.alloc.*, 0);
        return tok_maker;
    }

    pub fn deinit(self:*Tokenizer) void {
        self.mem.deinit(self.alloc.*);
        for (self.res.items) |*tok|
            @constCast(tok).deinit();
        self.res.deinit(self.alloc.*);
    }

    pub fn re_init(self:*Tokenizer) !void {
        self.deinit();
        self.mem = try std.ArrayList(u8).initCapacity(self.alloc.*, 0);
        self.res = try std.ArrayList(BasicTok).initCapacity(self.alloc.*, 0);
    }

    pub fn do(self:*Tokenizer) ![]BasicTok {
        defer {
            self.re_init() catch unreachable; //likely OOM
        }

        loop: while (self.itr.next()) |b| {

            if (self.esc) {
                try self.mem.append(self.alloc.*, b);
                continue :loop;
            }

            if (self.string != 0) {
                try self.mem.append(self.alloc.*, b);
                if (b == self.string) {
                    self.string = 0;
                    try self.new_tok();
                }
                continue :loop;
            }

            switch (b) {

                '"', '\'' => {
                    try self.mem.append(self.alloc.*, b);
                    self.string = b;
                },

                '#' => if (self.itr.peek() == '(') {
                    self.itr.skipToWithDepth(')', '(');
                },

                '\\' => self.esc = !self.esc,

                ' ', '\r', '\t', '\n', '(', ')', '{', '}', ';' => {
                    if (self.can_ignore()) continue :loop;
                    const mem_was_empty = self.mem.items.len == 0;
                    try self.new_tok();
                    if (BasicTok.looks_like_symbol(@constCast(&[_]u8{b})) and !mem_was_empty) 
                        try self.new_tok();
                },
                else => {
                    try self.mem.append(self.alloc.*, b);
                }
            }
        }
        
        if (self.mem.items.len > 0) try self.new_tok();

        return self.res.toOwnedSlice(self.alloc.*);
    }

    pub fn can_ignore(self:*Tokenizer) bool {
        return self.mem.items.len == 0 and std.ascii.isWhitespace(self.itr.cur);
    }

    pub fn new_tok(self:*Tokenizer) !void {

        var raw =
            if (self.mem.items.len > 0)
                try self.mem.toOwnedSlice(self.alloc.*)
            else
                try self.alloc.dupe(u8, &[_]u8{self.itr.cur});

        const matched_type = to_tok_type(raw);
        try self.res.append(self.alloc.*, .{
            .type = matched_type,
            .raw = raw,
            .alloc = self.alloc,
        });

        var last_tok:*BasicTok = &self.res.items[self.res.items.len - 1];
        var tok_alloc = last_tok.alloc;

        switch (matched_type) {

            .STRING => {
                const cut = try tok_alloc.dupe(u8, raw[1..raw.len-1]);
                self.alloc.free(raw);
                last_tok.raw = cut;
            },

            .KEYWORD => {
                last_tok.keyword = std.meta.stringToEnum(
                    BasicTok.KeyWords, last_tok.raw
                ) orelse unreachable;
            },

            .SYMBOL => {
                last_tok.symbol = std.meta.stringToEnum(
                    BasicTok.Symbols, last_tok.raw
                ) orelse unreachable;
            },

            else => {},
        }
    }
};
