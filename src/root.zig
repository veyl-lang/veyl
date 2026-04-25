pub const version = "0.0.1";

test "version is available" {
    const std = @import("std");

    try std.testing.expectEqualStrings("0.0.1", version);
}
