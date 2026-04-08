const std = @import("std");
const globs = @import("globs.zig");
const hlp = @import("helpers.zig");

const print = hlp.print_or_panic;

const stdout = globs.stdout;
const stderr = globs.stderr;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const Tokenized = @import("types.zig").Tokenized;
const Function = @import("types.zig").Function;

pub const Error = error {
    IsNotFlag
};

pub fn unescape(alloc:std.mem.Allocator, in:[]u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer _ = out.deinit(alloc);
    for (in) |b| try out.appendSlice(alloc, switch (b) {
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
        '\x1b' => "\\e",
        '\x07' => "\\a",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\x0b' => "\\v",
        else => &[_]u8{b},
    });
    return try out.toOwnedSlice(alloc);
}

pub const strings = struct {
    fn invalid(
        opts:struct {
            direct:?[]u8 = null,
            line:?[]u8 = null,
            start:?[]u8 = null,
            end:?[]u8 = null,
            expected:?[]const u8 = null,
            problem:?[]const u8 = null,
        }
    ) void {
        print(.ERR, "invalid string:\n", .{});
        if (opts.direct) |direct|
            print(.ERR, "\t{s}\n", .{direct});
        if (opts.line) |line|
            print(.ERR, "\t{s}\n", .{line});
        if (opts.expected) |expected|
            print(.ERR, "\texpected {s}\n", .{expected});
        if (opts.problem) |problem|
            print(.ERR, "\t{s}\n", .{problem});
        std.process.exit(1);
    }
    pub fn hex(pos:*usize, in:[]u8) u8 {
        var i = pos.*; 
        if (in[i..].len < 3) strings.invalid(.{
            .expected = "hex",
            .problem = "hex not long enough (expected format: \\xXX)"
        });
        i += 1;
        const start = i;
        var v:u8 = 0;
        while (i < start + 3) : (i += 1) {
            v *= 16;
            v += switch (in[i]) {
                '0'...'9' => in[i] - '0',
                'a'...'f' => in[i] - 'a' + 10,
                'A'...'F' => in[i] - 'A' + 10,
                else => {
                    strings.invalid(.{
                        .expected = "hex",
                        .problem = b: {
                            //'allocPrint(...)'? Why would I allocate the string just to add one byte?
                            const first_half = "invalid character in escape: ";
                            var buf:[first_half.len + 1]u8 = undefined;
                            for (first_half, 0..) |b, j| buf[j] = b;
                            buf[buf.len - 1] = in[i];
                            break :b &buf;
                        },
                    });
                    unreachable;
                },
            };
        }
        return v;
    }
};
