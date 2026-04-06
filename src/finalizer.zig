const std = @import("std");
const types = @import("types.zig");
const globs = @import("globs.zig");

const Token = types.Token;
const Param = Function.Param;
const Function = types.Function;
const Tokenized = types.Tokenized;

pub const Finalizer = struct {
    in:[]Token,
    pos:?usize,
    cur:Token,
    depth:usize = 0,
    
    alloc:std.mem.Allocator,

    mem:std.ArrayList(*Token),
    current_fn_mem:?Function,
    final_tokens:std.ArrayList(*Token),
    namespace:std.StringHashMap(Token),


    pub fn init(alloc:std.mem.Allocator) !Finalizer {
        var foo = Finalizer{
            .alloc = alloc,
            .namespace = undefined,
            .final_tokens = undefined,
            .mem = undefined,
            .pos = null,
            .cur = globs.void_token,
            .in = @constCast(&[_]Token{}),
            .current_fn_mem = null,
        };
        foo.namespace = std.StringHashMap(Token).init(foo.alloc);
        foo.final_tokens = try std.ArrayList(*Token).initCapacity(foo.alloc, 0);
        foo.mem = try std.ArrayList(*Token).initCapacity(foo.alloc, 0);
        return foo;
    }

    pub fn deinit(self:*Finalizer) void {
        self.namespace.deinit();

        for (self.final_tokens.items) |token|
            @constCast(token).free();
        self.final_tokens.deinit(self.alloc);

        for (self.mem.items) |*token|
            @constCast(token).free();
        self.mem.deinit(self.alloc);
    }

    fn next(self:*Finalizer) ?Token {
        self.pos = if (self.pos) |p| p + 1 else 0;
        if (self.in.len <= self.pos.?)
            return null;
        self.cur = self.in[self.pos.?];

        if (self.cur.is_oneof_symbols(&globs.symbol_sets.braces)) {
            self.depth =
                if (self.cur.is_symbol(.@"{"))
                    self.depth + 1
                else if (self.depth > 0)
                    self.depth - 1
                else
                    @panic("unexpected token: '}'");

            // NOTE: WHY MUST ZIG HAVE MORE THAN ONE NAMESPACE?
            // ([_]*const @TypeOf(std.ArrayList(*Token).append) {
            //     &self.mem.append,
            //     &self.final_tokens.append,
            // })[
            //     if (self.mem.items.len > 0) 0 else 1
            // ](
            //     &(self.cur.own(self.alloc) catch |e|
            //         @panic(@errorName(e)))
            // ) catch |e|
            //     @panic(@errorName(e));

            var const_crap_sucks = self.cur.own(self.alloc) catch |e| @panic(@errorName(e));
            (if (self.mem.items.len > 0)
                self.mem.append(self.alloc, &const_crap_sucks)
            else
                self.final_tokens.append(self.alloc, &const_crap_sucks)
            ) catch |e|
                @panic(@errorName(e));

            return self.next();
        }

        return self.cur;
    }

    fn back(self:*Finalizer) ?Token {
        self.pos =
            if (self.pos) |p|
                if (p > 0)
                    p - 1
                else
                    return null
            else
                0;
        if (self.pos.? < 1)
            return null;
        self.cur = self.in[self.pos.?];
        return self.cur;
    }

    fn peek(self:*Finalizer) Token {
        return
            if (self.pos) |p|
                if (p + 1 < self.in.len)
                    self.in[p + 1]
                else
                    globs.void_token
            else
                self.in[0];
    }

    fn previous(self:*Finalizer) Token {
        return
            if (self.pos) |p|
                if (p > 0)
                    self.in[p - 1]
                else
                    globs.void_token
            else
                self.in[0];
    }

    // TODO: type checking probably should be here

    pub fn do(self:*Finalizer, in:[]Token) !Tokenized {
        self.in = in;
        var cur_fn_line_num:?usize = null;
        var cur_fn_line_pos:?usize = null;
        while (self.next()) |*token| {
            @constCast(token).depth = self.depth;
            if (self.depth == 0) if (@constCast(token).is_ident_type(.@"fn")) {
                if (self.current_fn_mem) |_|
                    @panic("function mem not cleared"); 
                defer self.depth += 1;

                cur_fn_line_num = token.line_number;
                cur_fn_line_pos = token.line_pos;

                const fn_params = b: {
                    var mem = try std.ArrayList(Param).initCapacity(self.alloc, 0);
                    defer _ = mem.deinit(self.alloc);

                    defer _ = self.back();
                    while (self.next() != null and !@constCast(&self.previous()).is_symbol(.@"{")) {
                        const param:Param = .{
                            .name = try self.alloc.dupe(u8, self.cur.raw),
                            .type = self.cur.type_info.value orelse .VOID,
                            .value = null,
                        };
                        try mem.append(self.alloc, param);
                    }
                    break :b try mem.toOwnedSlice(self.alloc);
                };

                self.current_fn_mem = .{

                    .name = try self.alloc.dupe(u8, token.raw),
                    .code = undefined,
                    .params = fn_params,

                     // TODO: parse for return template
                    .return_template = @constCast(&globs.void_token),
                };

            } else {

                // TODO: other globals

                try self.final_tokens.append(
                    self.alloc,
                    @constCast(&(try @constCast(token).own(self.alloc)))
                );

            } else {
                if (self.mem.items.len > 0) {
                    defer _ = self.mem.clearAndFree(self.alloc);
                    if (self.current_fn_mem) |*mem| {
                        defer self.current_fn_mem = null;
                        mem.code = try self.mem.toOwnedSlice(self.alloc);
                        try self.namespace.put(
                            mem.name,
                            .{
                                .raw = mem.name,
                                .type = .FN,
                                .depth = self.depth,
                                .line_number = cur_fn_line_num.?,
                                .line_pos = cur_fn_line_pos.?,

                                .function = try @constCast(mem).own_and_free(self.alloc),

                                //being able to merge structs like sets in Nix would be great
                                .type_info = .{
                                    .value = mem.return_template.type_info.value,
                                    .thing = mem.return_template.type_info.thing,
                                    .ident = .@"fn",
                                },
                            }
                        );
                    }
                } else {
                    try self.mem.append(
                        self.alloc,
                        @constCast(&(try @constCast(token).own(self.alloc)))
                    );
                }
            }
        }

        var res = Tokenized{
            .tokens = undefined,
            .global_namespace = undefined,
            .alloc = self.alloc,
            .arena = undefined,
        };

        res.tokens = try self.final_tokens.toOwnedSlice(res.alloc);
        res.global_namespace = try self.namespace.cloneWithAllocator(res.alloc);

        return res;
    }
};
