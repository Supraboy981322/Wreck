const std = @import("std");

pub const DepthTrackerError = error {NotTracking} || std.mem.Allocator.Error;

pub fn DepthTracker(comptime T:type) type {
    return struct {
        stuff:std.AutoHashMap(T, usize),
        alloc:std.mem.Allocator,
        arena:*std.heap.ArenaAllocator,
        const Self = @This();
        pub fn init() !Self {
            var arena:std.heap.ArenaAllocator = .init(std.heap.page_allocator);
            return .{
                .alloc = arena.allocator(),
                .arena = &arena,
                .stuff = .init(arena.allocator()),
            };
        }
        pub fn deinit(self:*Self) void {
            self.stuff.deinit();
            _ = self.arena.deinit();
        }

        pub fn bump(self:*Self, what:T) DepthTrackerError!void {
            const thing = self.stuff.getPtr(what) orelse {
                try self.stuff.put(what, 0);
                return;
            };
            thing.* += 1;
        }

        pub fn knock(self:*Self, what:T) DepthTrackerError!void {
            const thing = self.stuff.getPtr(what) orelse {
                return error.NotTracking;
            };
            if (thing.* > 1)
                thing.* -= 1
            else
                if (!self.stuff.remove(what)) unreachable;
        }
    };
}
