const std = @import("std");
const Token = @import("tokenizer.zig").Token;

pub const Error = error {
    IsNotFlag
};

pub const Transpiler = struct {
    in:[]Token,
    alloc:std.mem.Allocator,
    arena:std.heap.ArenaAllocator,
    pos:?usize,
    cur:Token,
    mem:std.ArrayList(u8),
    returning_alloc:std.mem.Allocator,

    pub fn init(owned_alloc:std.mem.Allocator, tokens:[]Token) !Transpiler {
        var arena = std.heap.ArenaAllocator.init(owned_alloc);
        const alloc = arena.allocator(); 
        return .{
            .in = tokens,
            .pos = null,
            .cur = undefined,
            .arena = arena,
            .alloc = alloc,
            .returning_alloc = owned_alloc,
            .mem = try std.ArrayList(u8).initCapacity(alloc, 0),
        };
    }

    pub fn deinit(self:*Transpiler) void {
        _ = self.mem.deinit(self.alloc); 
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
        defer _ = self.arena.reset(.free_all);
        while (self.next()) |*token| {
            switch (token.type) {
                .EOX => try self.mem.append(self.alloc, '\n'),
                .FN => {
                    try self.mem.appendSlice(self.alloc, token.raw);
                    try self.expand_args();
                },
                else => @panic(token.raw),
            }
        }
        return try self.returning_alloc.dupe(u8, try self.mem.toOwnedSlice(self.alloc));
    }

    fn expand_args(self:*Transpiler) !void {
        defer _ = self.back();
        while (self.next()) |token| {
            try  self.mem.append(self.alloc, ' ');
            if (token.type != .VALUE) return;
            switch (token.value_type.?) {
                // TODO: string escaping and single quotes
                .STRING => try self.mem.print(
                    self.alloc, "\"{s}\"", .{try unescape(self.alloc, token.raw)}
                ),

                .NUM => try self.mem.appendSlice(self.alloc, token.raw),

                .FLAG => {
                    const expanded = try expand_flag(self.alloc, token);
                    try self.mem.appendSlice(self.alloc, expanded);
                    self.alloc.free(expanded);
                },

                else => @panic(@tagName(token.value_type.?)),
            }
        }
    }

    fn expand_flags(self:*Transpiler) !void {
        defer _ = self.back();
        while (self.next()) |token| {
            if (!@constCast(&token).is_flag()) return;
            
            const expanded = try expand_flag(self.alloc, token);
            try self.mem.appendSlice(self.alloc, expanded);
            self.alloc.free(expanded);
        }
    }
};


pub fn expand_flag(alloc:std.mem.Allocator, a:Token) ![]u8 {
    if (!@constCast(&a).is_flag()) return Error.IsNotFlag;
    if (a.raw.len > 1) return try std.fmt.allocPrint(alloc, "--{s}", .{a.raw});
    return try std.fmt.allocPrint(alloc, "-{s}", .{a.raw});
}

pub fn unescape(alloc:std.mem.Allocator, in:[]u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = out.deinit(alloc);
    for (in) |b| try out.appendSlice(alloc, switch (b) {
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
        '\x1b' => "\\e",
        '\x07' => "\\a",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\x0b' => "\\v",
        else => &[_]u8{b},
    });
    return try out.toOwnedSlice(alloc);
}
