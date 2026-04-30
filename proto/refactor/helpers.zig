const std = @import("std");

pub fn is_num(str:[]u8) bool {
    return
        for (str) |b| {
            if (!std.ascii.isDigit(b)) break false;
        } else
            true;
}

//returns null if invalid (better for my usecase)
pub fn parse_bool(str:[]u8) ?bool {
    return
        (std.meta.stringToEnum(
            enum{ @"true", @"false" }, str
        ) orelse { return null; }) == .true;
}

//pub fn maybe_string(in:[]u8) bool {
//    if (in.len == 0) return false;
//    std.debug.print("|{s}|\n", .{in});
//    return in[0] == '"' and in[in.len - 1] == '"';
//}
