pub const base = @import("base.zig");
pub const bytecode = @import("bytecode.zig");
pub const diag = @import("diag.zig");
pub const fmt = @import("fmt.zig");
pub const hir = @import("hir.zig");
pub const host = @import("host.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const resolve = @import("resolve.zig");
pub const runtime = @import("runtime.zig");
pub const typeck = @import("typeck.zig");

pub const version = "0.0.1";

test {
    _ = base;
    _ = bytecode;
    _ = diag;
    _ = fmt;
    _ = hir;
    _ = host;
    _ = lexer;
    _ = parser;
    _ = resolve;
    _ = runtime;
    _ = typeck;
}

test "version is available" {
    const std = @import("std");

    try std.testing.expectEqualStrings("0.0.1", version);
}
