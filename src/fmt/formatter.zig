const std = @import("std");
const ast_mod = @import("../parser/ast.zig");
const base = @import("../base.zig");

const Allocator = std.mem.Allocator;
const FormatError = Allocator.Error || std.Io.Writer.Error;

pub fn formatAst(allocator: Allocator, ast: *const ast_mod.Ast, interner: *const base.Interner) FormatError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    for (ast.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try formatImport(&output.writer, ast, interner, import_decl),
            .type_alias => |type_alias| try formatTypeAlias(&output.writer, ast, interner, type_alias),
            .fn_decl => |fn_decl| try formatFn(&output.writer, ast, interner, fn_decl),
            .struct_decl => |struct_decl| try formatStruct(&output.writer, ast, interner, struct_decl),
            .enum_decl => |enum_decl| try formatEnum(&output.writer, ast, interner, enum_decl),
            else => {},
        }
    }

    return output.toOwnedSlice();
}

fn formatFn(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    fn_decl: ast_mod.FnDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, fn_decl.visibility);
    try writer.writeAll("fn ");
    try writer.writeAll(interner.get(fn_decl.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, fn_decl.generic_params);
    try writeFnParams(writer, ast, interner, fn_decl.params);
    if (fn_decl.return_type) |return_type| {
        try writer.writeAll(" -> ");
        try writeTypeExpr(writer, ast, interner, return_type);
    }
    try writer.writeByte(' ');
    try writeBlock(writer, ast, interner, ast.blocks.items[fn_decl.body], 0);
}

fn writeFnParams(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    params: base.Range,
) std.Io.Writer.Error!void {
    try writer.writeByte('(');
    const start: usize = @intCast(params.start);
    const end: usize = @intCast(params.end());
    for (ast.fn_params.items[start..end], 0..) |param, index| {
        if (index != 0) try writer.writeAll(", ");
        if (param.is_mut) try writer.writeAll("mut ");
        try writer.writeAll(interner.get(param.name) orelse "<missing>");
        try writer.writeAll(": ");
        try writeTypeExpr(writer, ast, interner, param.type_expr);
        if (param.default_value) |default_value| {
            try writer.writeAll(" = ");
            try writeExpr(writer, ast, interner, default_value);
        }
    }
    try writer.writeByte(')');
}

fn writeBlock(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    block: ast_mod.Block,
    indent: usize,
) std.Io.Writer.Error!void {
    try writer.writeAll("{\n");
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (ast.block_stmt_ids.items[start..end]) |stmt_id| {
        try writeIndent(writer, indent + 1);
        try writeStmt(writer, ast, interner, ast.stmts.items[stmt_id], indent + 1);
    }
    if (block.final_expr) |final_expr| {
        try writeIndent(writer, indent + 1);
        try writeExpr(writer, ast, interner, final_expr);
        try writer.writeByte('\n');
    }
    try writeIndent(writer, indent);
    try writer.writeAll("}\n");
}

fn writeStmt(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    stmt: ast_mod.Stmt,
    indent: usize,
) std.Io.Writer.Error!void {
    switch (stmt) {
        .expr_stmt => |expr| {
            try writeExpr(writer, ast, interner, expr);
            try writer.writeAll(";\n");
        },
        .return_stmt => |return_stmt| {
            try writer.writeAll("return");
            if (return_stmt.value) |value| {
                try writer.writeByte(' ');
                try writeExpr(writer, ast, interner, value);
            }
            try writer.writeAll(";\n");
        },
        .break_stmt => try writer.writeAll("break;\n"),
        .continue_stmt => try writer.writeAll("continue;\n"),
        else => {
            _ = indent;
            try writer.writeAll("<stmt>;\n");
        },
    }
}

