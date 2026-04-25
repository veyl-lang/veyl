const std = @import("std");
const veyl = @import("veyl");

pub fn main() !void {
    std.debug.print("Veyl {s}\n", .{veyl.version});
}
