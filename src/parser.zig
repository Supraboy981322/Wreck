const std = @import("std");
const Token = @import("tokenizer.zig").Token;

pub const Error = error {
    IsNotFlag
};

pub const Transpiler = struct {
    in:[]Token,
    alloc:std.mem.Allocator,
    pos:?usize,
    cur:Token,
    mem:std.ArrayList(u8),

    pub fn init(alloc:std.mem.Allocator, tokens:[]Token) !Transpiler {
        return .{
            .in = tokens,
            .pos = null,
            .cur = undefined,
            .alloc = alloc,
            .mem = try std.ArrayList(u8).initCapacity(alloc, 0),
        };
    }

    fn next(self:*Transpiler) ?Token {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.in.len <= self.pos.?) return null;
        self.cur = self.in[self.pos.?];
        return self.cur;
    }

    fn back(self:*Transpiler) ?Token {
        if (self.pos) |p| {
            if (p <= 0) return null;
            self.pos.? -= 1;
            self.cur = self.in[self.pos.?];
            return self.cur;
        } else
            return null;
    }

    pub fn to_shell(self:*Transpiler) ![]u8 {
        defer _ = self.mem.clearAndFree(self.alloc);
        while (self.next()) |token| {
            switch (token.type) {
                .EOX => try self.mem.append(self.alloc, '\n'),
                .FN => {
                    try self.mem.appendSlice(self.alloc, token.raw);
                    try self.expand_args();
                },
                else => @panic(token.raw),
            }
        }
        return self.mem.toOwnedSlice(self.alloc);
    }

    fn expand_args(self:*Transpiler) !void {
        defer _ = self.back();
        while (self.next()) |token| {
            try @import("globs.zig").stdout.print("{s}\n", .{token.raw});
            try  self.mem.append(self.alloc, ' ');
            if (token.type != .VALUE) return;
            switch (token.value_type.?) {
                // TODO: string escaping and single quotes
                .STRING => try self.mem.print(self.alloc, "\"{s}\"", .{token.raw}),

                .NUM => try self.mem.appendSlice(self.alloc, token.raw),

                .FLAG => try self.mem.appendSlice(self.alloc, try expand_flag(self.alloc, token)),

                else => @panic(@tagName(token.value_type.?)),
            }
        }
    }

    fn expand_flags(self:*Transpiler) !void {
        defer _ = self.back();
        while (self.next()) |token| {
            try @import("globs.zig").stdout.print("{s}\n", .{token.raw});
            if (!@constCast(&token).is_flag()) return;
            try self.mem.appendSlice(self.alloc, try expand_flag(self.alloc, token));
        }
    }
};


pub fn expand_flag(alloc:std.mem.Allocator, a:Token) ![]u8 {
    if (!@constCast(&a).is_flag()) return Error.IsNotFlag;
    if (a.raw.len > 1) return try std.fmt.allocPrint(alloc, "--{s}", .{a.raw});
    return try std.fmt.allocPrint(alloc, "-{s}", .{a.raw});
}
