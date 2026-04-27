const std = @import("std");

pub fn GenericItr(comptime T:type, in:[]T) type {
    return struct {
        in:[]T = in,
        cur:T = undefined,
        pos:?usize = null,

        pub fn next(self:*@This()) ?T {
            self.pos = if (self.pos) |p| p + 1 else 0;
            if (self.pos.? >= self.in.len)
                return null; 
            self.cur = self.in[self.pos.?];
            return self.cur;
        }

        pub fn peek(self:*@This()) ?T {
            const pos = if (self.pos) |p| p else 0;
            if (pos + 1 >= self.in.len)
                return null;
            return self.in[pos + 1];
        }

        pub fn skip(self:*@This()) void {
            _ = self.next();
        }

        pub fn skipN(self:*@This(), n:usize) void {
            for (0..n) |_| self.skip();
        }

        pub fn back(self:*@This()) ?T {
            for ([_]bool{
                self.pos == null,
                self.pos.? == 0,
            }) |check|
                if (check) return null;
            self.pos = self.pos.? - 1;
            self.cur = self.in[self.pos.?];
            return self.cur;
        }
    };
}

pub const ByteItr = struct {
    in:[]u8,
    cur:u8,
    pos:?usize,

    pub fn init(in:[]u8) ByteItr {
        return .{
            .in = in,
            .cur = 0,
            .pos = null,
        };
    }

    pub fn next(self:*ByteItr) ?u8 {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.pos.? >= self.in.len)
            return null; 
        self.cur = self.in[self.pos.?];
        return self.cur;
    }

    pub fn peek(self:*ByteItr) u8 {
        const pos = if (self.pos) |p| p else 0;
        if (pos + 1 >= self.in.len)
            return 0;
        return self.in[pos + 1];
    }

    pub fn seekTo(self:*ByteItr, alloc:std.mem.Allocator, thing:u8) []u8 {
        const buf = alloc.alloc(u8, self.in.len - self.pos);
        defer alloc.free(buf);
        var i = 0;
        while (self.next()) |b| {
            defer i += 1;
            if (b == thing) return alloc.dupe(u8, buf[0..i]);
            buf[i] = b;
        }
        return buf[0..i];
    }
    
    pub fn skip(self:*ByteItr) void {
        _ = self.next();
    }

    pub fn skipN(self:*ByteItr, n:usize) void {
        for (0..n) |_| self.skip();
    }

    pub fn back(self:*ByteItr) ?u8 {
        for ([_]bool{
            self.pos == null,
            self.pos.? == 0,
        }) |check|
            if (check) return null;
        self.pos = self.pos.? - 1;
        self.cur = self.in[self.pos.?];
        return self.cur;
    }

    pub fn skipToWithDepth(self:*ByteItr, close:u8, open:u8) void {
        var depth:usize = 0;
        while (self.next()) |b| {
            if (b == open)
                depth += 1
            else if (b == close) 
                depth -= 1;
            if (depth == 0) return; 
        }
    }
};

pub fn maybe_string(in:[]u8) bool {
    if (in.len == 0) return false;
    std.debug.print("|{s}|\n", .{in});
    return in[0] == '"' and in[in.len - 1] == '"';
}
