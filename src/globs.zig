const std = @import("std");

const Keyword = @import("tokenizer.zig").Token.Keyword;

pub const stdout = &@constCast(&std.fs.File.stdout().writer(&.{})).interface;
pub const stderr = &@constCast(&std.fs.File.stderr().writer(&.{})).interface;

pub const dupe_keywords = struct {
    pub var @"else" = [_]Keyword{ .@"?!", .@"else" };
    pub var @"if" = [_]Keyword{ .@"?", .@"if" };
};
