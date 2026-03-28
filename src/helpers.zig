const std = @import("std");

pub fn is_num(b:u8) bool {
    return b >= '0' and b <= '9';
}
