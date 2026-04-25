pub const base = @import("base.zig");
pub const diag = @import("diag.zig");
pub const lexer = @import("lexer.zig");

pub const version = "0.0.1";

test {
    _ = base;
    _ = diag;
    _ = lexer;
}

test "version is available" {
    const std = @import("std");

    try std.testing.expectEqualStrings("0.0.1", version);
}
