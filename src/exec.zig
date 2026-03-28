const std = @import("std");
const globs = @import("globs.zig");
const tokenizer = @import("tokenizer.zig");

const stderr = globs.stderr;
const Token = tokenizer.Token;

pub const Exec = struct {
    in:[]Token,
    cur:Token,
    pos:?usize,
    arena:std.heap.ArenaAllocator,
    alloc:std.mem.Allocator,
    env:*const std.process.EnvMap,

    pub fn init(tokens: []Token, arena:*std.heap.ArenaAllocator) !Exec {
        const alloc = arena.*.allocator();
        const env = try std.process.getEnvMap(alloc);
        
        return .{
            .in = tokens,
            .pos = null,
            .cur = undefined,
            .arena = arena.*,
            .alloc = alloc,
            .env = &env,
        };
    }

    fn next(self:*Exec) ?Token {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.in.len <= self.pos.?)
            return null;
        self.cur = self.in[self.pos.?];
        return self.cur;
    }

    pub fn do(self:*Exec) !void {
        while (self.next()) |token| {
            switch (token.type) {
                .FN => try self.run(token, try self.get_args()),
                else => @panic(try std.fmt.allocPrint(
                    self.alloc, "UNKNOWN TOKEN ({t} |{s}|)", .{token.type, token.raw})
                ),
            }
        }
    }

    fn get_args(self:*Exec) ![]Token {
        var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        defer _ = mem.deinit(self.alloc);
        while (self.next() != null and self.cur.type != .EOX) {
            try mem.append(self.alloc, self.cur);
        }
        return try mem.toOwnedSlice(self.alloc);
    }
    
    fn string_args(self:*Exec, cmd:Token, args:[]Token) ![][]const u8 {
        var argv = try std.ArrayList([]const u8).initCapacity(self.alloc, 0);
        defer _ = argv.deinit(self.alloc);
        try argv.append(self.alloc, cmd.raw);
        for (args) |a|
            try argv.append(self.alloc, a.raw);
        return try argv.toOwnedSlice(self.alloc);

    }

    fn run(self:*Exec, cmd:Token, args:[]Token) !void {
        const argv = try self.string_args(cmd, args);
        return std.process.execv(self.alloc, argv);
    }
};
