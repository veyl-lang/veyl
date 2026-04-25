const std = @import("std");

pub const Range = struct {
    start: u32,
    len: u32,

    pub fn init(start: u32, len: u32) Range {
        return .{ .start = start, .len = len };
    }

    pub fn end(self: Range) u32 {
        return self.start + self.len;
    }
};

test "range end is exclusive" {
    const range = Range.init(2, 3);

    try std.testing.expectEqual(@as(u32, 5), range.end());
}
