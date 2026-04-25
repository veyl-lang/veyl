const std = @import("std");
const veyl = @import("veyl");

test "bytecode golden: simple function" {
    const source = @embedFile("fixtures/bytecode/simple.veyl");
    const expected = @embedFile("fixtures/bytecode/simple.bytecode");

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

    var bytecode = try veyl.bytecode.compileHir(std.testing.allocator, &hir, source);
    defer bytecode.deinit();

    const actual = try veyl.bytecode.dumpBytecode(std.testing.allocator, &bytecode, &interner);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "bytecode golden: binary expressions" {
    const source = @embedFile("fixtures/bytecode/binary.veyl");
    const expected = @embedFile("fixtures/bytecode/binary.bytecode");

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

    var bytecode = try veyl.bytecode.compileHir(std.testing.allocator, &hir, source);
    defer bytecode.deinit();

    const actual = try veyl.bytecode.dumpBytecode(std.testing.allocator, &bytecode, &interner);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
