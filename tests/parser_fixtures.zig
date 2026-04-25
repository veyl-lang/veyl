const std = @import("std");
const veyl = @import("veyl");

test "parser golden: imports" {
    const source = @embedFile("fixtures/parser/imports.veyl");
    const expected = @embedFile("fixtures/parser/imports.ast");

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try veyl.lexer.lex(std.testing.allocator, 0, source, &diagnostics);
    defer tokens.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var interner = veyl.base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = try veyl.parser.parse(std.testing.allocator, 0, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    const actual = try veyl.parser.dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}
