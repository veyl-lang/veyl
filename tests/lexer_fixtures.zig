const std = @import("std");
const veyl = @import("veyl");

test "lexer golden: core declarations" {
    const source = @embedFile("fixtures/lexer/core_decls.veyl");
    const expected = @embedFile("fixtures/lexer/core_decls.tokens");

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try veyl.lexer.lex(std.testing.allocator, 0, source, &diagnostics);
    defer tokens.deinit();

    try std.testing.expect(!diagnostics.hasErrors());

    const actual = try veyl.lexer.dumpTokens(std.testing.allocator, source, tokens.tokens.items);
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}
