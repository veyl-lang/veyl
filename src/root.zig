pub const base = @import("base.zig");
pub const diag = @import("diag.zig");
pub const host = @import("host.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");

pub const version = "0.0.1";

test {
    _ = base;
    _ = diag;
    _ = host;
    _ = lexer;
    _ = parser;
}

test "version is available" {
    const std = @import("std");

    try std.testing.expectEqualStrings("0.0.1", version);
}
