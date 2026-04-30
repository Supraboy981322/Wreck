const std = @import("std");
const hlp = @import("helpers.zig");
const types = @import("types.zig");

const Token = types.Token;

pub const Tokenizer = struct {
    io:std.Io,
    alloc:std.mem.Allocator,
    mem:std.ArrayList(u8) = .empty,
    res:std.ArrayList(Token) = .empty,
    esc:bool = false,
    reader:?std.Io.Reader = null,
    string:?u8 = null,

    pub fn init(io:std.Io, alloc:std.mem.Allocator) Tokenizer {
        return .{
            .io = io,
            .alloc = alloc,
        };
    }

    pub fn init_with_source(io:std.Io, alloc:std.mem.Allocator, src:[]u8) Tokenizer {
        var res:Tokenizer = .{
            .io = io,
            .alloc = alloc,
        };
        res.load_source(src);
        return res;
    }

    pub fn deinit(self:*Tokenizer) void {
        self.reset();
        self.res.deinit(self.alloc);
        self.mem.deinit(self.alloc);
    }

    pub fn reset(self:*Tokenizer) void {
        self.res.clearAndFree(self.alloc);
        self.mem.clearAndFree(self.alloc);
        self.reader = null;
        self.string = null;
    }

    pub fn next(self:*Tokenizer) !?u8 {
        const b = try self.peek();
        if (b) |_| self.reader.?.toss(1);
        return b;
    }

    pub fn peek(self:*Tokenizer) !?u8 {
        try self.ready_test();
        return
            self.reader.?.peekByte() catch |e|
                if (e != error.EndOfStream)
                    e
                else
                    null;
    }

    pub fn load_source(self:*Tokenizer, src:[]u8) void {
        self.reader = .fixed(src);
    }

    pub fn ready_test(self:*Tokenizer) !void {
        if (self.reader == null) return error.NoSource; //must call load_source() first
    }

    pub fn builtin(self:*Tokenizer) !void {
        if (self.mem.items.len > 0) unreachable;
        while (try self.next()) |b| {
            if (b == '(') break;
            try self.mem.append(self.alloc, b);
        }
        //comments are parsed like a builtin
        if (self.mem.items.len > 0) {
            self.mem.clearAndFree(self.alloc);
            var depth:usize = 0;
            while (try self.next()) |b| {
                if (b == '(')
                    depth += 1
                else if (b == ')')
                    depth -= 1;
                if (depth == 0) break;
            }
            return;
        }

        try self.res.append(self.alloc, try .mk_builtin(self.alloc, self.mem.items));
        self.mem.clearAndFree(self.alloc);
    }

    pub fn do(self:*Tokenizer) !std.ArrayList(Token) {
        try self.ready_test();
        while (try self.next()) |b| {
            if (self.esc) {
                self.esc = false;
                try self.mem.append(self.alloc, b);
                continue;
            }

            if (b == '\\') { self.esc = true; continue; }

            if (self.string) |s| {
                if (s != b)
                    try self.mem.append(self.alloc, b)
                else
                    self.string = null;
                continue;
            }
            switch (b) {
                '#' => try self.builtin(),
                '"', '\'' => self.string = b,
                else => try self.mem.append(self.alloc, b),
            }
        }
        return try self.res.clone(self.alloc);
    }
};
