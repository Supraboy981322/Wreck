const std = @import("std");
const globs = @import("globs.zig");
const Token = @import("types.zig").Token;

pub fn is_num(b:u8) bool {
    return b >= '0' and b <= '9';
}

pub fn print_or_panic(comptime where:enum { OUT, ERR }, comptime fmt:[]const u8, stuff:anytype) void {
    const place = switch (where) {
        .OUT => globs.stdout,
        .ERR => globs.stderr,
    };
    place.print(fmt, stuff) catch std.debug.panic(fmt, stuff);
}

pub const TokenIterator = struct {
    in:[]Token,
    cur:Token = undefined,
    pos:?usize = null,
    opts:Opts,
    
    pub const FnHook = *const fn(Token) anyerror!void;
    
    pub const Opts = struct {
        use_void:bool = true,
        hook_on_next:?FnHook = null,
    };

    pub fn init(in:[]Token, opts:Opts) TokenIterator {
        return .{
            .in = in,
            .opts = opts,
        };
    }

    pub fn can_seek(self:*TokenIterator, direction:enum{ NEXT, BACK }) bool {
        return
            for ([_]bool{

                if (direction == .BACK)
                    self.pos == null
                else
                    false,

                if (direction == .BACK)
                    self.pos.? < 1
                else
                    self.pos.? >= self.in.len,

            }) |cannot| {
                if (cannot) break false;
            } else
                true;

    }

    pub fn next(self:*TokenIterator) !?Token {

        self.pos = if (self.pos) |p| p + 1 else 0;

        if (!self.can_seek(.NEXT)) return null;

        self.cur = self.in[self.pos.?];
        if (self.opts.hook_on_next) |f| try f(self.cur);

        return self.cur;
    }

    pub fn void_or_null(self:*TokenIterator) ?Token {
        return if (self.opts.use_void)
            globs.void_token
        else
            null;
    }

    pub fn back(self:*TokenIterator) ?Token {
        if (!self.can_seek(.BACK))
            return self.void_or_null();

        if (self.pos.? > 0) self.pos.? -= 1;

        self.cur = self.in[self.pos.?];
        return self.cur;
    }

    pub fn previous(self:*TokenIterator) ?Token {
        if (!self.can_seek(.PREVIOUS))
            return self.void_or_null();
        return self.in[self.pos.? - 1];
    }
};
