const std = @import("std");
const globs = @import("globs.zig");
const tokenizer = @import("tokenizer.zig");
const evaluator = @import("evaluator.zig");

const dupes = globs.dupe_keywords;

const stderr = globs.stderr;
const stdout = globs.stdout;
const Token = tokenizer.Token;
const Keyword = Token.Keyword;
const conditional = evaluator.conditional;

pub const Exec = struct {
    in:[]Token,
    source:?[]u8,
    alloc:std.mem.Allocator,
    conditional_res:?bool,

    pub fn init(tokens: []Token, source:?[]u8, owned_alloc:std.mem.Allocator) !Exec {
        //var arena = std.heap.ArenaAllocator.init(owned_alloc);//std.heap.page_allocator);
        //const alloc = arena.allocator();
        var foo =  Exec{
            .in = undefined,
            .source = source,
            .alloc = owned_alloc,
            .conditional_res = null,
        };
        foo.in = try tokenizer.dupe(foo.alloc, tokens);
        return foo;
    }

    pub fn deinit(self:*Exec) void {
        _ = self;
        //tokenizer.free(self.alloc, self.in);
    }
    
    fn unexpected(self:*Exec, token:Token) !void {
        try stderr.print("\n\n\x1b[3;31munexpected token:\x1b[0m\n", .{});
        try @constCast(&token).print();
        if (self.source) |src| {
            var buf = try std.ArrayList(u8).initCapacity(self.alloc, 0);
            defer _ = buf.deinit(self.alloc);

            var l:usize = 1;
            const offset = for (src, 0..) |b, i| {
                if (b == '\n') l += 1;
                if (l == token.line_number) break i+1;
            } else {
                std.debug.panic(
                    "failed to find token in source code: |{s}| (line {d}, col {d})",
                    .{token.raw, token.line_number, token.line_pos}
                );
                unreachable;
            };

            const end = for (src[offset..], offset..) |b, i| {
                if (b == '\n') break i;
            } else {
                std.debug.panic(
                    "failed to find token in source code: |{s}| (line {d}, col {d})",
                    .{token.raw, token.line_number, token.line_pos}
                );
                unreachable;
            };

            const the_line = src[offset..end];
            const before_the_thing = the_line[0..(token.line_pos - token.raw.len) - 1];
            const the_thing = the_line[token.line_pos - token.raw.len - 1..token.line_pos - 1];
            const after_the_thing = the_line[token.line_pos - 1..];

            try buf.print(
                self.alloc,
                "\n\x1b[38;2;100;100;150m{s}\x1b[31m{s}\x1b[0m{s}\n",
                .{before_the_thing, the_thing, after_the_thing}
            );
            for (before_the_thing) |_|
                try buf.print(self.alloc, " ", .{});

            for (the_thing) |_|
                try buf.print(self.alloc, "\x1b[33m^\x1b[0m", .{});

            try stderr.print("{s}\n", .{buf.items});
        } else
            try stderr.print("\nsource not available\n", .{});
        std.process.exit(1);
    }

    pub fn do_block(self:*Exec, input:?[]Token) !void {

        const tokens = if (input) |in| in else self.in;
        var block = Block.init(tokens, self.alloc);
        defer block.deinit();

        while (block.next()) |token| {
            switch (token.type) {
                .FN => switch (token.thing_type.?) {
                    .SHELL_CMD => {
                        const argv = try block.get_args();
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
                .SYMBOL => {
                    switch (token.symbol_type.?) {
                        .@"{" => {
                            const code = try block.collect_depth(.@"{", .@"}");
                            try self.do_block(code);
                        },
                        else => try self.unexpected(token),
                    }
                },
                .KEYWORD => {
                    switch (token.keyword_type.?) {
                        .@"?", .@"if" => {
                            //skip .@"("
                            _ = block.next();
                            self.conditional_res = (try conditional.do(
                                self.alloc,
                                try block.collect(.@")")
                            )).bool_value;
                            defer self.conditional_res = false;

                            const if_true = b: {
                                if (block.next_is_symbol(.@"{")) {
                                    _ = block.next();
                                    break :b try block.collect_depth(.@"{", .@"}");
                                } else
                                   @panic("TODO: if statement with no braces");
                            };
                            defer for (if_true) |*tok| {
                                @constCast(tok).free(self.alloc);
                            };

                            const if_false:?[]Token = b: {
                                if (block.next_is_oneof_keywords(&dupes.@"else")) {
                                    block.skipN(2);
                                    break :b try block.collect_depth(.@"{", .@"}");
                                } else
                                    break :b null;
                            };
                            defer if (if_false) |toks| for (toks) |*tok| {
                                @constCast(tok).free(self.alloc);
                            };

                            try if (self.conditional_res.?)
                                self.do_block(if_true)
                            else if (if_false) |toks|
                                self.do_block(toks);
                        },
                        else => std.debug.panic(
                            "TODO (keyword): {s}\n",
                            .{@tagName(token.keyword_type.?)}
                        ),
                    }
                },
                else => {
                    try if (block.back()) |*t| @constCast(t).print();
                    for (0..2) |_| if (block.next()) |*t| try @constCast(t).print();
                    std.debug.panic("UNKNOWN TOKEN ({t} |{s}|)", .{token.type, token.raw});
                },
            }
        }
    }

    pub fn do(self:*Exec) !void {
        try self.do_block(null);
    }

    pub fn do_then_deinit(self:*Exec) !void {
        try self.do();
        self.deinit();
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

//stripped down state tracker for the current block without modifying overall state
pub const Block = struct {
    code:[]Token,
    pos:?usize = null,
    cur:Token = undefined,
    alloc:std.mem.Allocator,

    pub fn init(code:[]Token, alloc:std.mem.Allocator) Block {
        return .{
            .code = code,
            .alloc = alloc
        };
    }

    pub fn deinit(self:*Block) void {
        for (self.code) |*token| @constCast(token).free(self.alloc);
    }

    pub fn next(self:*Block) ?Token {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.code.len <= self.pos.?) return null;
        self.cur = self.code[self.pos.?];
        return self.cur;
    }

    pub fn back(self:*Block) ?Token {
        self.pos = if (self.pos) |p| p - 1 else 0;
        if (self.pos.? < 1) return null;
        self.cur = self.code[self.pos.?];
        return self.cur;
    }

    pub fn peek(self:*Block) ?Token {
        const p = if (self.pos) |p| p + 1 else 0;
        if (self.code.len <= p) return null;
        return self.code[p];
    }

    pub fn skipN(self:*Block, n:usize) void {
        for (0..n) |_| _ = self.next(); 
    }

    fn next_is_keyword(self:*Block, thing:Token.Keyword) bool {
        if (self.peek()) |token| {
            if (token.type != .KEYWORD) return false;
            return token.keyword_type.? == thing;
        }
        return false;
    }

    fn next_is_symbol(self:*Block, symbol:Token.Symbol) bool {
        return if (self.peek()) |*n| @constCast(n).is_symbol(symbol) else false;
    }
    
    fn next_is_oneof_keywords(self:*Block, keywords:[]Token.Keyword) bool {
        return for (keywords) |keyword| {
            if (self.next_is_keyword(keyword)) break true;
        } else false;
    }

    fn cur_is_oneof_keywords(self:*Block, keywords:[]Token.Keyword) bool {
        return for (keywords) |keyword| {
            if (self.cur.is_keyword(keyword)) break true;
        } else false;
    }

    fn collect(self:*Block, thing:Token.Symbol) ![]Token {
        var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        defer {
            tokenizer.free(self.alloc, mem.items);
            _ = mem.deinit(self.alloc);
        }
        loop: while (self.next()) |*devilish_const_token| {
            var token = @constCast(devilish_const_token);
            if (!token.is_symbol(thing)) {
                try mem.append(self.alloc, token.*);
            } else
                break :loop;
        }
        return try mem.toOwnedSlice(self.alloc);
    }

    fn collect_depth(self:*Block, start:Token.Symbol, end:Token.Symbol) ![]Token {
        var mem = try std.ArrayList(Token).initCapacity(self.alloc, 0);
        defer {
            tokenizer.free(self.alloc, mem.items);
            _ = mem.deinit(self.alloc);
        }
        var depth:usize = 1;
        loop: while (self.next()) |*devilish_const_token| {
            var token = @constCast(devilish_const_token);

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

    fn get_args(self:*Block) ![]Token {
        return try self.collect(.@";");
    }
};