fn writeExpr(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    expr_id: ast_mod.ExprId,
) std.Io.Writer.Error!void {
    switch (ast.exprs.items[expr_id]) {
        .name => |name| try writer.writeAll(interner.get(name.symbol) orelse "<missing>"),
        .unit_literal => try writer.writeAll("()"),
        .field => |field| {
            try writeExpr(writer, ast, interner, field.base);
            try writer.writeByte('.');
            try writer.writeAll(interner.get(field.name) orelse "<missing>");
        },
        .call => |call| {
            try writeExpr(writer, ast, interner, call.callee);
            if (call.type_args.len != 0) {
                try writer.writeByte('<');
                const type_start: usize = @intCast(call.type_args.start);
                const type_end: usize = @intCast(call.type_args.end());
                for (ast.type_args.items[type_start..type_end], 0..) |type_arg, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writeTypeExpr(writer, ast, interner, type_arg);
                }
                try writer.writeByte('>');
            }
            try writer.writeByte('(');
            const arg_start: usize = @intCast(call.args.start);
            const arg_end: usize = @intCast(call.args.end());
            for (ast.call_args.items[arg_start..arg_end], 0..) |arg, index| {
                if (index != 0) try writer.writeAll(", ");
                if (arg.name) |name| {
                    try writer.writeAll(interner.get(name) orelse "<missing>");
                    try writer.writeAll(": ");
                }
                try writeExpr(writer, ast, interner, arg.value);
            }
            try writer.writeByte(')');
        },
        .binary => |binary| {
            try writeExpr(writer, ast, interner, binary.left);
            try writer.print(" {s} ", .{binaryOpText(binary.op)});
            try writeExpr(writer, ast, interner, binary.right);
        },
        else => try writer.writeAll("<expr>"),
    }
}

fn binaryOpText(op: ast_mod.BinaryOp) []const u8 {
    return switch (op) {
        .assign => "=",
        .add_assign => "+=",
        .sub_assign => "-=",
        .mul_assign => "*=",
        .div_assign => "/=",
        .rem_assign => "%=",
        .logical_or => "||",
        .logical_and => "&&",
        .equal => "==",
        .not_equal => "!=",
        .less => "<",
        .less_equal => "<=",
        .greater => ">",
        .greater_equal => ">=",
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .rem => "%",
    };
}

fn writeIndent(writer: *std.Io.Writer, indent: usize) std.Io.Writer.Error!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("    ");
    }
}

fn formatStruct(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    struct_decl: ast_mod.StructDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, struct_decl.visibility);
    try writer.writeAll("struct ");
    try writer.writeAll(interner.get(struct_decl.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, struct_decl.generic_params);
    try writer.writeAll(" {\n");

    const start: usize = @intCast(struct_decl.fields.start);
    const end: usize = @intCast(struct_decl.fields.end());
    for (ast.struct_fields.items[start..end]) |field| {
        try writer.writeAll("    ");
        if (field.visibility == .private) try writer.writeAll("private ");
        try writer.writeAll(interner.get(field.name) orelse "<missing>");
        try writer.writeAll(": ");
        try writeTypeExpr(writer, ast, interner, field.type_expr);
        try writer.writeAll(",\n");
    }

    try writer.writeAll("}\n");
}

fn formatEnum(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    enum_decl: ast_mod.EnumDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, enum_decl.visibility);
    try writer.writeAll("enum ");
    try writer.writeAll(interner.get(enum_decl.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, enum_decl.generic_params);
    try writer.writeAll(" {\n");

    const start: usize = @intCast(enum_decl.variants.start);
    const end: usize = @intCast(enum_decl.variants.end());
    for (ast.enum_variants.items[start..end]) |variant| {
        try writer.writeAll("    ");
        try writer.writeAll(interner.get(variant.name) orelse "<missing>");
        switch (variant.kind) {
            .unit => {},
            .tuple => {
                try writer.writeByte('(');
                try writeEnumFields(writer, ast, interner, variant.fields, false);
                try writer.writeByte(')');
            },
            .record => {
                try writer.writeAll(" { ");
                try writeEnumFields(writer, ast, interner, variant.fields, true);
                try writer.writeAll(" }");
            },
        }
        try writer.writeAll(",\n");
    }

    try writer.writeAll("}\n");
}

