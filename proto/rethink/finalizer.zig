const std = @import("std");
const types = @import("types.zig");

pub const Finalizer = struct {
    pub fn init(_:std.mem.Allocator) !Finalizer {
        return .{};
    }

    pub fn do(_:*Finalizer, block:types.Block) !types.Block {
        //var itr = block.namespace.iterator();
        //while (itr.next()) |name_entry| {
        //    if (name_entry.value_ptr.*.type == .block) {
        //        var entry_block = name_entry.type.block;
        //        try entry_block.to_namespace(
        //            @constCast(name_entry.key_ptr.*),
        //            name_entry.value_ptr.*
        //        );
        //    }
        //}
        return block;
    }
};
