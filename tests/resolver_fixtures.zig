const std = @import("std");
const veyl = @import("veyl");

test "resolver golden: top-level symbols" {
    const source = @embedFile("fixtures/resolve/top_level.veyl");
    const expected = @embedFile("fixtures/resolve/top_level.resolve");

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

    var hir = try veyl.hir.lowerAst(std.testing.allocator, &tree);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(std.testing.allocator, &hir, &interner, &diagnostics);
    defer resolved.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    const actual = try veyl.resolve.dumpResolvedModule(std.testing.allocator, &resolved, &interner);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "resolver diagnostic: duplicate top-level symbols" {
    const source = @embedFile("fixtures/resolve/duplicate_symbols.veyl");
    const expected = @embedFile("fixtures/resolve/duplicate_symbols.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("duplicate_symbols.veyl", source);

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try veyl.lexer.lex(std.testing.allocator, source_id, source, &diagnostics);
    defer tokens.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var interner = veyl.base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = try veyl.parser.parse(std.testing.allocator, source_id, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var hir = try veyl.hir.lowerAst(std.testing.allocator, &tree);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(std.testing.allocator, &hir, &interner, &diagnostics);
    defer resolved.deinit();
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "resolver golden: import bindings" {
    const source = @embedFile("fixtures/resolve/import_bindings.veyl");
    const expected = @embedFile("fixtures/resolve/import_bindings.resolve");

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

    var hir = try veyl.hir.lowerAst(std.testing.allocator, &tree);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(std.testing.allocator, &hir, &interner, &diagnostics);
    defer resolved.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    const actual = try veyl.resolve.dumpResolvedModule(std.testing.allocator, &resolved, &interner);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "resolver diagnostic: unresolved function name" {
    const source = @embedFile("fixtures/resolve/unresolved_name.veyl");
    const expected = @embedFile("fixtures/resolve/unresolved_name.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("unresolved_name.veyl", source);

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try veyl.lexer.lex(std.testing.allocator, source_id, source, &diagnostics);
    defer tokens.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var interner = veyl.base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = try veyl.parser.parse(std.testing.allocator, source_id, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var hir = try veyl.hir.lowerAst(std.testing.allocator, &tree);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(std.testing.allocator, &hir, &interner, &diagnostics);
    defer resolved.deinit();
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "resolver golden: pattern bindings" {
    const source = @embedFile("fixtures/resolve/pattern_bindings.veyl");
    const expected = @embedFile("fixtures/resolve/pattern_bindings.resolve");

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

    var hir = try veyl.hir.lowerAst(std.testing.allocator, &tree);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(std.testing.allocator, &hir, &interner, &diagnostics);
    defer resolved.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    const actual = try veyl.resolve.dumpResolvedModule(std.testing.allocator, &resolved, &interner);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
