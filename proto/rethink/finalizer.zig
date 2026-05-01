const std = @import("std");
const types = @import("types.zig");

pub const Finalizer = struct {
    pub fn init(_:std.mem.Allocator) !Finalizer {
        return .{};
    }

    pub fn recurse(
        self:*Finalizer,
        block:*types.Block,
        parent:?*types.Block
    ) !types.Block {
        var block_itr = block.namespace.iterator();
        while (block_itr.next()) |entry| {
            _ = switch (entry.value_ptr.*.type) {
                .block => |*blk| try self.recurse(blk, block),
                else => {},
            };
        }
        if (parent) |p| {
            var parent_itr = p.namespace.iterator();
            while (parent_itr.next()) |entry| {
                const name = @constCast(entry.key_ptr.*);
                const value = entry.value_ptr.*;
                try block.to_namespace(name, value);
            }
        }
        return block.*;
    }

    pub fn do(self:*Finalizer, block:*types.Block) !types.Block {
        return try self.recurse(block, null);
    }
};
