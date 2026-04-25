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

    var bytecode = try veyl.bytecode.compileHir(std.testing.allocator, &hir, source);
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

    var bytecode = try veyl.bytecode.compileHir(std.testing.allocator, &hir, source);
    defer bytecode.deinit();

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .bool = true }, result);
}

test "runtime: int arithmetic returns int" {
    const source = @embedFile("fixtures/runtime/int_arithmetic.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 7 }, result);
}

test "runtime: local int returns int" {
    const source = @embedFile("fixtures/runtime/local_int.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 42 }, result);
}

test "runtime: user function call returns int" {
    const source = @embedFile("fixtures/runtime/function_call.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 42 }, result);
}

test "runtime: if expression returns selected branch" {
    const source = @embedFile("fixtures/runtime/if_expr.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 42 }, result);
}

test "runtime: local assignment updates local" {
    const source = @embedFile("fixtures/runtime/local_assignment.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 42 }, result);
}

test "runtime: while loop updates local" {
    const source = @embedFile("fixtures/runtime/while_loop.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 42 }, result);
}

test "runtime: break and continue control loop" {
    const source = @embedFile("fixtures/runtime/break_continue.veyl");

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

    var vm = veyl.runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();

    const result = try vm.runFirst(&bytecode);
    try std.testing.expectEqual(veyl.runtime.Value{ .int = 3 }, result);
}
