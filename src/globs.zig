const std = @import("std");

const Keyword = @import("tokenizer.zig").Token.Keyword;

pub const stdout = &@constCast(&std.fs.File.stdout().writer(&.{})).interface;
pub const stderr = &@constCast(&std.fs.File.stderr().writer(&.{})).interface;

pub const dupe_keywords = struct {
    pub var @"else" = [_]Keyword{ .@"?!", .@"else" };
    pub var @"if" = [_]Keyword{ .@"?", .@"if" };
};

pub const keyword_sets_following_type = struct {
    pub var ident = [_]Keyword{ .@"fn", .@"set", .@"let" };
    pub var immediately = [_]Keyword{ .@"return" };
};

//when the stupid scoped allocators have a bug where a seg-fault only occurs if value isn't used in IO operation
pub fn discard(thing:anytype) void {
    var wr = &@constCast(&std.Io.Writer.Discarding.init(&.{})).writer;
    wr.print("{any}", .{thing}) catch {};
}
