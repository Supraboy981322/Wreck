const std = @import("std");
const types = @import("types.zig");
const hlp = @import("helpers.zig");

const Token = types.Token;
const Variable = types.Variable;
const Arg = types.Arg;
const Block = types.Block;

pub const TokenizerError = error {
    EndOfFile,
    BadTypeHint,
    MissplacedSymbol,
    InvalidParameterType,
    MissingParameterName,
    MissingParameterType,
    Overflow,
    InvalidCharacter,
    InvalidVariableName,
    InvalidListFlag,
} || std.mem.Allocator.Error
  || std.Io.Reader.DelimiterError
  || hlp.DepthTrackerError
;

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

    pub fn do(
        self:*Tokenizer,
        reader:*std.Io.Reader,
        name:?[]u8
    ) TokenizerError!Block {

        // TODO:  helpers to dupe result so arena can be reset
        // defer self.arena.reset(.free_all);
        const alloc = self.arena.allocator();
        if (self.reader == null) self.reader = reader;

        var mem:std.ArrayList(u8) = .empty;
        defer mem.deinit(alloc);

        var res:Block = .init(self.alloc, name, null, true);

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

            // TODO: refactor this for string interpolation
            if (string) |s| {
                if (b == s) {
                    string = null;
                    const str:Token = .{
                        .type = .{ .string = try mem.toOwnedSlice(alloc) }
                    };
                    try res.code.append(self.alloc, str);
                } else
                    try mem.append(alloc, b);
                continue;
            }

            if (std.ascii.isWhitespace(b) or Token.byte_looks_like_symbol(b)) {
                const info = try self.whitespace(alloc, reader, &res, &mem, b);
                if (info.skip) continue;
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
                        return error.MissplacedSymbol; //colon
                    label_name = try mem.toOwnedSlice(self.alloc);
                },
                else => try mem.append(alloc, b),
            }
        }
        return res;
    }

    pub fn collect_fn(
        self:*Tokenizer,
        alloc:std.mem.Allocator,
        reader:*std.Io.Reader,
        mem:*std.ArrayList(u8),
    ) !struct{ name:[]u8, token:Token } {
        const fn_name = try reader.takeDelimiter('(') orelse {
            return error.EndOfFile;
        };

        var params:std.ArrayList(types.Param) = .empty;
        defer params.deinit(alloc);

        var c = while (reader.takeByte() catch null) |c| {
            if (std.ascii.isWhitespace(c) or c == ')') {
                var type_hint_string:?[]u8 = null;
                if (std.mem.count(u8, mem.items, "[") > 0) blk: {
                    _, const dumb_const_type_hint_string = std.mem.cut(
                        u8, mem.items, "["
                    ) orelse break :blk;
                    type_hint_string = @constCast(dumb_const_type_hint_string);
                    type_hint_string = type_hint_string.?[0..type_hint_string.?.len-1];
                }
                const param_type:Token.Types = Token.TokenType.make(
                    if (type_hint_string) |hint|
                        mem.items[0..mem.items.len-hint.len-2]
                    else
                        mem.items
                ) orelse
                    return error.InvalidParameterType;
                const type_hint:?Token.TypeHint = blk: {
                    if (type_hint_string) |hint_raw| {
                        switch (param_type) {
                            .list => break :blk .{
                                .list = std.meta.stringToEnum(
                                    Token.Types, hint_raw
                                ) orelse
                                    return error.BadTypeHint,
                            },
                            else => return error.BadTypeHint,
                        }
                    } else
                        break :blk null;
                };
                mem.clearAndFree(alloc);

                var skeleton = params.pop() orelse return error.MissingParameterName;
                if (skeleton.type != .void)
                    return error.MissingParameterName;

                skeleton.type_hint = type_hint;
                skeleton.type = param_type;

                try params.append(alloc, skeleton);
            }
            switch (c) {
                ')' => break try reader.peekByte(),
                '(' => return error.MissplacedSymbol,
                ':' => {
                    try params.append(alloc,
                        .skeleton(try mem.toOwnedSlice(self.alloc))
                    );
                },
                else => {
                    try mem.append(alloc, c);
                },
            }
        } else
            return error.EndOfFile;
        while (std.ascii.isWhitespace(c)) c = try reader.takeByte();
        var block:Block = try self.recurse(fn_name);
        block.params = try params.toOwnedSlice(self.alloc);
        return .{
            .name = fn_name,
            .token = .{ .type = .{ .block = block } }
        };
    }

    pub fn whitespace(
        self:*Tokenizer,
        alloc:std.mem.Allocator,
        reader:*std.Io.Reader,
        res:*Block,
        mem:*std.ArrayList(u8),
        b:u8
    ) !struct{
        skip:bool = true,
    } {
        if (mem.items.len > 0) {
            const raw = try mem.toOwnedSlice(alloc);
            const new_token = (try Token.make(raw)).?;
            if (new_token.type == .keyword) if (new_token.type.keyword == .@"fn") {

                if (Token.byte_to_symbol(b)) |_|
                    try res.code.append(
                        self.alloc, (try Token.make_from_byte(b)).?
                    );

                const function = try self.collect_fn(alloc, reader, mem);
                try res.to_namespace(function.name, function.token);

                return .{};
            };
            try res.code.append(self.alloc, new_token);
        }

        if (Token.byte_looks_like_symbol(b))
            try res.code.append(self.alloc, (try Token.make_from_byte(b)).?);

        return .{};
    }
};