fn writeEnumFields(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    fields: base.Range,
    include_names: bool,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(fields.start);
    const end: usize = @intCast(fields.end());
    for (ast.enum_fields.items[start..end], 0..) |field, index| {
        if (index != 0) try writer.writeAll(", ");
        if (include_names) {
            if (field.name) |name| {
                try writer.writeAll(interner.get(name) orelse "<missing>");
                try writer.writeAll(": ");
            }
        }
        try writeTypeExpr(writer, ast, interner, field.type_expr);
    }
}

fn formatTypeAlias(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    type_alias: ast_mod.TypeAliasDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, type_alias.visibility);
    try writer.writeAll("type ");
    try writer.writeAll(interner.get(type_alias.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, type_alias.generic_params);
    try writer.writeAll(" = ");
    try writeTypeExpr(writer, ast, interner, type_alias.aliased_type);
    try writer.writeAll(";\n");
}

fn formatImport(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    import_decl: ast_mod.ImportDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, import_decl.visibility);
    try writer.writeAll("import ");
    try writePath(writer, ast, interner, import_decl.path);
    if (import_decl.items.len != 0) {
        try writer.writeAll(".{");
        const start: usize = @intCast(import_decl.items.start);
        const end: usize = @intCast(import_decl.items.end());
        for (ast.import_items.items[start..end], 0..) |item, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(interner.get(item.name) orelse "<missing>");
            if (item.alias) |alias| {
                try writer.writeAll(" as ");
                try writer.writeAll(interner.get(alias) orelse "<missing>");
            }
        }
        try writer.writeByte('}');
    }
    if (import_decl.alias) |alias| {
        try writer.writeAll(" as ");
        try writer.writeAll(interner.get(alias) orelse "<missing>");
    }
    try writer.writeByte('\n');
}

fn writeVisibility(writer: *std.Io.Writer, visibility: ast_mod.Visibility) std.Io.Writer.Error!void {
    switch (visibility) {
        .public => try writer.writeAll("pub "),
        .private => try writer.writeAll("private "),
        .package => {},
    }
}

fn writeGenericParams(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    params: base.Range,
) std.Io.Writer.Error!void {
    if (params.len == 0) return;
    try writer.writeByte('<');
    const start: usize = @intCast(params.start);
    const end: usize = @intCast(params.end());
    for (ast.generic_params.items[start..end], 0..) |param, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(interner.get(param.name) orelse "<missing>");
        if (param.constraint) |constraint| {
            try writer.writeAll(": ");
            try writeTypeExpr(writer, ast, interner, constraint);
        }
    }
    try writer.writeByte('>');
}

fn writeTypeExpr(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    type_id: ast_mod.TypeId,
) std.Io.Writer.Error!void {
    switch (ast.types.items[type_id]) {
        .unit => try writer.writeAll("()"),
        .path => |path_type| {
            try writePath(writer, ast, interner, path_type.segments);
            if (path_type.args.len != 0) {
                try writer.writeByte('<');
                const start: usize = @intCast(path_type.args.start);
                const end: usize = @intCast(path_type.args.end());
                for (ast.type_args.items[start..end], 0..) |arg, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writeTypeExpr(writer, ast, interner, arg);
                }
                try writer.writeByte('>');
            }
        },
    }
}

fn writePath(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    path: base.Range,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(path.start);
    const end: usize = @intCast(path.end());
    for (ast.path_segments.items[start..end], 0..) |segment, index| {
        if (index != 0) try writer.writeByte('.');
        try writer.writeAll(interner.get(segment.name) orelse "<missing>");
    }
}

test "formatter formats imports" {
    const veyl = @import("../root.zig");
    const source =
        \\pub import http.router.{Route, Router as HttpRouter}
        \\import std.json as json
        \\
    ;

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();
    var tokens = try veyl.lexer.lex(std.testing.allocator, 0, source, &diagnostics);
    defer tokens.deinit();
    var interner = veyl.base.Interner.init(std.testing.allocator);
    defer interner.deinit();
    var tree = try veyl.parser.parse(std.testing.allocator, 0, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();

    const formatted = try formatAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(source, formatted);
}
