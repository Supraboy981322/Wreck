const std = @import("std");
const globs = @import("globs.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Exec = @import("exec.zig").Exec;
const parser = @import("parser.zig");

const stdout = globs.stdout;
const stderr = globs.stderr;

pub fn main() !void {
    const code =
    \\printf("foo '%d' \" %c\n" 1 '"');
    \\curl([[ f silent S L ]] "https://archive.google/heart");
    ;
    
    try stdout.print("#+BEGIN_SRC\n{s}\n#+END_SRC\n", .{code});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer {
        _ = arena.reset(.free_all);
        _ = arena.deinit();
    }
    const allocator = arena.allocator();

    var tokenizer = try Tokenizer.init(code, allocator);//alloc); // TODO: cleanup allocation
    defer tokenizer.deinit();
    const tokens = try tokenizer.do();
    defer tokenizer.free(tokens);

    try stderr.print("\ntokenized:\n", .{});
    try tokenizer.print(tokens);

    try stdout.print("\ntranspiled:\n", .{});
    var transpiler = try parser.Transpiler.init(allocator, tokens);
    defer transpiler.deinit();
    const shell = try transpiler.to_shell();
    defer arena.allocator().free(shell);
    try stdout.print("{s}\n", .{shell});

    try stderr.print("\noutput:\n", .{});
    var exec = try Exec.init(tokens, allocator);//alloc); // TODO: cleanup allocation
    defer exec.deinit();
    exec.do() catch |e| {
        try stderr.print("{t}\n", .{e});
    };
}
