const std = @import("std");
const globs = @import("globs.zig");
const tokenizer = @import("tokenizer.zig");
const evaluator = @import("evaluator.zig");
const types = @import("types.zig");

const dupes = globs.dupe_keywords;

const stderr = globs.stderr;
const stdout = globs.stdout;
const Token = tokenizer.Token;
const Keyword = Token.Keyword;
const conditional = evaluator.conditional;

const State = types.State;
const Tokenized = types.Tokenized;

pub const Exec = struct {
    in:[]Token,
    source:?[]u8,
    alloc:std.mem.Allocator,
    conditional_res:?bool,

    known_idents:std.StringHashMap(Token),
    state:State,

    pub fn init(tokens: Tokenized, source:?[]u8, owned_alloc:std.mem.Allocator) !Exec {
        //var arena = std.heap.ArenaAllocator.init(owned_alloc);//std.heap.page_allocator);
        //const alloc = arena.allocator();
        var foo =  Exec{
            .in = undefined,
            .source = source,
            .alloc = owned_alloc,
            .conditional_res = null,
            .state = tokens.base_state,
            .known_idents = undefined,
        };
        foo.in = tokens.tokens; //try tokenizer.dupe(foo.alloc, tokens.tokens);
        foo.known_idents = std.StringHashMap(Token).init(foo.alloc);
        return foo;
    }

    pub fn deinit(self:*Exec) void {
        while (@constCast(&self.known_idents.iterator()).next()) |ident| {
            self.alloc.free(ident.key_ptr.*);
            ident.value_ptr.free(self.alloc);
        }
        self.known_idents.deinit();
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

    pub fn do_block(self:*Exec, input:?[]Token, depth:usize) !void {

        const tokens = if (input) |in| in else self.in;
        var block = try Block.init(tokens, depth, self.alloc, self.known_idents);
        defer block.deinit();

        while (block.next()) |token| {
            switch (token.type) {
                .FN => switch (token.type_info.thing.?) {
                    .SHELL_CMD => {
                        const argv = try block.get_args();
                        defer {
                            tokenizer.free(self.alloc, argv); 
                            self.alloc.free(argv);
                        }
                        try self.run(token, argv, block);
                    },
                    else => std.debug.panic(
                        "TODO: FnType.{s}",
                        .{ @tagName(token.type_info.thing.?) }
                    )
                },
                .SYMBOL => {
                    switch (token.type_info.symbol.?) {
                        .@"{" => {
                            const code = try block.collect_depth(.@"{", .@"}");
                            try self.do_block(code, depth + 1);
                        },
                        else => try self.unexpected(token),
                    }
                },
                .KEYWORD => {
                    switch (token.type_info.keyword.?) {
                        .@"?", .@"if" => {
                            //skip .@"("
                            _ = block.next();
                            self.conditional_res = (try conditional.do(
                                self.alloc,
                                try block.collect(.@")")
                            )).value.bool;
                            defer self.conditional_res = null;

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
                                self.do_block(if_true, depth + 1)
                            else if (if_false) |toks|
                                self.do_block(toks, depth + 1);
                        },
                        else => std.debug.panic(
                            "TODO (keyword): {s}\n",
                            .{@tagName(token.type_info.keyword.?)}
                        ),
                    }
                },
                .IDENT => {
                    switch (token.type_info.ident.?) {
                        .@"set", .@"let" => {
                            try block.known_idents.put(token.raw, token);
                        },
                        else => std.debug.panic(
                            "TODO: exec switch block.next().?.type == "
                                ++ ".IDENT for IdentType of {s}",
                            .{ @tagName(token.type_info.ident.?) }
                        ),
                    }
                    try @constCast(&token).print();
                    try @constCast(&block.next().?).print();
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
        try self.do_block(null, 0);
    }

    pub fn do_then_deinit(self:*Exec) !void {
        try self.do();
        self.deinit();
    }
    
    fn string_args(self:*Exec, cmd:Token, args:[]Token, block:Block) ![][]const u8 {
        var argv = try std.ArrayList([]const u8).initCapacity(self.alloc, 0);
        defer {
            for (argv.items) |a| self.alloc.free(a);
            _ = argv.deinit(self.alloc);
        }
        try argv.append(self.alloc, try self.alloc.dupe(u8, cmd.raw));
        for (args) |*a| {
            if (a.type == .VALUE) {
                switch (a.type_info.value.?) {

                    .FLAG => {
                        try argv.append(self.alloc, try a.expand_flag(self.alloc));
                    },

                    else => {
                        try argv.append(self.alloc, try self.alloc.dupe(u8, a.raw));
                    },
                }
            } else if (a.type == .IDENT) {
                const og = block.known_idents.get(a.raw) orelse {
                    try self.unexpected(a.*);
                    unreachable;
                };
                try argv.append(self.alloc, og.value.string.?);
            } else
                std.debug.panic("TODO string_args(): {s}", .{@tagName(a.type)});
        }
        return try argv.toOwnedSlice(self.alloc);
    }

    fn run(self:*Exec, cmd:Token, args:[]Token, block:Block) !void {
        const argv = try self.string_args(cmd, args, block);
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
    depth:usize,

    known_idents:std.StringHashMap(Token),

    pub fn init(
        code:[]Token,
        parent_depth:usize,
        alloc:std.mem.Allocator,
        parent_idents:std.StringHashMap(Token),
    ) !Block {
        var block = Block{
            .code = code,
            .alloc = alloc,
            .depth = parent_depth + 1,
            .known_idents = undefined,
        };
        block.known_idents = try parent_idents.cloneWithAllocator(block.alloc);
        return block;
    }

    pub fn deinit(self:*Block) void {
        for (self.code) |*token|
            @constCast(token).free(self.alloc);
        var itr = self.known_idents.iterator();
        while (itr.next()) |ident| if (ident.value_ptr.*.depth == self.depth) {
            ident.value_ptr.free(self.alloc);
            self.alloc.free(ident.key_ptr.*);
        };
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
            return token.type_info.keyword.? == thing;
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
