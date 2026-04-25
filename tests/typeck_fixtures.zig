const std = @import("std");
const veyl = @import("veyl");

test "typeck diagnostic: if condition must be Bool" {
    const source = @embedFile("fixtures/typeck/non_bool_condition.veyl");
    const expected = @embedFile("fixtures/typeck/non_bool_condition.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("non_bool_condition.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: arithmetic operands must be numeric" {
    const source = @embedFile("fixtures/typeck/non_numeric_arithmetic.veyl");
    const expected = @embedFile("fixtures/typeck/non_numeric_arithmetic.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("non_numeric_arithmetic.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: local condition must be Bool" {
    const source = @embedFile("fixtures/typeck/local_non_bool_condition.veyl");
    const expected = @embedFile("fixtures/typeck/local_non_bool_condition.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("local_non_bool_condition.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: function return type mismatch" {
    const source = @embedFile("fixtures/typeck/return_type_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/return_type_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("return_type_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: parameter condition must be Bool" {
    const source = @embedFile("fixtures/typeck/parameter_non_bool_condition.veyl");
    const expected = @embedFile("fixtures/typeck/parameter_non_bool_condition.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("parameter_non_bool_condition.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: function argument type mismatch" {
    const source = @embedFile("fixtures/typeck/function_argument_type_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/function_argument_type_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("function_argument_type_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: function argument count mismatch" {
    const source = @embedFile("fixtures/typeck/function_argument_count_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/function_argument_count_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("function_argument_count_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: return statement type mismatch" {
    const source = @embedFile("fixtures/typeck/return_statement_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/return_statement_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("return_statement_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: assignment type mismatch" {
    const source = @embedFile("fixtures/typeck/assignment_type_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/assignment_type_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("assignment_type_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: if branch type mismatch" {
    const source = @embedFile("fixtures/typeck/if_branch_type_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/if_branch_type_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("if_branch_type_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: array index must be Int" {
    const source = @embedFile("fixtures/typeck/array_index_non_int.veyl");
    const expected = @embedFile("fixtures/typeck/array_index_non_int.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("array_index_non_int.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: array elements must match" {
    const source = @embedFile("fixtures/typeck/array_element_type_mismatch.veyl");
    const expected = @embedFile("fixtures/typeck/array_element_type_mismatch.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("array_element_type_mismatch.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "typeck diagnostic: immutable assignment" {
    const source = @embedFile("fixtures/typeck/immutable_assignment.veyl");
    const expected = @embedFile("fixtures/typeck/immutable_assignment.diag");

    var sources = veyl.base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("immutable_assignment.veyl", source);

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

    try veyl.typeck.checkModule(std.testing.allocator, &hir, &interner, &diagnostics);
    try std.testing.expect(diagnostics.hasErrors());

    const rendered = try diagnostics.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}
