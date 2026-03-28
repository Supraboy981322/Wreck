const std = @import("std");
const globs = @import("globs.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Exec = @import("exec.zig").Exec;

const stdout = globs.stdout;

pub fn main() !void {
    const code = \\echo("foo" "bar");
    ;
    
    try stdout.print("#+BEGIN_SRC\n{s}\n#+END_SRC\n\noutput:\n", .{code});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer {
        _ = arena.reset(.free_all);
        _ = arena.deinit();
    }

    var tokenizer = try Tokenizer.init(code, &arena);
    const tokens = try tokenizer.do();

    var exec = try Exec.init(tokens, &arena);
    try exec.do();
}
