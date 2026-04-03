const std = @import("std");
const globs = @import("globs.zig");
const tokenizer = @import("tokenizer.zig");
const evaluator = @import("evaluator.zig");

const stderr = globs.stderr;
const stdout = globs.stdout;
const Token = tokenizer.Token;
const conditional = evaluator.conditional;

pub const Exec = struct {
    in:[]Token,
    cur:Token,
    pos:?usize,
    alloc:std.mem.Allocator,
    conditional_res:?bool,

    pub fn init(tokens: []Token, owned_alloc:std.mem.Allocator) !Exec {
        //var arena = std.heap.ArenaAllocator.init(owned_alloc);//std.heap.page_allocator);
        //const alloc = arena.allocator();
        var foo =  Exec{
            .in = undefined,
            .pos = null,
            .cur = undefined,
            .alloc = owned_alloc,
            .conditional_res = null,
        };
        foo.in = try tokenizer.dupe(foo.alloc, tokens);
        return foo;
    }

    pub fn deinit(self:*Exec) void {
        //tokenizer.free(self.alloc, self.in);
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

    fn next_is_symbol(self:*Exec, symbol:Token.Symbol) bool {
        return if (self.peek()) |*n| @constCast(n).is_symbol(symbol) else false;
    }

    pub fn do(self:*Exec) !void {
        while (self.next()) |token| {
            switch (token.type) {
                .FN => switch (token.thing_type.?) {
                    .SHELL_CMD => {
                        const argv = try self.get_args();
                        defer {
                            tokenizer.free(self.alloc, argv); 
                            self.alloc.free(argv);
                        }
                        try self.run(token, argv);
                    },
                    else => std.debug.panic(
                        "TODO: FnType.{s}",
                        .{ @tagName(token.thing_type.?) }
                    )
                },
                .KEYWORD => {
                    switch (token.keyword_type.?) {
                        .@"?", .@"if" => {
                            //skip .@"("
                            _ = self.next();
                            self.conditional_res = (try conditional.do(
                                self.alloc,
                                try self.collect(.@")")
                            )).bool_value;
                            defer self.conditional_res = false;
                            const if_true = b: {
                                if (self.next_is_symbol(.@"{")) {
                                    _ = self.next();
                                    break :b try self.collect_depth(.@"{", .@"}");
                                } else
                                   @panic("TODO: if statement with no braces");
                            };
                            const if_false:?[]Token = b: {
                                if (self.next_is_keyword(.@"?!")) {
                                    _ = self.next();
                                    break :b try self.collect_depth(.@"{", .@"}");
                                } else
                                    break :b null;
                            };
                            if (self.conditional_res.?) {
                                if (if_false) |toks| for (toks) |*tok| {
                                    @constCast(tok).free(self.alloc);
                                };
                                for (if_true) |*tok| {
                                    try @constCast(tok).print();
                                }
                            } else {
                                for (if_true) |*tok| {
                                    @constCast(tok).free(self.alloc);
                                }
                                if (if_false) |toks| for (toks) |*tok| {
                                    try @constCast(tok).print();
                                };
                            }
                        },
                        else => std.debug.panic(
                            "TODO (keyword): {s}\n",
                            .{@tagName(token.keyword_type.?)}
                        ),
                    }
                },
                else => std.debug.panic("UNKNOWN TOKEN ({t} |{s}|)", .{token.type, token.raw}),
            }
        }
    }

    fn next_is_keyword(self:*Exec, thing:Token.Keyword) bool {
        if (self.peek()) |token| {
            if (token.type != .KEYWORD) return false;
            return token.keyword_type.? == thing;
        }
        return false;
    }

    fn collect(self:*Exec, thing:Token.Symbol) ![]Token {
        var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        defer {
            tokenizer.free(self.alloc, mem.items);
            _ = mem.deinit(self.alloc);
        }
        loop: while (self.peek()) |*devilish_const_token| {
            var token = @constCast(devilish_const_token);
            _ = self.next();
            if (!token.is_symbol(thing)) {
                try mem.append(self.alloc, token.*);
            } else
                break :loop;
        }
        return try mem.toOwnedSlice(self.alloc);
    }

    fn collect_depth(self:*Exec, start:Token.Symbol, end:Token.Symbol) ![]Token {
        var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        defer {
            tokenizer.free(self.alloc, mem.items);
            _ = mem.deinit(self.alloc);
        }
        var depth:usize = 1;
        loop: while (self.peek()) |*devilish_const_token| {
            var token = @constCast(devilish_const_token);
            _ = self.next();

            if (token.is_symbol(start))
                depth += 1
            else if (token.is_symbol(end))
                depth -= 1
            else
                try mem.append(self.alloc, token.*);

            if (depth == 0)
                break :loop;
        }
        return try mem.toOwnedSlice(self.alloc);
    }

    fn get_args(self:*Exec) ![]Token {
        return try self.collect(.@";");
        //var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        //defer {
        //    tokenizer.free(self.alloc, mem.items);
        //    _ = mem.deinit(self.alloc);
        //}
        //loop: while (self.peek()) |*devilish_const_token| {
        //    var token = @constCast(devilish_const_token);
        //    _ = self.next();
        //    if (!token.is_symbol(.@";")) {
        //        try mem.append(self.alloc, token.*);
        //    } else
        //        break :loop;
        //}
        //return try mem.toOwnedSlice(self.alloc);
    }
    
    fn string_args(self:*Exec, cmd:Token, args:[]Token) ![][]const u8 {
        var argv = try std.ArrayList([]const u8).initCapacity(self.alloc, 0);
        defer {
            for (argv.items) |a| self.alloc.free(a);
            _ = argv.deinit(self.alloc);
        }
        try argv.append(self.alloc, try self.alloc.dupe(u8, cmd.raw));
        for (args) |*a| {
                switch (a.value_type.?) {

                .FLAG => {
                    try argv.append(self.alloc, try a.expand_flag(self.alloc));
                },

                else => try argv.append(self.alloc, try self.alloc.dupe(u8, a.raw)),
            }
        }
        return try argv.toOwnedSlice(self.alloc);
    }

    fn run(self:*Exec, cmd:Token, args:[]Token) !void {
        const argv = try self.string_args(cmd, args);
        defer for (argv) |a| self.alloc.free(a);
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        var child = std.process.Child{
            .allocator = gpa.allocator(),
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
