const std = @import("std");
const globs = @import("globs.zig");
const tokenizer = @import("tokenizer.zig");

const stderr = globs.stderr;
const stdout = globs.stdout;
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
    fn peek(self:*Exec) ?Token {
        return if (self.in.len <= self.pos.? + 1) null else self.in[self.pos.?+1];
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
        defer {
            _ = mem.deinit(self.alloc);
        }
        loop: while (self.peek()) |tok| {
            _ = self.next();
            if (tok.type != .EOX) 
                try mem.append(self.alloc, tok)
            else
                break :loop;
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
        var child = std.process.Child{
            .allocator = self.alloc,
            .argv = argv,
            .stdout_behavior = .Inherit,
            .stderr_behavior = .Inherit,
            .stdin_behavior = .Inherit,
            .stdin = std.fs.File.stdin(),
            .stdout = std.fs.File.stdout(),
            .stderr = std.fs.File.stderr(),

            // TODO: this stuff
            .id = undefined,
            .thread_handle = undefined,
            .err_pipe = null,
            .term = null,
            .env_map = null,
            .uid = null,
            .cwd = null,
            .gid = null,
            .pgid = null,
            .expand_arg0 = .no_expand,
        };
        try child.spawn(); 
        // TODO: term code
        _ = try child.wait();
    }
};
