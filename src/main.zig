const std = @import("std");
const globs = @import("globs.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Exec = @import("exec.zig").Exec;
const parser = @import("parser.zig");

const stdout = globs.stdout;
const stderr = globs.stderr;

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const code:[]u8 = b: {
        var args = std.process.args();
        defer args.deinit();
        _ = args.skip();

        if (args.next()) |a| break :b try std.fs.cwd().readFileAlloc(
            alloc, a, std.math.maxInt(usize)
        ) else {
            try stderr.print("not enough args, need a file to run\n", .{});
            std.process.exit(1);
        }
    };
    defer alloc.free(code);
    
    try stdout.print("#+BEGIN_SRC\n{s}\n#+END_SRC\n", .{code});

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

    try stderr.print("\noutput:\n", .{});
    var exec = try Exec.init(tokens, allocator);//alloc); // TODO: cleanup allocation
    defer exec.deinit();
    exec.do() catch |e| {
        try stderr.print("{t}\n", .{e});
    };
}
