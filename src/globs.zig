const std = @import("std");

pub const stdout = &@constCast(&std.fs.File.stdout().writer(&.{})).interface;
pub const stderr = &@constCast(&std.fs.File.stderr().writer(&.{})).interface;
