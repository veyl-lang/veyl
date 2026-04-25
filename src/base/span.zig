const std = @import("std");
const ids = @import("ids.zig");

pub const Span = struct {
    source: ids.SourceId,
    start: u32,
    len: u32,

    pub fn init(source: ids.SourceId, start: u32, len: u32) Span {
        return .{
            .source = source,
            .start = start,
            .len = len,
        };
    }

    pub fn end(self: Span) u32 {
        return self.start + self.len;
    }

    pub fn join(first: Span, second: Span) Span {
        std.debug.assert(first.source == second.source);
        const start = @min(first.start, second.start);
        const end_pos = @max(first.end(), second.end());
        return .{
            .source = first.source,
            .start = start,
            .len = end_pos - start,
        };
    }
};

pub const LineCol = struct {
    line: u32,
    column: u32,
};

test "span end and join use byte offsets" {
    const left = Span.init(0, 2, 3);
    const right = Span.init(0, 8, 2);
    const joined = Span.join(left, right);

    try std.testing.expectEqual(@as(u32, 5), left.end());
    try std.testing.expectEqual(@as(u32, 2), joined.start);
    try std.testing.expectEqual(@as(u32, 8), joined.len);
}
