const std = @import("std");
const veyl = @import("veyl");

test "formatter golden: imports" {
    const source = @embedFile("fixtures/fmt/imports.input.veyl");
    const expected = @embedFile("fixtures/fmt/imports.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}

test "formatter golden: type aliases" {
    const source = @embedFile("fixtures/fmt/type_aliases.input.veyl");
    const expected = @embedFile("fixtures/fmt/type_aliases.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}

test "formatter golden: data declarations" {
    const source = @embedFile("fixtures/fmt/data_decls.input.veyl");
    const expected = @embedFile("fixtures/fmt/data_decls.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}

test "formatter golden: functions" {
    const source = @embedFile("fixtures/fmt/functions.input.veyl");
    const expected = @embedFile("fixtures/fmt/functions.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}

test "formatter golden: let and return" {
    const source = @embedFile("fixtures/fmt/let_return.input.veyl");
    const expected = @embedFile("fixtures/fmt/let_return.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}

test "formatter golden: aggregate expressions" {
    const source = @embedFile("fixtures/fmt/aggregate_exprs.input.veyl");
    const expected = @embedFile("fixtures/fmt/aggregate_exprs.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}

test "formatter golden: control flow" {
    const source = @embedFile("fixtures/fmt/control_flow.input.veyl");
    const expected = @embedFile("fixtures/fmt/control_flow.expected.veyl");

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

    const formatted = try veyl.fmt.formatAst(std.testing.allocator, &tree, &interner, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);

    var second_diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer second_diagnostics.deinit();
    var second_tokens = try veyl.lexer.lex(std.testing.allocator, 0, formatted, &second_diagnostics);
    defer second_tokens.deinit();
    var second_interner = veyl.base.Interner.init(std.testing.allocator);
    defer second_interner.deinit();
    var second_tree = try veyl.parser.parse(std.testing.allocator, 0, formatted, second_tokens.tokens.items, &second_interner, &second_diagnostics);
    defer second_tree.deinit();
    try std.testing.expect(!second_diagnostics.hasErrors());

    const formatted_again = try veyl.fmt.formatAst(std.testing.allocator, &second_tree, &second_interner, formatted);
    defer std.testing.allocator.free(formatted_again);
    try std.testing.expectEqualStrings(expected, formatted_again);
}
