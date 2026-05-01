const std = @import("std");
const types = @import("types.zig");
const hlp = @import("helpers.zig");

const Token = types.Token;
const Variable = types.Variable;
const Arg = types.Arg;
const Block = types.Block;

pub const TokenizerError = error {
} || std.mem.Allocator.Error;

pub const Tokenizer = struct {
    mem:std.ArrayList(u8) = .empty,
    alloc:std.mem.Allocator,
    reader:?*std.Io.Reader = null,
    arena:std.heap.ArenaAllocator,

    pub fn init(alloc:std.mem.Allocator) !Tokenizer {
        const foo:Tokenizer = .{
            .alloc = alloc,
            .reader = null,
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
        return foo;
    }

    pub fn deinit(self:*Tokenizer) void {
        self.mem.deinit(self.alloc);
        _ = self.arena.deinit();
    }

    pub fn recurse(self:*Tokenizer, name:?[]u8) !Block {
        var tokenizer:Tokenizer = try .init(self.alloc);
        return try tokenizer.do(self.reader.?, name);
    }

    pub fn do(self:*Tokenizer, reader:*std.Io.Reader, name:?[]u8) TokenizerError!Block {
        // TODO:  helpers to dupe result so arena can be reset
        // defer self.arena.reset(.free_all);
        const alloc = self.arena.allocator();
        if (self.reader == null) self.reader = reader;

        var mem:std.ArrayList(u8) = .empty;
        defer mem.deinit(alloc);

        var res:Block = .init(self.alloc, name, null, true);

        var function:?Block = null;
        _ = &function; // NOTE: may need this

        var depth_tracker:hlp.DepthTracker(u8) = try .init();
        _ = &depth_tracker; // NOTE: may need this

        var esc:bool = false;
        var label_name:?[]u8 = null;
        var string:?u8 = null;

        while (reader.takeByte() catch null) |b| {
            if (esc) {
                esc = false;
                try mem.append(alloc, b);
                continue;
            }
            if (string) |s| {
                if (b == s) {
                    string = null;
                    const str:Token = .{ .type = .{ .string = try mem.toOwnedSlice(alloc) } };
                    try res.code.append(self.alloc, str);
                } else
                    try mem.append(alloc, b);
                continue;
            }
            if (std.ascii.isWhitespace(b) or Token.byte_looks_like_symbol(b)) {
                if (mem.items.len > 0) {
                    const raw = try mem.toOwnedSlice(alloc);
                    const new_token = Token.make(raw).?;
                    if (new_token.type == .keyword) if (new_token.type.keyword == .@"fn") {

                        if (Token.byte_to_symbol(b)) |_|
                            try res.code.append(
                                self.alloc, Token.make(@constCast(&[_]u8{b})).?
                            );

                        const fn_name = try reader.takeDelimiter('(') orelse {
                            return error.EndOfFile;
                        };

                        var param_names:std.ArrayList([]u8) = .empty;
                        defer param_names.deinit(alloc);

                        var param_types:std.ArrayList(Token.Types) = .empty;
                        defer param_types.deinit(alloc);

                        var c = while (reader.takeByte() catch null) |c| {
                            if (std.ascii.isWhitespace(c) or c == ')') {
                                const param_type:Token.Types = Token.TokenType.make(
                                    mem.items
                                ) orelse return error.InvalidParameterType;
                                mem.clearAndFree(alloc);
                                try param_types.append(alloc, param_type);
                                if (param_types.items.len > param_names.items.len) {
                                    return error.MissingParameterName;
                                } else if (param_types.items.len < param_names.items.len) {
                                    return error.MissingParameterType;
                                }
                            }
                            switch (c) {
                                ')' => break try reader.peekByte(),
                                '(' => return error.MissplacedSymbol,
                                ':' => {
                                    try param_names.append(alloc,
                                        try mem.toOwnedSlice(self.alloc)
                                    );
                                },
                                else => {
                                    try mem.append(alloc, c);
                                },
                            }
                        } else
                            return error.EndOfFile;
                        var params:std.ArrayList(types.Param) = .empty;
                        defer params.deinit(alloc);
                        for (param_names.items, 0..) |p_name, i| {
                            try params.append(alloc, .{
                                .name = p_name,
                                .type = param_types.items[i],
                            });
                        }
                        while (std.ascii.isWhitespace(c)) c = try reader.takeByte();
                        var block:Block = try self.recurse(fn_name);
                        block.params = try params.toOwnedSlice(self.alloc);
                        const as_token:Token = .{
                            .type = .{ .block = block }
                        };
                        try res.to_namespace(fn_name, as_token);
                        continue;
                    };
                    try res.code.append(self.alloc, new_token);
                }

                if (Token.byte_looks_like_symbol(b))
                    try res.code.append(self.alloc, Token.make(@constCast(&[_]u8{b})).?);

                continue;
            }
            switch (b) {
                '"' => string = b,
                '\\' => esc = true,
                '{' => {
                    defer {
                        if (label_name) |_| label_name = null;
                    }
                    var block = try self.recurse(label_name);
                    block.is_label = label_name != null;
                    const as_token:Token = .{
                        .type = .{ .block = block }
                    };
                    if (label_name) |label|
                        try res.to_namespace(label, as_token)
                    else
                        try res.code.append(self.alloc, as_token);
                },
                '}' => return res,
                ':' => {
                    if (label_name) |_|
                        @panic("missplaced colon");
                    label_name = try mem.toOwnedSlice(self.alloc);
                },
                else => try mem.append(alloc, b),
            }
        }
        return res;
    }
};
