const std = @import("std");
const veyl = @import("veyl");

test "parser diagnostic: unexpected top-level token" {
    const source = @embedFile("fixtures/diagnostics/parser_unexpected_token.veyl");
    const expected = @embedFile("fixtures/diagnostics/parser_unexpected_token.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("parser_unexpected_token.veyl", source);

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try veyl.lexer.lex(std.testing.allocator, source_id, source, &diagnostics);
    defer tokens.deinit();

    var interner = veyl.base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = try veyl.parser.parse(std.testing.allocator, source_id, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();

    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}
