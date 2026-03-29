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
    alloc:std.mem.Allocator,

    pub fn init(tokens: []Token, owned_alloc:std.mem.Allocator) !Exec {
        //var arena = std.heap.ArenaAllocator.init(owned_alloc);//std.heap.page_allocator);
        //const alloc = arena.allocator();
        return .{
            .in = tokens,
            .pos = null,
            .cur = undefined,
            .alloc = owned_alloc,
        };
    }

    pub fn deinit(self:*Exec) void {
        _ = self;
        //_ = self.arena.reset(.free_all);
        //self.arena.deinit();
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
                .FN => {
                    const argv = try self.get_args();
                    defer self.alloc.free(argv);
                    try self.run(token, argv);
                },
                else => @panic(try std.fmt.allocPrint(
                    self.alloc, "UNKNOWN TOKEN ({t} |{s}|)", .{token.type, token.raw})
                ),
            }
        }
    }

    fn get_args(self:*Exec) ![]Token {
        var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        defer {
            for (mem.items) |token| self.alloc.free(token.raw);
            _ = mem.deinit(self.alloc);
        }
        loop: while (self.peek()) |tok| {
            _ = self.next();
            if (tok.type != .EOX) {
                try @constCast(&tok).print();
                try mem.append(self.alloc, tok);
            } else
                break :loop;
        }
        return try mem.toOwnedSlice(self.alloc);
    }
    
    fn string_args(self:*Exec, cmd:Token, args:[]Token) ![][]const u8 {
        var argv = try std.ArrayList([]const u8).initCapacity(self.alloc, 0);
        defer {
            for (argv.items) |arg| self.alloc.free(arg);
            _ = argv.deinit(self.alloc);
        }
        try argv.append(self.alloc, cmd.raw);
        for (args) |a| switch (a.value_type.?) {

            .FLAG => {
                defer self.alloc.free(a.raw);
                const converted = if (a.raw.len > 1)
                    try std.fmt.allocPrint(self.alloc, "--{s}", .{ a.raw })
                else
                    try std.fmt.allocPrint(self.alloc, "-{s}", .{ a.raw });
                try argv.append(self.alloc, converted);
            },

            else => try argv.append(self.alloc, a.raw),
        };
        return try argv.toOwnedSlice(self.alloc);
    }

    fn run(self:*Exec, cmd:Token, args:[]Token) !void {
        const argv = try self.string_args(cmd, args);
        defer self.alloc.free(argv);
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
