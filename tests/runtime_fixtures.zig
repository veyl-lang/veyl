const std = @import("std");
const veyl = @import("veyl");

test "runtime: empty main returns unit" {
    const source = @embedFile("fixtures/runtime/empty_main.veyl");

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

    var bytecode = try veyl.bytecode.compileHir(std.testing.allocator, &hir);
    defer bytecode.deinit();

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value.unit, result);
}

test "runtime: bool main returns bool" {
    const source = @embedFile("fixtures/runtime/bool_main.veyl");

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

    var bytecode = try veyl.bytecode.compileHir(std.testing.allocator, &hir);
    defer bytecode.deinit();

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .bool = true }, result);
}
